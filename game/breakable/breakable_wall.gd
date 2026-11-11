class_name BreakableWall
extends StaticBody2D

# Brick wall that a kick shatters into pre-fractured rigid pieces and that restore() rebuilds.
# Origin at the bottom centre, on the floor. Units are source px; the art grid is ART_PIXEL.
# Pieces are pooled: break_at() and restore() only re-enable, reposition and hide nodes.

signal impacted(point: Vector2, strength: float)
signal restored
signal debris_hit(body: Node2D, push: Vector2)

const GameScale := preload("res://game/game_scale.gd")
const PixelArt := preload("res://game/pixel_art.gd")
const Feedback := preload("res://game/feedback.gd")
const Fracture := preload("res://game/breakable/wall_fracture.gd")
const Particles := preload("res://game/breakable/debris_particles.gd")
const InteractionScript := preload("res://game/breakable/wall_interaction.gd")
const HitboxScript := preload("res://game/breakable/wall_hitbox.gd")

enum Phase { INTACT, BROKEN, VANISH, BUILD }
enum { PIECE_OFF, PIECE_LIVE, PIECE_FADING }

const STEPS := Fracture.ANGLE_STEPS
const ANGLE_STEP := TAU / Fracture.ANGLE_STEPS
const DUST_COLORS := [Color("#8a7872"), Color("#6c5e5e"), Color("#a4908a")]
const CHIP_COLORS := [PixelArt.STONE, PixelArt.STONE_LIGHT, PixelArt.STONE_SHADE, PixelArt.MORTAR]

@export_group("Shape")
@export var width_px := 26
@export var height_px := 60
@export var fracture_seed := 7
# Height (0 bottom, 1 top) of the band where bricks split into halves and chips: where the kick lands.
@export_range(0.0, 1.0) var weak_height := 0.6
@export_range(30, 60) var max_pieces := 56

@export_group("Physics")
@export var game_gravity := 2600.0
# Debris sits on its own layer and collides with the world and itself. Characters share layer 1
# with the world, so each piece gets a collision exception with every character that comes near:
# rubble never touches the player physically. Characters wade through it (soft shove of big pieces)
# and only pieces still flying from the break push them (once per piece, see _push_characters).
@export_flags_2d_physics var debris_layer := 1 << 4
@export_flags_2d_physics var debris_mask := 1 | (1 << 4)
@export var impulse_radius := 130.0
@export var friction := 0.85
@export var bounce := 0.18
@export var mass_per_px := 0.02

@export_group("Player")
@export_flags_2d_physics var player_mask := 1
@export_flags_2d_physics var hitbox_layer := 1 << 6
@export var interact_margin := 360.0
@export var push_min_speed := 380.0
@export var push_factor := 0.25
@export var push_max := 260.0
# Only pieces launched by the break push characters, and only this long after the impact.
@export var push_window := 1.5
@export var wade_speed_factor := 0.6

@export_group("Hits")
# take_hit(kind = &"kick"): direction * kick_speed is the velocity given at the impact point.
@export var kick_speed := 1900.0
@export var kick_damage_reference := 10.0

@export_group("Feedback")
@export var bounce_sfx_rate := 10.0
@export var bounce_min_dv := 420.0
@export var landing_dust_dv := 650.0

const STILL_SPEED := 16.0
const STILL_SPIN := 0.6
const STILL_TIME := 0.35
const FADE_TIME := 0.5
const SETTLE_TIMEOUT := 8.0
const VANISH_BATCH := 7
const STEP_TIME := 1.0 / 30.0
const BUILD_ROWS_PER_STEP := 6
const SHAKE_STEPS := 6

var last_break_usec := 0
var prefracture_usec := 0
# Worst per-frame cost of this wall's own scripts since the last break (profiling aid).
var max_process_usec := 0
var max_physics_usec := 0

var _a := 6
var _w := 26
var _h := 60
var _data: Dictionary
var _phase := Phase.INTACT
var _n := 0
var _bodies: Array[RigidBody2D] = []
var _sprites: Array[Sprite2D] = []
var _rest := PackedVector2Array()
var _area_px := PackedInt32Array()
var _tiny := PackedByteArray()
var _state := PackedByteArray()
var _prev_v := PackedVector2Array()
# Physics-tick snapshots for render interpolation (the sprites live outside the bodies).
var _pos0 := PackedVector2Array()
var _pos1 := PackedVector2Array()
var _rot0 := PackedFloat32Array()
var _rot1 := PackedFloat32Array()
var _still := PackedFloat32Array()
var _fade := PackedFloat32Array()
var _frame := PackedInt32Array()
var _rects: Array[Rect2] = []
var _offsets := PackedVector2Array()
var _half := PackedVector2Array()
var _order := PackedInt32Array()
var _order_at := 0
var _shape: CollisionShape2D
var _wall_sprite: Sprite2D
var _pieces_root: Node2D
var _particles: Particles
var _interaction: Area2D
var _interaction_shape: RectangleShape2D
var _hitbox: Area2D
var _rng := RandomNumberGenerator.new()
var _break_count := 0
var _broken_time := 0.0
var _settled := false
var _sfx_tokens := 3.0
var _dust_tokens := 4.0
var _step_time := 0.0
var _build_px := 0
var _shake := 0
var _solid_pending := false
var _pushed := PackedByteArray()
var _characters: Array[CharacterBody2D] = []


func _ready() -> void:
	_a = GameScale.art_pixel()
	_w = maxi(width_px / 2 * 2, 4)
	_h = maxi(height_px, BUILD_ROWS_PER_STEP)
	global_position = global_position.snapped(Vector2(_a, _a))
	var t0 := Time.get_ticks_usec()
	_data = Fracture.build(_w, _h, fracture_seed, weak_height, max_pieces, _a)
	prefracture_usec = Time.get_ticks_usec() - t0
	set_meta(&"surface", &"stone")
	set_meta(&"wall_top", global_position.y - _h * _a)
	set_meta(&"wall_bottom", global_position.y)
	_build_intact()
	_build_pieces()
	_particles = Particles.new()
	_particles.name = "Particles"
	_particles.z_index = 3
	add_child(_particles)
	_particles.setup(_a)
	_build_interaction()
	_build_hitbox()


# ---------------------------------------------------------------- public API

func break_at(point: Vector2, impulse: Vector2, strength: float = 1.0) -> void:
	if _phase != Phase.INTACT or _solid_pending:
		return
	var t0 := Time.get_ticks_usec()
	_phase = Phase.BROKEN
	_break_count += 1
	max_process_usec = 0
	max_physics_usec = 0
	_rng.seed = hash(fracture_seed * 7919 + _break_count)
	_broken_time = 0.0
	_settled = false
	_shake = 0
	_shape.set_deferred(&"disabled", true)
	_hitbox.set_deferred(&"monitorable", false)
	_wall_sprite.visible = false
	var local_point := to_local(point)
	var speed := impulse.length()
	var dir := impulse / speed if speed > 0.0 else Vector2.RIGHT
	for i in _n:
		var d := _rest[i] - local_point
		var dist := d.length()
		var f := 1.0 / (1.0 + (dist / impulse_radius) * (dist / impulse_radius))
		var radial := d / dist if dist > 0.01 else dir
		var v := impulse * f * strength
		v += radial * speed * 0.35 * f * strength
		v.y -= speed * 0.12 * f * strength
		v += Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 0.5)) * (30.0 + 160.0 * f) * strength
		var spin := _rng.randf_range(-1.0, 1.0) * (1.5 + 14.0 * f) * strength
		if _tiny[i] == 1:
			spin *= 1.8
		var b := _bodies[i]
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.global_transform = Transform2D(0.0, to_global(_rest[i]))
		b.linear_velocity = v
		b.angular_velocity = spin
		b.sleeping = false
		b.reset_physics_interpolation()
		_state[i] = PIECE_LIVE
		_prev_v[i] = v
		_still[i] = 0.0
		_frame[i] = -1
		_pushed[i] = 0
		_pos0[i] = b.global_position
		_pos1[i] = _pos0[i]
		_rot0[i] = 0.0
		_rot1[i] = 0.0
		_sprites[i].visible = true
	_place_sprites()
	_burst(point, impulse, strength)
	_fit_interaction(false)
	last_break_usec = Time.get_ticks_usec() - t0
	Feedback.sfx(&"wall_crack", point, strength)
	Feedback.sfx(&"wall_break", point, strength)
	Feedback.haptic(&"wall_break", strength)
	impacted.emit(point, strength)


func restore() -> void:
	if _phase != Phase.BROKEN:
		return
	_phase = Phase.VANISH
	_step_time = 0.0
	var live: Array = []
	for i in _n:
		if _state[i] != PIECE_OFF:
			live.append(i)
	# Farthest pieces vanish first, so the rubble pulls back towards the wall.
	live.sort_custom(func(l: int, r: int) -> bool:
		return _bodies[l].position.length_squared() > _bodies[r].position.length_squared())
	_order = PackedInt32Array(live)
	_order_at = 0


func is_broken() -> bool:
	return _phase != Phase.INTACT


func can_interact(player: Node) -> bool:
	if _phase != Phase.BROKEN or _broken_time < 0.4 or player == null:
		return false
	if player is PhysicsBody2D and not _interaction.overlaps_body(player):
		return false
	return not _blocks_wall(player as Node2D)


func interact(player: Node) -> bool:
	if not can_interact(player):
		return false
	restore()
	return true


func get_prompt_anchor() -> Vector2:
	return global_position + Vector2(0, -(_h * _a + 60))


func take_hit(point: Vector2, direction: Vector2, damage: float, kind: StringName) -> void:
	if _phase != Phase.INTACT:
		return
	var s := clampf(damage / kick_damage_reference, 0.6, 1.5) if damage > 0.0 else 1.0
	var dir := direction.normalized() if direction.length_squared() > 0.0 else Vector2.RIGHT
	if kind == &"kick":
		break_at(point, dir * kick_speed, s)
		return
	_shake = SHAKE_STEPS
	_step_time = 0.0
	for j in 5:
		var v := Vector2(-dir.x, -0.6).rotated(_rng.randf_range(-0.6, 0.6)) * _rng.randf_range(180.0, 480.0)
		_particles.emit(point, v, _rng.randf_range(0.3, 0.6), 1, CHIP_COLORS[j % 4], game_gravity, 0.5, global_position.y)
	for j in 3:
		_particles.emit(point, Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-60, -20)), _rng.randf_range(0.3, 0.5),
			2, DUST_COLORS[j % 3], -20.0, 3.0, INF, true)
	Feedback.sfx(&"wall_crack", point, 0.3 * s)


# ---------------------------------------------------------------- build

func _build_intact() -> void:
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_w * _a, _h * _a)
	_shape.shape = rect
	_shape.position = Vector2(0, -_h * _a * 0.5)
	add_child(_shape)
	_wall_sprite = Sprite2D.new()
	_wall_sprite.texture = _data.wall
	_wall_sprite.centered = false
	_wall_sprite.region_enabled = true
	_wall_sprite.scale = Vector2(_a, _a)
	add_child(_wall_sprite)
	_set_wall_rows(_h)


func _build_pieces() -> void:
	var pieces: Array = _data.pieces
	_n = pieces.size()
	_pieces_root = Node2D.new()
	_pieces_root.name = "Pieces"
	_pieces_root.top_level = true
	_pieces_root.z_index = 1
	_pieces_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_pieces_root)
	_pieces_root.global_position = Vector2.ZERO
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = bounce
	var chip_material := PhysicsMaterial.new()
	chip_material.friction = friction * 0.7
	chip_material.bounce = bounce * 1.8
	var default_gravity := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	var gscale := game_gravity / maxf(default_gravity, 1.0)
	_rest.resize(_n)
	_prev_v.resize(_n)
	_pushed.resize(_n)
	_pos0.resize(_n)
	_pos1.resize(_n)
	_rot0.resize(_n)
	_rot1.resize(_n)
	_half.resize(_n)
	_area_px.resize(_n)
	_tiny.resize(_n)
	_state.resize(_n)
	_still.resize(_n)
	_fade.resize(_n)
	_frame.resize(_n)
	_offsets.resize(_n * STEPS)
	for i in _n:
		var p: Dictionary = pieces[i]
		_rest[i] = p.origin
		_half[i] = p.half_size
		_area_px[i] = p.area
		_tiny[i] = 1 if p.tiny else 0
		for k in STEPS:
			_rects.append(p.rects[k])
			_offsets[i * STEPS + k] = p.offsets[k]
		var b := RigidBody2D.new()
		b.name = "Piece%d" % i
		b.collision_layer = debris_layer
		b.collision_mask = debris_mask
		b.mass = maxf(0.05, p.area * mass_per_px)
		b.physics_material_override = chip_material if p.tiny else material
		b.gravity_scale = gscale
		b.linear_damp = 0.05
		b.angular_damp = 0.6
		b.can_sleep = true
		if p.tiny:
			b.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
		var poly := CollisionPolygon2D.new()
		poly.polygon = p.hull
		b.add_child(poly)
		b.position = p.origin
		b.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(b)
		_bodies.append(b)
		var s := Sprite2D.new()
		s.texture = _data.atlas
		s.centered = false
		s.region_enabled = true
		s.scale = Vector2(_a, _a)
		s.visible = false
		_pieces_root.add_child(s)
		_sprites.append(s)


func _build_interaction() -> void:
	_interaction = Area2D.new()
	_interaction.name = "Interaction"
	_interaction.set_script(InteractionScript)
	_interaction.wall = self
	_interaction.interact_radius = interact_margin
	_interaction.collision_layer = 0
	_interaction.collision_mask = player_mask
	_interaction.monitorable = false
	_interaction.body_entered.connect(_on_character_entered)
	_interaction.body_exited.connect(_on_character_exited)
	var shape := CollisionShape2D.new()
	_interaction_shape = RectangleShape2D.new()
	shape.shape = _interaction_shape
	_interaction.add_child(shape)
	add_child(_interaction)
	_fit_interaction(false)


func _build_hitbox() -> void:
	_hitbox = Area2D.new()
	_hitbox.name = "Hitbox"
	_hitbox.set_script(HitboxScript)
	_hitbox.wall = self
	_hitbox.collision_layer = hitbox_layer
	_hitbox.collision_mask = 0
	_hitbox.monitoring = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_w * _a, _h * _a)
	shape.shape = rect
	shape.position = Vector2(0, -_h * _a * 0.5)
	_hitbox.add_child(shape)
	add_child(_hitbox)


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_step(delta)
	max_physics_usec = maxi(max_physics_usec, Time.get_ticks_usec() - t0)


func _physics_step(delta: float) -> void:
	if _solid_pending and not _character_in_footprint():
		_solid_pending = false
		_shape.set_deferred(&"disabled", false)
	if _phase == Phase.BROKEN or _phase == Phase.VANISH:
		_snapshot()
	if _phase != Phase.BROKEN:
		return
	if not _characters.is_empty():
		_push_characters()
	_broken_time += delta
	_sfx_tokens = minf(_sfx_tokens + delta * bounce_sfx_rate, 3.0)
	_dust_tokens = minf(_dust_tokens + delta * 6.0, 4.0)
	var awake := 0
	var min_dv2 := bounce_min_dv * bounce_min_dv
	for i in _n:
		if _state[i] != PIECE_LIVE:
			continue
		var b := _bodies[i]
		if b.sleeping:
			_prev_v[i] = Vector2.ZERO
			if _tiny[i] == 1:
				_state[i] = PIECE_FADING
				_fade[i] = 0.0
			continue
		awake += 1
		var v := b.linear_velocity
		var dv := v - _prev_v[i]
		_prev_v[i] = v
		var dv2 := dv.length_squared()
		if dv2 > min_dv2:
			_on_piece_impact(i, b, dv, sqrt(dv2))
		if v.length_squared() < STILL_SPEED * STILL_SPEED and absf(b.angular_velocity) < STILL_SPIN:
			_still[i] += delta
			if _still[i] > STILL_TIME:
				b.sleeping = true
		else:
			_still[i] = 0.0
		if _broken_time > SETTLE_TIMEOUT:
			b.sleeping = true
	if awake == 0 and not _settled:
		_settled = true
		_fit_interaction(true)


func _on_piece_impact(i: int, b: RigidBody2D, dv: Vector2, dv_len: float) -> void:
	var size := clampf(_area_px[i] / 60.0, 0.25, 1.0)
	var s := clampf((dv_len - bounce_min_dv) / 1400.0 + 0.2, 0.2, 1.0) * (0.5 + 0.5 * size)
	var pos := b.global_position
	if _sfx_tokens >= 1.0:
		_sfx_tokens -= 1.0
		Feedback.sfx(&"debris_bounce", pos, s)
	# A large piece stopping a downward fall: dust and chips where it lands.
	if _tiny[i] == 0 and _area_px[i] >= 30 and dv.y < -landing_dust_dv * 0.5 and dv_len > landing_dust_dv and _dust_tokens >= 1.0:
		_dust_tokens -= 1.0
		var foot := pos + Vector2(0, _half[i].y * 0.8)
		for j in 4:
			var side := -1.0 if j % 2 == 0 else 1.0
			_particles.emit(foot + Vector2(side * _rng.randf_range(0, _half[i].x), 0),
				Vector2(side * _rng.randf_range(60, 200), _rng.randf_range(-70, -20)),
				_rng.randf_range(0.5, 0.9), _rng.randi_range(2, 3), DUST_COLORS[j % 3], 30.0, 2.5, foot.y, true)
		for j in 2:
			_particles.emit(foot, Vector2(_rng.randf_range(-260, 260), _rng.randf_range(-420, -180)),
				_rng.randf_range(0.4, 0.7), 1, CHIP_COLORS[j], game_gravity, 0.3, global_position.y)


func _on_character_entered(body: Node2D) -> void:
	var c := body as CharacterBody2D
	if c == null or _characters.has(c):
		return
	_characters.append(c)
	for b in _bodies:
		b.add_collision_exception_with(c)


func _on_character_exited(body: Node2D) -> void:
	_characters.erase(body as CharacterBody2D)


# Flying pieces from the break shove a character once each (speed relative to the character, and
# only while closing in); resting or kicked pieces never push back. Big pieces a character wades
# through are nudged along with it instead of colliding.
func _push_characters() -> void:
	for c in _characters:
		if not is_instance_valid(c):
			continue
		var r := Rect2(c.global_position - Vector2(60, 360), Vector2(120, 360))
		if c.has_method(&"get_hurt_rect"):
			r = c.get_hurt_rect()
		var cv := c.velocity
		for i in _n:
			if _state[i] != PIECE_LIVE or _tiny[i] == 1:
				continue
			var b := _bodies[i]
			var p := b.global_position
			var h := _half[i]
			if p.x + h.x < r.position.x or p.x - h.x > r.end.x or p.y + h.y < r.position.y or p.y - h.y > r.end.y:
				continue
			var v := b.linear_velocity
			var rel := v - cv
			var closing := rel.x * (r.get_center().x - p.x) > 0.0 and v.dot(rel) > 0.0
			if _broken_time < push_window and _pushed[i] == 0 and closing \
					and v.length_squared() > push_min_speed * push_min_speed \
					and rel.length_squared() > push_min_speed * push_min_speed:
				_pushed[i] = 1
				var weight := clampf(_area_px[i] / 60.0, 0.3, 1.5)
				var push := Vector2(clampf(rel.x * push_factor * weight, -push_max, push_max), 0.0)
				if c.has_method(&"apply_push"):
					c.call(&"apply_push", push)
				debris_hit.emit(c, push)
			elif _area_px[i] >= 30 and absf(cv.x) > 40.0:
				# Wading: the piece is nudged along, slower than the character, and never pushes back.
				_pushed[i] = 1
				var target := cv.x * wade_speed_factor
				if absf(v.x) < absf(target) or signf(v.x) != signf(target):
					var hop := -120.0 if b.sleeping else v.y
					b.sleeping = false
					_still[i] = 0.0
					b.linear_velocity = Vector2(target, minf(v.y, hop))



func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_step(delta)
	max_process_usec = maxi(max_process_usec, Time.get_ticks_usec() - t0)


func _process_step(delta: float) -> void:
	match _phase:
		Phase.INTACT:
			if _shake > 0:
				_step_time += delta
				while _step_time >= STEP_TIME and _shake > 0:
					_step_time -= STEP_TIME
					_shake -= 1
				_wall_sprite.position.x = -_w * _a * 0.5 + (float(_a) * (1 if _shake % 2 == 1 else -1) if _shake > 0 else 0.0)
		Phase.BROKEN:
			_update_fading(delta)
			_place_sprites()
		Phase.VANISH:
			_place_sprites()
			_step_time += delta
			while _step_time >= STEP_TIME and _phase == Phase.VANISH:
				_step_time -= STEP_TIME
				_vanish_step()
		Phase.BUILD:
			_step_time += delta
			while _step_time >= STEP_TIME and _phase == Phase.BUILD:
				_step_time -= STEP_TIME
				_build_step()


func _snapshot() -> void:
	for i in _n:
		if _state[i] == PIECE_OFF:
			continue
		var b := _bodies[i]
		_pos0[i] = _pos1[i]
		_rot0[i] = _rot1[i]
		_pos1[i] = b.global_position
		_rot1[i] = b.global_rotation


func _place_sprites() -> void:
	var a := float(_a)
	var f := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	for i in _n:
		if _state[i] == PIECE_OFF:
			continue
		var o := _pos0[i].lerp(_pos1[i], f)
		var k := posmod(roundi(lerp_angle(_rot0[i], _rot1[i], f) / ANGLE_STEP), STEPS)
		var s := _sprites[i]
		s.position = Vector2(roundf(o.x / a) * a, roundf(o.y / a) * a) + _offsets[i * STEPS + k]
		if k != _frame[i]:
			_frame[i] = k
			s.region_rect = _rects[i * STEPS + k]


# Settled tiny pieces blink out and leave the simulation.
func _update_fading(delta: float) -> void:
	for i in _n:
		if _state[i] != PIECE_FADING:
			continue
		_fade[i] += delta
		if _fade[i] >= FADE_TIME:
			_disable_piece(i)
		else:
			_sprites[i].visible = int(_fade[i] * 16.0) % 2 == 0


func _disable_piece(i: int) -> void:
	_state[i] = PIECE_OFF
	_sprites[i].visible = false
	_bodies[i].process_mode = Node.PROCESS_MODE_DISABLED


func _vanish_step() -> void:
	var end := mini(_order_at + VANISH_BATCH, _order.size())
	for j in range(_order_at, end):
		var i := _order[j]
		if _state[i] == PIECE_OFF:
			continue
		var c := _sprites[i].position + Vector2(_half[i].x, _half[i].y)
		for m in 2:
			_particles.emit(c + Vector2(_rng.randf_range(-_half[i].x, _half[i].x), 0), Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-90, -40)),
				_rng.randf_range(0.25, 0.45), _rng.randi_range(2, 3), DUST_COLORS[m], -40.0, 3.0, INF, true)
		_disable_piece(i)
	_order_at = end
	if _order_at >= _order.size():
		for i in _n:
			if _state[i] != PIECE_OFF:
				_disable_piece(i)
		_phase = Phase.BUILD
		_build_px = 0
		_solid_pending = true
		_hitbox.set_deferred(&"monitorable", true)
		_wall_sprite.visible = true
		_set_wall_rows(0)


func _build_step() -> void:
	_build_px = mini(_build_px + BUILD_ROWS_PER_STEP, _h)
	_set_wall_rows(_build_px)
	var top := global_position.y - _build_px * _a
	for j in 3:
		_particles.emit(Vector2(global_position.x + _rng.randf_range(-_w * 0.5, _w * 0.5) * _a, top),
			Vector2(_rng.randf_range(-70, 70), _rng.randf_range(-80, -30)), _rng.randf_range(0.2, 0.4),
			_rng.randi_range(1, 2), DUST_COLORS[j], -30.0, 3.0, INF, true)
	if _build_px >= _h:
		_phase = Phase.INTACT
		_fit_interaction(false)
		restored.emit()


func _set_wall_rows(px: int) -> void:
	_wall_sprite.region_rect = Rect2(0, _h - px, _w, px)
	_wall_sprite.position = Vector2(-_w * _a * 0.5, -px * _a)
	_wall_sprite.visible = px > 0 and (_phase == Phase.INTACT or _phase == Phase.BUILD)


# ---------------------------------------------------------------- effects

func _burst(point: Vector2, impulse: Vector2, strength: float) -> void:
	var speed := impulse.length()
	var dir := impulse / speed if speed > 0.0 else Vector2.RIGHT
	var floor_y := global_position.y
	var crumbs: PackedVector2Array = _data.crumbs
	var crumb_colors: PackedColorArray = _data.crumb_colors
	for j in crumbs.size():
		var p := to_global(crumbs[j])
		var v := (dir * speed * 0.6 + (p - point).normalized() * 260.0).rotated(_rng.randf_range(-0.4, 0.4)) * _rng.randf_range(0.5, 1.1) * strength
		_particles.emit(p, v, _rng.randf_range(0.8, 1.4), 1, crumb_colors[j], game_gravity, 0.2, floor_y)
	for j in roundi(22 * strength):
		var v := dir.rotated(_rng.randf_range(-1.0, 1.0)) * _rng.randf_range(300.0, 1000.0) * strength + Vector2(0, -_rng.randf_range(80, 300))
		_particles.emit(point, v, _rng.randf_range(0.6, 1.3), 1, CHIP_COLORS[j % 4], game_gravity, 0.15, floor_y)
	for j in roundi(16 * strength):
		var v := Vector2.from_angle(_rng.randf_range(0, TAU)) * _rng.randf_range(40.0, 220.0) + dir * 120.0
		_particles.emit(point, v, _rng.randf_range(0.5, 1.1), _rng.randi_range(2, 4), DUST_COLORS[j % 3], -30.0, 2.5, INF, true)
	# Dust cloud from the base that spreads, sinks and settles.
	var half_w := _w * _a * 0.5
	for j in 30:
		var p := global_position + Vector2(_rng.randf_range(-half_w * 1.4, half_w * 1.4), -_rng.randf_range(0, _h * _a * 0.45))
		var v := Vector2(_rng.randf_range(-1, 1) * 200.0 + dir.x * 120.0, _rng.randf_range(-70, -10))
		_particles.emit(p, v, _rng.randf_range(1.4, 2.8), _rng.randi_range(3, 5), DUST_COLORS[j % 3], 70.0, 1.4, floor_y, true)


# Interaction zone: the wall footprint plus a margin while intact, the rubble spread once settled.
func _fit_interaction(from_rubble: bool) -> void:
	var half := Vector2(_w * _a * 0.5 + interact_margin, 0)
	var rect := Rect2(-half.x, -_h * _a - 60, half.x * 2, _h * _a + 120)
	if from_rubble:
		for i in _n:
			if _state[i] != PIECE_OFF:
				var p := _bodies[i].position
				rect = rect.expand(p + Vector2(interact_margin * 0.5, 0)).expand(p - Vector2(interact_margin * 0.5, 0))
	_interaction_shape.size = rect.size
	_interaction.position = rect.get_center()
	# The interaction manager measures this radius from the zone centre; can_interact still needs overlap.
	_interaction.interact_radius = maxf(interact_margin, rect.size.x * 0.5)


# The rebuilt wall only turns solid once no character overlaps it, so nobody ends up inside it.
func _character_in_footprint() -> bool:
	for body in _interaction.get_overlapping_bodies():
		if body is CharacterBody2D and _blocks_wall(body):
			return true
	return false


func _blocks_wall(player: Node2D) -> bool:
	if player == null:
		return false
	var half := _w * _a * 0.5 + 70.0
	var p := player.global_position - global_position
	return absf(p.x) < half and p.y > -_h * _a - 40.0 and p.y < 40.0
