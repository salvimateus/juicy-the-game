extends Area2D

# One pooled balloon of BalloonLauncher: a `damageable` area that any take_hit pops, letting arrows
# fly on through it. Motion, drawing and recycling belong to the launcher.

var launcher: Node
var index := -1
var alive := false


func _init() -> void:
	collision_layer = Hurtbox.HITBOX_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = false


func _ready() -> void:
	add_to_group(&"damageable")


func take_hit(point: Vector2, _direction: Vector2, _damage: float, _kind: StringName) -> void:
	if alive and launcher:
		launcher.pop(index, point)


func lets_projectiles_through() -> bool:
	return true
