extends RefCounted

# Kunai: X on the ground plays the rig's ninja_strike (smoke vanish, dash, reverse-grip cut; its
# advance comes as root motion). On the `hit` event the blade (anchor kunai.tip) sweeps a circle:
# every damageable takes a &"slash" hit (the scarecrow bleeds). A ricochet surface (meta ricochet)
# inside the circle turns the cut into a clang: sparks, a ring, a jolt and a short hitstop.

const Feedback := preload("res://game/feedback.gd")
const Hitbox := preload("res://game/combat/hitbox.gd")
const FogHooks := preload("res://game/fog_hooks.gd")
const Ricochet := preload("res://game/ricochet/ricochet.gd")

var damage := 22.0
var hit_radius := 90.0
var hitstop := 0.07
var shake := 12.0
var clang_hitstop := 0.05
var clang_shake := 8.0
var clang_mask := 1
var clang_reach := 200.0

var player
var hit_count := 0


func _init(owner_player) -> void:
	player = owner_player


func attack() -> bool:
	if not player.start_combat_action(&"ninja_strike"):
		return false
	Feedback.sfx(&"ninja_poof", player.global_position)
	return true


func on_event(id: StringName, event_name: StringName) -> void:
	if id != &"ninja_strike" or event_name != &"hit":
		return
	var rig = player.rig
	var tip: Vector2 = player.global_position + Vector2(player.facing * 160.0, -230.0)
	if rig.has_method(&"get_anchor"):
		tip = rig.get_anchor(&"kunai.tip")
	var direction := Vector2(player.facing, 0.0)
	Feedback.sfx(&"kunai_slash", tip)
	FogHooks.push(tip, direction * 1500.0, 170.0, 1.2)
	var targets := Hitbox.query(player.get_world_2d(), tip, hit_radius, [player.get_rid()])
	for target in targets:
		target.take_hit(tip, direction, damage, &"slash")
	var clanged := _clang(tip, direction)
	if targets.is_empty():
		if clanged:
			player.camera_shake(clang_shake, 0.12)
		return
	hit_count += 1
	Feedback.haptic(&"punch_hit")
	player.hitstop(hitstop)
	player.camera_shake(shake, 0.18)


# The blade meets a ricochet surface: along the strike line (body to tip and clang_reach ahead,
# at blade height) or inside the hit circle. It glances off with a spark fan.
func _clang(tip: Vector2, direction: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var from := Vector2(float(player.global_position.x), tip.y)
	var ray := PhysicsRayQueryParameters2D.create(from, from + direction * clang_reach, clang_mask, [player.get_rid()])
	var hit: Dictionary = space.intersect_ray(ray)
	if not hit.is_empty() and Ricochet.is_surface(hit.collider):
		var n := Ricochet.normal_of(hit.normal, direction)
		Ricochet.impact(hit.position, n, Vector2(n.x, -0.7).normalized(), 1.0, &"blade", hit.collider, player, clang_hitstop)
		return true
	var circle := CircleShape2D.new()
	circle.radius = hit_radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, tip)
	query.collision_mask = clang_mask
	query.collide_with_areas = false
	query.exclude = [player.get_rid()]
	for r in space.intersect_shape(query, 8):
		if Ricochet.is_surface(r.collider):
			var normal := -direction
			Ricochet.impact(tip, normal, Vector2(normal.x, -0.7).normalized(), 1.0, &"blade", r.collider, player, clang_hitstop)
			return true
	return false
