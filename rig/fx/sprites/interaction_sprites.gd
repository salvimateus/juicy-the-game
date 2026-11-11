extends RefCounted
## Interaction FX on the art grid: the chair creak ticks and the sleeping Zs.

## Creak ticks [x, y, w] per frame; frame 1 pushes them out a pixel.
const CREAK_TICKS := [[[1, 1, 1], [2, 3, 2], [1, 5, 1]], [[2, 1, 2], [3, 3, 2], [2, 5, 2]]]
const CREAK_OUTLINE := "#1a1420"
const CREAK_COLORS := ["#fff4d8", "#e8c890"]
## Small z (4x4) and big Z (5x6) with a 2-pixel diagonal so they read as Z, not I.
const Z_GLYPHS := [
	["####", "..##", "##..", "####"],
	["#####", "...##", "..##.", ".##..", "##...", "#####"],
]
const Z_OUTLINE := "#141224"
const Z_FILL := "#ffffff"
const Z_SHADE := "#c8d4ff"


static func sprites() -> Array:
	var creak: Array[Image] = []
	for f in CREAK_TICKS.size():
		var img := Image.create_empty(6, 7, false, Image.FORMAT_RGBA8)
		for tk: Array in CREAK_TICKS[f]:
			_rect(img, tk[0] - 1, tk[1] - 1, tk[2] + 2, 3, Color.html(CREAK_OUTLINE))
		for tk: Array in CREAK_TICKS[f]:
			_rect(img, tk[0], tk[1], tk[2], 1, Color.html(CREAK_COLORS[f]))
		creak.append(img)
	var zs: Array[Image] = []
	for glyph: Array in Z_GLYPHS:
		var img := Image.create_empty(7, 8, false, Image.FORMAT_RGBA8)
		var rows := glyph.size()
		var cols: int = (glyph[0] as String).length()
		var ox := (7 - cols) / 2
		var oy := (8 - rows) / 2
		for pass_i in 2:
			for y in rows:
				for x in cols:
					if (glyph[y] as String)[x] != "#":
						continue
					if pass_i == 0:
						_rect(img, ox + x - 1, oy + y - 1, 3, 3, Color.html(Z_OUTLINE))
					else:
						img.set_pixel(ox + x, oy + y, Color.html(Z_SHADE if y == rows - 1 else Z_FILL))
		zs.append(img)
	return [
		{"key": "sitCreak", "frames": creak, "origin": Vector2(0, 3), "rotation_step": TAU},
		{"key": "sleepZ", "frames": zs, "origin": Vector2(3, 4), "rotation_step": TAU},
	]


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for j in h:
		for i in w:
			var px := x + i
			var py := y + j
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, c)
