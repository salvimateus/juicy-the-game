class_name RigFxSprites
extends RefCounted
## FX sprites on the art grid: 1 texel = 1 ART_PIXEL block. Each frame is pre-rotated at art
## resolution in rotation_step increments, so a rotated effect never leaves the chunky grid.

const OUTLINE := "#2a1f1a"


## Extra sprite providers (scripts with `static func sprites() -> Array` returning masked() defs),
## loaded when present.
const PROVIDERS := [
	"res://rig/fx/sprites/boxing_sprites.gd",
	"res://rig/fx/sprites/kick_sprites.gd",
	"res://rig/fx/sprites/gun_sprites.gd",
	"res://rig/fx/sprites/bow_ninja_sprites.gd",
	"res://rig/fx/sprites/reaction_sprites.gd",
	"res://rig/fx/sprites/interaction_sprites.gd",
	"res://rig/fx/sprites/swim_sprites.gd",
]


static func build() -> Array:
	var out: Array = []
	for path in PROVIDERS:
		if ResourceLoader.exists(path):
			out.append_array(load(path).sprites())
	out.append(masked("dust", 7, 5, Vector2(3, 4), PI / 4, {"o": "#5e4c3c", "a": "#e0d0b0", "b": "#b8a283"}, [
		[".......", ".......", "..oo...", ".oabo..", ".obbo.."],
		[".......", "..ooo..", ".oaabo.", "oabbbo.", ".ooooo."],
		[".o...o.", "o.a.b.o", ".b...a.", "o.b.b..", "......."],
	]))
	out.append(masked("smoke", 7, 7, Vector2(3, 3), PI / 4, {"o": "#3e3e4c", "a": "#e4e4ec", "b": "#b4b4c4", "c": "#8a8a9c"}, [
		[".......", ".......", "..ooo..", ".oaabo.", ".oabbo.", "..ooo..", "......."],
		[".......", "..ooo..", ".oaabo.", "oaabbco", "oabbcco", ".occco.", "..ooo.."],
		["..o.o..", ".o.a.o.", "o.b.b.o", ".c.b.c.", "o.c.c.o", ".o...o.", "..o.o.."],
	]))
	out.append(masked("spark", 5, 3, Vector2(2, 1), PI / 4, {"h": "#fffbe0", "y": "#ffd040", "r": "#e86a10"}, [
		[".....", "ryyhh", "....."],
		[".....", ".ryyh", "....."],
	]))
	out.append(masked("star", 9, 9, Vector2(4, 4), PI / 2, {"o": OUTLINE, "w": "#ffffff", "y": "#ffd040", "r": "#ff8020"}, [
		["....o....", "...owo...", "...owo...", ".ooywyoo.", "owwyryywo", ".ooywyoo.", "...owo...", "...owo...", "....o...."],
		[".........", ".........", "....o....", "...oyo...", "..oyryo..", "...oyo...", "....o....", ".........", "........."],
	]))
	out.append(masked("confetti", 2, 2, Vector2(1, 1), PI / 2, {"a": "#ff2a3a", "b": "#a8101e", "c": "#d4142a", "d": "#ff6070"}, [
		["aa", "bb"], ["cd", "cd"], ["a.", ".."],
	]))
	out.append(masked("debris", 3, 3, Vector2(1, 1), PI / 2, {"o": OUTLINE, "a": "#9a8270", "b": "#6a5040"}, [
		["oao", "abo", "oo."], [".o.", "oab", ".bo"],
	]))
	out.append(masked("ledgeChip", 3, 3, Vector2(1, 1), PI / 2, {"s": "#967e79", "l": "#b8a09a", "d": "#2c2428", "m": "#6e5c5c", "e": "#5a4030", "f": "#3a2a20", "g": "#6e9a48", "h": "#3a5a2a"}, [
		["lsd", "ssd", "ddd"], ["mm.", "dd.", "..."], ["ef.", "...", "..."], ["gg.", "hh.", "..."],
	]))
	return out


## Builds a sprite def from string masks (one char per art pixel, '.' empty).
static func masked(key: String, w: int, h: int, origin: Vector2, rotation_step: float, palette: Dictionary, shapes: Array) -> Dictionary:
	var colors := {}
	for c in palette:
		colors[c] = Color.html(palette[c])
	var frames: Array[Image] = []
	for rows: Array in shapes:
		var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				var c := row[x]
				if c != ".":
					img.set_pixel(x, y, colors[c])
		frames.append(img)
	return {"key": key, "frames": frames, "origin": origin, "rotation_step": rotation_step}


## Nearest-neighbor rotation around `origin` (texel-corner coordinates), clockwise on screen.
## Returns the rotated image and the origin inside it.
static func rotate_nearest(src: Image, origin: Vector2, angle: float) -> Dictionary:
	var c := cos(angle)
	var s := sin(angle)
	if absf(c) < 1e-6:
		c = 0.0
	if absf(s) < 1e-6:
		s = 0.0
	if s == 0.0 and c == 1.0:
		return {"image": src, "origin": origin}
	var w := src.get_width()
	var h := src.get_height()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var d: Vector2 = corner - origin
		var r := Vector2(c * d.x - s * d.y, s * d.x + c * d.y)
		lo = lo.min(r)
		hi = hi.max(r)
	var o2 := Vector2(-floorf(lo.x + 1e-4), -floorf(lo.y + 1e-4))
	var dw := int(ceilf(hi.x - 1e-4) + o2.x)
	var dh := int(ceilf(hi.y - 1e-4) + o2.y)
	var dst := Image.create_empty(maxi(1, dw), maxi(1, dh), false, Image.FORMAT_RGBA8)
	for j in dh:
		for i in dw:
			var d := Vector2(i + 0.5, j + 0.5) - o2
			var sp := Vector2(c * d.x + s * d.y, -s * d.x + c * d.y) + origin
			var sx := int(floorf(sp.x))
			var sy := int(floorf(sp.y))
			if sx >= 0 and sy >= 0 and sx < w and sy < h:
				dst.set_pixel(i, j, src.get_pixel(sx, sy))
	return {"image": dst, "origin": o2}
