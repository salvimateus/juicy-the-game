extends Node2D

# Motocross stage: the player starts on foot at the start line, walks to the parked bike and
# mounts it (Y / E), rides the tabletop to the finish against the clock and may get off when
# stopped. A crash throws the rider and respawns both, mounted, at the start (Trials style).
# The stage owns the juice: engine loop and rumble, roost, landing dust, shake, crash hitstop.

const T := preload("res://game/moto/moto_tuning.gd")
const MotoArt := preload("res://game/moto/moto_art.gd")
const MotoTrack := preload("res://game/moto/moto_track.gd")
const MotoBike := preload("res://game/moto/moto_bike.gd")
const MotoCamera := preload("res://game/moto/moto_camera.gd")
const MotoHud := preload("res://game/moto/moto_hud.gd")
const MotoCapture := preload("res://game/moto/moto_capture.gd")
const LevelScript := preload("res://game/level.gd")
const DebrisParticles := preload("res://game/breakable/debris_particles.gd")
const PauseController := preload("res://game/pause_controller.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")

# Pause menu rows, same formats as PAD_LEGEND / KEY_LEGEND in game/ui/pause_menu.gd.
const LEGENDS := {
	"pad": [
		["lt", -1, "h", 0, "LT", "frear - parado: ré"],
		["view", -1, "up", 16, "Back", "recomeçar na largada, montado"],
		["left_stick", -1, "h", 0, "Analógico esquerdo", "a pé: andar - na moto: inclinar para trás / para a frente (no ar: girar)"],
		["dpad", -1, "h", 0, "Direcional esq. / dir.", "na moto: inclinar (no ar: girar)"],
		["menu", 1, "up", 22, "Menu", "pausa"],
		["rt", 1, "h", 0, "RT", "acelerar"],
		["y", 1, "h", 0, "Y", "montar na moto - parado: descer"],
		["b", 1, "h", 0, "B", "a pé: esquiva - na moto: frear e ré"],
		["a", 1, "h", 0, "A", "a pé: pular - na moto: acelerar"],
	],
	"keys": [
		[["A", "D"], "a pé: andar (ou as setas) - na moto: inclinar (no ar: girar)"],
		[["W"], "na moto: acelerar (ou seta para cima)"],
		[["S"], "na moto: frear - parado: ré (ou seta para baixo)"],
		[["Espaço"], "a pé: pular"],
		[["E"], "montar na moto - parado: descer"],
		[["R"], "recomeçar na largada, montado"],
		[["Esc"], "pausa"],
	],
}

@onready var player: CharacterBody2D = $Player
@onready var game_camera: Camera2D = $Camera
@onready var interaction: Node2D = $InteractionManager

var backdrop: Node2D
var track: Node2D
var bike: Node2D
var moto_camera: Camera2D
var debris: MultiMeshInstance2D
var hud: CanvasLayer
var pause: Node
var capture: Node
var run_time := 0.0
var timing := false
var art_ready := false

var _a := 6
var _engine_sfx := -1
var _engine_haptic := -1
var _engine_level := 0.0
var _respawn_token := 0
var _fade: ColorRect
var _riding_camera := false


func _ready() -> void:
	get_tree().physics_interpolation = true
	_a = GameScale.art_pixel()
	var fog := get_node_or_null(^"/root/Fog")
	if fog:
		fog.enabled = false
	backdrop = Node2D.new()
	backdrop.name = "Backdrop"
	backdrop.set_script(LevelScript)
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.build_backdrop()
	RenderingServer.set_default_clear_color(backdrop.sky_color)
	track = Node2D.new()
	track.name = "Track"
	track.set_script(MotoTrack)
	add_child(track)
	move_child(track, 1)
	track.build()
	_build_finish_line()
	bike = Node2D.new()
	bike.name = "Bike"
	bike.set_script(MotoBike)
	add_child(bike)
	move_child(bike, 2)
	bike.setup(track, player)
	bike.park_at(T.PARK_X)
	bike.mounted.connect(_on_mounted)
	bike.dismounted.connect(_on_dismounted)
	bike.landed.connect(_on_landed)
	bike.crashed.connect(_on_crashed)
	bike.respawned.connect(_on_respawned)
	bike.flipped.connect(_on_flipped)
	player.global_position = Vector2(T.SPAWN_X, track.height_at(T.SPAWN_X))
	player.reset_physics_interpolation()
	player.set_facing(1)
	player.combat.set_holstered(true, &"moto")
	player.combat.bow.aim.allow_mouse = false
	player.combat.guns.aim.allow_mouse = false
	interaction.player = player
	game_camera.setup(player, track.bounds)
	moto_camera = Camera2D.new()
	moto_camera.name = "MotoCamera"
	moto_camera.set_script(MotoCamera)
	# Set before entering the tree: with physics interpolation an idle-mode Camera2D warns on entry.
	moto_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	add_child(moto_camera)
	moto_camera.set_bounds(track.bounds)
	game_camera.make_current()
	debris = MultiMeshInstance2D.new()
	debris.name = "Debris"
	debris.set_script(DebrisParticles)
	add_child(debris)
	debris.setup(_a)
	debris.z_index = 2
	hud = CanvasLayer.new()
	hud.name = "MotoHud"
	hud.set_script(MotoHud)
	add_child(hud)
	hud.set_hint(&"foot")
	pause = PauseController.new()
	pause.name = "Menus"
	add_child(pause)
	pause.setup(false, LEGENDS)
	pause.covered_changed.connect(func(on: bool) -> void: hud.visible = not on)
	_build_fade()
	MotoArt.start()
	capture = MotoCapture.new()
	if capture.configure(OS.get_cmdline_user_args()):
		capture.name = "MotoCapture"
		capture.level = self
		add_child(capture)
	else:
		capture.free()
		capture = null


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)


# Checkered flag on a pole, procedural, at FINISH_X.
func _build_finish_line() -> void:
	var w := 14
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in h:
		img.set_pixel(0, y, Color("#141013"))
		img.set_pixel(1, y, T.FINISH_POLE_COLOR)
		img.set_pixel(2, y, Color("#141013"))
	for y in 12:
		for x in 11:
			var dark := ((x / 3) + (y / 3)) % 2 == 0
			img.set_pixel(3 + x, 1 + y, T.FINISH_FLAG_A if dark else T.FINISH_FLAG_B)
	for x in 12:
		img.set_pixel(2 + x, 0, Color("#141013"))
		img.set_pixel(2 + x, 13, Color("#141013"))
	for y in 14:
		img.set_pixel(13, y, Color("#141013"))
	var tex := ImageTexture.create_from_image(img)
	for side in [-1, 1]:
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.scale = Vector2.ONE * _a
		s.flip_h = side < 0
		var x: float = T.FINISH_X + side * 6.0 * _a
		s.position = Vector2(roundf(x / _a) * _a - (w * _a if side < 0 else 0.0), roundf(track.height_at(T.FINISH_X) / _a) * _a - h * _a)
		s.z_index = T.TRACK_Z
		add_child(s)
	# The line itself on the dirt.
	var line := ColorRect.new()
	line.color = T.FINISH_POLE_COLOR
	line.position = Vector2(roundf(T.FINISH_X / _a) * _a, roundf(track.height_at(T.FINISH_X) / _a) * _a - _a)
	line.size = Vector2(_a, _a * 2)
	line.z_index = T.TRACK_Z
	add_child(line)


func _process(delta: float) -> void:
	if not art_ready and MotoArt.poll():
		art_ready = true
		bike.show_art()
		var tw := create_tween()
		tw.tween_property(_fade, ^"color:a", 0.0, T.FADE_IN)
		tw.tween_callback(_fade.hide)
	var cam: Camera2D = moto_camera if _riding_camera else game_camera
	var view: Vector2 = cam.view_size()
	var ratio: float = T.FLOOR_SCREEN_RATIO if _riding_camera else game_camera.floor_screen_ratio
	backdrop.update_parallax(cam.get_screen_center_position(), -view.y * (ratio - 0.5), view)
	if get_tree().paused:
		return
	if Input.is_action_just_pressed(&"moto_restart") and art_ready:
		restart()
	_update_run(delta)
	_update_engine(delta)
	_emit_roost()
	_update_hint()


func _physics_process(delta: float) -> void:
	if _riding_camera and delta > 0.0:
		var p: Vector2 = bike.pos
		moto_camera.follow(Vector2(p.x, p.y + T.CAMERA_FLOOR_OFFSET), bike.vel, bike.wheels_down() > 0 or bike.is_crashed(), delta)


func _update_run(delta: float) -> void:
	if not bike.is_ridden() or bike.finished:
		return
	# A run is timed from the first throttle before the finish line.
	if not timing and bike.throttle > 0.05 and bike.pos.x < T.FINISH_X:
		timing = true
		run_time = 0.0
	if timing:
		run_time += delta
		hud.set_time(run_time)
	if timing and bike.pos.x >= T.FINISH_X:
		_finish()


func _finish() -> void:
	bike.finished = true
	timing = false
	var is_record: bool = hud.submit(run_time)
	hud.show_finish(run_time, is_record)
	Feedback.sfx(&"achievement", bike.pos)
	Feedback.haptic(&"achievement")
	moto_camera.add_shake(T.FINISH_SHAKE, 0.2)
	var top := Vector2(T.FINISH_X, float(track.height_at(T.FINISH_X)) - 64.0 * _a)
	for i in 30:
		var c: Color = [Color("#f95f03"), Color("#f7a939"), Color("#f4e6e6"), Color("#fc8c2f")][i % 4]
		debris.emit(top + Vector2(randf_range(-60, 60), 0), Vector2(randf_range(-500, 500), randf_range(-900, -300)), randf_range(0.8, 1.4), 1, c, 1400.0, 0.8, track.height_at(T.FINISH_X), false)


func _update_engine(delta: float) -> void:
	var on: bool = bike.is_ridden()
	if on and _engine_sfx < 0:
		_engine_sfx = Feedback.sfx_loop(&"moto_engine", bike.pos)
		_engine_haptic = Feedback.haptic_loop(&"moto_engine", T.RUMBLE_IDLE)
		_engine_level = T.ENGINE_IDLE
		Feedback.sfx_loop_update(_engine_sfx, _engine_level, bike.pos)
	elif not on and _engine_sfx >= 0:
		_stop_engine()
	if _engine_sfx < 0:
		return
	var air: bool = bike.wheels_down() == 0
	var want: float = T.ENGINE_IDLE + bike.throttle * T.ENGINE_THROTTLE
	want += clampf(absf(bike.ground_speed) / T.TOP_SPEED, 0.0, 1.0) * T.ENGINE_SPEED * (0.0 if air else 1.0)
	if air:
		want += bike.throttle * T.ENGINE_AIR_REV
	_engine_level = lerpf(_engine_level, clampf(want, 0.0, 1.0), 1.0 - exp(-T.ENGINE_SMOOTHING * delta))
	Feedback.sfx_loop_update(_engine_sfx, _engine_level, bike.pos)
	Feedback.haptic_loop_strength(_engine_haptic, T.RUMBLE_IDLE + bike.throttle * T.RUMBLE_THROTTLE)


func _stop_engine() -> void:
	Feedback.sfx_stop(_engine_sfx, 0.25)
	Feedback.haptic_stop(_engine_haptic)
	_engine_sfx = -1
	_engine_haptic = -1


# Dirt thrown back by the rear wheel while it drives hard (spinning up or pulling from low speed).
func _emit_roost() -> void:
	if not bike.is_ridden() or bike.depth[0] <= 0.0 or bike.throttle < 0.1:
		return
	if bike.rear_slip < T.ROOST_MIN_SLIP and absf(bike.ground_speed) > 900.0:
		return
	var c: Vector2 = bike.wheel_contact(0)
	var back := Vector2.from_angle(float(bike.angle) + PI)
	for i in T.ROOST_PER_FRAME:
		var v: Vector2 = (back * randf_range(0.5, 1.0) + Vector2(0, -randf_range(0.3, 0.9))) * T.ROOST_SPEED * bike.throttle
		var col: Color = T.ROOST_COLORS[randi() % T.ROOST_COLORS.size()]
		debris.emit(c + Vector2(randf_range(-10, 10), -4), v + bike.vel * 0.15, randf_range(0.3, 0.55), 1, col, T.DUST_GRAVITY, 1.5, track.height_at(c.x), false)


func _dust(at: Vector2, count: int, power: float) -> void:
	for i in count:
		var dir := Vector2(randf_range(-1.0, 1.0), -randf_range(0.2, 0.8)).normalized()
		var col: Color = T.DUST_COLORS[randi() % T.DUST_COLORS.size()]
		var size := 2 if randf() < 0.3 * power else 1
		debris.emit(at + Vector2(randf_range(-30, 30), -6), dir * randf_range(150.0, 520.0) * power, T.DUST_LIFE * randf_range(0.7, 1.3), size, col, T.DUST_GRAVITY, T.DUST_DRAG, track.height_at(at.x), true)


func _update_hint() -> void:
	match bike.mode:
		MotoBike.Mode.PARKED, MotoBike.Mode.APPROACH:
			hud.set_hint(&"foot")
		MotoBike.Mode.RIDING:
			if bike.finished:
				hud.set_hint(&"finished")
			elif bike.can_dismount():
				hud.set_hint(&"stopped")
			else:
				hud.set_hint(&"riding")
		MotoBike.Mode.CRASHED:
			hud.set_hint(&"crashed")


# --- Bike events --------------------------------------------------------------------------------

func _on_mounted() -> void:
	_use_moto_camera(true)


func _on_dismounted() -> void:
	_use_moto_camera(false)
	timing = false


func _on_landed(impact: float) -> void:
	var k := clampf(impact / T.HARD_LANDING, 0.15, 1.2)
	for w in 2:
		if bike.depth[w] > 0.0:
			var c: Vector2 = bike.wheel_contact(w)
			Feedback.sfx(&"land", c, k, &"dirt")
			_dust(c, roundi(T.LAND_DUST * k), k)
	Feedback.haptic(&"land", k)
	moto_camera.add_shake(impact * T.SHAKE_PER_IMPACT, T.SHAKE_LANDING_TIME)


# A flip that landed on the wheels: banner, the achievement sound and pulse, a pop of confetti.
func _on_flipped(turns: int, dir: int) -> void:
	var word := "MORTAL" if dir < 0 else "MORTAL DE FRENTE"
	if turns == 2:
		word += " DUPLO"
	elif turns > 2:
		word += " TRIPLO"
	hud.show_trick(word + "!")
	Feedback.sfx(&"achievement", bike.pos, 0.8)
	Feedback.haptic(&"achievement", 0.8)
	moto_camera.add_shake(T.FLIP_SHAKE, 0.2)
	var at: Vector2 = bike.pos + Vector2(0, -200)
	var floor_y: float = track.height_at(bike.pos.x)
	for i in T.FLIP_CONFETTI:
		var c: Color = [Color("#f95f03"), Color("#f7a939"), Color("#f4e6e6"), Color("#fc8c2f")][i % 4]
		debris.emit(at + Vector2(randf_range(-80, 80), 0), bike.vel * 0.6 + Vector2(randf_range(-450, 450), randf_range(-950, -350)), randf_range(0.7, 1.2), 1, c, 1400.0, 0.8, floor_y, false)


func _on_crashed() -> void:
	_stop_engine()
	timing = false
	Feedback.sfx(&"moto_crash", bike.pos)
	Feedback.haptic(&"moto_crash", T.CRASH_RUMBLE)
	moto_camera.add_shake(T.SHAKE_CRASH, T.SHAKE_CRASH_TIME)
	_dust(Vector2(bike.pos.x, track.height_at(bike.pos.x)), T.CRASH_DUST, 1.2)
	if player.has_method(&"hitstop"):
		player.hitstop(T.HITSTOP_CRASH)
	_respawn_token += 1
	var token := _respawn_token
	get_tree().create_timer(T.RESPAWN_DELAY, false).timeout.connect(func() -> void:
		if token == _respawn_token and is_inside_tree():
			restart())


func _on_respawned() -> void:
	timing = false
	run_time = 0.0
	hud.set_time(0.0)
	hud.hide_finish()
	# The manager only routes interact to the interactable that took the player; a mounted spawn
	# never went through it.
	interaction.set(&"_active", bike)


# Back to the start line, mounted (Back / R, and after a crash).
func restart(x: float = T.PARK_X) -> void:
	_respawn_token += 1
	bike.spawn_mounted(x)
	if not _riding_camera:
		_use_moto_camera(true)
	moto_camera.snap_to(Vector2(bike.pos.x, bike.pos.y + T.CAMERA_FLOOR_OFFSET))


func _use_moto_camera(on: bool) -> void:
	if on == _riding_camera:
		return
	_riding_camera = on
	if on:
		var p: Vector2 = bike.pos
		moto_camera.begin_at(game_camera.get_screen_center_position(), p.y + T.CAMERA_FLOOR_OFFSET)
	else:
		game_camera.global_position = moto_camera.get_screen_center_position()
		game_camera.reset_smoothing()
		game_camera.reset_physics_interpolation()
		game_camera.make_current()


func _exit_tree() -> void:
	Engine.time_scale = 1.0
	_stop_engine()
	if bike and is_instance_valid(bike):
		bike.release_rider()
	if player and is_instance_valid(player) and player.has_method(&"release_feedback"):
		player.release_feedback()
