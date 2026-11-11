class_name LedgeActions
extends RefCounted
## Ledge actions (grab, climb, descend, drop, leap). Each works in ledge space through RigLedge and
## converts its FX points from L to the Adventurer's local space at the event time.

const L := preload("res://rig/clips/ledge_tuning.gd")


static func create(rig: RigData, ledge: RigLedge) -> Dictionary:
	return {
		&"ledge_grab": Grab.new(rig, ledge),
		&"ledge_climb": Climb.new(rig, ledge, false),
		&"ledge_descend": Climb.new(rig, ledge, true),
		&"ledge_drop": Drop.new(rig, ledge),
		&"ledge_leap": Leap.new(rig, ledge),
	}


## L point to the Adventurer's local space for an origin in L and a facing.
static func to_local(p: Vector2, origin: Vector2, facing: int) -> Vector2:
	return Vector2((p.x - origin.x) * facing, p.y - origin.y)


class Base extends RigAction:
	var ledge: RigLedge
	var catch_age0 := 0.0
	var catch_k := 1.0

	func _init(rig_data: RigData, ledge_sampler: RigLedge) -> void:
		super(rig_data)
		ledge = ledge_sampler

	func begin(host) -> void:
		start_facing = host.facing
		catch_age0 = host.hang_catch_age
		catch_k = host.catch_k

	func origin_at(_t: float) -> Vector2:
		return ledge.hang_origin

	func custom_event(ev: Dictionary, host) -> void:
		if ev.custom == "fx":
			var local := LedgeActions.to_local(ev.at, origin_at(ev.t), start_facing)
			host.spawn_fx_local(ev.type, ev.params, local, ev.get("ground", false))


class Grab extends Base:
	func _init(rig_data: RigData, ledge_sampler: RigLedge) -> void:
		super(rig_data, ledge_sampler)
		id = &"ledge_grab"
		duration = ledge.D - ledge.tG
		next_state = "hanging"
		var J: Dictionary = L.T.juice
		var gx: float = (L.T.grip.front.x + L.T.grip.back.x) * 0.5
		events = [
			{"t": 0.0, "signal": &"grip"},
			{"t": 0.0, "custom": "fx", "type": "ledgeDebris", "at": Vector2(-6, 4), "params": J.debrisGrab.merged({"dir": -1})},
			{"t": 0.0, "custom": "fx", "type": "ledgeDust", "at": Vector2(gx + 6, -4), "params": J.gripPuff},
		]

	func begin(host) -> void:
		super(host)
		var J: Dictionary = L.T.juice
		catch_k = clampf(host.incoming_speed() / J.catchSpeed, J.catchMin, J.catchMax)
		host.catch_k = catch_k

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		ledge.sample(pose, ledge.tG + t, t, catch_k, ledge.hang_origin, start_facing, juice, rig_time(t))

	func rig_time(t: float) -> float:
		return t


class Climb extends Base:
	var reverse := false
	var speed := 1.0
	var from_t := 0.0

	func _init(rig_data: RigData, ledge_sampler: RigLedge, backward: bool) -> void:
		super(rig_data, ledge_sampler)
		reverse = backward
		var J: Dictionary = L.T.juice
		var F: Dictionary = L.T.feet
		if reverse:
			id = &"ledge_descend"
			speed = L.T.descendSpeed
			duration = (ledge.tS - ledge.tA) / speed
			next_state = "hanging"
			events = [
				{"t": _at(ledge.tS - 0.05), "custom": "fx", "type": "ledgeDust", "at": Vector2((F.standFront + F.standBack) * 0.5, 0), "params": J.gripPuff},
				{"t": _at(ledge.tK + 0.12), "signal": &"grip"},
				{"t": _at(ledge.tK), "custom": "fx", "type": "ledgeDebris", "at": Vector2(-4, 4), "params": J.debrisClimb.merged({"dir": -1})},
				{"t": _at(ledge.tP + 0.1), "custom": "fx", "type": "ledgeDebris", "at": Vector2(-6, 6), "params": J.debrisClimb.merged({"dir": -1, "count": 4})},
			]
		else:
			id = &"ledge_climb"
			speed = L.T.climbSpeed
			max_turn = L.T.climbMaxTurn
			duration = (ledge.tS + L.T.climbEnd - ledge.tA) / speed
			events = [
				{"t": _at(ledge.tP), "signal": &"pull"},
				{"t": _at(ledge.tP + 0.1), "custom": "fx", "type": "ledgeDebris", "at": Vector2(-6, 6), "params": J.debrisClimb.merged({"dir": -1, "count": 4})},
				{"t": _at(ledge.tK), "custom": "fx", "type": "ledgeDebris", "at": Vector2(-4, 4), "params": J.debrisClimb.merged({"dir": -1})},
				{"t": _at(ledge.tK), "custom": "fx", "type": "ledgeDust", "at": Vector2(F.stepUp + 10, 0), "params": J.gripPuff},
				{"t": _at(ledge.tK), "footstep": &"front", "strength": 0.4},
				{"t": _at(ledge.tS), "custom": "fx", "type": "dust", "at": Vector2((F.standFront + F.standBack) * 0.5 + 8, 0), "params": J.dust, "ground": true},
				{"t": _at(ledge.tS), "footstep": &"back", "strength": 0.5},
				{"t": _at(ledge.tS), "signal": &"on_top"},
			]
		sort_events()

	## Action time of a ledge time.
	func _at(lt: float) -> float:
		return (ledge.tS - lt) / speed if reverse else (lt - ledge.tA) / speed

	func ledge_time(t: float) -> float:
		return ledge.tS - t * speed if reverse else ledge.tA + t * speed

	func begin(host) -> void:
		super(host)
		if reverse:
			catch_age0 = L.T.descendCatchAge - duration
			catch_k = 0.4

	func origin_at(t: float) -> Vector2:
		return ledge.origin_at(ledge_time(t))

	func root_motion(t: float) -> Vector2:
		var start := ledge.top_origin if reverse else ledge.hang_origin
		return origin_at(t) - start

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var lt := ledge_time(t)
		ledge.sample(pose, lt, catch_age0 + t, catch_k, ledge.origin_at(lt), start_facing, juice, lt)


class Drop extends Base:
	var air: RigPose

	func _init(rig_data: RigData, ledge_sampler: RigLedge) -> void:
		super(rig_data, ledge_sampler)
		id = &"ledge_drop"
		duration = L.T.drop.duration
		air = RigPose.new(rig)

	func root_motion(t: float) -> Vector2:
		return Vector2(-L.T.drop.away * RigMath.smooth01(t / duration), 0.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		ledge.sample(pose, 0.0, catch_age0 + t, catch_k, ledge.hang_origin, 1, juice, t)
		pose.root_x = -ledge.hang_origin.x
		RigAir.sample_air(rig, air, L.T.drop.airVy, 0.0, juice, t)
		pose.blend_toward(air, RigMath.smooth01(t / duration))
		pose.draw_order = 1 if t < duration * 0.5 else 0
		RigLedge.finish_facing(pose, start_facing)


## Leap away from the wall: coil against it, push (takeoff), turn around in the air (flip).
class Leap extends Base:
	var air: RigPose

	func _init(rig_data: RigData, ledge_sampler: RigLedge) -> void:
		super(rig_data, ledge_sampler)
		id = &"ledge_leap"
		var P: Dictionary = L.T.leap
		duration = P.duration
		air = RigPose.new(rig)
		events = [
			{"t": P.push, "signal": &"takeoff"},
			{"t": P.push, "custom": "fx", "type": "ledgeDebris", "at": Vector2(-4, 8), "params": L.T.juice.debrisClimb.merged({"dir": -1, "count": 5})},
			{"t": P.push, "custom": "fx", "type": "ledgeDust", "at": Vector2(-4, 160), "params": L.T.juice.gripPuff},
			{"t": P.flip, "flip": true},
			{"t": P.flip, "signal": &"flip"},
		]
		sort_events()

	func root_motion(t: float) -> Vector2:
		var P: Dictionary = L.T.leap
		return Vector2(-P.away * RigMath.smooth01((t - P.coil) / (duration - P.coil)), 0.0)

	func facing_sign(t: float) -> int:
		return 1 if t < L.T.leap.flip else -1

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var P: Dictionary = L.T.leap
		var coil := RigMath.smooth01(t / P.coil) * (1.0 - RigMath.smooth01((t - P.coil) / (P.push - P.coil)))
		ledge.sample(pose, 0.0, catch_age0 + t, catch_k, ledge.hang_origin, 1, juice, t, P.coilTuck * coil, P.coilHipX * coil)
		pose.root_x = -ledge.hang_origin.x
		# Air pose mirrored back into the wall-facing frame until the flip.
		RigAir.sample_air(rig, air, P.airVy, 0.0, juice, t)
		var w := RigMath.smooth01((t - P.coil) / (duration - P.coil))
		pose.blend_toward(air, w)
		var turn: Array = P.turn
		if t > turn[0] and t < turn[1]:
			var s: float = (t - turn[0]) / (P.flip - turn[0]) if t < P.flip else (turn[1] - t) / (turn[1] - P.flip)
			pose.root_sx *= lerpf(1.0, P.turnWidth, s * s)
		pose.draw_order = 1 if t < P.push else 0
		RigLedge.finish_facing(pose, start_facing * facing_sign(t))
