extends Node2D

# Reward flag bench: a physics body in group `player` walks into the flag.
#   godot --path <project> res://game/interactables/test/reward_flag_test.tscn -- --capture <dir>
# Without --capture the walker keeps pacing so the flag can be watched live.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const FLAG := preload("res://game/interactables/reward_flag.tscn")

var flag: Node2D
var walker: CharacterBody2D
var camera: Camera2D
var _dir := ""
var _walking := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(PixelArt.SKY)
	var a := GameScale.art_pixel()
	var ground := Sprite2D.new()
	ground.texture = PixelArt.ground_tile()
	ground.centered = false
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	ground.region_rect = Rect2(0, 0, 400, PixelArt.GROUND_TILE_H)
	ground.scale = Vector2(a, a)
	ground.position = Vector2(-1200, 0)
	add_child(ground)
	flag = FLAG.instantiate()
	flag.position = Vector2(0, 0)
	add_child(flag)
	flag.captured.connect(func(): print("FLAG captured"))
	walker = CharacterBody2D.new()
	walker.name = "Walker"
	walker.add_to_group(&"player")
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 54
	capsule.height = 426
	shape.shape = capsule
	shape.position = Vector2(0, -213)
	walker.add_child(shape)
	var body := ColorRect.new()
	body.color = Color("#3a6c80")
	body.position = Vector2(-54, -426)
	body.size = Vector2(108, 426)
	walker.add_child(body)
	walker.position = Vector2(-700, 0)
	add_child(walker)
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * GameScale.camera_zoom()
	camera.position = Vector2(0, -300)
	add_child(camera)
	camera.make_current()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/reward_flag"
		DirAccess.make_dir_recursive_absolute(_dir)
		_run.call_deferred()
	else:
		_walking = true


func _physics_process(delta: float) -> void:
	if _walking:
		walker.position.x += 500.0 * delta
		if walker.position.x > 700.0:
			walker.position.x = -700.0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _dir.path_join("%s.png" % shot_name)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " err=", err)


func _run() -> void:
	await _wait(0.3)
	await _shot("flag_01_waving_a")
	await _wait(0.22)
	await _shot("flag_02_waving_b")
	_walking = true
	await flag.captured
	_walking = false
	await _wait(0.12)
	await _shot("flag_03_capture_pop")
	await _wait(0.25)
	await _shot("flag_04_capture_burst")
	await _wait(0.5)
	await _shot("flag_05_text_rising")
	walker.position.x = -700.0
	await _wait(1.8)
	await _shot("flag_06_captured_final")
	_walking = true
	await _wait(2.4)
	print("FLAG captured once: ", flag.is_captured)
	await _shot("flag_07_after_second_pass")
	get_tree().quit()
