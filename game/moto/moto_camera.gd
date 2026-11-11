extends Camera2D

# Camera of the ridden bike: horizontal lookahead by speed, the floor kept at FLOOR_SCREEN_RATIO,
# the height held in the air until the bike climbs past AIR_FOLLOW_MARGIN, shake in whole art
# pixels, track limits. Driven from _physics_process with the bike's physics state; the engine's
# physics interpolation smooths it like the bike sprites (which use the same interpolated state).

const T := preload("res://game/moto/moto_tuning.gd")
const GameScale := preload("res://game/game_scale.gd")

var _center := Vector2.ZERO
var _ref_y := 0.0
var _look := 0.0
var _look_y := 0.0
var _shake := 0.0
var _shake_time := 0.0
var _shake_left := 0.0
var _a := 6.0


func _ready() -> void:
	_a = float(GameScale.art_pixel())
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false
	_refresh_zoom()
	get_tree().root.size_changed.connect(_refresh_zoom)


func set_bounds(bounds: Rect2) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)


func _refresh_zoom() -> void:
	zoom = Vector2.ONE * GameScale.camera_zoom(get_window())


func view_size() -> Vector2:
	return get_viewport_rect().size / zoom


# Starts from where another camera is looking (no jump) and follows `floor_y` from there.
func begin_at(center: Vector2, floor_y: float) -> void:
	_center = center
	_ref_y = floor_y
	_look = 0.0
	global_position = _center
	make_current()
	reset_smoothing()
	reset_physics_interpolation()


# Jump to the goal (respawn, restart).
func snap_to(floor_point: Vector2) -> void:
	_ref_y = floor_point.y
	_look = 0.0
	_look_y = 0.0
	_center = _goal(floor_point.x)
	global_position = _center
	reset_smoothing()
	reset_physics_interpolation()


func _goal(x: float) -> Vector2:
	return Vector2(x + _look, _ref_y - view_size().y * (T.FLOOR_SCREEN_RATIO - 0.5))


# floor_point: the ground under the bike (centre of mass plus the rest height); grounded: a wheel
# touches.
func follow(floor_point: Vector2, v: Vector2, grounded: bool, delta: float) -> void:
	var vx := v.x
	var y := floor_point.y
	if grounded or y > _ref_y:
		_ref_y = y
	elif y < _ref_y - T.AIR_FOLLOW_MARGIN:
		_ref_y = y + T.AIR_FOLLOW_MARGIN
	var want := clampf(vx / T.TOP_SPEED, -1.0, 1.0) * T.LOOKAHEAD
	_look = lerpf(_look, want, 1.0 - exp(-T.LOOKAHEAD_SMOOTHING * delta))
	# Falling fast (off the table): look down towards the landing.
	var want_y := 0.0 if grounded else clampf((v.y - T.CAMERA_FALL_LOOK_SPEED) * T.CAMERA_FALL_LOOK, 0.0, T.CAMERA_FALL_LOOK_MAX)
	_look_y = lerpf(_look_y, want_y, 1.0 - exp(-T.CAMERA_SMOOTHING_Y * delta))
	var goal := _goal(floor_point.x) + Vector2(0.0, _look_y)
	_center = Vector2(
		lerpf(_center.x, goal.x, 1.0 - exp(-T.CAMERA_SMOOTHING_X * delta)),
		lerpf(_center.y, goal.y, 1.0 - exp(-T.CAMERA_SMOOTHING_Y * delta)))
	global_position = _center
	offset = Vector2.ZERO
	if _shake_left > 0.0:
		_shake_left = maxf(0.0, _shake_left - delta)
		var k := _shake * _shake_left / _shake_time
		offset = Vector2(roundf(randf_range(-k, k) / _a) * _a, roundf(randf_range(-k, k) / _a) * _a)


# Strong shakes override weaker running ones; amount in world units, fading over duration.
func add_shake(amount: float, duration: float) -> void:
	if amount * maxf(duration, 0.001) >= _shake * _shake_left:
		_shake = amount
		_shake_time = maxf(duration, 0.001)
		_shake_left = _shake_time
