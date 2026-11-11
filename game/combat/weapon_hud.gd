extends CanvasLayer

# Weapon bar, bottom left (top left in touch mode): the active weapon's icon at 2x (128 px), the others at 1x (64 px) in a
# row aligned on the base, and the current weapon's controls in small text under it. Switching
# flashes the active icon and pops its scale in steps. Icons: res://game/art/icons/<id>[_inactive|_flash].png.

const Weapons := preload("res://game/combat/weapons.gd")
const ICON_DIR := "res://game/art/icons/"
const MARGIN := 16
const GAP := 7
const ICONS_JSON := "res://game/art/icons/icons.json"
const FLASH_TIME := 0.12
# Stepped pop of the active slot (scale per step, seconds per step).
const POP_STEPS: Array[float] = [1.25, 1.125, 1.0]
const POP_STEP_TIME := 0.05

var _root: Control
var _column: VBoxContainer
var _active: TextureRect
var _inactive: Array[TextureRect] = []
var _hint: Label
var _current: StringName = &""
var _flash_left := 0.0
var _pop_index := -1
var _pop_left := 0.0
var _cache := {}
# From icons.json: art size times the suggested scale (active 2x, inactive 1x).
var _active_size := 90
var _inactive_size := 45


func _read_sizes() -> void:
	if not FileAccess.file_exists(ICONS_JSON):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ICONS_JSON))
	if not data is Dictionary:
		return
	var px := int(data.get("size", [45, 45])[0])
	var scale: Dictionary = data.get("suggested_scale", {})
	_active_size = px * int(scale.get("active", 2))
	_inactive_size = px * int(scale.get("inactive", 1))


func _ready() -> void:
	layer = 9
	_read_sizes()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	add_to_group(&"weapon_hud")
	var column := VBoxContainer.new()
	_column = column
	column.add_theme_constant_override(&"separation", 2)
	column.offset_left = MARGIN
	_root.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", GAP)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_child(row)
	_active = _slot(_active_size)
	row.add_child(_active)
	for i in Weapons.ORDER.size() - 1:
		var s := _slot(_inactive_size)
		s.size_flags_vertical = Control.SIZE_SHRINK_END
		row.add_child(s)
		_inactive.append(s)
	_hint = Label.new()
	_hint.add_theme_font_size_override(&"font_size", 11)
	_hint.add_theme_color_override(&"font_color", Color(0.91, 0.88, 0.78, 0.85))
	_hint.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override(&"shadow_offset_x", 1)
	_hint.add_theme_constant_override(&"shadow_offset_y", 1)
	column.add_child(_hint)
	var touch := get_node_or_null(^"/root/TouchControls")
	_place(touch != null and touch.is_touch_mode())
	if touch:
		touch.input_mode_changed.connect(func(mode: StringName) -> void: _place(mode == &"touch"))


# Bottom left; top left in touch mode, where the move stick does not cover it.
func _place(top: bool) -> void:
	_column.anchor_top = 0.0 if top else 1.0
	_column.anchor_bottom = 0.0 if top else 1.0
	_column.offset_top = MARGIN if top else 0.0
	_column.offset_bottom = 0.0 if top else -MARGIN
	_column.grow_vertical = Control.GROW_DIRECTION_END if top else Control.GROW_DIRECTION_BEGIN
	_column.reset_size()


# Canvas rect of the icon row: the touch controls cycle the weapon on a tap there.
func touch_rect() -> Rect2:
	var r := _active.get_global_rect()
	for s in _inactive:
		r = r.merge(s.get_global_rect())
	return r


func _slot(px: int) -> TextureRect:
	var t := TextureRect.new()
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _icon(id: StringName, variant: String) -> Texture2D:
	var key := "%s%s" % [id, variant]
	if not _cache.has(key):
		var path := ICON_DIR + key + ".png"
		if ResourceLoader.exists(path):
			_cache[key] = load(path)
		else:
			_cache[key] = _raw_png(path) if FileAccess.file_exists(path) else Weapons.icon(id)
	return _cache[key]


# A PNG the editor has not imported yet (no .import): decoded straight from the file.
func _raw_png(path: String) -> Texture2D:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return ImageTexture.create_from_image(img)


func show_weapon(id: StringName) -> void:
	var switched := _current != &"" and id != _current
	_current = id
	_active.texture = _icon(id, "_flash" if switched else "")
	var i := Weapons.ORDER.find(id)
	for k in _inactive.size():
		_inactive[k].texture = _icon(Weapons.ORDER[(i + 1 + k) % Weapons.ORDER.size()], "_inactive")
	var hint := Weapons.hint(id)
	_hint.text = hint if id in Weapons.READY else "(em breve)"
	if switched:
		_flash_left = FLASH_TIME
		_pop_index = 0
		_pop_left = POP_STEP_TIME
		_set_pop(POP_STEPS[0])


func set_dimmed(on: bool) -> void:
	if _root:
		_root.modulate.a = 0.35 if on else 1.0


func _set_pop(s: float) -> void:
	_active.pivot_offset = _active.size * 0.5
	_active.scale = Vector2(s, s)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_active.texture = _icon(_current, "")
	if _pop_index >= 0:
		_pop_left -= delta
		if _pop_left <= 0.0:
			_pop_index += 1
			if _pop_index >= POP_STEPS.size():
				_pop_index = -1
				_set_pop(1.0)
			else:
				_pop_left = POP_STEP_TIME
				_set_pop(POP_STEPS[_pop_index])
