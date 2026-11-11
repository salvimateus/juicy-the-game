class_name SwimActions
extends RefCounted
## Swimming provider: the swimmer for Adventurer.set_swim (RigSwim), the water_exit action
## (lunge to the bank corner, then the ledge climb) and pose sheet previews.

const S := preload("res://rig/clips/swim_tuning.gd")
const L := preload("res://rig/clips/ledge_tuning.gd")

## Water line relative to the origin while treading and swimming the crawl (y down): the game
## keeps the body so the water surface sits here.
const WATER_LINE_TREAD: float = S.T.waterLineTread
const WATER_LINE_SURFACE: float = S.T.waterLineSurface
## Center of mass relative to the origin in every swim mode; the body rotates around it.
const SWIM_CENTER := Vector2(S.T.com[0], S.T.com[1])
## Default bank corner relative to the origin when water_exit starts (facing 1, x toward the bank).
const WATER_EXIT_CORNER := Vector2(S.T.exit.corner[0], S.T.exit.corner[1])


static func create(rig: RigData) -> Dictionary:
	var ledge := RigLedge.new(rig)
	var out := {&"water_exit": WaterExit.new(rig, ledge)}
	var previews := [
		[&"swim_tread_preview", &"tread", Vector2.ZERO, 1.15],
		[&"swim_surface_slow_preview", &"surface", Vector2(200, 0), 1.65],
		[&"swim_surface_fast_preview", &"surface", Vector2(420, 0), 0.786],
		[&"swim_under_right_preview", &"under", Vector2(320, 0), 1.25],
		[&"swim_under_diagonal_preview", &"under", Vector2(240, 240), 1.25],
		[&"swim_under_down_preview", &"under", Vector2(0, 320), 1.25],
		[&"swim_under_up_preview", &"under", Vector2(0, -320), 1.25],
		[&"swim_under_idle_preview", &"under_idle", Vector2.ZERO, 2.8],
	]
	for p in previews:
		out[p[0]] = Preview.new(rig, p[0], p[1], p[2], p[3])
	# Transitions: a dive from the crawl, an underwater turn, surfacing into tread.
	out[&"swim_dive_preview"] = Preview.new(rig, &"swim_dive_preview", &"under", Vector2(160, 300), 1.0, &"surface", Vector2(300, 0))
	out[&"swim_turn_preview"] = Preview.new(rig, &"swim_turn_preview", &"under", Vector2(-320, 0), 1.0, &"under", Vector2(320, 0), -1)
	out[&"swim_surface_turn_preview"] = Preview.new(rig, &"swim_surface_turn_preview", &"surface", Vector2(-300, 0), 1.0, &"surface", Vector2(300, 0), -1)
	out[&"swim_surfacing_preview"] = Preview.new(rig, &"swim_surfacing_preview", &"tread", Vector2.ZERO, 1.0, &"under", Vector2(0, -300))
	return out


static func create_swimmer(rig: RigData) -> Object:
	return RigSwim.new(rig)


static func draw_orders() -> Dictionary:
	# Near horizontal the near arm reaches past the head, so it draws over it; the far arm stays
	# behind the body.
	return {RigSwim.ORDER_HORIZONTAL: [["foreArmF", "after", "head"], ["handF", "after", "foreArmF"], ["upperArmF", "after", "handF"]]}


## Out of the river onto the bank: from the current swim pose the body lunges up and grabs the
## corner (the RigLedge hang at ANTICIPATION_T), then plays ledge_climb at its game speed.
## Start: the bank corner at origin + corner (facing 1 mirrored by facing), corner taken from
## action_params[&"water_exit_corner"] when set, else WATER_EXIT_CORNER. Total root motion:
## corner + Adventurer.LEDGE_TOP_OFFSET.
class WaterExit extends RigAction:
	var ledge: RigLedge
	var reach := 0.0
	var speed := 1.0
	var corner := Vector2.ZERO
	var start: RigPose
	var tmp: RigPose
	var water_y := 0.0
	var drips: Dictionary
	var splash: Dictionary

	func _init(rig_data: RigData, ledge_sampler: RigLedge) -> void:
		super(rig_data)
		ledge = ledge_sampler
		id = &"water_exit"
		var E: Dictionary = S.T.exit
		reach = E.reach
		speed = L.T.climbSpeed
		max_turn = E.maxTurn
		duration = reach + (ledge.tS + L.T.climbEnd - ledge.tA) / speed
		corner = Vector2(E.corner[0], E.corner[1])
		start = RigPose.new(rig)
		tmp = RigPose.new(rig)
		var J: Dictionary = S.T.juice
		splash = J.exitSplash.merged({"emit": RigSwim.emit_splash})
		drips = J.exitDrips.merged({"emit": RigSwim.emit_drips})
		var F: Dictionary = L.T.feet
		events = [
			{"t": 0.0, "custom": "splash", "x": 40.0},
			{"t": reach * 0.6, "custom": "drip", "anchor": "fistF"},
			{"t": reach, "signal": &"grip"},
			{"t": _at(ledge.tP), "signal": &"pull"},
			{"t": _at(ledge.tP + 0.05), "custom": "splash", "x": -20.0},
			{"t": _at(ledge.tC), "custom": "drip", "anchor": "chest"},
			{"t": _at(ledge.tC + 0.15), "custom": "drip", "anchor": "soleB"},
			{"t": _at(ledge.tK), "custom": "drip", "anchor": "soleF"},
			{"t": _at(ledge.tK), "footstep": &"front", "strength": 0.4},
			{"t": _at(ledge.tK), "custom": "dust", "at": Vector2(F.stepUp + 10, 0), "params": L.T.juice.gripPuff},
			{"t": _at(ledge.tS), "footstep": &"back", "strength": 0.5},
			{"t": _at(ledge.tS), "custom": "dust", "at": Vector2((F.standFront + F.standBack) * 0.5 + 8, 0), "params": L.T.juice.dust, "ground": true},
			{"t": _at(ledge.tS), "signal": &"on_top"},
		]
		sort_events()

	## Action time of a ledge time in the climb part.
	func _at(lt: float) -> float:
		return reach + (lt - ledge.tA) / speed

	## Pose sheet: start from a settled tread.
	func sheet_setup(adv) -> void:
		for i in 120:
			adv.set_swim(&"tread", Vector2.ZERO, 1.0 / 120.0)
			adv.set_locomotion(0.0, 1.0 / 120.0)

	func begin(host) -> void:
		start_facing = host.facing
		var E: Dictionary = S.T.exit
		var c = host.action_params.get(&"water_exit_corner")
		corner = Vector2(E.corner[0], E.corner[1])
		if c is Vector2:
			corner = Vector2(clampf(c.x, E.cornerMin[0], E.cornerMax[0]), clampf(c.y, E.cornerMin[1], E.cornerMax[1]))
		start.copy_from(host.pose)
		water_y = host.global_position.y + WATER_LINE_TREAD

	## Origin in ledge space L (corner at 0, facing +x) at action time t.
	func origin_l(t: float) -> Vector2:
		if t < reach:
			var k := RigMath.smooth01(t / reach)
			return (-corner).lerp(ledge.hang_origin, k)
		return ledge.origin_at(_ledge_t(t))

	func _ledge_t(t: float) -> float:
		return ledge.tA + maxf(0.0, t - reach) * speed

	func root_motion(t: float) -> Vector2:
		return origin_l(t) + corner

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var catch_age := t - reach if t >= reach else -1.0
		var k: float = S.T.exit.catchK
		var lt := _ledge_t(t)
		ledge.sample(pose, lt, catch_age, k, origin_l(t), start_facing, juice, lt)
		if t >= reach:
			return
		# Lunge: the swim pose stays where it was while the origin moves, blended into the hang.
		tmp.copy_from(start)
		var rm := root_motion(t)
		tmp.root_x -= rm.x * start_facing
		tmp.root_y -= rm.y
		var w := RigMath.smooth01(t / reach)
		RigSwim.blend(tmp, pose, w)
		pose.copy_from(tmp)

	func custom_event(ev: Dictionary, host) -> void:
		if not host.juice:
			return
		var origin: Vector2 = host.global_position
		match ev.custom:
			"splash":
				if host.rig.fx_sprites.has("swimDrop"):
					host.fx.spawn("custom", splash, origin.x + ev.x * start_facing, water_y, 0.0, start_facing, water_y, host.now())
			"drip":
				if host.rig.fx_sprites.has("swimDrop"):
					var p: Vector2 = host.anchor_world(ev.anchor)
					host.fx.spawn("custom", drips, p.x, p.y, 0.0, start_facing, water_y, host.now())
			"dust":
				var local := LedgeActions.to_local(ev.at, origin_l(ev.t), start_facing)
				host.spawn_fx_local("dust" if ev.get("ground", false) else "ledgeDust", ev.params, local, ev.get("ground", false))


## Pose sheet helper (not for gameplay): drives its own swimmer in a mode at a fixed velocity,
## after a warm-up (optionally in another mode, for transitions).
class Preview extends RigAction:
	var swimmer: RigSwim
	var mode: StringName
	var velocity := Vector2.ZERO
	var warm_mode: StringName
	var warm_velocity := Vector2.ZERO
	var turn_to := 0
	var host_ref: WeakRef
	var sheet_duration := 1.0

	func _init(rig_data: RigData, action_id: StringName, m: StringName, v: Vector2, span: float, wm: StringName = &"", wv := Vector2.ZERO, turn := 0) -> void:
		super(rig_data)
		id = action_id
		mode = m
		velocity = v
		warm_mode = wm if wm != &"" else m
		warm_velocity = wv if wm != &"" else v
		turn_to = turn
		sheet_duration = span
		duration = span + 0.1
		swimmer = RigSwim.new(rig)

	func sheet_setup(adv) -> void:
		swimmer.has_out = false
		swimmer.quiet = true
		swimmer.target_facing = 0
		swimmer.last_now = -100.0
		var vx := warm_velocity.x if warm_velocity.x != 0.0 else velocity.x
		adv.facing = -1 if vx < 0.0 and turn_to == 0 else 1
		for i in 360:
			swimmer.tick(adv, warm_mode, warm_velocity, 1.0 / 120.0)
			swimmer.last_now = adv.now()
		swimmer.quiet = false

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)
		swimmer.target_facing = turn_to
		host.debug_skip_blend()

	func tick(host, delta: float) -> bool:
		swimmer.tick(host, mode, velocity, delta)
		return false

	func sample(_t: float, pose: RigPose, juice: bool) -> void:
		swimmer.sample(null, pose, juice)
