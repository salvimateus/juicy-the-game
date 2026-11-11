extends Node2D

# Placeholder that honours the Adventurer contract (res://rig/adventurer.tscn) until the real rig lands.

signal action_finished(id: StringName)
signal action_event(id: StringName, name: StringName)
signal footstep(foot: StringName, strength: float)
signal landed(strength: float)

const WALK_SPEED := 288.0
const RUN_SPEED := 602.0
const SPRINT_SPEED := 877.0

# Hanging body origin = corner - HANG_GRIP_OFFSET (x mirrored by facing).
const HANG_GRIP_OFFSET := Vector2(72, -440)
# Wall slide: body origin = wall contact point - WALL_CONTACT_OFFSET (x mirrored by facing).
const WALL_CONTACT_OFFSET := Vector2(66, 0)
# Origin relative to the corner standing on top (after ledge_climb, before ledge_descend).
const LEDGE_TOP_OFFSET := Vector2(90, 0)
# Steps up to this height are climbed with play_step_up; STEP_FORWARD is its forward root motion.
const STEP_MAX_HEIGHT := 120.0
const STEP_FORWARD := 60.0
const STEP_DURATION := 0.22
# Origin to the wall plane while pushing a wall too tall to step on, facing 1.
const PUSH_CONTACT_OFFSET := Vector2(80, 0)
# Collision height while crouched or crawling.
const CROUCH_HEIGHT := 171.0
const EVADES: Array[StringName] = [&"dodge", &"roll", &"roll_back"]
# Short actions any new action may cut.
const INTERRUPTIBLE: Array[StringName] = [&"jump", &"wall_grab", &"wall_jump", &"wall_kick", &"double_jump", &"ledge_drop", &"step_up"]

const HEIGHT := 380.0
const WIDTH := 132.0
const STEP_LENGTH := 150.0

# Each action: duration, horizontal root motion as [time, distance along facing] keys,
# and timed events. Root motion keys are eased with smoothstep between keys.
const ACTIONS := {
	&"roll": {
		"duration": 0.48,
		"motion": [[0.0, 0.0], [0.42, 450.0]],
		"events": [[0.0, &"iframes_start"], [0.06, &"roll_contact"], [0.38, &"iframes_end"]],
	},
	&"roll_back": {
		"duration": 0.5,
		"motion": [[0.0, 0.0], [0.44, -450.0]],
		"events": [[0.0, &"iframes_start"], [0.07, &"roll_contact"], [0.4, &"iframes_end"]],
	},
	&"dodge": {
		"duration": 0.35,
		# dodge_distance of the rig: ~130 back over the whole dodge.
		"motion": [[0.0, 0.0], [0.3, -130.0]],
		"events": [[0.0, &"whoosh"], [0.01, &"iframes_start"], [0.2, &"iframes_end"]],
	},
	&"jump": {
		"duration": 0.1,
		"motion": [],
		"events": [[0.0, &"takeoff"]],
	},
	&"ledge_grab": {
		"duration": 0.25,
		"motion": [],
		"events": [[0.04, &"grip"]],
	},
	&"ledge_climb": {
		"duration": 0.8,
		"motion": [],
		"events": [[0.1, &"pull"], [0.55, &"on_top"]],
	},
	&"ledge_drop": {
		"duration": 0.15,
		"motion": [],
		"events": [],
	},
	&"ledge_leap": {
		"duration": 0.3,
		"motion": [],
		"events": [[0.06, &"flip"], [0.12, &"takeoff"]],
	},
	&"ledge_descend": {
		"duration": 0.6,
		"motion": [],
		"events": [[0.55, &"grip"]],
	},
	&"wall_grab": {
		"duration": 0.15,
		"motion": [],
		"events": [[0.0, &"grip"]],
	},
	&"wall_jump": {
		"duration": 0.12,
		"motion": [],
		"events": [[0.0, &"takeoff"]],
	},
	# Short hop up off the wall; keeps the facing.
	&"wall_kick": {
		"duration": 0.1,
		"motion": [],
		"events": [[0.0, &"takeoff"]],
	},
	&"punch_1": {"duration": 0.26, "motion": [[0.0, 0.0], [0.1, 10.0]], "events": [[0.08, &"hit"], [0.15, &"combo_window"]]},
	&"punch_2": {"duration": 0.26, "motion": [[0.0, 0.0], [0.1, 10.0]], "events": [[0.08, &"hit"], [0.15, &"combo_window"]]},
	&"punch_3": {"duration": 0.34, "motion": [[0.0, 0.0], [0.14, 24.0]], "events": [[0.13, &"hit"], [0.21, &"combo_window"]]},
	&"punch_4": {"duration": 0.4, "motion": [[0.0, 0.0], [0.16, 16.0]], "events": [[0.15, &"hit"], [0.26, &"combo_window"]]},
	&"bow_draw": {"duration": 0.3, "motion": [], "events": []},
	&"bow_release": {"duration": 0.25, "motion": [], "events": [[0.04, &"release"]]},
	&"bow_cancel": {"duration": 0.15, "motion": [], "events": []},
	&"double_jump": {
		"duration": 0.12,
		"motion": [],
		"events": [[0.0, &"takeoff"]],
	},
}

# Skid: decelerate to a stop, turn (flip), launch the other way.
const SKID_STOP_T := 0.42
const SKID_FLIP_T := 0.61
const SKID_LAUNCH_T := 0.82
const SKID_DURATION := 1.06
const SKID_EASE := 1.4
const LAUNCH_EASE := 1.5

# Climb: rise to the top, then step forward onto it.
const CLIMB_RISE := Vector2(0.1, 0.55)
const CLIMB_STEP := Vector2(0.55, 0.8)

var facing := 1:
	set(value):
		facing = 1 if value >= 0 else -1
		queue_redraw()
var juice := true

var _speed := 0.0
var _gait := 0.0
var _foot := false
var _airborne := false
var _fall_speed := 0.0
var _vy := 0.0
var _hanging := false
var _action: StringName = &""
var _t := 0.0
var _entry_speed := 0.0
var _flipped := false
var _skid_stopped := false
var _fired := 0
var _root := Vector2.ZERO
var _crouch := false
var _guard := false
var weapon: StringName = &"fists"
# Flying kick: windup, then an open dive until kick_impact() or landing; impact recoils.
const KICK_WINDUP := 0.2
const KICK_DIVE := Vector2(980, 520)
const KICK_RECOIL := 0.35
var _kick_impact_t := -1.0
var _push := false
var _step_height := 0.0
var _wall_slide := false
var _wall_speed := 0.0


func set_locomotion(speed: float, delta: float) -> void:
	_speed = speed
	if not _action.is_empty():
		_advance(delta)
	elif not _airborne and not _hanging and speed > 1.0:
		var before := floori(_gait / STEP_LENGTH)
		_gait += speed * delta
		if floori(_gait / STEP_LENGTH) != before:
			_foot = not _foot
			footstep.emit(&"front" if _foot else &"back", clampf(speed / SPRINT_SPEED, 0.15, 1.0))
	queue_redraw()


func set_airborne(airborne: bool, vy: float) -> void:
	_vy = vy
	if airborne:
		_fall_speed = maxf(_fall_speed, vy)
	elif _airborne:
		if _action == &"flying_kick":
			_finish()
		landed.emit(clampf(_fall_speed / 1800.0, 0.1, 1.0))
		_fall_speed = 0.0
	_airborne = airborne


# Takes precedence over set_locomotion while crouching.
func set_crouch(crouching: bool, crawl_speed: float, _delta: float) -> void:
	_crouch = crouching
	if crouching:
		_speed = crawl_speed


func set_guard(on: bool) -> void:
	_guard = on
	queue_redraw()


func set_weapon(id: StringName) -> void:
	weapon = id


func get_anchor(anchor_name: StringName) -> Vector2:
	var reach := 150.0 if _action in [&"punch_1", &"punch_2", &"punch_3", &"punch_4"] else 90.0
	var y := -300.0 if _action == &"punch_4" else -250.0
	if anchor_name in [&"gloveB", &"gloveF", &"handB", &"handF"]:
		return global_position + Vector2(facing * reach, y)
	return global_position + Vector2(0, -200)


func get_kick_contact() -> Dictionary:
	if _action != &"flying_kick":
		return {}
	return {"point": global_position + Vector2(facing * 120.0, -70.0), "direction": Vector2(facing, 0.45).normalized()}


func kick_impact() -> void:
	if _action == &"flying_kick" and _kick_impact_t < 0.0:
		_kick_impact_t = _t
		action_event.emit(_action, &"impact")


func stop_action() -> void:
	if not _action.is_empty():
		_finish()


func set_bow_aim(_angle: float, _power: float = 1.0) -> void:
	pass


var _swim_mode: StringName = &""


func set_swim(mode: StringName, _velocity: Vector2, _delta: float) -> void:
	_swim_mode = mode


func set_push(active: bool, _delta: float) -> void:
	_push = active


func play_step_up(height: float) -> bool:
	if not _action.is_empty() and _action not in INTERRUPTIBLE:
		return false
	_action = &"step_up"
	_t = 0.0
	_fired = 0
	_step_height = height
	return true


func set_wall_slide(active: bool, speed: float) -> void:
	_wall_slide = active
	_wall_speed = speed


func action_elapsed() -> float:
	return _t if not _action.is_empty() else 0.0


func play_action(id: StringName) -> bool:
	if id == &"flying_kick":
		if not _airborne or (not _action.is_empty() and _action not in INTERRUPTIBLE):
			return false
		_action = id
		_t = 0.0
		_fired = 0
		_kick_impact_t = -1.0
		return true
	if id != &"skid_turn" and not ACTIONS.has(id):
		return false
	# Punches cancel each other; the game enforces the combo window.
	if _action.begins_with("punch_") and String(id).begins_with("punch_"):
		_action = &""
	if not _action.is_empty():
		var can := _action in INTERRUPTIBLE
		can = can or (_hanging and id in [&"ledge_climb", &"ledge_drop", &"ledge_leap"])
		# A running dodge is cancelled by a new evade (no action_finished for it); the player
		# decides when that is allowed (dodge_chain_after).
		can = can or (_action == &"dodge" and id in EVADES)
		if not can:
			return false
	_action = id
	_t = 0.0
	_entry_speed = _speed
	_flipped = false
	_skid_stopped = false
	_fired = 0
	match id:
		&"ledge_grab":
			_hanging = true
		&"ledge_drop", &"jump", &"wall_jump", &"wall_kick", &"double_jump":
			_hanging = false
	return true


func is_action_playing() -> bool:
	return not _action.is_empty()


func is_hanging() -> bool:
	return _hanging


func take_root_motion() -> Vector2:
	var out := _root
	_root = Vector2.ZERO
	return out


func _advance(delta: float) -> void:
	var t0 := _t
	_t += delta
	if _action == &"skid_turn":
		_advance_skid(t0)
		return
	if _action == &"flying_kick":
		_advance_kick(t0, delta)
		return
	if _action == &"step_up":
		_root += _step_offset(_t) - _step_offset(t0)
		if _t >= STEP_DURATION:
			_finish()
		return
	var data: Dictionary = ACTIONS[_action]
	var keys: Array = data.motion
	if keys.size() >= 2:
		_root.x += facing * (_sample(keys, _t) - _sample(keys, t0))
	if _action == &"ledge_climb":
		_root += _climb_offset(_t) - _climb_offset(t0)
	elif _action == &"ledge_descend":
		_root += _descend_offset(_t) - _descend_offset(t0)
	var id := _action
	var events: Array = data.events
	while _fired < events.size() and _t >= events[_fired][0]:
		var event_name: StringName = events[_fired][1]
		_fired += 1
		if event_name == &"flip":
			facing = -facing
		elif event_name == &"takeoff" and id == &"ledge_leap":
			_hanging = false
		action_event.emit(id, event_name)
		if _action != id:
			return
	if _t >= data.duration:
		match _action:
			&"ledge_climb":
				_hanging = false
			&"ledge_descend":
				_hanging = true
		_finish()


func _climb_offset(t: float) -> Vector2:
	var up := smoothstep(CLIMB_RISE.x, CLIMB_RISE.y, t) * HANG_GRIP_OFFSET.y
	var forward := smoothstep(CLIMB_STEP.x, CLIMB_STEP.y, t) * (HANG_GRIP_OFFSET.x + LEDGE_TOP_OFFSET.x)
	return Vector2(facing * forward, up)


func _advance_kick(t0: float, delta: float) -> void:
	if _kick_impact_t < 0.0:
		if t0 < KICK_WINDUP and _t >= KICK_WINDUP:
			action_event.emit(_action, &"hit_active")
		var v := Vector2(140, -60) if _t < KICK_WINDUP else KICK_DIVE
		_root += Vector2(facing * v.x, v.y) * delta
		return
	var k := (_t - _kick_impact_t) / KICK_RECOIL
	if k < 1.0:
		_root += Vector2(-facing * 420.0, -520.0 * (1.0 - k)) * delta
	else:
		_finish()


func _step_offset(t: float) -> Vector2:
	var up := smoothstep(0.0, STEP_DURATION * 0.6, t) * _step_height
	var forward := smoothstep(0.0, STEP_DURATION, t) * STEP_FORWARD
	return Vector2(facing * forward, -up)


# From standing at the edge (facing the platform) back over the corner and down to the hang.
func _descend_offset(t: float) -> Vector2:
	var back := smoothstep(0.0, 0.25, t) * -(HANG_GRIP_OFFSET.x + LEDGE_TOP_OFFSET.x)
	var down := smoothstep(0.15, 0.5, t) * -HANG_GRIP_OFFSET.y
	return Vector2(facing * back, down)


func _sample(keys: Array, t: float) -> float:
	if t <= keys[0][0]:
		return keys[0][1]
	for i in range(1, keys.size()):
		if t < keys[i][0]:
			var a: Array = keys[i - 1]
			var b: Array = keys[i]
			return lerpf(a[1], b[1], smoothstep(a[0], b[0], t))
	return keys[-1][1]


func _advance_skid(t0: float) -> void:
	if t0 == 0.0:
		action_event.emit(_action, &"skid_start")
	_root.x += facing * _skid_distance(t0, _t)
	if not _skid_stopped and _t >= SKID_STOP_T:
		_skid_stopped = true
		action_event.emit(_action, &"skid_stop")
	if not _flipped and _t >= SKID_FLIP_T:
		_flipped = true
		facing = -facing
		action_event.emit(_action, &"flip")
	if _t >= SKID_DURATION:
		_finish()


# Distance along the current facing between two times (integrated speed, numerically).
func _skid_distance(a: float, b: float) -> float:
	var d := 0.0
	var steps := 4
	for i in steps:
		var t := lerpf(a, b, (i + 0.5) / steps)
		var v := 0.0
		if t < SKID_STOP_T:
			v = _entry_speed * pow(1.0 - t / SKID_STOP_T, SKID_EASE)
		elif t >= SKID_LAUNCH_T:
			# After the flip the facing already points the new way, so launch speed is positive.
			v = RUN_SPEED * pow(clampf((t - SKID_LAUNCH_T) / (SKID_DURATION - SKID_LAUNCH_T), 0.0, 1.0), LAUNCH_EASE)
		d += v * (b - a) / steps
	return d


func _finish() -> void:
	var id := _action
	_action = &""
	action_finished.emit(id)


func _draw() -> void:
	var color := Color("#c8a46a")
	var size := Vector2(WIDTH, HEIGHT)
	var angle := 0.0
	var lift := 0.0
	match _action:
		&"skid_turn":
			color = Color("#e07a4a")
			angle = -0.25 if _t < SKID_STOP_T else (0.0 if _t < SKID_LAUNCH_T else 0.15)
		&"roll", &"roll_back":
			color = Color("#6ab0e0")
			size = Vector2(WIDTH, WIDTH * 1.4)
			var data: Dictionary = ACTIONS[_action]
			var spin := TAU * clampf(_t / data.motion[1][0], 0.0, 1.0)
			angle = spin if _action == &"roll" else -spin
		&"flying_kick":
			color = Color("#ffd23f")
			angle = 0.9
		&"punch_1", &"punch_2", &"punch_3", &"punch_4":
			color = Color("#ff9a6a")
		&"dodge":
			color = Color("#9ad0ff")
			angle = -0.35 * sin(PI * clampf(_t / 0.42, 0.0, 1.0))
		&"ledge_climb", &"ledge_descend":
			color = Color("#a0e070")
	if _wall_slide:
		color = Color("#d070e0")
		angle = -0.12
	elif _push and _action.is_empty():
		color = Color("#c87a50")
		angle = 0.3
	elif _crouch and _action.is_empty():
		color = Color("#b08850")
		size = Vector2(WIDTH * 1.5, CROUCH_HEIGHT)
		lift = absf(sin(_gait / STEP_LENGTH * PI)) * 6.0
	elif _action.is_empty():
		if _hanging:
			color = Color("#a0e070")
		elif _airborne:
			color = Color("#e0d070")
			size.y *= 0.92 if _vy < 0.0 else 1.0
		else:
			angle = clampf(_speed / SPRINT_SPEED, 0.0, 1.0) * 0.12
			lift = absf(sin(_gait / STEP_LENGTH * PI)) * 10.0
	if _hanging:
		# Arms up: the body hangs below the grip point.
		draw_line(Vector2(0, -HEIGHT), Vector2(facing * HANG_GRIP_OFFSET.x, HANG_GRIP_OFFSET.y), Color.WHITE, 10.0)
	draw_set_transform(Vector2(0, -size.y * 0.5 - lift), facing * angle, Vector2.ONE)
	var body := Rect2(-size * 0.5, size)
	draw_rect(body, color)
	draw_rect(body, Color(0, 0, 0, 0.6), false, 6.0)
	var y := -size.y * 0.25
	var tip := Vector2(facing * size.x * 0.9, y)
	draw_line(Vector2(facing * size.x * 0.1, y), tip, Color.WHITE, 12.0)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(facing * 36, 0), tip + Vector2(0, -30), tip + Vector2(0, 30)]), Color.WHITE)
	draw_set_transform(Vector2.ZERO)
