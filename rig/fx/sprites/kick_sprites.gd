extends RefCounted
## Flying kick FX on the art grid: the comic impact burst and its radial speed lines.

const OUTLINE := "#2a1f1a"
const BURST_SIZE := 23
const BURST_SHAPES := [
	{"outer": 6.0, "inner": 3.0, "spikes": 6, "twist": 0.25, "hollow": 0.0},
	{"outer": 11.0, "inner": 4.6, "spikes": 10, "twist": 0.25, "hollow": 0.0},
	{"outer": 11.0, "inner": 5.4, "spikes": 10, "twist": 0.3, "hollow": 0.0},
	{"outer": 11.0, "inner": 6.0, "spikes": 10, "twist": 0.3, "hollow": 0.66},
]
## Per frame: [k threshold, color] bands from the center out; the last color fills the rest.
const BURST_BANDS := [
	[[0.55, "#ffffff"], [INF, "#ffd040"]],
	[[0.4, "#ffffff"], [0.75, "#ffd040"], [INF, "#ff8020"]],
	[[0.4, "#fff0a0"], [0.75, "#ffb030"], [INF, "#e86a10"]],
	[[0.85, "#ffb030"], [INF, "#e86a10"]],
]


static func sprites() -> Array:
	var bursts: Array[Image] = []
	for f in BURST_SHAPES.size():
		bursts.append(_star(BURST_SHAPES[f], BURST_BANDS[f]))
	var lines: Array[Image] = []
	for n in [5, 3]:
		var img := Image.create_empty(5, 2, false, Image.FORMAT_RGBA8)
		for x in n:
			img.set_pixel(x, 0, Color.html("#ffffff"))
			img.set_pixel(x, 1, Color.html("#ffd040"))
		lines.append(img)
	return [
		{"key": "kickBurst", "frames": bursts, "origin": Vector2(11, 11), "rotation_step": PI / 2},
		{"key": "kickLine", "frames": lines, "origin": Vector2(0, 1), "rotation_step": PI / 4},
	]


## Normalized radius of a cell inside the jagged star (-1 outside or in the hollow).
static func _inside(s: Dictionary, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= BURST_SIZE or y >= BURST_SIZE:
		return -1.0
	var c := (BURST_SIZE - 1) / 2.0
	var dx := x - c
	var dy := y - c
	var a: float = atan2(dy, dx) / TAU * s.spikes + s.twist
	var tri := absf(a - floorf(a) - 0.5) * 2.0
	var k := sqrt(dx * dx + dy * dy) / lerpf(s.outer, s.inner, tri)
	return k if k <= 1.0 and k >= s.hollow else -1.0


static func _star(s: Dictionary, bands: Array) -> Image:
	var img := Image.create_empty(BURST_SIZE, BURST_SIZE, false, Image.FORMAT_RGBA8)
	var outline := Color.html(OUTLINE)
	for y in BURST_SIZE:
		for x in BURST_SIZE:
			var k := _inside(s, x, y)
			if k >= 0.0:
				for band: Array in bands:
					if k < band[0]:
						img.set_pixel(x, y, Color.html(band[1]))
						break
			elif _inside(s, x - 1, y) >= 0.0 or _inside(s, x + 1, y) >= 0.0 or _inside(s, x, y - 1) >= 0.0 or _inside(s, x, y + 1) >= 0.0:
				img.set_pixel(x, y, outline)
	return img
