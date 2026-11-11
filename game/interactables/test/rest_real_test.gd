extends Node

# Captures the chair and the bed in the real level with the real rig, waiting for the seated and
# sleeping loops: godot --path <project> res://game/interactables/test/rest_real_test.tscn
#   -- --shots <dir>

const MAIN := preload("res://game/main.tscn")

var game: Node
var player: CharacterBody2D
var _dir := "res://captures/interactables_rest"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i != -1 and i + 1 < args.size():
		_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(_dir)
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			InputMap.action_erase_events(action)
	game = MAIN.instantiate()
	add_child(game)
	player = game.get_node("Player")
	_run.call_deferred()


# The furniture node (furniture.gd) for a prop, wherever the level puts it.
func _furniture(prop: String) -> Node2D:
	for n in get_tree().get_nodes_in_group(&"interactable"):
		if n.get(&"prop") == prop and n.has_method(&"furniture_params"):
			return n
	return null


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)


func _go(x: float) -> void:
	player.global_position = Vector2(x, 0)
	player.velocity = Vector2.ZERO
	player.reset_physics_interpolation()
	var cam = game.get_node("Camera")
	if cam.has_method(&"snap"):
		cam.snap()
	await _frames(2)


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _dir.path_join("%s.png" % shot_name)
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path, " err=", err, " x=", player.global_position.x, " rig=", player.adventurer.current_action(), " facing=", player.adventurer.facing)


func _run() -> void:
	await _frames(10)
	var chair := _furniture("chair")
	var bed := _furniture("bed")
	print("CHAIR at ", chair.global_position if chair else null, " BED at ", bed.global_position if bed else null)
	await _go(chair.global_position.x - 150)
	await _wait(0.5)
	await _shot("rest_01_chair_prompt")
	await _tap(&"interact")
	if OS.get_cmdline_user_args().has("--trace"):
		var rig = player.adventurer
		rig.action_finished.connect(func(id): print("TRACE finished ", id))
		for k in 40:
			await _frames(6)
			print("TRACE %.1f cur=%s t=%.2f ctl=%s" % [k * 0.1, rig.current_action(), rig.action_elapsed(), player.is_controlled()])
		get_tree().quit()
		return
	await _wait(1.0)
	await _shot("rest_02_sitting_down")
	await _wait(1.6)
	await _shot("rest_03_seated")
	await _wait(1.0)
	await _shot("rest_04_seated_loop")
	await _tap(&"interact")
	await _wait(1.0)
	await _shot("rest_05_standing_up")
	await _wait(1.0)
	await _shot("rest_06_stood_up")
	await _go(bed.global_position.x + 260)
	await _wait(0.5)
	await _shot("rest_07_bed_prompt")
	await _tap(&"interact")
	await _wait(1.9)
	await _shot("rest_08_lying_down")
	await _wait(1.6)
	await _shot("rest_09_sleeping")
	var front := bed.get_node_or_null("Front") as Sprite2D
	var back := bed.get_node_or_null("Sprite") as Sprite2D
	print("BED layers: back=", back.texture.resource_path if back else "none", " front=", front.texture.resource_path if front else "none",
		" front_z=", (str(front.z_index) + (" rel" if front.z_as_relative else " abs")) if front else "-", " player_z=", player.z_index,
		" rig_params=", player.adventurer.action_params.get(&"furniture"))
	await _wait(1.5)
	await _shot("rest_10_sleeping_loop")
	await _tap(&"interact")
	await _wait(2.6)
	await _shot("rest_11_got_up")
	get_tree().quit()
