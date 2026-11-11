extends Node

# Test bench of the menus over the real game scene (game/main.tscn). Interactive: the start menu
# shows, then Esc / Start open the pause (no `pause` action needed). Capture:
# godot --path <project> --resolution 1280x720 res://game/ui/ui_test.tscn -- --ui-capture <dir> [--tag wide]
# saves the start menu, the pause with the gamepad and with the keyboard, then quits.

const MAIN_SCENE := "res://game/main.tscn"
const START_MENU := preload("res://game/ui/start_menu.tscn")
const PAUSE_MENU := preload("res://game/ui/pause_menu.tscn")

var start_menu: CanvasLayer
var pause_menu: CanvasLayer
var _dir := ""
var _tag := "720"
var _t := 0.0
var _steps: Array = []
var _busy := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child((load(MAIN_SCENE) as PackedScene).instantiate())
	pause_menu = PAUSE_MENU.instantiate()
	add_child(pause_menu)
	start_menu = START_MENU.instantiate()
	add_child(start_menu)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--ui-capture")
	if i == -1:
		return
	_dir = args[i + 1]
	var j := args.find("--tag")
	if j != -1:
		_tag = args[j + 1]
	DirAccess.make_dir_recursive_absolute(_dir)
	_steps = [
		[0.7, func() -> void: _shot("start_intro")],
		[4.9, func() -> void: _shot("start_menu")],
		[5.4, func() -> void: start_menu.request_start()],
		[6.4, func() -> void: pause_menu.set(&"_last_keyboard", false); pause_menu.open()],
		[6.8, func() -> void: _shot("pause_gamepad")],
		[7.0, func() -> void: pause_menu.select(1)],
		[7.4, func() -> void: _shot("pause_option_restart")],
		[7.5, func() -> void: pause_menu.set_keyboard(true)],
		[7.9, func() -> void: _shot("pause_keyboard")],
		[8.3, func() -> void: _quit()],
	]


func _process(delta: float) -> void:
	if _dir.is_empty():
		return
	_t += delta
	while not _steps.is_empty() and _t >= _steps[0][0]:
		(_steps.pop_front()[1] as Callable).call()


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _dir.path_join("%s_%s.png" % [shot_name, _tag])
	print("CAPTURE %s size=%s err=%d" % [path, image.get_size(), image.save_png(path)])
	_busy -= 1


func _quit() -> void:
	while _busy > 0:
		await get_tree().process_frame
	get_tree().quit()
