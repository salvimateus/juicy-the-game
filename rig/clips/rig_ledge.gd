class_name RigLedge
extends RefCounted
## Ledge hang, catch and climb sampler (port of the JS ledge clip) in ledge space L: stone face
## x = 0, grass top y = 0, hanging at x < 0 facing +x. The Adventurer origin follows origin(t), a
## collision-friendly path from the hanging origin up to the stand spot on the top; the pose is
## offset by it, so the visual is independent of that path.

const L := preload("res://rig/clips/ledge_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7
const SIDES := ["front", "back"]

var rig: RigData
var D: float = L.T.duration
var tA: float = L.T.ANTICIPATION_T
var tP: float = L.T.PULL_T
var tC: float = L.T.CHEST_T
var tH: float = L.T.PALMS_T
var tK: float = L.T.KNEE_T
var tS: float = L.T.STAND_T
var tB: float = L.T.STEP_BACK_T
var tD: float = L.T.DROP_T
var tG: float = L.T.GRAB_T
var hip_rest_y := 0.0
var arm_len := 0.0
var hang_y := 0.0
var dip_y := 0.0
var catch_y := 0.0
var grip := {}
var palms := {}
var keys := {}
var world := PackedFloat32Array()
var probe: RigPose
var probe_world := PackedFloat32Array()
## Hanging origin in L (feet level under the hip).
var hang_origin := Vector2.ZERO
## Standing origin on the top in L.
var top_origin := Vector2.ZERO


func _init(rig_data: RigData) -> void:
	rig = rig_data
	hip_rest_y = rig.bone_y[B.HIP]
	world = RigMath.create_world(rig)
	probe_world = RigMath.create_world(rig)
	probe = RigPose.new(rig)
	arm_len = Vector2(rig.bone_x[B.FORE_ARM_F], rig.bone_y[B.FORE_ARM_F]).length() + Vector2(rig.bone_x[B.HAND_F], rig.bone_y[B.HAND_F]).length()
	for side in SIDES:
		grip[side] = _wrist_of(L.T.grip[side])
		palms[side] = _wrist_of(L.T.palms[side])
	var H: Dictionary = L.T.hang
	hang_y = _hang_hip_y(H.x, H.lean, H.reach)
	dip_y = _hang_hip_y(H.x - 2.0, H.lean + 2.0, H.dipReach)
	catch_y = _hang_hip_y(H.x, H.lean, 0.998)
	hang_origin = Vector2(H.x, hang_y - L.T.stand.y)
	top_origin = Vector2(L.T.stand.x, 0.0)
	_build_keys()


func _wrist_of(spec: Dictionary) -> Vector3:
	var a := deg_to_rad(spec.angle)
	return Vector3(spec.x + L.T.fistCenter * sin(a), spec.y - L.T.fistCenter * cos(a), spec.angle)


func _apply_hunch(pose: RigPose, w: float) -> void:
	var h: Dictionary = L.T.hunch
	pose.y[B.UPPER_ARM_F] -= h.shoulder * w
	pose.y[B.UPPER_ARM_B] -= h.shoulder * w
	pose.y[B.NECK] += h.neck * w
	pose.x[B.UPPER_ARM_F] += h.shoulderXFront * w
	pose.x[B.UPPER_ARM_B] += h.shoulderXBack * w


func _shoulder_reach(hip_x: float, hip_y: float, lean: float) -> float:
	probe.reset()
	probe.x[B.HIP] = hip_x
	probe.y[B.HIP] = hip_y - hip_rest_y
	probe.rot[B.TORSO] = deg_to_rad(lean)
	_apply_hunch(probe, 1.0)
	RigMath.compute_world(rig, probe, probe_world)
	var worst := 0.0
	for side in SIDES:
		var o: int = (B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B) * 6
		var g: Vector3 = grip[side]
		worst = maxf(worst, Vector2(g.x - probe_world[o + 4], g.y - probe_world[o + 5]).length())
	return worst


func _hang_hip_y(hip_x: float, lean: float, reach: float) -> float:
	var lo := 60.0
	var hi := 600.0
	for i in 40:
		var mid := (lo + hi) * 0.5
		if _shoulder_reach(hip_x, mid, lean) < reach * arm_len:
			lo = mid
		else:
			hi = mid
	return lo


func _k(t: float, v: float, ease := "inOut") -> Array:
	return [t, v, ease]


func _build_keys() -> void:
	var H: Dictionary = L.T.hang
	var C: Dictionary = L.T.chest
	var M: Dictionary = L.T.mantle
	var S: Dictionary = L.T.stand
	var F: Dictionary = L.T.feet
	var ph: Dictionary = L.T.palmsHip
	var raw := {
		"hipX": [_k(0, H.x), _k(tA, H.x), _k(tP, H.x - 2), _k(tC, C.x), _k(tH, ph.x), _k(tK, M.x), _k(tS, S.x), _k(tG, S.x), _k(tG + 0.001, H.x), _k(D, H.x)],
		"hipY": [_k(0, hang_y), _k(tA, hang_y), _k(tP, dip_y), _k(tC, C.y), _k(tH, ph.y), _k(tK - 0.12, M.y + 6), _k(tK, M.y), _k(tS - 0.06, S.y - 8), _k(tS, S.y, "out"), _k(tB, S.y), _k(tG - 0.001, S.y), _k(tG, catch_y, "step"), _k(tG + 0.2, hang_y, "out"), _k(D, hang_y)],
		"lean": [_k(0, H.lean), _k(tA, H.lean), _k(tP, H.lean + 2), _k(tC, C.lean), _k(tH, lerpf(C.lean, M.lean, 0.6)), _k(tK, M.lean), _k(tS, S.lean), _k(tG, H.lean), _k(D, H.lean)],
		"neck": [_k(0, H.neck), _k(tA, H.neck), _k(tP, H.neck - 4), _k(tC, C.neck), _k(tK, M.neck), _k(tS, S.neck), _k(tB, S.neck), _k(tG, H.neck), _k(D, H.neck)],
		"armIK": [_k(0, 1), _k(tK + 0.12, 1), _k(tS, 0), _k(tG - 0.001, 0), _k(tG, 1, "step"), _k(D, 1)],
		"palms": [_k(0, 0), _k(tC, 0), _k(tH, 1), _k(tD, 1), _k(tD + 0.05, 0), _k(D, 0)],
		"legF": [_k(0, 0), _k(tK - F.plantTime, 0), _k(tK, 1), _k(tD + 0.02, 1), _k(tD + 0.12, 0, "out"), _k(D, 0)],
		"legB": [_k(0, 0), _k(tC - 0.1, 0), _k(tH + 0.05, 1), _k(tD, 1), _k(tD + 0.1, 0, "out"), _k(D, 0)],
		"footFX": [_k(0, F.stepUp), _k(tK + 0.12, F.stepUp), _k(tS, F.standFront), _k(D, F.standFront)],
		"headDodge": [_k(0, 0), _k(tP, 0), _k(tC, 1), _k(tH + 0.08, 1.2), _k(tK + 0.05, 0), _k(D, 0)],
		"kneeRaise": [_k(0, 0), _k(tC, 0), _k(tK - F.plantTime - F.reachTime, 1), _k(tB, 1), _k(tB + 0.05, 0), _k(D, 0)],
		"kneeReach": [_k(0, 0), _k(tK - F.plantTime - F.reachTime, 0), _k(tK - F.plantTime, 1), _k(tB, 1), _k(tB + 0.05, 0), _k(D, 0)],
		"hunch": [_k(0, 1), _k(tP, 1), _k(tC, 0.5), _k(tK, 0), _k(tD + 0.1, 0), _k(tG, 1, "out"), _k(D, 1)],
		"tuck": [_k(0, 0), _k(tA, 0), _k(tP, 0.5), _k(tC, 0.2), _k(tH, 0.4), _k(tK, 0.3), _k(tS, 0), _k(tG - 0.001, 0), _k(tG, 0.2, "step"), _k(D, 0)],
	}
	for name in raw:
		keys[name] = RigTrack.from_keys(raw[name], 1.0 / D)


func trk(name: String, t: float) -> float:
	return (keys[name] as RigTrack).sample(t / D, true)


## Adventurer origin in L along the climb (t in ledge time): up first, then over the top.
func origin_at(t: float) -> Vector2:
	var up := RigMath.smooth01((t - tP) / (tK - tP))
	var over := RigMath.smooth01((t - tK) / (tS - tK))
	return Vector2(lerpf(hang_origin.x, top_origin.x, over), lerpf(hang_origin.y, top_origin.y, up))


func _front_foot(t: float) -> Vector3:
	return Vector3(trk("footFX", t), -RigData.FOOT_ANKLE_HEIGHT, 0.0)


func _back_foot(t: float) -> Vector3:
	var F: Dictionary = L.T.feet
	var climb_end := lerpf(tK, tS, F.climbSplit)
	if t < tK:
		var w := RigMath.smooth01((t - tC) / (tK - tC))
		return Vector3(lerpf(F.wallLow[0], F.wall[0], w), lerpf(F.wallLow[1], F.wall[1], w), F.wallAngle)
	if t < climb_end:
		var w := RigMath.smooth01((t - tK) / (climb_end - tK))
		return Vector3(lerpf(F.wall[0], F.lip[0], w), lerpf(F.wall[1], F.lip[1], w), lerpf(F.wallAngle, 0.0, w))
	var w := RigMath.smooth01((t - climb_end) / (tS - climb_end))
	return Vector3(lerpf(F.lip[0], F.standBack, w), lerpf(F.lip[1], -RigData.FOOT_ANKLE_HEIGHT, w) - sin(PI * w) * 14.0, 0.0)


## Draw order preset at ledge time t (see Adventurer draw orders).
func draw_order(t: float) -> int:
	if t >= tH and t < tS + L.T.defaultOrderDelay:
		return 2
	if t < tS + L.T.defaultOrderDelay:
		return 1
	return 0


## Samples the ledge pose at ledge time t. catch_age: seconds since the hands caught the corner
## (-1 for none), catch_k scales the catch jolt, origin is the Adventurer origin in L, facing the
## final facing (the pose is authored facing the wall at +x). extra_tuck and extra_hip_x feed the
## leap coil.
func sample(pose: RigPose, t: float, catch_age: float, catch_k: float, origin: Vector2, facing: int, juice: bool, now: float, extra_tuck := 0.0, extra_hip_x := 0.0) -> void:
	var J: Dictionary = L.T.juice
	var Dn: Dictionary = L.T.dangle
	pose.reset()
	pose.root_x = -origin.x
	pose.root_y = -origin.y
	var hip_x := trk("hipX", t) + extra_hip_x
	var hip_y := trk("hipY", t)
	var lean := trk("lean", t)
	var neck := trk("neck", t)
	var tuck := clampf(trk("tuck", t) + extra_tuck, 0.0, 1.0)
	var arm_ik := trk("armIK", t)
	var palm := trk("palms", t)
	var age := catch_age if catch_age >= 0.0 else 10.0
	var hanging := t < tP or t >= tG
	var hang_fade := 1.0 if t >= tG else 1.0 - RigMath.smooth01((t - tA + 0.1) / 0.3)
	var swing := 0.0
	if hanging:
		swing = Dn.swing * sin(TAU * Dn.swingHz * age) * exp(-age / Dn.swingDecay) * hang_fade
		swing += 1.5 * sin(TAU * Dn.swingHz * age) * RigMath.smooth01(age / 0.3) * hang_fade
	var scarf_extra := 0.0
	var root_swing := 0.0
	if juice:
		if catch_age >= 0.0 and catch_age < 1.8:
			var ca := catch_age
			var env: float = exp(-ca / J.catchDecay) * hang_fade
			root_swing = J.catchSwing * catch_k * sin(TAU * J.catchSwingHz * ca) * env
			if ca < 0.18:
				hip_y -= J.catchBounce * catch_k * sin(PI * ca / 0.18)
			swing += 10.0 * catch_k * sin(TAU * Dn.swingHz * ca + 0.6) * exp(-ca / 0.5) * hang_fade
			scarf_extra += J.scarfWhip * catch_k * exp(-ca / J.scarfWhipDecay) * cos(TAU * J.scarfWhipHz * ca)
			neck += J.headWhip * catch_k * exp(-ca / 0.15) * sin(PI * clampf(ca / 0.2, 0.0, 1.0))
			if ca < J.catchShakeSeconds:
				var decay := pow(1.0 - ca / J.catchShakeSeconds, 2.0)
				pose.shake_y = J.catchShake * catch_k * decay * cos(TAU * 24.0 * ca)
				pose.shake_x = J.catchShake * catch_k * 0.5 * decay * sin(TAU * 31.0 * ca)
		var effort := RigMath.smooth01((t - tP) / 0.15) * (1.0 - RigMath.smooth01((t - tK) / 0.25))
		lean += J.tremor * effort * sin(TAU * J.tremorHz * t)
		hip_x += J.tremorPx * effort * sin(TAU * J.tremorHz * 1.3 * t + 1.0)
		var la := t - tS
		if la >= 0.0 and la < J.landSeconds:
			var bb := sin(PI * la / J.landSeconds)
			hip_y += J.landDip * bb
			RigMath.squash(pose, B.TORSO, J.landSquash * bb)
		if effort > 0.0:
			RigMath.squash(pose, B.NECK, J.strainSquash * effort * (0.5 + 0.5 * sin(TAU * 3.0 * t)))
	if hanging:
		pose.y[B.TORSO] -= L.T.breath * (0.5 - 0.5 * cos(TAU * L.T.breathHz * now))
	pose.x[B.HIP] = hip_x
	pose.y[B.HIP] = hip_y - hip_rest_y
	pose.rot[B.TORSO] = deg_to_rad(lean)
	pose.rot[B.NECK] = deg_to_rad(neck) - deg_to_rad(lean) * 0.4
	_apply_hunch(pose, trk("hunch", t))
	var dodge := trk("headDodge", t)
	pose.x[B.NECK] += L.T.headDodge.x * dodge
	pose.y[B.NECK] += L.T.headDodge.y * dodge
	if root_swing != 0.0:
		var gx: float = (L.T.grip.front.x + L.T.grip.back.x) * 0.5
		RigMath.spin_root(pose, deg_to_rad(root_swing * arm_ik), gx, (grip.front as Vector3).y)
	var tilt := pose.rot[B.TORSO] + pose.root_rot
	var grav: float = J.scarfGravity if juice else 0.5
	pose.rot[B.SCARF1] = deg_to_rad(6.0 - rad_to_deg(tilt) * grav + scarf_extra)
	pose.rot[B.SCARF2] = deg_to_rad(4.0 + scarf_extra * 1.3)
	_pose_legs(pose, t, tuck, swing)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
	for side in SIDES:
		_pose_arm(pose, side, arm_ik, palm)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
	pose.draw_order = draw_order(t)
	finish_facing(pose, facing)


## Applies the final facing to a pose authored facing +x around the Adventurer origin.
static func finish_facing(pose: RigPose, facing: int) -> void:
	pose.root_x *= facing
	pose.facing = facing


func _pose_arm(pose: RigPose, side: String, arm_ik: float, palm: float) -> void:
	var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
	var fore := upper + 1
	var hand := upper + 2
	var sign := 1.0 if side == "front" else -1.0
	var fk_upper := deg_to_rad(sign * 4.0)
	var fk_fore := deg_to_rad(-8.0)
	pose.rot[upper] = fk_upper
	pose.rot[fore] = fk_fore
	pose.rot[hand] = 0.0
	if arm_ik <= 0.0:
		return
	var g: Vector3 = grip[side]
	var p: Vector3 = palms[side]
	var tx := lerpf(g.x, p.x, palm) + pose.root_x
	var ty := lerpf(g.y, p.y, palm) + pose.root_y
	var angle := lerpf(g.z, p.z, palm)
	RigMath.solve_arm(rig, pose, side, tx, ty, world, false, L.T.bend[side])
	pose.rot[upper] = lerp_angle(fk_upper, pose.rot[upper], arm_ik)
	pose.rot[fore] = lerp_angle(fk_fore, pose.rot[fore], arm_ik)
	RigMath.compute_world(rig, pose, world)
	var fore_abs := RigMath.bone_angle(world, fore)
	pose.rot[hand] = lerp_angle(0.0, deg_to_rad(angle) - fore_abs, arm_ik)


func _pose_legs(pose: RigPose, t: float, tuck: float, swing: float) -> void:
	var Dn: Dictionary = L.T.dangle
	var KR: Dictionary = L.T.kneeRaise
	var w_f := trk("legF", t)
	var w_b := trk("legB", t)
	for side in SIDES:
		var leg: RigData.Leg = rig.legs[side]
		var s := 1.0 if side == "front" else -1.0
		var sw := swing * (1.0 if side == "front" else 0.7)
		var thigh := deg_to_rad(Dn.thigh + s * Dn.spread - tuck * 38.0 + sw)
		var shin := deg_to_rad(Dn.shin + tuck * 52.0 + sw * 0.6)
		var foot := deg_to_rad(Dn.foot - tuck * 8.0)
		if side == "front":
			var kr := trk("kneeRaise", t)
			var reach := trk("kneeReach", t)
			thigh = lerpf(thigh, deg_to_rad(KR.thigh), kr)
			shin = lerpf(shin, deg_to_rad(lerpf(KR.shin, KR.reachShin, reach)), kr)
			foot = lerpf(foot, deg_to_rad(lerpf(KR.foot, KR.reachFoot, reach)), kr)
		var w := w_f if side == "front" else w_b
		if w <= 0.0:
			pose.rot[leg.thigh] = thigh
			pose.rot[leg.shin] = shin
			pose.rot[leg.foot] = foot
			continue
		var target := _front_foot(t) if side == "front" else _back_foot(t)
		RigMath.solve_leg(rig, pose, side, target.x, target.y, deg_to_rad(target.z))
		pose.rot[leg.thigh] = lerp_angle(thigh, pose.rot[leg.thigh], w)
		pose.rot[leg.shin] = lerp_angle(shin, pose.rot[leg.shin], w)
		pose.rot[leg.foot] = lerp_angle(foot, pose.rot[leg.foot], w)
