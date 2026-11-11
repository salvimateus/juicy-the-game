extends RefCounted

# Terrain of the fog: a fine solid mask (sim and render clipping) and a coarse rest field
# (resting density plus height above the floor), built from the static colliders and the water.
# collect() / collect_region() run on the main thread (scene tree and water queries);
# compute() / compute_region() only touch this object, so they can run on a worker thread.

const MAX_TEX := 16384
# Rest field tuning, in world units.
const BAND := 175.0          # exponential decay length of the dense band
const FLAT := 12.0           # fully dense layer right above the floor
const H_MAX := 1150.0        # above this height over the floor the rest density is zero
const BASIN_MAX := 300.0     # deepest pooling a basin adds
const BASIN_FILL := 0.8      # how much of the basin depth the fog fills
const WALL_RISE := 620.0     # taller sides are walls, not basin rims
const HILL_FADE := 150.0     # floors raised above the surrounding ground keep exp(-rise / HILL_FADE)
const COVER_MAX := 420.0     # a ceiling closer than this covers the cell
const TUNNEL_SCALE := 0.3
const COVER_SCALE := 1.35
const WATER_BAND := 55.0      # decay of the thin blanket over water
const POCKET_MIN := 2.0        # slot width in cells with no rest fog
const POCKET_MAX := 5.0        # slot width from which the rest fog is full
const COVER_RUN_MIN := 6.0     # covered run (hole through a dam) with no rest fog
const COVER_RUN_MAX := 14.0    # covered run from which the rest fog is full (platforms are longer)
const BLUR := 5               # horizontal smoothing radius of the rest field, in cells
const REST_RANGE := 1.6      # rest density is stored as R / REST_RANGE

var mask_cell := 6.0
var rest_cell := 24.0
var bounds := Rect2()
var mask_image: Image
var rest_image: Image
var build_usec := 0
var collect_usec := 0

var dirty := Rect2()

var _rects: Array[Rect2] = []
# Per rect: true for ground (surface grass or dirt), whose art covers the fog base, so the visual
# front fog may sink deeper into it. The mask stores ground as SOFT and everything else as white.
var _soft: Array[bool] = []
var _cur_soft := false
var _polys: Array[PackedVector2Array] = []
var _water: Array[Rect2] = []
var _region := Rect2()
var _coarse: Image
var _water_img: Image
var _s := PackedByteArray()
var _wat := PackedByteArray()
var _cw := 0
var _ch := 0
var _floor_row := PackedInt32Array()
var _ceil_row := PackedInt32Array()
var _base := PackedInt32Array()
var _out := PackedByteArray()
var _raw := PackedByteArray()
var _pocket := PackedByteArray()


func collect(root: Node, art: float) -> bool:
	var t0 := Time.get_ticks_usec()
	_rects.clear()
	_soft.clear()
	_polys.clear()
	_water.clear()
	_region = Rect2()
	_walk(root)
	var box := Rect2()
	var first := true
	for r in _rects:
		box = r if first else box.merge(r)
		first = false
	for p in _polys:
		var pb := _poly_box(p)
		box = pb if first else box.merge(pb)
		first = false
	if first:
		return false
	for w in root.get_tree().get_nodes_in_group(&"water"):
		_collect_water(w, art)
	mask_cell = art * maxf(1.0, ceilf(maxf(box.size.x, box.size.y) / art / MAX_TEX))
	rest_cell = mask_cell * 4.0
	var x0 := floorf(box.position.x / rest_cell) * rest_cell
	var y0 := floorf(box.position.y / rest_cell) * rest_cell
	var x1 := ceilf(box.end.x / rest_cell) * rest_cell
	var y1 := ceilf(box.end.y / rest_cell) * rest_cell
	bounds = Rect2(x0, y0, x1 - x0, y1 - y0)
	collect_usec = Time.get_ticks_usec() - t0
	return true


func compute() -> void:
	var t0 := Time.get_ticks_usec()
	mask_image = _raster(mask_cell, true)
	_coarse = _raster(rest_cell, true)
	_water_img = Image.create_empty(_coarse.get_width(), _coarse.get_height(), false, Image.FORMAT_L8)
	for w in _water:
		_fill(_water_img, rest_cell, w)
	_cw = _coarse.get_width()
	_ch = _coarse.get_height()
	_s = _coarse.get_data()
	_wat = _water_img.get_data()
	var n := _cw * _ch
	_floor_row.resize(n)
	_ceil_row.resize(n)
	_base.resize(_cw)
	_out.resize(n * 2)
	_raw.resize(n)
	_pocket.resize(n)
	_scan(0, _cw)
	_rest(0, _cw)
	_blur(0, _cw)
	rest_image = Image.create_from_data(_cw, _ch, false, Image.FORMAT_RG8, _out)
	build_usec = Time.get_ticks_usec() - t0


## Gathers the colliders and water touching `rect` after a geometry change. False when the
## terrain was never built or the rect lies outside it.
func collect_region(root: Node, rect: Rect2, art: float) -> bool:
	if mask_image == null:
		return false
	var t0 := Time.get_ticks_usec()
	var r0 := floorf(rect.position.x / rest_cell) * rest_cell
	var r1 := ceilf(rect.end.x / rest_cell) * rest_cell
	var q0 := floorf(rect.position.y / rest_cell) * rest_cell
	var q1 := ceilf(rect.end.y / rest_cell) * rest_cell
	var region := Rect2(r0, q0, r1 - r0, q1 - q0).grow(rest_cell).intersection(bounds)
	if not region.has_area():
		return false
	_rects.clear()
	_soft.clear()
	_polys.clear()
	_water.clear()
	_region = region
	_walk(root)
	for w in root.get_tree().get_nodes_in_group(&"water"):
		_collect_water(w, art)
	dirty = region
	collect_usec = Time.get_ticks_usec() - t0
	return true


## Rasterizes the collected region again and recomputes the rest field of every column whose
## neighbourhood reaches it. Fog freed by a removed solid is left empty, so it flows back in.
func compute_region() -> void:
	var t0 := Time.get_ticks_usec()
	for pair in [[mask_image, mask_cell, true], [_coarse, rest_cell, false], [_water_img, rest_cell, false]]:
		var img: Image = pair[0]
		var cell: float = pair[1]
		var box := _texels(img, cell, _region)
		if box.size.x > 0 and box.size.y > 0:
			img.fill_rect(box, Color.BLACK)
	_fill_rects(mask_image, mask_cell, true)
	_fill_rects(_coarse, rest_cell, false)
	for p in _polys:
		_fill_poly(mask_image, mask_cell, p)
		_fill_poly(_coarse, rest_cell, p)
	for w in _water:
		_fill(mask_image, mask_cell, w)
		_fill(_coarse, rest_cell, w)
		_fill(_water_img, rest_cell, w)
	_s = _coarse.get_data()
	_wat = _water_img.get_data()
	var c0 := clampi(floori((_region.position.x - bounds.position.x) / rest_cell), 0, _cw)
	var c1 := clampi(ceili((_region.end.x - bounds.position.x) / rest_cell), 0, _cw)
	_scan(c0, c1)
	var reach := int(1000.0 / rest_cell)
	_rest(maxi(c0 - reach, 0), mini(c1 + reach, _cw))
	_blur(maxi(c0 - reach, 0), mini(c1 + reach, _cw))
	rest_image = Image.create_from_data(_cw, _ch, false, Image.FORMAT_RG8, _out)
	build_usec = Time.get_ticks_usec() - t0


func _texels(img: Image, cell: float, r: Rect2) -> Rect2i:
	var i0 := roundi((r.position.x - bounds.position.x) / cell)
	var i1 := roundi((r.end.x - bounds.position.x) / cell)
	var j0 := roundi((r.position.y - bounds.position.y) / cell)
	var j1 := roundi((r.end.y - bounds.position.y) / cell)
	return Rect2i(i0, j0, i1 - i0, j1 - j0).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))


func _walk(node: Node) -> void:
	if node is StaticBody2D and not node is AnimatableBody2D and (node.collision_layer & 1) != 0:
		var surface: StringName = node.get_meta(&"surface", &"")
		_cur_soft = surface == &"grass" or surface == &"dirt"
		for child in node.get_children():
			_collect_shape(child)
	for child in node.get_children():
		_walk(child)


func _add_poly(p: PackedVector2Array) -> void:
	if not _region.has_area() or _poly_box(p).intersects(_region):
		_polys.append(p)


func _collect_shape(node: Node) -> void:
	if node is CollisionShape2D:
		var cs := node as CollisionShape2D
		if cs.disabled or cs.shape == null:
			return
		var xf := cs.global_transform
		var shape := cs.shape
		if shape is RectangleShape2D:
			var h: Vector2 = shape.size * 0.5
			if absf(xf.x.y) < 0.0001 and absf(xf.y.x) < 0.0001:
				var a := xf * -h
				var b := xf * h
				var box := Rect2(a, Vector2.ZERO).expand(b)
				if not _region.has_area() or box.intersects(_region):
					_rects.append(box)
					_soft.append(_cur_soft)
			else:
				_add_poly(PackedVector2Array([xf * Vector2(-h.x, -h.y), xf * Vector2(h.x, -h.y), xf * Vector2(h.x, h.y), xf * Vector2(-h.x, h.y)]))
		elif shape is ConvexPolygonShape2D:
			_add_poly(xf * (shape as ConvexPolygonShape2D).points)
		elif shape is CircleShape2D or shape is CapsuleShape2D:
			var r := shape.get_rect()
			_add_poly(PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)]))
	elif node is CollisionPolygon2D:
		var cp := node as CollisionPolygon2D
		if not cp.disabled and cp.build_mode == CollisionPolygon2D.BUILD_SOLIDS and cp.polygon.size() >= 3:
			_add_poly(cp.global_transform * cp.polygon)


func _collect_water(w: Node, art: float) -> void:
	if not (w is Node2D and w.has_method(&"get_surface_y") and "domain" in w):
		return
	if w.has_method(&"is_ready") and not w.is_ready():
		return
	var d: Rect2 = w.domain
	var g := Rect2((w as Node2D).global_position + d.position, d.size)
	if _region.has_area():
		g = g.intersection(_region)
		if not g.has_area():
			return
	var x := floorf(g.position.x / art) * art + art * 0.5
	while x < g.end.x:
		var sy: float = w.get_surface_y(x, g.position.y)
		if sy < g.end.y:
			_water.append(Rect2(x - art * 0.5, sy, art, g.end.y - sy))
		x += art


func _poly_box(p: PackedVector2Array) -> Rect2:
	var r := Rect2(p[0], Vector2.ZERO)
	for v in p:
		r = r.expand(v)
	return r


func _raster(cell: float, with_water: bool) -> Image:
	var w := int(bounds.size.x / cell)
	var h := int(bounds.size.y / cell)
	var img := Image.create_empty(w, h, false, Image.FORMAT_L8)
	_fill_rects(img, cell, with_water)
	for p in _polys:
		_fill_poly(img, cell, p)
	if with_water:
		for r in _water:
			_fill(img, cell, r)
	return img


const SOFT := Color(0.6, 0.6, 0.6)


# Ground first, so a hard solid overlapping it wins.
func _fill_rects(img: Image, cell: float, fine: bool) -> void:
	for k in _rects.size():
		if _soft[k]:
			_fill(img, cell, _rects[k], SOFT if fine else Color.WHITE)
	for k in _rects.size():
		if not _soft[k]:
			_fill(img, cell, _rects[k])


# A cell is solid when its centre lies inside the shape.
func _fill(img: Image, cell: float, r: Rect2, value := Color.WHITE) -> void:
	var box := _texels(img, cell, r)
	if box.size.x > 0 and box.size.y > 0:
		img.fill_rect(box, value)


func _fill_poly(img: Image, cell: float, p: PackedVector2Array) -> void:
	var pb := _poly_box(p)
	var j0 := maxi(0, floori((pb.position.y - bounds.position.y) / cell))
	var j1 := mini(img.get_height(), ceili((pb.end.y - bounds.position.y) / cell))
	var xs := PackedFloat32Array()
	var n := p.size()
	for j in range(j0, j1):
		var y := bounds.position.y + (j + 0.5) * cell
		xs.clear()
		for k in n:
			var a := p[k]
			var b := p[(k + 1) % n]
			if (a.y <= y) != (b.y <= y):
				xs.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			var i0 := clampi(roundi((xs[k] - bounds.position.x) / cell), 0, img.get_width())
			var i1 := clampi(roundi((xs[k + 1] - bounds.position.x) / cell), 0, img.get_width())
			if i1 > i0:
				img.fill_rect(Rect2i(i0, j, i1 - i0, 1), Color.WHITE)


# Rest field: R = rest density / REST_RANGE, G = height above the floor / H_MAX.
# Dense right above every floor, decaying exponentially; basins pool more fog up to their rim,
# covered cells (under platforms) get more, long covers (tunnels) less, water floors more.
func _scan(c0: int, c1: int) -> void:
	var cw := _cw
	var ch := _ch
	var none := ch + 100000
	for c in range(c0, c1):
		# Deepest open floor of each column: the floor under its lowest air cell.
		var fl := none
		var deepest := -1
		var i := (ch - 1) * cw + c
		for r in range(ch - 1, -1, -1):
			if _s[i] != 0:
				fl = r
			elif fl != none:
				deepest = maxi(deepest, fl)
			_floor_row[i] = fl
			i -= cw
		_base[c] = deepest
		# Air cells: nearest solid row above. Solid cells: top row of their solid run.
		var ce := -100000
		var run_top := 0
		i = c
		for r in ch:
			if _s[i] != 0:
				if ce != r - 1:
					run_top = r
				ce = r
				_ceil_row[i] = run_top
			else:
				_ceil_row[i] = ce
			i += cw


func _rest(c0: int, c1: int) -> void:
	var cw := _cw
	var ch := _ch
	var s := _s
	var wat := _wat
	var floor_row := _floor_row
	var ceil_row := _ceil_row
	var base := _base
	var cell := rest_cell
	var h_rows := int(H_MAX / cell)
	var cover_rows := int(COVER_MAX / cell)
	var basin_rows := int(BASIN_MAX / cell)
	var step := maxi(1, int(168.0 / cell))
	var offs := PackedInt32Array([step, step * 2, step * 3])
	var hill_offs := PackedInt32Array([step, step * 2, step * 3, step * 4])
	var half := maxi(1, step / 2)
	var basin_offs := PackedInt32Array([half, half * 2, half * 3, half * 4, half * 5, half * 6])
	var wall_rows := int(WALL_RISE / cell)
	for c in range(c0, c1):
		for r in ch:
			var i := r * cw + c
			_pocket[i] = 255
			if s[i] != 0:
				_raw[i] = _raw[i - cw] if r > 0 else 0
				_out[i * 2 + 1] = 0
				continue
			var fr := floor_row[i]
			var hr := fr - r
			if hr > h_rows:
				_raw[i] = 0
				_out[i * 2 + 1] = 255
				continue
			var h := (hr - 0.5) * cell
			# Basin depth: how far the floor sits below the surface on each side, weighted down
			# with distance so the pooled fog has no hard vertical edges. Rises taller than
			# WALL_RISE are walls or pillars, not the rim of a dip, and do not pool fog.
			var rise_l := 0.0
			var rise_r := 0.0
			for k in basin_offs.size():
				var o := basin_offs[k]
				var wk := 1.0 - 0.6 * k / basin_offs.size()
				if c - o >= 0:
					rise_l = maxf(rise_l, _rise(s, floor_row, ceil_row, i - o, fr, wall_rows) * wk)
				if c + o < cw:
					rise_r = maxf(rise_r, _rise(s, floor_row, ceil_row, i + o, fr, wall_rows) * wk)
			var basin := minf(minf(rise_l, rise_r), basin_rows) * cell
			# Hill: how far this floor sits above the deepest floors on both sides (tower tops,
			# floating platforms); fog stays low, so raised floors get little of it.
			var drop_l := 0
			var drop_r := 0
			for o in hill_offs:
				if c - o >= 0:
					drop_l = maxi(drop_l, base[c - o] - fr)
				if c + o < cw:
					drop_r = maxi(drop_r, base[c + o] - fr)
			var hill := maxi(mini(drop_l, drop_r), 0) * cell
			var covered := r - ceil_row[i] <= cover_rows
			var tunnel := 0.0
			if covered:
				var hits := 0
				for o in offs:
					if c - o >= 0 and s[i - o] == 0 and r - ceil_row[i - o] <= cover_rows:
						hits += 1
					if c + o < cw and s[i + o] == 0 and r - ceil_row[i + o] <= cover_rows:
						hits += 1
				tunnel = clampf((hits - 3.5) / 2.5, 0.0, 1.0)
			var on_water := fr < ch and wat[fr * cw + c] != 0
			var d := 0.0
			if on_water:
				# Over water: a thin low blanket right above the surface, no basin pooling.
				d = 1.0 if h < FLAT else exp(-(h - FLAT) / WATER_BAND)
			else:
				var band := BAND * (1.0 + 0.35 * basin / BASIN_MAX)
				var he := maxf(h - basin * BASIN_FILL, 0.0)
				d = 1.0 if he < FLAT else exp(-(he - FLAT) / band)
				d *= (1.0 + 0.2 * basin / BASIN_MAX) * exp(-hill / HILL_FADE)
			if covered:
				d *= lerpf(COVER_SCALE, TUNNEL_SCALE, tunnel)
			_raw[i] = clampi(roundi(d / REST_RANGE * 255.0), 0, 255)
			# Pockets: a narrow slot between solids, or a short covered hole (through a dam), keeps
			# almost no rest fog, fading in over POCKET_MIN..POCKET_MAX cells. Long covers (under
			# platforms, tunnels) are not pockets.
			var open_k := smoothstep(POCKET_MIN, POCKET_MAX, _width(s, row_start(r), c, int(POCKET_MAX) + 1))
			if covered:
				open_k = minf(open_k, smoothstep(COVER_RUN_MIN, COVER_RUN_MAX, _cover_run(s, ceil_row, r, c, cover_rows, int(COVER_RUN_MAX) + 1)))
			_pocket[i] = clampi(roundi(open_k * 255.0), 0, 255)
			# G: height above the floor, so the front strip stays at the shins even in basins.
			_out[i * 2 + 1] = clampi(roundi(h / H_MAX * 255.0), 0, 255)


func _rise(s: PackedByteArray, floor_row: PackedInt32Array, ceil_row: PackedInt32Array, j: int, fr: int, wall_rows: int) -> float:
	var surface := ceil_row[j] if s[j] != 0 else floor_row[j]
	var rise := fr - mini(surface, fr)
	return 0.0 if rise > wall_rows else float(rise)


# Horizontal moving average of the rest density over open cells, so no terrain edge (step,
# platform end, valley rim) leaves a vertical seam in the fog. Solid cells keep their value.
func _blur(c0: int, c1: int) -> void:
	var cw := _cw
	for r in _ch:
		var row := r * cw
		var a0 := maxi(c0 - BLUR, 0)
		var sum := 0
		var cnt := 0
		for j in range(a0, mini(c0 + BLUR + 1, cw)):
			if _s[row + j] == 0:
				sum += _raw[row + j]
				cnt += 1
		for c in range(c0, c1):
			var i := row + c
			_out[i * 2] = _raw[i] if _s[i] != 0 or cnt == 0 else ((sum + cnt / 2) / cnt) * _pocket[i] / 255
			var add := c + BLUR + 1
			if add < cw and _s[row + add] == 0:
				sum += _raw[row + add]
				cnt += 1
			var drop := c - BLUR
			if drop >= 0 and _s[row + drop] == 0:
				sum -= _raw[row + drop]
				cnt -= 1


func row_start(r: int) -> int:
	return r * _cw


# Open run of air cells through column c of the row starting at index row, capped at cap.
func _width(s: PackedByteArray, row: int, c: int, cap: int) -> int:
	var w := 1
	var j := c - 1
	while j >= 0 and s[row + j] == 0 and w < cap:
		w += 1
		j -= 1
	j = c + 1
	while j < _cw and s[row + j] == 0 and w < cap:
		w += 1
		j += 1
	return w


# Run of covered air cells (ceiling within cover_rows) through column c of row r, capped at cap.
func _cover_run(s: PackedByteArray, ceil_row: PackedInt32Array, r: int, c: int, cover_rows: int, cap: int) -> int:
	var row := r * _cw
	var w := 1
	var j := c - 1
	while j >= 0 and s[row + j] == 0 and r - ceil_row[row + j] <= cover_rows and w < cap:
		w += 1
		j -= 1
	j = c + 1
	while j < _cw and s[row + j] == 0 and r - ceil_row[row + j] <= cover_rows and w < cap:
		w += 1
		j += 1
	return w
