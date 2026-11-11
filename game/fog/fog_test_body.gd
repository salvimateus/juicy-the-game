extends Node2D

# Blocky stand-in for the player in the fog bench: 420 units tall, origin at the sole, drawn on
# the 6-unit art grid, with the knee line where the front fog must stop at rest.

const SKIN := Color("#e0a878")
const SHIRT := Color("#2f3c5c")
const PANTS := Color("#3a2c2c")
const BOOTS := Color("#241a1a")
const OUTLINE := Color("#141013")
const SCARF := Color("#b03028")
const FLASH := Color("#ffe890")

var moving := false
var phase := 0.0
var punch := 0.0
var flash := 0.0


func _process(delta: float) -> void:
	punch = maxf(punch - delta, 0.0)
	flash = maxf(flash - delta, 0.0)
	queue_redraw()


func _box(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x - 6, y - 6, w + 12, h + 12), OUTLINE)
	draw_rect(Rect2(x, y, w, h), c)


func _draw() -> void:
	var swing := sin(phase * TAU * 0.5) * 30.0 if moving else 0.0
	var s := roundf(swing / 6.0) * 6.0
	_box(-42 + s, -60, 36, 60, BOOTS)
	_box(6 - s, -60, 36, 60, BOOTS)
	_box(-36 + s, -192, 30, 132, PANTS)
	_box(6 - s, -192, 30, 132, PANTS)
	_box(-48, -330, 96, 144, SHIRT)
	_box(-60, -336, 84, 24, SCARF)
	var reach := 120.0 if punch > 0.0 else 30.0
	_box(24, -306, reach, 30, SHIRT)
	_box(24 + reach, -312, 36, 36, SKIN)
	_box(-36, -420, 78, 84, SKIN)
	_box(-42, -426, 90, 30, Color("#5a3424"))
	draw_rect(Rect2(18, -390, 12, 12), OUTLINE)
	if flash > 0.0:
		draw_rect(Rect2(150, -276, 48, 36), FLASH)
