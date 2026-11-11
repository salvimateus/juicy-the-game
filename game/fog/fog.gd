extends Node

# Autoload `Fog`: physical swamp fog over the whole level.
# A GPU fluid step (density + velocity, semi-Lagrangian advection, diffusion, vorticity
# confinement, damping toward a slow wind, relaxation to a rest profile) runs in a SubViewport that
# follows the camera; two world-space layers draw it as pixel art on the art grid.
# Nothing in gameplay reads the fog back, so it is purely visual and safe to skip in headless runs.

const FogTerrain := preload("res://game/fog/fog_terrain.gd")
const SIM_SHADER := preload("res://game/fog/fog_sim.gdshader")
const LAYER_SHADER := preload("res://game/fog/fog_layer.gdshader")
const FogTuning := preload("res://game/fog/fog_tuning.gd")

enum Quality { LOW, MEDIUM, HIGH }

const ART := 6.0
const SIM_CELL := [18.0, 12.0, 6.0]
const MAX_IMPULSES := 64
const MAX_BODIES := 16
const BODY_TTL := 0.15
const MARGIN := 300.0
const BACK_Z := -3
const FRONT_Z := 30
const TYPE_PUSH := 0.0
const TYPE_BURST := 1.0
const TYPE_LINE := 2.0
const TYPE_DENSITY := 3.0
const TYPE_BODY := 4.0
const TYPE_SWEEP := 5.0
const TYPE_SWIRL := 6.0
const WATER_WATCH_MS := 9000

# Off by default: no terrain build, no simulation and nothing drawn until the game enables it.
var enabled := false: set = set_enabled
var density_scale := 1.0: set = set_density_scale
## Multiplies the alpha of the fog layers (F1 tuning, about 0.5 to 1.5).
var opacity_scale := 1.0
var quality: int = Quality.HIGH: set = set_quality
var wind := Vector2(18.0, 0.0)

var terrain: FogTerrain
var ready_terrain := false
var last_cpu_usec := 0
var last_build_ms := 0.0
var dropped := 0

var _gpu := false
var _vp: SubViewport
var _sim_rect: ColorRect
var _sim_mat: ShaderMaterial
var _back: Sprite2D
var _front: Sprite2D
var _layer_mats: Array[ShaderMaterial] = []
var _grid := Vector2i.ZERO
var _origin_cells := Vector2i.ZERO
var _reset_frames := 2
var _time := 0.0
var _window := Rect2()

var _a0 := PackedVector4Array()
var _b0 := PackedVector4Array()
var _a1 := PackedVector4Array()
var _b1 := PackedVector4Array()
var _flip := false
var _n := 0

var _body_id := PackedInt32Array()
var _body_a := PackedVector4Array()
var _body_r := PackedFloat32Array()
var _body_t := PackedFloat32Array()

var _scene: Node
var _task_region := false
var _pending := Rect2()
var _pending_wait := 0
var _solid_tex: ImageTexture
var _rest_tex: ImageTexture
var _water_watch_until := 0
var _water_watch_next := 0
var _build_wait := -1
var _water_tries := 0
var _task := -1
var _stats := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	for arr in [_a0, _b0, _a1, _b1]:
		arr.resize(MAX_IMPULSES)
	_body_id.resize(MAX_BODIES)
	_body_id.fill(-1)
	_body_a.resize(MAX_BODIES)
	_body_r.resize(MAX_BODIES)
	_body_t.resize(MAX_BODIES)
	_gpu = DisplayServer.get_name() != "headless"
	if _gpu:
		_build_nodes()
	# Dev switch to preview the fog in any scene before the game layer enables it.
	if OS.get_cmdline_user_args().has("--fog"):
		enabled = true


# --- API --------------------------------------------------------------------------------------

## Directional shove (punch, kick, roll wind, dodge). velocity in units/s.
func push(global_pos: Vector2, velocity: Vector2, radius: float, strength: float = 1.0) -> void:
	_add(global_pos.x, global_pos.y, velocity.x, velocity.y, radius, strength, 0.0, TYPE_PUSH, radius)


## Radial blast outward (landing, impact, wall breaking, foot stomp).
func burst(global_pos: Vector2, radius: float, strength: float = 1.0) -> void:
	_add(global_pos.x, global_pos.y, 0.0, 0.0, radius, strength, 0.0, TYPE_BURST, radius)


## Bullet or arrow trail: opens a thin tunnel with eddies on its edges that closes slowly.
func line(from: Vector2, to: Vector2, width: float, strength: float = 1.0) -> void:
	if _n >= MAX_IMPULSES or not _accepting():
		dropped += 1
		return
	var box := Rect2(from, Vector2.ZERO).expand(to).grow(width * 3.0)
	if not box.intersects(_window):
		return
	_put(Vector4(from.x, from.y, to.x, to.y), Vector4(width, strength, randf() * TAU, TYPE_LINE))


## Roll or slide: ploughs a wide furrow along the segment (at ground level), throwing the fog
## sideways and up. Call each physics frame of the move with the previous and current position.
func sweep(from: Vector2, to: Vector2, radius: float, strength: float = 1.0) -> void:
	if _n >= MAX_IMPULSES or not _accepting():
		if _accepting():
			dropped += 1
		return
	if not Rect2(from, Vector2.ZERO).expand(to).grow(radius * 1.8).intersects(_window):
		return
	_put(Vector4(from.x, from.y, to.x, to.y), Vector4(radius, strength, randf() * TAU, TYPE_SWEEP))


## Vortex at a point (dodge: where the body left). Negative strength spins the other way.
func swirl(global_pos: Vector2, radius: float, strength: float = 1.0) -> void:
	_add(global_pos.x, global_pos.y, 0.0, 0.0, radius, strength, 0.0, TYPE_SWIRL, radius)


## Raises fog (splash, dust).
func add_density(global_pos: Vector2, radius: float, amount: float) -> void:
	_add(global_pos.x, global_pos.y, 0.0, 0.0, radius, amount, 0.0, TYPE_DENSITY, radius)


## A body crossing the fog, pushing it continuously and leaving a wake. Call every frame; a body
## not updated for BODY_TTL seconds stops affecting the fog.
func set_body(id: int, global_pos: Vector2, velocity: Vector2, radius: float) -> void:
	var slot := _body_id.find(id)
	if slot == -1:
		slot = _body_id.find(-1)
		if slot == -1:
			var oldest := 0
			for i in MAX_BODIES:
				if _body_t[i] < _body_t[oldest]:
					oldest = i
			slot = oldest
		_body_id[slot] = id
	_body_a[slot] = Vector4(global_pos.x, global_pos.y, velocity.x, velocity.y)
	_body_r[slot] = radius
	_body_t[slot] = _time


func clear_body(id: int) -> void:
	var slot := _body_id.find(id)
	if slot != -1:
		_body_id[slot] = -1


## Re-reads the static colliders and water of the current scene (after the level changes).
func rebuild_terrain() -> void:
	_build_wait = 2


## Re-rasterizes the solids and water inside `rect` (global) a few frames later, once deferred
## collision changes have landed. Call it after geometry appears or disappears; freed space
## starts empty and the fog flows into it.
func invalidate_solids(rect: Rect2) -> void:
	if not rect.has_area():
		return
	_pending = rect if not _pending.has_area() else _pending.merge(rect)
	_pending_wait = 3


## Puts the visible fog back at rest at once.
func reset() -> void:
	_reset_frames = 2


func stats() -> Dictionary:
	_stats.enabled = enabled
	_stats.ready = ready_terrain
	_stats.gpu = _gpu
	_stats.quality = quality
	_stats.grid = _grid
	_stats.cell = SIM_CELL[quality]
	_stats.cpu_usec = last_cpu_usec
	_stats.sim_gpu_ms = RenderingServer.viewport_get_measured_render_time_gpu(_vp.get_viewport_rid()) if _vp else 0.0
	_stats.build_ms = last_build_ms
	_stats.dropped = dropped
	return _stats


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_n = 0
	elif not ready_terrain and _task == -1 and _build_wait < 0:
		_build_wait = 2
	_reset_frames = 2
	_apply_visibility()


func set_density_scale(v: float) -> void:
	density_scale = maxf(v, 0.0)


func set_quality(q: int) -> void:
	quality = clampi(q, Quality.LOW, Quality.HIGH)
	_grid = Vector2i.ZERO
	for m in _layer_mats:
		m.set_shader_parameter(&"detail", FogTuning.DETAIL_BY_QUALITY[quality])


# --- Internals --------------------------------------------------------------------------------

func _accepting() -> bool:
	return enabled and ready_terrain and _gpu


func _add(x: float, y: float, vx: float, vy: float, radius: float, strength: float, extra: float, type: float, reach: float) -> void:
	if _n >= MAX_IMPULSES or not _accepting():
		if _accepting():
			dropped += 1
		return
	if x + reach < _window.position.x or x - reach > _window.end.x or y + reach < _window.position.y or y - reach > _window.end.y:
		return
	_put(Vector4(x, y, vx, vy), Vector4(radius, strength, extra, type))


func _put(a: Vector4, b: Vector4) -> void:
	if _flip:
		_a1[_n] = a
		_b1[_n] = b
	else:
		_a0[_n] = a
		_b0[_n] = b
	_n += 1


func _build_nodes() -> void:
	_vp = SubViewport.new()
	_vp.name = "FogSim"
	_vp.use_hdr_2d = true
	_vp.transparent_bg = true
	_vp.disable_3d = true
	_vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.size = Vector2i(8, 8)
	add_child(_vp)
	RenderingServer.viewport_set_measure_render_time(_vp.get_viewport_rid(), true)
	_sim_mat = ShaderMaterial.new()
	_sim_mat.shader = SIM_SHADER
	_sim_rect = ColorRect.new()
	_sim_rect.material = _sim_mat
	_sim_rect.size = Vector2(8, 8)
	_vp.add_child(_sim_rect)
	var img := Image.create_empty(1, 1, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(img)
	_back = _make_layer(white, false, BACK_Z, "FogBack")
	_front = _make_layer(white, true, FRONT_Z, "FogFront")
	_apply_visibility()


func _make_layer(tex: Texture2D, front: bool, z: int, node_name: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = tex
	s.centered = false
	s.z_index = z
	s.z_as_relative = false
	var m := ShaderMaterial.new()
	m.shader = LAYER_SHADER
	m.set_shader_parameter(&"front", front)
	m.set_shader_parameter(&"sim_tex", _vp.get_texture())
	for d: Dictionary in [FogTuning.COMMON, FogTuning.FRONT if front else FogTuning.BACK]:
		for k in d:
			m.set_shader_parameter(StringName(k), d[k])
	m.set_shader_parameter(&"detail", FogTuning.DETAIL_BY_QUALITY[quality])
	s.material = m
	_layer_mats.append(m)
	add_child(s)
	return s


func _apply_visibility() -> void:
	if not _gpu:
		return
	var on := enabled and ready_terrain
	_back.visible = on
	_front.visible = on
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_track_scene()
	var paused := get_tree().paused
	var dt := 0.0 if paused else minf(delta, 1.0 / 30.0)
	_time += dt
	_expire_bodies()
	if not _gpu or not ready_terrain or not enabled:
		_n = 0
		last_cpu_usec = Time.get_ticks_usec() - t0
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		_back.visible = false
		_front.visible = false
		_n = 0
		return
	_back.visible = true
	_front.visible = true
	var cell: float = SIM_CELL[quality]
	var view := get_viewport().get_visible_rect().size / cam.zoom
	var ext := view + Vector2.ONE * MARGIN * 2.0
	var grid := Vector2i(ceili(ext.x / cell / 8.0) * 8, ceili(ext.y / cell / 8.0) * 8)
	if grid != _grid:
		_grid = grid
		_vp.size = grid
		_sim_rect.size = Vector2(grid)
		_reset_frames = 2
	var center := cam.get_screen_center_position()
	var oc := Vector2i(floori(center.x / cell - grid.x * 0.5), floori(center.y / cell - grid.y * 0.5))
	var shift := oc - _origin_cells
	if absi(shift.x) >= grid.x or absi(shift.y) >= grid.y:
		_reset_frames = maxi(_reset_frames, 1)
	_origin_cells = oc
	var origin := Vector2(oc) * cell
	_window = Rect2(origin, Vector2(grid) * cell)
	_push_bodies()
	var a := _a1 if _flip else _a0
	var b := _b1 if _flip else _b0
	var m := _sim_mat
	m.set_shader_parameter(&"origin", origin)
	m.set_shader_parameter(&"grid", Vector2(grid))
	m.set_shader_parameter(&"cell", cell)
	m.set_shader_parameter(&"shift", Vector2(shift))
	m.set_shader_parameter(&"dt", dt)
	m.set_shader_parameter(&"time", _time)
	m.set_shader_parameter(&"wind", wind)
	m.set_shader_parameter(&"density_scale", density_scale)
	m.set_shader_parameter(&"reset", _reset_frames > 0)
	m.set_shader_parameter(&"imp_count", 0 if dt == 0.0 else _n)
	if _n > 0:
		m.set_shader_parameter(&"imp_a", a)
		m.set_shader_parameter(&"imp_b", b)
		_flip = not _flip
	_n = 0
	if _reset_frames > 0:
		_reset_frames -= 1
	for lm in _layer_mats:
		lm.set_shader_parameter(&"sim_origin", origin)
		lm.set_shader_parameter(&"sim_world_size", Vector2(grid) * cell)
		lm.set_shader_parameter(&"time", _time)
		lm.set_shader_parameter(&"wind", wind)
		lm.set_shader_parameter(&"density_scale", density_scale)
		lm.set_shader_parameter(&"opacity_scale", opacity_scale)
	for layer in [_back, _front]:
		layer.global_position = origin
		layer.scale = Vector2(grid) * cell
	last_cpu_usec = Time.get_ticks_usec() - t0


func _expire_bodies() -> void:
	for i in MAX_BODIES:
		if _body_id[i] != -1 and _time - _body_t[i] > BODY_TTL:
			_body_id[i] = -1


func _push_bodies() -> void:
	for i in MAX_BODIES:
		if _body_id[i] == -1 or _n >= MAX_IMPULSES:
			continue
		var a := _body_a[i]
		var r := _body_r[i]
		if a.x + r < _window.position.x or a.x - r > _window.end.x or a.y + r < _window.position.y or a.y - r > _window.end.y:
			continue
		_put(a, Vector4(r, 1.0, _body_id[i] * 1.7, TYPE_BODY))


# --- Terrain ----------------------------------------------------------------------------------

func _track_scene() -> void:
	var scene := get_tree().current_scene
	if scene != _scene:
		_scene = scene
		ready_terrain = false
		_apply_visibility()
		_build_wait = 3 if scene and enabled else -1
	if _task != -1:
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			if _task_region:
				_finish_region()
			else:
				_finish_build()
		return
	if not enabled:
		return
	if ready_terrain:
		_watch_water()
		if _pending.has_area() and _build_wait < 0:
			_pending_wait -= 1
			if _pending_wait <= 0:
				_start_region()
	if _build_wait < 0:
		return
	_build_wait -= 1
	if _build_wait > 0:
		return
	# Water volumes rasterize a physics frame after they enter; wait for them (bounded).
	if _water_tries < 90:
		for w in get_tree().get_nodes_in_group(&"water"):
			if w.has_method(&"is_ready") and not w.is_ready():
				_water_tries += 1
				_build_wait = 1
				return
	_water_tries = 0
	_build_wait = -1
	_start_build()


func _start_build() -> void:
	var t := FogTerrain.new()
	if _scene == null or not t.collect(_scene, ART):
		ready_terrain = false
		_apply_visibility()
		return
	terrain = t
	_pending = Rect2()
	_task_region = false
	_task = WorkerThreadPool.add_task(t.compute, false, "fog terrain")


func _start_region() -> void:
	var rect := _pending
	_pending = Rect2()
	if terrain == null or _scene == null or not terrain.collect_region(_scene, rect, ART):
		return
	_task_region = true
	_task = WorkerThreadPool.add_task(terrain.compute_region, false, "fog terrain region")


func _finish_region() -> void:
	last_build_ms = (terrain.collect_usec + terrain.build_usec) / 1000.0
	if _gpu and _solid_tex:
		_solid_tex.update(terrain.mask_image)
		_rest_tex.update(terrain.rest_image)


# Breakable walls and water volumes change the terrain at runtime: hook their signals directly.
func _connect_dynamic(node: Node) -> void:
	if node.has_signal(&"impacted") and node.has_signal(&"restored") and node.has_method(&"is_broken"):
		var on_impact := _on_wall_impacted.bind(node)
		if not node.is_connected(&"impacted", on_impact):
			node.connect(&"impacted", on_impact)
			node.connect(&"restored", _on_wall_restored.bind(node))
	if node.has_signal(&"hole_opened") and node.has_signal(&"refilled"):
		if not node.is_connected(&"hole_opened", _on_water_changed):
			node.connect(&"hole_opened", _on_water_changed)
			node.connect(&"refilled", _on_water_changed)
	for child in node.get_children():
		_connect_dynamic(child)


func _on_wall_impacted(point: Vector2, strength: float, wall: Node) -> void:
	# The break itself blasts the fog away from the impact.
	burst(point, 320.0, clampf(strength * 1.3, 0.6, 1.8))
	if wall.is_broken():
		invalidate_solids(_node_rect(wall))


func _on_wall_restored(wall: Node) -> void:
	invalidate_solids(_node_rect(wall))


func _on_water_changed() -> void:
	# The water level keeps moving for a while after a dam opens or refills.
	_water_watch_until = Time.get_ticks_msec() + WATER_WATCH_MS
	_water_watch_next = 0


func _watch_water() -> void:
	var now := Time.get_ticks_msec()
	if now > _water_watch_until or now < _water_watch_next:
		return
	_water_watch_next = now + 500
	for w in get_tree().get_nodes_in_group(&"water"):
		if w is Node2D and "domain" in w:
			var d: Rect2 = w.domain
			invalidate_solids(Rect2((w as Node2D).global_position + d.position, d.size))


func _node_rect(node: Node) -> Rect2:
	var box := Rect2()
	var first := true
	for child in node.get_children():
		if child is CollisionShape2D and child.shape:
			var xf: Transform2D = child.global_transform
			var r: Rect2 = child.shape.get_rect()
			var g := Rect2(xf * r.position, Vector2.ZERO).expand(xf * r.end).expand(xf * Vector2(r.end.x, r.position.y)).expand(xf * Vector2(r.position.x, r.end.y))
			box = g if first else box.merge(g)
			first = false
	if first and node is Node2D:
		box = Rect2((node as Node2D).global_position - Vector2(200, 400), Vector2(400, 420))
	return box.grow(12.0)


func _finish_build() -> void:
	var t := terrain
	last_build_ms = (t.collect_usec + t.build_usec) / 1000.0
	print("FOG terrain bounds=%s mask=%dx%d rest=%dx%d collect_ms=%.1f compute_ms=%.1f" % [t.bounds,
		t.mask_image.get_width(), t.mask_image.get_height(), t.rest_image.get_width(), t.rest_image.get_height(),
		t.collect_usec / 1000.0, t.build_usec / 1000.0])
	ready_terrain = true
	_reset_frames = 2
	if not _gpu:
		return
	var solid := ImageTexture.create_from_image(t.mask_image)
	var rest := ImageTexture.create_from_image(t.rest_image)
	_solid_tex = solid
	_rest_tex = rest
	_connect_dynamic(_scene)
	var mats: Array[ShaderMaterial] = [_sim_mat]
	mats.append_array(_layer_mats)
	for m in mats:
		m.set_shader_parameter(&"solid_tex", solid)
		m.set_shader_parameter(&"solid_origin", t.bounds.position)
		m.set_shader_parameter(&"solid_size", t.bounds.size)
		m.set_shader_parameter(&"rest_tex", rest)
		m.set_shader_parameter(&"rest_origin", t.bounds.position)
		m.set_shader_parameter(&"rest_size", t.bounds.size)
		m.set_shader_parameter(&"rest_range", FogTerrain.REST_RANGE)
	for m in _layer_mats:
		m.set_shader_parameter(&"rest_h_max", FogTerrain.H_MAX)
		m.set_shader_parameter(&"art", ART)
	_apply_visibility()
