extends Node2D

const PixelArt := preload("res://game/pixel_art.gd")
const CaptureDriver := preload("res://game/capture_driver.gd")
const WeaponHud := preload("res://game/combat/weapon_hud.gd")
const PauseController := preload("res://game/pause_controller.gd")
const FogHooks := preload("res://game/fog_hooks.gd")
const SFX_BOARD_SCENE := "res://audio/sfx_board.tscn"

@onready var level: Node2D = $Level
@onready var player: CharacterBody2D = $Player
@onready var camera: Camera2D = $Camera
@onready var hud: CanvasLayer = $DebugHud

# Title and pause menus (the PauseMenu owns the pause input).
var pause: Node
var _board: Node

var _ground_camera_y := 0.0


func _ready() -> void:
	get_tree().physics_interpolation = true
	level.build(player.crouch_collision_height())
	RenderingServer.set_default_clear_color(level.sky_color)
	var spawn: Vector2 = level.SPAWN
	var capture := CaptureDriver.new()
	if capture.configure(OS.get_cmdline_user_args()):
		capture.name = "CaptureDriver"
		capture.player = player
		player.combat.bow.aim.allow_mouse = false
		player.combat.guns.aim.allow_mouse = false
		capture.camera = camera
		add_child(capture)
		if capture.spawn != Vector2.INF:
			spawn = capture.spawn
	else:
		capture.free()
	player.global_position = spawn
	player.reset_physics_interpolation()
	camera.setup(player, level.bounds)
	_ground_camera_y = -camera.view_size().y * (camera.floor_screen_ratio - 0.5)
	hud.player = player
	_wire_slot_pieces()
	var fog := get_node_or_null(^"/root/Fog")
	if fog:
		# --fog-off (capture comparisons) keeps it disabled.
		fog.enabled = not "--fog-off" in OS.get_cmdline_user_args()
	var hooks := FogHooks.new()
	hooks.name = "FogHooks"
	add_child(hooks)
	var turret = level.slot_scenes.get("Turret")
	if turret and turret.has_signal(&"fired"):
		turret.fired.connect(func(bullet: Node) -> void:
			hooks.track_bullet(bullet)
			if bullet is Node2D:
				var dir: Vector2 = bullet.get(&"direction") if bullet.get(&"direction") is Vector2 else Vector2.LEFT
				FogHooks.push((bullet as Node2D).global_position, dir * 600.0, 80.0, 0.6))
	var trap = level.slot_scenes.get("DamageTrap")
	if trap and trap.has_signal(&"impact"):
		trap.impact.connect(func(_p: Node, _hit: bool) -> void: FogHooks.burst(trap.global_position, 200.0, 1.0))
	player.combat.cycle_blockers.append(hud)
	pause = PauseController.new()
	pause.name = "Menus"
	add_child(pause)
	# Captures skip the title screen unless --with-title asks for it.
	var capturing := has_node(^"CaptureDriver")
	pause.setup(not capturing or "--with-title" in OS.get_cmdline_user_args())
	var weapon_hud := WeaponHud.new()
	add_child(weapon_hud)
	var refresh_hud := func() -> void:
		weapon_hud.visible = not player.combat.is_holstered_for(&"control") and not pause.is_covered()
		weapon_hud.set_dimmed(player.combat.is_holstered_for(&"climb"))
	player.combat.weapon_changed.connect(weapon_hud.show_weapon)
	player.combat.holstered_changed.connect(func(_on: bool) -> void: refresh_hud.call())
	pause.covered_changed.connect(func(_on: bool) -> void: refresh_hud.call())
	refresh_hud.call()
	weapon_hud.show_weapon(player.combat.weapon)
	# The sound board toggles itself on F2 and pauses-safe; it only has to exist once.
	if ResourceLoader.exists(SFX_BOARD_SCENE):
		_board = (load(SFX_BOARD_SCENE) as PackedScene).instantiate()
		add_child(_board)
		player.input_blocker = _board
		hud.input_blocker = _board


func _wire_slot_pieces() -> void:
	var ending = level.slot_scenes.get("EndingWall")
	if ending and "game_gravity" in ending:
		ending.game_gravity = player.gravity
	for key in ["PunchingBag", "Scarecrow"]:
		var target = level.slot_scenes.get(key)
		if target and target.has_signal(&"hit"):
			target.hit.connect(func(_point: Vector2, damage: float) -> void:
				var k := clampf(damage / 15.0, 0.4, 1.5)
				player.hitstop(0.04 * k)
				player.camera_shake(8.0 * k, 0.15))
	var wall = level.slot_scenes.get("BreakableWall")
	if wall:
		if "game_gravity" in wall:
			wall.game_gravity = player.gravity
		if wall.has_signal(&"impacted"):
			wall.impacted.connect(func(_point: Vector2, strength: float) -> void:
				player.hitstop(0.06 * strength)
				player.camera_shake(16.0 * strength, 0.25))


func _process(delta: float) -> void:
	_ground_camera_y = -camera.view_size().y * (camera.floor_screen_ratio - 0.5)
	level.update_parallax(camera.get_screen_center_position(), _ground_camera_y, camera.view_size())


# Leaving the scene (the ending's restart reloads it): nothing may linger in the autoloads.
func _exit_tree() -> void:
	Engine.time_scale = 1.0
	if player and player.has_method(&"release_feedback"):
		player.release_feedback()
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx and sfx.has_method(&"set_underwater"):
		sfx.set_underwater(false, 0.0)

