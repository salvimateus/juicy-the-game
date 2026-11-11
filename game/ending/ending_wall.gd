class_name EndingWall
extends StaticBody2D

# Last wall of the level. Pushing it builds up a quake (shake, rumble, rumble pad, dust, cracks);
# when it completes the ceiling caves in: physical rocks fall, a screen-space avalanche covers
# the screen, then the end screen ("FIM", "OBRIGADO POR JOGAR", A restarts the scene).
# Origin: bottom of the wall face (the left side) on the floor; the wall extends to +x and up.

signal collapse_started
signal screen_covered
signal ending_shown
signal credits_shown

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const DebrisParticles := preload("res://game/breakable/debris_particles.gd")
const EndingArt := preload("res://game/ending/ending_art.gd")
const EndingOverlay := preload("res://game/ending/ending_overlay.gd")

enum Phase { IDLE, COLLAPSE, COVERED, ENDED }

const SIGN_PIXEL := 3
const SIGN_POST_H := 44
const CRACK_H := 240
const CRACK_ORIGIN_UP := 46

@export var width_px := 600.0
@export var height_px := 4800.0
# Sign post centre, in units from the wall face (negative is in front of the wall).
@export var sign_x := -620.0
# Sign art at one texel per SIGN_PIXEL units, base at the bottom; without it a procedural sign
# with sign_lines is drawn.
@export var sign_texture: Texture2D = preload("res://game/ending/art/push_sign.png")
# Art pixels of the sign base sunk into the ground, so the grass tuft sits on the turf.
@export var sign_sink := 2
@export var sign_lines := PackedStringArray(["EMPURRE", "A PAREDE"])
@export_group("Push")
@export var push_time := 6.0
@export var decay_delay := 0.6
@export var decay_rate := 0.07
@export var push_reach := 200.0
# Past this progress the wall is doomed: control is taken and the progress runs on by itself.
@export var point_of_no_return := 0.7
@export var doom_accel := 0.6
@export var doom_rocks := 4
@export var crack_thresholds := PackedFloat32Array([0.1, 0.3, 0.55, 0.8])
@export var shake_min := 3.0
@export var shake_max := 30.0
@export var rumble_min := 0.12
@export var dust_rate_min := 2.0
@export var dust_rate_max := 90.0
@export_group("Collapse")
@export var game_gravity := 2600.0
@export var rock_count := 46
@export var rock_spawn_time := 2.4
@export var overlay_delay := 1.8
@export var collapse_shake := 70.0
@export var rock_sfx_interval := 0.06
@export var rock_haptic_interval := 0.1
@export var cave_in_tail := 3.7
@export var debris_layer := 1 << 4
@export var debris_mask := 1 | (1 << 4)

var progress := 0.0
var phase := Phase.IDLE

var _a := 6
var _w := 600.0
var _h := 4800.0
var _wall_sprite: Sprite2D
var _crack_sprite: Sprite2D
var _cracks: Array[ImageTexture] = []
var _stage := 0
var _sign: Sprite2D
var _sign_base := Vector2.ZERO
var _particles: Node
var _player: Node2D
var _since_push := 99.0
var _dust_acc := 0.0
var _jolt_left := 0.0
var _rumble_sfx := -1
var _rumble_haptic := -1
var _rumble_on := false
var _t := 0.0
var _clock := 0.0
var _doomed := false
var _doom_t := 0.0
var _rocks_root: Node2D
var _rocks: Array = []
var _spawned := 0
var _last_rock_sfx := -1.0
var _last_rock_haptic := -1.0
var _overlay: CanvasLayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 777
	_a = GameScale.art_pixel()
	global_position = global_position.snapped(Vector2(_a, _a))
	_w = roundf(width_px / _a) * _a
	_h = roundf(height_px / _a) * _a
	set_meta(&"surface", &"stone")
	set_meta(&"wall_top", global_position.y - _h)
	set_meta(&"wall_bottom", global_position.y)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_w, _h)
	shape.shape = rect
	shape.position = Vector2(_w * 0.5, -_h * 0.5)
	add_child(shape)

	_wall_sprite = Sprite2D.new()
	_wall_sprite.texture = PixelArt.stone_block(int(_w / _a), int(_h / _a), true, false)
	_wall_sprite.centered = false
	_wall_sprite.scale = Vector2(_a, _a)
	_wall_sprite.position = Vector2(0, -_h - PixelArt.STONE_TUFT_ROWS * _a)
	add_child(_wall_sprite)

	var cw := int(_w / _a)
	_cracks = EndingArt.crack_stages(cw, CRACK_H, Vector2i(0, CRACK_H - CRACK_ORIGIN_UP), crack_thresholds.size(), 31)
	_crack_sprite = Sprite2D.new()
	_crack_sprite.centered = false
	_crack_sprite.scale = Vector2(_a, _a)
	_crack_sprite.position = Vector2(0, -CRACK_H * _a)
	_crack_sprite.visible = false
	_wall_sprite.add_sibling(_crack_sprite)

	_sign = Sprite2D.new()
	if sign_texture:
		_sign.texture = sign_texture
	else:
		var s := EndingArt.sign_image(sign_lines, SIGN_POST_H)
		_sign.texture = ImageTexture.create_from_image(s.image)
	var size := _sign.texture.get_size()
	_sign.centered = false
	_sign.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sign.scale = Vector2(SIGN_PIXEL, SIGN_PIXEL)
	_sign_base = Vector2(sign_x - size.x * SIGN_PIXEL * 0.5, (sign_sink - size.y) * SIGN_PIXEL).snapped(Vector2(SIGN_PIXEL, SIGN_PIXEL))
	_sign.position = _sign_base
	add_child(_sign)

	_particles = DebrisParticles.new()
	_particles.z_index = 5
	add_child(_particles)
	_particles.setup(_a)

	_rocks_root = Node2D.new()
	_rocks_root.top_level = true
	_rocks_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rocks_root.z_index = 4
	add_child(_rocks_root)
	# Builds the shared sheets now, so the collapse never hitches on them.
	EndingArt.rock_set()
	EndingArt.rubble_tile()


func get_face_x() -> float:
	return global_position.x


func is_collapsing() -> bool:
	return phase != Phase.IDLE


func _find_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node2D
	return _player


func _player_pushing() -> bool:
	var p := _find_player()
	if p == null:
		return false
	if p.has_method(&"is_controlled") and p.is_controlled():
		return false
	if not bool(p.get(&"pushing")):
		return false
	var facing: Variant = p.get(&"facing")
	if facing != null and int(facing) != 1:
		return false
	var dx := global_position.x - p.global_position.x
	return dx > 0.0 and dx < push_reach and absf(p.global_position.y - global_position.y) < 48.0


func _physics_process(delta: float) -> void:
	_clock += delta
	match phase:
		Phase.IDLE:
			_push_tick(delta)
		Phase.COLLAPSE, Phase.COVERED:
			_collapse_tick(delta)


func _process(_delta: float) -> void:
	for r in _rocks:
		var body: RigidBody2D = r.body
		if body.freeze:
			continue
		var f := Engine.get_physics_interpolation_fraction()
		var a0: Transform2D = r.xf0
		var a1: Transform2D = r.xf1
		var origin := a0.origin.lerp(a1.origin, f)
		var rot := lerp_angle(a0.get_rotation(), a1.get_rotation(), f)
		var i := posmod(roundi(rot / (TAU / EndingArt.ROCK_ANGLES)), EndingArt.ROCK_ANGLES)
		var sh: Dictionary = r.shape
		var sprite: Sprite2D = r.sprite
		sprite.region_rect = sh.rects[i]
		sprite.global_position = origin.snapped(Vector2(_a, _a)) + sh.offsets[i] * _a


# --- Push build-up ---------------------------------------------------------------------------

func _push_tick(delta: float) -> void:
	var pushing := _player_pushing()
	if _doomed:
		_doom_t += delta
		progress = minf(1.0, progress + delta / push_time * (1.0 + doom_accel * _doom_t))
	elif pushing:
		_since_push = 0.0
		progress = minf(1.0, progress + delta / push_time)
	else:
		_since_push += delta
		if _since_push > decay_delay:
			progress = maxf(0.0, progress - decay_rate * delta)
	if not _doomed and progress >= point_of_no_return:
		_doom()
	if not _rocks.is_empty():
		_rock_impacts()
	var stage := 0
	for th in crack_thresholds:
		if progress >= th:
			stage += 1
	if stage > _stage:
		_set_stage(stage)
	var k := pow(progress, 1.4)
	_update_rumble(progress > 0.002, lerpf(rumble_min, 1.0, k))
	if progress > 0.002:
		_shake(lerpf(shake_min, shake_max, k), 0.2)
		_jolt_left -= delta
		if _jolt_left <= 0.0 and progress > 0.15:
			_jolt_left = _rng.randf_range(0.25, 0.9) * lerpf(2.5, 0.35, progress)
			_shake(lerpf(shake_min, shake_max, k) * 2.0, 0.14)
			Feedback.haptic(&"rock_fall", lerpf(0.2, 0.7, progress))
			_burst(_rng.randi_range(2, 4 + int(progress * 8)), false)
	_wobble()
	_emit_dust(delta, lerpf(dust_rate_min, dust_rate_max, pow(progress, 1.6)))
	if progress >= 1.0:
		_start_collapse()


func _doom() -> void:
	_doomed = true
	# The pause menu stays shut from here to the end screen.
	add_to_group(&"pause_blocker")
	_doom_t = 0.0
	var p := _find_player()
	if p and p.has_method(&"take_control"):
		p.take_control(self)
	Feedback.sfx(&"rock_fall", global_position + Vector2(0, -CRACK_ORIGIN_UP * _a), 1.0)
	Feedback.sfx(&"wall_crack", global_position + Vector2(0, -CRACK_ORIGIN_UP * _a), 1.0)
	Feedback.haptic(&"rock_fall", 1.0)
	_shake(collapse_shake * 0.8, 0.35)
	if p and p.has_method(&"hitstop"):
		p.hitstop(0.05)
	_burst(30, true)
	for i in doom_rocks:
		_spawn_rock(_rng.randi_range(0, 4))


func _update_rumble(on: bool, strength: float) -> void:
	if on and not _rumble_on:
		_rumble_on = true
		_rumble_sfx = Feedback.sfx_loop(&"quake_rumble")
		_rumble_haptic = Feedback.haptic_loop(&"quake", strength)
	elif not on and _rumble_on:
		_stop_rumble(0.4)
	if _rumble_on:
		Feedback.sfx_loop_update(_rumble_sfx, strength)
		Feedback.haptic_loop_strength(_rumble_haptic, strength)


func _stop_rumble(fade: float) -> void:
	_rumble_on = false
	Feedback.sfx_stop(_rumble_sfx, fade)
	Feedback.haptic_stop(_rumble_haptic)
	_rumble_sfx = -1
	_rumble_haptic = -1


func _set_stage(stage: int) -> void:
	_stage = stage
	_crack_sprite.texture = _cracks[mini(stage, _cracks.size() - 1)]
	_crack_sprite.visible = stage > 0
	var at := global_position + Vector2(_a * 2, -CRACK_ORIGIN_UP * _a)
	Feedback.sfx(&"wall_crack", at, 0.5 + 0.12 * stage)
	Feedback.haptic(&"rock_fall", 0.4 + 0.15 * stage)
	_shake(shake_max * (0.6 + 0.2 * stage), 0.25)
	_burst(8 + stage * 6, true)


# Sign and wall rattle by whole art pixels once the quake is strong enough.
func _wobble() -> void:
	var p := progress if phase == Phase.IDLE else 1.0
	var sx := 0.0
	if p > 0.25 and _rng.randf() < p * 0.6:
		sx = SIGN_PIXEL * (_rng.randi_range(-1, 1))
	var sy: float = -SIGN_PIXEL if p > 0.7 and _rng.randf() < (p - 0.7) else 0.0
	_sign.position = _sign_base + Vector2(sx, sy)
	var wx := 0.0
	if p > 0.6 and _rng.randf() < (p - 0.5):
		wx = _a * _rng.randi_range(-1, 1)
	_wall_sprite.position.x = wx
	_crack_sprite.position.x = wx


func _view_rect() -> Rect2:
	var vp := get_viewport()
	var inv := vp.get_canvas_transform().affine_inverse()
	var r := vp.get_visible_rect()
	var tl := inv * r.position
	var br := inv * r.end
	return Rect2(tl, br - tl)


func _emit_dust(delta: float, rate: float) -> void:
	_dust_acc += rate * delta
	if _dust_acc < 1.0:
		return
	var view := _view_rect()
	var floor_y := global_position.y
	var face := global_position.x
	var heavy := phase != Phase.IDLE
	while _dust_acc >= 1.0:
		_dust_acc -= 1.0
		var x := _rng.randf_range(view.position.x, minf(view.end.x, face + _w))
		var y := view.position.y - _rng.randf_range(0.0, 60.0)
		if _rng.randf() < 0.6:
			var c := PixelArt.STONE_LIGHT if _rng.randf() < 0.5 else PixelArt.PEBBLE
			c.a = 0.75
			_particles.emit(Vector2(x, y), Vector2(_rng.randf_range(-40, 40), _rng.randf_range(120, 320)),
				_rng.randf_range(2.2, 3.4), 1, c, 700.0, 0.5, floor_y, true)
		else:
			if _rng.randf() < 0.5:
				x = face - _rng.randf_range(-40.0, 360.0)
			var size := 1 + int(_rng.randf() * (1.0 + progress * 2.0 + (2.0 if heavy else 0.0)))
			var c2 := [PixelArt.STONE, PixelArt.STONE_SHADE, PixelArt.STONE_LIGHT][_rng.randi_range(0, 2)] as Color
			_particles.emit(Vector2(x, y), Vector2(_rng.randf_range(-60, 60), _rng.randf_range(100, 500)),
				_rng.randf_range(1.6, 2.4), size, c2, game_gravity * 0.8, 0.1, floor_y, false)


# Chips popping off the wall face around the push point.
func _burst(n: int, big: bool) -> void:
	var face := global_position.x
	for i in n:
		var y := global_position.y - _rng.randf_range(20.0, CRACK_ORIGIN_UP * _a * 2.0)
		var c := [PixelArt.STONE, PixelArt.STONE_SHADE, PixelArt.STONE_LIGHT, PixelArt.MORTAR][_rng.randi_range(0, 3)] as Color
		_particles.emit(Vector2(face - 2.0, y), Vector2(-_rng.randf_range(80, 420), -_rng.randf_range(40, 380)),
			_rng.randf_range(0.8, 1.6), _rng.randi_range(1, 3 if big else 2), c, game_gravity, 0.2, global_position.y, false)


func _shake(amount: float, duration: float) -> void:
	var p := _find_player()
	if p and p.has_method(&"camera_shake"):
		p.camera_shake(amount, duration)


# --- Collapse --------------------------------------------------------------------------------

func _start_collapse() -> void:
	phase = Phase.COLLAPSE
	_t = 0.0
	progress = 1.0
	var p := _find_player()
	if p and p.has_method(&"take_control"):
		p.take_control(self)
	_set_stage(crack_thresholds.size())
	_update_rumble(true, 1.0)
	Feedback.sfx(&"wall_crack", global_position + Vector2(0, -300), 1.0)
	Feedback.haptic(&"rock_fall", 1.0)
	_shake(collapse_shake, 0.6)
	if p and p.has_method(&"hitstop"):
		p.hitstop(0.08)
	_burst(40, true)
	collapse_started.emit()


func _collapse_tick(delta: float) -> void:
	_t += delta
	if phase == Phase.COLLAPSE:
		var target := int(ceilf(rock_count * pow(minf(1.0, _t / rock_spawn_time), 0.8)))
		while _spawned - doom_rocks < target:
			_spawn_rock()
		_shake(collapse_shake * lerpf(0.55, 0.85, minf(1.0, _t / 3.0)), 0.3)
		_emit_dust(delta, 110.0)
		_wobble()
		_update_rumble(true, 1.0)
		if _overlay == null and _t >= overlay_delay:
			_overlay = EndingOverlay.new()
			add_child(_overlay)
			_overlay.covered.connect(_on_covered)
			_overlay.ending_shown.connect(func() -> void: ending_shown.emit())
			_overlay.credits_shown.connect(func() -> void: credits_shown.emit())
			_overlay.start()
		_rock_impacts()
	elif phase == Phase.COVERED and _t >= cave_in_tail:
		phase = Phase.ENDED
		_overlay.start_end()


func _spawn_rock(force_idx := -1) -> void:
	_spawned += 1
	var sheet := EndingArt.rock_set()
	var shapes: Array = sheet.shapes
	var roll := _rng.randf()
	var idx := _rng.randi_range(0, 4) if roll < 0.25 else (_rng.randi_range(5, 9) if roll < 0.6 else _rng.randi_range(10, shapes.size() - 1))
	if force_idx >= 0:
		idx = force_idx
	var sh: Dictionary = shapes[idx]
	var view := _view_rect()
	var p := _find_player()
	var face := global_position.x
	var x := _rng.randf_range(view.position.x + 40.0, face - 30.0)
	if p and _rng.randf() < 0.45:
		x = clampf(p.global_position.x + _rng.randf_range(-500.0, 300.0), view.position.x, face - 30.0)
	var body := RigidBody2D.new()
	body.collision_layer = debris_layer
	body.collision_mask = debris_mask
	body.gravity_scale = game_gravity / float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	body.mass = maxf(0.2, float(sh.size * sh.size) / 60.0)
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.2
	mat.friction = 0.9
	body.physics_material_override = mat
	var cs := CollisionShape2D.new()
	var poly := ConvexPolygonShape2D.new()
	var pts := PackedVector2Array()
	for v in sh.poly:
		pts.append(v * _a)
	poly.points = pts
	cs.shape = poly
	body.add_child(cs)
	_rocks_root.add_child(body)
	body.global_position = Vector2(x, view.position.y - 120.0 - _rng.randf_range(0.0, 420.0))
	body.rotation = _rng.randf() * TAU
	body.linear_velocity = Vector2(_rng.randf_range(-140.0, 140.0), _rng.randf_range(300.0, 900.0))
	body.angular_velocity = _rng.randf_range(-6.0, 6.0)
	body.reset_physics_interpolation()
	var sprite := Sprite2D.new()
	sprite.texture = sheet.texture
	sprite.centered = false
	sprite.region_enabled = true
	sprite.scale = Vector2(_a, _a)
	sprite.top_level = true
	sprite.z_index = 4
	sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rocks_root.add_child(sprite)
	_rocks.append({body = body, sprite = sprite, shape = sh, prev = body.linear_velocity, hits = 0,
		xf0 = body.global_transform, xf1 = body.global_transform})


func _rock_impacts() -> void:
	for r in _rocks:
		var body: RigidBody2D = r.body
		r.xf0 = r.xf1
		r.xf1 = body.global_transform
		var v := body.linear_velocity
		var prev: Vector2 = r.prev
		r.prev = v
		var dv := (prev - v).length()
		if dv < 500.0 or int(r.hits) >= 3:
			continue
		r.hits = int(r.hits) + 1
		var size_k := float(r.shape.size) / 34.0
		var s := clampf(dv / 2200.0, 0.2, 1.0) * lerpf(0.5, 1.0, size_k)
		if _clock - _last_rock_sfx >= rock_sfx_interval:
			_last_rock_sfx = _clock
			Feedback.sfx(&"rock_fall", body.global_position, s)
		if _clock - _last_rock_haptic >= rock_haptic_interval and size_k > 0.4:
			_last_rock_haptic = _clock
			Feedback.haptic(&"rock_fall", s)
		if size_k > 0.6:
			_shake(collapse_shake * 1.2 * s, 0.2)
		for i in 3:
			var c := [PixelArt.STONE, PixelArt.STONE_LIGHT, PixelArt.PEBBLE][i] as Color
			_particles.emit(body.global_position + Vector2(0, r.shape.size * _a * 0.4), Vector2(_rng.randf_range(-300, 300), -_rng.randf_range(80, 300)),
				_rng.randf_range(0.5, 1.0), _rng.randi_range(1, 2), c, game_gravity, 0.3, global_position.y, false)


func _on_covered() -> void:
	phase = Phase.COVERED
	_t = 0.0
	_stop_rumble(0.25)
	Feedback.sfx(&"cave_in")
	Feedback.haptic(&"cave_in", 1.0)
	_overlay.jolt(18.0)
	_particles.clear()
	for r in _rocks:
		var body: RigidBody2D = r.body
		body.freeze = true
		body.process_mode = Node.PROCESS_MODE_DISABLED
	screen_covered.emit()


func coverage() -> float:
	return _overlay.coverage() if _overlay else 0.0


func _exit_tree() -> void:
	if _rumble_on:
		_stop_rumble(0.1)
