extends RefCounted
## Landing actions. hero_landing: the slam after a long fall, a deep three-point crouch held for a
## beat, then a smooth rise into the idle stand. The game plays it on touchdown and may end it
## early with stop_action (movement after a short lock).

const L := preload("res://rig/clips/landing_tuning.gd")
const B := preload("res://rig/rig_bone.gd")


static func create(rig: RigData) -> Dictionary:
	return {&"hero_landing": HeroLanding.new(rig)}


class HeroLanding extends RigAction:
	const LEG_BONES: Array[int] = [B.HIP, B.WAIST, B.THIGH_B, B.KNEE_B, B.SHIN_B, B.FOOT_B, B.THIGH_F, B.KNEE_F, B.SHIN_F, B.FOOT_F]
	var world := PackedFloat32Array()
	var stand: RigPose
	var _keep := PackedFloat32Array()

	func _init(rig_data: RigData) -> void:
		super(rig_data)
		id = &"hero_landing"
		requires = "ground"
		var H: Dictionary = L.T.hero
		var J: Dictionary = H.juice
		duration = H.duration
		world = RigMath.create_world(rig)
		stand = RigPose.new(rig)
		_keep.resize(rig.bone_count * 3)
		var open_x: float = rig.rest_ankle_x(H.openLeg) + H.openAnkle[0] + RigData.FOOT_TOE
		var fold_x: float = rig.rest_ankle_x(H.foldLeg) + H.foldAnkle[0]
		var hand_x: float = H.plantHand[0]
		events = [
			{"t": 0.0, "fx": "dust", "x": fold_x, "y": 0.0, "params": J.dust},
			{"t": 0.0, "fx": "dust", "x": open_x, "y": 0.0, "params": J.dust.merged({"count": 7})},
			{"t": 0.0, "fx": "dust", "x": hand_x, "y": 0.0, "params": J.handDust},
			{"t": 0.0, "fx": "skidCloud", "x": 0.0, "y": 0.0, "params": J.cloud.merged({"dir": 1})},
			{"t": 0.0, "fx": "skidCloud", "x": 0.0, "y": 0.0, "params": J.cloud.merged({"dir": -1})},
			{"t": 0.0, "fx": "burst", "x": 20.0, "y": -6.0, "params": J.debris},
		]

	func begin(host) -> void:
		start_facing = host.facing

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var H: Dictionary = L.T.hero
		var settle := RigMath.smooth01(t / H.settle)
		var dip: float = H.overshoot * (1.0 - settle)
		var breath: float = H.breath * sin(TAU * H.breathHz * t) * settle if juice else 0.0
		var look := RigMath.smooth01((t - H.settle) / (H.holdEnd - H.settle))
		var rise := RigMath.smooth01((t - H.holdEnd) / (duration - H.holdEnd))
		# Rising: the crouch itself opens up (feet stay on the ground through the IK), while the
		# arms, head and scarf ease into the stand.
		_crouch(pose, t, (dip + breath) * (1.0 - rise), look, juice, 1.0 - rise)
		if juice:
			var J: Dictionary = H.juice
			var k := 1.0 - RigMath.smooth01(t / J.squashTime)
			pose.root_sy = 1.0 - J.squash * k
			pose.root_sx = 1.0 + J.squash * 0.6 * k
		if rise > 0.0:
			RigLocomotion.sample_idle(rig, stand, 0.0, juice)
			# Only the upper body blends: the legs and hip stay on the IK, so the feet never dip.
			for i in LEG_BONES:
				_keep[i * 3] = pose.rot[i]
				_keep[i * 3 + 1] = pose.x[i]
				_keep[i * 3 + 2] = pose.y[i]
			pose.blend_toward(stand, rise * rise)
			for i in LEG_BONES:
				pose.rot[i] = _keep[i * 3]
				pose.x[i] = _keep[i * 3 + 1]
				pose.y[i] = _keep[i * 3 + 2]
		pose.facing = start_facing

	## c: 1 the full crouch, 0 the standing parameters (hip, lean, feet).
	func _crouch(pose: RigPose, t: float, dip: float, look: float, juice: bool, c: float) -> void:
		var H: Dictionary = L.T.hero
		RigLocomotion.sample_idle(rig, pose, 0.0, false)
		pose.facing = 1
		pose.x[B.HIP] = H.hipX * c
		pose.y[B.HIP] = lerpf(pose.y[B.HIP], H.hipY, c) + dip
		var lean := deg_to_rad(H.lean) * c
		pose.rot[B.TORSO] = lean
		# Head down at the slam, lifting to look ahead during the hold.
		pose.rot[B.NECK] = deg_to_rad(lerpf(H.headDown, H.headUp, look) * c) - lean
		var S: Dictionary = H.scarf
		var wave: float = S.wave * sin(TAU * S.waveHz * t) if juice else 0.0
		pose.rot[B.SCARF1] = deg_to_rad(S.link1 + wave)
		pose.rot[B.SCARF2] = deg_to_rad(S.link2 - wave * 1.3)
		var fold: String = H.foldLeg
		var open: String = H.openLeg
		RigMath.solve_leg(rig, pose, fold, rig.rest_ankle_x(fold) + H.foldAnkle[0] * c, -RigData.FOOT_ANKLE_HEIGHT + H.foldAnkle[1] * c, 0.0)
		var foot := deg_to_rad(H.openFoot) * c
		var ankle := RigMath.planted_ankle(rig.rest_ankle_x(open) + H.openAnkle[0] * c, H.openAnkle[1] * c, foot)
		RigMath.solve_leg(rig, pose, open, ankle.x, ankle.y, foot)
		RigMath.derive_bones(rig, pose, H.waistFollow)
		var free_upper: int = B.UPPER_ARM_B if H.plantArm == "front" else B.UPPER_ARM_F
		pose.rot[free_upper] = deg_to_rad(H.freeArm.upper) - lean
		pose.rot[free_upper + 1] = deg_to_rad(H.freeArm.fore)
		var plant_upper: int = B.UPPER_ARM_F if H.plantArm == "front" else B.UPPER_ARM_B
		pose.x[plant_upper] = H.plantShoulder[0] * c
		pose.y[plant_upper] = H.plantShoulder[1] * c
		RigMath.solve_arm(rig, pose, H.plantArm, H.plantHand[0], H.plantHand[1], world, true, 1.0)
		RigMath.derive_bones(rig, pose, H.waistFollow)
