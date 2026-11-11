extends RefCounted

# Pre-rotated pixel-art frames without mixels: the art (one texel per art pixel) is upscaled with
# Scale2x passes, then each angle is resampled nearest-neighbour back onto the art grid, the same
# technique as res://game/breakable/wall_fracture.gd. Frames are packed into one atlas texture that a
# Sprite2D shows at scale ART_PIXEL with region_rect, placed at pivot + offset * ART_PIXEL.

const UPSCALE_PASSES := 3
const ATLAS_WIDTH := 512


# Art-pixel image of a source-px texture drawn in `a`-sized blocks (pecas_extra style).
static func art_image(texture: Texture2D, a: int) -> Image:
	var src := texture.get_image()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var w := src.get_width() / a
	var h := src.get_height() / a
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			out.set_pixel(x, y, src.get_pixel(x * a + a / 2, y * a + a / 2))
	return out


# Loads a texture as an RGBA8 image (already one texel per art pixel).
static func load_art(texture: Texture2D) -> Image:
	var img := texture.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


# Rotated frames of `img` around `pivot` (art px, integer keeps angle 0 identical to the source).
# Returns {texture, rects: Array[Rect2], offsets: PackedVector2Array (art px, frame top-left minus
# pivot)}; frame i is angles[i] radians, clockwise on screen like Node2D.rotation.
static func build(img: Image, pivot: Vector2, angles: PackedFloat32Array, extra: Array[Image] = []) -> Dictionary:
	var f := frames(img, pivot, angles)
	var images: Array[Image] = f.images
	images.append_array(extra)
	var packed := pack(images)
	return {texture = packed.texture, rects = packed.rects, offsets = f.offsets}


# The rotated images themselves ({images: Array[Image], offsets}), to pack several sets together.
static func frames(img: Image, pivot: Vector2, angles: PackedFloat32Array) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var up := img.get_data().to_int32_array()
	var uw := w
	var uh := h
	for i in UPSCALE_PASSES:
		up = _scale2x(up, uw, uh)
		uw *= 2
		uh *= 2
	var k_up := float(1 << UPSCALE_PASSES)
	var images: Array[Image] = []
	var offsets := PackedVector2Array()
	for th in angles:
		var cs := cos(th)
		var sn := sin(th)
		var lo := Vector2(INF, INF)
		var hi := -lo
		for corner in [Vector2.ZERO, Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
			var d: Vector2 = corner - pivot
			var r := Vector2(d.x * cs - d.y * sn, d.x * sn + d.y * cs)
			lo = lo.min(r)
			hi = hi.max(r)
		var x0 := floori(lo.x + 0.001)
		var y0 := floori(lo.y + 0.001)
		var fw := ceili(hi.x - 0.001) - x0
		var fh := ceili(hi.y - 0.001) - y0
		var out := PackedInt32Array()
		out.resize(fw * fh)
		for yy in fh:
			var cy := y0 + yy + 0.5
			for xx in fw:
				var cx := x0 + xx + 0.5
				var ux := floori((pivot.x + cx * cs + cy * sn) * k_up)
				var uy := floori((pivot.y - cx * sn + cy * cs) * k_up)
				if ux >= 0 and uy >= 0 and ux < uw and uy < uh:
					out[yy * fw + xx] = up[uy * uw + ux]
		images.append(Image.create_from_data(fw, fh, false, Image.FORMAT_RGBA8, out.to_byte_array()))
		offsets.append(Vector2(x0, y0))
	return {images = images, offsets = offsets}


# Shelf-packs images into one atlas with a 1 px gap.
static func pack(images: Array[Image]) -> Dictionary:
	var x := 0
	var y := 0
	var row_h := 0
	var spots: Array[Vector2i] = []
	for img in images:
		if x + img.get_width() > ATLAS_WIDTH:
			x = 0
			y += row_h + 1
			row_h = 0
		spots.append(Vector2i(x, y))
		x += img.get_width() + 1
		row_h = maxi(row_h, img.get_height())
	var atlas := Image.create(ATLAS_WIDTH, maxi(1, y + row_h), false, Image.FORMAT_RGBA8)
	var rects: Array[Rect2] = []
	for i in images.size():
		var img := images[i]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), spots[i])
		rects.append(Rect2(spots[i], img.get_size()))
	return {texture = ImageTexture.create_from_image(atlas), rects = rects}


# Same image with every opaque pixel turned white (pop / flash frames).
static func silhouette(img: Image, color := Color.WHITE) -> Image:
	var out := img.duplicate() as Image
	for y in out.get_height():
		for x in out.get_width():
			if out.get_pixel(x, y).a > 0.0:
				out.set_pixel(x, y, color)
	return out


# Evenly spaced angles in [from, to].
static func angle_range(from: float, to: float, step: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := roundi((to - from) / step)
	for i in n + 1:
		out.append(from + step * i)
	return out


static func _scale2x(src: PackedInt32Array, w: int, h: int) -> PackedInt32Array:
	var dst := PackedInt32Array()
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
