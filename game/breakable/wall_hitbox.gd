extends Area2D

# Combat target of the intact wall, following the shared `damageable` contract.

var wall: Node


func _ready() -> void:
	add_to_group(&"damageable")


func take_hit(point: Vector2, direction: Vector2, damage: float, kind: StringName) -> void:
	if wall:
		wall.take_hit(point, direction, damage, kind)
