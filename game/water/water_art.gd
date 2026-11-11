extends RefCounted

# Procedural pixel art for the river scene, one texel per art pixel (drawn scaled by ART_PIXEL).
# Palette builds on res://game/pixel_art.gd so banks and stone match the level.

const PixelArt := preload("res://game/pixel_art.gd")

const BACKDROP := Color("#2a2228")
const BACKDROP_DARK := Color("#221b21")
const BACKDROP_LIGHT := Color("#33292f")
const MUD := Color("#4a3a32")
const MUD_DARK := Color("#3a2d28")
const SAND := Color("#8a7458")
const SAND_DARK := Color("#6e5c48")
const MOSS := Color("#3f6a3a")
const MOSS_DARK := Color("#2c4c30")
const KELP_DARK := Color("#2f6a48")
const KELP := Color("#4a9058")
const KELP_LIGHT := Color("#7cc070")
const CRYSTAL := Color("#7fe0e8")
const CRYSTAL_LIGHT := Color("#d8fbff")
const CRYSTAL_DARK := Color("#3a8ea8")

static var _cache := {}


static func _hash(x: int, y: int) -> int:
	return PixelArt._hash(x, y)


# Terrain for every segment [x0, x1, top, kind] (units) over [x_min, x_max), from y_min down to
# y_max, as [solid, backdrop]. The solid layer holds only the earth mass (drawn in front of the
# character so nothing pokes through it); below ground level (y = 0) the open air goes to the
# backdrop layer, a dark wall behind everything, so cuts read as depressions.
static func terrain(segments: Array, x_min: float, x_max: float, y_min: float, y_max: float, a: int) -> Array[ImageTexture]:
	var w := int((x_max - x_min) / a)
	var h := int((y_max - y_min) / a)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var back := Image.create(w, h, false, Image.FORMAT_RGBA8)
	back.fill(Color.TRANSPARENT)
	var ground_row := int((0.0 - y_min) / a)
	for seg in segments:
		var px0 := int((seg[0] - x_min) / a)
		var px1 := int((seg[1] - x_min) / a)
		var top := int((seg[2] - y_min) / a)
		var kind: StringName = seg[3]
		var fill_top := top
		if kind == &"dam":
			fill_top = int((seg[4] - y_min) / a)
		# Backdrop between ground level and the top of the segment.
		if fill_top > ground_row:
			back.fill_rect(Rect2i(px0, ground_row, px1 - px0, fill_top - ground_row), BACKDROP)
		img.fill_rect(Rect2i(px0, fill_top, px1 - px0, h - fill_top), PixelArt.DIRT_DARK)
		for x in range(px0, px1):
			match kind:
				&"grass":
					_grass_top(img, x, top)
				&"bed", &"valley":
					_bed_top(img, x, top, kind == &"valley")
				&"dam":
					pass
			_dirt_speckle(img, x, fill_top + 3, h)
	_backdrop_detail(back, ground_row)
	# Side faces of each step: a darker rim where a segment rises above its neighbour.
	for i in segments.size():
		var seg: Array = segments[i]
		for nb in [i - 1, i + 1]:
			if nb < 0 or nb >= segments.size():
				continue
			var other: Array = segments[nb]
			if other[3] == &"dam" or seg[3] == &"dam" or other[2] <= seg[2]:
				continue
			var x := int((seg[0] - x_min) / a) if nb == i - 1 else int((seg[1] - x_min) / a) - 1
			var y0 := int((seg[2] - y_min) / a)
			var y1 := int((other[2] - y_min) / a)
			for y in range(y0 + 2, y1):
				img.set_pixel(x, y, PixelArt.OUTLINE if _hash(x, y) % 4 == 0 else MUD_DARK)
	return [ImageTexture.create_from_image(img), ImageTexture.create_from_image(back)]


static func _grass_top(img: Image, x: int, top: int) -> void:
	var r := _hash(x, 11)
	if r % 3 == 0 and top > 0:
		img.set_pixel(x, top - 1, PixelArt.GRASS)
	img.set_pixel(x, top, PixelArt.GRASS_LIGHT if r % 5 != 0 else PixelArt.GRASS)
	img.set_pixel(x, top + 1, PixelArt.GRASS if r % 4 != 1 else PixelArt.GRASS_LIGHT)
	img.set_pixel(x, top + 2, PixelArt.GRASS_DARK)
	img.set_pixel(x, top + 3, PixelArt.DIRT if r % 3 != 0 else PixelArt.GRASS_DARK)


static func _bed_top(img: Image, x: int, top: int, valley: bool) -> void:
	var r := _hash(x, 23)
	img.set_pixel(x, top, SAND if r % 3 != 0 else SAND_DARK)
	img.set_pixel(x, top + 1, SAND_DARK if r % 4 != 0 else MUD)
	img.set_pixel(x, top + 2, MUD)
	img.set_pixel(x, top + 3, MUD if r % 2 == 0 else MUD_DARK)
	if valley and r % 5 == 0:
		img.set_pixel(x, top, PixelArt.GRASS_DARK)
	if r % 7 == 0:
		img.set_pixel(x, top + 1, PixelArt.PEBBLE)


static func _dirt_speckle(img: Image, x: int, y0: int, y1: int) -> void:
	for y in range(y0, mini(y1, y0 + 120), 1):
		var r := _hash(x, y)
		if r % 37 == 0:
			img.set_pixel(x, y, PixelArt.PEBBLE)
		elif r % 23 == 0:
			img.set_pixel(x, y, MUD_DARK)


static func _backdrop_detail(img: Image, ground_row: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(ground_row, mini(h, ground_row + 160)):
		for x in w:
			if img.get_pixel(x, y) != BACKDROP:
				continue
			var depth := y - ground_row
			var r := _hash(x, y)
			# Strata every few rows and sparse speckles, darker with depth.
			if posmod(y + (x / 17) % 3, 9) == 0 and r % 3 != 0:
				img.set_pixel(x, y, BACKDROP_DARK)
			elif r % 41 == 0:
				img.set_pixel(x, y, BACKDROP_LIGHT)
			elif depth > 40 and r % 5 == 0:
				img.set_pixel(x, y, BACKDROP_DARK)
	# Top lip of the cut: a row of grass roots hanging over the backdrop.
	for x in w:
		if ground_row < h and img.get_pixel(x, ground_row) == BACKDROP:
			if _hash(x, 3) % 3 == 0:
				img.set_pixel(x, ground_row, PixelArt.GRASS_DARK)


# Dam of bricks w x h art px. notch = [width, depth] of the low step on the left top corner.
# With hole = Rect2i (art px), the hole is open with a ragged rim and a dark inner wall.
static func dam(w: int, h: int, notch: Vector2i, waterline: int, hole := Rect2i()) -> ImageTexture:
	var key := "dam_%d_%d_%s_%s" % [w, h, notch, hole]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in h:
		for x in w:
			if x < notch.x and y < notch.y:
				continue
			var c := PixelArt._brick_color(x, y)
			# Moss and wet stains below the river's waterline on the river face.
			if y >= waterline and x < 4 and _hash(x, y) % 3 != 0:
				c = MOSS_DARK
			elif y >= waterline - 1 and y <= waterline + 1 and x < 8 and _hash(x, y) % 2 == 0:
				c = MOSS
			img.set_pixel(x, y, c)
	for y in h:
		img.set_pixel(w - 1, y, PixelArt.OUTLINE)
		if not (y < notch.y):
			img.set_pixel(0, y, PixelArt.OUTLINE)
	for x in w:
		img.set_pixel(x, notch.y if x < notch.x else 0, PixelArt.STONE_LIGHT)
	for y in notch.y:
		img.set_pixel(notch.x, y, PixelArt.OUTLINE)
	if hole.has_area():
		for y in range(hole.position.y - 2, hole.end.y + 2):
			for x in range(hole.position.x, hole.end.x):
				if y < 0 or y >= h:
					continue
				var inside := hole.has_point(Vector2i(x, y))
				var r := _hash(x * 3, y * 5)
				if inside:
					img.set_pixel(x, y, Color.TRANSPARENT)
				elif r % 3 == 0:
					# Ragged rim: chipped bricks just outside the opening.
					img.set_pixel(x, y, PixelArt.MORTAR if r % 2 == 0 else PixelArt.STONE_SHADE)
		for y in range(hole.position.y, hole.end.y):
			img.set_pixel(0, y, Color.TRANSPARENT)
			img.set_pixel(w - 1, y, Color.TRANSPARENT)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# Inner wall of the broken dam's tunnel (w x h art px), drawn behind the character.
static func dam_hole(w: int, h: int) -> ImageTexture:
	var key := "dam_hole_%d_%d" % [w, h]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := mini(y, h - 1 - y)
			var c := Color("#1c161b") if d > 2 else Color("#2c242a")
			if d == 0 and _hash(x * 3, y * 5) % 2 == 0:
				c = PixelArt.STONE_SHADE
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# Kelp strand h art px tall; frame 0/1 sway the upper half one pixel to each side.
static func kelp(h: int, frame: int, seed: int) -> ImageTexture:
	var key := "kelp_%d_%d_%d" % [h, frame, seed]
	if _cache.has(key):
		return _cache[key]
	var w := 7
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in h:
		var up := h - 1 - y
		var bend := int(round(sin(up * 0.45 + seed) * 1.2))
		if up > h / 2:
			bend += 1 if frame == 0 else -1
		var x := 3 + bend
		img.set_pixel(x, y, KELP)
		img.set_pixel(clampi(x + 1, 0, w - 1), y, KELP_DARK)
		if (up + seed) % 4 == 0 and up > 1:
			var side := 1 if (up / 4 + seed) % 2 == 0 else -1
			img.set_pixel(clampi(x + side, 0, w - 1), y, KELP_LIGHT)
			img.set_pixel(clampi(x + side * 2, 0, w - 1), y, KELP)
			if y + 1 < h:
				img.set_pixel(clampi(x + side * 2, 0, w - 1), y + 1, KELP_DARK)
	img.set_pixel(3, 0, KELP_LIGHT)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# Round boulder w x h art px with a light top-left and an outline.
static func rock(w: int, h: int, seed: int) -> ImageTexture:
	var key := "rock_%d_%d_%d" % [w, h, seed]
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var cx := (w - 1) * 0.5
	var cy := float(h)
	for y in h:
		for x in w:
			var dx := (x - cx) / (w * 0.5)
			var dy := (y - cy) / float(h)
			if dx * dx + dy * dy > 1.0:
				continue
			var c := PixelArt.STONE
			if dx + dy < -0.85:
				c = PixelArt.STONE_LIGHT
			elif dx - dy * 0.4 > 0.45:
				c = PixelArt.STONE_SHADE
			if _hash(x + seed * 13, y) % 9 == 0:
				c = PixelArt.STONE_SHADE
			if y >= h - 2 and _hash(x, seed) % 2 == 0:
				c = MOSS_DARK
			img.set_pixel(x, y, c)
	_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


# Glowing crystal cluster, worth the dive to the trench.
static func crystals() -> ImageTexture:
	if _cache.has("crystals"):
		return _cache["crystals"]
	var img := Image.create(13, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var spikes := [[2, 6, 2], [5, 11, 2], [8, 8, 2], [11, 5, 1]]
	for s in spikes:
		var x0: int = s[0]
		var tall: int = s[1]
		var half: int = s[2]
		for y in tall:
			var row := 11 - y
			var wd := half if y < tall - 2 else maxi(0, half - 1)
			for x in range(x0 - wd, x0 + wd + 1):
				var c := CRYSTAL
				if x < x0:
					c = CRYSTAL_LIGHT
				elif x > x0:
					c = CRYSTAL_DARK
				img.set_pixel(clampi(x, 0, 12), row, c)
	_outline(img)
	var tex := ImageTexture.create_from_image(img)
	_cache["crystals"] = tex
	return tex


static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.0 and src.get_pixel(nx, ny) != PixelArt.OUTLINE:
					img.set_pixel(x, y, PixelArt.OUTLINE)
					break
