extends RefCounted

# Pre-rotated sheets of the bike (PixelRotate, no rotation at draw time): body and swingarm every
# BODY_ANGLE_STEP_DEG, wheel in WHEEL_FRAMES steps plus one blurred wheel. Built once per run on a
# worker thread (the rotation is slow in GDScript) and kept in static vars.
# Use: start() once, poll() every frame until it returns true, then read the sheets.

const T := preload("res://game/moto/moto_tuning.gd")
const PixelRotate := preload("res://game/targets/pixel_rotate.gd")

# {texture, rects, offsets} each; wheel rects[WHEEL_FRAMES] is the blur, at blur_offset.
static var body: Dictionary = {}
static var swing: Dictionary = {}
static var wheel: Dictionary = {}
static var wheel_blur_offset := Vector2.ZERO
static var _task := -1
static var _result: Dictionary = {}


static func is_ready() -> bool:
	return not body.is_empty()


static func body_steps() -> int:
	return roundi(360.0 / T.BODY_ANGLE_STEP_DEG)


static func start() -> void:
	if is_ready() or _task != -1:
		return
	var imgs := {}
	for key in [["body", T.BODY_PNG], ["swing", T.SWINGARM_PNG], ["wheel", T.WHEEL_PNG]]:
		var tex := load(key[1]) as Texture2D
		if tex == null:
			push_error("Moto art missing: %s (run the Godot import)" % key[1])
			return
		imgs[key[0]] = PixelRotate.load_art(tex)
	_result = {}
	_task = WorkerThreadPool.add_task(_build.bind(imgs, _result), true, "moto_art")


# True once the sheets exist (packs them into textures on the calling, main, thread).
static func poll() -> bool:
	if is_ready():
		return true
	if _task == -1 or not WorkerThreadPool.is_task_completed(_task):
		return false
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var r := _result
	body = _pack(r.body)
	swing = _pack(r.swing)
	var wheel_images: Array[Image] = r.wheel.images
	wheel_images.append(r.blur)
	wheel = _pack({images = wheel_images, offsets = r.wheel.offsets})
	wheel_blur_offset = r.blur_offset
	_result = {}
	return true


static func _pack(f: Dictionary) -> Dictionary:
	var images: Array[Image] = []
	images.assign(f.images)
	var packed := PixelRotate.pack(images)
	return {texture = packed.texture, rects = packed.rects, offsets = f.offsets}


static func _build(imgs: Dictionary, out: Dictionary) -> void:
	var n := body_steps()
	var step := deg_to_rad(T.BODY_ANGLE_STEP_DEG)
	var angles := PackedFloat32Array()
	for k in n:
		angles.append(k * step)
	out.body = PixelRotate.frames(imgs.body, T.BODY_PIVOT_ART, angles)
	out.swing = PixelRotate.frames(imgs.swing, T.SWING_PIVOT_ART, angles)
	var wheel_angles := PackedFloat32Array()
	for k in T.WHEEL_FRAMES:
		wheel_angles.append(k * TAU / T.WHEEL_FRAMES)
	out.wheel = PixelRotate.frames(imgs.wheel, T.WHEEL_PIVOT_ART, wheel_angles)
	_build_blur(imgs.wheel, out)


# Average of WHEEL_BLUR_SAMPLES rotations across one spoke gap, cut at half alpha and snapped to the
# wheel's own colours (no new shades, no dither).
static func _build_blur(img: Image, out: Dictionary) -> void:
	var samples := PackedFloat32Array()
	for k in T.WHEEL_BLUR_SAMPLES:
		samples.append(k * (TAU / 8.0) / T.WHEEL_BLUR_SAMPLES)
	var f := PixelRotate.frames(img, T.WHEEL_PIVOT_ART, samples)
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := -lo
	for i in samples.size():
		var o := Vector2i(f.offsets[i])
		lo = lo.min(o)
		hi = hi.max(o + (f.images[i] as Image).get_size())
	var size := hi - lo
	var acc := PackedFloat32Array()
	acc.resize(size.x * size.y * 4)
	for i in samples.size():
		var im: Image = f.images[i]
		var o := Vector2i(f.offsets[i]) - lo
		for y in im.get_height():
			for x in im.get_width():
				var c := im.get_pixel(x, y)
				var j := ((o.y + y) * size.x + o.x + x) * 4
				acc[j] += c.r * c.a
				acc[j + 1] += c.g * c.a
				acc[j + 2] += c.b * c.a
				acc[j + 3] += c.a
	var palette: Array[Color] = []
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and not palette.has(c):
				palette.append(c)
	var blur := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var count := float(samples.size())
	for y in size.y:
		for x in size.x:
			var j := (y * size.x + x) * 4
			var a := acc[j + 3]
			if a / count < 0.5:
				continue
			var mean := Color(acc[j] / a, acc[j + 1] / a, acc[j + 2] / a)
			var best := palette[0]
			var best_d := INF
			for p in palette:
				var d := Vector3(p.r - mean.r, p.g - mean.g, p.b - mean.b).length_squared()
				if d < best_d:
					best_d = d
					best = p
			blur.set_pixel(x, y, best)
	out.blur = blur
	out.blur_offset = Vector2(lo)
