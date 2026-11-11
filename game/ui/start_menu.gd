extends CanvasLayer

# Title screen shown once per launch over the paused game: "JUICY: THE GAME" drops in by steps,
# the lines appear (any key or button skips to the end), left / right pick the stage and A, Enter or
# Space start. A scene reload skips it
# (static flag), so the restarts from the end screen or the pause menu go straight to the game;
# show_again() brings it back for the pause's "Menu inicial".

signal start_requested

const UiArt := preload("res://game/ui/ui_art.gd")
const Feedback := preload("res://game/feedback.gd")

const ANIM_FPS := 15.0
const DROP_STEPS := [-240.0, -150.0, -72.0, -18.0, 0.0, -12.0, 0.0]
const HOP_STEPS := [0.0, -2.0, -4.0, -4.0, -2.0, 0.0]
const LOGO_BLOCK := 2
const LOGO_SCALE := 5
const SUB_SCALE := 3
const LINE_SCALE := 3
const HINT_SCALE := 2
const PROMPT_SCALE := 3
const FADE_STEPS := 4
const FADE_TIME := 0.4
const LINES := ["Está preparado para sentir o game juicy?", "Explore cada cantinho."]
const HINT := "Aperte pause para ver os comandos"
const PROMPT := "Pressione A para começar"
const PROMPT_TOUCH := "Toque para começar"
const MODES := [["Aventura", &"adventure"], ["Motocross", &"moto"]]
const MODE_SCALE := 3
const MODE_GAP := 56.0
const HOP := [-2.0, -1.0, 0.0]
# Skip: the title letters bump once, in a quick ripple, so the jump to the end never reads as a cut.
const SETTLE_STEPS := [-3.0, -1.0, 0.0]
const SETTLE_STAGGER := 0.03

# Dim over the game behind the menu, 0..1.
@export var dim := 0.7

# Picked stage, written when the start is confirmed.
var mode: StringName = &"adventure"
# Modes whose start fades to black instead of to the game, because a scene change follows it.
var black_out_modes: Array = []

static var _shown := false

var _root: Node2D
var _dim: ColorRect
var _logo: Dictionary
var _sub: Dictionary
var _lines: Array[Sprite2D] = []
var _hint: Sprite2D
var _prompt: Sprite2D
var _modes: Array = []
var _mode_i := 0
var _mode_t := -1.0
var _axis_x := 0.0
var _t0 := 0
var _leaving := -1.0
var _accept := false
var _done := false
var _ready_at := 0.0
var _skip_t := -1.0
var _size := Vector2(1280, 720)


# True while the title screen has not been shown in this run of the game.
static func will_show() -> bool:
	return not _shown


# Lets the next instance show the title again (the pause's "Menu inicial").
static func show_again() -> void:
	_shown = false


func _ready() -> void:
	if _shown:
		queue_free()
		return
	_shown = true
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"pause_blocker")
	get_tree().paused = true
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, dim)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_root = Node2D.new()
	add_child(_root)
	_logo = UiArt.big_text(_root, "JUICY:", LOGO_BLOCK, LOGO_SCALE, UiArt.ORANGE)
	_sub = UiArt.big_text(_root, "THE GAME", LOGO_BLOCK, SUB_SCALE, UiArt.CREAM)
	for l in LINES:
		_lines.append(UiArt.text_sprite(_root, l, LINE_SCALE))
	_hint = UiArt.text_sprite(_root, HINT, HINT_SCALE, Color("#c8bcb0"), UiArt.MUTED)
	var touch := get_node_or_null(^"/root/TouchControls")
	_prompt = UiArt.text_sprite(_root, PROMPT_TOUCH if touch and touch.is_touch_mode() else PROMPT, PROMPT_SCALE, UiArt.ACCENT, UiArt.ACCENT_SHADE)
	if touch:
		touch.input_mode_changed.connect(func(m: StringName) -> void: _set_prompt(PROMPT_TOUCH if m == &"touch" else PROMPT))
	for m in MODES:
		var normal := UiArt.text_sprite(_root, m[0], MODE_SCALE, UiArt.MUTED, UiArt.MUTED_SHADE)
		var picked := UiArt.text_sprite(_root, "[" + m[0] + "]", MODE_SCALE, UiArt.ACCENT, UiArt.ACCENT_SHADE)
		_modes.append([normal, picked])
	for s in _all_sprites():
		s.visible = false
	# Mirrors the typing timeline in _process: the moment the prompt shows and input opens.
	_ready_at = 1.9
	for l in _lines:
		_ready_at += (l.get_meta(&"char_x") as PackedInt32Array).size() / 40.0 + 0.1
	_ready_at += 0.6
	_t0 = Time.get_ticks_msec()


func _set_prompt(text: String) -> void:
	var img: Image = UiArt.EndingArt.text_image(text, UiArt.ACCENT, UiArt.ACCENT_SHADE).image
	_prompt.texture = ImageTexture.create_from_image(img)
	_prompt.region_rect = Rect2(Vector2.ZERO, img.get_size())


func _all_sprites() -> Array:
	var out: Array = []
	for s in _logo.sprites + _sub.sprites:
		if s:
			out.append(s)
	out.append_array(_lines)
	out.append(_hint)
	out.append(_prompt)
	for m in _modes:
		out.append_array(m)
	return out


# Starts the game as if A was pressed (fade out, unpause, start_requested).
func request_start() -> void:
	if _leaving >= 0.0:
		return
	_accept = false
	_leaving = _now()
	mode = MODES[_mode_i][1]
	Feedback.sfx(&"menu_select")
	Feedback.haptic(&"menu_select")


func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _process(_delta: float) -> void:
	_size = get_viewport().get_visible_rect().size
	_dim.position = Vector2.ZERO
	_dim.size = _size
	var t := _now()
	var cx := roundf(_size.x * 0.5)
	# Logo: letters drop one after the other, then JUICY hops as a wave.
	var logo_y := roundf(_size.y * 0.13)
	var x0 := roundf(cx - float(_logo.width) * 0.5)
	var drop_end := 0.0
	var logo_sprites: Array = _logo.sprites
	for i: int in logo_sprites.size():
		var s: Sprite2D = logo_sprites[i]
		if s == null:
			continue
		var lt := t - 0.2 - i * 0.12
		drop_end = 0.2 + i * 0.12 + DROP_STEPS.size() / ANIM_FPS
		var y_off := _drop(lt, s)
		if t > drop_end + 0.3:
			var ht := fmod(t - drop_end - 0.3, 2.6) - i * 0.07
			var hs := floori(ht * ANIM_FPS)
			if ht >= 0.0 and hs < HOP_STEPS.size():
				y_off = HOP_STEPS[hs] * LOGO_SCALE
		y_off = _settle(t, i, y_off, LOGO_SCALE)
		s.position = UiArt.snap(Vector2(x0 + _logo.offsets[i], logo_y + y_off), LOGO_SCALE)
	var sub_y := logo_y + 11 * LOGO_BLOCK * LOGO_SCALE + 26
	var sx0 := roundf(cx - float(_sub.width) * 0.5)
	var sub_sprites: Array = _sub.sprites
	for i: int in sub_sprites.size():
		var s2: Sprite2D = sub_sprites[i]
		if s2 == null:
			continue
		var y2 := _settle(t, i, _drop(t - 0.9 - i * 0.06, s2), SUB_SCALE)
		s2.position = UiArt.snap(Vector2(sx0 + _sub.offsets[i], sub_y + y2), SUB_SCALE)
	# Lines type in after the logo settles.
	var line_y := roundf(_size.y * 0.58)
	var lt0 := 1.9
	for i in _lines.size():
		var l := _lines[i]
		var chars: PackedInt32Array = l.get_meta(&"char_x")
		var n := clampi(floori((t - lt0) * 40.0), 0, chars.size())
		lt0 += chars.size() / 40.0 + 0.1
		l.visible = n > 0
		if n > 0:
			l.region_rect = Rect2(0, 0, chars[n - 1], l.texture.get_height())
		l.position = UiArt.snap(Vector2(cx - l.texture.get_width() * LINE_SCALE * 0.5, line_y + i * 40), LINE_SCALE)
	_hint.visible = t >= lt0 + 0.2
	_hint.position = UiArt.snap(Vector2(cx - _hint.texture.get_width() * HINT_SCALE * 0.5, line_y + _lines.size() * 40 + 24), HINT_SCALE)
	var hint_bottom := _hint.position.y + _hint.texture.get_height() * HINT_SCALE
	_layout_modes(cx, maxf(roundf(_size.y * 0.76), hint_bottom + 12.0), _hint.visible, t)
	var prompt_at := lt0 + 0.6
	if t >= prompt_at and _leaving < 0.0:
		_accept = true
		_prompt.visible = fmod(t - prompt_at, 1.1) < 0.8
	_prompt.position = UiArt.snap(Vector2(cx - _prompt.texture.get_width() * PROMPT_SCALE * 0.5, roundf(_size.y * 0.86)), PROMPT_SCALE)
	if _leaving >= 0.0:
		var steps := clampi(floori((t - _leaving) / FADE_TIME * FADE_STEPS), 0, FADE_STEPS)
		var k := 1.0 - float(steps) / FADE_STEPS
		_root.modulate.a = k
		# A scene change follows: darken to black so the cut never flashes the stage behind.
		_dim.color.a = lerpf(1.0, dim, k) if mode in black_out_modes else dim * k
		if steps >= FADE_STEPS and not _done:
			_done = true
			get_tree().paused = false
			start_requested.emit()
			# The black screen stays up until the scene change frees it.
			if not (mode in black_out_modes):
				queue_free()


# Stage row, same highlight as the pause options: brackets and accent on the pick, a hop on change.
func _layout_modes(cx: float, y: float, shown: bool, t: float) -> void:
	var total := MODE_GAP * (_modes.size() - 1)
	for m in _modes:
		total += (m[1] as Sprite2D).texture.get_width() * MODE_SCALE
	var x := roundf(cx - total * 0.5)
	var hop := 0.0
	var st := floori((t - _mode_t) * ANIM_FPS)
	if _mode_t >= 0.0 and st >= 0 and st < HOP.size():
		hop = HOP[st] * MODE_SCALE
	var bracket := UiArt.text_width("[", MODE_SCALE) - 2.0 * MODE_SCALE
	for i in _modes.size():
		var normal: Sprite2D = _modes[i][0]
		var picked: Sprite2D = _modes[i][1]
		normal.visible = shown and i != _mode_i
		picked.visible = shown and i == _mode_i
		normal.position = UiArt.snap(Vector2(x + bracket, y), MODE_SCALE)
		picked.position = UiArt.snap(Vector2(x, y + (hop if i == _mode_i else 0.0)), MODE_SCALE)
		x += picked.texture.get_width() * MODE_SCALE + MODE_GAP


# Jumps the intro to the moment input opens; the press that skips neither starts nor picks.
func _skip_intro() -> void:
	var t := _now()
	if t >= _ready_at:
		return
	_t0 -= ceili((_ready_at - t) * 1000.0)
	_skip_t = _now()
	_accept = true
	Feedback.sfx(&"menu_move")


func _settle(t: float, i: int, y_off: float, px: int) -> float:
	if _skip_t < 0.0:
		return y_off
	var st := floori((t - _skip_t - i * SETTLE_STAGGER) * ANIM_FPS)
	if st >= 0 and st < SETTLE_STEPS.size():
		return SETTLE_STEPS[st] * px
	return y_off


func _is_skip_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton or event is InputEventMouseButton:
		return event.pressed
	return event is InputEventJoypadMotion and absf(event.axis_value) >= 0.5


func _select(index: int) -> void:
	if index == _mode_i:
		return
	_mode_i = index
	_mode_t = _now()
	Feedback.sfx(&"menu_move")


func _drop(lt: float, s: Sprite2D) -> float:
	if lt < 0.0:
		s.visible = false
		return DROP_STEPS[0]
	s.visible = true
	var step := mini(floori(lt * ANIM_FPS), DROP_STEPS.size() - 1)
	return DROP_STEPS[step]


# Touch: before input opens a tap skips the intro; then a tap on the other stage picks it and any
# other tap starts.
func _tap(p: Vector2) -> void:
	if not _accept:
		if _leaving < 0.0:
			_skip_intro()
		return
	for i in _modes.size():
		var s: Sprite2D = _modes[i][1]
		if i != _mode_i and Rect2(s.position, s.region_rect.size * s.scale).grow(16.0).has_point(p):
			_select(i)
			return
	request_start()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			get_viewport().set_input_as_handled()
			_tap(event.position)
		return
	# The stick is tracked before input opens, so one held from the intro does not move the pick.
	var stick := 0
	if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
		var was := _axis_x
		_axis_x = event.axis_value
		if absf(was) < 0.5 and absf(_axis_x) >= 0.5:
			stick = int(signf(_axis_x))
	if not _accept:
		if _leaving < 0.0 and _is_skip_press(event):
			get_viewport().set_input_as_handled()
			_skip_intro()
		return
	var go := false
	var dir := stick
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: go = true
			JOY_BUTTON_DPAD_LEFT: dir = -1
			JOY_BUTTON_DPAD_RIGHT: dir = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode if event.keycode != KEY_NONE else event.physical_keycode
		var pk: int = event.physical_keycode
		go = k == KEY_ENTER or k == KEY_KP_ENTER or k == KEY_SPACE
		if k == KEY_LEFT or pk == KEY_A:
			dir = -1
		elif k == KEY_RIGHT or pk == KEY_D:
			dir = 1
	if go:
		get_viewport().set_input_as_handled()
		request_start()
	elif dir != 0:
		get_viewport().set_input_as_handled()
		_select(wrapi(_mode_i + dir, 0, MODES.size()))
