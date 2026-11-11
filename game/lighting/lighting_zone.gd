extends Area2D

# Dark area (tunnel, cave): while the player stands inside, the Lighting overlay blacks out the
# world outside `world_rect()` and lights the inside with a torch around the player. The rect is
# `tunnel_rect` (world) when it has an area, else the first RectangleShape2D child. Members of
# group `lighting_zone`; the overlay is spawned on demand.

const Lighting := preload("res://game/lighting/lighting.gd")

@export var tunnel_rect := Rect2():
	set(value):
		tunnel_rect = value
		if is_inside_tree():
			refresh()
@export_range(0.0, 1.0) var ambient := 0.08
@export var ambient_color := Color(0.62, 0.62, 0.85)
@export var torch_radius := 430.0
@export var torch_color := Color(1.0, 0.64, 0.34)
# From the player origin (feet) to the torch centre, a little above the crawling hip.
@export var torch_offset := Vector2(0, -110)
@export_range(0.0, 0.5) var flicker_amount := 0.12
@export var fade_time := 0.5
# 1 = outside the rect is pure black; lower values let a little of the outside through.
@export_range(0.0, 1.0) var outside_black := 1.0
@export_range(2, 6) var bands := 4
# Fraction of each band, at its outer edge, dithered towards the next one.
@export_range(0.0, 1.0) var dither_width := 0.5
@export var zone_priority := 0

var _rect := Rect2()


func _enter_tree() -> void:
	add_to_group(&"lighting_zone")
	Lighting.register_zone(self)


func _exit_tree() -> void:
	Lighting.unregister_zone(self)


func _ready() -> void:
	monitoring = false
	monitorable = false
	refresh()
	_ensure_lighting.call_deferred()


func _ensure_lighting() -> void:
	Lighting.ensure(self)


func world_rect() -> Rect2:
	return _rect


func contains(point: Vector2) -> bool:
	return _rect.has_point(point)


func _rect_shape() -> CollisionShape2D:
	for child in get_children():
		if child is CollisionShape2D and child.shape is RectangleShape2D:
			return child
	return null


# Recomputes the rect after moving the zone or its shape; keeps the shape on `tunnel_rect` so
# `visible collision shapes` shows the zone.
func refresh() -> void:
	var node := _rect_shape()
	if tunnel_rect.has_area():
		_rect = tunnel_rect
		if node:
			var box := (node.shape as RectangleShape2D).duplicate() as RectangleShape2D
			box.size = tunnel_rect.size
			node.shape = box
			node.global_position = tunnel_rect.get_center()
	elif node:
		var size := (node.shape as RectangleShape2D).size
		_rect = node.global_transform * Rect2(-size * 0.5, size)
