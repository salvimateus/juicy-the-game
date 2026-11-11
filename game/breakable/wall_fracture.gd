extends RefCounted

# Brick wall art and its one-time pre-fracture, in art pixels (one texel per art pixel).
# Pieces follow the mortar joints: whole bricks, merged pairs near the base, halves and chips in the
# weak band. Each piece is pre-rendered at ANGLE_STEPS rotations with a RotSprite-style pass
# (Scale2x upscaling, nearest rotation, point resample, inner outline) into one shared atlas, so a
# spinning piece only swaps region rects and never rotates a texture (no mixels).

const PixelArt := preload("res://game/pixel_art.gd")

const ANGLE_STEPS := 16
const BRICK_W := 10
const BRICK_H := 6
const UPSCALE_PASSES := 3
const TINY_AREA := 12
const CRUMB_AREA := 3
const ATLAS_WIDTH := 512
const HULL_INSET := 2.5
const MIN_CELL := 3

enum { CLEAR, OUTLINE, MORTAR, SHADE, STONE, LIGHT }

static var _cache: Dictionary = {}


static func palette() -> PackedColorArray:
	return PackedColorArray([Color.TRANSPARENT, PixelArt.OUTLINE, PixelArt.MORTAR, PixelArt.STONE_SHADE,
		PixelArt.STONE, PixelArt.STONE_LIGHT])


# Shared by every wall with the same parameters: the fracture and its atlas are built once.
static func build(w: int, h: int, seed: int, weak_height: float, max_pieces: int, a: int) -> Dictionary:
	var key := "%d:%d:%d:%.3f:%d:%d" % [w, h, seed, weak_height, max_pieces, a]
	if _cache.has(key):
		return _cache[key]
	var t0 := Time.get_ticks_usec()
	var grid := _wall_grid(w, h)
	var split := _fracture(w, h, seed, weak_height, max_pieces)
	var colors := palette()
	var pieces: Array = []
	var frames: Array = []
	for p: PackedInt32Array in split.pieces:
		pieces.append(_piece(p, grid, w, h, a, frames, pieces.size()))
	var atlas := _pack(frames, pieces, a, colors)
	var crumbs := PackedVector2Array()
	var crumb_colors := PackedColorArray()
	for idx in split.crumbs:
		crumbs.append(Vector2((idx % w - w / 2) * a, (idx / w - h) * a))
		crumb_colors.append(colors[grid[idx]] if grid[idx] != CLEAR else PixelArt.STONE)
	var data := {
		wall = _texture(grid, w, h, colors),
		atlas = atlas,
		pieces = pieces,
		crumbs = crumbs,
		crumb_colors = crumb_colors,
		build_usec = Time.get_ticks_usec() - t0,
	}
	_cache[key] = data
	return data


static func _hash(x: int, y: int) -> int:
	var h := (x * 374761393 + y * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return h


static func _row_shift(row: int) -> int:
	return 3 if row % 2 == 0 else 8


static func _wall_grid(w: int, h: int) -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(w * h)
	for y in h:
		var ry := y % BRICK_H
		var shift := _row_shift(y / BRICK_H)
		for x in w:
			var c := STONE
			if x == 0 or x == w - 1 or y == 0:
				c = OUTLINE
			else:
				var bx := posmod(x + shift, BRICK_W)
				if ry == BRICK_H - 1 or bx == BRICK_W - 1:
					c = MORTAR
				elif ry == BRICK_H - 2 or bx == BRICK_W - 2:
					c = SHADE
				elif ry == 0 or bx == 0:
					c = LIGHT
				elif _hash(x, y) % 11 == 0:
					c = SHADE
			g[y * w + x] = c
	return g


static func _texture(grid: PackedByteArray, w: int, h: int, colors: PackedColorArray) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			img.set_pixel(x, y, colors[grid[y * w + x]])
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- fracture

static func _fracture(w: int, h: int, seed: int, weak_height: float, max_pieces: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var weak_y := h * (1.0 - weak_height)
	var rows := ceili(float(h) / BRICK_H)
	var pieces: Array[PackedInt32Array] = []
	for row in rows:
		var y0 := row * BRICK_H
		var y1 := mini(y0 + BRICK_H, h)
		var shift := _row_shift(row)
		var cells: Array = []
		var x := 0
		while x < w:
			var x1 := mini(((x + shift) / BRICK_W + 1) * BRICK_W - shift, w)
			cells.append([x, x1])
			x = x1
		# Slivers at the wall edge join their neighbour.
		if cells.size() > 1 and cells[0][1] - cells[0][0] < MIN_CELL:
			cells[1][0] = cells[0][0]
			cells.remove_at(0)
		if cells.size() > 1 and cells[-1][1] - cells[-1][0] < MIN_CELL:
			cells[-2][1] = cells[-1][1]
			cells.remove_at(cells.size() - 1)
		var dist := absf((y0 + y1) * 0.5 - weak_y) / BRICK_H
		if dist > 2.5 and y1 >= h - 2 * BRICK_H:
			var merged: Array = []
			var i := 0
			while i < cells.size():
				if i + 1 < cells.size() and rng.randf() < 0.55:
					merged.append([cells[i][0], cells[i + 1][1]])
					i += 2
				else:
					merged.append(cells[i])
					i += 1
			cells = merged
		for c in cells:
			var pix := _rect_indices(c[0], y0, c[1], y1, w)
			if dist < 1.0:
				_shatter(pix, w, rng, 2, pieces)
			elif dist < 2.0 and rng.randf() < 0.65:
				_shatter(pix, w, rng, 1, pieces)
			elif rng.randf() < (0.4 if dist < 3.0 else 0.15):
				pieces.append_array(_chip(pix, w, rng))
			else:
				pieces.append(pix)
	var crumbs := PackedInt32Array()
	var kept: Array[PackedInt32Array] = []
	for p in pieces:
		if p.size() < CRUMB_AREA:
			crumbs.append_array(p)
		elif not p.is_empty():
			kept.append(p)
	kept.sort_custom(func(l: PackedInt32Array, r: PackedInt32Array) -> bool: return l.size() > r.size())
	while kept.size() > max_pieces:
		crumbs.append_array(kept.pop_back())
	return {pieces = kept, crumbs = crumbs}


static func _rect_indices(x0: int, y0: int, x1: int, y1: int, w: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for y in range(y0, y1):
		for x in range(x0, x1):
			out.append(y * w + x)
	return out


static func _bbox(pix: PackedInt32Array, w: int) -> Rect2i:
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	for idx in pix:
		var x := idx % w
		var y := idx / w
		x0 = mini(x0, x)
		y0 = mini(y0, y)
		x1 = maxi(x1, x)
		y1 = maxi(y1, y)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


# Straight cuts keep every piece convex, so the convex collision hulls of neighbours barely overlap.
static func _split(pix: PackedInt32Array, w: int, p0: Vector2, n: Vector2) -> Array:
	var a := PackedInt32Array()
	var b := PackedInt32Array()
	for idx in pix:
		var c := Vector2(idx % w + 0.5, idx / w + 0.5)
		if (c - p0).dot(n) >= 0.0:
			a.append(idx)
		else:
			b.append(idx)
	return [a, b]


static func _shatter(pix: PackedInt32Array, w: int, rng: RandomNumberGenerator, depth: int, out: Array[PackedInt32Array]) -> void:
	var box := _bbox(pix, w)
	if box.size.x < 4 and box.size.y < 4:
		out.append(pix)
		return
	var center := Vector2(box.position) + Vector2(box.size) * 0.5
	var angle: float
	if box.size.x >= box.size.y:
		center.x += rng.randf_range(-1.5, 1.5)
		angle = rng.randf_range(-0.5, 0.5)
	else:
		center.y += rng.randf_range(-1.5, 1.5)
		angle = PI * 0.5 + rng.randf_range(-0.5, 0.5)
	var halves := _split(pix, w, center, Vector2.from_angle(angle))
	for half: PackedInt32Array in halves:
		if half.is_empty():
			continue
		if depth > 1 and half.size() > 16 and rng.randf() < 0.5:
			_shatter(half, w, rng, depth - 1, out)
		elif rng.randf() < 0.6:
			out.append_array(_chip(half, w, rng))
		else:
			out.append(half)


# Knocks a small triangle off one corner.
static func _chip(pix: PackedInt32Array, w: int, rng: RandomNumberGenerator) -> Array:
	var box := _bbox(pix, w)
	if box.size.x < 4 or box.size.y < 3:
		return [pix]
	var right := rng.randf() < 0.5
	var bottom := rng.randf() < 0.5
	var corner := Vector2(box.end.x if right else box.position.x, box.end.y if bottom else box.position.y)
	var n := Vector2(1.0 if right else -1.0, 1.0 if bottom else -1.0).normalized()
	var parts := _split(pix, w, corner - n * rng.randf_range(2.2, 3.8), n)
	var chip: PackedInt32Array = parts[0]
	var rest: PackedInt32Array = parts[1]
	if chip.is_empty() or rest.size() < CRUMB_AREA:
		return [pix]
	return [rest, chip]


# ---------------------------------------------------------------- pieces and frames

static func _piece(pix: PackedInt32Array, grid: PackedByteArray, w: int, h: int, a: int, frames: Array, index: int) -> Dictionary:
	var box := _bbox(pix, w)
	var bw := box.size.x
	var bh := box.size.y
	var fill := PackedByteArray()
	fill.resize(bw * bh)
	var sum := Vector2.ZERO
	for idx in pix:
		var x := idx % w
		var y := idx / w
		fill[(y - box.position.y) * bw + (x - box.position.x)] = grid[idx]
		sum += Vector2(x + 0.5, y + 0.5)
	var centroid := sum / pix.size()
	var origin := Vector2i(roundi(centroid.x), roundi(centroid.y))
	var pivot := Vector2(origin - box.position)
	var up := fill
	var uw := bw
	var uh := bh
	for i in UPSCALE_PASSES:
		up = _scale2x(up, uw, uh)
		uw *= 2
		uh *= 2
	var k_up := float(1 << UPSCALE_PASSES)
	var tiny := pix.size() < TINY_AREA
	for k in ANGLE_STEPS:
		var th := TAU * k / ANGLE_STEPS
		var cs := cos(th)
		var sn := sin(th)
		var lo := Vector2(INF, INF)
		var hi := -lo
		for corner in [Vector2.ZERO, Vector2(bw, 0), Vector2(0, bh), Vector2(bw, bh)]:
			var d: Vector2 = corner - pivot
			var r := Vector2(d.x * cs - d.y * sn, d.x * sn + d.y * cs)
			lo = lo.min(r)
			hi = hi.max(r)
		var x0 := floori(lo.x)
		var y0 := floori(lo.y)
		var fw := ceili(hi.x) - x0
		var fh := ceili(hi.y) - y0
		var out := PackedByteArray()
		out.resize(fw * fh)
		for yy in fh:
			for xx in fw:
				var cx := x0 + xx + 0.5
				var cy := y0 + yy + 0.5
				var ux := floori((pivot.x + cx * cs + cy * sn) * k_up)
				var uy := floori((pivot.y - cx * sn + cy * cs) * k_up)
				if ux >= 0 and uy >= 0 and ux < uw and uy < uh:
					out[yy * fw + xx] = up[uy * uw + ux]
		var trimmed := _trim(out, fw, fh)
		var tr: Rect2i = trimmed.rect
		var img: PackedByteArray = trimmed.data
		if not tiny:
			img = _inner_outline(img, tr.size.x, tr.size.y)
		frames.append({piece = index, k = k, w = tr.size.x, h = tr.size.y, data = img,
			offset = Vector2((x0 + tr.position.x) * a, (y0 + tr.position.y) * a)})
	var corners := PackedVector2Array()
	for idx in pix:
		var p := Vector2(idx % w - origin.x, idx / w - origin.y)
		corners.append_array([p * a, (p + Vector2(1, 0)) * a, (p + Vector2(0, 1)) * a, (p + Vector2.ONE) * a])
	var hull := Geometry2D.convex_hull(corners)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	var inset := Geometry2D.offset_polygon(hull, -HULL_INSET)
	if not inset.is_empty() and inset[0].size() >= 3:
		hull = inset[0]
	return {
		origin = Vector2((origin.x - w / 2) * a, (origin.y - h) * a),
		hull = hull,
		area = pix.size(),
		tiny = tiny,
		half_size = Vector2(bw, bh) * a * 0.5,
		rects = [],
		offsets = [],
	}


static func _scale2x(src: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var dst := PackedByteArray()
	dst.resize(w * h * 4)
	var w2 := w * 2
	for y in h:
		for x in w:
			var p := src[y * w + x]
			var a := src[(y - 1) * w + x] if y > 0 else 0
			var b := src[y * w + x + 1] if x < w - 1 else 0
			var c := src[y * w + x - 1] if x > 0 else 0
			var d := src[(y + 1) * w + x] if y < h - 1 else 0
			var o := y * 2 * w2 + x * 2
			dst[o] = a if c == a and c != d and a != b else p
			dst[o + 1] = b if a == b and a != c and b != d else p
			dst[o + w2] = c if d == c and d != b and c != a else p
			dst[o + w2 + 1] = d if b == d and b != a and d != c else p
	return dst


static func _trim(src: PackedByteArray, w: int, h: int) -> Dictionary:
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if src[y * w + x] != CLEAR:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		var one := PackedByteArray([STONE])
		return {rect = Rect2i(0, 0, 1, 1), data = one}
	var tw := x1 - x0 + 1
	var th := y1 - y0 + 1
	var out := PackedByteArray()
	out.resize(tw * th)
	for y in th:
		for x in tw:
			out[y * tw + x] = src[(y + y0) * w + x + x0]
	return {rect = Rect2i(x0, y0, tw, th), data = out}


# Edge pixels of a loose piece become the dark contour (inside the shape, so pieces keep their size).
static func _inner_outline(src: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := src.duplicate()
	for y in h:
		for x in w:
			if src[y * w + x] == CLEAR:
				continue
			var edge := x == 0 or y == 0 or x == w - 1 or y == h - 1 \
				or src[y * w + x - 1] == CLEAR or src[y * w + x + 1] == CLEAR \
				or src[(y - 1) * w + x] == CLEAR or src[(y + 1) * w + x] == CLEAR
			if edge:
				out[y * w + x] = OUTLINE
	return out


static func _pack(frames: Array, pieces: Array, _a: int, colors: PackedColorArray) -> ImageTexture:
	var x := 0
	var y := 0
	var row_h := 0
	var placed: Array[Vector2i] = []
	for f in frames:
		if x + f.w + 1 > ATLAS_WIDTH:
			x = 0
			y += row_h + 1
			row_h = 0
		placed.append(Vector2i(x, y))
		x += f.w + 1
		row_h = maxi(row_h, f.h)
	var img := Image.create(ATLAS_WIDTH, maxi(y + row_h, 1), false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for i in frames.size():
		var f: Dictionary = frames[i]
		var at := placed[i]
		var data: PackedByteArray = f.data
		for yy in f.h:
			for xx in f.w:
				var c := data[yy * f.w + xx]
				if c != CLEAR:
					img.set_pixel(at.x + xx, at.y + yy, colors[c])
		var piece: Dictionary = pieces[f.piece]
		piece.rects.append(Rect2(at.x, at.y, f.w, f.h))
		piece.offsets.append(f.offset)
	return ImageTexture.create_from_image(img)
