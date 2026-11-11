extends RefCounted

# Ricochet surfaces. Contract: any CollisionObject2D with the meta &"ricochet" (float, the share of
# speed it gives back; 1.0 = plain steel) deflects projectiles instead of stopping them. It may also
# implement on_ricochet(point, normal, strength) to react (the steel plate rattles). Projectiles ask
# deflect() and keep() for the bounce and call impact() for the juice: sparks, the "ping", and, for
# the player's own shots, a light rumble and an optional micro hitstop.

const Feedback := preload("res://game/feedback.gd")
const RicochetFx := preload("res://game/ricochet/ricochet_fx.gd")

const META := &"ricochet"
# Speed kept by a head-on hit and by a grazing one, before the surface's own factor.
const KEEP_HEAD_ON := 0.45
const KEEP_GRAZING := 0.85
# Random turn of the outgoing direction (radians): repeated shots fan out a little.
const SCATTER := 0.05
# Minimum angle between the outgoing direction and the surface (as dot with the normal).
const MIN_LEAVE_DOT := 0.08
# How far the projectile is put off the surface after the bounce, so it does not hit it again.
const CLEARANCE := 12.0
const HAPTIC := &"ricochet"
const SFX := &"ricochet"
const SHAKE := 4.0
const SHAKE_TIME := 0.1

static var _fx: WeakRef


static func is_surface(collider: Variant) -> bool:
	var o := collider as Object
	return o != null and is_instance_valid(o) and o.has_meta(META)


static func restitution(collider: Variant) -> float:
	return float((collider as Object).get_meta(META, 1.0)) if is_surface(collider) else 0.0


# Surface normal from a ray hit; a ray started inside a shape reports zero, then face the shot.
static func normal_of(hit_normal: Vector2, incoming: Vector2) -> Vector2:
	if hit_normal.length_squared() > 0.01:
		return hit_normal.normalized()
	return -incoming.normalized() if incoming.length_squared() > 0.0 else Vector2.UP


# Share of speed kept: grazing hits keep more than head-on ones.
static func keep(incoming: Vector2, normal: Vector2, collider: Variant) -> float:
	var graze := 1.0 - absf(incoming.normalized().dot(normal))
	return lerpf(KEEP_HEAD_ON, KEEP_GRAZING, graze) * restitution(collider)


# Mirrored direction (unit), scattered a little and never flatter than MIN_LEAVE_DOT.
static func deflect(incoming: Vector2, normal: Vector2, scatter: float = SCATTER) -> Vector2:
	var out := incoming.normalized().bounce(normal).rotated(randf_range(-scatter, scatter))
	var d := out.dot(normal)
	if d < MIN_LEAVE_DOT:
		out = (out + normal * (MIN_LEAVE_DOT - d)).normalized()
	return out


# Juice for one bounce. kind picks the sound (&"bullet", &"arrow", &"blade"); shooter is the
# player when the shot is theirs (rumble, and hitstop seconds when > 0).
static func impact(point: Vector2, normal: Vector2, out_dir: Vector2, strength: float, kind: StringName, collider: Variant = null, shooter: Node = null, hitstop: float = 0.0) -> void:
	var fx := _spark_node()
	if fx:
		fx.burst(point, normal, out_dir, strength)
	Feedback.sfx(SFX, point, strength, kind)
	if is_surface(collider) and (collider as Object).has_method(&"on_ricochet"):
		collider.on_ricochet(point, normal, strength)
	if shooter == null or not is_instance_valid(shooter):
		return
	Feedback.haptic(HAPTIC, strength)
	if hitstop > 0.0:
		if shooter.has_method(&"hitstop"):
			shooter.hitstop(hitstop)
		if shooter.has_method(&"camera_shake"):
			shooter.camera_shake(SHAKE * strength, SHAKE_TIME)


# One spark drawer per scene, created on first use.
static func _spark_node() -> Node2D:
	var node: Node2D = _fx.get_ref() as Node2D if _fx else null
	if node and is_instance_valid(node) and node.is_inside_tree():
		return node
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return null
	node = RicochetFx.new()
	node.name = "RicochetFx"
	tree.current_scene.add_child(node)
	_fx = weakref(node)
	return node
