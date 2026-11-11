extends Node2D

# Oxygen bar above the head in pixel art (art-grid blocks), visible only underwater.

const ART := 6
const FRAME := Color("#141013")
const FULL := Color("#7fd0ff")
const LOW := Color("#e05050")
const EMPTY := Color(0.1, 0.12, 0.2, 0.8)

var ratio := 1.0
var low := false
var blink := false


func set_state(value: float, is_low: bool, show: bool) -> void:
	ratio = value
	low = is_low
	visible = show
	blink = is_low and int(Time.get_ticks_msec() / 150) % 2 == 0
	queue_redraw()


func _draw() -> void:
	var w := 20
	var origin := Vector2(-w * ART * 0.5, 0)
	draw_rect(Rect2(origin - Vector2(ART, ART), Vector2((w + 2) * ART, 3 * ART)), FRAME)
	draw_rect(Rect2(origin, Vector2(w * ART, ART)), EMPTY)
	var filled := int(ceilf(ratio * w))
	if filled > 0:
		draw_rect(Rect2(origin, Vector2(filled * ART, ART)), Color.WHITE if blink else (LOW if low else FULL))
