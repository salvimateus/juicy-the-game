extends RefCounted
## Ninja strike FX on the art grid (ports of the JS ninjaPuff and slash sprites).

const PUFF_OUTLINE := "#3a3a4e"
const PUFF_MID := "#aeaec2"
const PUFF_LIGHT := "#e6e6f0"
const PUFF_LOBES := [[3.4, 5.6, 2.6], [6.2, 4.0, 3.1], [8.6, 5.8, 2.4], [6.0, 6.6, 3.0]]


static func sprites() -> Array:
	var puffs: Array[Image] = []
	for f in 4:
		puffs.append(_puff(f))
	var slashes: Array[Image] = []
	for f in 3:
		slashes.append(_slash(f))
	return [
		{"key": "ninjaPuff", "frames": puffs, "origin": Vector2(6, 6), "rotation_step": 0.0},
		{"key": "ninjaSlash", "frames": slashes, "origin": Vector2(10, 10), "rotation_step": PI / 4.0},
	]


## Bumpy three-lobe cloud: dark outline, mid body, light top rim. Frames: 0 small, 1 full,
## 2 full breaking up, 3 small breaking up.
static func _puff(f: int) -> Image:
	var img := Image.create_empty(12, 10, false, Image.FORMAT_RGBA8)
	var k := 0.62 if f == 0 or f == 3 else 1.0
	for y in 10:
		for x in 12:
			if not _puff_solid(x, y, k):
				continue
			var edge := not _puff_solid(x + 1, y, k) or not _puff_solid(x - 1, y, k) or not _puff_solid(x, y + 1, k) or not _puff_solid(x, y - 1, k)
			if not edge and f >= 2 and (x * 5 + y * 3) % 4 == 0:
				continue
			var rim := not edge and (not _puff_solid(x, y - 2, k) or not _puff_solid(x - 1, y - 1, k))
			img.set_pixel(x, y, Color.html(PUFF_OUTLINE if edge else (PUFF_LIGHT if rim else PUFF_MID)))
	return img


static func _puff_solid(x: int, y: int, k: float) -> bool:
	for l: Array in PUFF_LOBES:
		var dx: float = (x + 0.5 - 6.0) / k + 6.0 - l[0]
		var dy: float = (y + 0.5 - 6.0) / k + 6.0 - l[1]
		if dx * dx + dy * dy <= l[2] * l[2]:
			return true
	return false


## Crescent of blocks thinning over its frames.
static func _slash(f: int) -> Image:
	var img := Image.create_empty(21, 21, false, Image.FORMAT_RGBA8)
	var r := 10.0
	var inset := 3.0 + f * 1.5
	for y in 21:
		for x in 21:
			var dx := x - 10.0
			var dy := y - 10.0
			var outer := dx * dx + dy * dy <= r * r
			var ix := dx + inset
			var inner := ix * ix + dy * dy <= (r - 1.5) * (r - 1.5)
			if outer and not inner and dx > -4.0:
				var edge := dx * dx + dy * dy > (r - 1.0) * (r - 1.0)
				img.set_pixel(x, y, Color.html("#a8d8ff" if edge else ("#d8f0ff" if f == 2 else "#ffffff")))
	return img
