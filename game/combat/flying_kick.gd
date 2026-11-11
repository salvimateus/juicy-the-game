extends RefCounted

# Flying kick (X in the air, once per flight). The rig's root motion is the whole trajectory, so
# the player suspends gravity and applies it in X and Y. The sole is probed every frame (after the
# rig's get_kick_contact()); the first damageable reached takes the hit and the rig recoils. A wall
# (or a resting crate) in front of the sole is a contact too: the kick thuds and bounces off it,
# without refilling the kick.

const Feedback := preload("res://game/feedback.gd")
const Hitbox := preload("res://game/combat/hitbox.gd")
const FogHooks := preload("res://game/fog_hooks.gd")

# The breakable wall scales its break impulse by damage / kick_damage_reference (10).
var damage := 15.0
var hit_radius := 55.0
var hitstop := 0.1
var shake := 30.0
# Wall bounce: how far ahead of the sole the world is probed, the minimum |normal.x| that counts as
# a wall (just above the floor_max_angle default, so 45 degree ramps still end in a landing), and
# the lighter thud than a hit on a target.
var wall_probe_ahead := 20.0
var wall_min_normal := 0.71
var wall_hitstop := 0.07
var wall_shake := 18.0
var wall_bounces := 0

var player
var available := true
var impacted := false
var hit_count := 0


func _init(owner_player) -> void:
	player = owner_player


func attack() -> bool:
	if not available:
		return false
	if not player.start_combat_action(&"flying_kick"):
		return false
	available = false
	impacted = false
	return true


func playing() -> bool:
	return player.current_action == &"flying_kick"


# Called every physics frame while the kick plays, after the body moved.
func probe() -> void:
	if impacted or not player.rig.has_method(&"get_kick_contact"):
		return
	var contact: Dictionary = player.rig.get_kick_contact()
	if contact.is_empty():
		return
	var point: Vector2 = contact.point
	var direction: Vector2 = contact.direction
	var targets := Hitbox.query(player.get_world_2d(), point, hit_radius, [player.get_rid()])
	if targets.is_empty():
		_probe_wall(point, direction)
		return
	_impact_target(targets[0], point, direction)


func _impact_target(target: Object, point: Vector2, direction: Vector2) -> void:
	impacted = true
	hit_count += 1
	player.rig.kick_impact()
	FogHooks.burst(point, 220.0, 1.2)
	target.take_hit(point, direction, damage, &"kick")
	Feedback.sfx(&"kick_hit", point)
	Feedback.haptic(&"kick_hit")
	player.hitstop(hitstop)
	player.camera_shake(shake, 0.3)


# A steep face of the world right ahead of the sole (or one the body already slid into) stops the
# kick: the sole is brought flush to it and the rig recoils as on a hit.
func _probe_wall(sole: Vector2, direction: Vector2) -> void:
	var f := signf(direction.x)
	if f == 0.0:
		f = float(player.facing)
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(Vector2(player.global_position.x, sole.y), sole + Vector2(f * wall_probe_ahead, 0.0), 1, [player.get_rid()])
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.normal.x * f <= -wall_min_normal:
		var collider: Object = hit.collider
		if collider and collider.has_method(&"take_hit"):
			_impact_target(collider, hit.position, direction)
			return
		player.move_and_collide(Vector2(hit.position.x - sole.x, 0.0))
		_impact_wall(Vector2(hit.position.x, sole.y), collider)
		return
	# The capsule may have reached the wall before the boot did.
	for i in player.get_slide_collision_count():
		var c: KinematicCollision2D = player.get_slide_collision(i)
		if c.get_normal().x * f <= -wall_min_normal:
			var collider := c.get_collider()
			if collider and collider.has_method(&"take_hit"):
				_impact_target(collider, c.get_position(), direction)
			else:
				_impact_wall(c.get_position(), collider)
			return


func _impact_wall(at: Vector2, collider: Object) -> void:
	impacted = true
	wall_bounces += 1
	if player.rig.has_method(&"kick_impact"):
		player.rig.kick_impact()
	var surface: StringName = &"stone"
	if collider and collider.has_meta(&"surface"):
		surface = collider.get_meta(&"surface")
	FogHooks.burst(at, 180.0, 1.0)
	Feedback.sfx(&"kick_hit", at, 0.8)
	Feedback.sfx(&"land", at, 0.8, surface)
	Feedback.haptic(&"kick_hit", 0.8)
	player.hitstop(wall_hitstop)
	player.camera_shake(wall_shake, 0.25)


# Landed while the kick still played without hitting: end it with a heavy landing.
func landed() -> void:
	if player.rig.has_method(&"stop_action") and playing():
		player.rig.stop_action()
	if not impacted:
		Feedback.sfx(&"land", player.global_position, 1.0, player.surface)
		Feedback.haptic(&"land", 1.0)
		player.camera_shake(10.0, 0.2)


func refill() -> void:
	available = true
