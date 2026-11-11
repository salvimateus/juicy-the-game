extends SceneTree

# Flag frame sheet: godot --headless -s res://game/interactables/test/flag_frames_sheet.gd -- <out.png>

const Art := preload("res://game/interactables/interactables_art.gd")


func _init() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var s := Art.FLAG_SIZE
	var img := Image.create((s.x + 2) * Art.FLAG_FRAMES, (s.y + 2) * 2, false, Image.FORMAT_RGBA8)
	img.fill(Color("#20202c"))
	for row in 2:
		for f in Art.FLAG_FRAMES:
			var fr := (Art.flag_frame(f, row == 1) as ImageTexture).get_image()
			img.blend_rect(fr, Rect2i(Vector2i.ZERO, s), Vector2i(f * (s.x + 2) + 1, row * (s.y + 2) + 1))
	img.resize(img.get_width() * 8, img.get_height() * 8, Image.INTERPOLATE_NEAREST)
	print("SHEET err=", img.save_png(out))
	quit()
