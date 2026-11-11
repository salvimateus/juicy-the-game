extends RefCounted

# Procedural pixel art for the interactables, one texel per art pixel (sprites are scaled by
# ART_PIXEL). Wood follows pecas_extra/chair.png, metal and stone the level palette.
# Every texture is cached, so building scenes repeatedly is cheap.

const PixelFont := preload("res://game/interactables/pixel_font.gd")

const OUTLINE := Color("#141013")
const WOOD_DARK := Color("#3d2b2f")
const WOOD := Color("#5a3e3a")
const WOOD_MID := Color("#7d564a")
const WOOD_LIGHT := Color("#966856")
const METAL_DARK := Color("#2c2a34")
const METAL := Color("#4a4854")
const METAL_MID := Color("#6e6c7a")
const METAL_LIGHT := Color("#a4a2b0")
const ROPE := Color("#8a7450")
const ROPE_DARK := Color("#5e4c34")
const RED_DARK := Color("#6e1a20")
const RED := Color("#b02e34")
const RED_LIGHT := Color("#e0584c")
const PAD_YELLOW_DARK := Color("#7a5410")
const PAD_YELLOW := Color("#d8a020")
const PAD_YELLOW_LIGHT := Color("#f4cc50")
const KEY_FACE := Color("#d8d0c0")
const KEY_LIGHT := Color("#f0ead8")
const KEY_SIDE := Color("#8a8072")
const TIP_FILL := Color(0.106, 0.098, 0.141, 0.84)
const TIP_TEXT := Color("#f2e8d0")

static var _cache := {}


static func _img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	return img


static func _tex(key: String, img: Image) -> ImageTexture:
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


static func _hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(x, y, w, h), c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


# Adds a 1-texel dark outline around every opaque region (4-neighbour).
static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var marks: Array[Vector2i] = []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixel(q.x, q.y).a > 0.0:
					marks.append(Vector2i(x, y))
					break
	for m in marks:
		img.set_pixel(m.x, m.y, OUTLINE)


# Pixel line (Bresenham) of a given width going right/down from each point.
static func _line(img: Image, a: Vector2i, b: Vector2i, c: Color, width := 1) -> void:
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx + dy
	var p := a
	while true:
		for i in width:
			_px(img, p.x + i, p.y, c)
		if p == b:
			break
		var e2 := 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy


# --- Lever (damage trap) -------------------------------------------------------------------------

# 13 x 14 texels, pivot at (6, 10), bottom row on the floor.
static func lever(pulled: bool) -> ImageTexture:
	var key := "lever_%s" % pulled
	if _cache.has(key):
		return _cache[key]
	var img := _img(13, 14)
	var tip := Vector2i(10, 3) if pulled else Vector2i(2, 3)
	_line(img, Vector2i(6, 10), tip, WOOD_MID, 1)
	_line(img, Vector2i(6, 11), tip + Vector2i(0, 1), WOOD, 1)
	_rect(img, tip.x - 1, tip.y - 2, 3, 3, RED)
	_px(img, tip.x - 1, tip.y - 2, RED_LIGHT)
	_px(img, tip.x + 1, tip.y, RED_DARK)
	_rect(img, 2, 10, 9, 4, METAL)
	_rect(img, 2, 10, 9, 1, METAL_LIGHT)
	_rect(img, 4, 10, 5, 1, METAL_DARK)
	_px(img, 3, 12, METAL_MID)
	_px(img, 9, 12, METAL_MID)
	_outline(img)
	_rect(img, 1, 13, 11, 1, OUTLINE)
	return _tex(key, img)


# --- Swinging log (damage trap) ------------------------------------------------------------------

# Gallows: beam from x -16..112 at rows -126..-121 (art px, relative to the trap origin), post at
# x 100..105 down to the floor, diagonal brace. Top-left texel sits at GALLOWS_ORIGIN.
const GALLOWS_ORIGIN := Vector2i(-18, -128)
const GALLOWS_POST_X := 100


static func gallows() -> ImageTexture:
	if _cache.has("gallows"):
		return _cache["gallows"]
	var px := GALLOWS_POST_X
	var img := _img(px + 6 + 8 - GALLOWS_ORIGIN.x, 128)
	var o := -GALLOWS_ORIGIN
	_rect(img, o.x - 16, o.y - 126, px + 29, 6, WOOD)
	_rect(img, o.x - 16, o.y - 126, px + 29, 1, WOOD_LIGHT)
	_rect(img, o.x - 16, o.y - 121, px + 29, 1, WOOD_DARK)
	_rect(img, o.x + px, o.y - 121, 6, 121, WOOD)
	_rect(img, o.x + px, o.y - 121, 1, 121, WOOD_LIGHT)
	_rect(img, o.x + px + 5, o.y - 121, 1, 121, WOOD_DARK)
	_line(img, Vector2i(o.x + px - 1, o.y - 98), Vector2i(o.x + px - 23, o.y - 120), WOOD_MID, 3)
	for y in range(o.y - 120, o.y, 1):
		for x in range(o.x + px + 1, o.x + px + 5):
			if _hash(x, y) % 11 == 0:
				img.set_pixel(x, y, WOOD_DARK)
	# Iron rings where the ropes hang.
	for rx in [-15, 15]:
		_rect(img, o.x + rx - 1, o.y - 121, 3, 1, METAL_LIGHT)
	# Catch hook on the post that holds the raised log.
	_rect(img, o.x + px - 3, o.y - 96, 3, 2, METAL_MID)
	_outline(img)
	return _tex("gallows", img)


# Spiked log from art/spiked_log.png, drawn at double density: one texel is LOG_TEXEL units (half
# an art pixel), 152 x 56 texels. The log never rotates (two parallel ropes), so it stays on its
# grid. Offsets below are in log texels relative to the log centre.
const SPIKED_LOG := preload("res://game/interactables/art/spiked_log.png")
const LOG_TEXEL := 3
const LOG_ORIGIN := Vector2i(-76, -28)
# Rope lugs on top of the wooden body.
const LOG_ROPE_Y := -14
# Hit boxes [x, y, w, h], tips trimmed by about one texel: body plus the end spikes, and the band of
# top and bottom spikes over the middle; the gaps between spikes stay out.
const LOG_HIT_BOXES := [[-70, -14, 140, 30], [-52, -24, 103, 48]]


# --- Turret --------------------------------------------------------------------------------------

# Pedestal plus dome, 18 x 23 texels, bottom row on the floor. Pivot at TURRET_PIVOT (art px,
# relative to the turret origin on the floor).
const TURRET_BASE_ORIGIN := Vector2i(-9, -23)
const TURRET_PIVOT := Vector2i(0, -19)


static func turret_base() -> ImageTexture:
	if _cache.has("turret_base"):
		return _cache["turret_base"]
	var img := _img(18, 23)
	# Pedestal.
	_rect(img, 2, 7, 14, 15, METAL)
	_rect(img, 2, 7, 14, 1, METAL_LIGHT)
	_rect(img, 2, 7, 1, 15, METAL_MID)
	_rect(img, 15, 7, 1, 15, METAL_DARK)
	_rect(img, 2, 19, 14, 3, METAL_DARK)
	_rect(img, 1, 19, 16, 1, METAL_MID)
	for r in [Vector2i(4, 9), Vector2i(13, 9), Vector2i(4, 17), Vector2i(13, 17)]:
		_px(img, r.x, r.y, METAL_LIGHT)
	# Hazard stripes.
	for x in range(3, 15):
		_px(img, x, 13, PAD_YELLOW if (x / 2) % 2 == 0 else OUTLINE)
		_px(img, x, 14, PAD_YELLOW if ((x + 1) / 2) % 2 == 0 else OUTLINE)
	# Dome.
	_rect(img, 5, 2, 8, 5, METAL_MID)
	_rect(img, 4, 4, 10, 3, METAL_MID)
	_rect(img, 6, 2, 3, 1, METAL_LIGHT)
	_rect(img, 5, 3, 1, 2, METAL_LIGHT)
	_outline(img)
	_rect(img, 0, 22, 18, 1, OUTLINE)
	return _tex("turret_base", img)


# Barrel pointing +x, 18 x 7 texels, pivot at (3, 3), muzzle at (17, 3).
const BARREL_PIVOT := Vector2i(3, 3)
const BARREL_MUZZLE := Vector2i(17, 3)


static func turret_barrel() -> ImageTexture:
	if _cache.has("turret_barrel"):
		return _cache["turret_barrel"]
	var img := _img(18, 7)
	_rect(img, 1, 1, 6, 5, METAL)
	_rect(img, 1, 1, 6, 1, METAL_LIGHT)
	_rect(img, 7, 2, 9, 3, METAL_MID)
	_rect(img, 7, 2, 9, 1, METAL_LIGHT)
	_rect(img, 7, 4, 9, 1, METAL_DARK)
	_rect(img, 14, 1, 2, 5, METAL)
	_px(img, 3, 3, METAL_DARK)
	_outline(img)
	return _tex("turret_barrel", img)


# Warning light, 6 x 5 texels, white so it can be tinted with modulate.
static func light_bulb() -> ImageTexture:
	if _cache.has("bulb"):
		return _cache["bulb"]
	var img := _img(6, 5)
	_rect(img, 1, 1, 4, 3, Color(0.8, 0.8, 0.8))
	_rect(img, 2, 0, 2, 1, Color(0.8, 0.8, 0.8))
	_px(img, 2, 1, Color.WHITE)
	_px(img, 1, 1, Color.WHITE)
	_outline(img)
	_rect(img, 0, 4, 6, 1, OUTLINE)
	return _tex("bulb", img)


# --- Push button on a post (reset button, turret trigger) ---------------------------------------

# 14 x 31 texels, bottom row on the floor; the cap sits on rows 1..3 (1 row when pressed).
static func push_button(pressed: bool) -> ImageTexture:
	var key := "button_%s" % pressed
	if _cache.has(key):
		return _cache[key]
	var img := _img(14, 31)
	# Post.
	_rect(img, 4, 7, 6, 23, METAL)
	_rect(img, 4, 7, 1, 23, METAL_MID)
	_rect(img, 9, 7, 1, 23, METAL_DARK)
	_rect(img, 2, 27, 10, 3, METAL_DARK)
	_rect(img, 2, 27, 10, 1, METAL_MID)
	# Head plate.
	_rect(img, 1, 4, 12, 3, METAL_MID)
	_rect(img, 1, 4, 12, 1, METAL_LIGHT)
	_rect(img, 1, 6, 12, 1, METAL_DARK)
	# Cap.
	if pressed:
		_rect(img, 3, 3, 8, 1, RED)
		_rect(img, 4, 3, 2, 1, RED_LIGHT)
	else:
		_rect(img, 3, 1, 8, 3, RED)
		_rect(img, 3, 3, 8, 1, RED_DARK)
		_rect(img, 4, 1, 3, 1, RED_LIGHT)
	_outline(img)
	_rect(img, 1, 30, 12, 1, OUTLINE)
	return _tex(key, img)


# --- Prompt icons --------------------------------------------------------------------------------

const ICON_SIZE := 11


# Xbox Y: yellow disc with a dark Y.
static func draw_pad_y(img: Image, at: Vector2i) -> void:
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var d := Vector2(x - 5, y - 5).length()
			if d > 5.6:
				continue
			var c := PAD_YELLOW
			if d > 4.6:
				c = OUTLINE
			elif y >= 7 and d > 3.4:
				c = PAD_YELLOW_DARK
			elif y <= 3 and x <= 5 and d > 3.0:
				c = PAD_YELLOW_LIGHT
			_px(img, at.x + x, at.y + y, c)
	PixelFont.draw(img, "Y", at + Vector2i(3, 2), OUTLINE)


# Keyboard key with a letter, face on rows 1..7 and the key side below.
static func draw_key(img: Image, at: Vector2i, letter: String) -> void:
	var s := ICON_SIZE
	_rect(img, at.x, at.y, s, s, OUTLINE)
	_rect(img, at.x + 1, at.y + 1, s - 2, s - 2, KEY_SIDE)
	_rect(img, at.x + 1, at.y + 1, s - 2, s - 4, KEY_FACE)
	_rect(img, at.x + 1, at.y + 1, s - 2, 1, KEY_LIGHT)
	for c in [Vector2i(0, 0), Vector2i(s - 1, 0), Vector2i(0, s - 1), Vector2i(s - 1, s - 1)]:
		_px(img, at.x + c.x, at.y + c.y, Color.TRANSPARENT)
	var w := PixelFont.measure(letter)
	PixelFont.draw(img, letter, at + Vector2i((s - w) / 2, 1), OUTLINE)


# --- Prompt box ----------------------------------------------------------------------------------

const TIP_PAD := 2
const TIP_GAP := 3
const TIP_TAIL := 2


# Box with stepped corners, icon and text, plus a tail at the bottom centre.
# Returns {texture, tip: Vector2i} where tip is the texel of the tail point.
static func prompt_box(text: String, gamepad: bool, key_letter := "E") -> Dictionary:
	var key := "tip_%s_%s_%s" % [text, gamepad, key_letter]
	if _cache.has(key):
		return _cache[key]
	var text_w := PixelFont.measure(text)
	# Text row 0 (cap top) aligns with icon row 1; capital accents may need extra rows above.
	var extra := maxi(0, -PixelFont.top_row(text) - 1)
	var content_h := ICON_SIZE + extra
	var w := 1 + TIP_PAD + ICON_SIZE + TIP_GAP + text_w + TIP_PAD + 1
	var h := 1 + TIP_PAD + content_h + TIP_PAD + 1
	var img := _img(w, h + TIP_TAIL)
	_rect(img, 1, 1, w - 2, h - 2, TIP_FILL)
	# Border with stepped corners.
	_rect(img, 2, 0, w - 4, 1, OUTLINE)
	_rect(img, 2, h - 1, w - 4, 1, OUTLINE)
	_rect(img, 0, 2, 1, h - 4, OUTLINE)
	_rect(img, w - 1, 2, 1, h - 4, OUTLINE)
	for c in [Vector2i(1, 1), Vector2i(w - 2, 1), Vector2i(1, h - 2), Vector2i(w - 2, h - 2)]:
		_px(img, c.x, c.y, OUTLINE)
	# Tail.
	var cx := w / 2
	_px(img, cx, h - 1, TIP_FILL)
	_px(img, cx - 1, h, OUTLINE)
	_px(img, cx, h, TIP_FILL)
	_px(img, cx + 1, h, OUTLINE)
	_px(img, cx, h + 1, OUTLINE)
	var top := 1 + TIP_PAD + extra
	var icon_at := Vector2i(1 + TIP_PAD, top)
	if gamepad:
		draw_pad_y(img, icon_at)
	else:
		draw_key(img, icon_at, key_letter)
	PixelFont.draw(img, text, Vector2i(icon_at.x + ICON_SIZE + TIP_GAP, top + 1), TIP_TEXT)
	var result := {texture = ImageTexture.create_from_image(img), tip = Vector2i(cx, h + 1)}
	_cache[key] = result
	return result


# --- Reward flag ---------------------------------------------------------------------------------

const FLAG_FRAMES := 6
const FLAG_SIZE := Vector2i(24, 17)
# Pole texture: 6 x 54 texels, bottom row on the floor; the pole axis is column 2-3.
const POLE_SIZE := Vector2i(6, 54)
const POLE_ORIGIN := Vector2i(-3, -54)
const GOLD := Color("#e8b030")
const GOLD_LIGHT := Color("#fbe07a")
const GOLD_DARK := Color("#9a6a18")
const CLOTH_RED := [Color("#6e1a22"), Color("#a82a30"), Color("#d84a3c"), Color("#f07a5c")]
const CLOTH_PALE := [Color("#7a7262"), Color("#a89e88"), Color("#d2c8b0"), Color("#ece4d0")]


static func flag_pole() -> ImageTexture:
	if _cache.has("flag_pole"):
		return _cache["flag_pole"]
	var img := _img(POLE_SIZE.x, POLE_SIZE.y)
	# Shaft.
	_rect(img, 2, 4, 2, 47, WOOD)
	_rect(img, 2, 4, 1, 47, WOOD_LIGHT)
	for y in range(6, 50, 7):
		_px(img, 3, y, WOOD_DARK)
	# Gold finial.
	_rect(img, 2, 1, 2, 2, GOLD)
	_px(img, 2, 1, GOLD_LIGHT)
	_px(img, 3, 2, GOLD_DARK)
	_rect(img, 1, 3, 4, 1, GOLD_DARK)
	# Foot block.
	_rect(img, 1, 50, 4, 3, METAL)
	_rect(img, 1, 50, 4, 1, METAL_LIGHT)
	_outline(img)
	_rect(img, 0, 53, 6, 1, OUTLINE)
	return _tex("flag_pole", img)


# One frame of the waving cloth, hoist on the left (x 0). The wave travels to the fly end: each
# column is shifted by a sine that grows towards the tip, faces turned to the light are lighter,
# and the fly end has a swallowtail notch that opens and closes with the wave.
static func flag_frame(frame: int, captured: bool) -> ImageTexture:
	var key := "flag_%d_%s" % [frame, captured]
	if _cache.has(key):
		return _cache[key]
	var cloth: Array = CLOTH_RED if captured else CLOTH_PALE
	var w := FLAG_SIZE.x - 2
	var h := 12
	var img := _img(FLAG_SIZE.x, FLAG_SIZE.y)
	var phase := TAU * float(frame) / FLAG_FRAMES
	var prev := 0
	for x in w:
		var k := float(x) / float(w - 1)
		var dy := roundi(sin(phase - x * 0.45) * 2.0 * k)
		var slope := dy - prev
		prev = dy
		var col_h := h - (1 if x >= w - 3 and frame % 3 == 0 else 0)
		for y in col_h:
			var c: Color = cloth[1]
			if y == 0:
				c = cloth[3] if slope <= 0 else cloth[2]
			elif y == col_h - 1:
				c = cloth[0]
			elif slope < 0:
				c = cloth[2]
			elif slope > 0:
				c = cloth[0] if y > col_h / 2 else cloth[1]
			_px(img, x + 1, y + 2 + dy, c)
		# Swallowtail notch at the fly end.
		if x >= w - 3:
			var notch := x - (w - 4)
			for y in range(h / 2 - notch, h / 2 + notch):
				_px(img, x + 1, y + 2 + dy, Color.TRANSPARENT)
	if captured:
		# Gold star near the hoist, following the cloth.
		var sx := 7
		var sy := 2 + roundi(sin(phase - (sx - 1) * 0.45) * 2.0 * float(sx - 1) / float(w - 1)) + 3
		_px(img, sx, sy, GOLD_LIGHT)
		_rect(img, sx - 2, sy + 1, 5, 1, GOLD)
		_px(img, sx, sy + 1, GOLD_LIGHT)
		_rect(img, sx - 1, sy + 2, 3, 1, GOLD)
		_px(img, sx - 1, sy + 3, GOLD_DARK)
		_px(img, sx + 1, sy + 3, GOLD_DARK)
	_outline(img)
	return _tex(key, img)


# Pixel text with a 1-texel dark outline and a drop shadow; returns {texture, size}.
static func outlined_text(text: String, color: Color) -> Dictionary:
	var key := "text_%s_%s" % [text, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var top := PixelFont.top_row(text)
	var w := PixelFont.measure(text) + 4
	var h := PixelFont.LINE_BOTTOM - top + 5
	var img := _img(w, h)
	PixelFont.draw(img, text, Vector2i(2, 3 - top), OUTLINE)
	PixelFont.draw(img, text, Vector2i(2, 2 - top), color)
	_outline(img)
	var result := {texture = ImageTexture.create_from_image(img), size = Vector2i(w, h)}
	_cache[key] = result
	return result
