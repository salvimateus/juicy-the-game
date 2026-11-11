extends Node2D

# Debug capture mode: godot --path <project> -- --capture <dir> [--frames N]
var _capture_dir := ""
var _frames_left := 0
var _capturing := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i == -1:
		return
	_capture_dir = args[i + 1] if i + 1 < args.size() else "res://captures"
	var f := args.find("--frames")
	_frames_left = int(args[f + 1]) if f != -1 and f + 1 < args.size() else 10
	_print_joypads()


func _process(_delta: float) -> void:
	if _capture_dir.is_empty() or _capturing:
		return
	_frames_left -= 1
	if _frames_left > 0:
		return
	_capturing = true
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_capture_dir)
	var path := _capture_dir.path_join("capture_%s.png" % Time.get_datetime_string_from_system().replace(":", "-"))
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("CAPTURE ", path, " size=", image.get_size(), " err=", err)
	get_tree().quit()


func _print_joypads() -> void:
	var pads := Input.get_connected_joypads()
	print("JOYPADS count=", pads.size())
	for id in pads:
		print("JOYPAD id=%d name=\"%s\" guid=%s known=%s" % [id, Input.get_joy_name(id), Input.get_joy_guid(id), Input.is_joy_known(id)])
