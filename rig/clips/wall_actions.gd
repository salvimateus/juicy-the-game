class_name WallActions
extends RefCounted
## Wall grab (jolt into the slide) and wall jump (push off, turn away, takeoff).

const W := preload("res://rig/clips/wall_tuning.gd")


class Grab extends RigAction:
	var wall: RigWall
	var host_ref: WeakRef

	func _init(rig_data: RigData, wall_sampler: RigWall) -> void:
		super(rig_data)
		wall = wall_sampler
		id = &"wall_grab"
		duration = W.T.grab.duration
		next_state = "wall"
		events = [
			{"t": 0.0, "signal": &"grip"},
			{"t": 0.0, "custom": "contact"},
		]

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var G: Dictionary = W.T.grab
		var host = host_ref.get_ref()
		var k := t / duration
		var bounce: float = -G.bounce * sin(PI * minf(1.0, k * 1.6)) * (1.0 - k)
		wall.sample(pose, host.wall_speed, t, juice, bounce)
		if juice:
			var whip: float = G.whip * exp(-t / G.whipDecay) * cos(TAU * G.whipHz * t)
			pose.rot[RigBone.SCARF1] += deg_to_rad(whip)
			pose.rot[RigBone.SCARF2] -= deg_to_rad(whip * 1.3)
			var sq: float = G.squash * sin(PI * minf(1.0, k * 2.0))
			pose.root_sx = 1.0 - sq
			pose.root_sy = 1.0 + sq * 0.4
		pose.facing = start_facing

	func custom_event(_ev: Dictionary, host) -> void:
		host.wall_contact_fx(true)


class Jump extends RigAction:
	var wall: RigWall
	var air: RigPose
	var host_ref: WeakRef

	func _init(rig_data: RigData, wall_sampler: RigWall) -> void:
		super(rig_data)
		wall = wall_sampler
		air = RigPose.new(rig)
		id = &"wall_jump"
		var P: Dictionary = W.T.jump
		duration = P.duration
		events = [
			{"t": P.push, "signal": &"takeoff"},
			{"t": P.push, "custom": "contact"},
			{"t": P.flip, "flip": true},
			{"t": P.flip, "signal": &"flip"},
		]
		sort_events()

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)

	func facing_sign(t: float) -> int:
		return 1 if t < W.T.jump.flip else -1

	func root_motion(t: float) -> Vector2:
		var P: Dictionary = W.T.jump
		return Vector2(-P.away * RigMath.smooth01((t - P.coil) / (duration - P.coil)), 0.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var P: Dictionary = W.T.jump
		var host = host_ref.get_ref()
		var coil := RigMath.smooth01(t / P.coil) * (1.0 - RigMath.smooth01((t - P.coil) / (P.push - P.coil)))
		wall.sample(pose, host.wall_speed, t, juice, P.coilDip * coil, 6.0 * coil, P.coilHipX * coil)
		RigAir.sample_air(rig, air, P.airVy, 0.0, juice, t)
		pose.blend_toward(air, RigMath.smooth01((t - P.coil) / (duration - P.coil)))
		var turn: Array = P.turn
		if t > turn[0] and t < turn[1]:
			var s: float = (t - turn[0]) / (P.flip - turn[0]) if t < P.flip else (turn[1] - t) / (turn[1] - P.flip)
			pose.root_sx *= lerpf(1.0, P.turnWidth, s * s)
		if juice:
			var push := sin(PI * clampf((t - P.coil) / (duration - P.coil), 0.0, 1.0))
			pose.root_sy *= 1.0 + P.stretch * push
		pose.draw_order = 0
		pose.facing = start_facing * facing_sign(t)

	func custom_event(_ev: Dictionary, host) -> void:
		host.wall_contact_fx(true)
