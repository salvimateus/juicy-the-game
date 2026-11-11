extends CanvasLayer

# Debug sound board. F2 toggles; ui_up/ui_down select, ui_left/ui_right change surface,
# ui_page_up/ui_page_down change strength, ui_accept plays (or toggles a loop). Also fires Haptics.

const TOGGLE_KEY := KEY_F2
const STRENGTH_STEP := 0.25

var _ids: Array[StringName] = []
var _labels: Array[Label] = []
var _index := 0
var _surface_index := 0
var _strength := 1.0
var _loop_handle := 0
var _loop_haptic := 0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _header: Label
var _status: Label


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		_set_open(not visible)
		get_viewport().set_input_as_handled()
		return
	if not visible:
		return
	if event.is_action_pressed(&"ui_up", true):
		_select(_index - 1)
	elif event.is_action_pressed(&"ui_down", true):
		_select(_index + 1)
	elif event.is_action_pressed(&"ui_left", true):
		_cycle_surface(-1)
	elif event.is_action_pressed(&"ui_right", true):
		_cycle_surface(1)
	elif event.is_action_pressed(&"ui_page_up", true):
		_set_strength(_strength + STRENGTH_STEP)
	elif event.is_action_pressed(&"ui_page_down", true):
		_set_strength(_strength - STRENGTH_STEP)
	elif event.is_action_pressed(&"ui_accept"):
		_trigger()
	elif event.is_action_pressed(&"ui_cancel"):
		_set_open(false)
	else:
		return
	get_viewport().set_input_as_handled()


func _build_ui() -> void:
	if _sfx():
		_ids = _sfx().ids()
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -300.0
	_panel.offset_right = -8.0
	_panel.offset_top = 8.0
	_panel.offset_bottom = 420.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.82)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	_panel.add_child(box)
	_header = _label(13, Color(1.0, 0.85, 0.4))
	box.add_child(_header)
	_status = _label(11, Color(0.7, 0.75, 0.85))
	box.add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 0)
	_scroll.add_child(list)
	for id in _ids:
		var l := _label(12, Color(0.8, 0.82, 0.88))
		l.text = "  " + String(id)
		list.add_child(l)
		_labels.append(l)
	var help := _label(10, Color(0.5, 0.55, 0.65))
	help.text = "F2 close  up/down select  left/right surface\npgup/pgdn strength  accept play"
	box.add_child(help)
	_refresh()


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


func _set_open(open: bool) -> void:
	visible = open
	if not open:
		_stop_loop()


func _select(i: int) -> void:
	if _ids.is_empty():
		return
	_stop_loop()
	_index = wrapi(i, 0, _ids.size())
	_surface_index = 0
	_refresh()
	_scroll.ensure_control_visible(_labels[_index])


func _cycle_surface(dir: int) -> void:
	var surf := _surfaces()
	if surf.is_empty():
		return
	_surface_index = wrapi(_surface_index + dir, 0, surf.size())
	_refresh()


func _set_strength(value: float) -> void:
	_strength = clampf(value, 0.0, 1.5)
	if _loop_handle and _sfx():
		_sfx().set_loop_strength(_loop_handle, _strength)
	var haptics := get_node_or_null(^"/root/Haptics")
	if _loop_haptic and haptics:
		haptics.set_loop_strength(_loop_haptic, _strength)
	_refresh()


func _trigger() -> void:
	var sfx := _sfx()
	if sfx == null or _ids.is_empty():
		return
	var id := _ids[_index]
	var haptics := get_node_or_null(^"/root/Haptics")
	if sfx.is_loop(id):
		if _loop_handle:
			_stop_loop()
		else:
			_loop_handle = sfx.start_loop(id)
			sfx.set_loop_strength(_loop_handle, _strength)
			if haptics:
				_loop_haptic = haptics.start_loop(id, _strength)
	else:
		var surf := _surfaces()
		sfx.play(id, Vector2.INF, _strength, surf[_surface_index] if not surf.is_empty() else &"")
		if haptics:
			haptics.play(id, _strength)
	_refresh()


func _stop_loop() -> void:
	var sfx := _sfx()
	if _loop_handle and sfx:
		sfx.stop_loop(_loop_handle)
	var haptics := get_node_or_null(^"/root/Haptics")
	if _loop_haptic and haptics:
		haptics.stop_loop(_loop_haptic)
	_loop_handle = 0
	_loop_haptic = 0


func _surfaces() -> Array:
	var sfx := _sfx()
	return sfx.surfaces(_ids[_index]) if sfx and not _ids.is_empty() else []


func _refresh() -> void:
	for i in _labels.size():
		var on := i == _index
		_labels[i].text = ("> " if on else "  ") + String(_ids[i])
		_labels[i].add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0) if on else Color(0.62, 0.65, 0.72))
	if _ids.is_empty():
		_header.text = "SFX  (Sfx autoload missing)"
		return
	var id := _ids[_index]
	var surf := _surfaces()
	var haptics := get_node_or_null(^"/root/Haptics")
	_header.text = "SFX  %s" % id
	_status.text = "surface: %s   strength: %.2f%s%s" % [
		"< %s >" % surf[_surface_index] if not surf.is_empty() else "-",
		_strength,
		"   [loop %s]" % ("ON" if _loop_handle else "off") if _sfx().is_loop(id) else "",
		"   rumble" if haptics and haptics.has_profile(id) else ""]


func _sfx() -> Node:
	return get_node_or_null(^"/root/Sfx")
