extends RefCounted

# Procedural pixel art, one texel per art pixel (sprites are scaled by ART_PIXEL).
# Palettes follow the JS renderer (ground, hills) and pecas_extra/ledge.png (stone).

const SKY := Color("#20202c")
const HILL_FAR := Color("#2b2b40")
const HILL_NEAR := Color("#232a2c")
const HILL_NEAR_CAP := Color("#2e3a34")

const GROUND_TOP := Color("#4f6b3a")
const GROUND_TOP_LIGHT := Color("#6f8f4a")
const DIRT := Color("#5a4030")
const DIRT_DARK := Color("#463126")
const PEBBLE := Color("#7a6250")

const STONE := Color("#6e5c5c")
const STONE_LIGHT := Color("#967e79")
const STONE_SHADE := Color("#483c40")
const MORTAR := Color("#2c242a")
const OUTLINE := Color("#141013")
const GRASS_LIGHT := Color("#6e9448")
const GRASS := Color("#4e763a")
const GRASS_DARK := Color("#34502e")

const GROUND_TILE_W := 8
const GROUND_TILE_H := 12
# Rows of grass drawn above the walkable surface of a stone block (tufts).
const STONE_TUFT_ROWS := 1


static func _tex(image: Image) -> ImageTexture:
	return ImageTexture.create_from_image(image)


static func _hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


static func ground_tile() -> ImageTexture:
	var img := Image.create(GROUND_TILE_W, GROUND_TILE_H, false, Image.FORMAT_RGBA8)
	img.fill(DIRT)
	img.fill_rect(Rect2i(0, 0, 8, 1), GROUND_TOP_LIGHT)
	img.fill_rect(Rect2i(0, 1, 8, 1), GROUND_TOP)
	img.set_pixel(1, 1, GROUND_TOP_LIGHT)
	img.set_pixel(5, 1, GROUND_TOP_LIGHT)
	img.set_pixel(3, 2, GROUND_TOP)
	img.set_pixel(6, 2, GROUND_TOP)
	img.fill_rect(Rect2i(2, 5, 2, 1), DIRT_DARK)
	img.set_pixel(6, 8, DIRT_DARK)
	img.set_pixel(0, 10, DIRT_DARK)
	img.set_pixel(5, 4, PEBBLE)
	img.set_pixel(1, 8, PEBBLE)
	img.set_pixel(4, 9, PEBBLE)
	return _tex(img)


# Seamless hill silhouette (sum of integer-period sines), heights in art pixels.
static func hill_tile(width: int, height: int, base: float, amps: Array, color: Color, cap := Color.TRANSPARENT) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for x in width:
		var h := base
		for i in amps.size():
			h += amps[i] * sin(TAU * (i + 1) * x / width + i * 1.7)
		var top := clampi(roundi(height - h), 0, height - 1)
		img.fill_rect(Rect2i(x, top, 1, height - top), color)
		if cap.a > 0.0:
			img.set_pixel(x, top, cap)
	return _tex(img)


# Stone block like pecas_extra/ledge.png: bricks 10x5 with mortar, grass on top, dark outline.
static func stone_block(width: int, height: int, grass := true, outline_bottom := true, grooved := false) -> ImageTexture:
	var tuft := STONE_TUFT_ROWS if grass else 0
	var img := Image.create(width, height + tuft, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in height:
		for x in width:
			img.set_pixel(x, y + tuft, _groove_color(x, y) if grooved else _brick_color(x, y))
	if grass:
		for x in width:
			var r := _hash(x, 7)
			if r % 3 == 0 and x > 0 and x < width - 1:
				img.set_pixel(x, 0, OUTLINE)
			img.set_pixel(x, tuft, OUTLINE if r % 5 == 0 else GRASS_LIGHT)
			img.set_pixel(x, tuft + 1, GRASS if r % 4 == 1 else GRASS_LIGHT)
			img.set_pixel(x, tuft + 2, GRASS_LIGHT if r % 6 == 2 else GRASS)
			img.set_pixel(x, tuft + 3, GRASS_DARK)
	for y in range(tuft, height + tuft):
		img.set_pixel(0, y, OUTLINE)
		img.set_pixel(width - 1, y, OUTLINE)
	if outline_bottom:
		img.fill_rect(Rect2i(0, height + tuft - 1, width, 1), OUTLINE)
	return _tex(img)


static func _brick_color(x: int, y: int) -> Color:
	var row := y / 6
	var ry := y % 6
	if ry == 5:
		return MORTAR
	var bx := posmod(x + (5 if row % 2 == 1 else 0) + 3, 10)
	if bx == 9:
		return MORTAR
	if ry == 4 or bx == 8:
		return STONE_SHADE
	if ry == 0 or bx == 0:
		return STONE_LIGHT
	return STONE_SHADE if _hash(x, y) % 11 == 0 else STONE


# Climbable stone: tall slabs split by vertical grooves (handholds), with notches every few rows.
static func _groove_color(x: int, y: int) -> Color:
	var gx := posmod(x - 2, 7)
	if gx == 0:
		return MORTAR if posmod(y, 4) != 3 else STONE_SHADE
	if gx == 1:
		return STONE_LIGHT
	if gx == 6:
		return STONE_SHADE
	if posmod(y + x / 7 * 5, 16) == 0:
		return MORTAR
	return STONE_SHADE if _hash(x, y) % 9 == 0 else STONE


const STEEL := Color("#5f6d7a")
const STEEL_LIGHT := Color("#8fa0ae")
const STEEL_SHINE := Color("#d2dde5")
const STEEL_SHADE := Color("#434d59")
const STEEL_DARK := Color("#2a3039")
const RUST := Color("#7a4a32")
# Rows per riveted panel of a steel plate.
const STEEL_PANEL := 40


# Riveted steel plate: bevelled rim, panels split by seams, rivets along the seams, a brushed
# highlight band, a few dings and rust tears under some rivets.
static func steel_plate(width: int, height: int) -> ImageTexture:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var band := maxi(2, width / 4)
	for y in height:
		for x in width:
			var c := STEEL
			var h := _hash(x, y)
			if x >= band and x < band + 2 and h % 7 != 0:
				c = STEEL_LIGHT
			elif x == band + 2 and h % 3 == 0:
				c = STEEL_LIGHT
			elif h % 13 == 0:
				c = STEEL_SHADE
			var py := y % STEEL_PANEL
			if y > 0 and py == STEEL_PANEL - 1:
				c = STEEL_DARK
			elif y > 0 and py == 0:
				c = STEEL_LIGHT
			img.set_pixel(x, y, c)
	# Dings: a dark pit with a bright rim above-left.
	for i in maxi(1, height * width / 220):
		var dx := 3 + _hash(i, 91) % maxi(1, width - 6)
		var dy := 3 + _hash(i, 57) % maxi(1, height - 6)
		img.set_pixel(dx, dy, STEEL_DARK)
		img.set_pixel(dx - 1, dy - 1, STEEL_SHINE)
		img.set_pixel(dx + 1, dy, STEEL_SHADE)
	var cols := [3, width - 5]
	if width >= 20:
		cols.append(width / 2 - 1)
	var y0 := 3
	while y0 < height - 4:
		for cx in cols:
			_rivet(img, cx, y0)
			if _hash(cx, y0) % 3 == 0:
				for k in 1 + _hash(y0, cx) % 3:
					if y0 + 2 + k < height - 2:
						img.set_pixel(cx, y0 + 2 + k, RUST)
		var py := y0 % STEEL_PANEL
		y0 += STEEL_PANEL - 7 if py < STEEL_PANEL / 2 else 7
	for y in height:
		img.set_pixel(0, y, OUTLINE)
		img.set_pixel(width - 1, y, OUTLINE)
		img.set_pixel(1, y, STEEL_LIGHT)
		img.set_pixel(width - 2, y, STEEL_SHADE)
	for x in width:
		img.set_pixel(x, 0, OUTLINE)
		img.set_pixel(x, height - 1, OUTLINE)
		if x > 0 and x < width - 1:
			img.set_pixel(x, 1, STEEL_SHINE if x < width / 2 else STEEL_LIGHT)
			img.set_pixel(x, height - 2, STEEL_SHADE)
	return _tex(img)


static func _rivet(img: Image, cx: int, cy: int) -> void:
	img.set_pixel(cx, cy, STEEL_SHINE)
	img.set_pixel(cx + 1, cy, STEEL_LIGHT)
	img.set_pixel(cx, cy + 1, STEEL_LIGHT)
	img.set_pixel(cx + 1, cy + 1, STEEL_DARK)
	img.set_pixel(cx + 2, cy + 1, STEEL_SHADE)
	img.set_pixel(cx + 1, cy + 2, STEEL_SHADE)


# Hanging chain, 3 texels wide: a face-on link then a side-on one, every 6 rows.
static func steel_chain(height: int) -> ImageTexture:
	var img := Image.create(3, maxi(1, height), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in height:
		match y % 6:
			0:
				img.set_pixel(1, y, STEEL_LIGHT)
			1, 2:
				img.set_pixel(0, y, STEEL_LIGHT)
				img.set_pixel(2, y, STEEL_SHADE)
			3:
				img.set_pixel(1, y, STEEL_SHADE)
			_:
				img.set_pixel(1, y, STEEL_DARK)
	return _tex(img)
