class_name Hurtbox
extends Area2D

# Combat target of a training dummy, following the shared `damageable` contract: an Area2D in the
# `damageable` group on HITBOX_LAYER (the same bit as the breakable wall's hitbox), forwarding
# take_hit to `target`. Projectiles that stay stuck ask `target.attach_projectile` when it exists.

const HITBOX_LAYER := 1 << 6

var target: Node


func _init() -> void:
	collision_layer = HITBOX_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func _ready() -> void:
	add_to_group(&"damageable")


func take_hit(point: Vector2, direction: Vector2, damage: float, kind: StringName) -> void:
	if target and target.has_method(&"take_hit"):
		target.take_hit(point, direction, damage, kind)


# Lets a stuck projectile ride the target's motion; false when the target cannot carry it.
func attach_projectile(projectile: Node2D, point: Vector2) -> bool:
	if target and target.has_method(&"attach_projectile"):
		return target.attach_projectile(projectile, point)
	return false
