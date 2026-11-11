extends Node

# Capture mode: godot --path <project> -- --capture <dir> [--script <name>] [--frames N]
# With --script it replays a recorded input sequence (input_scripts.gd) and saves PNGs at marked
# times; without it, it saves one PNG after N frames. Either way it quits when done.

const InputScripts := preload("res://game/input_scripts.gd")
# Pad id the "stick" op drives (no real controller uses it).
const SCRIPT_PAD := 7
# Loaded on use, so the driver still parses if the arrow script is mid-change.
const ARROW_SCRIPT := "res://game/targets/arrow.gd"

var player: CharacterBody2D
var cups_struck := 0
var _cups_hooked := false
var camera: Camera2D
var spawn := Vector2.INF
var _dir := ""
var _steps: Array = []
var _script_name := ""
var _frames_left := -1
var _time := 0.0
var _releases: Array = []
var _busy := 0
var _quit_requested := false
# Relative scripts: each step's time is a delay after the previous step; "wait" steps hold the
# timeline until a player/rig condition holds (or their timeout runs out, which is logged).
var _relative := false
# Scene loads in this process: the ending's restart reloads the scene and the driver comes back.
static var loads := 0
var _since_step := 0.0


func configure(args: PackedStringArray) -> bool:
	var i := args.find("--capture")
	if i == -1:
		return false
	_dir = args[i + 1] if i + 1 < args.size() else "res://captures"
	loads += 1
	var s := args.find("--script")
	if loads > 1:
		# After a reload (the ending's restart): one shot of the fresh scene, then quit.
		_script_name = "restart"
		_steps = [[1.5, "shot", "after_restart"], [0.2, "quit"]]
		_relative = true
		# The reloaded scene may open on a paused tree (title or pause menu), like the scripted runs.
		process_mode = Node.PROCESS_MODE_ALWAYS
		DirAccess.make_dir_recursive_absolute(_dir)
		process_priority = -100
		process_physics_priority = -100
		return true
	if s != -1 and s + 1 < args.size():
		_script_name = args[s + 1]
		var data: Dictionary = InputScripts.SCRIPTS.get(_script_name, {})
		if data.is_empty():
			push_error("Unknown input script: %s" % _script_name)
			return false
		_steps = data.steps.duplicate()
		spawn = data.get("spawn", Vector2.INF)
		_relative = data.get("relative", false)
		# Only the recorded sequence drives the actions: a pad or keyboard in use on the machine
		# (the window does not need focus to read the pad) would otherwise leak into the run.
		for action in InputMap.get_actions():
			if not String(action).begins_with("ui_"):
				var axes: Array = InputMap.action_get_events(action).filter(func(e): return e is InputEventJoypadMotion)
				InputMap.action_erase_events(action)
				# The stick axes come back bound to a pad id no real device uses, for the "stick" op.
				for e in axes:
					var copy := (e as InputEventJoypadMotion).duplicate() as InputEventJoypadMotion
					copy.device = SCRIPT_PAD
					InputMap.action_add_event(action, copy)
		# Esc stays on pause so the "key" op can drive it; the driver keeps running while paused.
		if InputMap.has_action(&"pause"):
			var esc := InputEventKey.new()
			esc.physical_keycode = KEY_ESCAPE
			InputMap.action_add_event(&"pause", esc)
		process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		var f := args.find("--frames")
		_frames_left = int(args[f + 1]) if f != -1 and f + 1 < args.size() else 10
	DirAccess.make_dir_recursive_absolute(_dir)
	process_priority = -100
	process_physics_priority = -100
	return true


func _physics_process(delta: float) -> void:
	if _script_name.is_empty():
		return
	_time += delta
	for r in _releases.duplicate():
		if _time >= r[0]:
			_send(r[1], false)
			_releases.erase(r)
	if _relative:
		_advance_relative(delta)
		return
	while not _steps.is_empty() and _time >= _steps[0][0]:
		_run(_steps.pop_front())


func _advance_relative(delta: float) -> void:
	_since_step += delta
	while not _steps.is_empty():
		var step: Array = _steps[0]
		if _since_step < step[0]:
			return
		if step[1] == "wait":
			var timeout: float = step[3] if step.size() > 3 else 5.0
			var met := _condition(step[2])
			if not met and _since_step - step[0] < timeout:
				return
			if not met:
				print("WAIT TIMEOUT ", step[2])
		_steps.pop_front()
		_since_step = 0.0
		_run(step)


func _rig_busy() -> bool:
	var rig = player.rig
	return rig.has_method(&"is_action_playing") and rig.is_action_playing()


func _condition(cond: String) -> bool:
	if cond.begins_with("cups_struck>="):
		if not _cups_hooked:
			_cups_hooked = true
			var cups = get_tree().current_scene.get_node_or_null(^"Level").slot_scenes.get("CupTable")
			if cups and cups.has_signal(&"cup_struck"):
				cups.cup_struck.connect(func(_c, _p) -> void: cups_struck += 1)
		return cups_struck >= int(cond.substr(13))
	if cond == "flag_captured":
		var lvl = get_tree().current_scene.get_node_or_null(^"Level")
		return lvl != null and lvl.reward_flags.any(func(f): return f.is_captured)
	if cond.begins_with("state:"):
		return player.state_name() == cond.substr(6)
	if cond == "paused":
		return get_tree().paused
	if cond == "unpaused":
		return not get_tree().paused
	if cond == "holstered":
		return player.combat.holstered
	if cond.begins_with("rig_action:"):
		# Without current_action (stub) there is nothing to wait for.
		var rig = player.rig
		return not rig.has_method(&"current_action") or rig.current_action() == StringName(cond.substr(11))
	if cond.begins_with("ending>="):
		var wall = get_tree().current_scene.get_node_or_null(^"Level").slot_scenes.get("EndingWall")
		return wall != null and wall.progress >= float(cond.substr(8))
	if cond == "ending_shown":
		var wall2 = get_tree().current_scene.get_node_or_null(^"Level").slot_scenes.get("EndingWall")
		return wall2 != null and wall2.phase >= 3
	if cond.begins_with("oxygen<"):
		return player.swim.oxygen < float(cond.substr(7))
	if cond.begins_with("slash_hits>="):
		return player.combat.kunai.hit_count >= int(cond.substr(12))
	if cond.begins_with("gun_shots>="):
		return player.combat.guns.shots >= int(cond.substr(11))
	if cond.begins_with("bow_shots>="):
		return player.combat.bow.shots >= int(cond.substr(11))
	if cond.begins_with("punch_hits>="):
		return player.combat.fists.hit_count >= int(cond.substr(12))
	if cond.begins_with("kick_hits>="):
		return player.combat.kick.hit_count >= int(cond.substr(11))
	if cond.begins_with("arrow_hits>="):
		return _arrow_hits() >= int(cond.substr(12))
	if cond.begins_with("kick_bounces>="):
		return int(_combat_field(&"kick", &"wall_bounces", -1)) >= int(cond.substr(14))
	if cond.begins_with("punch_swings>="):
		return int(_combat_field(&"fists", &"swings", -1)) >= int(cond.substr(14))
	if cond.begins_with("x>="):
		return player.global_position.x >= float(cond.substr(3))
	if cond.begins_with("x<="):
		return player.global_position.x <= float(cond.substr(3))
	match cond:
		"hanging":
			return player.hanging and not player.climbing and not player.descending and not player.leaping and not _rig_busy()
		"floor":
			return player.is_on_floor() and not player.hanging and player.current_action.is_empty() and not _rig_busy()
		"standing":
			return player.is_on_floor() and not player.crouching
		"wall_slide":
			return player.wall_sliding
		"can_move":
			return not player.hurting
		"free":
			return not player.is_controlled() and not _rig_busy()
		"crate_side":
			# A floating push crate within climbing reach (the same search the swim uses).
			return player.swim._crate_near() != null
		"swimming":
			return player.swim.active()
		"surface":
			return player.swim.mode_name() == &"swim"
		"diving":
			return player.swim.mode_name() == &"dive"
		"combo_window":
			return player.combat.fists.window_open
		"hang_any":
			return player.hanging
		"wall_or_hang":
			return player.wall_sliding or player.hanging
		"stepping":
			return player.stepping
		"airborne":
			return not player.is_on_floor() and not player.wall_sliding and not player.hanging
		"apex":
			return not player.is_on_floor() and not player.wall_sliding and not player.hanging and player.velocity.y >= 0.0
		"pushing":
			return player.pushing
	push_error("Unknown wait condition: %s" % cond)
	return true


func _process(_delta: float) -> void:
	if _frames_left < 0:
		return
	_frames_left -= 1
	if _frames_left == 0:
		_shot("frame")
		_quit_requested = true


func _run(step: Array) -> void:
	match step[1]:
		"press":
			_send(step[2], true, step[3] if step.size() > 3 else 1.0)
		"release":
			_send(step[2], false)
		"tap":
			_send(step[2], true)
			_releases.append([_time + 0.1, step[2]])
		"teleport":
			player.global_position = Vector2(step[2], step[3])
			player.velocity = Vector2.ZERO
			player.reset_physics_interpolation()
			if camera and camera.has_method(&"snap"):
				camera.snap()
		"shot":
			_shot(step[2])
		"wait", "label":
			pass
		"key":
			# A raw key press and release (the ending overlay reads events, not actions).
			for pressed in [true, false]:
				var ev := InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(step[2])
				ev.physical_keycode = ev.keycode
				ev.pressed = pressed
				Input.parse_input_event(ev)
		"call":
			# ["call", method, args...]: Vector2 args are written as [x, y].
			var args: Array = step.slice(3).map(func(v): return Vector2(v[0], v[1]) if v is Array else (self if v is String and v == "self" else v))
			print("CALL ", step[2], " -> ", player.callv(step[2], args))
		"skip_to_if":
			# Drop the following steps up to the label when the condition already holds.
			if _condition(step[2]):
				while not _steps.is_empty() and not (_steps[0][1] == "label" and _steps[0][2] == step[3]):
					_steps.pop_front()
		"arrow":
			# ["arrow", dx, dy, vx, vy]: an arrow fired from the player's feet + (dx, dy), with the
			# player as shooter (ignored briefly after the spawn, then hittable).
			var arrow_script: Variant = load(ARROW_SCRIPT) if ResourceLoader.exists(ARROW_SCRIPT) else null
			var vel := Vector2(step[4], step[5])
			if player and arrow_script is Script:
				arrow_script.spawn(player.get_parent(), player.global_position + Vector2(step[2], step[3]), vel.normalized(), vel.length(), player)
			else:
				push_error("arrow op: no player or arrow script")
		"stick":
			# ["stick", x, y]: the left stick of a scripted pad (axes 0 and 1), through the input events
			# the actions read, so deadzones and raw strengths behave as with a controller.
			for axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
				var ev := InputEventJoypadMotion.new()
				ev.device = SCRIPT_PAD
				ev.axis = axis
				ev.axis_value = float(step[2] if axis == JOY_AXIS_LEFT_X else step[3])
				Input.parse_input_event(ev)
		"joy":
			# ["joy", device, connected]: fakes a pad (dis)connection for every listener of the signal.
			Input.joy_connection_changed.emit(int(step[2]), bool(step[3]))
		"quit":
			_quit_requested = true
	_log(step)
	_try_quit()


func _send(action: StringName, pressed: bool, strength := 1.0) -> void:
	if pressed:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _log(step: Array) -> void:
	if player:
		print("[%5.2f] %-28s x=%7.1f y=%7.1f vx=%6.1f vy=%7.1f state=%s action=%s inv=%s fps=%d face=%d/%d shots=%d aim=%s/%s bad=%d hol=%s rigw=%s paused=%s menu=%s loops=%s look=%s cam_y=%s arrows=%s" % [
			_time, " ".join(step.slice(1).map(func(v): return str(v))),
			player.global_position.x, player.global_position.y, player.velocity.x, player.velocity.y,
			player.state_name(), _action_label(), player.invulnerable, Engine.get_frames_per_second(), player.facing, player.rig.facing, player.combat.guns.shots, "Y" if (player.combat.bow.aiming or player.combat.guns.aiming) else "-", (player.rig.current_action() if player.rig.has_method(&"current_action") else &"?"), player.combat.aim_bad_frames, "Y" if player.combat.holstered else "-", (player.rig.get(&"weapon") if player.rig.get(&"weapon") != null else &"?"), get_tree().paused, _menu_state(), _loop_state(),
			("%d/%.2f" % [int(player.get(&"look_dir")), float(player.get(&"look_amount"))]) if player.get(&"look_amount") != null else ("%d" % int(player.get(&"look_dir")) if player.get(&"look_dir") != null else "?"),
			"%.0f" % camera.global_position.y if is_instance_valid(camera) else "",
			_arrow_hits()])


func _arrow_hits() -> int:
	var stuck: Variant = player.get(&"stuck") if player else null
	if not is_instance_valid(stuck) or stuck.get(&"hit_count") == null:
		return -1
	return int(stuck.hit_count)


# A counter on one of the combat handlers (player.combat.<handler>.<field>), or fallback.
func _combat_field(handler: StringName, field: StringName, fallback: Variant) -> Variant:
	var combat: Variant = player.get(&"combat") if player else null
	var h: Variant = combat.get(handler) if is_instance_valid(combat) else null
	if h == null:
		return fallback
	var v: Variant = h.get(field)
	return fallback if v == null else v


func _menu_state() -> String:
	var menus = get_tree().current_scene.get(&"pause")
	if menus == null or not menus.has_method(&"is_covered"):
		return "?"
	return "pause" if menus.is_paused_by_menu() else ("title" if menus.is_covered() else "-")


# Sfx loops running/held and the Haptics hold, for the pause checks.
func _loop_state() -> String:
	var sfx := get_node_or_null(^"/root/Sfx")
	var loops: Variant = sfx.get(&"_loops") if sfx else null
	var held := 0
	var total := 0
	if loops is Dictionary:
		for p: Node in loops.values():
			total += 1
			held += 1 if p.stream_paused else 0
	var hap := get_node_or_null(^"/root/Haptics")
	return "%d/%d%s" % [total, held, "H" if hap and hap.get(&"_paused") else ""]


func _action_label() -> String:
	var id := String(player.rig_action())
	if id.is_empty():
		return "-"
	if player.rig.has_method(&"action_elapsed"):
		return "%s@%.2f" % [id, player.rig.action_elapsed()]
	return id


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var prefix := (_script_name + "_") if not _script_name.is_empty() else ""
	var path := _dir.path_join("%s%s.png" % [prefix, shot_name])
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("CAPTURE ", path, " size=", image.get_size(), " err=", err)
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _quit_requested and _busy == 0:
		get_tree().quit()
