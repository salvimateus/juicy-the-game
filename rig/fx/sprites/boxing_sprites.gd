extends RefCounted
## Boxing FX sprites: the punch impact star (hot core, full star, breaking ring) and the reach wind.

const OUTLINE := "#2a1f1a"
const SIZE := 13
const SHAPES := [
	{"outer": 3.6, "inner": 1.8, "spikes": 4, "twist": 0.5, "hollow": 0.0},
	{"outer": 6.0, "inner": 2.6, "spikes": 8, "twist": 0.5, "hollow": 0.0},
	{"outer": 6.0, "inner": 3.4, "spikes": 8, "twist": 0.5, "hollow": 0.62},
]


static func sprites() -> Array:
	var frames: Array[Image] = []
	for f in SHAPES.size():
		frames.append(_star(f))
	return [
		{"key": "boxImpact", "frames": frames, "origin": Vector2(6, 6), "rotation_step": PI / 2.0},
		# Punch wind streak: head at the origin (right end), thinning over three frames.
		RigFxSprites.masked("boxWind", 14, 2, Vector2(13, 1), PI / 8, {"h": "#ffffff", "w": "#dce8f2", "s": "#9fb4c6"}, [
			["........wwhh..", "sswwwwwwwwwhhh"],
			["..............", "...sswwwwwhhh."],
			["..............", "......s.w.wh.."],
		]),
	]


## Jagged comic star on the art grid: cells inside get a color by r / edge, empty cells touching
## it get the outline.
static func _star(f: int) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var outline := Color.html(OUTLINE)
	for y in SIZE:
		for x in SIZE:
			var k := _inside(f, x, y)
			if k >= 0.0:
				img.set_pixel(x, y, _color(f, k))
			elif _inside(f, x - 1, y) >= 0.0 or _inside(f, x + 1, y) >= 0.0 or _inside(f, x, y - 1) >= 0.0 or _inside(f, x, y + 1) >= 0.0:
				img.set_pixel(x, y, outline)
	return img


static func _inside(f: int, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return -1.0
	var s: Dictionary = SHAPES[f]
	var c := (SIZE - 1) / 2.0
	var dx := x - c
	var dy := y - c
	var a: float = atan2(dy, dx) / TAU * s.spikes + s.twist
	var tri := absf(a - floorf(a) - 0.5) * 2.0
	var k := Vector2(dx, dy).length() / lerpf(s.outer, s.inner, tri)
	return k if k <= 1.0 and k >= s.hollow else -1.0


static func _color(f: int, k: float) -> Color:
	if f == 2:
		return Color.html("#e86a10" if k > 0.85 else "#ffd040")
	if k < 0.45:
		return Color.html("#ffffff")
	return Color.html("#ffd040" if k < 0.8 else "#ff8020")
