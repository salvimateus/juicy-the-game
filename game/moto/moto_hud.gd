extends CanvasLayer

# Motocross HUD: run timer in pre-made digit slots (no texture is made per frame), the session
# record, a controls hint per state and the "CHEGADA!" banner at the finish.

const UiArt := preload("res://game/ui/ui_art.gd")
const EndingArt := preload("res://game/ending/ending_art.gd")

const TIMER_SCALE := 4
const TEXT_SCALE := 2
const MARGIN := 24.0
const BANNER_BLOCK := 2
const BANNER_SCALE := 3
const BANNER_POP := 0.3
const BANNER_DROP := 160.0
const BANNER_BOUNCE := 12.0
# Glyphs the logo set lacks, in its style (2-pixel strokes, 11 rows).
const EXTRA_GLYPHS := {
	"D": ["######.", "#######", "##...##", "##...##", "##...##", "##...##", "##...##", "##...##", "##...##", "#######", "######."],
	"!": ["##", "##", "##", "##", "##", "##", "##", "..", "..", "##", "##"],
	"M": ["##....##", "###..###", "########", "##.##.##", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##"],
	"O": [".######.", "########", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "########", ".######."],
	"R": ["#######.", "########", "##....##", "##....##", "##....##", "########", "#######.", "##..##..", "##...##.", "##....##", "##....##"],
	"L": ["##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "#######", "#######"],
	"F": ["#######", "#######", "##.....", "##.....", "######.", "######.", "##.....", "##.....", "##.....", "##.....", "##....."],
	"N": ["##....##", "###...##", "####..##", "##.##.##", "##.##.##", "##..####", "##...###", "##....##", "##....##", "##....##", "##....##"],
	"I": ["######", "######", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "######", "######"],
}
const TRICK_TIME := 1.6
const TRICK_SCALE := 2
const HINTS := {
	&"foot": "Y / E: montar na moto",
	&"riding": "RT / W: acelerar    LT / S: frear e ré    analógico / A D: inclinar    Back / R: recomeçar",
	&"stopped": "Y / E: descer    RT / W: acelerar    Back / R: recomeçar",
	&"crashed": "Caiu! Voltando para a largada...",
	&"finished": "Back / R: correr de novo    Y / E: descer",
}

# Best time of this run of the game (seconds).
static var best := INF

var _glyphs := {}
var _cell_w := 0.0
var _timer_root: Node2D
var _slots: Array[Sprite2D] = []
var _record: Sprite2D
var _hint: Sprite2D
var _hint_key: StringName = &""
var _banner: Node2D
var _banner_time: Sprite2D
var _banner_t := -1.0
var _trick: Node2D
var _trick_t := -1.0
var _text := ""


func _ready() -> void:
	layer = 5
	var scratch := Node.new()
	add_child(scratch)
	for ch in "0123456789:.":
		var s := UiArt.text_sprite(scratch, ch, 1, UiArt.TEXT, UiArt.TEXT_SHADE)
		_glyphs[ch] = s.texture
		if ch.is_valid_int():
			_cell_w = maxf(_cell_w, s.texture.get_width() - 1)
	scratch.queue_free()
	_timer_root = Node2D.new()
	add_child(_timer_root)
	for i in 7:
		var s := Sprite2D.new()
		s.centered = false
		s.scale = Vector2.ONE * TIMER_SCALE
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_timer_root.add_child(s)
		_slots.append(s)
	_banner = Node2D.new()
	_banner.visible = false
	add_child(_banner)
	_banner.set_meta(&"width", _big_word(_banner, "CHEGADA!", BANNER_SCALE))
	_trick = Node2D.new()
	_trick.visible = false
	add_child(_trick)
	set_time(0.0)
	_refresh_record()
	get_tree().root.size_changed.connect(_layout)
	_layout()


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


# Big logo-style letters into parent; returns the width.
func _big_word(parent: Node2D, word: String, scale: int) -> float:
	var glyphs: Dictionary = UiArt.LOGO_GLYPHS.merged(EXTRA_GLYPHS)
	var x := 0.0
	for i in word.length():
		if word[i] == " ":
			x += UiArt.BIG_SPACE * BANNER_BLOCK * scale
			continue
		var img := EndingArt.title_glyph(word[i], BANNER_BLOCK, glyphs, PackedColorArray(UiArt.ORANGE))
		var g := Sprite2D.new()
		g.texture = ImageTexture.create_from_image(img)
		g.centered = false
		g.scale = Vector2.ONE * scale
		g.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		g.position = Vector2(x - 2 * scale, 0)
		parent.add_child(g)
		x += (img.get_width() - 4) * scale + UiArt.BIG_GAP * BANNER_BLOCK * scale
	return x


# Trick callout under the timer ("MORTAL!"): drops in, holds, then hides.
func show_trick(text: String) -> void:
	for c in _trick.get_children():
		c.queue_free()
	_trick.set_meta(&"width", _big_word(_trick, text, TRICK_SCALE))
	_trick.visible = true
	_trick_t = 0.0
	_layout_trick()


func _layout_trick() -> void:
	if not _trick.visible:
		return
	var u := clampf(_trick_t / BANNER_POP, 0.0, 1.0)
	var drop := -BANNER_DROP * (1.0 - u) * (1.0 - u) + BANNER_BOUNCE * sin(u * PI)
	var w: float = _trick.get_meta(&"width", 0.0)
	_trick.position = UiArt.snap(Vector2(_screen().x * 0.5 - w * 0.5, MARGIN + 9.0 * TIMER_SCALE + 48.0 + drop), TRICK_SCALE)


static func format_time(t: float) -> String:
	var cs := int(floorf(t * 100.0))
	var m := cs / 6000
	var s := (cs / 100) % 60
	return "%d:%02d.%02d" % [mini(m, 9), s, cs % 100]


func set_time(t: float) -> void:
	var text := format_time(t)
	if text == _text:
		return
	_text = text
	var x := 0.0
	for i in _slots.size():
		var s := _slots[i]
		if i >= text.length():
			s.visible = false
			continue
		var ch := text[i]
		s.visible = true
		s.texture = _glyphs[ch]
		var w: float = _cell_w if ch.is_valid_int() else float(s.texture.get_width() - 1)
		s.position = Vector2(x + (w - (s.texture.get_width() - 1)) * 0.5 * TIMER_SCALE, 0)
		x += w * TIMER_SCALE
	_timer_root.set_meta(&"width", x)
	_layout_timer()


# Records t when it beats the session best; returns true then.
func submit(t: float) -> bool:
	var is_record := t < best
	if is_record:
		best = t
		_refresh_record()
	return is_record


func _refresh_record() -> void:
	if _record:
		_record.queue_free()
	var text := "Recorde: --" if best == INF else "Recorde: " + format_time(best)
	_record = UiArt.text_sprite(self, text, TEXT_SCALE, UiArt.MUTED, UiArt.MUTED_SHADE)
	_layout()


func set_hint(key: StringName) -> void:
	if key == _hint_key:
		return
	_hint_key = key
	if _hint:
		_hint.queue_free()
	_hint = UiArt.text_sprite(self, HINTS.get(key, ""), TEXT_SCALE)
	_layout()


func show_finish(t: float, is_record: bool) -> void:
	_trick.visible = false
	_trick_t = -1.0
	if _banner_time:
		_banner_time.queue_free()
	var text := format_time(t) + ("  novo recorde!" if is_record else "")
	_banner_time = UiArt.text_sprite(_banner, text, 3, UiArt.ACCENT if is_record else UiArt.TEXT, UiArt.ACCENT_SHADE if is_record else UiArt.TEXT_SHADE)
	_banner.visible = true
	_banner_t = 0.0
	_layout()


func hide_finish() -> void:
	_banner.visible = false
	_banner_t = -1.0
	_trick.visible = false
	_trick_t = -1.0


func _process(delta: float) -> void:
	if _trick_t >= 0.0:
		_trick_t += delta
		_layout_trick()
		if _trick_t > TRICK_TIME:
			_trick_t = -1.0
			_trick.visible = false
	if _banner_t < 0.0:
		return
	_banner_t += delta
	if _banner_t > BANNER_POP:
		_banner_t = -1.0
	_layout_banner()


func _layout() -> void:
	_layout_timer()
	var size := _screen()
	if _record:
		_record.position = UiArt.snap(Vector2(size.x * 0.5 - _record.texture.get_width() * TEXT_SCALE * 0.5, MARGIN + 9.0 * TIMER_SCALE + 12.0), TEXT_SCALE)
	if _hint:
		_hint.position = UiArt.snap(Vector2(size.x * 0.5 - _hint.texture.get_width() * TEXT_SCALE * 0.5, size.y - MARGIN - 9.0 * TEXT_SCALE), TEXT_SCALE)
	_layout_banner()


func _layout_timer() -> void:
	var w: float = _timer_root.get_meta(&"width", 0.0)
	_timer_root.position = UiArt.snap(Vector2(_screen().x * 0.5 - w * 0.5, MARGIN), TIMER_SCALE)


func _layout_banner() -> void:
	if not _banner.visible:
		return
	var size := _screen()
	var w: float = _banner.get_meta(&"width", 0.0)
	# Drops in from above with a small bounce (positions only, so the letters stay crisp).
	var u := clampf(_banner_t / BANNER_POP, 0.0, 1.0) if _banner_t >= 0.0 else 1.0
	var drop := -BANNER_DROP * (1.0 - u) * (1.0 - u) + BANNER_BOUNCE * sin(u * PI)
	_banner.position = UiArt.snap(Vector2(size.x * 0.5 - w * 0.5, size.y * 0.16 + drop), BANNER_SCALE)
	if _banner_time:
		var bw: float = _banner.get_meta(&"width", 0.0)
		_banner_time.position = UiArt.snap(Vector2(bw * 0.5 - _banner_time.texture.get_width() * 3 * 0.5, 11.0 * BANNER_BLOCK * BANNER_SCALE + 24.0), 3)
