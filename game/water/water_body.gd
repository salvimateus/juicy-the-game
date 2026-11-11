class_name WaterBody
extends Node2D

# Water over a rectangular domain: a shallow-water heightfield (virtual pipes between columns,
# momentum per edge, exact volume bookkeeping) plus orifices for passages under the terrain
# (Torricelli outflow, equalizes like communicating vessels) and ballistic parcels that carry the
# volume of jets and cascades until they land. The terrain comes from the static colliders inside
# the domain, rasterized into a solid mask. On top: per-art-pixel-column springs for ripples,
# pooled splash drops and bubbles, and a pixel-art shader fed by one texel per art-pixel column.
# Units: 1 = 1 source px, y down. Every public method takes and returns global coordinates.

signal rasterized

const Particles := preload("res://game/water/water_particles.gd")
const SHADER := preload("res://game/water/water.gdshader")
const Feedback := preload("res://game/feedback.gd")

const GROUP := &"water"
const ART := 6
# Below this depth (units) a column counts as dry for queries and rendering.
const WET := 1.5
# A flow edge whose downstream surface sits this far below the lip spills as falling parcels.
const CLIFF := 60.0
const PARCEL_VOL := 90.0
const PARCEL_MIN := 24.0
const MAX_SUBSTEPS := 16

@export var domain := Rect2(-120, -288, 3216, 1200)
# Simulation column width; a multiple of the art pixel.
@export var cell := 12
@export var gravity := 2600.0
@export_flags_2d_physics var solid_mask := 0xFFFFFFFF
# Discharge coefficient of the orifices (sharp-edged hole ~0.6).
@export var orifice_coefficient := 0.62
# Seconds for a newly detected orifice to reach full aperture (the plug crumbling away).
@export var orifice_ramp := 0.35
# Linear damping of the edge fluxes, 1/s.
@export var flux_damping := 0.25
# Fraction of the neighbour flux difference blended in per substep (0..0.25).
@export var viscosity := 0.12
# Splash, buoyancy and waves for RigidBody2D/CharacterBody2D crossing the surface.
@export var auto_bodies := true
@export var buoyancy := 1.6
@export var draw_z := 40
# Reference flow (units^2/s) for loop strength 1 of the flow sound and rumble.
@export var flow_reference := 90000.0


class Orifice:
	var left_col := 0
	var right_col := 0
	var top := 0.0
	var bottom := 0.0
	var x_left := 0.0
	var x_right := 0.0
	var open := 0.0
	# Signed volume rate, positive left to right.
	var q := 0.0
	var spill := 0.0
	var jet_speed := 0.0
	var jet_dir := 1
	var wet_top := INF


var cols := 0
var rows := 0
var rcols := 0
var orifices: Array[Orifice] = []
# Diagnostics of the last physics tick.
var last_step_usec := 0
var max_step_usec := 0
var last_substeps := 0
var last_render_usec := 0
var active_columns := 0

var _solid := PackedByteArray()
var _bed := PackedFloat32Array()
var _depth := PackedFloat32Array()
var _rest := PackedFloat32Array()
var _flux := PackedFloat32Array()
var _evel := PackedFloat32Array()
var _spill := PackedFloat32Array()
var _rbed := PackedFloat32Array()
var _sh := PackedFloat32Array()
var _sv := PackedFloat32Array()
var _foam := PackedFloat32Array()
var _data := PackedByteArray()
var _img: Image
var _tex: ImageTexture
var _rect: ColorRect
var _mat: ShaderMaterial
var _tunnels := PackedVector4Array()
var _origin := Vector2.ZERO
var _ready_sim := false
var _awake := false
var _idle := 0
var _springs_awake := false
var _render_dirty := true
var _pending_fills: Array = []
var _restore_from := PackedFloat32Array()
var _restore_t := -1.0
var _restore_len := 0.6
var _restore_rise := 0.0
var _restore_drop := 0.0
var _rng := RandomNumberGenerator.new()
var _query := PhysicsPointQueryParameters2D.new()
var _ray := PhysicsRayQueryParameters2D.new()

var _drops: Particles
var _parcels: Particles
var _bubbles: Particles
var _rings: Particles
var _pops: Particles
var _all_pools: Array[Particles] = []
var _bubble_pools: Array[Particles] = []

var _bodies: Array[Node2D] = []
var _body_wet := PackedByteArray()
var _disturb_cd := 0.0
var _bubble_sfx_cd := 0.0
var _flow_handle := -1
var _rumble_handle := -1
var _flow_quiet := 0.0
var _flow_rate := 0.0
var _flow_at := Vector2.ZERO
var _volume_clamped := 0.0


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_rng.seed = 7151
	cols = int(domain.size.x) / cell
	rows = int(domain.size.y) / cell
	rcols = int(domain.size.x) / ART
	assert(int(domain.size.y) / ART < 255, "domain too tall for the byte rows of the shader")
	_solid.resize(cols * rows)
	_bed.resize(cols); _depth.resize(cols); _rest.resize(cols)
	_flux.resize(cols + 1); _evel.resize(cols + 1); _spill.resize(cols + 1)
	_rbed.resize(rcols); _sh.resize(rcols); _sv.resize(rcols); _foam.resize(rcols)
	_data.resize(rcols * 4)
	_bed.fill(domain.end.y)
	_rbed.fill(domain.end.y)
	_img = Image.create(rcols, 1, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	_build_render()
	_build_particles()
	if auto_bodies:
		_build_area()
	_query.collide_with_areas = false
	_query.collide_with_bodies = true
	_query.collision_mask = solid_mask
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	_ray.collision_mask = solid_mask
	_ray.hit_from_inside = true
	_origin = global_position
	_initial_rasterize.call_deferred()


func _initial_rasterize() -> void:
	await get_tree().physics_frame
	rasterize()
	_ready_sim = true
	for f in _pending_fills:
		fill_level(f[0], f[1], f[2])
	_pending_fills.clear()
	rasterized.emit()


func is_ready() -> bool:
	return _ready_sim


# --- Public API -----------------------------------------------------------------------------------

func is_point_in_water(global_pos: Vector2) -> bool:
	var p := global_pos - _origin
	if _in_tunnel(p) >= 0:
		return true
	var s := _surface_local(p.x)
	return s != INF and p.y >= s and p.y <= _rbed_at(p.x) + 2.0


# Water surface over the column at global_x, or INF when that column is dry or near_y is
# underground there. Inside a flooded passage it returns the passage's water top.
func get_surface_y(global_x: float, near_y: float) -> float:
	var p := Vector2(global_x, near_y) - _origin
	var t := _in_tunnel(p)
	if t >= 0:
		return orifices[t].wet_top + _origin.y
	var s := _surface_local(p.x)
	if s == INF or p.y > _rbed_at(p.x) + 48.0:
		return INF
	return s + _origin.y


func get_submerged_ratio(rect: Rect2) -> float:
	if rect.size.y <= 0.0:
		return 0.0
	var r := Rect2(rect.position - _origin, rect.size)
	var n := clampi(int(r.size.x / ART), 1, 16)
	var step := r.size.x / n
	var sum := 0.0
	for i in n:
		var x := r.position.x + step * (i + 0.5)
		var t := _in_tunnel(Vector2(x, r.position.y + r.size.y * 0.5))
		var s := orifices[t].wet_top if t >= 0 else _surface_local(x)
		if s == INF:
			continue
		var bottom := minf(r.end.y, orifices[t].bottom if t >= 0 else _rbed_at(x))
		sum += clampf((bottom - maxf(r.position.y, s)) / r.size.y, 0.0, 1.0)
	return sum / n


# Current velocity of the water at a point (units/s), zero outside the water. Near a flowing
# orifice it also pulls toward the inlet.
func get_flow_at(global_pos: Vector2) -> Vector2:
	var p := global_pos - _origin
	var flow := Vector2.ZERO
	var t := _in_tunnel(p)
	if t >= 0:
		var o := orifices[t]
		return Vector2(o.jet_speed * signf(o.q) * 0.6, 0.0) if absf(o.q) > 1.0 else Vector2.ZERO
	if not is_point_in_water(global_pos):
		return flow
	var c := _col(p.x)
	flow.x = clampf((_evel[c] + _evel[c + 1]) * 0.5, -1200.0, 1200.0)
	for o in orifices:
		if absf(o.q) < 100.0:
			continue
		var inlet := Vector2(o.x_left if o.q > 0.0 else o.x_right, clampf(p.y, o.wet_top, o.bottom))
		var d := inlet - p
		var dist := d.length()
		if dist < 320.0 and dist > 1.0:
			flow += d / dist * minf(o.jet_speed * 0.45, 700.0) * (1.0 - dist / 320.0) * o.open
		# Drawdown drift: the surface of a draining pool runs toward the outlet from far away.
		if dist < 1400.0:
			flow.x += signf(d.x) * 190.0 * minf(absf(o.q) / flow_reference, 1.0) * (1.0 - dist / 1400.0) * o.open
	return flow


# Waves (and a small splash when it is fast at the surface) from a body moving at global_pos.
func apply_disturbance(global_pos: Vector2, velocity: Vector2) -> void:
	if not _ready_sim:
		return
	var p := global_pos - _origin
	var s := _surface_local(p.x)
	if s == INF:
		return
	var near := absf(p.y - s)
	var c := _col(p.x)
	var push := clampf(velocity.x * 0.12, -400.0, 400.0) * minf(_depth[c], 160.0) / 160.0
	_flux[c] += push
	_flux[c + 1] += push
	_awake = true
	_idle = 0
	if near > 90.0:
		return
	var fall := 1.0 - near / 90.0
	var j := _rcol(p.x)
	for k in range(-3, 4):
		var jj := j + k
		if jj >= 0 and jj < rcols:
			_sv[jj] += clampf(velocity.y * 0.3, -420.0, 420.0) * fall * (1.0 - absf(k) / 4.0)
	_springs_awake = true
	var speed := velocity.length()
	if speed > 650.0 and near < 40.0 and _disturb_cd <= 0.0:
		_disturb_cd = 0.12
		emit_splash(Vector2(global_pos.x, s + _origin.y), clampf((speed - 500.0) / 2000.0, 0.1, 0.5))


func emit_bubbles(global_pos: Vector2, count: int, velocity: Vector2 = Vector2.ZERO) -> void:
	var p := global_pos - _origin
	for i in count:
		var big := _rng.randf() < 0.3
		var pool := _rings if big else _bubbles
		pool.spawn(p.x + _rng.randf_range(-12.0, 12.0), p.y + _rng.randf_range(-12.0, 12.0),
			velocity.x * 0.4 + _rng.randf_range(-40.0, 40.0), velocity.y * 0.4 - _rng.randf_range(40.0, 140.0),
			_rng.randf_range(4.0, 8.0), 1, _rng.randi_range(0, pool.palette.size() - 1), _rng.randf() * TAU)


func emit_splash(global_pos: Vector2, strength: float) -> void:
	var s := clampf(strength, 0.05, 1.5)
	var p := global_pos - _origin
	var n := int(5 + 24 * s)
	for i in n:
		var size := 2 if (s > 0.6 and _rng.randf() < 0.25) else 1
		_drops.spawn(p.x + _rng.randf_range(-18.0, 18.0), p.y - 6.0,
			_rng.randf_range(-1.0, 1.0) * (110.0 + 300.0 * s), -_rng.randf_range(260.0, 420.0 + 820.0 * s),
			2.0, size, _rng.randi_range(0, 2))
	var j := _rcol(p.x)
	var radius := int(2 + 7 * s)
	for k in range(-radius, radius + 1):
		var jj := j + k
		if jj < 0 or jj >= rcols:
			continue
		var f := 1.0 - absf(k) / float(radius + 1)
		_sv[jj] += 330.0 * s * f
		_foam[jj] = minf(1.0, _foam[jj] + 0.7 * s * f)
	_springs_awake = true
	_render_dirty = true
	Feedback.sfx(&"splash", global_pos, minf(s, 1.0))
	if s > 0.45:
		emit_bubbles(global_pos + Vector2(0, 30), int(4 + 8 * s), Vector2(0, 120))


# --- Volume management ----------------------------------------------------------------------------

# Fills every column in [x0, x1) whose bed lies below level_y up to that level.
func fill_level(global_x0: float, global_x1: float, global_level_y: float) -> void:
	if not _ready_sim:
		_pending_fills.append([global_x0, global_x1, global_level_y])
		return
	var level := global_level_y - _origin.y
	for c in range(_col(global_x0 - _origin.x), _col(global_x1 - _origin.x - 1.0) + 1):
		if _bed[c] > level:
			_depth[c] = _bed[c] - level
	_awake = true
	_idle = 0
	_render_dirty = true


func store_rest_state() -> void:
	_rest = _depth.duplicate()


# Blends the water back to the stored rest state over `duration` seconds.
func restore_rest_state(duration := 0.6) -> void:
	_parcels.clear()
	_drops.clear()
	_flux.fill(0.0)
	_spill.fill(0.0)
	for o in orifices:
		o.spill = 0.0
		o.q = 0.0
	_restore_from = _depth.duplicate()
	_restore_rise = 0.0
	_restore_drop = 0.0
	for c in cols:
		_restore_rise = maxf(_restore_rise, _rest[c] - _depth[c])
		_restore_drop = maxf(_restore_drop, _depth[c] - _rest[c])
	_restore_len = maxf(0.05, duration)
	_restore_t = 0.0
	_awake = true


func get_total_volume() -> float:
	var v := 0.0
	for c in cols:
		v += _depth[c]
	v *= cell
	for i in _parcels.count:
		v += _parcels.aux[i]
	for e in _spill.size():
		v += _spill[e]
	for o in orifices:
		v += o.spill
	return v


func get_volume_clamped() -> float:
	return _volume_clamped


# The flowing orifice whose inlet is nearest to global_pos within radius, as a dictionary with
# global `inlet` (centre of the upstream face), `outlet`, `top`, `bottom`, `x_in`, `x_out`, `dir`
# (+1 flows right) and `speed` (jet speed); empty when none flows.
func get_active_orifice_near(global_pos: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for o in orifices:
		if absf(o.q) < 100.0:
			continue
		var dir := 1 if o.q > 0.0 else -1
		var x_in := o.x_left if dir > 0 else o.x_right
		var x_out := o.x_right if dir > 0 else o.x_left
		var inlet := _origin + Vector2(x_in, (o.top + o.bottom) * 0.5)
		var d := global_pos.distance_to(inlet)
		if d < best_d:
			best_d = d
			best = {inlet = inlet, outlet = _origin + Vector2(x_out, (o.top + o.bottom) * 0.5),
				top = o.top + _origin.y, bottom = o.bottom + _origin.y, x_in = x_in + _origin.x,
				x_out = x_out + _origin.x, dir = dir, speed = o.jet_speed}
	return best


func get_flow_rate() -> float:
	return _flow_rate


func get_floor_y(global_x: float) -> float:
	return _rbed_at(global_x - _origin.x) + _origin.y


func get_depth_at(global_x: float) -> float:
	var c := _col(global_x - _origin.x)
	return _depth[c]


func parcel_count() -> int:
	return _parcels.count


func particle_count() -> int:
	return _parcels.count + _drops.count + _bubbles.count + _rings.count + _pops.count


# --- Terrain --------------------------------------------------------------------------------------

# Re-reads the static colliders in rect (global; empty = whole domain) into the solid mask and
# rebuilds the beds and orifices. Call it after the terrain changes, once the physics server has
# the change (one physics frame after toggling a shape).
func rasterize(global_rect := Rect2()) -> void:
	var t0 := Time.get_ticks_usec()
	_origin = global_position
	var space := get_world_2d().direct_space_state
	var c0 := 0
	var c1 := cols
	var r0 := 0
	var r1 := rows
	if global_rect.has_area():
		var lr := Rect2(global_rect.position - _origin - domain.position, global_rect.size)
		c0 = clampi(floori(lr.position.x / cell), 0, cols)
		c1 = clampi(ceili(lr.end.x / cell), 0, cols)
		r0 = clampi(floori(lr.position.y / cell), 0, rows)
		r1 = clampi(ceili(lr.end.y / cell), 0, rows)
	var base := _origin + domain.position + Vector2.ONE * (cell * 0.5)
	for r in range(r0, r1):
		for c in range(c0, c1):
			_query.position = base + Vector2(c * cell, r * cell)
			_solid[r * cols + c] = 1 if _hits_static(space.intersect_point(_query, 8)) else 0
	for c in range(c0, c1):
		var bed := domain.end.y
		for r in rows:
			if _solid[r * cols + c] == 1:
				bed = domain.position.y + r * cell
				break
		_bed[c] = bed
		if _depth[c] > 0.0 and bed < domain.position.y + 1.0:
			_depth[c] = 0.0
	var j0 := c0 * cell / ART
	var j1 := c1 * cell / ART
	for j in range(j0, j1):
		_rbed[j] = _ray_floor(space, domain.position.x + (j + 0.5) * ART)
	_detect_orifices()
	_awake = true
	_idle = 0
	_render_dirty = true
	print("WATER rasterize cells=%d usec=%d orifices=%d" % [(c1 - c0) * (r1 - r0), Time.get_ticks_usec() - t0, orifices.size()])


func _hits_static(hits: Array) -> bool:
	for h in hits:
		var o: Object = h.collider
		if o is StaticBody2D or o is TileMapLayer:
			return true
	return false


func _ray_floor(space: PhysicsDirectSpaceState2D, x: float) -> float:
	var exclude: Array[RID] = []
	_ray.from = _origin + Vector2(x, domain.position.y)
	_ray.to = _origin + Vector2(x, domain.end.y)
	for attempt in 6:
		_ray.exclude = exclude
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			return domain.end.y
		if hit.collider is StaticBody2D or hit.collider is TileMapLayer:
			return hit.position.y - _origin.y
		exclude.append(hit.rid)
	return domain.end.y


# Air pockets under the beds that open sideways into two columns become orifices.
func _detect_orifices() -> void:
	var old := orifices
	orifices = []
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var stack := PackedInt32Array()
	for start in cols * rows:
		if seen[start] == 1 or not _is_pocket(start):
			continue
		var lo_col := cols
		var hi_col := -1
		var lo_rows := Vector2i(rows, -1)
		var hi_rows := Vector2i(rows, -1)
		stack.clear()
		stack.append(start)
		seen[start] = 1
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var c := i % cols
			var r := i / cols
			for side in [-1, 1]:
				var nc: int = c + side
				if nc < 0 or nc >= cols:
					continue
				if _is_open(nc, r):
					if nc < lo_col:
						lo_col = nc
						lo_rows = Vector2i(r, r)
					elif nc == lo_col:
						lo_rows = Vector2i(mini(lo_rows.x, r), maxi(lo_rows.y, r))
					if nc > hi_col:
						hi_col = nc
						hi_rows = Vector2i(r, r)
					elif nc == hi_col:
						hi_rows = Vector2i(mini(hi_rows.x, r), maxi(hi_rows.y, r))
			for n in [i - 1, i + 1, i - cols, i + cols]:
				if n < 0 or n >= cols * rows:
					continue
				if (n == i - 1 and c == 0) or (n == i + 1 and c == cols - 1):
					continue
				if seen[n] == 0 and _is_pocket(n):
					seen[n] = 1
					stack.append(n)
		if hi_col <= lo_col or lo_col == cols:
			continue
		var o := Orifice.new()
		o.left_col = lo_col
		o.right_col = hi_col
		o.top = domain.position.y + maxi(lo_rows.x, hi_rows.x) * cell
		o.bottom = domain.position.y + (mini(lo_rows.y, hi_rows.y) + 1) * cell
		if o.bottom <= o.top:
			continue
		o.x_left = domain.position.x + (lo_col + 1) * cell
		o.x_right = domain.position.x + hi_col * cell
		for prev in old:
			if prev.left_col == o.left_col and prev.right_col == o.right_col:
				o.open = prev.open
		orifices.append(o)


func _is_pocket(i: int) -> bool:
	var c := i % cols
	var r := i / cols
	return _solid[i] == 0 and domain.position.y + (r + 0.5) * cell > _bed[c]


func _is_open(c: int, r: int) -> bool:
	return _solid[r * cols + c] == 0 and domain.position.y + (r + 0.5) * cell < _bed[c]


# --- Helpers --------------------------------------------------------------------------------------

func _col(local_x: float) -> int:
	return clampi(floori((local_x - domain.position.x) / cell), 0, cols - 1)


func _rcol(local_x: float) -> int:
	return clampi(floori((local_x - domain.position.x) / ART), 0, rcols - 1)


func _rbed_at(local_x: float) -> float:
	return _rbed[_rcol(local_x)]


# Simulated surface (interpolated between wet column centres) plus the ripple springs; INF if dry.
func _surface_local(local_x: float) -> float:
	var fx := (local_x - domain.position.x) / cell - 0.5
	var c := clampi(floori(fx + 0.5), 0, cols - 1)
	if _depth[c] < WET:
		return INF
	var s := _bed[c] - _depth[c]
	var t := fx - c
	var n := c + (1 if t > 0.0 else -1)
	if n >= 0 and n < cols and _depth[n] >= WET:
		s = lerpf(s, _bed[n] - _depth[n], absf(t))
	return s + _sh[_rcol(local_x)]


func _in_tunnel(p: Vector2) -> int:
	for i in orifices.size():
		var o := orifices[i]
		if o.wet_top != INF and p.x >= o.x_left and p.x < o.x_right and p.y >= o.wet_top and p.y < o.bottom:
			return i
	return -1


# --- Simulation -----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _ready_sim:
		return
	var t0 := Time.get_ticks_usec()
	_origin = global_position
	_disturb_cd -= delta
	_bubble_sfx_cd -= delta
	if auto_bodies:
		_track_bodies(delta)
	if _restore_t >= 0.0:
		_step_restore(delta)
	elif _awake:
		_step_water(delta)
	_step_parcels(delta)
	_step_drops(delta)
	_step_bubbles(delta)
	_step_springs(delta)
	_update_audio(delta)
	last_step_usec = Time.get_ticks_usec() - t0
	max_step_usec = maxi(max_step_usec, last_step_usec)


func _step_water(delta: float) -> void:
	var hmax := 1.0
	for c in cols:
		hmax = maxf(hmax, _depth[c])
	var n := clampi(ceili(delta * sqrt(gravity * hmax) * 2.2 / cell), 1, MAX_SUBSTEPS)
	last_substeps = n
	var dt := delta / n
	var damp := 1.0 - flux_damping * dt
	var inv := 1.0 / cell
	# Own the arrays locally for the hot loop (no copy-on-write against the members).
	var depth := _depth
	_depth = PackedFloat32Array()
	var bed := _bed
	var flux := _flux
	_flux = PackedFloat32Array()
	var evel := _evel
	_evel = PackedFloat32Array()
	var spill := _spill
	_spill = PackedFloat32Array()
	var maxq := 0.0
	var active := 0
	for s in n:
		for e in range(1, cols):
			var za := -bed[e - 1]
			var zb := -bed[e]
			var ha := za + depth[e - 1]
			var hb := zb + depth[e]
			var lip := maxf(za, zb)
			var h_edge := maxf(ha, hb) - lip
			if h_edge <= 0.5:
				flux[e] = 0.0
				evel[e] = 0.0
				continue
			var q := (flux[e] + dt * gravity * h_edge * (maxf(ha, lip) - maxf(hb, lip)) * inv) * damp
			flux[e] = q
			evel[e] = q / maxf(h_edge, 24.0)
		# Viscosity on the edge fluxes (conservative): damps the column-scale ripples the
		# pipe model otherwise keeps forever.
		var prev := flux[0]
		for e in range(1, cols):
			var cur := flux[e]
			if cur != 0.0:
				flux[e] = cur + viscosity * (prev - 2.0 * cur + flux[e + 1])
			prev = cur
		# Outflow limiter: a column never gives more than it holds this substep.
		for c in cols:
			var out := (maxf(flux[c + 1], 0.0) - minf(flux[c], 0.0)) * dt
			var vol := depth[c] * cell
			if out > vol and out > 0.0:
				var k := vol / out
				if flux[c + 1] > 0.0:
					flux[c + 1] *= k
				if flux[c] < 0.0:
					flux[c] *= k
		for e in range(1, cols):
			var q := flux[e]
			if q == 0.0:
				continue
			var v := q * dt
			var src := e - 1 if q > 0.0 else e
			var dst := e if q > 0.0 else e - 1
			depth[src] -= absf(v) * inv
			var lip := maxf(-bed[e - 1], -bed[e])
			if bed[dst] > bed[src] and lip - (depth[dst] - bed[dst]) > CLIFF:
				spill[e] += absf(v)
			else:
				depth[dst] += absf(v) * inv
		for o in orifices:
			_step_orifice(o, dt, depth, bed)
	for e in range(1, cols):
		var aq := absf(flux[e])
		if aq > 4.0:
			active += 1
		maxq = maxf(maxq, aq)
	for c in cols:
		if depth[c] < 0.0:
			_volume_clamped -= depth[c] * cell
			depth[c] = 0.0
	_depth = depth
	_flux = flux
	_evel = evel
	_spill = spill
	active_columns = active
	_spawn_spills(delta)
	var orifice_flow := 0.0
	for o in orifices:
		orifice_flow += absf(o.q)
	_render_dirty = true
	if maxq < 6.0 and orifice_flow < 6.0 and _parcels.count == 0:
		_idle += 1
		if _idle > 45:
			_awake = false
			_flux.fill(0.0)
			_evel.fill(0.0)
			active_columns = 0
	else:
		_idle = 0


func _step_orifice(o: Orifice, dt: float, depth: PackedFloat32Array, bed: PackedFloat32Array) -> void:
	o.open = minf(1.0, o.open + dt / orifice_ramp)
	var zl := -bed[o.left_col] + depth[o.left_col]
	var zr := -bed[o.right_col] + depth[o.right_col]
	var src := o.left_col
	var dst := o.right_col
	var hs := zl
	var hd := zr
	o.jet_dir = 1
	if zr > zl:
		src = o.right_col
		dst = o.left_col
		hs = zr
		hd = zl
		o.jet_dir = -1
	var zt := -o.top
	var zbot := -o.bottom
	var wet := minf(hs, zt) - zbot
	o.wet_top = -minf(maxf(hs, hd), zt) if maxf(hs, hd) > zbot + 1.0 else INF
	if wet <= 0.5:
		o.q = 0.0
		o.jet_speed = 0.0
		return
	var head := hs - maxf(hd, zbot + wet * 0.5)
	if head <= 0.0:
		o.q = 0.0
		o.jet_speed = 0.0
		return
	o.jet_speed = sqrt(2.0 * gravity * head)
	var vol := minf(orifice_coefficient * wet * o.jet_speed * o.open * dt, (hs - zbot) * cell * 0.45)
	vol = minf(vol, depth[src] * cell)
	depth[src] -= vol / cell
	if hd > zbot + 6.0:
		depth[dst] += vol / cell
	else:
		o.spill += vol
	o.q = vol / dt * o.jet_dir


func _spawn_spills(delta: float) -> void:
	for o in orifices:
		if o.spill < PARCEL_MIN:
			continue
		var n := clampi(ceili(o.spill / PARCEL_VOL), 1, 26)
		var vol := o.spill / n
		o.spill = 0.0
		var x := (o.x_right + 3.0) if o.jet_dir > 0 else (o.x_left - 3.0)
		var top := o.wet_top if o.wet_top != INF else o.top
		for i in n:
			var y := lerpf(top, o.bottom, _rng.randf_range(0.22, 0.78))
			var vx := o.jet_dir * o.jet_speed * _rng.randf_range(0.86, 1.03)
			var vy := _rng.randf_range(-50.0, 40.0)
			var lead := _rng.randf() * delta
			_parcels.spawn(x + vx * lead, y + vy * lead, vx, vy, 4.0, 2, _rng.randi_range(0, 3), vol)
		# Loose spray around the stream, visual only.
		if _rng.randf() < 0.6 and _drops.count < _drops.capacity - 2:
			var sy := lerpf(top, o.bottom, _rng.randf())
			_drops.spawn(x, sy, o.jet_dir * o.jet_speed * _rng.randf_range(0.6, 1.1), _rng.randf_range(-260.0, 60.0), 1.2, 1, _rng.randi_range(0, 2))
	for e in range(1, cols):
		if _spill[e] < PARCEL_MIN:
			continue
		var n := clampi(ceili(_spill[e] / PARCEL_VOL), 1, 4)
		var vol := _spill[e] / n
		_spill[e] = 0.0
		var dir := 1.0 if _flux[e] > 0.0 else -1.0
		var src := e - 1 if dir > 0.0 else e
		var x := domain.position.x + e * cell + dir * 3.0
		for i in n:
			var y := _bed[src] - maxf(_depth[src], 6.0) * _rng.randf()
			_parcels.spawn(x, y, dir * clampf(absf(_evel[e]), 80.0, 900.0), _rng.randf_range(-20.0, 30.0), 4.0, 2, _rng.randi_range(0, 2), vol)


func _step_parcels(delta: float) -> void:
	var g := gravity * delta
	var i := _parcels.count - 1
	while i >= 0:
		var vy := _parcels.vy[i] + g
		var vx := _parcels.vx[i]
		var x := _parcels.px[i] + vx * delta
		var y := _parcels.py[i] + vy * delta
		_parcels.vy[i] = vy
		_parcels.px[i] = x
		_parcels.py[i] = y
		_parcels.life[i] -= delta
		var c := _col(x)
		var top := _bed[c] - _depth[c]
		if y >= top or y >= domain.end.y or _parcels.life[i] <= 0.0:
			if y - vy * delta >= top + 1.0:
				# Came in through the side of a higher column: it hit the wall, stays below it.
				c = _col(x - vx * delta)
			_land(c, x, vx, vy, _parcels.aux[i])
			_parcels.kill(i)
		i -= 1


func _land(c: int, x: float, vx: float, vy: float, vol: float) -> void:
	# Spread over three columns (when they are not higher ground) to avoid single-column spikes.
	var share := vol / cell
	for n in [c - 1, c + 1]:
		if n >= 0 and n < cols and _bed[n] >= _bed[c] - 6.0:
			_depth[n] += vol * 0.25 / cell
			share -= vol * 0.25 / cell
	_depth[c] += share
	_awake = true
	_idle = 0
	var j := _rcol(x)
	var impact := clampf(vy * vol / 160000.0, 0.0, 1.0)
	for k in range(-2, 3):
		var jj := j + k
		if jj >= 0 and jj < rcols:
			_sv[jj] += minf(vy * vol * 0.00012, 14.0) * (1.0 - absf(k) * 0.3)
			_foam[jj] = minf(1.0, _foam[jj] + 0.18 + impact)
	_springs_awake = true
	if _rng.randf() < 0.3 and _drops.count < _drops.capacity - 4:
		var y := _bed[c] - _depth[c]
		_drops.spawn(x, y - 6.0, vx * 0.25 + _rng.randf_range(-160.0, 160.0), -_rng.randf_range(200.0, 520.0), 1.5, 1, _rng.randi_range(0, 2))


func _step_drops(delta: float) -> void:
	var g := gravity * delta
	var i := _drops.count - 1
	while i >= 0:
		_drops.vy[i] += g
		_drops.px[i] += _drops.vx[i] * delta
		_drops.py[i] += _drops.vy[i] * delta
		_drops.life[i] -= delta
		var x := _drops.px[i]
		var y := _drops.py[i]
		var c := _col(x)
		var top := _bed[c] - _depth[c]
		if _drops.life[i] <= 0.0 or (_drops.vy[i] > 0.0 and y >= top) or y >= _rbed_at(x):
			_drops.kill(i)
		i -= 1


func _step_bubbles(delta: float) -> void:
	for pool in _bubble_pools:
		var rise := 150.0 if pool == _bubbles else 210.0
		var i: int = pool.count - 1
		while i >= 0:
			var vy: float = move_toward(pool.vy[i], -rise, 300.0 * delta)
			var vx: float = pool.vx[i] * (1.0 - 2.5 * delta)
			pool.vx[i] = vx
			pool.vy[i] = vy
			var c := _col(pool.px[i])
			var drift := (_evel[c] + _evel[c + 1]) * 0.25
			pool.px[i] += (vx + drift) * delta
			pool.py[i] += vy * delta
			pool.life[i] -= delta
			pool.aux[i] += delta * 7.0
			pool.draw_dx[i] = roundf(sin(pool.aux[i])) * ART
			var x: float = pool.px[i]
			var y: float = pool.py[i]
			var p := Vector2(x, y)
			var s := _surface_local(x)
			var t := _in_tunnel(p)
			var dead := false
			if t >= 0:
				pass
			elif s == INF or y <= s + 3.0:
				dead = true
				if s != INF:
					_pops.spawn(x - ART, s - ART * 2.0, 0.0, 0.0, 0.12, 1, 0)
					if _bubble_sfx_cd <= 0.0 and pool == _rings:
						_bubble_sfx_cd = 0.09
						Feedback.sfx(&"bubble", p + _origin, _rng.randf_range(0.2, 0.55))
			elif y > _rbed_at(x) or pool.life[i] <= 0.0:
				dead = true
			if dead:
				pool.kill(i)
			i -= 1
	var k := _pops.count - 1
	while k >= 0:
		_pops.life[k] -= delta
		if _pops.life[k] <= 0.0:
			_pops.kill(k)
		k -= 1


func _step_springs(delta: float) -> void:
	if not _springs_awake:
		return
	var tension := 2200.0
	var stiff := 26.0
	var damping := 4.5
	var dt := delta * 0.5
	var energy := 0.0
	var sh := _sh
	_sh = PackedFloat32Array()
	var sv := _sv
	_sv = PackedFloat32Array()
	var per := cell / ART
	for sub in 2:
		for j in rcols:
			var c := j / per
			if _depth[c] < WET:
				sh[j] = 0.0
				sv[j] = 0.0
				continue
			var hl: float = sh[j - 1] if j > 0 and _depth[(j - 1) / per] >= WET else sh[j]
			var hr: float = sh[j + 1] if j < rcols - 1 and _depth[(j + 1) / per] >= WET else sh[j]
			var h: float = sh[j]
			var a := tension * (hl + hr - 2.0 * h) - stiff * h - damping * sv[j]
			sv[j] += a * dt
		for j in rcols:
			var lim := minf(24.0, _depth[j / per] * 0.4)
			sh[j] = clampf(sh[j] + sv[j] * dt, -lim, lim)
			energy = maxf(energy, absf(sh[j]) + absf(sv[j]) * 0.05)
	_sh = sh
	_sv = sv
	_render_dirty = true
	if energy < 0.08:
		_springs_awake = false
		_sh.fill(0.0)
		_sv.fill(0.0)


func _step_restore(delta: float) -> void:
	_restore_t += delta
	# Levels move uniformly (a draining pool sinks flat instead of thinning into a film).
	var t := smoothstep(0.0, 1.0, _restore_t / _restore_len)
	for c in cols:
		var a := _restore_from[c]
		var b := _rest[c]
		_depth[c] = maxf(a, b - (1.0 - t) * _restore_rise) if b > a else maxf(b, a - t * _restore_drop)
	_render_dirty = true
	if _restore_t >= _restore_len:
		_restore_t = -1.0
		_depth = _rest.duplicate()
		_volume_clamped = 0.0
		_idle = 0
		_awake = true


# --- Bodies ---------------------------------------------------------------------------------------

func _build_area() -> void:
	var area := Area2D.new()
	area.name = "BodyProbe"
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = 0xFFFFFFFF
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = domain.size
	shape.shape = rect
	shape.position = domain.get_center()
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if (body is RigidBody2D or body is CharacterBody2D) and not _bodies.has(body):
		_bodies.append(body)
		_body_wet.append(1 if is_point_in_water(body.global_position) else 0)


func _on_body_exited(body: Node2D) -> void:
	var i := _bodies.find(body)
	if i != -1:
		_bodies.remove_at(i)
		_body_wet.remove_at(i)


func _track_bodies(delta: float) -> void:
	for i in _bodies.size():
		var b := _bodies[i]
		if not is_instance_valid(b):
			continue
		var v: Vector2 = b.linear_velocity if b is RigidBody2D else b.velocity
		var p := b.global_position
		var wet := is_point_in_water(p)
		if wet != (_body_wet[i] == 1):
			_body_wet[i] = 1 if wet else 0
			var s := get_surface_y(p.x, p.y)
			if s != INF and not b.has_meta(&"water_custom_splash") and ((wet and v.y > 120.0) or (not wet and v.y < -150.0)):
				var strength := clampf(absf(v.y) / 1600.0, 0.12, 1.2) * (1.0 if wet else 0.5)
				emit_splash(Vector2(p.x, s), strength)
		elif wet and v.length() > 220.0:
			var s2 := get_surface_y(p.x, p.y)
			if s2 != INF and absf(p.y - s2) < 90.0:
				apply_disturbance(p, v * delta * 6.0)
		if b is RigidBody2D:
			_buoy(b as RigidBody2D, v)


func _buoy(b: RigidBody2D, v: Vector2) -> void:
	var size: Vector2 = b.get_meta(&"water_size", Vector2.ZERO)
	if size == Vector2.ZERO:
		for child in b.get_children():
			if child is CollisionShape2D and child.shape:
				size = child.shape.get_rect().size
				break
		b.set_meta(&"water_size", size)
	var ratio := get_submerged_ratio(Rect2(b.global_position - size * 0.5, size))
	if ratio <= 0.0:
		return
	var g := float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)) * b.gravity_scale
	var density: float = b.get_meta(&"buoyancy", buoyancy)
	var force := Vector2(0.0, -g * b.mass * density * ratio)
	var drag: float = b.get_meta(&"water_drag", 2.2)
	# Sample the current low in the body: a floating body's centre may sit above the surface.
	var rel := get_flow_at(b.global_position + Vector2(0.0, size.y * 0.35)) - v
	# `water_drag` couples a body to the current; vertical damping stays at the default so a
	# pushed-under body still bobs back up.
	force += Vector2(rel.x * drag, rel.y * 2.2) * b.mass * ratio
	b.apply_central_force(force)
	b.apply_torque(-b.angular_velocity * b.mass * 4000.0 * ratio)


# --- Audio ----------------------------------------------------------------------------------------

func _update_audio(delta: float) -> void:
	var rate := 0.0
	var at := _flow_at
	for o in orifices:
		if absf(o.q) > rate:
			rate = absf(o.q)
			at = _origin + Vector2(o.x_right if o.jet_dir > 0 else o.x_left, (o.top + o.bottom) * 0.5)
	_flow_rate = rate
	_flow_at = at
	var strength := clampf(rate / flow_reference, 0.0, 1.0)
	if strength > 0.03:
		_flow_quiet = 0.0
		if _flow_handle <= 0:
			_flow_handle = Feedback.sfx_loop(&"water_flow", at)
			_rumble_handle = Feedback.haptic_loop(&"water_flow", strength * 0.5)
		Feedback.sfx_loop_update(_flow_handle, strength, at)
		Feedback.haptic_loop_strength(_rumble_handle, strength * 0.5)
	elif _flow_handle > 0 or _rumble_handle > 0:
		_flow_quiet += delta
		Feedback.sfx_loop_update(_flow_handle, strength)
		Feedback.haptic_loop_strength(_rumble_handle, strength * 0.5)
		if _flow_quiet > 0.6:
			Feedback.sfx_stop(_flow_handle, 0.4)
			Feedback.haptic_stop(_rumble_handle)
			_flow_handle = -1
			_rumble_handle = -1


func _exit_tree() -> void:
	if _flow_handle > 0:
		Feedback.sfx_stop(_flow_handle, 0.1)
	if _rumble_handle > 0:
		Feedback.haptic_stop(_rumble_handle)
	_flow_handle = -1
	_rumble_handle = -1


# --- Render ---------------------------------------------------------------------------------------

func _build_render() -> void:
	_rect = ColorRect.new()
	_rect.name = "WaterSurface"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.position = domain.position
	_rect.size = domain.size
	_rect.z_as_relative = false
	_rect.z_index = draw_z
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter(&"col_data", _tex)
	_mat.set_shader_parameter(&"grid", Vector2(rcols, int(domain.size.y) / ART))
	_rect.material = _mat
	add_child(_rect)
	_tunnels.resize(4)


func _build_particles() -> void:
	var water := PackedColorArray([Color("#9ad8ec"), Color("#5ab4d2", 0.9), Color("#eef8ff")])
	_drops = _make_pool("Drops", 600, water, null, 1)
	_parcels = _make_pool("Jet", 2000, PackedColorArray([Color("#6cc0dc", 0.92), Color("#9ad8ec", 0.92), Color("#4a9cc4", 0.9), Color("#dff4fb", 0.95)]), null, 1)
	_bubbles = _make_pool("Bubbles", 400, PackedColorArray([Color("#b8e8f4", 0.85), Color("#e6f8ff", 0.8)]), null, 1)
	_rings = _make_pool("BubbleRings", 200, PackedColorArray([Color(1, 1, 1, 0.85)]), _ring_texture(), 3)
	_pops = _make_pool("BubblePops", 120, PackedColorArray([Color(1, 1, 1, 0.8)]), _pop_texture(), 3)
	_all_pools = [_drops, _parcels, _bubbles, _rings, _pops]
	_bubble_pools = [_bubbles, _rings]


func _make_pool(pool_name: String, cap: int, colors: PackedColorArray, tex: Texture2D, quad: int) -> Particles:
	var p := Particles.new()
	p.name = pool_name
	p.z_as_relative = false
	p.z_index = draw_z + 1
	add_child(p)
	p.setup(cap, colors, tex, quad)
	return p


func _ring_texture() -> ImageTexture:
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var rim := Color("#c4ecf6")
	for v in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 2)]:
		img.set_pixelv(v, rim)
	img.set_pixel(1, 1, Color(0.85, 0.95, 1.0, 0.25))
	img.set_pixel(0, 0, Color(1, 1, 1, 0.9))
	return ImageTexture.create_from_image(img)


func _pop_texture() -> ImageTexture:
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for v in [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(2, 2)]:
		img.set_pixelv(v, Color("#e6f8ff"))
	return ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if not _ready_sim:
		return
	for pool in _all_pools:
		pool.flush()
	if not _render_dirty:
		return
	_render_dirty = false
	var t0 := Time.get_ticks_usec()
	_upload(delta)
	last_render_usec = Time.get_ticks_usec() - t0


func _upload(delta: float) -> void:
	var top := domain.position.y
	var decay := exp(-1.4 * delta)
	var per := cell / ART
	var foam_max := 0.0
	for j in rcols:
		var x := domain.position.x + (j + 0.5) * ART
		var s := _surface_local(x)
		var bed_row := clampi(floori((_rbed[j] - top) / ART + 0.5), 0, 254)
		var k := j * 4
		var c := j / per
		var speed := absf(_evel[c] + _evel[c + 1]) * 0.5
		var foam := _foam[j] * decay
		if speed > 420.0:
			foam = maxf(foam, minf(1.0, (speed - 420.0) / 900.0))
		_foam[j] = foam
		foam_max = maxf(foam_max, foam)
		if s == INF or s >= _rbed[j] - 0.5:
			_data[k] = 255
		else:
			_data[k] = clampi(floori((s - top) / ART + 0.5), 0, maxi(bed_row - 1, 0))
		_data[k + 1] = bed_row
		_data[k + 2] = int(foam * 255.0)
		_data[k + 3] = clampi(int(speed / 900.0 * 255.0), 0, 255)
	if foam_max > 0.01:
		_render_dirty = true
	_img.set_data(rcols, 1, false, Image.FORMAT_RGBA8, _data)
	_tex.update(_img)
	var n := 0
	for o in orifices:
		if n >= 4 or o.wet_top == INF:
			continue
		_tunnels[n] = Vector4((o.x_left - domain.position.x) / ART, floorf((o.wet_top - top) / ART + 0.5),
			(o.x_right - domain.position.x) / ART, (o.bottom - top) / ART)
		n += 1
	_mat.set_shader_parameter(&"tunnels", _tunnels)
	_mat.set_shader_parameter(&"tunnel_count", n)
