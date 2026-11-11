extends Camera2D

const GameScale := preload("res://game/game_scale.gd")

@export var smoothing_x := 8.0
@export var smoothing_y := 4.0
# Reached at sprint speed; keeps the character in frame at ~1426 units/s.
@export var lookahead := 560.0
@export var lookahead_smoothing := 2.0
# Vertical position of the player's floor on screen (0 top, 1 bottom); with the standing height
# this keeps the body a little below the centre (~57%).
@export_range(0.0, 1.0) var floor_screen_ratio := 0.7
# While airborne the camera keeps its height until the player rises this far above the last floor.
@export var air_follow_margin := 260.0

@export_group("Look")
# Falling faster than this pulls the view down, up to fall_look_max.
@export var fall_look_speed := 700.0
@export var fall_look_max := 320.0
# The player's look_dir (held stick while still) lowers the view by crouch_look or raises it by
# look_up_distance.
@export var crouch_look := 360.0
@export var look_up_distance := 340.0
# Inside a camera zone that pushes the view down: room kept above the feet at the top of the screen.
@export var zone_headroom := 660.0
@export var look_smoothing := 3.0

@export_group("Swimming")
# Body centre on screen while floating (0 top): a bit above the middle shows the water below.
@export_range(0.0, 1.0) var swim_surface_ratio := 0.42
# Underwater the camera centres on the body and leads along the vertical motion.
@export var swim_under_lead := 220.0
@export var swim_lead_speed := 340.0

@export_group("Zones")
# Blend time into and out of a CameraZone (exponential rate).
@export var zone_blend_rate := 6.0
@export var default_limit_bottom := 420.0

var target: CharacterBody2D
var _look := 0.0
var _shake := 0.0
var _shake_time := 0.0
var _shake_left := 0.0
var _ref_y := 0.0
var _look_y := 0.0
var _min_center := -INF
var _limit_bottom := 420.0


func setup(player: CharacterBody2D, bounds: Rect2) -> void:
	target = player
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	_refresh_zoom()
	get_tree().root.size_changed.connect(_refresh_zoom)
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	# The bottom limit is applied by hand so zones can move it smoothly.
	limit_bottom = 1000000
	default_limit_bottom = bounds.end.y
	_limit_bottom = default_limit_bottom
	_ref_y = player.global_position.y
	global_position = _goal()
	make_current()
	reset_smoothing()


func _refresh_zoom() -> void:
	zoom = Vector2.ONE * GameScale.camera_zoom(get_window())


func view_size() -> Vector2:
	return get_viewport_rect().size / zoom


func _goal() -> Vector2:
	return Vector2(target.global_position.x + _look, _ref_y - view_size().y * (floor_screen_ratio - 0.5))


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var y := target.global_position.y
	if target.is_on_floor() or target.hanging:
		_ref_y = y
	elif y > _ref_y:
		_ref_y = y
	elif y < _ref_y - air_follow_margin:
		_ref_y = y + air_follow_margin
	var speed_ref: float = target.sprint_speed
	var desired := clampf(target.velocity.x / speed_ref, -1.0, 1.0) * lookahead
	_look = lerpf(_look, desired, 1.0 - exp(-lookahead_smoothing * delta))
	var goal := _goal()
	goal.y = _vertical_goal(goal.y, delta)
	global_position = Vector2(
		lerpf(global_position.x, goal.x, 1.0 - exp(-smoothing_x * delta)),
		lerpf(global_position.y, goal.y, 1.0 - exp(-smoothing_y * delta)))
	var rig = target.rig
	offset = rig.get_shake() if rig and rig.has_method(&"get_shake") else Vector2.ZERO
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var k := _shake * _shake_left / _shake_time
		offset += Vector2(randf_range(-k, k), randf_range(-k, k))


# Strong shakes override weaker running ones; amount in world units, fading over duration.
func add_shake(amount: float, duration: float) -> void:
	if amount * maxf(duration, 0.001) >= _shake * _shake_left:
		_shake = amount
		_shake_time = maxf(duration, 0.001)
		_shake_left = _shake_time


func _vertical_goal(base_y: float, delta: float) -> float:
	var view_h := view_size().y
	var y := base_y
	var swim = target.get(&"swim")
	var swimming: bool = swim != null and swim.active()
	if swimming:
		var body_y: float = target.global_position.y - target.get_hurt_rect().size.y * 0.5
		if swim.mode_name() == &"swim":
			y = body_y + view_h * (0.5 - swim_surface_ratio)
		else:
			y = body_y + clampf(target.velocity.y / swim_lead_speed, -1.0, 1.0) * swim_under_lead
		_look_y = 0.0
	else:
		var want := 0.0
		if not target.is_on_floor() and target.velocity.y > fall_look_speed:
			want = minf((target.velocity.y - fall_look_speed) * 0.4, fall_look_max)
		# look_amount eases in while the stick is held (look_dir only flips at the full hold).
		var look = target.get(&"look_amount")
		if look == null:
			look = float(target.get(&"look_dir")) if target.get(&"look_dir") != null else 0.0
		if look is float and look > 0.0:
			want = maxf(want, crouch_look * look)
		elif look is float and look < 0.0:
			want = look_up_distance * look
		_look_y = lerpf(_look_y, want, 1.0 - exp(-look_smoothing * delta))
	# Zones: blend their minimum centre and bottom limit in and out.
	var zone := _zone()
	var k := 1.0 - exp(-zone_blend_rate * delta)
	var want_min: float = zone.min_center_y if zone and not swimming else -INF
	if want_min == -INF:
		_min_center = -INF if _min_center == -INF or _min_center < y - view_h else lerpf(_min_center, y - view_h, k)
	else:
		_min_center = want_min if _min_center == -INF else lerpf(_min_center, want_min, k)
	if _min_center != -INF:
		y = maxf(y, _min_center)
		# A zone may push the view down, but never so far that the head (and an interaction prompt
		# above it) leaves the top of the screen.
		if not swimming:
			y = minf(y, target.global_position.y - zone_headroom + view_h * 0.5)
	# The held look (and the fall look) goes on top of the zone's framing: looking up always rises.
	if not swimming:
		y += _look_y
	var want_limit: float = zone.limit_bottom if zone and zone.limit_bottom != INF else default_limit_bottom
	_limit_bottom = lerpf(_limit_bottom, want_limit, k)
	return minf(y, _limit_bottom - view_h * 0.5)


func _zone() -> Node:
	var best: Node = null
	for z in get_tree().get_nodes_in_group(&"camera_zones"):
		if z.contains(target.global_position) and (best == null or z.priority > best.priority):
			best = z
	return best


# Jump straight to the target (after a teleport).
func snap() -> void:
	_ref_y = target.global_position.y
	_look = 0.0
	global_position = _goal()
	reset_smoothing()
	reset_physics_interpolation()
