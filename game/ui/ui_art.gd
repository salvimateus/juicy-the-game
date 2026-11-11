extends RefCounted

# Shared art and layout helpers of the menus: chunky logo letters drawn by EndingArt.title_glyph
# and outlined pixel-font text sprites, all at integer canvas scales.

const EndingArt := preload("res://game/ending/ending_art.gd")
const PixelFont := preload("res://game/interactables/pixel_font.gd")

# Chunky letters with 2-pixel strokes, 11 rows, matching the "FIM" of the ending.
const LOGO_GLYPHS := {
	"J": ["..######", "..######", "....##..", "....##..", "....##..", "....##..", "....##..", "....##..", "##..##..", "######..", ".####..."],
	"U": ["##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "##....##", "########", ".######."],
	"C": [".#######", "########", "##......", "##......", "##......", "##......", "##......", "##......", "##......", "########", ".#######"],
	"Y": ["##....##", "##....##", "##....##", "###..###", ".######.", "..####..", "...##...", "...##...", "...##...", "...##...", "...##..."],
	":": ["..", "..", "..", "##", "##", "..", "..", "..", "##", "##", ".."],
	"T": ["########", "########", "...##...", "...##...", "...##...", "...##...", "...##...", "...##...", "...##...", "...##...", "...##..."],
	"H": ["##....##", "##....##", "##....##", "##....##", "##....##", "########", "########", "##....##", "##....##", "##....##", "##....##"],
	"E": ["#######", "#######", "##.....", "##.....", "######.", "######.", "##.....", "##.....", "##.....", "#######", "#######"],
	"G": [".#######", "########", "##......", "##......", "##......", "##..####", "##..####", "##....##", "##....##", "########", ".######."],
	"A": [".######.", "########", "##....##", "##....##", "##....##", "########", "########", "##....##", "##....##", "##....##", "##....##"],
	"P": ["#######.", "########", "##....##", "##....##", "##....##", "########", "#######.", "##......", "##......", "##......", "##......"],
	"S": [".#######", "########", "##......", "##......", "#######.", ".#######", "......##", "......##", "......##", "########", "#######."],
}

const CREAM := [Color("#fff6dc"), Color("#e8d6a8"), Color("#d2b37a"), Color("#9c7444")]
const ORANGE := [Color("#ffd98a"), Color("#ffb03a"), Color("#f08a2a"), Color("#b8521a")]
const TEXT := Color("#e8d6a8")
const TEXT_SHADE := Color("#d2b37a")
const ACCENT := Color("#ffb03a")
const ACCENT_SHADE := Color("#e86a1e")
const MUTED := Color("#9a9090")
const MUTED_SHADE := Color("#6e6466")
const LINE := Color("#c8b48a")

# Font pixels between big letters and the width of a big space.
const BIG_GAP := 2
const BIG_SPACE := 9


# One sprite per big letter (null for spaces) and the word width in canvas units.
# {sprites: Array, offsets: PackedFloat32Array (x of each letter), width: float}
static func big_text(parent: Node, text: String, block: int, scale: int, colors: Array) -> Dictionary:
	var sprites: Array = []
	var offsets := PackedFloat32Array()
	var x := 0.0
	for i in text.length():
		var ch := text[i]
		if ch == " ":
			sprites.append(null)
			offsets.append(x)
			x += BIG_SPACE * block * scale
			continue
		var img := EndingArt.title_glyph(ch, block, LOGO_GLYPHS, PackedColorArray(colors))
		var s := Sprite2D.new()
		s.texture = ImageTexture.create_from_image(img)
		s.centered = false
		s.scale = Vector2(scale, scale)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		parent.add_child(s)
		sprites.append(s)
		# The glyph image has a 2-texel margin on the left (outline and shadow room).
		offsets.append(x - 2 * scale)
		x += (img.get_width() - 4) * scale
		if i < text.length() - 1 and text[i + 1] != " ":
			x += BIG_GAP * block * scale
	return {sprites = sprites, offsets = offsets, width = x}


# Outlined pixel-font text. Returns the sprite; char_x (prefix widths in texels) is in its meta.
static func text_sprite(parent: Node, text: String, scale: int, color: Color = TEXT, shade: Color = TEXT_SHADE) -> Sprite2D:
	var t := EndingArt.text_image(text, color, shade)
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(t.image)
	s.centered = false
	s.region_enabled = true
	s.region_rect = Rect2(Vector2.ZERO, (t.image as Image).get_size())
	s.scale = Vector2(scale, scale)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.set_meta(&"char_x", t.char_x)
	parent.add_child(s)
	return s


# Width in canvas units of a text sprite of `text` at `scale`.
static func text_width(text: String, scale: int) -> float:
	return float(PixelFont.measure(text) + 2) * scale


# Greedy word wrap by measured width (font pixels * scale), first line optionally narrower.
static func wrap(text: String, scale: int, width: float, first_width: float = -1.0) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	var limit := first_width if first_width > 0.0 else width
	for word in text.split(" "):
		var probe := word if line.is_empty() else line + " " + word
		if text_width(probe, scale) > limit and not line.is_empty():
			lines.append(line)
			line = word
			limit = width
		else:
			line = probe
	if not line.is_empty():
		lines.append(line)
	return lines


static func snap(v: Vector2, step: float) -> Vector2:
	return Vector2(roundf(v.x / step) * step, roundf(v.y / step) * step)
