extends Node2D

# Test bench for BreakableWall: ground, a floating stone platform, the wall and a game-zoom camera.
# Interactive: attack (J) kicks the wall, interact (E) restores it.
# Capture: godot --path <project> res://game/breakable/breakable_test.tscn -- --capture <dir>
# kicks left to right at 60% of the wall height, saves PNGs at SHOTS (s after the kick), restores
# and saves RESTORE_SHOTS, then quits. Each shot also gets a close-up crop (`*_crop.png`).

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const WALL_SCENE := preload("res://game/breakable/breakable_wall.tscn")

const KICK_DELAY := 0.5
const KICK := Vector2(1900, -160)
const SHOTS := [0.0, 0.05, 0.15, 0.3, 0.6, 1.2, 2.5]
const RESTORE_AT := 3.0
const RESTORE_SHOTS := [0.12, 0.42, 0.75]
const CROP := Rect2(-480, -720, 1680, 840)

var wall: BreakableWall
var camera: Camera2D
var _dir := ""
var _time := 0.0
var _tick := 0
var _kicked_at := -1.0
var _restored_at := -1.0
var _shots: Array = []
var _busy := 0
var _done := false
var _max_frame := 0.0
var _frames := 0
var _frame_sum := 0.0


func _ready() -> void:
	get_tree().physics_interpolation = true
	RenderingServer.set_default_clear_color(PixelArt.SKY)
	var a := GameScale.art_pixel()
	_add_ground(-2400, 3000, a)
	_add_platform(480, 960, -192, 72, a)
	wall = WALL_SCENE.instantiate()
	wall.position = Vector2.ZERO
	add_child(wall)
	camera = Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.zoom = Vector2.ONE * GameScale.camera_zoom()
	camera.position = Vector2(360, -420)
	add_child(camera)
	camera.make_current()
	print("WALL pieces=%d prefracture_ms=%.2f" % [wall._n, wall.prefracture_usec / 1000.0])
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/breakable"
		DirAccess.make_dir_recursive_absolute(_dir)
		for t in SHOTS:
			_shots.append([KICK_DELAY + t, "break_%04d" % roundi(t * 1000.0)])
		for t in RESTORE_SHOTS:
			_shots.append([KICK_DELAY + RESTORE_AT + t, "restore_%04d" % roundi(t * 1000.0)])


func kick() -> void:
	var a := GameScale.art_pixel()
	var h: float = wall._h * a
	var point := wall.global_position + Vector2(-wall._w * a * 0.5, -h * 0.6)
	wall.break_at(point, KICK, 1.0)
	print("BREAK usec=%d particles=%d" % [wall.last_break_usec, wall._particles.active_count()])


func _physics_process(delta: float) -> void:
	_tick += 1
	_time = _tick / float(Engine.physics_ticks_per_second)
	if _dir.is_empty():
		if Input.is_action_just_pressed(&"attack"):
			if wall.is_broken():
				wall.restore()
			else:
				kick()
		if Input.is_action_just_pressed(&"interact"):
			wall.restore()
		return
	if _kicked_at < 0.0 and _time >= KICK_DELAY - 0.001:
		_kicked_at = _time
		kick()
	if _restored_at < 0.0 and _time >= KICK_DELAY + RESTORE_AT - 0.001:
		_restored_at = _time
		wall.restore()
	while not _shots.is_empty() and _time >= _shots[0][0] - 0.001:
		_shot(_shots.pop_front()[1])
	if _shots.is_empty() and not _done:
		_done = true
		_try_quit()


func _process(delta: float) -> void:
	if _kicked_at >= 0.0 and _time < _kicked_at + 2.5:
		_max_frame = maxf(_max_frame, delta)
		_frames += 1
		_frame_sum += delta


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	var err := image.save_png(path)
	var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var xf := get_viewport().get_canvas_transform()
	var tl := (xf * CROP.position) * scale
	var br := (xf * CROP.end) * scale
	var crop := Rect2i(Vector2i(tl), Vector2i(br - tl)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if crop.size.x > 0 and crop.size.y > 0:
		image.get_region(crop).save_png(_dir.path_join(shot_name + "_crop.png"))
	print("CAPTURE %s size=%s err=%d fps=%d physics_ms=%.2f wall_max_process_us=%d wall_max_physics_us=%d particles=%d" % [path, image.get_size(), err,
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		wall.max_process_usec, wall.max_physics_usec, wall._particles.active_count()])
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _done and _busy == 0:
		if _frames > 0:
			print("FRAMES after kick: n=%d avg_ms=%.2f max_ms=%.2f" % [_frames, _frame_sum / _frames * 1000.0, _max_frame * 1000.0])
		get_tree().quit()


func _add_ground(x0: float, x1: float, a: int) -> void:
	var body := StaticBody2D.new()
	body.set_meta(&"surface", &"grass")
	body.position = Vector2(x0, 0)
	add_child(body)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(x1 - x0, 1800)
	shape.shape = rect
	shape.position = rect.size * 0.5
	body.add_child(shape)
	var fill := ColorRect.new()
	fill.color = PixelArt.DIRT_DARK
	fill.position = Vector2(0, PixelArt.GROUND_TILE_H * a)
	fill.size = Vector2(x1 - x0, 1800)
	body.add_child(fill)
	var sprite := Sprite2D.new()
	sprite.texture = PixelArt.ground_tile()
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, (x1 - x0) / a, PixelArt.GROUND_TILE_H)
	sprite.scale = Vector2(a, a)
	body.add_child(sprite)


func _add_platform(x0: float, x1: float, top: float, thickness: float, a: int) -> void:
	var body := StaticBody2D.new()
	body.set_meta(&"surface", &"stone")
	body.position = Vector2(x0, top)
	add_child(body)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(x1 - x0, thickness)
	shape.shape = rect
	shape.position = rect.size * 0.5
	body.add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = PixelArt.stone_block(int((x1 - x0) / a), int(thickness / a), true, true)
	sprite.centered = false
	sprite.position = Vector2(0, -PixelArt.STONE_TUFT_ROWS * a)
	sprite.scale = Vector2(a, a)
	body.add_child(sprite)
