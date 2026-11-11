extends RefCounted

# Procedural pixel art of the ending, one texel per art pixel, in the stone palette of PixelArt.
# Rocks are pre-rotated through PixelRotate, so a spinning rock swaps atlas regions (no mixels).

const PixelArt := preload("res://game/pixel_art.gd")
const PixelFont := preload("res://game/interactables/pixel_font.gd")
const PixelRotate := preload("res://game/targets/pixel_rotate.gd")

const WOOD := Color("#8a5a34")
const WOOD_LIGHT := Color("#b07a48")
const WOOD_DARK := Color("#5a3a22")
const INK := Color("#2a1a12")

const TITLE := Color("#e8d6a8")
const TITLE_LIGHT := Color("#fff6dc")
const TITLE_MID := Color("#d2b37a")
const TITLE_SHADE := Color("#9c7444")
const TITLE_SHADOW := Color("#4a3428")

const ROCK_ANGLES := 24
# Rock diameters in art pixels: large, medium, small.
const ROCK_SIZES := [34, 30, 27, 24, 21, 19, 17, 15, 13, 12, 11, 9, 8, 7, 6, 5]

# Chunky title letters (2-pixel strokes); other characters fall back to the pixel font.
const TITLE_GLYPHS := {
	"F": ["########", "########", "##......", "##......", "######..", "######..", "##......", "##......", "##......", "##......", "##......"],
	"I": ["######", "######", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "..##..", "######", "######"],
	"M": ["##......##", "###....###", "####..####", "##.####.##", "##..##..##", "##......##", "##......##", "##......##", "##......##", "##......##", "##......##"],
}

static var _rocks := {}
static var _rubble: ImageTexture


# Wooden sign: a board with engraved text on a single post. {image, board_h}
static func sign_image(lines: PackedStringArray, post_h: int) -> Dictionary:
	var tw := 0
	for l in lines:
		tw = maxi(tw, PixelFont.measure(l))
	var bw := tw + 10
	var bh := lines.size() * 7 + (lines.size() - 1) * 3 + 10
	var img := Image.create(bw, bh + post_h, false, Image.FORMAT_RGBA8)
	var px := bw / 2 - 2
	# Post.
	img.fill_rect(Rect2i(px, bh - 2, 4, post_h + 2), PixelArt.OUTLINE)
	img.fill_rect(Rect2i(px + 1, bh - 2, 1, post_h + 1), WOOD)
	img.fill_rect(Rect2i(px + 2, bh - 2, 1, post_h + 1), WOOD_DARK)
	for y in range(bh + 3, bh + post_h - 1, 5):
		img.set_pixel(px + 1, y, WOOD_DARK)
	# Board: outline, planks, grain, nails.
	img.fill_rect(Rect2i(0, 0, bw, bh), PixelArt.OUTLINE)
	img.fill_rect(Rect2i(1, 1, bw - 2, bh - 2), WOOD)
	img.fill_rect(Rect2i(1, 1, bw - 2, 1), WOOD_LIGHT)
	var plank := (bh - 2) / 2
	img.fill_rect(Rect2i(1, 1 + plank, bw - 2, 1), WOOD_DARK)
	img.fill_rect(Rect2i(1, 2 + plank, bw - 2, 1), WOOD_LIGHT)
	img.fill_rect(Rect2i(1, bh - 2, bw - 2, 1), WOOD_DARK)
	var h := 17
	for y in range(2, bh - 2):
		for x in range(2, bw - 2):
			h = (h * 1103515245 + 12345) & 0x7fffffff
			if h % 23 == 0 and img.get_pixel(x, y) == WOOD:
				img.set_pixel(x, y, WOOD_DARK)
	for p in [Vector2i(2, 2), Vector2i(bw - 3, 2), Vector2i(2, bh - 3), Vector2i(bw - 3, bh - 3)]:
		img.set_pixel(p.x, p.y, PixelArt.OUTLINE)
	# Engraved text: a light lip under dark ink.
	var y0 := 5
	for l in lines:
		var x0 := (bw - PixelFont.measure(l)) / 2
		PixelFont.draw(img, l, Vector2i(x0, y0 + 1), WOOD_LIGHT)
		PixelFont.draw(img, l, Vector2i(x0, y0), INK)
		y0 += 10
	return {image = img, board_h = bh}


# Cumulative crack overlays for the wall face, stage 0 (empty) to `stages`. The image bottom is
# the floor; `origin` is where the push cracks start (art px, image space).
static func crack_stages(w: int, h: int, origin: Vector2i, stages: int, seed: int) -> Array[ImageTexture]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var grid := PackedByteArray()
	grid.resize(w * h)
	var holes: Array[Vector2i] = []
	var hole_stage: Array[int] = []
	for s in range(1, stages + 1):
		var count: int = [0, 2, 2, 3, 4][mini(s, 4)]
		for i in count:
			var start := origin + Vector2i(0, rng.randi_range(-4 - s * 5, 4 + s * 5))
			if s >= 3 and i == count - 1:
				start = Vector2i(rng.randi_range(10, w - 10), h - 1)
			var ang := rng.randf_range(-0.9, 0.9)
			if start.y == h - 1:
				ang = rng.randf_range(-2.2, -0.9)
			var length: int = [0, 18, 32, 50, 75][mini(s, 4)] + rng.randi_range(-4, 10)
			_crack(grid, w, h, Vector2(start), ang, length, s, rng, 1)
			if s >= 3 and i < 2:
				holes.append(start + Vector2i(rng.randi_range(4, 14), rng.randi_range(-8, 8)))
				hole_stage.append(s)
	var out: Array[ImageTexture] = []
	for k in stages + 1:
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var g := grid[y * w + x]
				if g > 0 and g <= k:
					img.set_pixel(x, y, PixelArt.OUTLINE)
					if x + 1 < w and y + 1 < h and (grid[(y + 1) * w + x + 1] == 0 or grid[(y + 1) * w + x + 1] > k):
						img.set_pixel(x + 1, y + 1, PixelArt.STONE_LIGHT)
		for i in holes.size():
			if hole_stage[i] <= k:
				var p := holes[i]
				img.fill_rect(Rect2i(p.x, p.y, 3, 2).intersection(Rect2i(0, 0, w, h)), PixelArt.MORTAR)
				img.fill_rect(Rect2i(p.x, p.y + 2, 3, 1).intersection(Rect2i(0, 0, w, h)), PixelArt.STONE_LIGHT)
		out.append(ImageTexture.create_from_image(img))
	return out


static func _crack(grid: PackedByteArray, w: int, h: int, start: Vector2, ang: float, length: int,
		stage: int, rng: RandomNumberGenerator, depth: int) -> void:
	var p := start
	var a := ang
	var seg := 0
	for i in length:
		seg -= 1
		if seg <= 0:
			seg = rng.randi_range(3, 7)
			a = ang + rng.randf_range(-0.65, 0.65)
		p += Vector2(cos(a), sin(a))
		var q := Vector2i(roundi(p.x), roundi(p.y))
		if q.x < 1 or q.y < 1 or q.x >= w - 1 or q.y >= h - 1:
			return
		if grid[q.y * w + q.x] == 0:
			grid[q.y * w + q.x] = stage
		# Main cracks widen near their start in the later stages.
		if stage >= 4 and i < length / 4 and grid[q.y * w + q.x + 1] == 0:
			grid[q.y * w + q.x + 1] = stage
		if depth > 0 and rng.randf() < 0.06:
			_crack(grid, w, h, p, a + rng.randf_range(-1.2, 1.2), length / 3, stage, rng, depth - 1)


# Shared pre-rotated rock sheet. {texture, shapes: [{size, poly (art px around the pivot),
# rects, offsets}]}; frame i is angle i * TAU / ROCK_ANGLES.
static func rock_set() -> Dictionary:
	if not _rocks.is_empty():
		return _rocks
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var angles := PixelRotate.angle_range(0.0, TAU * (ROCK_ANGLES - 1) / ROCK_ANGLES, TAU / ROCK_ANGLES)
	var images: Array[Image] = []
	var shapes: Array = []
	for d in ROCK_SIZES:
		var rock := _rock_image(int(d), rng)
		var f := PixelRotate.frames(rock.image, rock.pivot, angles)
		var first := images.size()
		var imgs: Array[Image] = f.images
		images.append_array(imgs)
		shapes.append({size = int(d), poly = rock.poly, first = first, offsets = f.offsets})
	var packed := PixelRotate.pack(images)
	for s in shapes:
		var rects: Array[Rect2] = []
		for i in ROCK_ANGLES:
			rects.append(packed.rects[int(s.first) + i])
		s.rects = rects
	_rocks = {texture = packed.texture, shapes = shapes}
	return _rocks


static func _rock_image(d: int, rng: RandomNumberGenerator) -> Dictionary:
	var size := d + 2
	var c := Vector2(size / 2, size / 2)
	var n := rng.randi_range(6, 9)
	var squash := rng.randf_range(0.75, 1.0)
	var verts := PackedVector2Array()
	var base := rng.randf() * TAU
	for i in n:
		var t := base + TAU * i / n + rng.randf_range(-0.25, 0.25)
		var r := d * 0.5 * rng.randf_range(0.72, 1.0)
		verts.append(Vector2(cos(t) * r, sin(t) * r * squash))
	verts = Geometry2D.convex_hull(verts)
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var inside := PackedByteArray()
	inside.resize(size * size)
	var light_dir := Vector2(-0.6, -0.8)
	for y in size:
		for x in size:
			var q := Vector2(x + 0.5, y + 0.5) - c
			if Geometry2D.is_point_in_polygon(q, verts):
				inside[y * size + x] = 1
	for y in size:
		for x in size:
			if inside[y * size + x] == 0:
				continue
			var edge := x == 0 or y == 0 or x == size - 1 or y == size - 1 \
				or inside[y * size + x - 1] == 0 or inside[y * size + x + 1] == 0 \
				or inside[(y - 1) * size + x] == 0 or inside[(y + 1) * size + x] == 0
			if edge:
				img.set_pixel(x, y, PixelArt.OUTLINE)
				continue
			var q := (Vector2(x + 0.5, y + 0.5) - c) / (d * 0.5)
			var l := q.dot(light_dir)
			var col := PixelArt.STONE
			if l > 0.38:
				col = PixelArt.STONE_LIGHT
			elif l < -0.3:
				col = PixelArt.STONE_SHADE
			if d >= 9 and rng.randf() < 0.06:
				col = PixelArt.MORTAR if l < 0.2 else PixelArt.STONE_SHADE
			img.set_pixel(x, y, col)
	var hull := PackedVector2Array()
	for v in verts:
		hull.append(v * 0.92)
	return {image = img, pivot = c, poly = hull}


# Seamless tile of packed rubble: rocks of the shared sheet stamped with wrap-around over a dark
# bed, for the screen-filling pile.
static func rubble_tile() -> ImageTexture:
	if _rubble:
		return _rubble
	var size := 128
	var sheet := rock_set()
	var atlas: Image = (sheet.texture as Texture2D).get_image()
	var shapes: Array = sheet.shapes
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(PixelArt.MORTAR)
	for y in size:
		for x in size:
			if (x * 7 + y * 13) % 11 == 0:
				img.set_pixel(x, y, PixelArt.OUTLINE)
	for n in 420:
		var idx := rng.randi_range(4, shapes.size() - 1) if n > 70 else rng.randi_range(1, 7)
		var r: Rect2 = shapes[idx].rects[rng.randi_range(0, ROCK_ANGLES - 1)]
		var ox := rng.randi_range(0, size - 1)
		var oy := rng.randi_range(0, size - 1)
		var dark := rng.randf() < 0.35
		for yy in int(r.size.y):
			for xx in int(r.size.x):
				var c := atlas.get_pixel(int(r.position.x) + xx, int(r.position.y) + yy)
				if c.a <= 0.0:
					continue
				if dark:
					if c == PixelArt.STONE_LIGHT:
						c = PixelArt.STONE
					elif c == PixelArt.STONE:
						c = PixelArt.STONE_SHADE
				img.set_pixel((ox + xx) % size, (oy + yy) % size, c)
	_rubble = ImageTexture.create_from_image(img)
	return _rubble


# One big title glyph: every font pixel becomes a block x block cell, with a bevel, an outline
# and a drop shadow. The glyph's top-left cell sits at (2, 2).
# `glyphs` adds or overrides chunky letters ({char: rows}); `colors` is [light, base, lower, shade].
static func title_glyph(ch: String, block: int, glyphs: Dictionary = {}, colors: PackedColorArray = PackedColorArray()) -> Image:
	var g := PixelFont.glyph(ch)
	var rows := 7
	var pal := colors if colors.size() == 4 else PackedColorArray([TITLE_LIGHT, TITLE, TITLE_MID, TITLE_SHADE])
	var table: Dictionary = glyphs if glyphs.has(ch) else TITLE_GLYPHS
	if table.has(ch):
		var src: Array = table[ch]
		var px: Array[Vector2i] = []
		for y in src.size():
			for x in (src[y] as String).length():
				if (src[y] as String)[x] == "#":
					px.append(Vector2i(x, y))
		g = {width = (src[0] as String).length(), pixels = px}
		rows = src.size()
	var gw: int = int(g.width) * block
	var gh := rows * block
	var w := gw + 4
	var h := gh + 6
	var mask := PackedByteArray()
	mask.resize(w * h)
	for p in g.pixels:
		for yy in block:
			for xx in block:
				mask[(2 + p.y * block + yy) * w + 2 + p.x * block + xx] = 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				continue
			var near := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and mask[ny * w + nx] == 1:
						near = true
			if near:
				img.set_pixel(x, y, PixelArt.OUTLINE)
	# Drop shadow: the outlined shape pushed down, under it.
	for y in range(h - 1, -1, -1):
		for x in w:
			if mask[y * w + x] == 1 or img.get_pixel(x, y).a > 0.0:
				continue
			for sy in range(1, 3):
				if y - sy >= 0 and (mask[(y - sy) * w + x] == 1 or img.get_pixel(x, y - sy) == PixelArt.OUTLINE):
					img.set_pixel(x, y, TITLE_SHADOW)
					break
	for y in h:
		for x in w:
			if mask[y * w + x] == 0:
				continue
			var up := mask[(y - 1) * w + x] == 0
			var down := mask[(y + 1) * w + x] == 0
			var left := mask[y * w + x - 1] == 0
			var right := mask[y * w + x + 1] == 0
			var row := (y - 2) / block
			var col := pal[1] if row * 2 < rows + 1 else pal[2]
			if up or left:
				col = pal[0]
			elif down or right:
				col = pal[3]
			img.set_pixel(x, y, col)
	return img


# Text at one texel per font pixel with a 1-texel outline and a drop shadow.
# {image, char_x: right edge of each prefix, in texels}
static func text_image(text: String, color: Color, shade: Color) -> Dictionary:
	var top := PixelFont.top_row(text)
	var tw := PixelFont.measure(text)
	var w := tw + 2
	var th := PixelFont.LINE_BOTTOM - top + 1
	var h := th + 3
	var base := Image.create(w, h, false, Image.FORMAT_RGBA8)
	PixelFont.draw(base, text, Vector2i(1, 1 - top), Color.WHITE)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			if base.get_pixel(x, y).a > 0.0:
				continue
			var near := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and base.get_pixel(nx, ny).a > 0.0:
						near = true
			if near:
				img.set_pixel(x, y, PixelArt.OUTLINE)
			elif y >= 2 and base.get_pixel(x, y - 2).a > 0.0:
				img.set_pixel(x, y, TITLE_SHADOW)
	for y in h:
		for x in w:
			if base.get_pixel(x, y).a > 0.0:
				var low := y > 1 - top + 4
				img.set_pixel(x, y, shade if low else color)
	var char_x := PackedInt32Array()
	for i in text.length():
		char_x.append(PixelFont.measure(text.substr(0, i + 1)) + 2)
	return {image = img, char_x = char_x}
