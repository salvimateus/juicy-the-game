extends CanvasLayer

# Pause menu: pauses the tree, shows the controls (gamepad art with callout lines, or the keyboard
# keys when the last input came from the keyboard) and the options Continuar, Reiniciar fase,
# Menu inicial and Sair do jogo. Opens on the `pause` action (Start/Menu, Esc), Menu, Esc or B close it.
# Taps pick options and tabs (the touch layout shows the gamepad view: its buttons carry the pad
# letters). It refuses to open while any node is in group `pause_blocker` or the tree is already paused.

signal opened
signal closed
# "Menu inicial": the menu already let go of the pause; the owner changes the scene.
signal menu_requested

const UiArt := preload("res://game/ui/ui_art.gd")
const Feedback := preload("res://game/feedback.gd")
const PAD_TEXTURE := preload("res://game/ui/art/gamepad.png")
const PAD_POINTS := "res://game/ui/art/gamepad.json"

const PAD_SCALE := 3
const TEXT_SCALE := 2
const OPTION_SCALE := 3
const TITLE_BLOCK := 2
const TITLE_SCALE := 3
const ANIM_FPS := 15.0
const LINE_W := 2.0
const OPTIONS := ["Continuar", "Reiniciar fase", "Menu inicial", "Sair do jogo"]
const OPTION_GAP := 56.0
const OPTION_MIN_GAP := 24.0
const OPTION_MARGIN := 32.0

# [point in gamepad.json, side (-1 left, 1 right), route, lane (art px above the pad, for "up"), name, text]
const PAD_LEGEND := [
	["lt", -1, "h", 0, "LT", "mirar"],
	["view", -1, "up", 16, "View", "painel de debug (F1)"],
	["left_stick", -1, "h", 0, "Analógico esquerdo", "andar / correr - baixo: agachar / engatinhar - escolhe a direção do pulo duplo e do rolamento"],
	["dpad", -1, "h", 0, "Direcional esq. / dir.", "trocar arma"],
	["menu", 1, "up", 22, "Menu", "pausa"],
	["x", 1, "up", 16, "X", "atacar (soco, kunai) - no ar: voadora com qualquer arma"],
	["rt", 1, "h", 0, "RT", "atirar"],
	["rb", 1, "h", 0, "RB", "correr muito rápido"],
	["y", 1, "h", 0, "Y", "interagir"],
	["b", 1, "h", 0, "B", "esquiva - com direção: rolamento"],
	["a", 1, "h", 0, "A", "pular - pulo duplo no ar - pendurado: cima e A sobe, baixo e A solta, lado e A salta - na parede: escalada"],
	["right_stick", 1, "h", 0, "Analógico direito", "apontar a mira (no arco, a força)"],
]

# [keys, text], keys are drawn as keycaps.
const KEY_LEGEND := [
	[["A", "D"], "andar / correr (ou as setas)"],
	[["S"], "agachar / engatinhar"],
	[["Espaço"], "pular - pulo duplo no ar - pendurado: W e Espaço sobe, S e Espaço solta, lado e Espaço salta - na parede: escalada"],
	[["K"], "esquiva - com direção: rolamento"],
	[["J"], "atacar (soco, kunai) - no ar: voadora com qualquer arma"],
	[["E"], "interagir"],
	[["L"], "mirar (ou botão direito do mouse)"],
	[["J"], "atirar (ou botão esquerdo do mouse)"],
	[["Mouse"], "apontar a mira (no arco, a força)"],
	[["Shift"], "correr muito rápido"],
	[["Q", "R"], "trocar arma"],
	[["Esc"], "pausa"],
	[["F1"], "painel de debug"],
]

@export var enabled := true
# Dim over the paused game, 0..1.
@export var dim := 0.86

var keyboard := false
# Shown legends, same row formats as PAD_LEGEND / KEY_LEGEND; set_legends swaps them per stage.
var pad_legend: Array = PAD_LEGEND
var key_legend: Array = KEY_LEGEND

var _open := false
var _sel := 0
var _sel_t := 0.0
var _t0 := 0
var _dim: ColorRect
var _root: Node2D
var _lines: Node2D
var _pad_group: Node2D
var _key_group: Node2D
var _pad: Sprite2D
var _points := {}
var _title: Dictionary
var _tabs: Array[Sprite2D] = []
var _options: Array = []
var _pad_entries: Array = []
var _key_entries: Array = []
var _axis := {}
var _size := Vector2.ZERO
var _last_keyboard := false
var _option_scale := OPTION_SCALE
# TouchControls autoload: owns the input mode when present (touch shows the pad view).
var _touch: Node


func _ready() -> void:
	layer = 105
	process_mode = Node.PROCESS_MODE_ALWAYS
	_touch = get_node_or_null(^"/root/TouchControls")
	_last_keyboard = Input.get_connected_joypads().is_empty() if _touch == null else not _touch.uses_pad_glyphs()
	_points = _load_points()
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, dim)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_root = Node2D.new()
	add_child(_root)
	_title = UiArt.big_text(_root, "PAUSA", TITLE_BLOCK, TITLE_SCALE, UiArt.CREAM)
	for i in 2:
		var label: String = ["Controle", "Teclado"][i]
		_tabs.append(UiArt.text_sprite(_root, label, TEXT_SCALE, UiArt.ACCENT, UiArt.ACCENT_SHADE))
		_tabs.append(UiArt.text_sprite(_root, label, TEXT_SCALE, UiArt.MUTED, UiArt.MUTED_SHADE))
	_pad_group = Node2D.new()
	_root.add_child(_pad_group)
	_pad = Sprite2D.new()
	_pad.texture = PAD_TEXTURE
	_pad.centered = false
	_pad.scale = Vector2(PAD_SCALE, PAD_SCALE)
	_pad.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pad_group.add_child(_pad)
	_lines = Node2D.new()
	_lines.draw.connect(_draw_lines)
	_pad_group.add_child(_lines)
	_key_group = Node2D.new()
	_key_group.draw.connect(_draw_keycaps)
	_root.add_child(_key_group)
	for i in OPTIONS.size():
		var normal := UiArt.text_sprite(_root, OPTIONS[i], OPTION_SCALE, UiArt.MUTED, UiArt.MUTED_SHADE)
		var picked := UiArt.text_sprite(_root, "[" + OPTIONS[i] + "]", OPTION_SCALE, UiArt.ACCENT, UiArt.ACCENT_SHADE)
		_options.append([normal, picked])
	visible = false


func _load_points() -> Dictionary:
	var f := FileAccess.open(PAD_POINTS, FileAccess.READ)
	if f == null:
		return {}
	var data: Variant = JSON.parse_string(f.get_as_text())
	return data.points if data is Dictionary and data.has("points") else {}


func is_open() -> bool:
	return _open


func can_open() -> bool:
	if not enabled or _open or get_tree().paused:
		return false
	return get_tree().get_nodes_in_group(&"pause_blocker").is_empty()


func open() -> void:
	if _open:
		return
	_open = true
	_sel = 0
	_sel_t = 0.0
	_t0 = Time.get_ticks_msec()
	keyboard = _last_keyboard
	get_tree().paused = true
	visible = true
	_layout(true)
	Feedback.sfx(&"pause_open")
	opened.emit()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false
	closed.emit()


func set_legends(pad: Array, keys: Array) -> void:
	pad_legend = pad
	key_legend = keys
	if _open:
		_layout(true)


func set_keyboard(on: bool) -> void:
	keyboard = on
	_layout(true)


func select(index: int) -> void:
	var i := clampi(index, 0, OPTIONS.size() - 1)
	if i != _sel:
		_sel = i
		_sel_t = _now()
		Feedback.sfx(&"menu_move")


func _now() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _confirm() -> void:
	Feedback.sfx(&"menu_select")
	match _sel:
		0:
			close()
		1:
			_open = false
			get_tree().paused = false
			Engine.time_scale = 1.0
			get_tree().reload_current_scene()
		2:
			_open = false
			get_tree().paused = false
			Engine.time_scale = 1.0
			menu_requested.emit()
		3:
			get_tree().quit()


func _process(_delta: float) -> void:
	if not _open:
		return
	_layout(false)


# --- Layout ---------------------------------------------------------------------------------

func _layout(rebuild: bool) -> void:
	var size := get_viewport().get_visible_rect().size
	if size != _size:
		_size = size
		rebuild = true
	_dim.size = _size
	var cx := roundf(_size.x * 0.5)
	var tx := roundf(cx - float(_title.width) * 0.5)
	var title_sprites: Array = _title.sprites
	for i: int in title_sprites.size():
		var s: Sprite2D = title_sprites[i]
		if s:
			s.position = UiArt.snap(Vector2(tx + _title.offsets[i], 18), TITLE_SCALE)
	# Tabs: the active one in the accent colour.
	var tab_y := 18.0 + 11 * TITLE_BLOCK * TITLE_SCALE + 14
	var gap := 40.0
	var w0 := _tabs[0].texture.get_width() * TEXT_SCALE
	var w1 := _tabs[2].texture.get_width() * TEXT_SCALE
	var x := roundf(cx - (w0 + gap + w1) * 0.5)
	for i in 2:
		var active := (i == 1) == keyboard
		_tabs[i * 2].visible = active
		_tabs[i * 2 + 1].visible = not active
		for j in 2:
			_tabs[i * 2 + j].position = UiArt.snap(Vector2(x, tab_y), TEXT_SCALE)
		x += (w0 if i == 0 else w1) + gap
	_pad_group.visible = not keyboard
	_key_group.visible = keyboard
	if rebuild:
		if keyboard:
			_build_keys()
		else:
			_build_pad()
	_layout_options()


func _clear(list: Array) -> void:
	for e in list:
		for s in e.sprites:
			(s as Node).queue_free()
	list.clear()


func _build_pad() -> void:
	_clear(_pad_entries)
	var pad_size := PAD_TEXTURE.get_size() * PAD_SCALE
	var top := 22.0 * PAD_SCALE + 150.0
	var origin := UiArt.snap(Vector2(roundf(_size.x * 0.5 - pad_size.x * 0.5), top), PAD_SCALE)
	_pad.position = origin
	var margin := 24.0
	var bus_gap := 56.0
	var col_w := origin.x - bus_gap - 20.0 - margin
	var line_h := 9.0 * TEXT_SCALE + 4.0
	var next_y := {-1: 0.0, 1: 0.0}
	var entries: Array = []
	for e in pad_legend:
		var key: String = e[0]
		if not _points.has(key):
			continue
		var p: Array = _points[key]
		var anchor: Vector2 = origin + (Vector2(p[0], p[1]) + Vector2(0.5, 0.5)) * PAD_SCALE
		var route_y := anchor.y
		if e[2] == "up":
			route_y = origin.y - float(e[3]) * PAD_SCALE
		elif key == "lt" or key == "rt":
			# The trigger labels sit right above the shoulders.
			route_y = origin.y - 4.0 * PAD_SCALE
		entries.append([e, anchor, route_y])
	entries.sort_custom(func(l: Array, r: Array) -> bool: return l[2] < r[2])
	for item in entries:
		var e: Array = item[0]
		var key: String = e[0]
		var side: int = e[1]
		var anchor: Vector2 = item[1]
		var route_y: float = item[2]
		var name_text: String = e[4] + ":"
		var body: String = e[5]
		var name_w := UiArt.text_width(name_text + " ", TEXT_SCALE)
		var lines := UiArt.wrap(body, TEXT_SCALE, col_w, col_w - name_w)
		var height := lines.size() * line_h
		var y := maxf(route_y - line_h * 0.5, next_y[side])
		next_y[side] = y + height + 10.0
		var sprites: Array = []
		var text_x := origin.x + pad_size.x + bus_gap + 20.0 if side == 1 else 0.0
		for li in lines.size():
			var lw := UiArt.text_width(lines[li], TEXT_SCALE) + (name_w if li == 0 else 0.0)
			var lx := text_x if side == 1 else origin.x - bus_gap - 20.0 - lw
			var ly := y + li * line_h
			if li == 0:
				var ns := UiArt.text_sprite(_pad_group, name_text, TEXT_SCALE, UiArt.ACCENT, UiArt.ACCENT_SHADE)
				ns.position = UiArt.snap(Vector2(lx, ly), TEXT_SCALE)
				sprites.append(ns)
				lx += name_w
			var ts := UiArt.text_sprite(_pad_group, lines[li], TEXT_SCALE)
			ts.position = UiArt.snap(Vector2(lx, ly), TEXT_SCALE)
			sprites.append(ts)
		var label: Sprite2D = null
		if key == "lt" or key == "rt":
			label = UiArt.text_sprite(_pad_group, key.to_upper(), TEXT_SCALE, UiArt.ACCENT, UiArt.ACCENT_SHADE)
			# RT shifts right so the X callout, which rises next to it, never touches the label.
			var shift := 6.0 * PAD_SCALE if key == "rt" else 0.0
			label.position = UiArt.snap(Vector2(anchor.x + shift - label.texture.get_width() * TEXT_SCALE * 0.5, route_y - 9.0), TEXT_SCALE)
			sprites.append(label)
		_pad_entries.append({sprites = sprites, side = side, anchor = anchor, route = e[2], route_y = route_y,
			text_y = y + line_h * 0.5 - 2.0, label = label})
	# Keep both columns clear of the options row, long columns start higher.
	_lines.queue_redraw()


func _draw_lines() -> void:
	var pad_size := PAD_TEXTURE.get_size() * PAD_SCALE
	var left_bus := _pad.position.x - 14.0
	var right_bus := _pad.position.x + pad_size.x + 14.0
	var count := {-1: 0, 1: 0}
	for e in _pad_entries:
		count[e.side] += 1
	var idx := {-1: 0, 1: 0}
	for e in _pad_entries:
		var side: int = e.side
		var a: Vector2 = e.anchor
		var ry: float = e.route_y
		var ty: float = e.text_y
		# Lower entries turn closer to the pad, so no line crosses another.
		var step: int = count[side] - 1 - idx[side]
		var bus := (right_bus + step * 3.0) if side == 1 else (left_bus - step * 3.0)
		idx[side] += 1
		var end_x := (_pad.position.x + pad_size.x + 70.0) if side == 1 else (_pad.position.x - 70.0)
		var pts := PackedVector2Array()
		if e.label:
			var lab: Sprite2D = e.label
			var lx := lab.position.x + (lab.texture.get_width() * TEXT_SCALE + 4.0 if side == 1 else -4.0)
			pts.append_array([Vector2(lx, ry), Vector2(bus, ry), Vector2(bus, ty), Vector2(end_x, ty)])
		elif e.route == "up":
			pts.append_array([a, Vector2(a.x, ry), Vector2(bus, ry), Vector2(bus, ty), Vector2(end_x, ty)])
		else:
			pts.append_array([a, Vector2(bus, a.y), Vector2(bus, ty), Vector2(end_x, ty)])
		for i in pts.size() - 1:
			var p0 := UiArt.snap(pts[i], LINE_W)
			var p1 := UiArt.snap(pts[i + 1], LINE_W)
			var r := Rect2(p0.min(p1), (p1 - p0).abs() + Vector2(LINE_W, LINE_W))
			_lines.draw_rect(r.grow(1.0), Color(0.05, 0.04, 0.05))
			_lines.draw_rect(r, UiArt.LINE)
		if not e.label:
			var dot := UiArt.snap(a, LINE_W) - Vector2(2, 2)
			_lines.draw_rect(Rect2(dot - Vector2(1, 1), Vector2(8, 8)), Color(0.05, 0.04, 0.05))
			_lines.draw_rect(Rect2(dot, Vector2(6, 6)), UiArt.ACCENT)


func _build_keys() -> void:
	_clear(_key_entries)
	var top := 22.0 * PAD_SCALE + 118.0
	var bottom := _size.y - 110.0
	var cols := 2
	var gap := 48.0
	var total_w := minf(_size.x - 64.0, 1400.0)
	var col_w := (total_w - gap) / cols
	var keys_w := 150.0
	var line_h := 9.0 * TEXT_SCALE + 4.0
	var x0 := roundf(_size.x * 0.5 - total_w * 0.5)
	var per_col := ceili(key_legend.size() / float(cols))
	for c in cols:
		var y := top
		for k in range(c * per_col, mini((c + 1) * per_col, key_legend.size())):
			var entry: Array = key_legend[k]
			var keys: Array = entry[0]
			var lines := UiArt.wrap(entry[1], TEXT_SCALE, col_w - keys_w - 16.0)
			var sprites: Array = []
			var caps: Array = []
			var kx := x0 + c * (col_w + gap) + keys_w
			for i in range(keys.size() - 1, -1, -1):
				var ks := UiArt.text_sprite(_key_group, keys[i], TEXT_SCALE, UiArt.TEXT, UiArt.TEXT_SHADE)
				var kw := ks.texture.get_width() * TEXT_SCALE
				kx -= kw + 16.0
				ks.position = UiArt.snap(Vector2(kx + 8.0, y + 2.0), TEXT_SCALE)
				caps.append(Rect2(kx, y - 4.0, kw + 16.0, line_h + 6.0))
				kx -= 8.0
				sprites.append(ks)
			for li in lines.size():
				var ts := UiArt.text_sprite(_key_group, lines[li], TEXT_SCALE)
				ts.position = UiArt.snap(Vector2(x0 + c * (col_w + gap) + keys_w + 16.0, y + 2.0 + li * line_h), TEXT_SCALE)
				sprites.append(ts)
			_key_entries.append({sprites = sprites, caps = caps})
			y += maxf(lines.size() * line_h, line_h + 6.0) + 14.0
			if y > bottom:
				break
	_key_group.queue_redraw()


func _draw_keycaps() -> void:
	for e in _key_entries:
		for r in e.caps:
			var rect: Rect2 = r
			rect = Rect2(UiArt.snap(rect.position, 2.0), UiArt.snap(rect.size, 2.0))
			_key_group.draw_rect(rect, Color("#141013"))
			_key_group.draw_rect(rect.grow(-2.0), Color("#5a4c50"))
			_key_group.draw_rect(Rect2(rect.position + Vector2(2, 2), rect.size - Vector2(4, 8)), Color("#3a3036"))


# The row keeps OPTION_SCALE and OPTION_GAP while they fit; a narrow screen first tightens the
# gap, then drops the text one integer scale.
func _fit_options() -> float:
	var texels := 0.0
	for o in _options:
		texels += (o[1] as Sprite2D).texture.get_width()
	var room := _size.x - OPTION_MARGIN * 2.0
	var n := _options.size() - 1
	_option_scale = OPTION_SCALE
	while _option_scale > 1 and texels * _option_scale + OPTION_MIN_GAP * n > room:
		_option_scale -= 1
	for o in _options:
		for s: Sprite2D in o:
			s.scale = Vector2(_option_scale, _option_scale)
	return clampf((room - texels * _option_scale) / maxf(n, 1), OPTION_MIN_GAP, OPTION_GAP)


func _layout_options() -> void:
	var gap := _fit_options()
	var sc := _option_scale
	var y := _size.y - 62.0
	var total := 0.0
	for o in _options:
		total += (o[1] as Sprite2D).texture.get_width() * sc
	total += gap * (_options.size() - 1)
	var x := roundf(_size.x * 0.5 - total * 0.5)
	var hop := 0.0
	var st := floori((_now() - _sel_t) * ANIM_FPS)
	if st >= 0 and st < 3:
		hop = [-2.0, -1.0, 0.0][st] * sc
	var bracket := UiArt.text_width("[", sc) - 2.0 * sc
	for i in _options.size():
		var normal: Sprite2D = _options[i][0]
		var picked: Sprite2D = _options[i][1]
		var w := picked.texture.get_width() * sc
		normal.visible = i != _sel
		picked.visible = i == _sel
		normal.position = UiArt.snap(Vector2(x + bracket, y), sc)
		picked.position = UiArt.snap(Vector2(x, y + (hop if i == _sel else 0.0)), sc)
		x += w + gap


# --- Input ----------------------------------------------------------------------------------

# Touch: a tap on an option picks and confirms it ("Sair do jogo" only once already picked); a tap
# on a tab switches the view.
func _tap(p: Vector2) -> void:
	for i in 2:
		if _sprite_rect(_tabs[i * 2]).grow(10.0).has_point(p):
			if (i == 1) != keyboard:
				set_keyboard(i == 1)
				Feedback.sfx(&"menu_move")
			return
	for i in _options.size():
		var picked: Sprite2D = _options[i][1]
		if _sprite_rect(picked).grow(12.0).has_point(p):
			var was := _sel
			select(i)
			if i != OPTIONS.size() - 1 or was == i:
				_confirm()
			return


func _sprite_rect(s: Sprite2D) -> Rect2:
	return Rect2(s.position, s.region_rect.size * s.scale)


func _is_pause(event: InputEvent) -> bool:
	if InputMap.has_action(&"pause"):
		return event.is_action_pressed(&"pause")
	if event is InputEventKey and event.pressed and not event.echo:
		return event.physical_keycode == KEY_ESCAPE
	return event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START


func _input(event: InputEvent) -> void:
	if _touch:
		_last_keyboard = not _touch.uses_pad_glyphs()
	elif event is InputEventKey or event is InputEventMouseButton:
		_last_keyboard = true
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_last_keyboard = false
	if not _open:
		if _is_pause(event) and can_open():
			get_viewport().set_input_as_handled()
			open()
		return
	get_viewport().set_input_as_handled()
	if _last_keyboard != keyboard and (event is InputEventKey or event is InputEventJoypadButton):
		set_keyboard(_last_keyboard)
	if _is_pause(event):
		close()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_tap(event.position)
		return
	var dir := 0
	var ok := false
	var cancel := false
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: ok = true
			JOY_BUTTON_B: cancel = true
			JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_UP: dir = -1
			JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN: dir = 1
	elif event is InputEventJoypadMotion and (event.axis == JOY_AXIS_LEFT_X or event.axis == JOY_AXIS_LEFT_Y):
		var was: float = _axis.get(event.axis, 0.0)
		_axis[event.axis] = event.axis_value
		if absf(was) < 0.5 and absf(event.axis_value) >= 0.5:
			dir = int(signf(event.axis_value))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: ok = true
			KEY_LEFT, KEY_UP, KEY_A, KEY_W: dir = -1
			KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S: dir = 1
			KEY_TAB: set_keyboard(not keyboard)
	if cancel:
		close()
	elif ok:
		_confirm()
	elif dir != 0:
		select(wrapi(_sel + dir, 0, OPTIONS.size()))
