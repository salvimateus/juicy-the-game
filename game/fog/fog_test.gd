extends Node2D

# Test bench for the Fog autoload: uneven ground, a floating platform, a low pit and a scripted
# test body that walks, jumps, lands, punches and fires, then sprints and fires an AK burst.
# Interactive: the script loops. Capture:
# godot --path <project> --resolution 1280x720 res://game/fog/fog_test.tscn -- --capture <dir>
# saves SHOTS, prints per-phase timings (idle, sprint, ak, off) and quits.

const GameScale := preload("res://game/game_scale.gd")

const SKY := Color("#4e80c2")
const HORIZON := Color("#b2d2ee")
const GRASS := Color("#5f9a3a")
const GRASS_LIGHT := Color("#8cc04a")
const DIRT := Color("#8a4a32")
const DIRT_DARK := Color("#6e3826")
const STONE := Color("#6e5c5c")

# [x0, x1, top y]
const GROUND := [
	[-3000.0, -200.0, 0.0],
	[-200.0, 300.0, 300.0],
	[300.0, 1000.0, 0.0],
	[1000.0, 9000.0, -120.0],
]
const PLATFORM := Rect2(1250.0, -560.0, 540.0, 72.0)
const CAMERA_POS := Vector2(300.0, -330.0)
const BODY_H := 420.0
const GRAVITY := 2600.0
const WALK := 520.0
const SPRINT := 1400.0

const SHOTS := [
	[2.0, "fog_rest"],
	[3.15, "fog_wake"],
	[4.47, "fog_land"],
	[5.34, "fog_shot"],
	[6.36, "fog_punch"],
	[10.0, "fog_recompose"],
	[11.6, "fog_sprint"],
	[14.0, "fog_ak"],
	[15.45, "fog_wall_before"],
	[15.75, "fog_wall_break"],
	[16.6, "fog_wall_flow"],
	[18.0, "fog_wall_filled"],
	[18.15, "fog_roll_before"],
	[18.45, "fog_roll_during"],
	[18.95, "fog_roll_after"],
	[19.9, "fog_roll_settled"],
	[20.3, "fog_rollback_during"],
	[20.95, "fog_dodge_before"],
	[21.1, "fog_dodge_during"],
	[21.6, "fog_dodge_after"],
]
const PHASES := [
	["idle", 7.6, 9.9],
	["sprint", 10.3, 12.7],
	["ak", 12.9, 15.4],
	["off", 22.4, 23.8],
]
const END := 24.0
const ROLL_SPEED := 1100.0
const ROLL_TIME := 0.55
const DODGE_SPEED := 1700.0
const DODGE_TIME := 0.18
const WALL_X := 5400.0
const TARGETS := [Vector2(1580.0, -170.0), Vector2(1580.0, -330.0), Vector2(1000.0, -90.0)]

var camera: Camera2D
var body: Node2D
var wall: Node2D
var _dir := ""
var _tick := 0
var _t := 0.0
var _pos := Vector2(-950.0, 0.0)
var _vel := Vector2.ZERO
var _facing := 1.0
var _mode := &"idle"
var _air := false
var _step_t := 0.0
var _next_fire := 0.0
var _shots: Array = []
var _busy := 0
var _done := false
var _events: Array = []
var _phase := {}
var _shot_i := 0
var _move_dir := 1.0
var _mode_t := 0.0
var _frame_dt := 0.0
var _frame_max := 0.0
var _frame_n := 0


func _ready() -> void:
	get_tree().physics_interpolation = true
	RenderingServer.set_default_clear_color(SKY)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var horizon := ColorRect.new()
	horizon.color = HORIZON
	horizon.position = Vector2(-4000, -700)
	horizon.size = Vector2(14000, 3000)
	horizon.z_index = -30
	add_child(horizon)
	var band := ColorRect.new()
	band.color = SKY.lerp(HORIZON, 0.5)
	band.position = Vector2(-4000, -880)
	band.size = Vector2(14000, 180)
	band.z_index = -30
	add_child(band)
	for g in GROUND:
		_add_block(Rect2(g[0], g[2], g[1] - g[0], 2000.0), true)
	_add_block(PLATFORM, false)
	wall = preload("res://game/breakable/breakable_wall.tscn").instantiate()
	wall.position = Vector2(WALL_X, _floor_at(WALL_X))
	add_child(wall)
	body = Node2D.new()
	body.set_script(preload("res://game/fog/fog_test_body.gd"))
	body.z_index = 1
	add_child(body)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.zoom = Vector2.ONE * GameScale.camera_zoom()
	camera.position = CAMERA_POS
	add_child(camera)
	camera.make_current()
	_events = [
		[2.2, &"walk"], [3.35, &"jump"],
		[5.1, &"fire"], [5.18, &"fire"], [5.26, &"fire"], [6.2, &"punch"],
		[10.2, &"sprint"], [12.8, &"ak"], [15.4, &"stop"], [15.6, &"break"], [18.2, &"roll"], [20.0, &"roll_back"], [21.0, &"dodge"], [22.2, &"fog_off"],
	]
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/fog"
		DirAccess.make_dir_recursive_absolute(_dir)
		_shots = SHOTS.duplicate()
	Fog.enabled = true
	Fog.rebuild_terrain()


func _add_block(r: Rect2, grass: bool) -> void:
	var sb := StaticBody2D.new()
	sb.position = r.position
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.size * 0.5
	sb.add_child(cs)
	var fill := ColorRect.new()
	fill.color = DIRT if grass else STONE
	fill.size = r.size
	sb.add_child(fill)
	if grass:
		var dark := ColorRect.new()
		dark.color = DIRT_DARK
		dark.position = Vector2(0, 60)
		dark.size = Vector2(r.size.x, 24)
		sb.add_child(dark)
	var top := ColorRect.new()
	top.color = GRASS
	top.size = Vector2(r.size.x, 30)
	sb.add_child(top)
	var lit := ColorRect.new()
	lit.color = GRASS_LIGHT
	lit.size = Vector2(r.size.x, 12)
	sb.add_child(lit)
	add_child(sb)


func _floor_at(x: float) -> float:
	for g in GROUND:
		if x >= g[0] and x < g[1]:
			return g[2]
	return 0.0


func _physics_process(delta: float) -> void:
	_tick += 1
	_t = _tick / float(Engine.physics_ticks_per_second)
	while not _events.is_empty() and _t >= _events[0][0] - 0.0001:
		_event(_events.pop_front()[1])
	_move(delta)
	_couple(delta)
	_measure_phase()
	while not _shots.is_empty() and _t >= _shots[0][0] - 0.0001:
		_shot(_shots.pop_front()[1])
	if _t >= END and not _done:
		_done = true
		if _dir.is_empty():
			get_tree().reload_current_scene()
		else:
			_try_quit()


func _event(e: StringName) -> void:
	match e:
		&"walk":
			_mode = &"walk"
		&"jump":
			_vel = Vector2(700.0, -1300.0)
			_air = true
			_mode = &"air"
			# Jump: a small burst under the feet.
			Fog.burst(_pos, 110.0, 0.45)
		&"punch":
			_mode = &"idle"
			_vel = Vector2.ZERO
			body.punch = 0.25
			Fog.push(_pos + Vector2(170.0 * _facing, -250.0), Vector2(1500.0 * _facing, 0.0), 170.0, 1.0)
		&"fire":
			_fire(TARGETS[_shot_i % TARGETS.size()], 1.0)
			_shot_i += 1
		&"sprint":
			_mode = &"sprint"
		&"ak":
			_mode = &"ak"
			_vel = Vector2.ZERO
		&"stop":
			_mode = &"idle"
		&"roll", &"roll_back":
			_mode = &"roll"
			_move_dir = 1.0 if e == &"roll" else -1.0
			_mode_t = ROLL_TIME
			# Roll entry: dust and fog kicked up where the body drops.
			Fog.burst(_pos, 170.0, 0.8)
		&"dodge":
			_mode = &"dodge"
			_move_dir = -_facing
			_mode_t = DODGE_TIME
			# Dodge: a short strong blow along the dodge and a vortex where the body was.
			Fog.push(_pos + Vector2(0.0, -200.0), Vector2(DODGE_SPEED * 1.2 * _move_dir, -200.0), 200.0, 1.2)
			Fog.swirl(_pos + Vector2(0.0, -150.0), 190.0, 1.2 * _move_dir)
		&"break":
			var h: float = wall._h * GameScale.art_pixel()
			wall.break_at(wall.global_position + Vector2(-wall._w * GameScale.art_pixel() * 0.5, -h * 0.6), Vector2(1900.0, -160.0), 1.0)
		&"fog_off":
			Fog.enabled = false


func _fire(target: Vector2, strength: float) -> void:
	var muzzle := _pos + Vector2(140.0 * _facing, -255.0)
	Fog.line(muzzle, target, 14.0, strength)
	Fog.push(muzzle, Vector2(500.0 * _facing, 0.0), 60.0, 0.6)
	if target.y >= _floor_at(target.x) - 70.0:
		Fog.burst(target, 70.0, 0.4)
	body.flash = 0.05


func _move(delta: float) -> void:
	var speed := 0.0
	var dir := _facing
	if _mode == &"walk":
		speed = WALK
	elif _mode == &"sprint":
		speed = SPRINT
	elif _mode == &"roll" or _mode == &"dodge":
		speed = ROLL_SPEED if _mode == &"roll" else DODGE_SPEED
		dir = _move_dir
		_mode_t -= delta
		if _mode_t <= 0.0:
			if _mode == &"roll":
				# Roll exit burst.
				Fog.burst(_pos, 170.0, 0.8)
			_mode = &"idle"
			speed = 0.0
	if not _air:
		_vel.x = speed * dir
	else:
		_vel.y += GRAVITY * delta
	var prev := _pos
	_pos += _vel * delta
	if _mode == &"roll":
		# Roll: sweep the ground-level segment covered this frame.
		Fog.sweep(prev + Vector2(0.0, -50.0), _pos + Vector2(0.0, -50.0), 130.0, 1.1)
	var fy := _floor_at(_pos.x)
	if _air and _vel.y > 0.0 and _pos.y >= fy:
		_pos.y = fy
		var impact := _vel.y
		_vel = Vector2.ZERO
		_air = false
		_mode = &"idle"
		# Landing: radial burst scaled by the fall speed.
		Fog.burst(_pos, 230.0, clampf(impact / 1300.0, 0.3, 1.4))
	elif not _air:
		_pos.y = fy
	if _mode == &"ak" and _t >= _next_fire:
		_next_fire = _t + 1.0 / 12.0
		var far := _pos.x + 1300.0
		_fire(Vector2(far, _floor_at(far) - 20.0 + randf_range(-160.0, 0.0)), 0.8)
	body.position = _pos
	body.scale = Vector2(1.0, 0.4 if _mode == &"roll" else 1.0)
	body.moving = absf(_vel.x) > 1.0 and not _air
	body.phase += absf(_vel.x) * delta / 140.0
	if _mode == &"sprint" or _mode == &"ak":
		camera.position = Vector2(_pos.x + 650.0, CAMERA_POS.y - 120.0)


func _couple(delta: float) -> void:
	# The test body passes its legs and torso every frame, like the player will.
	Fog.set_body(1, _pos + Vector2(0.0, -70.0), _vel, 80.0)
	Fog.set_body(2, _pos + Vector2(0.0, -250.0), _vel, 110.0)
	if body.moving:
		_step_t -= delta
		if _step_t <= 0.0:
			var sprint := absf(_vel.x) > WALK * 1.2
			_step_t = 0.22 if sprint else 0.34
			# Footstep: small burst at the planted foot, larger when sprinting.
			Fog.burst(_pos + Vector2(30.0 * _facing, 0.0), 90.0 if sprint else 70.0, 0.35 if sprint else 0.22)


func _process(delta: float) -> void:
	_frame_dt += delta
	_frame_max = maxf(_frame_max, delta)
	_frame_n += 1


func _measure_phase() -> void:
	for p in PHASES:
		if _t >= p[1] and _t < p[2]:
			var s: Dictionary = _phase.get(p[0], {})
			if s.is_empty():
				s = {"n": 0, "dt": 0.0, "max": 0.0, "cpu": 0.0, "sim": 0.0, "main": 0.0, "fps": 0.0}
				_phase[p[0]] = s
			var st := Fog.stats()
			s.n += 1
			s.frames = s.get("frames", 0) + _frame_n
			s.dt += _frame_dt
			s.max = maxf(s.max, _frame_max)
			s.cpu += st.cpu_usec
			s.sim += st.sim_gpu_ms
			s.main += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
			s.fps += Engine.get_frames_per_second()
		elif _t >= p[2] and _phase.has(p[0]) and not _phase[p[0]].has("printed"):
			var s: Dictionary = _phase[p[0]]
			s.printed = true
			var n := maxf(s.n, 1)
			var fn := maxf(s.get("frames", 0), 1)
			print("FOG phase=%s ticks=%d frame_ms=%.3f max_frame_ms=%.3f fog_cpu_us=%.0f sim_gpu_ms=%.3f main_gpu_ms=%.3f fps=%.0f grid=%s dropped=%d" % [
				p[0], s.n, s.dt / fn * 1000.0, s.max * 1000.0, s.cpu / n, s.sim / n, s.main / n, s.fps / n, Fog.stats().grid, Fog.dropped])
	_frame_dt = 0.0
	_frame_max = 0.0
	_frame_n = 0


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	var image := tex.get_image() if tex else null
	if image:
		var path := _dir.path_join(shot_name + ".png")
		var err := image.save_png(path)
		print("CAPTURE %s size=%s err=%d fps=%d" % [path, image.get_size(), err, Engine.get_frames_per_second()])
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _done and _busy == 0:
		get_tree().quit()
