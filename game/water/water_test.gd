extends Node2D

# Test bench for the river: a crate falls in (splash and waves), then the dam opens, the valley
# fills until both sides level out, and the river is refilled.
# Interactive: interact (E / Y) opens the hole or refills, attack (J / X) drops a crate,
# jump (Space / A) blows bubbles in the trench, left/right pan the camera.
# Capture: godot --path <project> res://game/water/water_test.tscn -- --capture <dir>
# saves PNGs at SHOTS and logs FPS, ms per simulation tick, active columns and total volume.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const RIVER_SCENE := preload("res://game/water/river.tscn")

const OVERVIEW := Vector2(1488, 330)
const OVERVIEW_ZOOM := 1.0 / 3.0
const DROP_AT := 0.5
const DROP_POS := Vector2(560, -700)
const OPEN_AT := 3.0
const REFILL_AT := 26.0
# [time, name, camera centre, zoom]
const SHOTS := [
	[0.45, "01_still", OVERVIEW, OVERVIEW_ZOOM],
	[0.46, "01_still_close", Vector2(820, 380), 0.5],
	[1.30, "02_splash", Vector2(620, 120), 0.5],
	[1.75, "03_waves", Vector2(700, 160), 0.5],
	[3.12, "04_hole_open", Vector2(1960, 240), 0.5],
	[3.70, "05_jet", OVERVIEW, OVERVIEW_ZOOM],
	[3.71, "05_jet_close", Vector2(2060, 330), 0.5],
	[5.00, "06_running", OVERVIEW, OVERVIEW_ZOOM],
	[8.00, "07_valley_filling", OVERVIEW, OVERVIEW_ZOOM],
	[8.01, "07_valley_close", Vector2(2300, 600), 0.5],
	[12.0, "08_valley_filling", OVERVIEW, OVERVIEW_ZOOM],
	[25.0, "09_equilibrium", OVERVIEW, OVERVIEW_ZOOM],
	[25.01, "09_equilibrium_close", Vector2(1700, 300), 0.5],
	[26.35, "10_reset_mid", OVERVIEW, OVERVIEW_ZOOM],
	[27.6, "11_reset_done", OVERVIEW, OVERVIEW_ZOOM],
	# Clip probes (magenta bodies at the player's z) pushed into the bank, the bed and the dam:
	# nothing magenta may show over earth or stone.
	[28.0, "12_clip_bank", Vector2(330, 200), 0.5],
	[28.05, "13_clip_trench", Vector2(1000, 520), 0.5],
	[28.1, "14_clip_dam", Vector2(1600, 220), 0.5],
	[28.15, "15_clip_overview", OVERVIEW, OVERVIEW_ZOOM],
]
const PROBES_AT := 27.8
# [x, y top-left, width, height] in river units.
const PROBES := [
	[162.0, -42.0, 108.0, 426.0],
	[860.0, 666.0, 426.0, 108.0],
	[1572.0, 40.0, 108.0, 428.0],
	[1650.0, 300.0, 108.0, 426.0],
]

var river: Node2D
var camera: Camera2D
var _dir := ""
var _tick := 0
var _time := 0.0
var _shots: Array = []
var _busy := 0
var _done := false
var _dropped := false
var _opened := false
var _refilled := false
var _volume0 := -1.0
var _frames := 0
var _frame_sum := 0.0
var _frame_max := 0.0
var _step_sum := 0
var _step_n := 0
var _step_max := 0
var _active_max := 0
var _particles_max := 0
var _vent := 0.0
var _probes := false


func _ready() -> void:
	get_tree().physics_interpolation = true
	RenderingServer.set_default_clear_color(PixelArt.SKY)
	_add_hills()
	river = RIVER_SCENE.instantiate()
	add_child(river)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = OVERVIEW
	camera.zoom = Vector2.ONE * OVERVIEW_ZOOM
	add_child(camera)
	camera.make_current()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/water"
		DirAccess.make_dir_recursive_absolute(_dir)
		_shots = SHOTS.duplicate()
	print("WATER test ready capture=%s" % (not _dir.is_empty()))


func _physics_process(delta: float) -> void:
	if not river.is_ready():
		return
	var water: WaterBody = river.water
	if _volume0 < 0.0:
		_volume0 = water.get_total_volume()
		print("WATER columns=%d render_columns=%d volume0=%.0f" % [water.cols, water.rcols, _volume0])
	_tick += 1
	_time = _tick / float(Engine.physics_ticks_per_second)
	_step_sum += water.last_step_usec
	_step_n += 1
	_step_max = maxi(_step_max, water.last_step_usec)
	_active_max = maxi(_active_max, water.active_columns)
	_particles_max = maxi(_particles_max, water.particle_count())
	_vent -= delta
	if _vent <= 0.0:
		_vent = 0.7
		water.emit_bubbles(river.to_global(Vector2(860, 690)), 2)
	if _dir.is_empty():
		_interactive()
		return
	if not _dropped and _time >= DROP_AT:
		_dropped = true
		_drop_crate(DROP_POS)
	if not _opened and _time >= OPEN_AT:
		_opened = true
		if river.open_button and river.open_button.has_method(&"press"):
			river.open_button.press()
		else:
			river.open_hole()
	if not _refilled and _time >= REFILL_AT:
		_refilled = true
		_log_state("before_reset")
		if river.reset_button and river.reset_button.has_method(&"press"):
			river.reset_button.press()
		else:
			river.refill()
	if not _probes and _time >= PROBES_AT:
		_probes = true
		_add_probes()
	if _tick % 60 == 0:
		_log_state("t")
	while not _shots.is_empty() and _time >= _shots[0][0] - 0.001:
		var s: Array = _shots.pop_front()
		camera.position = s[2]
		camera.zoom = Vector2.ONE * s[3]
		camera.reset_physics_interpolation()
		_shot(s[1])
	if _shots.is_empty() and not _done:
		_done = true
		_try_quit()


func _interactive() -> void:
	if Input.is_action_just_pressed(&"interact"):
		if river.hole_open:
			river.refill()
		else:
			river.open_hole()
	if Input.is_action_just_pressed(&"attack"):
		_drop_crate(camera.position + Vector2(_randf_range(-300, 300), -900))
	if Input.is_action_pressed(&"jump"):
		river.water.emit_bubbles(river.to_global(Vector2(860, 690)), 1, Vector2(0, -60))
	var pan := Input.get_axis(&"move_left", &"move_right")
	camera.position.x += pan * 1800.0 / 60.0


func _randf_range(a: float, b: float) -> float:
	return randf_range(a, b)


func _process(delta: float) -> void:
	if _opened or _dropped:
		_frames += 1
		_frame_sum += delta
		_frame_max = maxf(_frame_max, delta)


func _log_state(tag: String) -> void:
	var water: WaterBody = river.water
	var vol := water.get_total_volume()
	print("WATER %s t=%.2f fps=%d render_ms=%.3f step_ms=%.3f step_avg_ms=%.3f substeps=%d active_cols=%d parcels=%d particles=%d flow=%.0f volume=%.0f drift=%+.4f%% clamped=%.1f" % [
		tag, _time, Engine.get_frames_per_second(), water.last_render_usec / 1000.0, water.last_step_usec / 1000.0,
		(_step_sum / float(maxi(_step_n, 1))) / 1000.0, water.last_substeps, water.active_columns,
		water.parcel_count(), water.particle_count(), water.get_flow_rate(), vol,
		(vol - _volume0) / _volume0 * 100.0, water.get_volume_clamped()])


func _drop_crate(at: Vector2) -> void:
	var a := GameScale.art_pixel()
	var body := RigidBody2D.new()
	body.name = "Crate"
	body.position = at
	body.gravity_scale = 2600.0 / float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	body.mass = 2.0
	body.set_meta(&"buoyancy", 1.7)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 12) * a
	shape.shape = rect
	body.add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = _crate_texture()
	sprite.scale = Vector2(a, a)
	body.add_child(sprite)
	add_child(body)


func _crate_texture() -> ImageTexture:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(Color("#8a5a34"))
	for i in 12:
		img.set_pixel(i, 0, Color("#b07a48"))
		img.set_pixel(0, i, Color("#b07a48"))
		img.set_pixel(i, 11, Color("#5a3a22"))
		img.set_pixel(11, i, Color("#5a3a22"))
		img.set_pixel(i, i, Color("#5a3a22"))
		img.set_pixel(11 - i, i, Color("#6e4a2a"))
	return ImageTexture.create_from_image(img)


func _add_probes() -> void:
	var a := GameScale.art_pixel()
	for p in PROBES:
		var w := int(p[2] / a)
		var h := int(p[3] / a)
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color("#ff3cc8"))
		img.fill_rect(Rect2i(0, 0, w, 1), Color("#ffd0f0"))
		img.fill_rect(Rect2i(0, 0, 1, h), Color("#ffd0f0"))
		var s := Sprite2D.new()
		s.texture = ImageTexture.create_from_image(img)
		s.centered = false
		s.scale = Vector2(a, a)
		s.position = river.to_global(Vector2(p[0], p[1]))
		s.z_index = 1
		add_child(s)


func _add_hills() -> void:
	var a := GameScale.art_pixel()
	var tex := PixelArt.hill_tile(320, 60, 30.0, [8.0, 4.0, 2.0], PixelArt.HILL_FAR)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, 800, 60)
	s.scale = Vector2(a, a)
	s.position = Vector2(-1200, -60 * a)
	s.z_index = -5
	add_child(s)


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	var err := image.save_png(path)
	print("CAPTURE %s size=%s err=%d" % [path, image.get_size(), err])
	_log_state(shot_name)
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _done and _busy == 0:
		if _frames > 0:
			print("WATER frames n=%d fps_avg=%.1f frame_avg_ms=%.2f frame_max_ms=%.2f step_avg_ms=%.3f step_max_ms=%.3f active_cols_max=%d particles_max=%d" % [
				_frames, _frames / _frame_sum, _frame_sum / _frames * 1000.0, _frame_max * 1000.0,
				(_step_sum / float(maxi(_step_n, 1))) / 1000.0, _step_max / 1000.0, _active_max, _particles_max])
		get_tree().quit()
