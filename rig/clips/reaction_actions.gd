extends RefCounted
## Hit reactions, ported from the JS hit and shot clips. Both play anywhere (the host lets them
## interrupt any other action) and read Adventurer.action_params[&"hit_direction"] (the world
## direction the blow or the bullet travels) in begin: against the facing is a hit from the front
## (the JS case), along the facing a hit from behind (mirrored channels).
##
## hurt: dry impact, knockback slide, two recovery steps; root motion away from the hit.
## shot_hit: blood burst, stagger, drops to one knee pressing the wound, gets up and squares the
## feet where it stands (the JS walk home is dropped); root motion keeps the stagger distance.
## In the air both play an upper-body version over the air pose, end on landing and have no root
## motion (the game owns the air knockback).
##
## Signals (action_event): &"impact" and &"iframes_start" at t = 0 (shot_hit also
## &"bullet_hit_body"); shot_hit &"down" (knee on the ground) and &"rise" (starts getting up);
## &"recovered" with &"iframes_end" once standing on both feet (the game may stop_action() from
## there to give control back early). Footsteps on every recovery step.

const X := preload("res://rig/clips/reaction_tuning.gd")
const C := preload("res://rig/clips/reaction_common.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7


static func create(rig: RigData) -> Dictionary:
	return {
		&"hurt": Hurt.new(rig, &"hurt", Vector2.LEFT),
		&"shot_hit": ShotHit.new(rig, &"shot_hit", Vector2.LEFT),
		# Pose sheet helpers (the same actions with a hit from behind when facing right).
		&"hurt_behind_sheet": Hurt.new(rig, &"hurt_behind_sheet", Vector2.RIGHT),
		&"shot_hit_behind_sheet": ShotHit.new(rig, &"shot_hit_behind_sheet", Vector2.RIGHT),
	}


class Hurt extends RigAction:
	var H: Dictionary
	var D := 1.2
	var tracks := {}
	var sheet_dir := Vector2.LEFT
	## 1 from the front, -1 from behind (set in begin).
	var side := 1.0
	var air := false
	var air_vy := 0.0
	var hitstop := 0.0
	var impact_s := 0.0

	func _init(rig_data: RigData, action_id: StringName, dir: Vector2) -> void:
		super(rig_data)
		id = action_id
		sheet_dir = dir
		H = X.T.hurt
		D = H.anim_seconds
		var ie: float = H.impactEnd
		var he: float = H.holdEnd
		var re: float = H.recoverEnd
		tracks = RigTrack.compile({
			"impact": [[0.0, 0.0], [ie, 1.0, "out"], [he, 0.9, "linear"], [re, 0.0, "back"]],
			"lag": [[0.0, 0.0], [ie * 2.0, 0.6, "out"], [he + 0.04, 1.0, "out"], [re + 0.06, 0.0, "back"]],
			"hip": [[0.0, 0.0], [ie, 1.0, "out"], [he, 0.9, "linear"], [re, 0.0, "inOut"]],
			"slide": [[0.0, 0.0], [he, 1.0, "out"]],
			"squash": [[0.0, 0.0], [ie, 1.0, "out"], [he, 0.6, "linear"], [0.24, -0.35, "inOut"], [0.4, 0.0, "inOut"]],
		})
		impact_s = ie * D
		hitstop = H.juice.hitstop
		duration = H.endU * D + hitstop
		_build_events()

	func sheet_setup(adv) -> void:
		adv.set_hit_direction(sheet_dir)

	func begin(host) -> void:
		start_facing = host.facing
		side = C.hit_side(host)
		air = bool(host.get("_airborne"))
		air_vy = float(host.get("_vy"))
		ends_on_landing = air
		hitstop = float(H.juice.hitstop) if host.juice else 0.0
		duration = float(H.airEndU if air else H.endU) * D + hitstop
		_build_events()

	## Game time at which the anim phase u plays (the hitstop delays everything after the impact).
	func real_at(u: float) -> float:
		var a := u * D
		return a + hitstop if a > impact_s else a

	func _anim(t: float) -> float:
		if t < impact_s:
			return t
		if t < impact_s + hitstop:
			return impact_s
		return t - hitstop

	func _build_events() -> void:
		var J: Dictionary = H.juice
		var r1 := real_at(H.stepBack[1])
		events = [
			{"t": 0.0, "signal": &"impact"},
			{"t": 0.0, "signal": &"iframes_start"},
			{"t": 0.0, "fx": "spark", "x": J.impactX if side > 0.0 else J.impactXBehind, "y": J.impactY,
				"params": {"count": J.sparks, "speed": J.sparkSpeed, "life": J.sparkLife}},
			{"t": minf(real_at(H.canMoveAt), duration), "signal": &"can_move"},
			{"t": minf(r1, duration), "signal": &"recovered"},
			{"t": minf(r1, duration), "signal": &"iframes_end"},
		]
		if not air:
			var dust: Dictionary = J.skidDust.merged({"dir": int(J.skidDust.dir * side)}, true)
			var step: Dictionary = J.stepDust
			var r0 := real_at(H.stepFront[1])
			events.append_array([
				{"t": real_at(H.impactEnd), "fx": "dust", "anchor": "soleF", "params": dust},
				{"t": r0, "footstep": &"front", "strength": H.stepStrength},
				{"t": r0, "fx": "dust", "anchor": "soleF", "params": step},
				{"t": r1, "footstep": &"back", "strength": H.stepStrength},
				{"t": r1, "fx": "dust", "anchor": "soleB", "params": step},
			])
		sort_events()

	func _tk(name: String, u: float) -> float:
		return (tracks[name] as RigTrack).sample(u)

	## World offset of a boot along the facing: skids with the slide, then its recovery step.
	func _foot(s: String, u: float) -> float:
		var share: float = H.skidShare
		var span: Array = H.stepFront if s == "front" else H.stepBack
		var k: float = H.knockback * side
		return k * (share * _tk("slide", u) + (1.0 - share) * RigMath.smooth01(C.window01(u, span)))

	func _root_x(u: float) -> float:
		return (_foot("front", u) + _foot("back", u)) * 0.5

	func root_motion(t: float) -> Vector2:
		if air:
			return Vector2.ZERO
		return Vector2(_root_x(_anim(t) / D), 0.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var J: Dictionary = H.juice
		var a := _anim(t)
		var u := a / D
		if air:
			RigAir.sample_air(rig, pose, air_vy, 0.0, juice, t)
		else:
			RigLocomotion.sample_idle(rig, pose, 0.0, juice)
		pose.facing = 1
		var k := _tk("impact", u)
		var lag := _tk("lag", u)
		var hip_k := _tk("hip", u)
		var front := side > 0.0
		var torso: float = H.torsoRecoil if front else H.torsoRecoilBehind
		var neck: float = H.neckRecoil if front else H.neckRecoilBehind
		var arm: float = H.armFling if front else H.armFlingBehind
		var elbow: float = H.elbowFling if front else H.elbowFlingBehind
		var scarf: float = H.scarfFling if front else H.scarfFlingBehind
		var hair: float = H.hairFling if front else H.hairFlingBehind
		pose.rot[B.TORSO] += deg_to_rad(torso * k)
		pose.rot[B.NECK] += deg_to_rad(neck * lag)
		pose.rot[B.UPPER_ARM_F] += deg_to_rad(arm * lag)
		pose.rot[B.UPPER_ARM_B] += deg_to_rad(arm * H.backArmShare * lag)
		pose.rot[B.FORE_ARM_F] += deg_to_rad(elbow * lag)
		pose.rot[B.FORE_ARM_B] += deg_to_rad(elbow * lag)
		var droop: float = H.handDroop if front else H.handDroopBehind
		pose.rot[B.HAND_F] += deg_to_rad(droop * lag)
		pose.rot[B.HAND_B] += deg_to_rad(droop * lag)
		pose.rot[B.SCARF1] += deg_to_rad(scarf * lag)
		pose.rot[B.SCARF2] += deg_to_rad(scarf * 0.5 * lag)
		pose.rot[B.HAIR] += deg_to_rad(hair * lag)
		if not air:
			# The hip takes the whole slide; the boots skid part of it and step the rest.
			var root := _root_x(u)
			var hip_world: float = (H.hipBack * hip_k + H.knockback * _tk("slide", u)) * side
			pose.x[B.HIP] += hip_world - root
			pose.y[B.HIP] += H.hipDrop * hip_k
			for s in ["front", "back"]:
				var w := C.window01(u, H.stepFront if s == "front" else H.stepBack)
				var lift: float = sin(PI * w) * H.stepLift
				var x := rig.rest_ankle_x(s) + _foot(s, u) - root
				RigMath.solve_leg(rig, pose, s, x, -RigData.FOOT_ANKLE_HEIGHT - lift, sin(PI * w) * deg_to_rad(H.stepToe))
		pose.flash = H.flashAlpha if t < H.flashSeconds else 0.0
		pose.shake_x = 0.0
		pose.shake_y = 0.0
		C.shake(pose, t, J.shakeAmp if juice else H.shakeAmp, J.shakeSeconds if juice else H.shakeSeconds, H.shakeFreq)
		if juice:
			RigMath.squash(pose, B.TORSO, J.squash * _tk("squash", u))
			var ts := maxf(0.0, a - impact_s)
			var spring: float = J.springAmp * exp(-ts / J.springDecay) * sin(TAU * J.springFreq * ts)
			pose.rot[B.HAIR] += deg_to_rad(spring * 0.5)
			pose.rot[B.SCARF1] += deg_to_rad(spring)
			pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
			if t >= H.flashSeconds and t < H.flashSeconds + J.tintSeconds:
				pose.tint = J.tintAlpha * (1.0 - (t - H.flashSeconds) / J.tintSeconds)
				pose.tint_color = Color.html(J.tintColor)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		pose.facing = start_facing
		pose.draw_order = 0


class ShotHit extends RigAction:
	var S: Dictionary
	var J: Dictionary
	var BL: Dictionary
	## Anim second of the impact; the game action starts there.
	var I := 0.26
	var tracks := {}
	var world := PackedFloat32Array()
	var scratch: RigPose
	var sheet_dir := Vector2.LEFT
	var side := 1.0
	## World x sign the bullet travels.
	var bullet_x := -1.0
	var air := false
	var air_vy := 0.0
	var hitstop := 0.0
	var gen := 0
	var host_ref: WeakRef
	var boot_box := Rect2(-34, -8, 92, 47)
	var drip_times := PackedFloat32Array()
	var _kneel_ankle := Vector2.ZERO
	var _kneel_hip := Vector2.ZERO
	var _kneel_foot_b := Vector2.ZERO

	func _init(rig_data: RigData, action_id: StringName, dir: Vector2) -> void:
		super(rig_data)
		id = action_id
		sheet_dir = dir
		S = X.T.shot
		J = S.juice
		BL = J.blood
		I = S.impactAt
		var jolt: float = I + S.joltSeconds
		var hd: float = S.hipDrop
		var hl: float = S.hipLead
		var at0 := func(keys: Array) -> Array: return [[0.0, 0.0], [I, 0.0]] + keys
		tracks = RigTrack.compile({
			"torso": at0.call(S.torso),
			"neck": at0.call(S.neck),
			"torsoBehind": at0.call(S.torsoBehind),
			"neckBehind": at0.call(S.neckBehind),
			"drop": at0.call([[jolt, hd, "out"], [0.54, hd * 0.8], [2.3, hd * 0.6], [2.7, 0.0]]),
			"lead": at0.call([[jolt, hl, "out"], [0.5, hl * 0.4], [0.7, 0.0]]),
			"fling": at0.call([[I + 0.1, 1.0, "out"], [0.6, 0.3], [0.9, 0.0]]),
			"lag": at0.call([[I + 0.12, 1.0, "out"], [0.55, 0.4], [0.9, 0.15], [2.4, 0.1], [2.8, 0.0, "back"]]),
			"squash": at0.call([[I + 0.04, 1.0, "out"], [I + 0.12, -0.4], [0.6, 0.0], [0.84, 0.0], [0.88, 0.6, "out"], [1.0, 0.0]]),
			"kneel": S.kneel,
		})
		world = RigMath.create_world(rig)
		scratch = RigPose.new(rig)
		for part in rig.parts:
			if part.name == "footF" and part.has_box:
				boot_box = part.box
		var d: Dictionary = BL.drips
		for i in int(d.count):
			var t0: float = d.from + (d.to - d.from) * (float(i) / (d.count - 1)) + (RigMath.hash01(31, i) - 0.5) * d.jitter
			drip_times.append(t0)
		hitstop = J.hitstop
		duration = S.endA - I + hitstop
		_build_events()

	func sheet_setup(adv) -> void:
		adv.set_hit_direction(sheet_dir)

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)
		gen += 1
		side = C.hit_side(host)
		bullet_x = -start_facing * side
		air = bool(host.get("_airborne"))
		air_vy = float(host.get("_vy"))
		ends_on_landing = air
		hitstop = float(J.hitstop) if host.juice else 0.0
		duration = float(S.airEndA if air else S.endA) - I + hitstop
		_build_events()

	# ---------- timeline ----------

	func _anim(t: float) -> float:
		return I + maxf(0.0, t - hitstop)

	## Game time (seconds since the impact) of the anim second a.
	func real_at(a: float) -> float:
		return a - I + hitstop

	func _build_events() -> void:
		events = [
			{"t": 0.0, "signal": &"bullet_hit_body"},
			{"t": 0.0, "signal": &"impact"},
			{"t": 0.0, "signal": &"iframes_start"},
			{"t": 0.0, "custom": "blood"},
		]
		var steps: Array = S.steps
		var recovered := duration
		if not air:
			var dust: Dictionary = J.dust.merged({"dir": int(J.dust.dir * side)}, true)
			events.append({"t": 0.0, "fx": "dust", "anchor": "soleF", "params": dust})
			for s: Dictionary in steps:
				var t1 := real_at(s.at[1])
				var dx: float = s.dx * side
				var foot := "F" if s.side == "front" else "B"
				events.append({"t": t1, "footstep": StringName(s.side), "strength": S.stepStrength})
				events.append({"t": t1, "fx": "dust", "anchor": ("heel" if dx < 0.0 else "toe") + foot, "params": J.stepDust.merged({"dir": 1 if dx > 0.0 else -1})})
			events.append({"t": real_at(S.kneelLanding), "signal": &"down"})
			events.append({"t": real_at(S.kneelLanding), "custom": "knee_dust"})
			events.append({"t": real_at(S.riseAt), "signal": &"rise"})
			events.append({"t": minf(real_at(S.canMoveAt), duration), "signal": &"can_move"})
			recovered = real_at((steps[steps.size() - 1] as Dictionary).at[1])
			for i in drip_times.size():
				var td := drip_times[i] - I
				if td < duration:
					events.append({"t": td, "custom": "drip", "i": i})
		if air:
			events.append({"t": recovered, "signal": &"can_move"})
		events.append({"t": recovered, "signal": &"recovered"})
		events.append({"t": recovered, "signal": &"iframes_end"})
		sort_events()

	func _tk(name: String, a: float) -> float:
		return (tracks[name] as RigTrack).sample(a)

	## Boot offset along the facing in the world: skid on impact plus its steps.
	func _foot(s: String, a: float) -> float:
		var sk: Dictionary = S.skid
		var x: float = sk.dx * C.ease_out(C.window01(a, sk.at))
		for st: Dictionary in S.steps:
			if st.side == s:
				x += st.dx * RigMath.smooth01(C.window01(a, st.at))
		return x * side

	func _root_x(a: float) -> float:
		return (_foot("front", a) + _foot("back", a)) * 0.5

	func root_motion(t: float) -> Vector2:
		if air:
			return Vector2.ZERO
		return Vector2(_root_x(_anim(t)), 0.0)

	# ---------- pose ----------

	## Standing target of a boot (character space): ankle x, y and foot angle.
	func _standing_leg(s: String, a: float, root_x: float) -> Vector3:
		var lift := 0.0
		var toe := 0.0
		for st: Dictionary in S.steps:
			if st.side != s or a <= st.at[0] or a >= st.at[1]:
				continue
			var w := C.window01(a, st.at)
			lift = sin(PI * w) * st.lift
			toe = sin(PI * w) * deg_to_rad(st.toe)
		return Vector3(rig.rest_ankle_x(s) + _foot(s, a) - root_x, -RigData.FOOT_ANKLE_HEIGHT - lift, toe)

	## Kneel geometry from the front-side contact x: knee pad on the ground ahead, toe planted
	## behind with the heel up, hip above the knee, the other boot planted ahead.
	func _kneel_pose(contact_x: float) -> float:
		var angle := deg_to_rad(S.kneelFootAngle)
		var lf: RigData.Leg = rig.legs.front
		var lb: RigData.Leg = rig.legs.back
		var toe := rig.anchor("toeF")
		var ky: float = -S.kneeHeight
		var kx: float = contact_x + S.kneeForward
		_kneel_ankle.y = -(toe.y * sin(angle) + toe.z * cos(angle))
		var dy := _kneel_ankle.y - ky
		_kneel_ankle.x = kx - sqrt(maxf(0.0, lf.lower * lf.lower - dy * dy))
		var lean: float = S.thighLean
		var hx := kx + lean
		var hy := ky - sqrt(lf.upper * lf.upper - lean * lean)
		_kneel_hip.x = hx - lf.hip_x - rig.bone_x[B.HIP]
		_kneel_hip.y = hy - lf.hip_y - rig.bone_y[B.HIP]
		_kneel_foot_b.x = _kneel_hip.x + rig.bone_x[B.HIP] + lb.hip_x + S.kneelFrontFoot
		_kneel_foot_b.y = -RigData.FOOT_ANKLE_HEIGHT
		return angle

	## Lifts an ankle so no corner of the boot at angle goes below the ground.
	func _above_ground(ankle_y: float, angle: float) -> float:
		var sn := sin(angle)
		var cs := cos(angle)
		var low := 0.0
		for k in 4:
			var x := boot_box.end.x if k & 1 else boot_box.position.x
			var y := boot_box.end.y if k & 2 else boot_box.position.y
			low = maxf(low, ankle_y + x * sn + y * cs)
		return ankle_y - low

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var a := _anim(t)
		if air:
			RigAir.sample_air(rig, pose, air_vy, 0.0, juice, t)
		else:
			RigLocomotion.sample_idle(rig, pose, 0.0, juice)
		pose.facing = 1
		var front := side > 0.0
		var fling := _tk("fling", a)
		var lag := _tk("lag", a)
		var kneel := 0.0 if air else _tk("kneel", a)
		var kenv := clampf(kneel, 0.0, 1.0)
		var shiver: float = kenv * sin(TAU * S.trembleFreq * a) * S.tremble
		var breath: float = kenv * (0.5 - 0.5 * cos(TAU * S.breathFreq * (a - S.kneelLanding))) * S.breath
		if not air:
			pose.x[B.HIP] += _tk("lead", a) * side
			pose.y[B.HIP] += _tk("drop", a)
		pose.rot[B.TORSO] += deg_to_rad(_tk("torso" if front else "torsoBehind", a) + shiver)
		pose.rot[B.NECK] += deg_to_rad(_tk("neck" if front else "neckBehind", a) - shiver * 0.5)
		pose.rot[B.UPPER_ARM_F] += deg_to_rad((S.armFling if front else S.armFlingBehind) * fling)
		pose.rot[B.FORE_ARM_F] += deg_to_rad((S.elbowFling if front else S.elbowFlingBehind) * fling)
		pose.rot[B.UPPER_ARM_B] += deg_to_rad((S.backArmFling if front else S.backArmFlingBehind) * fling)
		pose.rot[B.FORE_ARM_B] += deg_to_rad((S.backElbowFling if front else S.backElbowFlingBehind) * fling)
		pose.rot[B.SCARF1] += deg_to_rad(S.scarfFling * lag * side)
		pose.rot[B.SCARF2] += deg_to_rad(S.scarfFling * 0.5 * lag * side)
		pose.rot[B.HAIR] += deg_to_rad(S.hairFling * lag * side)

		if not air:
			var r := _root_x(a)
			var fl := _standing_leg("front", a, r)
			if kneel > 0.0:
				var k_angle := _kneel_pose(fl.x)
				pose.x[B.HIP] = lerpf(pose.x[B.HIP], _kneel_hip.x, kneel)
				pose.y[B.HIP] = lerpf(pose.y[B.HIP], _kneel_hip.y, kneel)
				pose.y[B.TORSO] += breath
				var angle := lerpf(fl.z, k_angle, kneel)
				RigMath.solve_leg(rig, pose, "front", lerpf(fl.x, _kneel_ankle.x, kneel), _above_ground(lerpf(fl.y, _kneel_ankle.y, kneel), angle), angle)
			else:
				RigMath.solve_leg(rig, pose, "front", fl.x, fl.y, fl.z)
			var bl := _standing_leg("back", a, r)
			if kneel > 0.0:
				# The other boot steps forward as he goes down (and back as he rises).
				var lift: float = sin(PI * kenv) * S.kneelStepLift
				RigMath.solve_leg(rig, pose, "back", lerpf(bl.x, _kneel_foot_b.x, kenv), lerpf(bl.y, _kneel_foot_b.y, kenv) - lift, bl.z * (1.0 - kenv))
			else:
				RigMath.solve_leg(rig, pose, "back", bl.x, bl.y, bl.z)

		pose.flash = 0.0
		pose.shake_x = 0.0
		pose.shake_y = 0.0
		if juice:
			RigMath.squash(pose, B.TORSO, J.squash * _tk("squash", a))
			var ts := a - I
			var spring: float = J.springAmp * exp(-ts / J.springDecay) * sin(TAU * J.springFreq * ts) if ts > 0.0 else 0.0
			pose.rot[B.HAIR] += deg_to_rad(spring * 0.5)
			pose.rot[B.SCARF1] += deg_to_rad(spring)
			pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
			if t < J.flashSeconds:
				pose.flash = J.flashAlpha
			elif t < J.flashSeconds + J.tintSeconds:
				pose.tint = J.tintAlpha * (1.0 - (t - J.flashSeconds) / J.tintSeconds)
				pose.tint_color = Color.html(J.tintColor)
			C.shake(pose, t, J.shakeAmp, J.shakeSeconds, J.shakeFreq)
			if not air:
				C.shake(pose, t - real_at(S.kneelLanding), J.kneelShake, J.kneelShakeSeconds, J.shakeFreq)

		var hc: Array = S.handToChest
		var hand_in := RigMath.smooth01((a - hc[0]) / (hc[1] - hc[0]))
		var hand_out := 1.0 - RigMath.smooth01((a - hc[2]) / (hc[3] - hc[2]))
		_hand_on_chest(pose, minf(hand_in, hand_out))
		if not air:
			_brace_knee(pose, RigMath.smooth01(kenv))
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		pose.facing = start_facing
		pose.draw_order = 0

	## Front wrist slides onto the chest and the hand lays flat across the wound.
	func _hand_on_chest(pose: RigPose, weight: float) -> void:
		if weight <= 0.0:
			return
		RigMath.compute_world(rig, pose, world)
		var h := B.HAND_F * 6
		var fx := world[h + 4]
		var fy := world[h + 5]
		var cw: Array = S.chestWrist
		var target := RigMath.point(world, B.TORSO, cw[0], cw[1])
		var torso_angle := RigMath.bone_angle(world, B.TORSO)
		RigMath.solve_arm(rig, pose, "front", lerpf(fx, target.x, weight), lerpf(fy, target.y, weight), world, false, 1.0)
		RigMath.compute_world(rig, pose, world)
		var flat := deg_to_rad(S.chestHandAngle) + torso_angle - RigMath.bone_angle(world, B.FORE_ARM_F)
		pose.rot[B.HAND_F] = lerpf(pose.rot[B.HAND_F], wrapf(flat, -PI, PI), weight)

	## Back wrist braces on the raised knee while kneeling.
	func _brace_knee(pose: RigPose, weight: float) -> void:
		if weight <= 0.0:
			return
		RigMath.compute_world(rig, pose, world)
		var h := B.HAND_B * 6
		var k: int = (rig.legs.back as RigData.Leg).shin * 6
		var off: Array = S.braceOffset
		var tx: float = world[k + 4] + off[0]
		var ty: float = world[k + 5] + off[1]
		RigMath.solve_arm(rig, pose, "back", lerpf(world[h + 4], tx, weight), lerpf(world[h + 5], ty, weight), world, false, 1.0)

	# ---------- blood ----------

	func custom_event(ev: Dictionary, host) -> void:
		if not host.juice:
			return
		var gp: Vector2 = host.global_position
		var ground: float = gp.y + (4000.0 if air else 0.0)
		match ev.custom:
			"blood":
				_spawn_blood(host, gp, ground)
			"drip":
				var hw: PackedFloat32Array = host.get("_world")
				var i: int = ev.i
				var p: Vector2 = gp + RigMath.point(hw, B.HAND_F, 0.0, 24.0 + RigMath.hash01(37, i) * 30.0) + Vector2(0.0, 6.0)
				var fade: Array = BL.stainFade
				var params := {"emit": _emit_drip, "life": float(fade[1]) - float(ev.t), "t0": ev.t, "vis": RigMath.hash01(97, i), "seed": 97 + i}
				host.fx.spawn("custom", params, p.x, p.y, 0.0, host.pose.facing, ground, host.now())
			"knee_dust":
				var hw: PackedFloat32Array = host.get("_world")
				var knee := RigMath.point(hw, (rig.legs.front as RigData.Leg).shin, 0.0, 0.0)
				host.fx.spawn("dust", J.kneeDust, gp.x + knee.x, gp.y, 0.0, host.pose.facing, gp.y, host.now())

	## Spray out of the exit side, a jet back from the entry, mist on both and the wound decal.
	## Origins come from the impact pose itself (the live pose is still blending in).
	func _spawn_blood(host, gp: Vector2, ground: float) -> void:
		sample(0.0, scratch, true)
		RigMath.compute_world(rig, scratch, world)
		var back_pt: Array = BL.exitPoint
		var chest_pt: Array = BL.frontPoint
		var exit_l: Array = back_pt if side > 0.0 else chest_pt
		var entry_l: Array = chest_pt if side > 0.0 else back_pt
		var exit := gp + RigMath.point(world, B.TORSO, exit_l[0], exit_l[1])
		var entry := gp + RigMath.point(world, B.TORSO, entry_l[0], entry_l[1])
		var now: float = host.now()
		var facing: int = start_facing
		host.fx.spawn("custom", _droplets(BL.spray, exit, ground), exit.x, exit.y, 0.0, facing, ground, now)
		host.fx.spawn("custom", _droplets(BL.jet, entry, ground), entry.x, entry.y, 0.0, facing, ground, now)
		var m: Dictionary = BL.mist
		host.fx.spawn("custom", {"emit": _emit_mist, "life": m.life, "exit": exit, "entry": entry, "drift": m.drift * bullet_x}, exit.x, exit.y, 0.0, facing, ground, now)
		host.fx.spawn("custom", {"emit": _emit_wound, "life": BL.woundFade[1], "gen": gen}, exit.x, exit.y, 0.0, facing, ground, now)

	## Precomputed droplets (drag and gravity in closed form) and their landing on the ground.
	func _droplets(p: Dictionary, origin: Vector2, ground: float) -> Dictionary:
		var n: int = p.count
		var seed: int = p.seed
		var x0 := PackedFloat32Array()
		var y0 := PackedFloat32Array()
		var vx := PackedFloat32Array()
		var vy := PackedFloat32Array()
		var land := PackedFloat32Array()
		var land_x := PackedFloat32Array()
		var size := PackedFloat32Array()
		var back := PackedByteArray()
		var vis := PackedFloat32Array()
		var k: float = p.drag
		var g: float = p.gravity
		for i in n:
			var r := func(j: int) -> float: return RigMath.hash01(seed, i * 8 + j)
			var angle: float = deg_to_rad(p.angle) + (r.call(0) - 0.5) * deg_to_rad(p.cone)
			if bullet_x > 0.0:
				angle = PI - angle
			var speed: float = p.speed * (0.35 + 0.8 * r.call(1))
			var px: float = origin.x + (r.call(2) - 0.5) * 10.0
			var py: float = origin.y + (r.call(3) - 0.5) * 10.0
			x0.append(px)
			y0.append(py)
			vx.append(cos(angle) * speed)
			vy.append(sin(angle) * speed)
			var tl := _land_time(py, vy[i], k, g, ground)
			land.append(tl)
			land_x.append(px + vx[i] * (1.0 - exp(-k * tl)) / k)
			size.append(r.call(4))
			back.append(1 if r.call(5) < float(p.backShare) else 0)
			vis.append(r.call(6))
		return {"emit": _emit_droplets, "life": BL.stainFade[1], "seed": seed, "n": n, "k": k, "g": g,
			"x0": x0, "y0": y0, "vx": vx, "vy": vy, "land": land, "land_x": land_x, "size": size, "back": back, "vis": vis}

	static func _drop_y(y0: float, vy0: float, k: float, g: float, t: float) -> float:
		return y0 + g / k * t + (vy0 - g / k) * (1.0 - exp(-k * t)) / k

	static func _land_time(y0: float, vy0: float, k: float, g: float, ground: float) -> float:
		var hi := 1.6
		if _drop_y(y0, vy0, k, g, hi) < ground:
			return hi
		var lo := 0.0
		for _i in 24:
			var mid := (lo + hi) * 0.5
			if _drop_y(y0, vy0, k, g, mid) < ground:
				lo = mid
			else:
				hi = mid
		return hi

	## 0 before the stain window, 1 after it; each stain vanishes at its own moment inside it.
	func _stain_fade(since: float) -> float:
		var f: Array = BL.stainFade
		return clampf((since - f[0]) / (f[1] - f[0]), 0.0, 1.0)

	func _emit_droplets(fx: RigFx, ev: Dictionary) -> void:
		var age := fx.e_age
		var fade := _stain_fade(age)
		var drop := fx.rig.fx_sprite("bloodDrop").id
		var splat := fx.rig.fx_sprite("bloodSplat").id
		var k: float = ev.k
		var g: float = ev.g
		var land: PackedFloat32Array = ev.land
		var size: PackedFloat32Array = ev.size
		var vis: PackedFloat32Array = ev.vis
		var back: PackedByteArray = ev.back
		var x0: PackedFloat32Array = ev.x0
		var y0: PackedFloat32Array = ev.y0
		var vx: PackedFloat32Array = ev.vx
		var vy: PackedFloat32Array = ev.vy
		for i in int(ev.n):
			var sz := size[i]
			if age >= land[i]:
				if fade < 0.05 + 0.9 * vis[i]:
					var full := 0 if sz < 0.5 else (1 if sz < 0.85 else 2)
					var spread := mini(full, int((age - land[i]) / 0.06 * 3.0))
					fx.add(splat, spread, (ev.land_x as PackedFloat32Array)[i], fx.e_ground, 1.0, 1.0, 1.0, 0.0, RigFx.Layer.BACK)
				continue
			var e := exp(-k * age)
			var x := x0[i] + vx[i] * (1.0 - e) / k
			var y := _drop_y(y0[i], vy[i], k, g, age)
			var cvx := vx[i] * e
			var cvy := g / k + (vy[i] - g / k) * e
			var stretch := roundf(1.0 + minf(1.5, Vector2(cvx, cvy).length() / 500.0))
			var layer := RigFx.Layer.BACK if back[i] == 1 else RigFx.Layer.FRONT
			fx.add(drop, 0 if sz < 0.55 else (1 if sz < 0.85 else 2), x, y, 1.0, stretch, 1.0, atan2(cvy, cvx), layer)

	func _emit_mist(fx: RigFx, ev: Dictionary) -> void:
		var m: Dictionary = BL.mist
		var k := fx.e_age / fx.e_life
		var sprite := fx.rig.fx_sprite("bloodMist").id
		for i in int(m.count):
			var src: Vector2 = ev.entry if i % 2 == 1 else ev.exit
			var r := RigMath.hash01(53, i)
			var x: float = src.x + (r - 0.5) * 16.0 + ev.drift * fx.e_age * (0.3 if i % 2 == 1 else 1.0)
			var y: float = src.y - m.rise * fx.e_age * (0.5 + r)
			if k < 0.85 - 0.15 * r:
				fx.add(sprite, mini(2, int(k * 3.0)), x, y, 1.0, 1.0, 1.0, 0.0, RigFx.Layer.FRONT if i % 2 == 1 else RigFx.Layer.BACK)

	## Wound decal glued to the torso while this reaction plays.
	func _emit_wound(fx: RigFx, ev: Dictionary) -> void:
		var host = host_ref.get_ref() if host_ref else null
		if host == null or int(ev.gen) != gen or host.current_action() != id:
			return
		var f: Array = BL.woundFade
		var fade := clampf((fx.e_age - f[0]) / (f[1] - f[0]), 0.0, 1.0)
		var grow: float = clampf(fx.e_age / BL.woundGrow, 0.0, 1.0) * (1.0 - fade)
		if grow <= 0.05:
			return
		var hw: PackedFloat32Array = host.get("_world")
		var wp: Array = BL.woundPoint
		var p: Vector2 = host.global_position + RigMath.point(hw, B.TORSO, wp[0], wp[1])
		var a := RigMath.bone_angle(hw, B.TORSO)
		var facing: int = host.pose.facing
		var rot := a if facing > 0 else PI - a
		fx.add(fx.rig.fx_sprite("bloodWound").id, 0 if grow < 0.3 else (1 if grow < 0.7 else 2), p.x, p.y, 1.0, float(facing), 1.0, rot)

	## One drop from under the fingers falling to the ground, then a stain.
	func _emit_drip(fx: RigFx, ev: Dictionary) -> void:
		var g: float = BL.drips.gravity
		var dt := fx.e_age
		var fall := sqrt(2.0 * maxf(0.0, fx.e_ground - fx.e_y) / g)
		if dt < fall:
			var stretch := roundf(1.0 + minf(1.2, g * dt / 500.0))
			fx.add(fx.rig.fx_sprite("bloodDrop").id, 0, fx.e_x, fx.e_y + 0.5 * g * dt * dt, 1.0, stretch, 1.0, PI / 2.0)
		elif _stain_fade(float(ev.t0) + dt) < 0.05 + 0.9 * float(ev.vis):
			fx.add(fx.rig.fx_sprite("bloodSplat").id, 0, fx.e_x, fx.e_ground, 1.0, 1.0, 1.0, 0.0, RigFx.Layer.BACK)
