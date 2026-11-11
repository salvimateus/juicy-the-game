extends CanvasLayer

# Short top-centre toast above every menu: pixel-font title and optional detail on a dark panel,
# drops in by steps, holds, then blinks out. Used for the pad (dis)connection and the Android back.

const UiArt := preload("res://game/ui/ui_art.gd")

const TITLE_SCALE := 3
const DETAIL_SCALE := 2
const PAD := 14.0
const TOP := 28.0
const DROP_STEPS := [-40.0, -16.0, 4.0, 0.0]
const ANIM_FPS := 15.0

var _panel: ColorRect
var _root: Node2D
var _t := -1.0
var _hold := 2.4


func _ready() -> void:
	layer = 125
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	_panel.color = Color(0.06, 0.05, 0.09, 0.86)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_root = Node2D.new()
	add_child(_root)
	_panel.visible = false


func show_toast(title: String, detail := "", hold := 2.4) -> void:
	for c in _root.get_children():
		c.queue_free()
	var t := UiArt.text_sprite(_root, title, TITLE_SCALE, UiArt.ACCENT, UiArt.ACCENT_SHADE)
	var w := t.texture.get_width() * TITLE_SCALE
	var h := t.texture.get_height() * TITLE_SCALE
	var d: Sprite2D = null
	if not detail.is_empty():
		d = UiArt.text_sprite(_root, detail, DETAIL_SCALE)
		w = maxf(w, d.texture.get_width() * DETAIL_SCALE)
		d.position = Vector2(roundf((w - d.texture.get_width() * DETAIL_SCALE) * 0.5), h + 4.0)
		h += 4.0 + d.texture.get_height() * DETAIL_SCALE
	t.position = Vector2(roundf((w - t.texture.get_width() * TITLE_SCALE) * 0.5), 0.0)
	_panel.size = Vector2(w + PAD * 2.0, h + PAD * 2.0)
	_hold = hold
	_t = 0.0
	_place()


func _place() -> void:
	var vp := get_viewport().get_visible_rect().size
	var st := mini(floori(_t * ANIM_FPS), DROP_STEPS.size() - 1)
	var y: float = TOP + DROP_STEPS[st]
	_panel.position = Vector2(roundf((vp.x - _panel.size.x) * 0.5), y)
	_root.position = _panel.position + Vector2(PAD, PAD)


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var shown := _t < _hold
	# Leaves with two quick blinks (no alpha fades on the pixel art).
	if _t >= _hold - 0.3 and shown:
		shown = int((_t - _hold) * 20.0) % 2 == 0
	_panel.visible = shown
	_root.visible = shown
	if _t >= _hold:
		_t = -1.0
		return
	_place()
