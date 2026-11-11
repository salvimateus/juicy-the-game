extends Node2D

# Faint red dashed aim line on the art grid, from the muzzle to the first hit (or max length).
# With set_path it follows the ricochets too: each reflected segment fainter, a brighter dot at
# every bounce.

var from := Vector2.ZERO
var to := Vector2.ZERO
var dot := 6.0
var gap := 18.0
var color := Color(1.0, 0.2, 0.2, 0.45)
# Alpha factor per bounce for the reflected segments, and the bounce dot colour.
var bounce_fade := 0.5
var bounce_color := Color(1.0, 0.55, 0.45, 0.75)

var _path := PackedVector2Array()


func _ready() -> void:
	top_level = true
	z_index = 5


func set_line(a: Vector2, b: Vector2) -> void:
	set_path(PackedVector2Array([a, b]))


# Muzzle, bounce points..., end.
func set_path(points: PackedVector2Array) -> void:
	_path = points
	if points.size() >= 2:
		from = points[0]
		to = points[points.size() - 1]
	queue_redraw()


func _draw() -> void:
	var cell := Vector2(dot, dot)
	var c := color
	# Dash phase carries over the bounces so the line reads as one.
	var phase := 0.0
	for i in range(1, _path.size()):
		var a := _path[i - 1]
		var b := _path[i]
		var length := a.distance_to(b)
		if length >= 1.0:
			var dir := (b - a) / length
			var d := phase
			while d < length:
				draw_rect(Rect2(((a + dir * d) / dot).floor() * dot, cell), c)
				d += dot + gap
			phase = d - length
		if i < _path.size() - 1:
			draw_rect(Rect2((b / dot).floor() * dot, cell), bounce_color)
			c.a *= bounce_fade
