class_name CupRange
extends Node2D

# Archery stand: a wooden table with a pyramid of red party cups. Each cup is a light RigidBody2D with
# a trapezoid hull; an Arrow hitting one applies an impulse at the contact point and wakes the stack,
# so the cups topple, roll, knock each other and fall off the table. Cups show the pre-rotated frame
# of their physics rotation (22.5 degree steps, no mixels) snapped to the art grid. The reset button
# freezes them and rebuilds the pyramid row by row with a pop. Origin: floor under the table centre.

signal cups_reset
signal cup_struck(cup: RigidBody2D, point: Vector2)

const TABLE_ART := preload("res://game/targets/art/table.png")
const CUP_ART := preload("res://game/targets/art/cup.png")
const PixelRotate := preload("res://game/targets/pixel_rotate.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const RESET_BUTTON := "res://game/interactables/reset_button.tscn"
const CupHitbox := preload("res://game/targets/cup_hitbox.gd")
const PLASTIC := Color("#d81219")

# Party cups and the table top share this layer; the player does not mask it.
const CUP_LAYER := 1 << 5
const STEPS := 16
const ANGLE_STEP := TAU / STEPS
const WHITE_FRAME := STEPS

# Art-pixel layout (table.png 87x37, cup.png 10x11).
const TABLE_CENTER_COL := 43
const TABLE_SURFACE_ROW := 6
const TABLE_SHAPES := [Rect2(1, 6, 85, 10), Rect2(5, 16, 9, 21), Rect2(73, 16, 9, 21)]
const CUP_PIVOT := Vector2(5, 6)
const CUP_HULL := [Vector2(-5, -6), Vector2(5, -6), Vector2(4, 5), Vector2(-4, 5)]

enum Phase { READY, BUILD }

@export var rows := 5
# Centre-to-centre distance of the cups in a row, in art px (even, so half steps stay on the grid).
@export var spacing_px := 12
@export var game_gravity := 2600.0
@export_group("Cup physics")
@export var cup_mass := 0.05
@export var cup_friction := 0.4
@export var cup_bounce := 0.28
@export var linear_damp := 0.08
@export var angular_damp := 0.9
# Bullets and melee hits on a single cup (CupHitbox). Impulses always apply; the sound, the plastic
# chips and the rumble are rate limited so an AK burst cannot flood them.
@export var bullet_speed := Vector2(1100.0, 2600.0)
@export var melee_speed := Vector2(400.0, 1600.0)
@export var bullet_spin := 18.0
@export var hit_fx_per_second := 12.0
# An arrow strike also kicks the struck cup upwards and shoves the cups around it, so the stack
# breaks apart instead of sliding as one block.
@export var strike_lift := 650.0
@export var blast_radius := 170.0
@export var blast_speed := 950.0
@export_group("Feedback")
@export var hit_speed := 240.0
@export var hit_cooldown := 0.12
@export var hits_per_second := 10.0
@export var falls_per_second := 4.0
@export var build_step := 0.07
@export var pop_time := 0.06
@export_group("Reset")
@export var button_offset := Vector2(420, 0)
@export_group("Floor cups")
# Cups never collide with the player's body (collision exception both ways): on the table only
# take_hit, arrows and other cups move them. A cup lying on the floor is kicked from here when
# the player walks into it, so nothing ever pushes the player back.
@export var kick_factor := 1.1
@export var kick_max_speed := 900.0
@export var kick_lift := 220.0
@export var kick_min_speed := 60.0
@export var kick_cooldown := 0.15
# A cup counts as on the floor when its centre is this close to the floor line.
@export var floor_band := 90.0
@export var button_prompt := "Arrumar os copos"

static var _cup_sheet: Dictionary = {}

var cups: Array[RigidBody2D] = []
var phase := Phase.READY

var _a := 6.0
var _sprites: Array[Sprite2D] = []
var _slots := PackedVector2Array()
var _frame := PackedInt32Array()
var _speed := PackedFloat32Array()
var _cool := PackedFloat32Array()
var _fallen := PackedByteArray()
var _pop := PackedFloat32Array()
var _table: StaticBody2D
var _fx: TargetFx
var _button: Node
var _build_t := 0.0
var _build_i := 0
var _hit_tokens := 0.0
var _fall_tokens := 0.0
var _player: Node2D
var _fx_tokens := 0.0
var _kick_cool := PackedFloat32Array()


static func cup_sheet() -> Dictionary:
	if _cup_sheet.is_empty():
		var img := PixelRotate.load_art(CUP_ART)
		var white: Array[Image] = [PixelRotate.silhouette(img)]
		_cup_sheet = PixelRotate.build(img, CUP_PIVOT, PixelRotate.angle_range(0.0, TAU - ANGLE_STEP, ANGLE_STEP), white)
		# The white frame is the unrotated cup: same placement as frame 0.
		_cup_sheet.offsets.append(_cup_sheet.offsets[0])
	return _cup_sheet


func _ready() -> void:
	_a = float(GameScale.art_pixel())
	global_position = global_position.snapped(Vector2(_a, _a))
	_build_table()
	_build_cups()
	_fx = TargetFx.new()
	_fx.name = "Fx"
	add_child(_fx)
	_fx.floor_y = global_position.y
	_build_button()
	_hit_tokens = hits_per_second
	_fall_tokens = falls_per_second


func _build_table() -> void:
	var size := Vector2(TABLE_ART.get_width(), TABLE_ART.get_height())
	var top_left := Vector2(-TABLE_CENTER_COL, -size.y)
	var sprite := Sprite2D.new()
	sprite.name = "TableSprite"
	sprite.texture = TABLE_ART
	sprite.centered = false
	sprite.scale = Vector2(_a, _a)
	sprite.position = top_left * _a
	add_child(sprite)
	_table = StaticBody2D.new()
	_table.name = "Table"
	_table.collision_layer = CUP_LAYER
	_table.collision_mask = 0
	_table.set_meta(&"surface", &"wood")
	var mat := PhysicsMaterial.new()
	mat.friction = 0.7
	mat.bounce = 0.1
	_table.physics_material_override = mat
	for r: Rect2 in TABLE_SHAPES:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size * _a
		shape.shape = rect
		shape.position = (top_left + r.position + r.size * 0.5) * _a
		_table.add_child(shape)
	add_child(_table)


# Table top height above the floor, in world units.
func surface_height() -> float:
	return (TABLE_ART.get_height() - TABLE_SURFACE_ROW) * _a


func _build_cups() -> void:
	var sheet := cup_sheet()
	var mat := PhysicsMaterial.new()
	mat.friction = cup_friction
	mat.bounce = cup_bounce
	var default_gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var hull := PackedVector2Array()
	for v: Vector2 in CUP_HULL:
		hull.append(v * _a)
	var cup_h := (CUP_HULL[2].y - CUP_HULL[0].y) * _a
	var surface := -surface_height()
	for r in rows:
		var n := rows - r
		for i in n:
			var x := (i - (n - 1) * 0.5) * spacing_px * _a
			var bottom := surface - r * cup_h
			_slots.append(Vector2(x, bottom - CUP_HULL[2].y * _a))
	for i in _slots.size():
		var b := RigidBody2D.new()
		b.name = "Cup%d" % i
		b.collision_layer = CUP_LAYER
		b.collision_mask = 1 | CUP_LAYER
		b.mass = cup_mass
		b.physics_material_override = mat
		b.gravity_scale = game_gravity / maxf(default_gravity, 1.0)
		b.linear_damp = linear_damp
		b.angular_damp = angular_damp
		b.can_sleep = true
		b.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		b.contact_monitor = true
		b.max_contacts_reported = 2
		b.position = _slots[i]
		b.sleeping = true
		b.add_to_group(&"party_cup")
		# Sprites follow the physics transform directly and snap to the grid, so no interpolation.
		b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		b.set_meta(&"struck_by_arrow", _on_cup_struck)
		b.set_meta(&"surface", &"plastic")
		var poly := CollisionPolygon2D.new()
		poly.polygon = hull
		b.add_child(poly)
		b.body_entered.connect(_on_cup_contact.bind(i))
		var hit_area := Area2D.new()
		hit_area.set_script(CupHitbox)
		hit_area.name = "Hitbox"
		hit_area.cup_range = self
		hit_area.index = i
		var hit_shape := CollisionPolygon2D.new()
		hit_shape.polygon = hull
		hit_area.add_child(hit_shape)
		b.add_child(hit_area)
		add_child(b)
		cups.append(b)
		var s := Sprite2D.new()
		s.name = "CupSprite%d" % i
		s.texture = sheet.texture
		s.centered = false
		s.region_enabled = true
		s.scale = Vector2(_a, _a)
		s.top_level = true
		s.z_index = 1
		s.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(s)
		_sprites.append(s)
	var count := cups.size()
	_frame.resize(count)
	_frame.fill(-1)
	_speed.resize(count)
	_cool.resize(count)
	_fallen.resize(count)
	_pop.resize(count)
	_kick_cool.resize(count)
	_place_sprites()


func _build_button() -> void:
	if not ResourceLoader.exists(RESET_BUTTON):
		return
	_button = (load(RESET_BUTTON) as PackedScene).instantiate()
	_button.name = "ResetButton"
	_button.set(&"prompt", button_prompt)
	add_child(_button)
	_button.position = button_offset
	if _button.has_signal(&"pressed"):
		_button.connect(&"pressed", reset_cups)


# Rebuilds the pyramid with a short pop, row by row from the bottom.
func reset_cups() -> void:
	phase = Phase.BUILD
	_build_t = build_step
	_build_i = 0
	for i in cups.size():
		var b := cups[i]
		b.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		b.freeze = true
		b.linear_velocity = Vector2.ZERO
		b.angular_velocity = 0.0
		b.global_transform = Transform2D(0.0, to_global(_slots[i]))
		b.reset_physics_interpolation()
		_sprites[i].visible = false
		_fallen[i] = 0
		_frame[i] = -1
	var area := Rect2(global_position + Vector2(-TABLE_ART.get_width() * _a, -900), Vector2(TABLE_ART.get_width() * _a * 2.0, 1000))
	for arrow in get_tree().get_nodes_in_group(Arrow.GROUP):
		if arrow is Node2D and area.has_point(arrow.global_position) and arrow.has_method(&"vanish"):
			arrow.vanish()


func is_standing() -> bool:
	for b in cups:
		if not b.sleeping:
			return false
	return phase == Phase.READY


# One cup takes a hit from its own hitbox (bullet, punch, kick, slash).
func hit_cup(i: int, point: Vector2, direction: Vector2, damage: float, kind: StringName) -> void:
	if phase != Phase.READY or i < 0 or i >= cups.size():
		return
	var b := cups[i]
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var range_v := bullet_speed if kind == &"bullet" else melee_speed
	var speed := clampf(damage * (70.0 if kind == &"bullet" else 50.0), range_v.x, range_v.y)
	_wake_all()
	b.apply_impulse(dir * speed * b.mass, point - b.global_position)
	var off := point - b.global_position
	var spin := signf(off.x * dir.y - off.y * dir.x)
	b.apply_torque_impulse((spin if spin != 0.0 else 1.0) * bullet_spin * b.mass * 60.0 * (1.0 if kind == &"bullet" else 0.5))
	if _fx_tokens >= 1.0:
		_fx_tokens -= 1.0
		var s := clampf(speed / range_v.y, 0.35, 1.0)
		_fx.shreds(point, PLASTIC, 5 if kind == &"bullet" else 3)
		Feedback.sfx(&"cup_hit", point, s)
		Feedback.haptic(&"cup_hit", s * 0.6)
	cup_struck.emit(b, point)


# Take hits like any damageable: the nearest cup to the point gets the impulse.
func take_hit(point: Vector2, direction: Vector2, damage: float, _kind: StringName) -> void:
	var best: RigidBody2D
	var best_d := INF
	for b in cups:
		var d := b.global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = b
	if best == null or best_d > 90.0 * 90.0:
		return
	var impulse := direction.normalized() * best.mass * clampf(damage * 60.0, 300.0, 2200.0)
	best.sleeping = false
	best.apply_impulse(impulse, point - best.global_position)
	_on_cup_struck(best, point, impulse)


func _sync_player() -> void:
	var p := get_tree().get_first_node_in_group(&"player") as Node2D
	if p == _player:
		return
	_player = p
	if p is PhysicsBody2D:
		for b in cups:
			b.add_collision_exception_with(p)


func _kick_floor_cups(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var pv: Vector2 = _player.get(&"velocity") if &"velocity" in _player else Vector2.ZERO
	var body: Rect2 = _player.get_hurt_rect() if _player.has_method(&"get_hurt_rect") else Rect2(_player.global_position - Vector2(54, 426), Vector2(108, 426))
	var floor_y := global_position.y
	var reach := body.grow_individual(18.0, 0.0, 18.0, 0.0)
	for i in cups.size():
		_kick_cool[i] = maxf(0.0, _kick_cool[i] - delta)
		var b := cups[i]
		if b.freeze or _kick_cool[i] > 0.0 or floor_y - b.global_position.y > floor_band:
			continue
		if not reach.has_point(b.global_position):
			continue
		var rel := pv.x - b.linear_velocity.x
		if absf(rel) < kick_min_speed:
			continue
		var speed := clampf(rel * kick_factor, -kick_max_speed, kick_max_speed)
		b.sleeping = false
		b.apply_central_impulse(Vector2(speed, -kick_lift * absf(speed) / kick_max_speed) * b.mass)
		b.apply_torque_impulse(speed * 0.02 * b.mass * 60.0)
		_kick_cool[i] = kick_cooldown
		if absf(speed) > 450.0 and _fall_tokens >= 1.0:
			_fall_tokens -= 1.0
			Feedback.sfx(&"cup_fall", b.global_position, clampf(absf(speed) / kick_max_speed, 0.3, 1.0))
		elif _hit_tokens >= 1.0:
			_hit_tokens -= 1.0
			Feedback.sfx(&"cup_hit", b.global_position, clampf(absf(speed) / kick_max_speed, 0.2, 0.7))


func _physics_process(delta: float) -> void:
	_sync_player()
	if phase == Phase.READY:
		_kick_floor_cups(delta)
	_hit_tokens = minf(hits_per_second, _hit_tokens + hits_per_second * delta)
	_fall_tokens = minf(falls_per_second * 0.75, _fall_tokens + falls_per_second * delta)
	_fx_tokens = minf(hit_fx_per_second * 0.5, _fx_tokens + hit_fx_per_second * delta)
	for i in cups.size():
		_cool[i] = maxf(0.0, _cool[i] - delta)
		if not cups[i].sleeping:
			_speed[i] = cups[i].linear_velocity.length()


func _process(delta: float) -> void:
	if phase == Phase.BUILD:
		_update_build(delta)
	_place_sprites(delta)


func _update_build(delta: float) -> void:
	_build_t -= delta
	while _build_t <= 0.0 and phase == Phase.BUILD:
		_build_t += build_step
		if _build_i < cups.size():
			var i := _build_i
			_sprites[i].visible = true
			_pop[i] = pop_time
			_fx.puff(to_global(_slots[i]) + Vector2(0, CUP_HULL[0].y * _a), 5)
			Feedback.sfx(&"cup_hit", to_global(_slots[i]), 0.25 + 0.05 * (i % 3))
			_build_i += 1
		elif _build_i == cups.size():
			_build_i += 1
		else:
			for b in cups:
				b.freeze = false
				b.linear_velocity = Vector2.ZERO
				b.angular_velocity = 0.0
				b.sleeping = true
			phase = Phase.READY
			cups_reset.emit()


func _place_sprites(delta := 0.0) -> void:
	var sheet := cup_sheet()
	for i in cups.size():
		var s := _sprites[i]
		if not s.visible:
			continue
		var t: Transform2D = cups[i].global_transform
		var k := posmod(roundi(t.get_rotation() / ANGLE_STEP), STEPS)
		var lift := 0.0
		if _pop[i] > 0.0:
			_pop[i] -= delta
			k = WHITE_FRAME if _pop[i] > pop_time * 0.4 else 0
			lift = -_a if _pop[i] > 0.0 else 0.0
		if k != _frame[i]:
			_frame[i] = k
			s.region_rect = sheet.rects[k]
		var o: Vector2 = t.origin
		s.global_position = Vector2(roundf(o.x / _a) * _a, roundf(o.y / _a) * _a + lift) + sheet.offsets[k] * _a


func _wake_all() -> void:
	for b in cups:
		b.sleeping = false


func _on_cup_struck(cup: RigidBody2D, point: Vector2, impulse: Vector2) -> void:
	if phase != Phase.READY:
		return
	_wake_all()
	cup.apply_central_impulse(Vector2(0, -strike_lift * cup.mass))
	var along := impulse.normalized()
	for b in cups:
		if b == cup:
			continue
		var d := b.global_position - point
		var dist := d.length()
		if dist >= blast_radius:
			continue
		var f := 1.0 - dist / blast_radius
		var push := (d / maxf(dist, 1.0) * 0.5 + along * 0.6 + Vector2(0, -0.35)).normalized()
		b.apply_impulse(push * b.mass * blast_speed * f, Vector2(randf_range(-12.0, 12.0), -18.0))
	var s := clampf(impulse.length() / 220.0, 0.4, 1.0)
	Feedback.sfx(&"cup_hit", point, s)
	Feedback.haptic(&"cup_hit", s)
	var i := cups.find(cup)
	if i >= 0:
		_cool[i] = hit_cooldown
	cup_struck.emit(cup, point)


func _on_cup_contact(body: Node, i: int) -> void:
	if phase != Phase.READY:
		return
	var cup := cups[i]
	var speed := maxf(_speed[i], cup.linear_velocity.length())
	if body is RigidBody2D or body == _table:
		if body is RigidBody2D and (body as RigidBody2D).sleeping:
			(body as RigidBody2D).sleeping = false
		if speed >= hit_speed and _cool[i] <= 0.0 and _hit_tokens >= 1.0:
			_hit_tokens -= 1.0
			_cool[i] = hit_cooldown
			Feedback.sfx(&"cup_hit", cup.global_position, clampf(speed / 900.0, 0.2, 1.0))
		return
	# The floor or a wall: the first landing of each cup after a reset.
	if _fallen[i] == 0:
		_fallen[i] = 1
		if _fall_tokens >= 1.0:
			_fall_tokens -= 1.0
			Feedback.sfx(&"cup_fall", cup.global_position, clampf(speed / 1100.0, 0.3, 1.0))
			Feedback.haptic(&"cup_hit", 0.4)
	elif speed >= hit_speed * 1.5 and _cool[i] <= 0.0 and _hit_tokens >= 1.0:
		_hit_tokens -= 1.0
		_cool[i] = hit_cooldown
		Feedback.sfx(&"cup_hit", cup.global_position, clampf(speed / 1100.0, 0.2, 0.7))
