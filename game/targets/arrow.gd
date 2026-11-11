class_name Arrow
extends Node2D

# Arrow projectile (pecas_extra/arrow.png). The node origin is the tip. It flies with gravity, showing
# the pre-rotated frame closest to its velocity (22.5 degree steps), and casts a ray along each
# physics step: damageable areas take the hit and keep the arrow stuck; rigid bodies (party cups,
# debris) get an impulse at the contact point while the arrow goes on slower or tumbles; anything
# else static pins it, quivering, until it blinks out. Ricochet surfaces (meta ricochet, see
# res://game/ricochet/ricochet.gd) bounce it off instead, a few times, until it falls tumbling.

const SCENE := "res://game/targets/arrow.tscn"
const TEXTURE := preload("res://assets/pecas_extra/arrow.png")
const PixelRotate := preload("res://game/targets/pixel_rotate.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const Ricochet := preload("res://game/ricochet/ricochet.gd")

const STEPS := 16
const ANGLE_STEP := TAU / STEPS
const GROUP := &"arrow"
# Tip of the arrow in art px of arrow.png (props.json "tip" / ART_PIXEL).
const TIP := Vector2(21, 3.5)

enum State { FLYING, TUMBLING, STUCK, FADING }

@export var gravity := 1500.0
@export var damage := 34.0
# Bodies the arrow collides with: world (1) and the party cups / table layer (CupRange.CUP_LAYER).
@export_flags_2d_physics var body_mask := 1 | (1 << 5)
@export_flags_2d_physics var area_mask := 1 << 6
# Impulse given to a rigid body = velocity * mass.
@export var mass := 0.11
@export var max_push_speed := 2200.0
@export var pierce_keep := 0.62
@export var tumble_below := 700.0
@export var embed := 24.0
@export var stick_time := 3.5
@export var fade_time := 0.6
@export var quiver_time := 0.4
@export var max_flight_time := 6.0
# The shooter is ignored for this long after the shot; after that the arrow can hit it on the way down.
@export var shooter_grace := 0.3
# Ricochet surfaces: bounces before the arrow gives up and drops tumbling, the speed below which a
# bounce turns into a tumble, and the micro hitstop when it is the player's arrow.
@export var max_ricochets := 3
@export var ricochet_min_speed := 380.0
@export var ricochet_hitstop := 0.03
@export var ricochet_spin := Vector2(10.0, 16.0)

static var _scene: PackedScene
static var _sheet: Dictionary = {}

var velocity := Vector2.ZERO
var state := State.FLYING
var stuck_to: Node
var ricochets := 0

var _sprite: Sprite2D
var _ray_body := PhysicsRayQueryParameters2D.new()
var _ray_area := PhysicsRayQueryParameters2D.new()
var _exclude: Array[RID] = []
var _area_exclude: Array[RID] = []
var _angle := 0.0
var _spin := 0.0
var _t := 0.0
var _quiver := 0.0
var _frame := -1
var _a := 6.0
var _carried := false
var _shooter := RID()
var _player: Node


# Fires an arrow from `global_pos` (its tip) along `direction`. `shooter` is ignored by the rays
# for shooter_grace seconds.
static func spawn(parent: Node, global_pos: Vector2, direction: Vector2, speed: float, shooter: CollisionObject2D = null) -> Arrow:
	if _scene == null:
		_scene = load(SCENE) as PackedScene
	var arrow := _scene.instantiate() as Arrow
	arrow.velocity = direction.normalized() * speed
	arrow._angle = arrow.velocity.angle()
	if shooter:
		arrow._shooter = shooter.get_rid()
		arrow._exclude.append(arrow._shooter)
		if shooter.is_in_group(&"player"):
			arrow._player = shooter
	parent.add_child(arrow)
	arrow.global_position = global_pos
	arrow.reset_physics_interpolation()
	arrow._place_sprite(global_pos)
	Feedback.sfx(&"arrow_whoosh", global_pos, clampf(speed / 2600.0, 0.3, 1.0))
	return arrow


static func sheet() -> Dictionary:
	if _sheet.is_empty():
		var a := GameScale.art_pixel()
		var img := PixelRotate.art_image(TEXTURE, a)
		_sheet = PixelRotate.build(img, TIP, PixelRotate.angle_range(0.0, TAU - ANGLE_STEP, ANGLE_STEP))
	return _sheet


func _ready() -> void:
	add_to_group(GROUP)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_a = float(GameScale.art_pixel())
	z_index = 2
	var s := sheet()
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = s.texture
	_sprite.centered = false
	_sprite.region_enabled = true
	_sprite.scale = Vector2(_a, _a)
	_sprite.top_level = true
	_sprite.z_index = z_index
	_sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_sprite)
	_ray_body.collision_mask = body_mask
	_ray_body.collide_with_areas = false
	_ray_body.collide_with_bodies = true
	# After skipping a cup's hit area the ray may start on the cup's own hull.
	_ray_body.hit_from_inside = true
	_ray_area.collision_mask = area_mask
	_ray_area.collide_with_areas = true
	_ray_area.collide_with_bodies = false
	_ray_body.exclude = _exclude
	_place_sprite(global_position)


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.FLYING, State.TUMBLING:
			_fly(delta)
		State.STUCK:
			_quiver = maxf(0.0, _quiver - delta)
			if not _carried and _t >= stick_time:
				vanish()
		State.FADING:
			if _t >= fade_time:
				queue_free()


func _process(_delta: float) -> void:
	_place_sprite(global_position)
	if state == State.FADING:
		_sprite.visible = int(_t * 20.0) % 2 == 0


# Blinks out and frees itself (resets, lifetime).
func vanish() -> void:
	if state == State.FADING:
		return
	state = State.FADING
	_t = 0.0
	_carried = false


# Pose while carried by a moving target (tip position, flight angle).
func set_carried_pose(tip: Vector2, angle: float) -> void:
	global_position = tip
	_angle = angle
	reset_physics_interpolation()


func _fly(delta: float) -> void:
	if _t > max_flight_time:
		queue_free()
		return
	velocity.y += gravity * delta
	if _shooter.is_valid() and _t >= shooter_grace:
		_exclude.erase(_shooter)
		_ray_body.exclude = _exclude
		_shooter = RID()
	var from := global_position
	var to := from + velocity * delta
	if state == State.FLYING:
		_angle = velocity.angle()
	else:
		_angle += _spin * delta
	var space := get_world_2d().direct_space_state
	_ray_body.from = from
	_ray_body.to = to
	var hit := space.intersect_ray(_ray_body)
	var area_hit := {}
	if state == State.FLYING:
		_ray_area.from = from
		_ray_area.to = to
		area_hit = space.intersect_ray(_ray_area)
	if not area_hit.is_empty() and (hit.is_empty() or from.distance_squared_to(area_hit.position) <= from.distance_squared_to(hit.position)):
		var target: Object = area_hit.collider
		if not target.has_method(&"take_hit") or target.has_meta(&"arrow_ignores"):
			_area_exclude.append(area_hit.rid)
			_ray_area.exclude = _area_exclude
			global_position = area_hit.position
			return
		if target.has_method(&"lets_projectiles_through") and target.lets_projectiles_through():
			# Balloons and the like: pop them and keep flying.
			target.take_hit(area_hit.position, velocity.normalized(), damage, &"arrow")
			_area_exclude.append(area_hit.rid)
			_ray_area.exclude = _area_exclude
			global_position = area_hit.position
			return
		_hit_target(target, area_hit.position)
		return
	if hit.is_empty():
		global_position = to
		return
	var body: Object = hit.collider
	if body is RigidBody2D:
		_hit_rigid(body as RigidBody2D, hit.position)
		return
	if (body is CharacterBody2D and not body.has_method(&"take_hit")) or (body.has_method(&"lets_projectiles_through") and body.lets_projectiles_through()):
		_exclude.append(hit.rid)
		_ray_body.exclude = _exclude
		global_position = to
		return
	if body.has_method(&"take_hit"):
		_hit_target(body, hit.position)
		return
	if Ricochet.is_surface(body):
		_ricochet(hit.position, hit.normal, body)
		return
	_stick(hit.position, hit.normal)


func _hit_target(target: Object, point: Vector2) -> void:
	var dir := velocity.normalized()
	var speed_scale := clampf(velocity.length() / 2400.0, 0.4, 1.2)
	target.take_hit(point, dir, damage * speed_scale, &"arrow")
	global_position = point + dir * embed
	state = State.STUCK
	_t = 0.0
	_quiver = quiver_time
	stuck_to = target as Node
	if target.has_method(&"attach_projectile"):
		_carried = target.attach_projectile(self, global_position)
	Feedback.sfx(&"arrow_hit", point, speed_scale)


func _hit_rigid(body: RigidBody2D, point: Vector2) -> void:
	# Capped by the speed it may give the body, so a light cup is knocked away, not launched.
	var impulse := velocity * mass
	var cap := body.mass * max_push_speed
	if impulse.length() > cap:
		impulse = impulse.normalized() * cap
	body.sleeping = false
	body.apply_impulse(impulse, point - body.global_position)
	if body.has_meta(&"struck_by_arrow"):
		var cb: Callable = body.get_meta(&"struck_by_arrow")
		cb.call(body, point, impulse)
	_exclude.append(body.get_rid())
	_ray_body.exclude = _exclude
	velocity = velocity.rotated(randf_range(-0.12, 0.12)) * pierce_keep
	global_position = point
	if state == State.FLYING and velocity.length() < tumble_below:
		state = State.TUMBLING
		_spin = randf_range(8.0, 14.0) * (1.0 if velocity.x >= 0.0 else -1.0)
		velocity.y -= 220.0


# Bounces off a ricochet surface: mirrored by the normal, slower (head-on hits lose more), set off
# the face. Spent or slow, it tumbles; tumbling slowly onto a floor-like face it lands flat.
func _ricochet(point: Vector2, hit_normal: Vector2, body: Object) -> void:
	var speed := velocity.length()
	if speed < 1.0:
		_stick(point, hit_normal)
		return
	var n := Ricochet.normal_of(hit_normal, velocity)
	var out_speed := speed * Ricochet.keep(velocity, n, body)
	var strength := clampf(speed / 2400.0, 0.25, 1.0)
	var floor_like := n.y < -0.7
	if state == State.TUMBLING and floor_like and out_speed < ricochet_min_speed:
		Ricochet.impact(point, n, Vector2.UP, strength * 0.4, &"arrow", body)
		_stick(point, n)
		return
	var spent := ricochets >= max_ricochets or out_speed < ricochet_min_speed
	if spent:
		out_speed = minf(out_speed, ricochet_min_speed)
	velocity = Ricochet.deflect(velocity, n) * out_speed
	ricochets += 1
	global_position = point + n * Ricochet.CLEARANCE
	if spent or out_speed < tumble_below:
		if state == State.FLYING:
			_spin = randf_range(ricochet_spin.x, ricochet_spin.y) * (1.0 if velocity.x >= 0.0 else -1.0)
		state = State.TUMBLING
	else:
		_angle = velocity.angle()
	# A bounced arrow may come back at whoever shot it.
	if _shooter.is_valid():
		_exclude.erase(_shooter)
		_ray_body.exclude = _exclude
		_shooter = RID()
	var by_player: Node = _player if is_instance_valid(_player) else null
	Ricochet.impact(point, n, velocity.normalized(), strength, &"arrow", body, by_player, 0.0 if spent else ricochet_hitstop)
	reset_physics_interpolation()


func _stick(point: Vector2, normal: Vector2) -> void:
	if state == State.TUMBLING:
		# Lands flat on what it hit.
		global_position = point
		_angle = 0.0 if absf(normal.y) > 0.7 and velocity.x >= 0.0 else (PI if absf(normal.y) > 0.7 else _angle)
		_quiver = 0.0
	else:
		global_position = point + velocity.normalized() * embed
		_quiver = quiver_time
		Feedback.sfx(&"arrow_hit", point, clampf(velocity.length() / 2400.0, 0.3, 1.0))
	state = State.STUCK
	_t = 0.0
	reset_physics_interpolation()


func _place_sprite(o: Vector2) -> void:
	if _sprite == null:
		return
	var k := posmod(roundi(_angle / ANGLE_STEP), STEPS)
	var s := sheet()
	if k != _frame:
		_frame = k
		_sprite.region_rect = s.rects[k]
	var p: Vector2 = Vector2(roundf(o.x / _a) * _a, roundf(o.y / _a) * _a) + s.offsets[k] * _a
	if _quiver > 0.0:
		# Shaft vibration: one art pixel across the flight line, alternating and decaying.
		var phase := int(_quiver * 60.0) % 2
		var side := Vector2.from_angle(k * ANGLE_STEP + PI * 0.5)
		side = Vector2(roundf(side.x), roundf(side.y))
		p += side * _a * (1.0 if phase == 0 else -1.0) * (1.0 if _quiver > quiver_time * 0.35 else 0.0)
	_sprite.global_position = p
