extends Node2D

# Provisional water volume with the WaterBody API (res://game/water/water_body.gd): a flat
# rectangle of water in pixel art, with simple ripples, bubbles and splash drops. The player only
# talks to the API, so it works the same with the real WaterBody. Global coordinates, y down.

const GROUP := &"water"
const ART := 6
const BODY := Color(0.18, 0.42, 0.78, 0.55)
const SURFACE := Color(0.55, 0.78, 1.0, 0.85)
const BUBBLE := Color(0.8, 0.92, 1.0, 0.9)

# Water rectangle in local coordinates: top-left at the origin, surface at y = 0.
@export var size := Vector2(1800, 600)

var _ripples: Array = []
var _bubbles: Array = []
var _drops: Array = []


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	z_index = 3


func is_ready() -> bool:
	return true


func _rect() -> Rect2:
	return Rect2(global_position, size)


func is_point_in_water(global_pos: Vector2) -> bool:
	return _rect().has_point(global_pos)


func get_surface_y(global_x: float, near_y: float) -> float:
	var r := _rect()
	if global_x < r.position.x or global_x > r.end.x or near_y > r.end.y + 48.0:
		return INF
	return r.position.y + _wave(global_x)


func get_submerged_ratio(rect: Rect2) -> float:
	var r := _rect()
	var inter := rect.intersection(r)
	if rect.size.y <= 0.0 or inter.size.x <= 0.0:
		return 0.0
	return clampf(inter.size.y / rect.size.y, 0.0, 1.0)


func get_flow_at(_global_pos: Vector2) -> Vector2:
	return Vector2.ZERO


func apply_disturbance(global_pos: Vector2, velocity: Vector2) -> void:
	var s := clampf(velocity.length() / 1200.0, 0.0, 1.0)
	if s > 0.05:
		_ripples.append([global_pos.x, s * 18.0, 0.0])


func emit_bubbles(global_pos: Vector2, count: int, velocity: Vector2 = Vector2.ZERO) -> void:
	for i in count:
		_bubbles.append([global_pos + Vector2(randf_range(-18, 18), randf_range(-12, 12)), velocity * 0.2 + Vector2(randf_range(-20, 20), -randf_range(90, 160)), randf_range(0.8, 1.6)])


func emit_splash(global_pos: Vector2, strength: float) -> void:
	var n := int(6 + 18 * clampf(strength, 0.0, 1.0))
	for i in n:
		var v := Vector2(randf_range(-260, 260), -randf_range(300, 900) * (0.4 + strength))
		_drops.append([Vector2(global_pos.x, get_surface_y(global_pos.x, global_pos.y)) + Vector2(randf_range(-30, 30), 0), v])
	apply_disturbance(global_pos, Vector2(0, 1200.0 * strength))


func _wave(global_x: float) -> float:
	var y := 0.0
	for r in _ripples:
		var d := absf(global_x - r[0])
		y += r[1] * cos(d / 40.0 - r[2] * 9.0) * exp(-d / 260.0) * exp(-r[2] * 2.0)
	return y


func _process(delta: float) -> void:
	for r in _ripples:
		r[2] += delta
	_ripples = _ripples.filter(func(r): return r[2] < 2.0)
	var top := global_position.y
	for b in _bubbles:
		b[0] += b[1] * delta
		b[2] -= delta
	_bubbles = _bubbles.filter(func(b): return b[2] > 0.0 and b[0].y > top + 6.0)
	for d in _drops:
		d[1].y += 2600.0 * delta
		d[0] += d[1] * delta
	_drops = _drops.filter(func(d): return d[0].y < top + 12.0 or d[1].y < 0.0)
	queue_redraw()


func _draw() -> void:
	var cols := int(size.x / ART)
	for i in cols:
		var x := i * ART
		var top := roundf(_wave(global_position.x + x + ART * 0.5) / ART) * ART
		draw_rect(Rect2(x, top, ART, size.y - top), BODY)
		draw_rect(Rect2(x, top, ART, ART), SURFACE)
	for b in _bubbles:
		var p: Vector2 = ((b[0] - global_position) / ART).floor() * ART
		draw_rect(Rect2(p, Vector2(ART, ART)), BUBBLE)
	for d in _drops:
		var p: Vector2 = ((d[0] - global_position) / ART).floor() * ART
		draw_rect(Rect2(p, Vector2(ART, ART)), SURFACE)
