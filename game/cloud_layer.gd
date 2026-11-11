extends Node2D

# Drifting clouds of the background: each cloud moves left at its own speed and wraps every
# wrap_width; drawn once per wrap window across the visible span (layer-local coordinates).

var clouds: Array = []          # [texture, x, y, speed]
var wrap_width := 6400.0
var drift_dir := -1.0
var view_left := 0.0
var view_right := 0.0
var _time := 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func set_view(left: float, right: float) -> void:
	view_left = left
	view_right = right


func _draw() -> void:
	for c in clouds:
		var tex: Texture2D = c[0]
		var x := fposmod(c[1] + drift_dir * c[3] * _time, wrap_width)
		var k := floorf((view_left - tex.get_width() - x) / wrap_width)
		var px := x + k * wrap_width
		while px < view_right:
			draw_texture(tex, Vector2(roundf(px), c[2]))
			px += wrap_width
