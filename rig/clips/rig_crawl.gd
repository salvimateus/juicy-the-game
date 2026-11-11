class_name RigCrawl
extends RefCounted
## Crouch idle and the crawl gait (port of the JS crawl clip). Knees and hands plant in diagonal
## pairs; the hip height follows the planted knee, the hands reach their contacts with arm IK. The
## phase is one gait cycle and advances by distance (cycle_length per cycle), so contacts stay put.

const C := preload("res://rig/clips/crawl_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const SIDES := ["front", "back"]

var rig: RigData
var world := PackedFloat32Array()
var contact_pose: RigPose
var contact_world := PackedFloat32Array()
var part_px := {}  # side -> {"knee": [bones, xy], "shin": ..., "foot": ...}
var foot_rel := {"back": 0.0, "front": 0.0}
var knee_y := {"back": 0.0, "front": 0.0}
var shin_dir := {"back": 0.0, "front": 0.0}
var half := 0.0
var hand_stride := 0.0
const KNEE_OFFSET := {"back": 0.0, "front": 0.5}


func _init(rig_data: RigData) -> void:
	rig = rig_data
	world = RigMath.create_world(rig)
	contact_world = RigMath.create_world(rig)
	contact_pose = RigPose.new(rig)
	var K: Dictionary = C.T.knee
	half = K.stride * 0.5
	hand_stride = 2.0 * K.stride * C.T.hand.duty
	part_px = {
		"back": {"knee": _pixels(["kneeB", "thighB"]), "shin": _pixels(["shaftB"]), "foot": _pixels(["footB"])},
		"front": {"knee": _pixels(["kneeF", "thighF"]), "shin": _pixels(["shaftF"]), "foot": _pixels(["footF"])},
	}
	foot_rel.back = deg_to_rad(K.footRelMax)
	foot_rel.front = deg_to_rad(K.footRelMax)
	knee_y.back = K.height
	knee_y.front = K.height
	for round in 4:
		shin_dir.back = _solve_shin("back", knee_y.back)
		knee_y.back -= _lowest("back", knee_y.back, shin_dir.back, "knee", foot_rel.back)
	var lb: RigData.Leg = rig.legs.back
	var lf: RigData.Leg = rig.legs.front
	knee_y.front = knee_y.back - sqrt(lb.upper * lb.upper - half * half) + sqrt(lf.upper * lf.upper - half * half)
	shin_dir.front = _solve_shin("front", knee_y.front)


## Ground distance per crawl cycle.
func cycle_length() -> float:
	return 2.0 * C.T.knee.stride


func _hand_offset(side: String) -> float:
	return C.T.hand.lead + (0.0 if side == "front" else 0.5)


func knee_phase(side: String, p: float) -> float:
	return RigMath.frac(p + KNEE_OFFSET[side])


func hand_phase(side: String, p: float) -> float:
	return RigMath.frac(p + _hand_offset(side))


## Contact x (character space, facing right, centered) of a knee or hand plant.
func knee_contact_x(side: String) -> float:
	var leg: RigData.Leg = rig.legs[side]
	return rig.bone_x[B.HIP] + leg.hip_x + C.T.hipSpread[side] + half + C.T.centerShift


func hand_contact_x(side: String) -> float:
	return (C.T.hand.reachXFront if side == "front" else C.T.hand.reachXBack) + hand_stride * 0.5 + C.T.centerShift


# Opaque pixels of the named parts as bone-local points (bottom edges can touch the ground).
func _pixels(names: Array) -> Array:
	var bones := PackedInt32Array()
	var xy := PackedFloat32Array()
	for part in rig.parts:
		if not names.has(part.name):
			continue
		var img: Image = rig.images.get(part.image)
		if img == null:
			continue
		var crop := img.get_region(part.src)
		for y in crop.get_height():
			for x in crop.get_width():
				if crop.get_pixel(x, y).a == 0.0:
					continue
				bones.append(part.bone)
				xy.append(x + part.src.position.x - part.pivot.x + 0.5)
				xy.append(y + part.src.position.y - part.pivot.y + 1.0)
	return [bones, xy]


func _lowest(side: String, knee_joint_y: float, psi: float, set_name: String, rel: float) -> float:
	var leg: RigData.Leg = rig.legs[side]
	contact_pose.reset()
	contact_pose.y[B.HIP] = knee_joint_y - leg.upper - leg.hip_y - rig.bone_y[B.HIP]
	var thigh_rot := -leg.upper_angle
	contact_pose.rot[leg.thigh] = thigh_rot
	contact_pose.rot[leg.shin] = psi - leg.lower_angle - thigh_rot
	contact_pose.rot[leg.foot] = rel
	contact_pose.rot[leg.cap] = contact_pose.rot[leg.shin] * 0.5
	RigMath.compute_world(rig, contact_pose, contact_world)
	var set: Array = part_px[side][set_name]
	var bones: PackedInt32Array = set[0]
	var xy: PackedFloat32Array = set[1]
	var max_y := -INF
	for i in bones.size():
		var o := bones[i] * 6
		var wy := contact_world[o + 1] * xy[i * 2] + contact_world[o + 3] * xy[i * 2 + 1] + contact_world[o + 5]
		if wy > max_y:
			max_y = wy
	return max_y


func _solve_shin(side: String, knee_joint_y: float) -> float:
	var lo := deg_to_rad(40.0)
	var hi := deg_to_rad(175.0)
	for i in 30:
		var mid := (lo + hi) * 0.5
		if _lowest(side, knee_joint_y, mid, "shin", foot_rel[side]) > 0.0:
			lo = mid
		else:
			hi = mid
	var psi := (lo + hi) * 0.5
	lo = deg_to_rad(C.T.knee.footRelMin)
	hi = deg_to_rad(C.T.knee.footRelMax)
	for i in 30:
		var mid := (lo + hi) * 0.5
		if _lowest(side, knee_joint_y, psi, "foot", mid) > 0.0:
			lo = mid
		else:
			hi = mid
	foot_rel[side] = (lo + hi) * 0.5
	return psi


static func _bump(w: float) -> float:
	return sin(PI * clampf(w, 0.0, 1.0))


func _knee_target(side: String, p: float) -> Vector3:
	var K: Dictionary = C.T.knee
	if p < 0.5:
		return Vector3(half - K.stride * (p / 0.5), knee_y[side], -1.0)
	var w := (p - 0.5) / 0.5
	return Vector3(lerpf(-half, half, RigMath.smooth01(w)), knee_y[side] - K.lift * _bump(w), w)


func _hip_height(p: float, sway_x: float) -> float:
	for side in SIDES:
		var kp := knee_phase(side, p)
		if kp >= 0.5:
			continue
		var kt := _knee_target(side, kp)
		var dx := kt.x - sway_x
		var leg: RigData.Leg = rig.legs[side]
		return kt.y - sqrt(leg.upper * leg.upper - dx * dx) - leg.hip_y
	return 0.0


func _hand_target(side: String, p: float) -> Vector2:
	var H: Dictionary = C.T.hand
	var base_x: float = H.reachXFront if side == "front" else H.reachXBack
	var gy: float = H.groundYFront if side == "front" else H.groundYBack
	var hs := hand_stride * 0.5
	if p < H.duty:
		return Vector2(base_x + hs - hand_stride * (p / H.duty), gy)
	var w: float = (p - H.duty) / (1.0 - H.duty)
	return Vector2(lerpf(base_x - hs, base_x + hs, RigMath.smooth01(w)), gy - H.lift * _bump(w))


## Crawl pose at cycle phase p, authored facing right and centered by centerShift.
func sample_crawl(pose: RigPose, p: float, juice: bool, facing: int) -> void:
	var T: Dictionary = C.T
	pose.reset()
	var sway_x: float = T.hipSway * sin(TAU * 2.0 * p)
	var hip_y := _hip_height(p, sway_x)
	pose.x[B.HIP] = sway_x
	pose.y[B.HIP] = hip_y - rig.bone_y[B.HIP]
	var wave2 := sin(TAU * 2.0 * (p - T.torsoWavePhase))
	var theta := deg_to_rad(T.torsoAngle + T.torsoWave * wave2)
	pose.rot[B.TORSO] = theta
	var head_bob: float = T.headBob * sin(TAU * 2.0 * (p - T.torsoWavePhase - T.headLag))
	pose.x[B.NECK] = T.neckShift[0]
	pose.y[B.NECK] = T.neckShift[1]
	pose.rot[B.NECK] = deg_to_rad(T.headAngle + head_bob) - theta
	var sc: Dictionary = T.scarf
	var sw: float = sc.wave * sin(TAU * 2.0 * (p - sc.phase))
	pose.rot[B.SCARF_WRAP] = deg_to_rad(sc.wrap) - theta
	pose.rot[B.SCARF1] = deg_to_rad(sc.link1 - sc.wrap + sw)
	pose.rot[B.SCARF2] = deg_to_rad(sc.link2 - sc.link1 + sw * 1.3)
	for side in SIDES:
		_pose_leg(pose, side, p, sway_x, hip_y)
	if juice:
		var J: Dictionary = T.juice
		var cycle_t := 1.0
		var k := 0.0
		for side in SIDES:
			var age := hand_phase(side, p) * cycle_t
			if age < J.squash.seconds:
				k = maxf(k, _bump(age / J.squash.seconds))
		RigMath.squash(pose, B.NECK, J.squash.head * k)
		pose.rot[B.TORSO] += deg_to_rad(J.squash.dip * k)
		pose.rot[B.NECK] -= deg_to_rad(J.squash.dip * k)
		var lag := sin(TAU * 2.0 * (p - T.torsoWavePhase - 0.18))
		pose.rot[B.NECK] += deg_to_rad(J.follow.head * lag)
		pose.rot[B.SCARF1] += deg_to_rad(J.follow.scarf * lag)
		pose.rot[B.SCARF2] += deg_to_rad(J.follow.scarf * 1.4 * sin(TAU * 2.0 * (p - T.torsoWavePhase - 0.3)))
	for side in SIDES:
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		pose.x[upper] = T.shoulderShift[side][0]
		pose.y[upper] = T.shoulderShift[side][1]
	pose.sx[B.WAIST] = T.beltScale
	RigMath.derive_bones(rig, pose, T.waistFollow)
	var H: Dictionary = T.hand
	for side in SIDES:
		var hp := hand_phase(side, p)
		var h := _hand_target(side, hp)
		var swing := 0.0 if hp < H.duty else _bump((hp - H.duty) / (1.0 - H.duty))
		var angle := deg_to_rad(H.angle + H.swingTilt * swing)
		var fist := rig.anchor("fistF" if side == "front" else "fistB")
		var wx := h.x - (fist.y * cos(angle) - fist.z * sin(angle))
		var wy := h.y - (fist.y * sin(angle) + fist.z * cos(angle))
		RigMath.solve_arm(rig, pose, side, wx, wy, world, false, 1.0)
		RigMath.compute_world(rig, pose, world)
		var fore: int = B.FORE_ARM_F if side == "front" else B.FORE_ARM_B
		pose.rot[fore + 1] = angle - RigMath.bone_angle(world, fore)
	RigMath.derive_bones(rig, pose, T.waistFollow)
	pose.root_x = T.centerShift * facing
	pose.facing = facing


func _pose_leg(pose: RigPose, side: String, p: float, sway_x: float, hip_y: float) -> void:
	var leg: RigData.Leg = rig.legs[side]
	var K: Dictionary = C.T.knee
	var kt := _knee_target(side, knee_phase(side, p))
	var joint_x := rig.bone_x[B.HIP] + sway_x + leg.hip_x
	var joint_y := hip_y + leg.hip_y
	var dx := kt.x + rig.bone_x[B.HIP] + leg.hip_x - joint_x
	var dy := kt.y - joint_y
	var dist := sqrt(dx * dx + dy * dy)
	var thigh_rot := atan2(-dx, dy) - leg.upper_angle
	pose.sy[leg.thigh] = minf(1.0, dist / leg.upper)
	var psi: float = shin_dir[side]
	if kt.z >= 0.0:
		psi += deg_to_rad(K.shinLift) * _bump(kt.z)
	pose.rot[leg.thigh] = thigh_rot
	pose.x[leg.thigh] = C.T.hipSpread[side]
	pose.rot[leg.shin] = psi - leg.lower_angle - thigh_rot
	pose.rot[leg.foot] = foot_rel[side]


## Crouch idle: deep squat, torso forward, hands near the knees, breathing.
func sample_crouch(pose: RigPose, time: float, juice: bool, facing: int) -> void:
	var c: Dictionary = C.T.crouch
	RigLocomotion.sample_idle(rig, pose, 0.0, false)
	var breath := 0.5 - 0.5 * cos(TAU * c.breathHz * time)
	pose.y[B.HIP] = c.hipY + (c.breath * breath if juice else 0.0)
	pose.x[B.HIP] = c.hipX
	var lean := deg_to_rad(c.lean - (1.2 * breath if juice else 0.0))
	pose.rot[B.TORSO] = lean
	# Head in line with the back, like the crawl, looking ahead and down.
	pose.x[B.NECK] = C.T.neckShift[0]
	pose.y[B.NECK] = C.T.neckShift[1]
	pose.rot[B.NECK] = deg_to_rad(c.headAngle) - lean
	pose.y[B.TORSO] = -c.breath * 0.5 * breath if juice else 0.0
	pose.rot[B.SCARF_WRAP] = deg_to_rad(C.T.scarf.wrap) - lean
	pose.rot[B.SCARF1] = deg_to_rad(c.scarf1)
	pose.rot[B.SCARF2] = deg_to_rad(c.scarf2)
	pose.sx[B.WAIST] = C.T.beltScale
	for side in SIDES:
		var s := -1.0 if side == "front" else 1.0
		RigMath.solve_leg(rig, pose, side, rig.rest_ankle_x(side) + s * c.feetSpread, -RigData.FOOT_ANKLE_HEIGHT, 0.0)
	RigMath.derive_bones(rig, pose, C.T.waistFollow)
	for side in SIDES:
		var h: Array = c.handF if side == "front" else c.handB
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		pose.x[upper] = C.T.shoulderShift[side][0]
		pose.y[upper] = C.T.shoulderShift[side][1]
		RigMath.solve_arm(rig, pose, side, h[0], h[1], world, true, 1.0)
	RigMath.derive_bones(rig, pose, C.T.waistFollow)
	pose.facing = facing
