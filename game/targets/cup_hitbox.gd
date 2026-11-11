extends Area2D

# Hit area of one party cup (child of its RigidBody2D, so it follows the cup): `damageable` on the
# hitbox layer, so a gun raycast stops on the exact cup, on the table or on the floor. Arrows skip
# it (meta `arrow_ignores`) because they already strike the cup body.

var cup_range: Node
var index := -1


func _init() -> void:
	collision_layer = Hurtbox.HITBOX_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	set_meta(&"arrow_ignores", true)


func _ready() -> void:
	add_to_group(&"damageable")


func take_hit(point: Vector2, direction: Vector2, damage: float, kind: StringName) -> void:
	if cup_range:
		cup_range.hit_cup(index, point, direction, damage, kind)
