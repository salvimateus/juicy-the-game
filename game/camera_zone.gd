extends Node2D

# Camera framing override over a world rectangle (river, tunnel, towers): while the player stands
# inside, GameCamera blends towards these values over ~0.5 s. Members of group `camera_zones`.

@export var rect := Rect2()
# The camera centre never goes above this world y (shows what lies below, e.g. a river bed).
@export var min_center_y := -INF
# Bottom edge of the view never goes below this world y (INF keeps the level limit).
@export var limit_bottom := INF
@export var priority := 0


func _enter_tree() -> void:
	add_to_group(&"camera_zones")


func contains(point: Vector2) -> bool:
	return rect.has_point(point)
