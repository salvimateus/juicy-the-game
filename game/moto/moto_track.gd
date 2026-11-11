extends Node2D

# Motocross track: a polyline (x strictly increasing) with filleted corners. The bike queries it
# analytically (height_at, probe); the player walks on a matching CollisionPolygon2D on layer 1.
# The art is one image per block of art-pixel columns: each column is a column of the dirt top from
# game/art/ground.json pasted at the surface height, the dirt fill tiled below and a dark rect under
# it. Images are cached statically, so restarting the stage does not rebuild them.

const T := preload("res://game/moto/moto_tuning.gd")
const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")

const GROUND_JSON := "res://game/art/ground.json"
const GROUND_SEED := 1729

var points := PackedVector2Array()
var bounds := Rect2()
# Upward unit normal per segment (points[i] -> points[i + 1]).
var _normals := PackedVector2Array()
var _xs := PackedFloat32Array()

static var _art_cache: Array = []


func build() -> void:
	points = _fillet(T.TRACK_POINTS, T.TRACK_FILLET)
	_xs.resize(points.size())
	for i in points.size():
		_xs[i] = points[i].x
	_normals.resize(points.size() - 1)
	var top := INF
	for i in points.size() - 1:
		var t := (points[i + 1] - points[i]).normalized()
		_normals[i] = Vector2(t.y, -t.x)
		top = minf(top, points[i].y)
	top = minf(top, points[-1].y)
	bounds = Rect2(points[0].x, top - T.BOUNDS_ABOVE, points[-1].x - points[0].x, T.BOUNDS_ABOVE + T.BOUNDS_BELOW - top)
	bounds.size.y = T.BOUNDS_BELOW - bounds.position.y
	_build_collision()
	_build_art()


# Rounds each interior corner with an arc tangent to both segments (radius clamped so the tangent
# points stay within half of each segment).
static func _fillet(src: Array, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(src[0])
	for i in range(1, src.size() - 1):
		var p0: Vector2 = src[i - 1]
		var p1: Vector2 = src[i]
		var p2: Vector2 = src[i + 1]
		var d0 := (p0 - p1)
		var d1 := (p2 - p1)
		var l0 := d0.length()
		var l1 := d1.length()
		d0 /= l0
		d1 /= l1
		var turn := PI - acos(clampf(d0.dot(d1), -1.0, 1.0))
		if turn < 0.01:
			out.append(p1)
			continue
		var tan_len := radius * tan(turn * 0.5)
		var limit := minf(l0, l1) * 0.5
		var r := radius
		if tan_len > limit:
			tan_len = limit
			r = tan_len / tan(turn * 0.5)
		var a := p1 + d0 * tan_len
		var b := p1 + d1 * tan_len
		var bis := (d0 + d1).normalized()
		var center := p1 + bis * sqrt(r * r + tan_len * tan_len)
		var a0 := (a - center).angle()
		var a1 := (b - center).angle()
		var sweep := wrapf(a1 - a0, -PI, PI)
		var n := maxi(2, ceili(absf(sweep) / deg_to_rad(T.TRACK_FILLET_STEP_DEG)))
		for k in n + 1:
			out.append(center + Vector2.from_angle(a0 + sweep * k / n) * r)
	out.append(src[-1])
	return out


func _segment_at(x: float) -> int:
	var i := _xs.bsearch(x, true) - 1
	return clampi(i, 0, points.size() - 2)


func height_at(x: float) -> float:
	if x <= points[0].x:
		return points[0].y
	if x >= points[-1].x:
		return points[-1].y
	var i := _segment_at(x)
	var a := points[i]
	var b := points[i + 1]
	return lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))


# Surface angle in radians (positive going down to the right, like Node2D.rotation).
func slope_at(x: float) -> float:
	var i := _segment_at(x)
	return (points[i + 1] - points[i]).angle()


# Nearest surface point to p within reach: {hit, point, normal, dist}. dist is negative when p is
# under the surface; then the normal is the segment's own upward normal.
func probe(p: Vector2, reach: float) -> Dictionary:
	var i0 := _segment_at(p.x - reach)
	var i1 := _segment_at(p.x + reach)
	var best_d := INF
	var best_p := p
	var best_i := i0
	for i in range(i0, i1 + 1):
		var a := points[i]
		var ab := points[i + 1] - a
		var u := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * u
		var d := p.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best_p = q
			best_i = i
	var dist := sqrt(best_d)
	var normal: Vector2
	if p.y > height_at(p.x):
		dist = -dist
		normal = _normals[_segment_at(p.x)]
	elif dist > 0.001:
		normal = (p - best_p) / dist
	else:
		normal = _normals[best_i]
	return {hit = dist <= reach, point = best_p, normal = normal, dist = dist}


func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "TrackBody"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta(&"surface", &"dirt")
	# Never a grabbable wall (player._is_grab_wall needs wall_top above the head).
	body.set_meta(&"wall_top", INF)
	body.set_meta(&"wall_bottom", -INF)
	var poly := CollisionPolygon2D.new()
	var shape := PackedVector2Array(points)
	shape.append(Vector2(points[-1].x, T.BOUNDS_BELOW + T.DIRT_DEPTH))
	shape.append(Vector2(points[0].x, T.BOUNDS_BELOW + T.DIRT_DEPTH))
	poly.polygon = shape
	body.add_child(poly)
	add_child(body)


func _build_art() -> void:
	if _art_cache.is_empty():
		_art_cache = _make_art()
	for item in _art_cache:
		var s := Sprite2D.new()
		s.texture = item[0]
		s.centered = false
		s.position = item[1]
		s.scale = Vector2.ONE * GameScale.art_pixel()
		s.z_index = T.TRACK_Z
		add_child(s)
		var under := ColorRect.new()
		under.color = PixelArt.DIRT_DARK
		under.position = item[2]
		under.size = item[3]
		under.z_index = T.TRACK_Z
		add_child(under)


# [texture, sprite position, dark rect position, dark rect size] per block.
func _make_art() -> Array:
	var a := GameScale.art_pixel()
	var g := _ground_art(a)
	if g.is_empty():
		return []
	var tops: Array = g.tops
	var fills: Array = g.fills
	var tile_cols: int = g.tile_cols
	var surf_rows: int = g.surface_rows
	var top_rows: int = (tops[0] as Image).get_height()
	var fill_rows: int = (fills[0] as Image).get_height()
	var below := top_rows - surf_rows + T.TRACK_FILL_ROWS
	var col0 := floori(points[0].x / a)
	var col1 := ceili(points[-1].x / a)
	var rng := RandomNumberGenerator.new()
	var out: Array = []
	var c := col0
	while c < col1:
		var n := mini(T.TRACK_BLOCK_COLS, col1 - c)
		var surf := PackedInt32Array()
		surf.resize(n)
		var lo := 1 << 30
		var hi := -(1 << 30)
		for k in n:
			var s := roundi(height_at((c + k + 0.5) * a) / a)
			surf[k] = s
			lo = mini(lo, s)
			hi = maxi(hi, s)
		var row0 := lo - surf_rows
		var rows := hi + below - row0
		var img := Image.create(n, rows, false, Image.FORMAT_RGBA8)
		for k in n:
			var col := c + k
			var tile := floori(float(col) / tile_cols)
			rng.seed = hash([GROUND_SEED, tile])
			var v := rng.randi() % tops.size()
			var top: Image = tops[v]
			var fill: Image = fills[(v + absi(tile)) % fills.size()]
			var tx := posmod(col, tile_cols)
			var y0 := surf[k] - surf_rows - row0
			for r in top_rows:
				var px := top.get_pixel(tx, r)
				if px.a > 0.0:
					img.set_pixel(k, y0 + r, px)
			var fy := y0 + top_rows
			var r2 := 0
			while fy + r2 < rows:
				img.set_pixel(k, fy + r2, fill.get_pixel(tx % fill.get_width(), r2 % fill_rows))
				r2 += 1
		var tex := ImageTexture.create_from_image(img)
		var bottom := float((row0 + rows) * a)
		out.append([tex, Vector2(c * a, row0 * a), Vector2(c * a, bottom), Vector2(n * a, T.BOUNDS_BELOW + T.DIRT_DEPTH - bottom)])
		c += n
	return out


# Dirt tops and fills of ground.json at one texel per art pixel.
static func _ground_art(a: int) -> Dictionary:
	if not FileAccess.file_exists(GROUND_JSON):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROUND_JSON))
	if not data is Dictionary:
		return {}
	var tops: Array = []
	var fills: Array = []
	for v in data.variants:
		var top_path: String = v.get("top_dirt", v.get("top", ""))
		tops.append(_art_image(load(top_path) as Texture2D, a))
		fills.append(_art_image(load(v.fill) as Texture2D, a))
	return {tops = tops, fills = fills, tile_cols = int(data.tile_width) / a, surface_rows = int(data.surface_y) / a}


static func _art_image(texture: Texture2D, a: int) -> Image:
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
