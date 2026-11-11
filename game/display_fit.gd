extends Node

# Autoload `DisplayFit`: the integer canvas_items stretch fills the whole window on every platform.
# With the base 1280x720, `expand` and an integer scale, a window whose size is not a multiple of the
# base (2400x1080 phone: 1.5 floored to 1; maximized 3440x1380: 1.92 floored to 1) gets a centred
# canvas inside black bars. Here the base size follows the window, divided by an integer k, so the
# canvas covers the window exactly at whole-pixel scale. k is the floored scale, or one more when the
# canvas then keeps at least MIN_BASE_FRACTION of the base on both axes (so a maximized window is not
# drawn at half the size of fullscreen).
# Dev: `--display-probe=<abs .png>` prints the window,
# canvas and transform, saves the window's screen pixels (bars included) and quits after
# `--display-probe-frames=N` frames (90); `--display-resize=WxH` resizes
# the window halfway, `--display-maximize` maximizes it.

const BASE := Vector2i(1280, 720)
const PROBE_FRAMES := 90
# Smallest canvas, as a fraction of BASE, that still takes the next integer scale.
const MIN_BASE_FRACTION := 0.9


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	# Deferred: refitting inside size_changed is overwritten by the stretch update that emitted it,
	# which then shows the full frame squeezed into the old centred rect.
	get_tree().root.size_changed.connect(_fit, CONNECT_DEFERRED)
	_fit()
	var frames := PROBE_FRAMES
	for a in args:
		if a.begins_with("--display-probe-frames="):
			frames = int(a.trim_prefix("--display-probe-frames="))
	for a in args:
		if a.begins_with("--display-probe="):
			_probe(a.trim_prefix("--display-probe="), frames)


func _fit() -> void:
	var win := get_tree().root
	var size := DisplayServer.window_get_size()
	if size.x <= 0 or size.y <= 0:
		return
	var k := scale_for(size)
	var target := Vector2i(size.x / k, size.y / k)
	if win.content_scale_size != target:
		win.content_scale_size = target


static func scale_for(size: Vector2i) -> int:
	var k := maxi(1, floori(minf(float(size.x) / BASE.x, float(size.y) / BASE.y)))
	var min_canvas := Vector2(BASE) * MIN_BASE_FRACTION
	if float(size.x) / (k + 1) >= min_canvas.x and float(size.y) / (k + 1) >= min_canvas.y:
		k += 1
	return k


func _probe(path: String, frames: int) -> void:
	var resize := Vector2i.ZERO
	var maximize := "--display-maximize" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--display-resize="):
			var v := a.trim_prefix("--display-resize=").split("x")
			resize = Vector2i(int(v[0]), int(v[1]))
	for i in frames:
		if i == frames / 2 and maximize:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		if i == frames / 2 and resize != Vector2i.ZERO:
			print("DISPLAY_PROBE before-resize window=%s content_scale_size=%s" % [DisplayServer.window_get_size(), get_tree().root.content_scale_size])
			DisplayServer.window_set_size(resize)
			var screen := DisplayServer.window_get_current_screen()
			DisplayServer.window_set_position(DisplayServer.screen_get_position(screen) + (DisplayServer.screen_get_size(screen) - resize) / 2)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var vp := get_viewport()
	var t := vp.get_final_transform()
	var win_pos := DisplayServer.window_get_position()
	var win_size := DisplayServer.window_get_size()
	print("DISPLAY_PROBE k=%d root=%s window=%s content_scale_size=%s visible_rect=%s final_scale=%s final_offset=%s covered=%s" % [
		scale_for(win_size), get_tree().root.size, win_size, get_tree().root.content_scale_size, vp.get_visible_rect().size, t.get_scale(), t.origin,
		Vector2(vp.get_visible_rect().size) * t.get_scale()])
	var img := DisplayServer.screen_get_image_rect(Rect2i(win_pos, win_size))
	if img:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		print("DISPLAY_PROBE shot %s size=%s err=%s" % [path, img.get_size(), img.save_png(path)])
	get_tree().quit()
