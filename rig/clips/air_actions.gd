class_name AirActions
extends RefCounted
## Double jump and wall kick.

const A := preload("res://rig/clips/air_tuning.gd")
const B := preload("res://rig/rig_bone.gd")


class DoubleJump extends RigAction:
	var air: RigPose
	var world := PackedFloat32Array()

	func _init(rig_data: RigData) -> void:
		super(rig_data)
		id = &"double_jump"
		var P: Dictionary = A.T.doubleJump
		duration = P.duration
		air = RigPose.new(rig)
		world = RigMath.create_world(rig)
		events = [
			{"t": 0.0, "signal": &"takeoff"},
			{"t": 0.0, "fx": "dust", "anchor": "soleF", "params": P.puff},
			{"t": 0.0, "fx": "dust", "anchor": "soleB", "params": P.puff.merged({"count": 5})},
			{"t": P.kickEnd + 0.02, "fx": "ghost", "params": P.ghost},
		]

	func begin(host) -> void:
		start_facing = host.facing

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var P: Dictionary = A.T.doubleJump
		var K: Dictionary = P.kick
		var U: Dictionary = P.tuck
		RigAir.sample_air(rig, pose, P.openVy, 0.0, juice, t)
		# Weights: kick pose, then tuck, then open back to the air pose.
		var kick := 1.0 - RigMath.smooth01((t - P.kickEnd * 0.5) / P.kickEnd)
		var tuck := RigMath.smooth01((t - P.kickEnd * 0.6) / (P.kickEnd * 0.8)) * (1.0 - RigMath.smooth01((t - (P.flipEnd - 0.05)) / (P.duration - P.flipEnd + 0.05)))
		for side in ["front", "back"]:
			var leg: RigData.Leg = rig.legs[side]
			var kt := deg_to_rad(K.thigh)
			var ks := deg_to_rad(K.shin)
			var tt := deg_to_rad(U.thighF if side == "front" else U.thighB)
			var ts := deg_to_rad(U.shinF if side == "front" else U.shinB)
			var th := lerpf(lerpf(pose.rot[leg.thigh], kt, kick), tt, tuck)
			var sh := lerpf(lerpf(pose.rot[leg.shin], ks, kick), ts, tuck)
			var fa := lerpf(deg_to_rad(K.footAbs), deg_to_rad(U.footAbs), tuck)
			pose.rot[leg.thigh] = th
			pose.rot[leg.shin] = sh
			pose.rot[leg.foot] = fa - th - sh
		var O: Dictionary = P.open
		pose.rot[B.UPPER_ARM_F] = lerp_angle(deg_to_rad(O.armF), deg_to_rad(K.armF), kick)
		pose.rot[B.UPPER_ARM_B] = lerp_angle(deg_to_rad(O.armB), deg_to_rad(K.armB), kick)
		pose.rot[B.FORE_ARM_F] = lerp_angle(deg_to_rad(O.foreF), deg_to_rad(K.fore), kick)
		pose.rot[B.FORE_ARM_B] = lerp_angle(deg_to_rad(O.foreB), deg_to_rad(K.fore), kick)
		pose.rot[B.TORSO] = lerpf(pose.rot[B.TORSO], deg_to_rad(U.lean), tuck)
		pose.rot[B.NECK] = lerpf(pose.rot[B.NECK], deg_to_rad(U.neck), tuck)
		pose.facing = start_facing
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		# Fists hug the shins while tucked.
		if tuck > 0.01:
			var hug := tuck * tuck * (3.0 - 2.0 * tuck)
			var fk := [pose.rot[B.UPPER_ARM_F], pose.rot[B.FORE_ARM_F], pose.rot[B.UPPER_ARM_B], pose.rot[B.FORE_ARM_B]]
			var saved_facing := pose.facing
			pose.facing = 1
			RigMath.compute_world(rig, pose, world)
			var kf := RigMath.point(world, B.SHIN_F, 0, 0).lerp(RigMath.point(world, B.FOOT_F, 0, 0), 0.45)
			var kb := RigMath.point(world, B.SHIN_B, 0, 0).lerp(RigMath.point(world, B.FOOT_B, 0, 0), 0.35)
			RigMath.solve_arm(rig, pose, "front", kf.x, kf.y, world, true, 1.0)
			RigMath.solve_arm(rig, pose, "back", kb.x, kb.y, world, true, 1.0)
			pose.facing = saved_facing
			pose.rot[B.UPPER_ARM_F] = lerp_angle(fk[0], pose.rot[B.UPPER_ARM_F], hug)
			pose.rot[B.FORE_ARM_F] = lerp_angle(fk[1], pose.rot[B.FORE_ARM_F], hug)
			pose.rot[B.UPPER_ARM_B] = lerp_angle(fk[2], pose.rot[B.UPPER_ARM_B], hug)
			pose.rot[B.FORE_ARM_B] = lerp_angle(fk[3], pose.rot[B.FORE_ARM_B], hug)
		# Forward flip around the ball's center.
		var s := RigMath.smooth01((t - P.kickEnd) / (P.flipEnd - P.kickEnd))
		if s > 0.0 and s < 1.0:
			var piv: Array = P.pivot
			var hx := rig.bone_x[B.HIP] + pose.x[B.HIP]
			var hy := rig.bone_y[B.HIP] + pose.y[B.HIP]
			RigMath.spin_root(pose, TAU * s, hx + piv[0], hy + piv[1])
		if juice:
			var st: float = K.stretch * (1.0 - RigMath.smooth01(t / P.kickEnd))
			pose.root_sy = 1.0 + st
			pose.root_sx = 1.0 - st * 0.6


class WallKick extends RigAction:
	var wall: RigWall
	var air: RigPose
	var host_ref: WeakRef

	func _init(rig_data: RigData, wall_sampler: RigWall) -> void:
		super(rig_data)
		wall = wall_sampler
		air = RigPose.new(rig)
		id = &"wall_kick"
		var P: Dictionary = A.T.wallKick
		duration = P.duration
		events = [
			{"t": P.push, "signal": &"takeoff"},
			{"t": P.push, "custom": "contact"},
		]

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)

	func root_motion(t: float) -> Vector2:
		var P: Dictionary = A.T.wallKick
		return Vector2(-P.away * RigMath.smooth01(t / duration), 0.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var P: Dictionary = A.T.wallKick
		var host = host_ref.get_ref()
		var coil := 1.0 - RigMath.smooth01(t / P.push)
		wall.sample(pose, host.wall_speed, t, juice, 10.0 * coil)
		RigAir.sample_air(rig, air, P.airVy, 0.0, juice, t)
		pose.blend_toward(air, RigMath.smooth01((t - P.push * 0.5) / (duration - P.push * 0.5)))
		if juice:
			pose.root_sy *= 1.0 + P.stretch * sin(PI * clampf(t / duration, 0.0, 1.0))
		pose.draw_order = 0
		pose.facing = start_facing

	func custom_event(_ev: Dictionary, host) -> void:
		host.wall_contact_fx(true)
