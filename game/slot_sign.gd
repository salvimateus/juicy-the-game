extends Marker2D

# Reserved spot for a next-phase object: an empty sign and the footprint it may use.

@export var footprint := 300.0
# Without the board only the footprint strip is drawn (area bounds).
@export var board := true

const POST := Color("#5a4030")
const BOARD := Color("#7a6250")
const EDGE := Color("#141013")
const MARK := Color(1, 1, 1, 0.18)


func _ready() -> void:
	add_to_group(&"next_phase_slots")
	z_index = -1


func _draw() -> void:
	var half := roundf(footprint / 12.0) * 6.0
	for x in range(int(-half), int(half), 36):
		draw_rect(Rect2(x, -6, 18, 6), MARK)
	if not board:
		return
	draw_rect(Rect2(-6, -132, 12, 132), POST)
	draw_rect(Rect2(-66, -192, 132, 72), EDGE)
	draw_rect(Rect2(-60, -186, 120, 60), BOARD)
