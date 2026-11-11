extends Node

# Real-level check for walking over the rubble: loads res://game/main.tscn, breaks the Boxing wall,
# then walks, runs and sprints the player across the debris both ways, logging velocity.x every
# physics frame and every debris push. Quits when done.
# godot --path <project> res://game/breakable/breakable_walk_test.tscn -- --walklog <dir>

const MAIN := preload("res://game/main.tscn")

# [label, action, strength, sprint, target x offset from the wall, timeout s]
const LEGS := [
	["walk_right", &"move_right", 0.4, false, 900.0, 7.0],
	["run_left", &"move_left", 1.0, false, -600.0, 4.0],
	["sprint_right", &"move_right", 1.0, true, 1100.0, 4.0],
	["walk_left", &"move_left", 0.4, false, -600.0, 8.0],
	["sprint_left", &"move_left", 1.0, true, -700.0, 4.0],
]

var _dir := ""
var _game: Node
var _player: CharacterBody2D
var _wall: BreakableWall
var _tick := 0
var _leg := -1
var _leg_time := 0.0
var _leg_max := 0.0
var _leg_shot := 0
var _pushes := 0
var _busy := 0
var _done := false


func _ready() -> void:
	process_physics_priority = -200
	var args := OS.get_cmdline_user_args()
	var i := args.find("--walklog")
	_dir = args[i + 1] if i != -1 and i + 1 < args.size() else "res://captures/breakable_walk"
	DirAccess.make_dir_recursive_absolute(_dir)
	_game = MAIN.instantiate()
	add_child(_game)
	_player = _game.get_node("Player")
	for n in _game.find_children("*", "StaticBody2D", true, false):
		if n is BreakableWall:
			_wall = n
			break
	_wall.debris_hit.connect(_on_debris_hit)
	print("SETUP wall_x=%.0f player_mask=%d player_layer=%d speeds walk=%.0f run=%.0f sprint=%.0f" % [
		_wall.global_position.x, _player.collision_mask, _player.collision_layer,
		_player.walk_speed, _player.run_speed, _player.sprint_speed])


func _physics_process(delta: float) -> void:
	_tick += 1
	var t := _tick / float(Engine.physics_ticks_per_second)
	var wx := _wall.global_position.x
	if _tick == 20:
		_teleport(wx - 500.0)
	if _tick == 40:
		_wall.break_at(_wall.global_position + Vector2(-78, -216), Vector2(1900, -160), 1.0)
	if _tick == 200:
		_shot("rubble")
		_next_leg()
	if _leg < 0 or _done:
		return
	var leg: Array = LEGS[_leg]
	_leg_time += delta
	var vx := _player.velocity.x
	_leg_max = maxf(_leg_max, absf(vx))
	var over := absf(_player.global_position.x - wx) < 700.0
	print("[%5.2f] %-12s x=%8.1f vx=%7.1f vy=%7.1f floor=%s step=%s state=%s%s" % [t, leg[0],
		_player.global_position.x - wx, vx, _player.velocity.y, _player.is_on_floor(), _player.stepping,
		_player.state_name(), "  <-- OVER LIMIT" if absf(vx) > _player.sprint_speed + 1.0 else ""])
	if over and _leg_shot < 2 and _leg_time > 0.35 * (_leg_shot + 1):
		_leg_shot += 1
		_shot("%s_%d" % [leg[0], _leg_shot])
	var target: float = wx + leg[4]
	var arrived: bool = (_player.global_position.x >= target) if leg[4] > 0.0 else (_player.global_position.x <= target)
	if arrived or _leg_time > leg[5]:
		Input.action_release(leg[1])
		Input.action_release(&"sprint")
		print("LEG %s max_abs_vx=%.1f arrived=%s pushes_so_far=%d" % [leg[0], _leg_max, arrived, _pushes])
		_next_leg()


func _next_leg() -> void:
	_leg += 1
	_leg_time = 0.0
	_leg_max = 0.0
	_leg_shot = 0
	if _leg >= LEGS.size():
		_done = true
		_try_quit()
		return
	var leg: Array = LEGS[_leg]
	Input.action_press(leg[1], leg[2])
	if leg[3]:
		Input.action_press(&"sprint")


func _teleport(x: float) -> void:
	_player.global_position = Vector2(x, 0)
	_player.velocity = Vector2.ZERO
	_player.reset_physics_interpolation()


func _on_debris_hit(body: Node2D, push: Vector2) -> void:
	_pushes += 1
	print("DEBRIS PUSH body=%s push=%s player_vx_after=%.1f" % [body.name, push, _player.velocity.x])


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var path := _dir.path_join(shot_name + ".png")
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " err=", err)
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _done and _busy == 0:
		get_tree().quit()
