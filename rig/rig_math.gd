class_name RigMath
extends RefCounted
## Pose evaluation: forward kinematics, IK and pose helpers. Pure math, no nodes.

const SETTLE_IGNORE := ["scarfTail", "scarfMid", "hair"]


static func create_world(rig: RigData) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(rig.bone_count * 6)
	return w


## World affine per bone [a, b, c, d, e, f] in character space at stride 6
## (x' = a x + c y + e, y' = b x + d y + f).
static func compute_world(rig: RigData, pose: RigPose, out: PackedFloat32Array) -> PackedFloat32Array:
	var rc := cos(pose.root_rot)
	var rs := sin(pose.root_rot)
	var fx := -1.0 if pose.facing < 0 else 1.0
	var ra := fx * rc * pose.root_sx
	var rb := rs * pose.root_sx
	var rcc := -fx * rs * pose.root_sy
	var rd := rc * pose.root_sy
	var re := pose.root_x + fx * (pose.pivot_x - (rc * pose.pivot_x - rs * pose.pivot_y))
	var rf := pose.root_y + pose.pivot_y - (rs * pose.pivot_x + rc * pose.pivot_y)
	var parents := rig.parent
	for i in rig.bone_count:
		var r := pose.rot[i] + rig.rest_rot[i] + pose.hammer * rig.hammer_angle[i]
		var cs := cos(r)
		var sn := sin(r)
		var bsx := pose.sx[i]
		var bsy := pose.sy[i]
		var la := cs * bsx
		var lb := sn * bsx
		var lc := -sn * bsy
		var ld := cs * bsy
		var lx := rig.bone_x[i] + pose.x[i]
		var ly := rig.bone_y[i] + pose.y[i]
		var a := ra
		var b := rb
		var c := rcc
		var d := rd
		var e := re
		var f := rf
		var p := parents[i]
		if p >= 0:
			p *= 6
			a = out[p]
			b = out[p + 1]
			c = out[p + 2]
			d = out[p + 3]
			e = out[p + 4]
			f = out[p + 5]
		var o := i * 6
		out[o] = a * la + c * lb
		out[o + 1] = b * la + d * lb
		out[o + 2] = a * lc + c * ld
		out[o + 3] = b * lc + d * ld
		out[o + 4] = a * lx + c * ly + e
		out[o + 5] = b * lx + d * ly + f
	return out


static func point(world: PackedFloat32Array, bone: int, lx: float, ly: float) -> Vector2:
	var o := bone * 6
	return Vector2(world[o] * lx + world[o + 2] * ly + world[o + 4], world[o + 1] * lx + world[o + 3] * ly + world[o + 5])


static func anchor_point(rig: RigData, world: PackedFloat32Array, name: String) -> Vector2:
	var a := rig.anchor(name)
	return point(world, int(a.x), a.y, a.z)


static func bone_angle(world: PackedFloat32Array, bone: int) -> float:
	return atan2(world[bone * 6 + 1], world[bone * 6])


## Knee caps take half the knee bend and the waist follows part of the torso lean; clips call
## this last, after every leg and torso write.
static func derive_bones(rig: RigData, pose: RigPose, waist_follow: float) -> void:
	for side in rig.legs:
		var leg: RigData.Leg = rig.legs[side]
		pose.rot[leg.cap] = pose.rot[leg.shin] * 0.5
	pose.rot[rig.waist] = pose.rot[rig.torso] * waist_follow


## Ankle for a boot on the ground rolled by angle around the heel (negative, toe up) or the toe
## (positive, heel up); contact_x is the ankle x with the boot flat.
static func planted_ankle(contact_x: float, ground_y: float, angle: float) -> Vector2:
	var cs := cos(angle)
	var sn := sin(angle)
	var pivot := contact_x + (RigData.FOOT_HEEL if angle < 0.0 else (RigData.FOOT_TOE if angle > 0.0 else 0.0))
	var dx := contact_x - pivot
	var dy := -RigData.FOOT_ANKLE_HEIGHT
	return Vector2(pivot + dx * cs - dy * sn, ground_y + dx * sn + dy * cs)


## Two-bone leg IK, knee forward (+x). Targets are in character space before the root transform;
## hip rotation is not compensated. foot_angle is the boot's absolute angle.
static func solve_leg(rig: RigData, pose: RigPose, side: String, ankle_x: float, ankle_y: float, foot_angle: float) -> void:
	var leg: RigData.Leg = rig.legs[side]
	var jx := rig.bone_x[0] + pose.x[0] + leg.hip_x
	var jy := rig.bone_y[0] + pose.y[0] + leg.hip_y
	var dx := ankle_x - jx
	var dy := ankle_y - jy
	var l1 := leg.upper
	var l2 := leg.lower
	var dist := clampf(sqrt(dx * dx + dy * dy), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var to_target := atan2(-dx, dy)
	var hip_bend := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var knee_inner := acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	var thigh_dir := to_target - hip_bend
	var shin_dir := thigh_dir + (PI - knee_inner)
	var thigh_rot := thigh_dir - leg.upper_angle
	var shin_rot := shin_dir - leg.lower_angle - thigh_rot
	pose.rot[leg.thigh] = thigh_rot
	pose.rot[leg.shin] = shin_rot
	pose.rot[leg.foot] = foot_angle - thigh_rot - shin_rot


## Both feet planted at their rest ankles (shifted by offset_x); legs follow the hip.
static func plant_legs(rig: RigData, pose: RigPose, offset_x := 0.0) -> void:
	for side in ["front", "back"]:
		solve_leg(rig, pose, side, rig.rest_ankle_x(side) + offset_x, -RigData.FOOT_ANKLE_HEIGHT, 0.0)


## Cyclic gait for one leg: u in [0, 1), stance for the first g.duty then swing. During stance the
## contact moves back by g.stride at constant speed (ground speed stride / duty per cycle).
static func gait_leg(rig: RigData, pose: RigPose, side: String, u: float, g: RigGait) -> void:
	var base_x := g.center_x + g.reach_x
	var half := g.stride * 0.5
	if u < g.duty:
		var s := u / g.duty
		var roll := _stance_roll(s, g)
		var a := planted_ankle(base_x + half - g.stride * s, 0.0, roll)
		solve_leg(rig, pose, side, a.x, a.y, roll)
		return
	var w := (u - g.duty) / (1.0 - g.duty)
	var from := planted_ankle(base_x - half, 0.0, g.toe_angle)
	var to := planted_ankle(base_x + half, 0.0, -g.heel_angle)
	var e := smoothstep(0.0, 1.0, w)
	var lift := sin(PI * pow(w, g.lift_bias)) * g.lift
	var x := lerpf(from.x, to.x, e) - sin(PI * w) * g.kick_back * (1.0 - w)
	var y := lerpf(from.y, to.y, e) - lift
	var angle := lerpf(g.toe_angle, -g.heel_angle, e) + sin(PI * w) * g.swing_toe
	solve_leg(rig, pose, side, x, y, angle)


static func _stance_roll(s: float, g: RigGait) -> float:
	if s < g.heel_phase:
		var k := 1.0 - s / g.heel_phase
		return -g.heel_angle * k * k
	var toe_start := 1.0 - g.toe_phase
	if s > toe_start:
		var k := (s - toe_start) / g.toe_phase
		return g.toe_angle * k * k
	return 0.0


## Squash (amount > 0) or stretch (< 0) a bone and its children, keeping rough volume.
static func squash(pose: RigPose, bone: int, amount: float) -> void:
	pose.sy[bone] = 1.0 - amount
	pose.sx[bone] = 1.0 + amount * 0.7


static func spin_root(pose: RigPose, angle: float, px: float, py: float) -> void:
	pose.root_rot = angle
	pose.pivot_x = px
	pose.pivot_y = py


## Lowest transformed corner of the visible parts' opaque boxes (honoring props and hide bits).
static func lowest_point(rig: RigData, pose: RigPose, world: PackedFloat32Array, only := PackedStringArray()) -> float:
	compute_world(rig, pose, world)
	var max_y := -INF
	for part in rig.parts:
		if not part.has_box:
			continue
		if only.is_empty():
			if SETTLE_IGNORE.has(part.name):
				continue
		elif not only.has(part.name):
			continue
		if part.prop_bit != 0 and (pose.props & part.prop_bit) == 0:
			continue
		if part.hide_bit != 0 and (pose.props & part.hide_bit) != 0:
			continue
		var o := part.bone * 6
		var b := part.box
		for k in 4:
			var px := b.end.x if k & 1 else b.position.x
			var py := b.end.y if k & 2 else b.position.y
			var wy := world[o + 1] * px + world[o + 3] * py + world[o + 5]
			if wy > max_y:
				max_y = wy
	return max_y


## Shifts root_y so the lowest opaque pixel touches y = 0 and returns that lowest point.
static func settle_on_ground(rig: RigData, pose: RigPose, world: PackedFloat32Array) -> float:
	var max_y := lowest_point(rig, pose, world)
	if max_y > -INF:
		pose.root_y -= max_y
	return max_y


## Two-bone arm IK putting the wrist (or the fist with reach_fist) on a target in final character
## space (after root and facing). bend 1 flexes the elbow the anatomical way (forearm folding toward
## the front of the upper arm, elbow down/back); -1 is the mirrored solution, a hyperextended elbow.
static func solve_arm(rig: RigData, pose: RigPose, side: String, tx: float, ty: float, world: PackedFloat32Array, reach_fist := false, bend := 1.0) -> void:
	var upper: int = rig.index["upperArmF" if side == "front" else "upperArmB"]
	var fore := upper + 1
	var hand := upper + 2
	compute_world(rig, pose, world)
	var p := rig.parent[upper] * 6
	var a := world[p]
	var b := world[p + 1]
	var c := world[p + 2]
	var d := world[p + 3]
	var det := a * d - b * c
	var dx0 := tx - world[p + 4]
	var dy0 := ty - world[p + 5]
	var lx := (d * dx0 - c * dy0) / det
	var ly := (-b * dx0 + a * dy0) / det
	var shx := rig.bone_x[upper] + pose.x[upper]
	var shy := rig.bone_y[upper] + pose.y[upper]
	var l1 := Vector2(rig.bone_x[fore], rig.bone_y[fore]).length()
	var l2 := Vector2(rig.bone_x[hand], rig.bone_y[hand]).length()
	if reach_fist:
		l2 += rig.anchor("fistF" if side == "front" else "fistB").z
	var dx := lx - shx
	var dy := ly - shy
	var dist := clampf(sqrt(dx * dx + dy * dy), absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var to_target := atan2(-dx, dy)
	var shoulder := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var inner := acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	pose.rot[upper] = to_target + bend * shoulder
	pose.rot[fore] = -bend * (PI - inner)
	if reach_fist:
		pose.rot[hand] = 0.0


static func wave(u: float, cycles := 1.0, phase := 0.0) -> float:
	return sin(TAU * (u * cycles - phase))


static func smooth01(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func frac(v: float) -> float:
	return v - floorf(v)


static func hash01(a: int, b: int) -> float:
	var x := (a * 374761393 + b * 668265263) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 1274126177) & 0xFFFFFFFF
	x ^= x >> 16
	return float(x) / 4294967296.0
