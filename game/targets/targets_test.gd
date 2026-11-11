extends Node2D

# Test bench of the training targets: ground, a wall, the character rig for scale, the scarecrow,
# the cup range and the balloon launcher. Interactive: left click fires an arrow from the archer
# mark towards the mouse; 1 slash, 2 punch, 3 kick, 4 bullet on the scarecrow; R resets both;
# B toggles the balloons. With `-- --capture <dir>` it plays a scripted run and saves PNGs.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const RIG_SCENE := "res://rig/adventurer.tscn"

const GROUND_X := Vector2(-2400, 5600)
const WALL_X := 5400.0
const ARCHER := Vector2(-700, -250)
const ARCHER_CUPS := Vector2(700, -230)
const ARCHER_BALLOONS := Vector2(2500, -250)
const ARROW_SPEED := 2600.0

@onready var camera: Camera2D = $Camera
@onready var scarecrow: Scarecrow = $Scarecrow
@onready var cup_range: CupRange = $CupRange
@onready var launcher: BalloonLauncher = $BalloonLauncher

var _rig: Node2D
var _bag: Node2D
var _shake := 0.0
var _capture_dir := ""
var _steps: Array = []
var _time := 0.0
var _busy := 0
var _quit := false
var _log_pops := 0
# Stand-in for the player (group `player`, the player's capsule on layer 1): the real player needs
# the rig, which may be mid-edit. It walks at `_walk` and can jump.
var _dummy: CharacterBody2D
var _walk := 0.0


func _ready() -> void:
	get_tree().physics_interpolation = true
	RenderingServer.set_default_clear_color(PixelArt.SKY)
	_build_ground()
	_build_wall()
	# The live rig is opt-in (`-- --rig`): the scale reference otherwise is a 428-unit height post.
	if OS.get_cmdline_user_args().has("--rig") and ResourceLoader.exists(RIG_SCENE):
		_rig = (load(RIG_SCENE) as PackedScene).instantiate()
		_rig.position = Vector2(-420, 0)
		add_child(_rig)
	else:
		_build_height_post()
	_bag = get_node_or_null(^"PunchingBag")
	scarecrow.hit.connect(_on_hit)
	launcher.popped.connect(func(_c, _p): _log_pops += 1)
	if _bag and _bag.has_signal(&"hit"):
		_bag.hit.connect(_on_hit)
	_focus(Vector2(0, -300), 1.0)
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_capture_dir = args[i + 1] if i + 1 < args.size() else "res://captures/targets"
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		_steps = _script()


func _build_ground() -> void:
	var a := GameScale.art_pixel()
	var body := StaticBody2D.new()
	body.name = "Ground"
	body.set_meta(&"surface", &"grass")
	body.position = Vector2(GROUND_X.x, 0)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(GROUND_X.y - GROUND_X.x, 1200)
	shape.shape = rect
	shape.position = rect.size * 0.5
	body.add_child(shape)
	var fill := ColorRect.new()
	fill.color = PixelArt.DIRT_DARK
	fill.position = Vector2(0, PixelArt.GROUND_TILE_H * a)
	fill.size = Vector2(GROUND_X.y - GROUND_X.x, 1200)
	body.add_child(fill)
	var sprite := Sprite2D.new()
	sprite.texture = PixelArt.ground_tile()
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, (GROUND_X.y - GROUND_X.x) / a, PixelArt.GROUND_TILE_H)
	sprite.scale = Vector2(a, a)
	body.add_child(sprite)
	body.z_index = -1
	add_child(body)


# Character height marker: a 428-unit dark post with a notch every 60 units.
func _build_height_post() -> void:
	var a := GameScale.art_pixel()
	var post := Node2D.new()
	post.name = "HeightPost"
	post.position = Vector2(-420, 0)
	post.draw.connect(func():
		var h := roundi(GameScale.character_height() / a)
		post.draw_rect(Rect2(-a, -h * a, 2 * a, h * a), Color("#141013"))
		post.draw_rect(Rect2(0, -h * a + a, a, h * a - a), Color("#6e5c5c"))
		for k in range(10, h, 10):
			post.draw_rect(Rect2(-2 * a, -k * a, a, a), Color("#967e79"))
		post.draw_rect(Rect2(-3 * a, -h * a - a, 6 * a, a), Color("#b81e22")))
	add_child(post)


func _build_wall() -> void:
	var a := GameScale.art_pixel()
	var body := StaticBody2D.new()
	body.name = "Wall"
	body.position = Vector2(WALL_X, -1200)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(240, 1200)
	shape.shape = rect
	shape.position = rect.size * 0.5
	body.add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = PixelArt.stone_block(240 / a, 1200 / a, true, false, false)
	sprite.centered = false
	sprite.scale = Vector2(a, a)
	body.add_child(sprite)
	add_child(body)


func _focus(center: Vector2, zoom: float) -> void:
	camera.zoom = Vector2(zoom, zoom)
	camera.global_position = center
	camera.reset_smoothing()
	camera.reset_physics_interpolation()


func _on_hit(_point: Vector2, damage: float) -> void:
	_shake = maxf(_shake, clampf(damage / 40.0, 0.2, 1.0))
	# Hitstop: a few frames of slow motion, timed in real time.
	Engine.time_scale = 0.08
	get_tree().create_timer(0.05, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 4.0)
		var a := float(GameScale.art_pixel())
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)).round() * a * roundf(_shake * 2.0)
	else:
		camera.offset = Vector2.ZERO


func _physics_process(delta: float) -> void:
	if _dummy:
		_dummy.velocity.x = _walk
		_dummy.velocity.y = 0.0 if _dummy.is_on_floor() and _dummy.velocity.y > 0.0 else _dummy.velocity.y + 2600.0 * delta
		_dummy.move_and_slide()
	if _rig and _rig.has_method(&"set_locomotion"):
		_rig.set_locomotion(0.0, delta)
	if _capture_dir.is_empty():
		return
	_time += delta
	while not _steps.is_empty() and _time >= _steps[0][0]:
		_run(_steps.pop_front())


# --------------------------------------------------------------------------- simulated attacks

func fire_arrow(from: Vector2, at: Vector2, speed := ARROW_SPEED) -> Arrow:
	var d := at - from
	var t := d.length() / speed
	var aim := at - Vector2(0, 0.5 * 1500.0 * t * t)
	return Arrow.spawn(self, from, (aim - from).normalized(), speed)


# Same as the game's shot: a ray from the muzzle on the hitbox layer, first damageable takes it.
func gun_shot(muzzle: Vector2, at: Vector2, damage: float) -> void:
	var dir := (at - muzzle).normalized()
	var q := PhysicsRayQueryParameters2D.create(muzzle, muzzle + dir * 3000.0, Hurtbox.HITBOX_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := get_world_2d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("gun miss")
		return
	var c: Object = hit.collider
	if c is Node and (c as Node).is_in_group(&"damageable"):
		c.take_hit(hit.position, dir, damage, &"bullet")


func strike(target: Node, point: Vector2, dir: Vector2, damage: float, kind: StringName) -> void:
	target.take_hit(point, dir, damage, kind)


func _scarecrow_point(art: Vector2) -> Vector2:
	return scarecrow.global_position + (art - Scarecrow.ORIGIN) * GameScale.art_pixel()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var from := ARCHER
		var mouse := get_global_mouse_position()
		if mouse.x > 2200.0:
			from = ARCHER_BALLOONS
		elif mouse.x > 900.0:
			from = ARCHER_CUPS
		Arrow.spawn(self, from, (mouse - from).normalized(), ARROW_SPEED)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:
				strike(scarecrow, _scarecrow_point(Vector2(30, 45)), Vector2(1, 0.2), 22.0, &"slash")
			KEY_2:
				strike(scarecrow, _scarecrow_point(Vector2(30, 40)), Vector2.RIGHT, 12.0, &"punch")
			KEY_3:
				strike(scarecrow, _scarecrow_point(Vector2(30, 50)), Vector2.RIGHT, 30.0, &"kick")
			KEY_4:
				strike(scarecrow, _scarecrow_point(Vector2(34, 20)), Vector2.RIGHT, 25.0, &"bullet")
			KEY_5:
				if _bag:
					strike(_bag, _bag.global_position + Vector2(-60, -300), Vector2.RIGHT, 10.0, &"punch")
			KEY_6:
				if _bag:
					strike(_bag, _bag.global_position + Vector2(-60, -260), Vector2.RIGHT, 30.0, &"kick")
			KEY_R:
				scarecrow.heal()
				cup_range.reset_cups()
			KEY_B:
				launcher.toggle()
			KEY_ESCAPE:
				get_tree().quit()


# --------------------------------------------------------------------------- capture script

func _script() -> Array:
	var s := []
	var t := 0.4
	s.append([t, "focus", Vector2(-150, -300), 1.0])
	s.append([t + 0.1, "shot", "00_scale"])
	# Scarecrow: three slashes, then an arrow.
	t = 0.8
	var cuts := [Vector2(28, 44), Vector2(38, 52), Vector2(30, 36)]
	for k in 3:
		s.append([t, "slash", cuts[k]])
		s.append([t + 0.04, "shot", "01_slash%d_impact" % (k + 1)])
		s.append([t + 0.22, "shot", "01_slash%d_blood" % (k + 1)])
		t += 0.6
	s.append([t, "arrow_scarecrow"])
	s.append([t + 0.3, "shot", "02_arrow_stuck"])
	s.append([t + 0.7, "shot", "02_sway"])
	s.append([t + 1.6, "shot", "03_stains"])
	t += 1.8
	# Finish it off to see it slump.
	s.append([t, "kill"])
	s.append([t + 1.4, "shot", "04_dead"])
	t += 1.6
	# Cups: an arrow at the base of the pyramid.
	s.append([t, "focus", Vector2(1450, -300), 1.0])
	s.append([t + 0.1, "shot", "10_cups_ready"])
	t += 0.2
	s.append([t, "arrow_cups"])
	var cup_times := [0.12, 0.25, 0.45, 0.7, 1.0, 1.5, 2.5]
	for k in cup_times.size():
		s.append([t + cup_times[k], "shot", "11_cups_%02d" % k])
	t += 2.8
	# Balloons.
	s.append([t, "focus", Vector2(2950, -620), 0.5])
	s.append([t + 0.1, "shot", "20_balloons_a"])
	s.append([t + 0.9, "shot", "20_balloons_b"])
	s.append([t + 1.0, "arrow_balloon"])
	s.append([t + 1.08, "shot", "21_pop_a"])
	s.append([t + 1.2, "shot", "21_pop_b"])
	s.append([t + 1.6, "arrow_balloon"])
	s.append([t + 1.7, "shot", "21_pop_c"])
	s.append([t + 2.4, "shot", "22_ribbon"])
	t += 2.6
	# Resets.
	s.append([t, "focus", Vector2(-150, -300), 1.0])
	s.append([t + 0.05, "heal"])
	s.append([t + 0.1, "shot", "30_healed_flash"])
	s.append([t + 0.8, "shot", "31_healed"])
	t += 1.0
	s.append([t, "focus", Vector2(1450, -300), 1.0])
	s.append([t + 0.05, "reset_cups"])
	s.append([t + 0.3, "shot", "32_cups_building"])
	s.append([t + 1.6, "shot", "33_cups_rebuilt"])
	t += 1.8
	# Punching bag: a combo of punches, then a flying kick.
	s.append([t, "focus", Vector2(-1500, -330), 1.0])
	for k in 4:
		s.append([t + 0.1 + k * 0.28, "punch_bag"])
	s.append([t + 0.14, "shot", "40_bag_punch_squash"])
	s.append([t + 1.0, "shot", "41_bag_combo"])
	s.append([t + 1.6, "kick_bag"])
	var kick_times := [0.05, 0.25, 0.45, 0.7, 1.2, 1.8, 2.6]
	for k in kick_times.size():
		s.append([t + 1.6 + kick_times[k], "shot", "42_bag_kick_%02d" % k])
	# Player vs cups: walking and jumping past the pyramid moves nothing; floor cups get kicked.
	var p := t + 4.4
	s.append([p, "focus", Vector2(1500, -300), 1.0])
	s.append([p, "reset_cups"])
	s.append([p + 1.6, "dummy_at", 900.0])
	s.append([p + 1.65, "walk", 560.0])
	s.append([p + 2.25, "jump"])
	s.append([p + 2.3, "shot", "60_walk_past_pyramid_a"])
	s.append([p + 2.6, "shot", "60_walk_past_pyramid_b"])
	s.append([p + 3.0, "shot", "60_walk_past_pyramid_c"])
	s.append([p + 3.9, "walk", 0.0])
	s.append([p + 4.0, "shot", "61_pyramid_untouched"])
	s.append([p + 4.1, "arrow_cups"])
	s.append([p + 7.0, "dummy_at", 2350.0])
	s.append([p + 7.05, "shot", "62_floor_cups_before"])
	s.append([p + 7.1, "walk", -620.0])
	s.append([p + 7.8, "shot", "63_kick_a"])
	s.append([p + 8.2, "shot", "63_kick_b"])
	s.append([p + 8.7, "shot", "63_kick_c"])
	s.append([p + 9.0, "walk", 0.0])
	s.append([p + 9.6, "shot", "64_after_kicks"])
	# Guns: an AK burst into the pyramid, then revolver shots at the cups on the floor.
	var g := p + 9.8
	s.append([g, "reset_cups"])
	s.append([g + 1.6, "shot", "70_guns_ready"])
	for k in 10:
		s.append([g + 1.7 + k * 0.1, "gun_pyramid", k])
	s.append([g + 1.75, "shot", "71_ak_burst_a"])
	s.append([g + 2.05, "shot", "71_ak_burst_b"])
	s.append([g + 2.5, "shot", "71_ak_burst_c"])
	s.append([g + 3.4, "shot", "72_after_burst"])
	s.append([g + 4.6, "focus", Vector2(1900, -200), 1.0])
	for k in 4:
		s.append([g + 4.8 + k * 0.45, "gun_floor"])
	s.append([g + 4.85, "shot", "73_floor_shot_a"])
	s.append([g + 5.35, "shot", "73_floor_shot_b"])
	s.append([g + 6.6, "shot", "74_floor_after"])
	t = g + 6.8 - 4.4
	s.append([t + 4.4, "focus", Vector2(4700, -300), 1.0])
	s.append([t + 4.45, "lineup"])
	s.append([t + 4.6, "shot", "50_balloon_colors"])
	s.append([t + 4.8, "quit"])
	s.sort_custom(func(x, y): return x[0] < y[0])
	return s


func _run(step: Array) -> void:
	print("[%5.2f] %s" % [_time, " ".join(step.slice(1).map(func(v): return str(v)))])
	match step[1]:
		"focus":
			_focus(step[2], step[3])
		"shot":
			_shot(step[2])
		"slash":
			strike(scarecrow, _scarecrow_point(step[2]), Vector2(1, 0.25).normalized(), 16.0, &"slash")
		"kill":
			strike(scarecrow, _scarecrow_point(Vector2(34, 46)), Vector2(-1, 0), 60.0, &"kick")
		"arrow_scarecrow":
			fire_arrow(ARCHER, _scarecrow_point(Vector2(33, 54)))
		"arrow_cups":
			var base := cup_range.cups[1].global_position
			fire_arrow(ARCHER_CUPS, base)
		"arrow_balloon":
			_shoot_balloon()
		"punch_bag":
			strike(_bag, _bag.global_position + Vector2(-66, -330 + randf_range(-40, 40)), Vector2.RIGHT, 10.0, &"punch")
		"kick_bag":
			strike(_bag, _bag.global_position + Vector2(-66, -250), Vector2(1, -0.15).normalized(), 30.0, &"kick")
		"gun_pyramid":
			var c: RigidBody2D = cup_range.cups[(step[2] * 7) % cup_range.cups.size()]
			gun_shot(Vector2(800, -260), c.global_position + Vector2(0, randf_range(-20, 20)), 30.0)
		"gun_floor":
			var target: RigidBody2D
			for c in cup_range.cups:
				if c.global_position.y > -100.0 and (target == null or c.global_position.x > target.global_position.x):
					target = c
			if target:
				gun_shot(Vector2(2600, -120), target.global_position, 45.0)
			else:
				print("no floor cup")
		"dummy_at":
			_ensure_dummy()
			_dummy.global_position = Vector2(step[2], -2)
			_dummy.velocity = Vector2.ZERO
			_dummy.reset_physics_interpolation()
		"walk":
			_walk = step[2]
		"jump":
			_dummy.velocity.y = -1100.0
		"lineup":
			_build_lineup()
		"heal":
			var b := scarecrow.get_node_or_null(^"HealButton")
			if b and b.has_method(&"press"):
				b.press()
			else:
				scarecrow.heal()
		"reset_cups":
			var b := cup_range.get_node_or_null(^"ResetButton")
			if b and b.has_method(&"press"):
				b.press()
			else:
				cup_range.reset_cups()
		"quit":
			_quit = true
			_try_quit()


func _ensure_dummy() -> void:
	if _dummy:
		return
	_dummy = CharacterBody2D.new()
	_dummy.name = "PlayerDummy"
	_dummy.add_to_group(&"player")
	_dummy.floor_snap_length = 24.0
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 65.0
	cap.height = 365.0
	shape.shape = cap
	shape.position = Vector2(0, -182.5)
	_dummy.add_child(shape)
	_dummy.draw.connect(func():
		var a := float(GameScale.art_pixel())
		_dummy.draw_rect(Rect2(-66, -426, 132, 426), Color("#141013"))
		_dummy.draw_rect(Rect2(-60, -420, 120, 414), Color("#3a5a8c"))
		_dummy.draw_rect(Rect2(-60, -420, 120, 2 * a), Color("#5a7ab0")))
	_dummy.z_index = 2
	add_child(_dummy)


# Every balloon colour beside a character-height post, for the comparison sheet.
func _build_lineup() -> void:
	var a := GameScale.art_pixel()
	var at := BalloonLauncher.atlas()
	var post := get_node(^"HeightPost").duplicate() as Node2D
	post.position = Vector2(4200, 0)
	add_child(post)
	for c in BalloonLauncher.color_count():
		for part in [c, BalloonLauncher.color_count() + BalloonLauncher.RIBBON_SWAY]:
			var sp := Sprite2D.new()
			sp.texture = at.texture
			sp.region_enabled = true
			sp.region_rect = at.rects[part]
			sp.centered = false
			sp.scale = Vector2(a, a)
			var origin := Vector2(4320 + c * 120, -300)
			sp.position = origin - Vector2(BalloonLauncher.KNOT) * a if part == c else origin - Vector2(BalloonLauncher.RIBBON_TOP.x + BalloonLauncher.RIBBON_SWAY, 0) * a
			add_child(sp)


# Aims at the lowest rising balloon, leading its rise.
func _shoot_balloon() -> void:
	var best: Node2D
	for b in launcher.get_children():
		if b is Area2D and b.get(&"alive") and b.global_position.y < launcher.global_position.y - 400.0:
			if best == null or b.global_position.y > best.global_position.y:
				best = b
	if best == null:
		print("no balloon to shoot")
		return
	var target := best.global_position + Vector2(0, -60)
	var t := target.distance_to(ARCHER_BALLOONS) / ARROW_SPEED
	fire_arrow(ARCHER_BALLOONS, target + Vector2(0, -170.0 * t))


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var path := _capture_dir.path_join("%s.png" % shot_name)
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("CAPTURE ", path, " size=", image.get_size(), " err=", err, " pops=", _log_pops)
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _quit and _busy == 0:
		get_tree().quit()
