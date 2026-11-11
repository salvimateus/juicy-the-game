extends Node2D

# Test bench for EndingWall: ground, the wall, a fake player against it and a fixed game-zoom camera.
# Interactive: hold right to push. Capture:
# godot --path <project> res://game/ending/ending_test.tscn -- --capture <dir>
# pushes from PUSH_AT until the end screen, saves the PNGs of the sequence and quits.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const WALL_SCENE := preload("res://game/ending/ending_wall.tscn")
const FakePlayer := preload("res://game/ending/fake_player.gd")
const TestCamera := preload("res://game/ending/test_camera.gd")

const WALL_X := 960.0
const PUSH_AT := 0.6
const QUIT_AFTER := 40.0
# Capture lets go of the wall here (past the point of no return) unless --hold is given.
const RELEASE_AT := 0.75

var wall: EndingWall
var player: CharacterBody2D
var camera: Camera2D
var _dir := ""
var _time := 0.0
var _busy := 0
var _done := false
var _taken := {}
var _collapse_at := -1.0
var _covered_at := -1.0
var _fim_at := -1.0
var _thanks_at := -1.0
var _hold := false
var _released := false


func _ready() -> void:
	get_tree().physics_interpolation = true
	RenderingServer.set_default_clear_color(PixelArt.SKY)
	var a := GameScale.art_pixel()
	_add_ground(-3000, 3000, a)
	wall = WALL_SCENE.instantiate()
	wall.position = Vector2(WALL_X, 0)
	add_child(wall)
	player = CharacterBody2D.new()
	player.set_script(FakePlayer)
	player.position = Vector2(WALL_X - 80.0, -2.0)
	add_child(player)
	camera = Camera2D.new()
	camera.set_script(TestCamera)
	camera.zoom = Vector2.ONE * GameScale.camera_zoom()
	camera.position = Vector2(WALL_X - 900.0, -420.0)
	add_child(camera)
	camera.make_current()
	wall.collapse_started.connect(func() -> void: _collapse_at = _time)
	wall.screen_covered.connect(func() -> void: _covered_at = _time)
	wall.ending_shown.connect(func() -> void: _fim_at = _time)
	wall.credits_shown.connect(func() -> void: _thanks_at = _time)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/ending"
		DirAccess.make_dir_recursive_absolute(_dir)
		player.scripted = true
		_hold = args.has("--hold")


func _physics_process(delta: float) -> void:
	_time += delta
	if _dir.is_empty():
		return
	if not _hold and wall.progress >= RELEASE_AT and not _released:
		_released = true
		print("RELEASE t=%.2f progress=%.2f" % [_time, wall.progress])
	player.pushing = _time >= PUSH_AT and not _released and not player.is_controlled()
	_take("01_sign", _time >= 0.3)
	_take("02_progress_20", wall.progress >= 0.2)
	_take("03_progress_60", wall.progress >= 0.6)
	_take("03b_point_of_no_return", wall.progress >= wall.point_of_no_return + 0.02)
	_take("04_progress_95", wall.progress >= 0.95)
	_take("05_collapse_start", _collapse_at >= 0.0 and _time >= _collapse_at + 0.6)
	_take("05b_collapse_rocks", _collapse_at >= 0.0 and _time >= _collapse_at + 1.4)
	_take("06_pile_growing", wall.coverage() >= 0.45)
	_take("06b_pile_high", wall.coverage() >= 0.8)
	_take("07_covered", _covered_at >= 0.0 and _time >= _covered_at + 0.4)
	_take("08_fim", _fim_at >= 0.0 and _time >= _fim_at + 0.9)
	_take("09_obrigado", _thanks_at >= 0.0 and _time >= _thanks_at + 0.3)
	_take("10_juicy", _thanks_at >= 0.0 and _time >= _thanks_at + 3.6)
	if (_taken.size() >= 13 or _time > QUIT_AFTER) and not _done:
		_done = true
		_try_quit()


func _take(shot_name: String, cond: bool) -> void:
	if cond and not _taken.has(shot_name):
		_taken[shot_name] = true
		_shot(shot_name)


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	var err := image.save_png(path)
	if shot_name == "01_sign":
		# Close-up of the sign next to the character, for the art check.
		var scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
		var xf := get_viewport().get_canvas_transform()
		var tl := (xf * Vector2(WALL_X - 900.0, -500.0)) * scale
		var br := (xf * Vector2(WALL_X + 60.0, 40.0)) * scale
		var crop := Rect2i(Vector2i(tl), Vector2i(br - tl)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		var sheet := image.get_region(crop)
		sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
		sheet.save_png(_dir.path_join("01_sign_sheet.png"))
	print("CAPTURE %s t=%.2f progress=%.2f coverage=%.2f fps=%d err=%d" % [path, _time, wall.progress, wall.coverage(), Engine.get_frames_per_second(), err])
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _done and _busy == 0:
		print("TIMES collapse=%.2f covered=%.2f fim=%.2f thanks=%.2f" % [_collapse_at, _covered_at, _fim_at, _thanks_at])
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
