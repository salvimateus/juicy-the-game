extends Node2D

# Lighting test: a short tunnel with a fake player that walks in, crawls through, pauses in the
# middle (flicker and muzzle flash) and walks out. With `-- --capture <dir>` it saves
# lighting_<name>.png at fixed times and quits.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Lighting := preload("res://game/lighting/lighting.gd")
const ZONE_SCENE := preload("res://game/lighting/lighting_zone.tscn")
const TUNNEL_CEILING := preload("res://game/art/tunnel_ceiling.png")
const TUNNEL_WALL := preload("res://game/art/tunnel_wall.png")
const TUNNEL_FLOOR := preload("res://game/art/tunnel_floor.png")

const A := 6
const X0 := 0.0
const X1 := 1600.0
const CEILING_Y := -216.0
const TOP_Y := -2400.0
const FRAME_W := 96.0
const SKY := Color("#7fa6c9")
# [time, x]: walk in, crawl, pause in the middle, crawl, walk out.
const PATH := [[0.0, -700.0], [2.0, 0.0], [5.0, 750.0], [6.6, 750.0], [10.0, 1600.0], [11.6, 2160.0]]
const SHOTS := [[1.0, "1_outside"], [2.22, "2_entering"], [4.2, "3_middle"], [5.3, "4_flicker_a"],
	[5.75, "4_flicker_b"], [6.0, "5_flash"], [10.22, "6_exiting"], [11.2, "7_outside_after"]]
const FLASH_AT := 6.0
const QUIT_AT := 11.5

var _player: Node2D
var _stand: Sprite2D
var _crawl: Sprite2D
var _camera: Camera2D
var _time := 0.0
var _shot_index := 0
var _flashed := false
var _dir := ""
var _busy := 0


func _ready() -> void:
	Engine.max_fps = 60
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/lighting"
		DirAccess.make_dir_recursive_absolute(_dir)
	RenderingServer.set_default_clear_color(SKY)
	_build_world()
	_build_player()
	_build_hud()
	var zone := ZONE_SCENE.instantiate()
	zone.tunnel_rect = Rect2(X0, CEILING_Y - 260.0, X1 - X0, 260.0 - CEILING_Y + 120.0)
	add_child(zone)
	_camera = Camera2D.new()
	_camera.zoom = Vector2.ONE * GameScale.camera_zoom()
	add_child(_camera)
	_camera.make_current()
	_update(0.0)


func _process(delta: float) -> void:
	_time += delta
	_update(_time)
	if not _flashed and _time >= FLASH_AT:
		_flashed = true
		Lighting.flash(_player.global_position + Vector2(130, -80), 520.0, 0.034)
	while _shot_index < SHOTS.size() and _time >= SHOTS[_shot_index][0]:
		_shot(SHOTS[_shot_index][1])
		_shot_index += 1
	if _time >= QUIT_AT and _busy == 0:
		get_tree().quit()


func _update(t: float) -> void:
	var x: float = PATH[-1][1]
	for k in PATH.size() - 1:
		var a: Array = PATH[k]
		var b: Array = PATH[k + 1]
		if t < b[0]:
			x = lerpf(a[1], b[1], (t - a[0]) / (b[0] - a[0]))
			break
	_player.global_position = Vector2(roundf(x / A) * A, 0)
	var inside := x > X0 + 40.0 and x < X1 - 40.0
	_crawl.visible = inside
	_stand.visible = not inside
	if _camera:
		var view := get_viewport_rect().size / _camera.zoom
		_camera.global_position = Vector2(x + 150.0, -view.y * 0.2)


func _shot(shot_name: String) -> void:
	if _dir.is_empty():
		return
	_busy += 1
	await RenderingServer.frame_post_draw
	var path := _dir.path_join("lighting_%s.png" % shot_name)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " t=%.2f err=%d" % [_time, err])
	_busy -= 1


func _strip(texture: Texture2D, width: float, height: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, width, height)
	return sprite


func _rect(pos: Vector2, size: Vector2, color: Color, z := 0) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	r.z_index = z
	add_child(r)
	return r


func _build_world() -> void:
	# Hills behind, grass ground outside, dirt tunnel in the middle.
	var hills := Polygon2D.new()
	hills.color = Color("#5d7f6a")
	hills.z_index = -20
	hills.polygon = PackedVector2Array([Vector2(-3000, 0), Vector2(-2200, -520), Vector2(-1300, -300),
		Vector2(-600, -640), Vector2(400, -360), Vector2(1400, -700), Vector2(2400, -380),
		Vector2(3400, -560), Vector2(4400, 0)])
	add_child(hills)
	for seg in [[-3000.0, X0], [X1, 4400.0]]:
		_rect(Vector2(seg[0], 0), Vector2(seg[1] - seg[0], 36), PixelArt.GRASS)
		_rect(Vector2(seg[0], 36), Vector2(seg[1] - seg[0], 800), PixelArt.DIRT_DARK)
	var length := X1 - X0
	var back := _strip(TUNNEL_WALL, length, -TOP_Y)
	back.position = Vector2(X0, TOP_Y)
	back.z_index = -5
	add_child(back)
	_rect(Vector2(X0, 0), Vector2(length, 800), Color("#221c20"))
	var floor_sprite := _strip(TUNNEL_FLOOR, length, TUNNEL_FLOOR.get_height())
	floor_sprite.position = Vector2(X0, -9)
	add_child(floor_sprite)
	var mass_h := CEILING_Y - TOP_Y
	_rect(Vector2(X0, TOP_Y), Vector2(length, mass_h - 88), Color("#2a2226"))
	var edge := _strip(TUNNEL_CEILING, length, TUNNEL_CEILING.get_height())
	edge.position = Vector2(X0, CEILING_Y - 88)
	add_child(edge)
	for x in [X0, X1 - FRAME_W]:
		var frame := Sprite2D.new()
		frame.texture = PixelArt.stone_block(int(FRAME_W / A), int(mass_h / A) + 1, true, true)
		frame.centered = false
		frame.scale = Vector2(A, A)
		frame.position = Vector2(x, TOP_Y - PixelArt.STONE_TUFT_ROWS * A)
		frame.z_index = 1
		add_child(frame)


# Rows of the fake body, one char per art pixel: h hair, s skin, t shirt, p pants, b boots.
const STAND := [
	"..hhhh..", ".hhhhhh.", ".hssssh.", ".ssssss.", ".ssssss.", "..ssss..", "...ss...",
	".tttttt.", "tttttttt", "tttttttt", "tttttttt", "tttttttt", "sttttttts", "s.tttt.s",
	"..pppp..", "..pppp..", "..pp.pp.", "..pp.pp.", "..pp.pp.", "..pp.pp.", ".bbb.bbb",
]
const CRAWL := [
	"...............hhh.", "..............hhhhh", "..............hssss", "..ttttttttttt.sssss",
	".ttttttttttttt.sss.", "pptttttttttttt.....", "ppppp.......ss.....", "pp.pp.......ss.....",
	"bb.bb.......ss.....",
]
const COLORS := {"h": Color("#3a2418"), "s": Color("#d8a07a"), "t": Color("#a0432e"),
	"p": Color("#3a4a7a"), "b": Color("#2a1e1a")}


func _figure(rows: Array, scale_k: int) -> Sprite2D:
	var w := 0
	for row in rows:
		w = maxi(w, row.length())
	var img := Image.create(w * scale_k + 2, rows.size() * scale_k + 2, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			var c: Color = COLORS.get(rows[y][x], Color.TRANSPARENT)
			if c.a > 0.0:
				img.fill_rect(Rect2i(1 + x * scale_k, 1 + y * scale_k, scale_k, scale_k), c)
	var out := img.duplicate() as Image
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and img.get_pixel(q.x, q.y).a > 0.0:
					out.set_pixel(x, y, PixelArt.OUTLINE)
					break
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(out)
	sprite.centered = false
	sprite.scale = Vector2(A, A)
	sprite.position = Vector2(-out.get_width() * A * 0.5, -out.get_height() * A)
	return sprite


func _build_player() -> void:
	_player = Node2D.new()
	_player.name = "FakePlayer"
	_player.add_to_group(&"player")
	_player.z_index = 2
	add_child(_player)
	_stand = _figure(STAND, 3)
	_crawl = _figure(CRAWL, 3)
	_player.add_child(_stand)
	_player.add_child(_crawl)


func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	var bar_back := ColorRect.new()
	bar_back.position = Vector2(16, 16)
	bar_back.size = Vector2(200, 18)
	bar_back.color = Color("#141013")
	hud.add_child(bar_back)
	var bar := ColorRect.new()
	bar.position = Vector2(19, 19)
	bar.size = Vector2(140, 12)
	bar.color = Color("#5ec8e8")
	hud.add_child(bar)
	var icon := ColorRect.new()
	icon.position = Vector2(16, 720 - 16 - 96)
	icon.size = Vector2(96, 96)
	icon.color = Color("#e8c060")
	hud.add_child(icon)
	var label := Label.new()
	label.text = "HUD stays lit"
	label.position = Vector2(128, 720 - 48)
	hud.add_child(label)
