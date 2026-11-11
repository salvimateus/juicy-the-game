extends Marker2D

# Visual reward on top of a wall challenge: a sign with a pennant.

const POST := Color("#5a4030")
const BOARD := Color("#d8b04a")
const STAR := Color("#fff2b0")
const FLAG := Color("#c84a4a")
const EDGE := Color("#141013")


func _ready() -> void:
	add_to_group(&"rewards")


func _draw() -> void:
	draw_rect(Rect2(-6, -228, 12, 228), POST)
	draw_rect(Rect2(6, -228, 72, 42), FLAG)
	draw_rect(Rect2(-66, -168, 132, 78), EDGE)
	draw_rect(Rect2(-60, -162, 120, 66), BOARD)
	draw_rect(Rect2(-12, -144, 24, 30), STAR)
	draw_rect(Rect2(-24, -132, 48, 6), STAR)
