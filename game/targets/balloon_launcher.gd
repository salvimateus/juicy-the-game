class_name BalloonLauncher
extends Node2D

# Archery target: a thick old metal pipe that releases balloons at irregular intervals, from random
# spots across its mouth, each rising at its own speed with its own sway. Any take_hit pops a balloon
# (arrows fly on through, so one shot can pop several): rubber shreds in its colour, a flash, and
# its ribbon falling. Balloons are pooled; colours are hue-shifted variants of the user's red balloon
# (art/balloon.png), generated once at load into one atlas with the ribbon frames, so every balloon
# batches with the others. A small scoreboard counts the pops; two buttons toggle the launcher and
# zero the score. Origin: floor under the pipe centre.

signal popped(balloon_color: Color, position: Vector2)
signal score_changed(score: int)

const BALLOON_ART := preload("res://game/targets/art/balloon.png")
const RIBBON_ART := preload("res://game/targets/art/ribbon.png")
const BalloonScript := preload("res://game/targets/balloon.gd")
const PixelRotate := preload("res://game/targets/pixel_rotate.gd")
const PixelFont := preload("res://game/interactables/pixel_font.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const RESET_BUTTON := "res://game/interactables/reset_button.tscn"

# [name, hue shift (turns), saturation scale, value scale]; value is tuned so yellow does not glare
# and blue / purple do not sink into the outline.
const VARIANTS := [
	["red", 0.0, 1.0, 1.0],
	["orange", 0.072, 1.0, 1.0],
	["yellow", 0.135, 0.88, 1.1],
	["green", 0.31, 0.8, 0.92],
	["blue", 0.585, 0.78, 1.12],
	["purple", 0.765, 0.72, 1.12],
	["pink", 0.905, 0.55, 1.1],
]
const BALLOON_MAIN := Color("#de0b12")
# Balloon art layout (art px): node origin at the bottom of the knot, ribbon hanging from there.
const KNOT := Vector2i(8, 20)
const RIBBON_TOP := Vector2i(3, 0)
const RIBBON_SWAY := 2
const HIT_RECT := Rect2(1, 1, 14, 16)

# Pipe art (art px).
const PIPE_W := 36
const PIPE_H := 42
const PIPE_BODY := Vector2i(3, 32)
const MOUTH := Vector2i(6, 29)
const OUTLINE := Color("#141013")
const METAL := [Color("#3c2e32"), Color("#605052"), Color("#765e5c"), Color("#967e79"), Color("#b09891"), Color("#c4aea6")]
const RUST := [Color("#712c1f"), Color("#8c391f"), Color("#ae4c24")]
const INNER := Color("#1c161a")
const BOARD_WOOD := [Color("#5a3e3a"), Color("#7d564a"), Color("#966856")]
const BOARD_PANEL := Color("#2c242a")
const BOARD_DIGIT := Color("#f0c862")

enum { FREE, RISING, RIBBON }

@export var running := true
@export var max_alive := 12
@export var interval := Vector2(0.4, 1.4)
@export_range(0.0, 1.0) var burst_chance := 0.25
@export var rise_speed := Vector2(80.0, 260.0)
@export var sway_amplitude := Vector2(24.0, 90.0)
@export var sway_frequency := Vector2(0.9, 2.4)
@export var drift := 70.0
# Height above the mouth where a balloon is recycled when no camera tells where the screen ends.
@export var max_rise := 2600.0
@export var ribbon_gravity := 700.0
@export var ribbon_max_fall := 380.0
@export_group("Buttons")
@export var toggle_offset := Vector2(-300, 0)
@export var zero_offset := Vector2(420, 0)
@export var board_offset := Vector2(234, 0)

static var _atlas: Dictionary = {}

var score := 0

var _a := 6.0
var _pool: Array[Area2D] = []
var _body_sprites: Array[Sprite2D] = []
var _ribbon_sprites: Array[Sprite2D] = []
var _shapes: Array[CollisionShape2D] = []
var _state := PackedByteArray()
var _base_x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _t := PackedFloat32Array()
var _vy := PackedFloat32Array()
var _amp := PackedFloat32Array()
var _w := PackedFloat32Array()
var _ph := PackedFloat32Array()
var _drift := PackedFloat32Array()
var _x := PackedFloat32Array()
var _color := PackedByteArray()
var _rib := PackedInt32Array()
var _next := 0.5
var _burst := 0
var _last_x := 0.0
var _fx: TargetFx
var _board: Sprite2D
var _board_img: Image
var _board_tex: ImageTexture
var _toggle: Node
var _zero: Node
var _rng := RandomNumberGenerator.new()


# One atlas: VARIANTS.size() balloon colours, then 2 * RIBBON_SWAY + 1 ribbon frames.
static func atlas() -> Dictionary:
	if _atlas.is_empty():
		var base := PixelRotate.load_art(BALLOON_ART)
		var images: Array[Image] = []
		var mains: Array[Color] = []
		for v in VARIANTS:
			images.append(_recolor(base, v[1], v[2], v[3]))
			mains.append(_shift(BALLOON_MAIN, v[1], v[2], v[3]))
		var rib := PixelRotate.load_art(RIBBON_ART)
		for s in range(-RIBBON_SWAY, RIBBON_SWAY + 1):
			images.append(_shear(rib, s))
		var packed := PixelRotate.pack(images)
		_atlas = {texture = packed.texture, rects = packed.rects, mains = mains, ribbon_pad = RIBBON_SWAY}
	return _atlas


static func color_count() -> int:
	return VARIANTS.size()


static func _shift(c: Color, hue: float, sat: float, val: float) -> Color:
	return Color.from_hsv(fposmod(c.h + hue, 1.0), clampf(c.s * sat, 0.0, 1.0), clampf(c.v * val, 0.0, 1.0), c.a)


# Hue shift only on the saturated balloon pixels: outline, white shine and knot shadow stay as drawn.
static func _recolor(src: Image, hue: float, sat: float, val: float) -> Image:
	var out := src.duplicate() as Image
	if hue == 0.0 and sat == 1.0 and val == 1.0:
		return out
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0 and c.s > 0.4 and c.v > 0.2:
				out.set_pixel(x, y, _shift(c, hue, sat, val))
	return out


# Ribbon bent sideways by `s` art px at its tail, rows shifted whole pixels (no mixels).
static func _shear(src: Image, s: int) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w + RIBBON_SWAY * 2, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / maxf(1.0, h - 1.0)
		var dx := roundi(s * t * t) + RIBBON_SWAY
		for x in w:
			var c := src.get_pixel(x, y)
			if c.a > 0.0:
				out.set_pixel(x + dx, y, c)
	return out


func _ready() -> void:
	_a = float(GameScale.art_pixel())
	global_position = global_position.snapped(Vector2(_a, _a))
	_rng.randomize()
	_build_pipe()
	_build_pool()
	_build_board()
	_fx = TargetFx.new()
	_fx.name = "Fx"
	add_child(_fx)
	_fx.floor_y = global_position.y
	_build_buttons()
	_next = _rng.randf_range(0.2, 0.6)


func _build_pipe() -> void:
	var img := Image.create(PIPE_W, PIPE_H, false, Image.FORMAT_RGBA8)
	# Body: cylinder shading per column, two riveted bands and rust.
	for y in range(7, PIPE_H):
		for x in range(PIPE_BODY.x, PIPE_BODY.y + 1):
			img.set_pixel(x, y, _metal(x, PIPE_BODY.x, PIPE_BODY.y, 0))
	for band in [15, 31]:
		for y in range(band, band + 3):
			for x in range(PIPE_BODY.x, PIPE_BODY.y + 1):
				img.set_pixel(x, y, _metal(x, PIPE_BODY.x, PIPE_BODY.y, 1 if y != band + 2 else 2))
		for rx in [PIPE_BODY.x + 3, (PIPE_BODY.x + PIPE_BODY.y) / 2, PIPE_BODY.y - 3]:
			img.set_pixel(rx, band + 1, METAL[5])
			img.set_pixel(rx, band + 2, METAL[0])
			# Rust streaks run down from some rivets.
			if _hash(rx, band) % 3 != 0:
				var length := 2 + _hash(band, rx) % 5
				for i in length:
					img.set_pixel(rx, band + 3 + i, RUST[1] if i < length - 1 else RUST[0])
	# A few rust blotches near the ground and under the rim.
	for spot in [Vector2i(8, 38), Vector2i(24, 36), Vector2i(27, 9), Vector2i(14, 25)]:
		for dy in range(-1, 2):
			for dx in range(-2, 3):
				if absi(dx) + absi(dy) <= 2 and _hash(spot.x + dx, spot.y + dy) % 3 != 0:
					img.set_pixel(spot.x + dx, spot.y + dy, RUST[(_hash(dx, dy) % 2) + (1 if dy < 0 else 0)])
	# Shadow of the rim on the body.
	for x in range(PIPE_BODY.x, PIPE_BODY.y + 1):
		img.set_pixel(x, 7, METAL[0])
	# Rim: wider lip with the dark mouth on top.
	for y in range(0, 7):
		for x in range(0, PIPE_W):
			img.set_pixel(x, y, _metal(x, 0, PIPE_W - 1, 1 if y >= 5 else 0))
	for x in range(MOUTH.x, MOUTH.y + 1):
		img.set_pixel(x, 1, INNER)
		img.set_pixel(x, 2, INNER if x > MOUTH.x and x < MOUTH.y else METAL[1])
	for x in range(MOUTH.x - 2, MOUTH.y + 3):
		img.set_pixel(x, 0, METAL[4])
	for x in [3, PIPE_W / 2, PIPE_W - 4]:
		img.set_pixel(x, 4, METAL[5])
		img.set_pixel(x, 5, METAL[0])
	_outline(img)
	var sprite := Sprite2D.new()
	sprite.name = "Pipe"
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = false
	sprite.scale = Vector2(_a, _a)
	sprite.position = Vector2(-PIPE_W / 2, -PIPE_H) * _a
	sprite.z_index = 1
	add_child(sprite)


func _metal(x: int, x0: int, x1: int, darken: int) -> Color:
	var t := float(x - x0) / maxf(1.0, x1 - x0)
	var i := 1
	if t < 0.1:
		i = 1
	elif t < 0.22:
		i = 3
	elif t < 0.34:
		i = 5
	elif t < 0.48:
		i = 4
	elif t < 0.7:
		i = 3
	elif t < 0.86:
		i = 2
	else:
		i = 1
	return METAL[maxi(0, i - darken)]


static func _hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a == 0.0:
				continue
			# The bottom row stands on the ground: no outline there.
			var edge := x == 0 or x == w - 1 or y == 0 \
				or src.get_pixel(x - 1, y).a == 0.0 or src.get_pixel(x + 1, y).a == 0.0 \
				or src.get_pixel(x, y - 1).a == 0.0 or (y < h - 1 and src.get_pixel(x, y + 1).a == 0.0)
			if edge:
				img.set_pixel(x, y, OUTLINE)


func _build_pool() -> void:
	var at := atlas()
	var rect := RectangleShape2D.new()
	rect.size = HIT_RECT.size * _a
	for i in max_alive:
		var b := Area2D.new()
		b.set_script(BalloonScript)
		b.name = "Balloon%d" % i
		b.launcher = self
		b.index = i
		b.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		b.visible = false
		var shape := CollisionShape2D.new()
		shape.shape = rect
		shape.position = (HIT_RECT.position + HIT_RECT.size * 0.5 - Vector2(KNOT)) * _a
		shape.disabled = true
		b.add_child(shape)
		var body := Sprite2D.new()
		body.texture = at.texture
		body.centered = false
		body.region_enabled = true
		body.scale = Vector2(_a, _a)
		body.position = -Vector2(KNOT) * _a
		b.add_child(body)
		var rib := Sprite2D.new()
		rib.texture = at.texture
		rib.centered = false
		rib.region_enabled = true
		rib.scale = Vector2(_a, _a)
		rib.position = Vector2(-RIBBON_TOP.x - RIBBON_SWAY, 0) * _a
		b.add_child(rib)
		add_child(b)
		_pool.append(b)
		_shapes.append(shape)
		_body_sprites.append(body)
		_ribbon_sprites.append(rib)
	for arr in [_base_x, _y, _t, _vy, _amp, _w, _ph, _drift, _x]:
		arr.resize(max_alive)
	_state.resize(max_alive)
	_color.resize(max_alive)
	_rib.resize(max_alive)
	_rib.fill(-99)


func _build_board() -> void:
	_board_img = Image.create(24, 21, false, Image.FORMAT_RGBA8)
	_board_tex = ImageTexture.create_from_image(_board_img)
	_board = Sprite2D.new()
	_board.name = "Scoreboard"
	_board.texture = _board_tex
	_board.centered = false
	_board.scale = Vector2(_a, _a)
	_board.position = board_offset + Vector2(-12, -21) * _a
	add_child(_board)
	_redraw_board()


func _redraw_board() -> void:
	var img := _board_img
	img.fill(Color(0, 0, 0, 0))
	# Post.
	for y in range(11, 21):
		img.set_pixel(11, y, BOARD_WOOD[1])
		img.set_pixel(12, y, BOARD_WOOD[0])
	# Frame and panel.
	for y in range(0, 12):
		for x in range(0, 24):
			img.set_pixel(x, y, BOARD_WOOD[2] if y == 0 else BOARD_WOOD[1] if y < 11 else BOARD_WOOD[0])
	for y in range(2, 10):
		for x in range(2, 22):
			img.set_pixel(x, y, BOARD_PANEL)
	var text := str(mini(score, 999))
	var width := PixelFont.measure(text)
	PixelFont.draw(img, text, Vector2i(21 - width, 2), BOARD_DIGIT)
	_outline(img)
	_board_tex.update(img)


func _build_buttons() -> void:
	if not ResourceLoader.exists(RESET_BUTTON):
		return
	var scene := load(RESET_BUTTON) as PackedScene
	_toggle = scene.instantiate()
	_toggle.name = "ToggleButton"
	add_child(_toggle)
	_toggle.position = toggle_offset
	_toggle.connect(&"pressed", toggle)
	_zero = scene.instantiate()
	_zero.name = "ZeroButton"
	_zero.set(&"prompt", "Zerar o placar")
	add_child(_zero)
	_zero.position = zero_offset
	_zero.connect(&"pressed", reset_score)
	_update_toggle_prompt()


func _update_toggle_prompt() -> void:
	if _toggle:
		_toggle.set(&"prompt", "Desligar balões" if running else "Ligar balões")


func toggle() -> void:
	set_running(not running)


func set_running(on: bool) -> void:
	running = on
	_next = _rng.randf_range(0.15, 0.4)
	_burst = 0
	_update_toggle_prompt()


func reset_score() -> void:
	score = 0
	_redraw_board()
	score_changed.emit(score)


# Releases one balloon now (colour -1 = random); returns its pool index or -1 when all are in use.
func release(color := -1, x_art := INF) -> int:
	var i := -1
	for k in max_alive:
		if _state[k] == FREE:
			i = k
			break
	if i < 0:
		return -1
	var half := (MOUTH.y - MOUTH.x + 1) / 2 - KNOT.x
	var x := 0.0
	if x_art != INF:
		x = x_art * _a
	else:
		for attempt in 4:
			x = _rng.randi_range(-half, half) * _a
			if absf(x - _last_x) >= 2.0 * _a:
				break
	_last_x = x
	_state[i] = RISING
	_base_x[i] = x
	_x[i] = x
	_y[i] = -(PIPE_H - 1) * _a + (KNOT.y + 2) * _a
	_t[i] = 0.0
	_vy[i] = _rng.randf_range(rise_speed.x, rise_speed.y)
	_amp[i] = _rng.randf_range(sway_amplitude.x, sway_amplitude.y)
	_w[i] = _rng.randf_range(sway_frequency.x, sway_frequency.y)
	_ph[i] = _rng.randf() * TAU
	_drift[i] = _rng.randf_range(-drift, drift)
	_color[i] = _rng.randi() % VARIANTS.size() if color < 0 else color % VARIANTS.size()
	_rib[i] = -99
	var b := _pool[i]
	b.alive = true
	b.visible = true
	b.monitorable = true
	_shapes[i].set_deferred(&"disabled", false)
	_body_sprites[i].visible = true
	_body_sprites[i].region_rect = atlas().rects[_color[i]]
	_ribbon_sprites[i].visible = true
	_place(i, 0.0)
	var mouth := to_global(Vector2(x, -(PIPE_H - 1) * _a))
	_fx.puff(mouth, 6)
	Feedback.sfx(&"balloon_release", mouth, clampf(_vy[i] / rise_speed.y, 0.3, 1.0))
	return i


func pop(i: int, _point: Vector2) -> void:
	if i < 0 or i >= max_alive or _state[i] != RISING:
		return
	var b := _pool[i]
	b.alive = false
	b.set_deferred(&"monitorable", false)
	_shapes[i].set_deferred(&"disabled", true)
	_body_sprites[i].visible = false
	_state[i] = RIBBON
	_vy[i] = -60.0
	_t[i] = 0.0
	var center := b.global_position + Vector2(0, -10 * _a)
	var main: Color = atlas().mains[_color[i]]
	_fx.shreds(center, main, 12)
	_fx.puff(center, 8)
	Feedback.sfx(&"balloon_pop", center, 1.0)
	Feedback.haptic(&"balloon_pop", 0.4)
	score += 1
	_redraw_board()
	popped.emit(main, center)
	score_changed.emit(score)


func alive_count() -> int:
	var n := 0
	for k in max_alive:
		if _state[k] == RISING:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if running:
		_next -= delta
		if _next <= 0.0:
			release()
			if _burst > 0:
				_burst -= 1
				_next = _rng.randf_range(0.08, 0.22)
			elif _rng.randf() < burst_chance:
				_burst = _rng.randi_range(1, 2)
				_next = _rng.randf_range(0.08, 0.22)
			else:
				_next = _rng.randf_range(interval.x, interval.y)
	var top := _screen_top()
	for i in max_alive:
		match _state[i]:
			RISING:
				_t[i] += delta
				var ramp := minf(1.0, 0.6 + _t[i] * 2.0)
				_y[i] -= _vy[i] * ramp * delta
				_x[i] = _base_x[i] + _drift[i] * _t[i] + _amp[i] * sin(_ph[i] + _w[i] * _t[i]) * minf(1.0, _t[i] * 0.8)
				var vx := _drift[i] + _amp[i] * _w[i] * cos(_ph[i] + _w[i] * _t[i])
				_place(i, vx)
				var gy := global_position.y + _y[i]
				if gy < top - 24.0 * _a or -_y[i] > max_rise:
					_free(i)
			RIBBON:
				_t[i] += delta
				_vy[i] = minf(ribbon_max_fall, _vy[i] + ribbon_gravity * delta)
				_y[i] += _vy[i] * delta
				var sway := sin(_t[i] * 7.0 + _ph[i]) * 90.0
				_x[i] += sway * delta * 0.4
				var floor_y := -float(_ribbon_sprites[i].region_rect.size.y) * _a
				if _y[i] >= floor_y:
					_y[i] = floor_y
					_vy[i] = 0.0
					if _t[i] > 1.6:
						_free(i)
						continue
					_ribbon_sprites[i].visible = int(_t[i] * 14.0) % 2 == 0 or _t[i] < 1.1
				_place(i, sway)


func _place(i: int, vx: float) -> void:
	var b := _pool[i]
	b.position = Vector2(roundf(_x[i] / _a) * _a, roundf(_y[i] / _a) * _a)
	var s := clampi(roundi(-vx / 40.0), -RIBBON_SWAY, RIBBON_SWAY)
	if s != _rib[i]:
		_rib[i] = s
		_ribbon_sprites[i].region_rect = atlas().rects[VARIANTS.size() + s + RIBBON_SWAY]


func _free(i: int) -> void:
	_state[i] = FREE
	var b := _pool[i]
	b.alive = false
	b.visible = false
	b.set_deferred(&"monitorable", false)
	_shapes[i].set_deferred(&"disabled", true)


# Top edge of the visible world, from the canvas transform (camera), or -INF without a viewport.
func _screen_top() -> float:
	var vp := get_viewport()
	if vp == null:
		return -INF
	var inv := vp.get_canvas_transform().affine_inverse()
	return (inv * Vector2.ZERO).y
