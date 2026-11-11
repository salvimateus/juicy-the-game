extends Node2D

# Short-lived pixel-art bullet impact on solids (sparks and dust) plus an optional tracer line.

const DOT := 6.0
var _sparks: Array = []
var _tracers: Array = []


func _ready() -> void:
	top_level = true
	z_index = 6


func impact(point: Vector2, normal: Vector2) -> void:
	for i in 7:
		var v := (normal.rotated(randf_range(-1.0, 1.0)) * randf_range(200.0, 520.0))
		_sparks.append([point, v, randf_range(0.12, 0.3), Color("#ffd23f") if i < 4 else Color("#9a8a7a")])


func tracer(a: Vector2, b: Vector2) -> void:
	_tracers.append([a, b, 0.05])


func _process(delta: float) -> void:
	for s in _sparks:
		s[1].y += 1400.0 * delta
		s[0] += s[1] * delta
		s[2] -= delta
	_sparks = _sparks.filter(func(s): return s[2] > 0.0)
	for t in _tracers:
		t[2] -= delta
	_tracers = _tracers.filter(func(t): return t[2] > 0.0)
	if not _sparks.is_empty() or not _tracers.is_empty():
		queue_redraw()
	elif visible:
		queue_redraw()


func _draw() -> void:
	for t in _tracers:
		draw_line(t[0], t[1], Color(1.0, 0.9, 0.6, 0.8), 4.0)
	for s in _sparks:
		draw_rect(Rect2((s[0] / DOT).floor() * DOT, Vector2(DOT, DOT)), s[3])
