class_name PunchingBag
extends Node2D

# Heavy punching bag hanging from a gallows stand (art: stand.png, bag_chain.png, bag_body.png). The
# origin is the floor point under the hook. The bag is a damped physical pendulum around the hook:
# hits add angular velocity from the torque of their impulse at the contact point, gravity brings it
# back. Chain and body show pre-rotated frames of the same angle (no mixels); a hit also shows a few
# frames of a horizontal squash on the struck side. Only the stand's low base collides, so the
# player can walk up to the bag. Hits come through the Hurtbox child (group `damageable`).

signal hit(point: Vector2, damage: float)
signal combo_changed(combo: int, best: int)

const STAND_ART := preload("res://game/targets/art/stand.png")
const CHAIN_ART := preload("res://game/targets/art/bag_chain.png")
const BODY_ART := preload("res://game/targets/art/bag_body.png")
const PixelRotate := preload("res://game/targets/pixel_rotate.gd")
const PixelFont := preload("res://game/interactables/pixel_font.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")

# Art-pixel layout: the hook ring of stand.png, the hanging point of the bag (top bar centre) in
# bag_chain.png, where bag_body.png starts below it, and the floor row of the stand.
const STAND_HOOK := Vector2(45, 13)
const STAND_FLOOR := 105
const BAG_PIVOT := Vector2(12, 1)
const BODY_TOP := 24
const SQUASH_FROM_ROW := 12
const BASE_RECT := Rect2(0, 102, 56, 3)
# Hurt box of the body in bag coordinates (art px, relative to the top-left of bag_chain.png).
const HURT_RECT := Rect2(1, 24, 21, 53)

const STEP := 5.0 * PI / 180.0
const MAX_ANGLE := 85.0 * PI / 180.0
const SQUASH_MAX := 20.0 * PI / 180.0
const OUTLINE := Color("#141013")

@export_group("Pendulum")
@export var game_gravity := 2600.0
# Hook to the bag's centre of mass, and its radius of gyration (world units).
@export var center_distance := 280.0
@export var gyration := 110.0
@export var angular_damp := 0.45
# Angular speed (rad/s) per unit of damage for a hit at the centre of mass.
@export var spin_per_damage := 0.03
@export var kick_boost := 4.2
@export_group("Feedback")
@export var squash_time := 0.11
@export var creak_speed := 1.4
@export var creak_interval := 0.55
@export var combo_window := 0.9

var angle := 0.0
var angular_velocity := 0.0
var combo := 0
var best_combo := 0

static var _sheet: Dictionary = {}

var _a := 6.0
var _chain: Sprite2D
var _body: Sprite2D
var _hurtbox: Hurtbox
var _fx: TargetFx
var _board: Sprite2D
var _board_img: Image
var _board_tex: ImageTexture
var _k := -1
var _variant := -1
var _squash := 0.0
var _squash_side := 0
var _creak_wait := 0.0
var _last_sign := 0.0
var _combo_t := 0.0


# Atlas with the chain frames, the body frames and the squashed body frames.
static func sheet() -> Dictionary:
	if _sheet.is_empty():
		var angles := PixelRotate.angle_range(-MAX_ANGLE, MAX_ANGLE, STEP)
		var squash_angles := PixelRotate.angle_range(-SQUASH_MAX, SQUASH_MAX, STEP)
		var chain := PixelRotate.load_art(CHAIN_ART)
		var body := PixelRotate.load_art(BODY_ART)
		var body_pivot := BAG_PIVOT - Vector2(0, BODY_TOP)
		var sets := [PixelRotate.frames(chain, BAG_PIVOT, angles), PixelRotate.frames(body, body_pivot, angles)]
		# Squash variants: struck from the left by 1 and 2 art px, then from the right.
		for side in [1, -1]:
			for depth in [1, 2]:
				sets.append(PixelRotate.frames(_dent(body, side, depth), body_pivot, squash_angles))
		var images: Array[Image] = []
		var offsets := PackedVector2Array()
		for s in sets:
			images.append_array(s.images)
			offsets.append_array(s.offsets)
		var packed := PixelRotate.pack(images)
		_sheet = {texture = packed.texture, rects = packed.rects, offsets = offsets,
			n = angles.size(), sq = squash_angles.size()}
	return _sheet


# Body with the struck half pushed in by `depth` columns (side 1 = hit from the left).
static func _dent(src: Image, side: int, depth: int) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := w / 2
	for y in h:
		if y < SQUASH_FROM_ROW:
			for x in w:
				out.set_pixel(x, y, src.get_pixel(x, y))
			continue
		if side > 0:
			for x in range(cx, w):
				out.set_pixel(x, y, src.get_pixel(x, y))
			for x in range(cx - 1, -1, -1):
				if x + depth < w:
					out.set_pixel(x + depth, y, src.get_pixel(x, y))
		else:
			for x in range(0, cx + 1):
				out.set_pixel(x, y, src.get_pixel(x, y))
			for x in range(cx + 1, w):
				if x - depth >= 0:
					out.set_pixel(x - depth, y, src.get_pixel(x, y))
	return out


func _ready() -> void:
	_a = float(GameScale.art_pixel())
	global_position = global_position.snapped(Vector2(_a, _a))
	var stand := Sprite2D.new()
	stand.name = "Stand"
	stand.texture = STAND_ART
	stand.centered = false
	stand.scale = Vector2(_a, _a)
	stand.position = -Vector2(STAND_HOOK.x, STAND_FLOOR) * _a
	add_child(stand)
	var base := StaticBody2D.new()
	base.name = "StandBase"
	base.set_meta(&"surface", &"metal")
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = BASE_RECT.size * _a
	shape.shape = rect
	shape.position = (BASE_RECT.position + BASE_RECT.size * 0.5 - Vector2(STAND_HOOK.x, STAND_FLOOR)) * _a
	base.add_child(shape)
	add_child(base)
	var s := sheet()
	_chain = _frame_sprite("Chain", s.texture)
	_body = _frame_sprite("Body", s.texture)
	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.target = self
	var hs := CollisionShape2D.new()
	var hr := RectangleShape2D.new()
	hr.size = HURT_RECT.size * _a
	hs.shape = hr
	hs.position = (HURT_RECT.position + HURT_RECT.size * 0.5 - BAG_PIVOT) * _a
	_hurtbox.add_child(hs)
	_hurtbox.position = _pivot()
	add_child(_hurtbox)
	_fx = TargetFx.new()
	_fx.name = "Fx"
	add_child(_fx)
	_fx.floor_y = global_position.y
	_build_board()
	_apply(true)


func _frame_sprite(node_name: String, texture: Texture2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.name = node_name
	sp.texture = texture
	sp.centered = false
	sp.region_enabled = true
	sp.scale = Vector2(_a, _a)
	sp.z_index = 1
	add_child(sp)
	return sp


func _pivot() -> Vector2:
	return Vector2(0, -(STAND_FLOOR - STAND_HOOK.y)) * _a


func take_hit(point: Vector2, direction: Vector2, damage: float, kind: StringName) -> void:
	var s := clampf(damage / 30.0, 0.15, 1.3)
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var r := to_local(point) - _pivot()
	var lever := clampf(r.length() / center_distance, 0.3, 1.5)
	var cross := r.x * dir.y - r.y * dir.x
	var torque_sign := signf(cross) if absf(cross) > 0.001 else -signf(dir.x)
	var boost := kick_boost if kind == &"kick" else 1.0
	angular_velocity += torque_sign * spin_per_damage * damage * lever * boost * (center_distance * center_distance) / (center_distance * center_distance + gyration * gyration) * 1.15
	_squash = squash_time
	_squash_side = 1 if dir.x >= 0.0 else -1
	_fx.dust(point, -dir, 6 if kind != &"kick" else 12)
	Feedback.sfx(&"punch_hit", point, s)
	if kind == &"kick":
		Feedback.sfx(&"kick_hit", point, s)
		Feedback.haptic(&"kick_hit", s)
	else:
		Feedback.haptic(&"punch_hit", s)
	combo = combo + 1 if _combo_t > 0.0 else 1
	_combo_t = combo_window
	if combo > best_combo:
		best_combo = combo
		_redraw_board()
	combo_changed.emit(combo, best_combo)
	hit.emit(point, damage)


func _physics_process(delta: float) -> void:
	var steps := maxi(1, ceili(delta * 240.0))
	var dt := delta / steps
	var w2 := game_gravity * center_distance / (center_distance * center_distance + gyration * gyration)
	for i in steps:
		angular_velocity += (-w2 * sin(angle) - angular_damp * angular_velocity) * dt
		angle += angular_velocity * dt
		if absf(angle) > MAX_ANGLE:
			angle = clampf(angle, -MAX_ANGLE, MAX_ANGLE)
			angular_velocity *= -0.25
	_hurtbox.rotation = angle
	_creak(delta)
	if _combo_t > 0.0:
		_combo_t -= delta


func _creak(delta: float) -> void:
	_creak_wait = maxf(0.0, _creak_wait - delta)
	var sgn := signf(angular_velocity)
	# At the end of a strong swing the chain creaks once.
	if sgn != _last_sign and sgn != 0.0:
		if absf(angle) > 0.35 and _creak_wait <= 0.0:
			_creak_wait = creak_interval
			Feedback.sfx(&"chair_creak", to_global(_pivot()), clampf(absf(angle) / 1.4, 0.15, 0.45))
		_last_sign = sgn
	elif absf(angular_velocity) > creak_speed and _creak_wait <= 0.0 and _last_sign == 0.0:
		_last_sign = sgn


func _process(delta: float) -> void:
	if _squash > 0.0:
		_squash -= delta
	_apply(false)


func _apply(force: bool) -> void:
	var s := sheet()
	var k := clampi(roundi((angle + MAX_ANGLE) / STEP), 0, s.n - 1)
	var snapped := -MAX_ANGLE + k * STEP
	var variant := -1
	if _squash > 0.0 and absf(snapped) <= SQUASH_MAX + 0.001:
		var depth := 2 if _squash > squash_time * 0.5 else 1
		variant = (0 if _squash_side > 0 else 2) + depth - 1
	if not force and k == _k and variant == _variant:
		return
	_k = k
	_variant = variant
	var pivot := _pivot()
	_chain.region_rect = s.rects[k]
	_chain.position = pivot + s.offsets[k] * _a
	var bi: int = s.n + k
	if variant >= 0:
		var sk := k - roundi((MAX_ANGLE - SQUASH_MAX) / STEP)
		bi = 2 * s.n + variant * s.sq + sk
	_body.region_rect = s.rects[bi]
	_body.position = pivot + s.offsets[bi] * _a


func _build_board() -> void:
	_board_img = Image.create(13, 9, false, Image.FORMAT_RGBA8)
	_board_tex = ImageTexture.create_from_image(_board_img)
	_board = Sprite2D.new()
	_board.name = "ComboBoard"
	_board.texture = _board_tex
	_board.centered = false
	_board.scale = Vector2(_a, _a)
	# Bolted to the stand's pole, under the arm brace.
	_board.position = (Vector2(10, 30) - STAND_HOOK - Vector2(0, STAND_FLOOR - STAND_HOOK.y)) * _a
	add_child(_board)
	_redraw_board()


func _redraw_board() -> void:
	var img := _board_img
	img.fill(OUTLINE)
	for y in range(1, 8):
		for x in range(1, 12):
			img.set_pixel(x, y, Color("#2c242a"))
	var text := str(mini(best_combo, 99))
	PixelFont.draw(img, text, Vector2i(11 - PixelFont.measure(text), 1), Color("#f0c862"))
	_board_tex.update(img)


func reset_combo() -> void:
	combo = 0
	best_combo = 0
	_redraw_board()
	combo_changed.emit(combo, best_combo)
