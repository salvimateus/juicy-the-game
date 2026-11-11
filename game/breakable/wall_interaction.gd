extends Area2D

# Interaction zone around the rubble, following the shared `interactable` contract.

@export var interact_radius := 360.0

var wall: Node


func _ready() -> void:
	add_to_group(&"interactable")


func get_prompt(_player: Node) -> String:
	return "Restaurar a parede"


func can_interact(player: Node) -> bool:
	return wall != null and wall.can_interact(player)


func interact(player: Node) -> void:
	if wall:
		wall.interact(player)


func get_interact_point() -> Vector2:
	return global_position


func get_prompt_anchor() -> Vector2:
	return wall.get_prompt_anchor() if wall else global_position
