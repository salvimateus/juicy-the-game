extends Node2D

# Dotted aim trajectory in world space: square dots on the art grid that fade towards the end.

var points: PackedVector2Array = []
var dot_size := 6.0
var color := Color("#e8e0c8")


func _ready() -> void:
	top_level = true
	z_index = 5


func set_points(p: PackedVector2Array) -> void:
	points = p
	queue_redraw()


func _draw() -> void:
	var n := points.size()
	for i in n:
		var c := color
		c.a = lerpf(0.95, 0.15, float(i) / maxf(1.0, n - 1))
		var p := (points[i] / dot_size).floor() * dot_size
		draw_rect(Rect2(p, Vector2(dot_size, dot_size)), c)
