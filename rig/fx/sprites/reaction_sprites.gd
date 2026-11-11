extends RefCounted
## Blood FX on the art grid for the shot reaction: drops in flight, ground stains, mist puffs and
## the wound decal (three growth stages).

const DARK := "#5e0b0e"
const MID := "#8c1418"
const BRIGHT := "#b81e22"
const WOUND_CELLS := [
	["..", ".#", "##"],
	[".##.", "####", "#o##", ".##.", "..#."],
	["..###..", ".#####.", "###o##.", "##oo###", ".#####.", "..##.#.", "..#....", "..#...."],
]


static func sprites() -> Array:
	var palette := {"d": DARK, "m": MID, "b": BRIGHT}
	return [
		# Drawn along +x so rotation turns them into streaks.
		RigFxSprites.masked("bloodDrop", 3, 2, Vector2(1, 1), PI / 4, palette, [
			["...", ".m."],
			["...", "db."],
			["dmm", "ddb"],
		]),
		# Ground stains, origin at the bottom center: dot, flat splat, splat with spatter.
		RigFxSprites.masked("bloodSplat", 7, 2, Vector2(3, 2), PI / 2, palette, [
			[".......", "...dd.."],
			[".......", "..dmd.."],
			[".....d.", "ddmmdd."],
		]),
		{"key": "bloodMist", "frames": _mist(), "origin": Vector2(5, 5), "rotation_step": PI / 2},
		{"key": "bloodWound", "frames": _wound(), "origin": Vector2(3, 4), "rotation_step": PI / 8},
	]


static func _mist() -> Array[Image]:
	var frames: Array[Image] = []
	for f in 3:
		var img := Image.create_empty(11, 11, false, Image.FORMAT_RGBA8)
		var radius: float = [2.5, 3.8, 5.0][f]
		for y in range(-5, 6):
			for x in range(-5, 6):
				var d := sqrt(float(x * x + y * y))
				if d > radius:
					continue
				if f > 0 and posmod(x * 3 + y * 5 + f, f + 2) == 0:
					continue
				img.set_pixel(x + 5, y + 5, Color.html(MID if d < radius * 0.5 and f < 2 else DARK))
		frames.append(img)
	return frames


static func _wound() -> Array[Image]:
	var frames: Array[Image] = []
	for cells: Array in WOUND_CELLS:
		var img := Image.create_empty(7, 8, false, Image.FORMAT_RGBA8)
		var ox := (7 - (cells[0] as String).length()) / 2
		var oy := (8 - cells.size()) / 2
		for y in cells.size():
			var row: String = cells[y]
			for x in row.length():
				var c := row[x]
				if c == ".":
					continue
				var color := BRIGHT if c == "o" else (DARK if (x + y) % 3 == 0 else MID)
				img.set_pixel(ox + x, oy + y, Color.html(color))
		frames.append(img)
	return frames
