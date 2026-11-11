extends Node2D

# Test bench for the interactables: ground, every object, a fake player and the manager.
# Interactive by default (walk with the stick or A/D, Y/E interacts). Capture mode follows
# game/capture_driver.gd: `-- --capture <dir>` runs a scripted visit of each object, saves PNGs
# and quits.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const FakePlayer := preload("res://game/interactables/test/fake_player.gd")
const CHAIR := preload("res://game/interactables/chair.tscn")
const BED := preload("res://game/interactables/bed.tscn")
const TRAP := preload("res://game/interactables/damage_trap.tscn")
const TURRET := preload("res://game/interactables/turret.tscn")
const RESET := preload("res://game/interactables/reset_button.tscn")
const MANAGER := preload("res://game/interactables/interaction_manager.tscn")

const FLOOR_SCREEN_RATIO := 0.72
const X0 := -900.0
const X1 := 7200.0

var player: Node2D
var manager: Node2D
var camera: Camera2D
var chair: Node2D
var bed: Node2D
var trap: Node2D
var turret: Node2D
var reset_button: Node2D
var _dir := ""
var _reset_count := 0


func _ready() -> void:
	RenderingServer.set_default_clear_color(PixelArt.SKY)
	_build_ground()
	chair = _add(CHAIR, 600)
	bed = _add(BED, 1500)
	trap = _add(TRAP, 2700)
	turret = _add(TURRET, 4500)
	reset_button = _add(RESET, 5400)
	reset_button.prompt = "Resetar os copos"
	reset_button.pressed.connect(func(): _reset_count += 1; print("RESET pressed ", _reset_count))
	player = FakePlayer.new()
	player.name = "FakePlayer"
	player.position = Vector2(150, 0)
	add_child(player)
	manager = MANAGER.instantiate()
	add_child(manager)
	manager.player = player
	camera = Camera2D.new()
	camera.zoom = Vector2.ONE * GameScale.camera_zoom()
	add_child(camera)
	camera.make_current()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/interactables"
		DirAccess.make_dir_recursive_absolute(_dir)
		player.input_enabled = false
		for action in InputMap.get_actions():
			if not String(action).begins_with("ui_"):
				InputMap.action_erase_events(action)
		_run_capture.call_deferred()


func _add(scene: PackedScene, x: float) -> Node2D:
	var n := scene.instantiate() as Node2D
	n.position = Vector2(x, 0)
	add_child(n)
	return n


func _build_ground() -> void:
	var a := GameScale.art_pixel()
	var sprite := Sprite2D.new()
	sprite.texture = PixelArt.ground_tile()
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, (X1 - X0) / a, PixelArt.GROUND_TILE_H)
	sprite.scale = Vector2(a, a)
	sprite.position = Vector2(X0, 0)
	sprite.z_index = -1
	add_child(sprite)
	var fill := ColorRect.new()
	fill.color = PixelArt.DIRT_DARK
	fill.position = Vector2(X0, PixelArt.GROUND_TILE_H * a)
	fill.size = Vector2(X1 - X0, 1800)
	fill.z_index = -1
	add_child(fill)


func _process(_delta: float) -> void:
	var view := get_viewport_rect().size / camera.zoom
	camera.position = Vector2(player.position.x, -view.y * (FLOOR_SCREEN_RATIO - 0.5))


# --- Capture sequence -----------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


func _go(x: float) -> void:
	player.position = Vector2(x, 0)
	await _frames(1)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _dir.path_join("%s.png" % shot_name)
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("CAPTURE ", path, " size=", image.get_size(), " err=", err)


# Waits for a signal with a timeout; returns the emitted args, or null on timeout.
func _await_signal(sig: Signal, timeout: float) -> Variant:
	var box := {done = false, args = null}
	var cb := func(a = null, b = null):
		if not box.done:
			box.done = true
			box.args = [a, b]
	sig.connect(cb, CONNECT_ONE_SHOT)
	var t := 0.0
	while not box.done and t < timeout:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	if not box.done:
		print("SIGNAL TIMEOUT ", sig.get_name())
		if sig.is_connected(cb):
			sig.disconnect(cb)
	return box.args


func _run_capture() -> void:
	await _frames(5)
	# Chair, keyboard icon.
	manager.use_gamepad = false
	await _go(chair.position.x - 96)
	await _wait(0.4)
	await _shot("01_chair_prompt_key")
	await _tap(&"interact")
	await _wait(0.9)
	print("CHAIR state=", chair.state, " controlled=", player.is_controlled(), " rig=", player.adventurer.current_action())
	await _shot("02_chair_sitting")
	await _tap(&"interact")
	await _wait(0.8)
	print("CHAIR after exit state=", chair.state, " controlled=", player.is_controlled())
	await _shot("03_chair_stood_up")
	# Bed, gamepad icon; leave with the stick.
	manager.use_gamepad = true
	await _go(bed.position.x + 120)
	await _wait(0.4)
	await _shot("04_bed_prompt_pad")
	await _tap(&"interact")
	await _wait(1.3)
	print("BED state=", bed.state, " rig=", player.adventurer.current_action())
	await _shot("05_bed_sleeping")
	Input.action_press(&"move_right", 1.0)
	await _frames(3)
	Input.action_release(&"move_right")
	await _wait(0.9)
	print("BED after stick state=", bed.state, " controlled=", player.is_controlled())
	await _shot("06_bed_got_up")
	# Trap: hit.
	await _go(trap.position.x)
	await _wait(0.4)
	await _shot("07_trap_prompt")
	await _tap(&"interact")
	await _wait(0.25)
	await _shot("08_trap_falling")
	var res = await _await_signal(trap.impact, 3.0)
	print("TRAP impact ", res)
	await _shot("09_trap_impact")
	await _wait(0.3)
	await _shot("10_trap_after")
	await _await_signal(trap.rearmed, 6.0)
	# Trap: dodge (invulnerable as during a roll).
	await _go(trap.position.x)
	await _wait(0.3)
	player.invulnerable = true
	await _tap(&"interact")
	res = await _await_signal(trap.impact, 3.0)
	print("TRAP dodge impact ", res)
	await _frames(4)
	await _shot("11_trap_dodged")
	player.invulnerable = false
	await _await_signal(trap.rearmed, 6.0)
	# Turret: hit.
	var button: Node2D = turret.button
	await _go(button.global_position.x + 120)
	await _wait(0.4)
	await _shot("12_turret_prompt")
	await _tap(&"interact")
	await _wait(0.45)
	await _shot("13_turret_warning")
	await _await_signal(turret.fired, 2.0)
	await _frames(3)
	await _shot("14_turret_bullet")
	res = await _await_signal(turret.shot_resolved, 2.0)
	print("TURRET resolved ", res)
	await _shot("15_turret_hit")
	await _wait(0.5)
	await _await_signal(turret.ready_again, 4.0)
	# Turret: dodge, the round flies through.
	await _go(button.global_position.x + 120)
	await _wait(0.3)
	player.invulnerable = true
	await _tap(&"interact")
	res = await _await_signal(turret.shot_resolved, 3.0)
	print("TURRET dodge resolved ", res)
	await _frames(3)
	await _shot("16_turret_dodged")
	player.invulnerable = false
	# Reset button.
	await _go(reset_button.position.x - 120)
	await _wait(0.4)
	await _shot("17_reset_prompt")
	await _tap(&"interact")
	await _frames(1)
	await _shot("18_reset_pressed")
	print("RESET count ", _reset_count)
	await _wait(0.2)
	get_tree().quit()
