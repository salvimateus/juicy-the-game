class_name RollAction
extends RigAction
## Dodge roll, forward (roll) or backward (roll_back, the forward roll played in reverse from the
## guard crouch). Crouch, dive, tuck into a ball and roll 360 degrees on the ground (settled on the
## lowest pixel), pop up into a guard and stand. The advance comes out as root motion.

const R := preload("res://rig/clips/roll_tuning.gd")

var reverse := false
var K := {}
var D: float = R.T.duration
var R0: float = R.T.ROLL_START
var R1: float = R.T.ROLL_EXIT
var world := PackedFloat32Array()
var scratch: RigPose
var blend_pose: RigPose
var fk := PackedFloat32Array()
var hug := PackedFloat32Array()
var rest_x := {}
var plant_x := 0.0
var ground_bias := 0.0
var advance := PackedFloat32Array()
## Distance a no-slip roll of the ball would cover (for tuning roll_distance).
var no_slip_distance := 0.0
const STEPS := 96
const ARM_BONES := [RigBone.UPPER_ARM_F, RigBone.FORE_ARM_F, RigBone.HAND_F, RigBone.UPPER_ARM_B, RigBone.FORE_ARM_B, RigBone.HAND_B]
var CLOTH := PackedStringArray(["scarfTail", "scarfMid"])


func _init(rig_data: RigData, backward: bool) -> void:
	super(rig_data)
	reverse = backward
	id = &"roll_back" if backward else &"roll"
	K = RigTrack.compile(R.T.tracks)
	world = RigMath.create_world(rig)
	scratch = RigPose.new(rig)
	blend_pose = RigPose.new(rig)
	fk.resize(rig.bone_count)
	hug.resize(rig.bone_count)
	rest_x = {"front": rig.rest_ankle_x("front"), "back": rig.rest_ankle_x("back")}
	RigLocomotion.sample_idle(rig, scratch, 0.0, false)
	ground_bias = -RigMath.settle_on_ground(rig, scratch, world)
	_body(R.T.PLANT_T, scratch, false)
	RigMath.compute_world(rig, scratch, world)
	plant_x = RigMath.anchor_point(rig, world, "fistF").x
	_build_advance()
	duration = _segments()[-1][1]
	_build_events()


func begin(host) -> void:
	start_facing = host.facing


func _tk(name: String, t: float) -> float:
	return (K[name] as RigTrack).sample(t)


func _segments() -> Array:
	return R.T.timelineBack if reverse else R.T.timeline


## Game time -> showcase time along the timeline segments.
func _js_time(t: float) -> float:
	var segs := _segments()
	for seg: Array in segs:
		if t < seg[1]:
			return lerpf(seg[2], seg[3], clampf((t - seg[0]) / (seg[1] - seg[0]), 0.0, 1.0))
	return segs[-1][3]


## Showcase time -> game time (first segment that covers it).
func _at(tj: float) -> float:
	for seg: Array in _segments():
		var lo := minf(seg[2], seg[3])
		var hi := maxf(seg[2], seg[3])
		if tj >= lo - 1e-4 and tj <= hi + 1e-4:
			return lerpf(seg[0], seg[1], clampf((tj - seg[2]) / (seg[3] - seg[2]), 0.0, 1.0))
	return 0.0


func _spin_at(t: float) -> float:
	var w := clampf((t - R0) / (R1 - R0), 0.0, 1.0)
	return TAU * lerpf(RigMath.smooth01(w), w, R.T.spinLinear)


func _settle_weight(t: float) -> float:
	return RigMath.smooth01((t - (R0 - 0.02)) / 0.06) * (1.0 - RigMath.smooth01((t - (R1 - 0.02)) / 0.06))


func _hop_lift(t: float) -> float:
	for hop in [R.T.HOP1, R.T.HOP2]:
		if t > hop[0] and t < hop[1]:
			return sin(PI * (t - hop[0]) / (hop[1] - hop[0])) * R.T.hopLift
	return 0.0


func _settle(pose: RigPose, sw: float) -> void:
	if sw <= 0.0:
		return
	var y := pose.root_y
	RigMath.settle_on_ground(rig, pose, world)
	pose.root_y = y + (pose.root_y - y - ground_bias) * sw


func _juice_bones(t: float, pose: RigPose) -> void:
	var s: Dictionary = R.T.juice.squash
	var amount: float = s.crouch * _tri(t, 0.1, 0.07) + s.dive * _tri(t, R0, 0.07) + s.exit * _tri(t, R1 + 0.12, 0.07) + s.hop * (_tri(t, R.T.HOP1[1], 0.05) + _tri(t, R.T.HOP2[1], 0.05))
	RigMath.squash(pose, B.TORSO, 1.0 - pose.sy[B.TORSO] + amount)
	var w := clampf((t - R0) / (R1 - R0), 0.0, 1.0)
	var spin_speed := (_spin_at(minf(t + 0.005, R1)) - _spin_at(maxf(t - 0.005, R0))) / 0.01
	# The cloth trails the spin; played backwards it must trail the other way.
	var trail: float = spin_speed * R.T.juice.spinTrail * sin(PI * w) * (-1.0 if reverse else 1.0)
	pose.rot[B.SCARF1] -= deg_to_rad(trail)
	pose.rot[B.SCARF2] -= deg_to_rad(trail * 0.8)
	pose.rot[B.HAIR] -= deg_to_rad(trail * 0.4)
	var ts := t - R1
	if ts >= 0.0 and not reverse:
		var J: Dictionary = R.T.juice
		var spring: float = clampf((D - t) / 0.2, 0.0, 1.0) * J.springAmp * exp(-ts / J.springDecay) * sin(TAU * J.springFreq * ts)
		pose.rot[B.HAIR] += deg_to_rad(spring * 0.6)
		pose.rot[B.SCARF1] += deg_to_rad(spring)
		pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
		pose.rot[B.NECK] += deg_to_rad(spring * 0.2)


static func _tri(t: float, at: float, w: float) -> float:
	return clampf(1.0 - absf(t - at) / w, 0.0, 1.0)


## Body pose at JS time t (s) without horizontal root motion.
func _body(t: float, pose: RigPose, juice: bool) -> void:
	RigLocomotion.sample_idle(rig, pose, 0.0, juice)
	pose.x[B.HIP] += _tk("hipX", t)
	pose.y[B.HIP] += _tk("hipY", t)
	pose.rot[B.TORSO] += deg_to_rad(_tk("torso", t))
	pose.rot[B.NECK] += deg_to_rad(_tk("neck", t))
	pose.rot[B.UPPER_ARM_F] += deg_to_rad(_tk("armF", t))
	pose.rot[B.FORE_ARM_F] += deg_to_rad(_tk("elbowF", t))
	pose.rot[B.UPPER_ARM_B] += deg_to_rad(_tk("armB", t))
	pose.rot[B.FORE_ARM_B] += deg_to_rad(_tk("elbowB", t))
	pose.rot[B.HAIR] += deg_to_rad(_tk("hair", t))
	var scarf := _tk("scarf", t)
	pose.rot[B.SCARF1] += deg_to_rad(scarf)
	pose.rot[B.SCARF2] += deg_to_rad(scarf * 0.6)
	if juice:
		_juice_bones(t, pose)
	var lift := _hop_lift(t)
	var tuck := _tk("tuck", t)
	var hx := rig.bone_x[B.HIP] + pose.x[B.HIP]
	var hy := rig.bone_y[B.HIP] + pose.y[B.HIP]
	for side in ["front", "back"]:
		var f := "footF" if side == "front" else "footB"
		var angle := deg_to_rad(_tk(f + "2", t))
		var a := RigMath.planted_ankle(rest_x[side] + _tk(f + "0", t), -_tk(f + "1", t) - lift, angle)
		var tf: Array = R.T.tuckFeet[side]
		RigMath.solve_leg(rig, pose, side, lerpf(a.x, hx + tf[0], tuck), lerpf(a.y, hy + tf[1], tuck), lerpf(angle, deg_to_rad(tf[2]), tuck))
	var spin := _spin_at(t)
	if spin > 0.0 and spin < TAU:
		RigMath.spin_root(pose, spin, hx + R.T.pivotX, hy + R.T.pivotY)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
	var sw := _settle_weight(t)
	_settle(pose, sw)
	var h := _tk("hug", t)
	var p := _tk("plant", t)
	if h > 0.0 or p > 0.0:
		for i in rig.bone_count:
			fk[i] = pose.rot[i]
		RigMath.compute_world(rig, pose, world)
		if h > 0.0:
			var kf := Vector2(world[B.SHIN_F * 6 + 4], world[B.SHIN_F * 6 + 5])
			var af := Vector2(world[B.FOOT_F * 6 + 4], world[B.FOOT_F * 6 + 5])
			var kb := Vector2(world[B.SHIN_B * 6 + 4], world[B.SHIN_B * 6 + 5])
			var ab := Vector2(world[B.FOOT_B * 6 + 4], world[B.FOOT_B * 6 + 5])
			var ft := kf.lerp(af, 0.45)
			var bt := kb.lerp(ab, 0.35)
			RigMath.solve_arm(rig, pose, "front", ft.x, ft.y, world, true, 1.0)
			RigMath.solve_arm(rig, pose, "back", bt.x, bt.y, world, true, 1.0)
			for b in ARM_BONES:
				hug[b] = pose.rot[b]
		if p > 0.0:
			RigMath.solve_arm(rig, pose, "front", plant_x + R.T.plantSpread, -R.T.fistRadius, world, true, 1.0)
			RigMath.solve_arm(rig, pose, "back", plant_x - R.T.plantSpread, -R.T.fistRadius, world, true, 1.0)
		for b in ARM_BONES:
			pose.rot[b] = lerpf(lerpf(fk[b], hug[b], h), pose.rot[b], p)
		_settle(pose, sw)
	if sw > 0.0:
		_lift_cloth(pose)


func _lift_cloth(pose: RigPose) -> void:
	var step := deg_to_rad(R.T.clothStep)
	var depth := RigMath.lowest_point(rig, pose, world, CLOTH)
	var i := 0
	while i < 8 and depth > 0.0:
		var base := pose.rot[B.SCARF1]
		pose.rot[B.SCARF1] = base + step
		var up := RigMath.lowest_point(rig, pose, world, CLOTH)
		pose.rot[B.SCARF1] = base - step
		var down := RigMath.lowest_point(rig, pose, world, CLOTH)
		var dir := 1.0 if up < down else -1.0
		pose.rot[B.SCARF1] = base + dir * step
		pose.rot[B.SCARF2] += dir * step * 0.5
		depth = RigMath.lowest_point(rig, pose, world, CLOTH)
		i += 1


# Rolling without slipping: the center advances by (pivot height) * d(angle); the total is set
# by tuning because hands and feet carry part of the turn in place.
func _build_advance() -> void:
	advance.resize(STEPS + 1)
	advance[0] = 0.0
	for i in range(1, STEPS + 1):
		var t := R0 + (i - 0.5) / STEPS * (R1 - R0)
		_body(t, scratch, false)
		var height := -(scratch.root_y + scratch.pivot_y)
		var da := _spin_at(R0 + float(i) / STEPS * (R1 - R0)) - _spin_at(R0 + float(i - 1) / STEPS * (R1 - R0))
		advance[i] = advance[i - 1] + maxf(0.0, height) * da
	var total := advance[STEPS]
	no_slip_distance = total
	for i in STEPS + 1:
		advance[i] *= R.T.roll_distance / total


func _root_x(t: float) -> float:
	if t <= R0:
		return 0.0
	if t >= R1:
		return R.T.roll_distance
	var f := (t - R0) / (R1 - R0) * STEPS
	var i := mini(STEPS - 1, int(f))
	return lerpf(advance[i], advance[i + 1], f - i)


func root_motion(t: float) -> Vector2:
	if reverse:
		return Vector2(_root_x(_js_time(t)) - _root_x(_js_time(0.0)), 0.0)
	return Vector2(_root_x(_js_time(t)), 0.0)


func sample(t: float, pose: RigPose, juice: bool) -> void:
	var tj := _js_time(t)
	_body(tj, pose, juice)
	# Crossfade over a jump between timeline segments.
	var segs := _segments()
	for k in range(1, segs.size()):
		var cut_at: float = segs[k][0]
		if segs[k][2] != segs[k - 1][3] and t >= cut_at and t < cut_at + R.T.CUT_BLEND:
			_body(segs[k - 1][3], blend_pose, juice)
			blend_pose.blend_toward(pose, RigMath.smooth01((t - cut_at) / R.T.CUT_BLEND))
			pose.copy_from(blend_pose)
	pose.root_x = 0.0
	pose.facing = start_facing
	if juice and not reverse:
		var J: Dictionary = R.T.juice
		var ts := tj - R1
		if ts >= 0.0 and ts < J.exitSquashSeconds:
			var k: float = sin(PI * ts / J.exitSquashSeconds) * J.exitSquash
			pose.root_sy = 1.0 - k
			pose.root_sx = 1.0 + k * 0.6
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)


func _build_events() -> void:
	events.clear()
	var J: Dictionary = R.T.juice
	var contact := rig.bone_x[B.HIP] + R.T.pivotX + 34.0
	var feet_front: float = rest_x.front + 24.0 + RigData.FOOT_TOE
	var feet_back: float = rest_x.back + RigData.FOOT_TOE
	var mid := lerpf(R0, R1, 0.35)
	var late := lerpf(R0, R1, 0.7)
	if not reverse:
		events.append({"t": R.T.iframes[0], "signal": &"iframes_start"})
		events.append({"t": _at(R0), "signal": &"roll_contact"})
		events.append({"t": _at(R0), "fx": "dust", "x": feet_back, "y": 0.0, "params": _with(J.dust, "dir", -1)})
		events.append({"t": _at(mid), "fx": "dust", "x": contact, "y": 0.0, "params": _with(J.rollDust, "dir", -1)})
		events.append({"t": _at(late), "fx": "dust", "x": contact, "y": 0.0, "params": _with(J.rollDust, "dir", -1)})
		events.append({"t": _at(R1), "fx": "dust", "x": feet_front, "y": 0.0, "params": _with(J.dust, "dir", 1)})
		events.append({"t": _at(R1), "signal": &"roll_exit"})
		events.append({"t": R.T.iframes[1], "signal": &"iframes_end"})
		events.append({"t": _at(R1), "footstep": &"front", "strength": 0.7})
		events.append({"t": _at(1.56), "footstep": &"back", "strength": 0.35})
		events.append({"t": _at(1.6), "footstep": &"front", "strength": 0.35})
	else:
		events.append({"t": R.T.iframesBack[0], "signal": &"iframes_start"})
		events.append({"t": _at(R1), "signal": &"roll_contact"})
		events.append({"t": _at(R1), "fx": "dust", "x": feet_front, "y": 0.0, "params": _with(J.dust, "dir", 1)})
		events.append({"t": _at(late), "fx": "dust", "x": contact, "y": 0.0, "params": _with(J.rollDust, "dir", 1)})
		events.append({"t": _at(mid), "fx": "dust", "x": contact, "y": 0.0, "params": _with(J.rollDust, "dir", 1)})
		events.append({"t": _at(R0), "fx": "dust", "x": feet_back, "y": 0.0, "params": _with(J.dust, "dir", 1)})
		events.append({"t": _at(R0), "signal": &"roll_exit"})
		events.append({"t": R.T.iframesBack[1], "signal": &"iframes_end"})
		events.append({"t": duration, "footstep": &"front", "strength": 0.5})
	sort_events()


static func _with(d: Dictionary, key: String, value) -> Dictionary:
	var out := d.duplicate()
	out[key] = value
	return out
