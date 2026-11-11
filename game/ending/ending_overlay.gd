extends CanvasLayer

# Screen-space part of the ending: a rubble avalanche that piles up from the bottom until it covers
# the whole screen, then the fade to black and the "FIM" screen. Coordinates are canvas units of
# the root viewport; one art pixel is GameScale.art_pixel() * camera zoom units, like the world.

signal covered
signal ending_shown
signal credits_shown
signal restart_ready

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const EndingArt := preload("res://game/ending/ending_art.gd")
const PixelFont := preload("res://game/interactables/pixel_font.gd")

const MARGIN := 48.0
const GRAVITY := 2400.0
const SLOPE := 1.2
const MAX_CHUNKS := 900
const ANIM_FPS := 15.0
const TITLE_BLOCK := 2
# Gap between title letters, in texels.
const TITLE_GAP := 4
const TITLE_SCALE := 6
const THANKS_SCALE := 4
const PROMPT_SCALE := 2
const DROP_STEPS := [-264.0, -168.0, -84.0, -24.0, 0.0, -18.0, -6.0, 0.0]
const FADE_STEPS := 5
const FADE_TIME := 0.8

@export var fill_time := 3.0
@export var spawn_rate_start := 150.0
@export var spawn_rate_end := 330.0
@export var rise_speed := 560.0
@export var landing_sfx_interval := 0.07
@export var landing_haptic_interval := 0.11

var _px := 3.0
var _size := Vector2(1280, 720)
var _canvas: Node2D
var _tile: Texture2D
var _rocks: Dictionary
var _heights := PackedFloat32Array()
# Where the landings and slides put the pile; _heights (drawn) rises towards it at rise_speed.
var _target := PackedFloat32Array()
var _col_w := 6.0
var _chunks: Array = []
var _t := 0.0
var _spawn_acc := 0.0
var _active := false
var _covered := false
var _last_sfx := -1.0
var _last_haptic := -1.0
var _jolt := 0.0
var _rng := RandomNumberGenerator.new()

var _fade: ColorRect
var _end_t := -1.0
var _letters: Array[Sprite2D] = []
var _thanks: Sprite2D
var _thanks_x := PackedInt32Array()
var _thanks_h := 0
var _prompt: Sprite2D
var _juicy: Array = []
var _juicy_popped := false
var _shown_fim := false
var _shown_thanks := false
var _accept := false

const THANKS_AT := 1.3
const JUICY_TEXT := "E aí, sentiu o juicy?"
const JUICY_SCALE := 3
const JUICY_CPS := 18.0
const JUICY_PAUSE := 0.8
const JUICY_COLOR := Color("#ffb03a")
const JUICY_SHADE := Color("#e86a1e")
# Hop of "juicy" in texels, one step per ANIM_FPS frame.
const JUICY_HOP := [0.0, -2.0, -4.0, -5.0, -4.0, -2.0, 0.0, -1.0, 0.0]
const THANKS_CPS := 22.0
const PROMPT_DELAY := 0.9


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1234
	_px = GameScale.art_pixel() * GameScale.camera_zoom()
	_col_w = _px * 2.0
	_tile = EndingArt.rubble_tile()
	_rocks = EndingArt.rock_set()
	_canvas = Node2D.new()
	_canvas.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_draw_rubble)
	add_child(_canvas)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_layout()


func start() -> void:
	_active = true
	_t = 0.0


func coverage() -> float:
	if _heights.is_empty():
		return 0.0
	var sum := 0.0
	for h in _heights:
		sum += clampf((_size.y - h) / _size.y, 0.0, 1.0)
	return sum / _heights.size()


func is_covered() -> bool:
	return _covered


func jolt(amount: float) -> void:
	_jolt = maxf(_jolt, amount)


func _layout() -> void:
	_size = get_viewport().get_visible_rect().size
	_fade.position = Vector2(-MARGIN, -MARGIN)
	_fade.size = _size + Vector2(MARGIN, MARGIN) * 2.0
	var n := ceili((_size.x + MARGIN * 2.0) / _col_w) + 1
	if _heights.size() != n:
		var fresh := PackedFloat32Array()
		fresh.resize(n)
		for c in n:
			fresh[c] = _heights[c] if c < _heights.size() else _size.y + MARGIN
		_heights = fresh
		_target = fresh.duplicate()


func _process(delta: float) -> void:
	if get_viewport().get_visible_rect().size != _size:
		_layout()
	if _active and not _covered:
		_t += delta
		_avalanche(delta)
	if _jolt > 0.0:
		_jolt = maxf(0.0, _jolt - delta * 40.0)
		var k := roundf(_jolt / _px) * _px
		_canvas.position = Vector2(_rng.randf_range(-k, k), _rng.randf_range(-k, k)).snapped(Vector2(_px, _px))
	else:
		_canvas.position = Vector2.ZERO
	if _active:
		_canvas.queue_redraw()
	if _end_t >= 0.0:
		_end_t += delta
		_end_screen()


func _avalanche(delta: float) -> void:
	var k := clampf(_t / fill_time, 0.0, 1.0)
	_spawn_acc += lerpf(spawn_rate_start, spawn_rate_end, k * k) * delta
	while _spawn_acc >= 1.0 and _chunks.size() < MAX_CHUNKS:
		_spawn_acc -= 1.0
		_spawn_chunk(k)
	_spawn_acc = minf(_spawn_acc, 1.0)
	var rise := rise_speed * delta
	for c in _heights.size():
		_heights[c] = maxf(_target[c], _heights[c] - rise)
	var shapes: Array = _rocks.shapes
	var i := 0
	while i < _chunks.size():
		var ch: Dictionary = _chunks[i]
		if not ch.landed:
			ch.vy += GRAVITY * delta
			ch.y += ch.vy * delta
			ch.spin += ch.spin_rate * delta
			ch.frame = posmod(int(ch.spin), EndingArt.ROCK_ANGLES)
			var r: Rect2 = shapes[ch.shape].rects[ch.frame]
			ch.w = r.size.x * _px
			ch.h = r.size.y * _px
			var span := _span(ch.x, ch.w)
			var surface := _surface(span)
			if ch.y + ch.h >= surface + ch.h * 0.3:
				_land(ch, span, surface)
		else:
			var span2 := _span(ch.x, ch.w)
			var buried := true
			for c in range(span2.x, span2.y + 1):
				if _heights[c] > ch.y - ch.h * 1.5:
					buried = false
					break
			if buried and _chunks.size() >= MAX_CHUNKS - 40:
				_chunks.remove_at(i)
				continue
		i += 1
	var top := -INF
	for h in _heights:
		top = maxf(top, h)
	if top <= -_px * 2.0:
		_covered = true
		for ch in _chunks:
			ch.landed = true
		covered.emit()


func _spawn_chunk(k: float) -> void:
	var shapes: Array = _rocks.shapes
	# Bias towards the lowest part of the pile so the screen fills evenly.
	var best := -1
	var best_h := -INF
	for t in 3:
		var c := _rng.randi_range(0, _heights.size() - 1)
		if _heights[c] > best_h:
			best_h = _heights[c]
			best = c
	var idx := _rng.randi_range(0, 9) if _rng.randf() < 0.75 else _rng.randi_range(0, shapes.size() - 1)
	var frame := _rng.randi_range(0, EndingArt.ROCK_ANGLES - 1)
	var r: Rect2 = shapes[idx].rects[frame]
	var w := r.size.x * _px
	var x := best * _col_w - MARGIN - w * 0.5 + _rng.randf_range(-_col_w * 2.0, _col_w * 2.0)
	_chunks.append({
		shape = idx, frame = frame, spin = float(frame), spin_rate = _rng.randf_range(-14.0, 14.0),
		x = x, y = -r.size.y * _px - _rng.randf_range(0.0, 120.0), vy = _rng.randf_range(300.0, 700.0) + k * 500.0,
		w = w, h = r.size.y * _px, landed = false,
	})


func _span(x: float, w: float) -> Vector2i:
	var c0 := clampi(floori((x + MARGIN) / _col_w), 0, _heights.size() - 1)
	var c1 := clampi(floori((x + w + MARGIN) / _col_w), 0, _heights.size() - 1)
	return Vector2i(c0, c1)


func _surface(span: Vector2i) -> float:
	var s := INF
	for c in range(span.x, span.y + 1):
		s = minf(s, _heights[c])
	return s


func _land(ch: Dictionary, span: Vector2i, surface: float) -> void:
	ch.landed = true
	ch.y = roundf((surface - ch.h * 0.7) / _px) * _px
	var fill_to: float = ch.y + ch.h * 0.5
	for c in range(span.x, span.y + 1):
		_target[c] = minf(_target[c], fill_to)
	# Slopes slide: no column stays far below its neighbours.
	var step := SLOPE * _col_w
	for c in range(1, _target.size()):
		_target[c] = minf(_target[c], _target[c - 1] + step)
	for c in range(_target.size() - 2, -1, -1):
		_target[c] = minf(_target[c], _target[c + 1] + step)
	var size_k := float(_rocks.shapes[ch.shape].size) / 34.0
	if _t - _last_sfx >= landing_sfx_interval and size_k > 0.4:
		_last_sfx = _t
		Feedback.sfx(&"rock_fall", Vector2.INF, clampf(0.35 + size_k * 0.6, 0.0, 1.0))
	if _t - _last_haptic >= landing_haptic_interval and size_k > 0.55:
		_last_haptic = _t
		Feedback.haptic(&"rock_fall", clampf(0.5 + size_k * 0.5, 0.0, 1.0))
		jolt(_px * 2.0 * size_k)


func _draw_rubble() -> void:
	var bottom := _size.y + MARGIN
	var tex := _rocks.texture as Texture2D
	if _covered:
		var full := Rect2(-MARGIN, -MARGIN, _size.x + MARGIN * 2.0, _size.y + MARGIN * 2.0)
		_canvas.draw_texture_rect_region(_tile, full, Rect2(full.position / _px, full.size / _px))
	for c in _heights.size():
		if _covered:
			break
		var top := roundf(_heights[c] / _px) * _px
		if top >= bottom:
			continue
		var x := c * _col_w - MARGIN
		var r := Rect2(x, top, _col_w, bottom - top)
		_canvas.draw_texture_rect_region(_tile, r, Rect2(r.position / _px, r.size / _px))
		_canvas.draw_rect(Rect2(x, top, _col_w, _px), PixelArt.OUTLINE)
	var shapes: Array = _rocks.shapes
	for ch in _chunks:
		var src: Rect2 = shapes[ch.shape].rects[ch.frame]
		var pos := Vector2(roundf(ch.x / _px) * _px, roundf(ch.y / _px) * _px)
		_canvas.draw_texture_rect_region(tex, Rect2(pos, src.size * _px), src)


# --- End screen ------------------------------------------------------------------------------

func start_end() -> void:
	_end_t = 0.0
	_fade.color = Color(0, 0, 0, 0)


func _end_screen() -> void:
	var t := _end_t
	var steps := clampi(floori(t / FADE_TIME * FADE_STEPS), 0, FADE_STEPS)
	_fade.color = Color(0, 0, 0, float(steps) / FADE_STEPS)
	if steps >= FADE_STEPS and _active:
		_active = false
		_canvas.visible = false
	var ft := t - FADE_TIME - 0.25
	if ft < 0.0:
		return
	if not _shown_fim:
		_shown_fim = true
		_build_title()
		Feedback.sfx(&"ending_sting")
		ending_shown.emit()
	var center_x := roundf(_size.x * 0.5)
	var title_y := roundf(_size.y * 0.36)
	var title_w := 0.0
	for l in _letters:
		title_w += (l.region_rect.size.x - 4 + TITLE_GAP) * TITLE_SCALE
	title_w -= TITLE_GAP * TITLE_SCALE
	var x := roundf(center_x - title_w * 0.5 - 2 * TITLE_SCALE)
	for i in _letters.size():
		var l := _letters[i]
		var lt := ft - i * 0.16
		var y_off: float = DROP_STEPS[0]
		if lt >= 0.0:
			var s := mini(floori(lt * ANIM_FPS), DROP_STEPS.size() - 1)
			y_off = DROP_STEPS[s]
			l.visible = true
			if s == 4 and not l.has_meta(&"landed"):
				l.set_meta(&"landed", true)
				Feedback.haptic(&"rock_fall", 0.35)
		l.position = Vector2(x, title_y - l.region_rect.size.y * TITLE_SCALE * 0.5 + y_off).snapped(Vector2(TITLE_SCALE, TITLE_SCALE))
		x += (l.region_rect.size.x - 4 + TITLE_GAP) * TITLE_SCALE
	var tt := ft - THANKS_AT
	if tt < 0.0:
		return
	if _thanks == null:
		_build_thanks()
	var n := mini(floori(tt * THANKS_CPS), _thanks_x.size())
	_thanks.visible = n > 0
	if n > 0:
		_thanks.region_rect = Rect2(0, 0, _thanks_x[n - 1], _thanks_h)
	var full_w := _thanks.texture.get_width() * THANKS_SCALE
	_thanks.position = Vector2(roundf(center_x - full_w * 0.5), roundf(_size.y * 0.57)).snapped(Vector2(THANKS_SCALE, THANKS_SCALE))
	if n >= _thanks_x.size() and not _shown_thanks:
		_shown_thanks = true
		credits_shown.emit()
	# Closing line, typed after a pause, with a stepped hop on "juicy".
	var jt := tt - _thanks_x.size() / THANKS_CPS - JUICY_PAUSE
	if jt < 0.0:
		return
	if _juicy.is_empty():
		_build_juicy()
	var shown := mini(floori(jt * JUICY_CPS), JUICY_TEXT.length())
	var line_w := float(PixelFont.measure(JUICY_TEXT) + 2) * JUICY_SCALE
	var x0 := roundf(center_x - line_w * 0.5)
	var y0 := roundf(_size.y * 0.7)
	var typed_at := float(JUICY_TEXT.length()) / JUICY_CPS
	for part in _juicy:
		var sprite: Sprite2D = part.sprite
		var start: int = part.start
		var chars: PackedInt32Array = part.char_x
		var k := clampi(shown - start, 0, chars.size())
		sprite.visible = k > 0
		if k > 0:
			sprite.region_rect = Rect2(0, 0, chars[k - 1], sprite.texture.get_height())
		var hop := 0.0
		if part.pop and jt >= typed_at:
			var step := floori((jt - typed_at) * ANIM_FPS)
			if step < JUICY_HOP.size():
				hop = JUICY_HOP[step] * JUICY_SCALE
			if step >= 1 and not _juicy_popped:
				_juicy_popped = true
				Feedback.sfx(&"prompt_pop")
				Feedback.haptic(&"rock_fall", 0.25)
		sprite.position = Vector2(x0 + float(part.offset) * JUICY_SCALE, y0 + hop).snapped(Vector2(JUICY_SCALE, JUICY_SCALE))
	var pt := jt - typed_at - JUICY_HOP.size() / ANIM_FPS - PROMPT_DELAY
	if pt < 0.0:
		return
	if not _accept:
		_accept = true
		restart_ready.emit()
	_prompt.visible = fmod(pt, 1.1) < 0.8
	_prompt.position = Vector2(roundf(center_x - _prompt.texture.get_width() * PROMPT_SCALE * 0.5), roundf(_size.y * 0.86)).snapped(Vector2(PROMPT_SCALE, PROMPT_SCALE))


# "E aí, sentiu o " / "juicy" / "?" as separate sprites, so the word can hop on its own.
func _build_juicy() -> void:
	var cut_a := JUICY_TEXT.find("juicy")
	var cut_b := cut_a + 5
	var parts := [[0, cut_a, false, EndingArt.TITLE, EndingArt.TITLE_MID],
		[cut_a, cut_b, true, JUICY_COLOR, JUICY_SHADE],
		[cut_b, JUICY_TEXT.length(), false, EndingArt.TITLE, EndingArt.TITLE_MID]]
	for p in parts:
		var text := JUICY_TEXT.substr(p[0], p[1] - p[0])
		var t := EndingArt.text_image(text, p[3], p[4])
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(t.image)
		sprite.centered = false
		sprite.region_enabled = true
		sprite.scale = Vector2(JUICY_SCALE, JUICY_SCALE)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.visible = false
		add_child(sprite)
		var prefix := JUICY_TEXT.substr(0, p[0])
		var offset := PixelFont.measure(prefix) + PixelFont.SPACING if p[0] > 0 else 0
		_juicy.append({sprite = sprite, start = p[0], char_x = t.char_x, offset = offset, pop = p[2]})


func _build_title() -> void:
	for ch in "FIM":
		var img := EndingArt.title_glyph(ch, TITLE_BLOCK)
		var s := Sprite2D.new()
		s.texture = ImageTexture.create_from_image(img)
		s.centered = false
		s.region_enabled = true
		s.region_rect = Rect2(Vector2.ZERO, img.get_size())
		s.scale = Vector2(TITLE_SCALE, TITLE_SCALE)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.visible = false
		add_child(s)
		_letters.append(s)


func _build_thanks() -> void:
	var t := EndingArt.text_image("OBRIGADO POR JOGAR", EndingArt.TITLE, EndingArt.TITLE_MID)
	var img: Image = t.image
	_thanks = Sprite2D.new()
	_thanks.texture = ImageTexture.create_from_image(img)
	_thanks.centered = false
	_thanks.region_enabled = true
	_thanks.scale = Vector2(THANKS_SCALE, THANKS_SCALE)
	_thanks.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_thanks_x = t.char_x
	_thanks_h = img.get_height()
	add_child(_thanks)
	var touch := get_node_or_null(^"/root/TouchControls")
	var again := "Toque para jogar de novo" if touch and touch.is_touch_mode() else "Pressione A para jogar de novo"
	var p := EndingArt.text_image(again, Color("#9a9090"), Color("#6e6466"))
	_prompt = Sprite2D.new()
	_prompt.texture = ImageTexture.create_from_image(p.image)
	_prompt.centered = false
	_prompt.scale = Vector2(PROMPT_SCALE, PROMPT_SCALE)
	_prompt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_prompt.visible = false
	add_child(_prompt)


func _input(event: InputEvent) -> void:
	if not _accept:
		return
	var go := false
	if event is InputEventScreenTouch and event.pressed:
		go = true
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		go = true
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		go = k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE
	if go:
		_accept = false
		get_viewport().set_input_as_handled()
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
