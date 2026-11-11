extends Node

# Capture driver of the motocross stage (the main scene's CaptureDriver does not exist here):
#   godot --path <project> res://game/moto/moto_level.tscn -- --capture <dir> --script moto_ramp
# Replays a relative step list (each step's time is a delay after the previous one; "wait" holds
# until a condition or its timeout), drives the actions with Input.action_press, saves PNGs and
# logs the bike state per step. menu_moto continues the main scene's script of the same name
# (title, Motocross, Enter) once the stage is loaded.

const T := preload("res://game/moto/moto_tuning.gd")

const SCRIPTS := {
	"moto_mount": [
		[0.0, "wait", "art_ready", 10.0], [0.4, "shot", "start"],
		[0.0, "press", "move_right"], [0.0, "wait", "near_bike", 6.0], [0.0, "release", "move_right"],
		[0.3, "shot", "near_bike"], [0.0, "tap", "interact"],
		[0.0, "wait", "mode:mounting", 4.0], [0.15, "shot", "mount_1"], [0.25, "shot", "mount_2"], [0.25, "shot", "mount_3"],
		[0.0, "wait", "mode:riding", 3.0], [0.3, "shot", "riding"],
		[0.0, "press", "moto_throttle"], [1.2, "release", "moto_throttle"], [0.0, "shot", "moving"],
		[0.0, "press", "moto_brake"], [0.0, "wait", "speed<20", 5.0], [0.0, "release", "moto_brake"],
		[0.0, "wait", "can_dismount", 3.0], [0.3, "shot", "stopped"], [0.0, "tap", "interact"],
		[0.0, "wait", "mode:dismounting", 2.0], [0.2, "shot", "dismount_1"], [0.3, "shot", "dismount_2"],
		[0.0, "wait", "mode:parked", 3.0], [0.4, "shot", "on_foot"],
		[0.0, "wait", "near_bike", 2.0], [0.2, "tap", "interact"], [0.0, "wait", "mode:riding", 5.0], [0.3, "shot", "remounted"],
		[0.2, "quit"],
	],
	"moto_ramp": [
		[0.0, "wait", "art_ready", 10.0], [0.0, "restart"], [0.4, "shot", "start"],
		[0.0, "press", "moto_throttle"], [0.0, "trace", 6],
		[0.0, "wait", "x>=3800", 8.0], [0.0, "shot", "kicker_foot"],
		[0.0, "wait", "airborne", 3.0], [0.0, "shot", "takeoff"], [0.25, "shot", "air_1"], [0.25, "shot", "air_2"],
		[0.0, "wait", "landed", 3.0], [0.0, "shot", "landing"], [0.15, "shot", "after_landing"],
		[0.0, "wait", "finished", 8.0], [0.3, "shot", "finish"], [0.0, "release", "moto_throttle"], [0.6, "shot", "finish_banner"],
		[0.3, "quit"],
	],
	"moto_flip": [
		[0.0, "wait", "art_ready", 10.0], [0.0, "restart"], [0.3, "press", "moto_throttle"],
		[0.0, "wait", "airborne", 8.0], [0.0, "press", "moto_lean_back"], [0.0, "trace", 3],
		[0.0, "burst", "flip", 12, 0.12],
		[0.0, "wait", "rotated>=220", 2.0], [0.0, "release", "moto_lean_back"], [0.0, "press", "moto_lean_forward"],
		[0.0, "wait", "spin>=-1", 1.0], [0.0, "release", "moto_lean_forward"],
		[0.0, "wait", "landed_or_crashed", 3.0], [0.05, "shot", "flip_landing"], [0.45, "shot", "flip_trick"],
		[0.6, "shot", "flip_after"], [0.2, "quit"],
	],
	"moto_crash": [
		[0.0, "wait", "art_ready", 10.0], [0.0, "restart"], [0.3, "press", "moto_throttle"],
		[0.0, "wait", "airborne", 8.0], [0.0, "press", "moto_lean_forward"], [0.0, "trace", 3],
		[0.0, "wait", "crashed", 3.0], [0.0, "shot", "crash_0"], [0.15, "shot", "crash_1"], [0.25, "shot", "crash_2"],
		[0.4, "shot", "crash_3"], [0.0, "release", "moto_lean_forward"], [0.0, "release", "moto_throttle"],
		[0.0, "wait", "mode:riding", 3.0], [0.3, "shot", "respawned"],
		[0.2, "quit"],
	],
	"moto_brake": [
		[0.0, "wait", "art_ready", 10.0], [0.0, "restart"], [0.3, "press", "moto_throttle"],
		[1.0, "release", "moto_throttle"], [0.0, "press", "moto_brake"], [0.0, "trace", 6], [0.0, "shot", "braking"],
		[0.0, "wait", "speed<10", 5.0], [0.3, "shot", "stopped"], [0.0, "wait", "speed<10", 0.1], [0.0, "label", "still_after_0.3s"],
		[0.0, "wait", "reversing", 2.0], [0.8, "shot", "reversing"],
		[0.0, "release", "moto_brake"], [0.3, "quit"],
	],
	"moto_wheelie": [
		[0.0, "wait", "art_ready", 10.0], [0.0, "restart"], [0.3, "press", "moto_throttle", 0.5], [0.6, "press", "moto_lean_back"],
		[0.0, "trace", 6], [0.0, "wait", "front_up", 1.0], [0.25, "shot", "wheelie_up"], [0.15, "release", "moto_lean_back"],
		[0.0, "shot", "wheelie_hold"], [0.0, "wait", "front_down", 2.0], [0.2, "shot", "wheelie_down"],
		[0.0, "release", "moto_throttle"], [0.0, "restart"], [0.3, "press", "moto_throttle", 0.6], [0.0, "press", "moto_lean_back"], [0.0, "wait", "crashed", 4.0],
		[0.0, "shot", "loop_out_0"], [0.25, "shot", "loop_out_1"], [0.0, "release", "moto_lean_back"], [0.0, "release", "moto_throttle"],
		[0.0, "wait", "mode:riding", 3.0], [0.3, "shot", "respawned"], [0.2, "quit"],
	],
	"moto_dismount_slope": [
		[0.0, "wait", "art_ready", 10.0],
		[0.0, "spawn", 2000.0], [0.05, "tap", "interact"],
		[0.0, "wait", "mode:dismounting", 1.0], [0.0, "burst", "flat", 5, 0.17], [0.0, "wait", "mode:parked", 2.0],
		[0.3, "shot", "flat_end_end"], [0.0, "tap", "interact"], [0.0, "wait", "mode:mounting", 2.0],
		[0.0, "burst", "flat_mount", 4, 0.22], [0.0, "wait", "mode:riding", 2.0], [0.3, "shot", "flat_remounted"],
		[0.0, "spawn", 5300.0], [0.05, "tap", "interact"],
		[0.0, "wait", "mode:dismounting", 1.0], [0.0, "burst", "uphill", 5, 0.17], [0.0, "wait", "mode:parked", 2.0],
		[0.3, "shot", "uphill_end"], [0.0, "tap", "interact"], [0.0, "wait", "mode:mounting", 2.0],
		[0.0, "burst", "uphill_mount", 4, 0.22], [0.0, "wait", "mode:riding", 2.0], [0.3, "shot", "uphill_remounted"],
		[0.0, "spawn", 8400.0], [0.05, "tap", "interact"],
		[0.0, "wait", "mode:dismounting", 1.0], [0.0, "burst", "downhill", 5, 0.17], [0.0, "wait", "mode:parked", 2.0],
		[0.3, "shot", "downhill_end"], [0.0, "tap", "interact"], [0.0, "wait", "mode:mounting", 2.0],
		[0.0, "burst", "downhill_mount", 4, 0.22], [0.0, "wait", "mode:riding", 2.0], [0.3, "shot", "downhill_remounted"],
		[0.0, "spawn", 13300.0], [0.05, "tap", "interact"],
		[0.0, "wait", "mode:dismounting", 1.0], [0.0, "burst", "flat_end", 5, 0.17], [0.0, "wait", "mode:parked", 2.0],
		[0.3, "shot", "flat_end_end"], [0.0, "tap", "interact"], [0.0, "wait", "mode:mounting", 2.0],
		[0.0, "burst", "flat_end_mount", 4, 0.22], [0.0, "wait", "mode:riding", 2.0], [0.3, "shot", "flat_end_remounted"],
		[0.0, "spawn", 6250.0], [0.05, "wait", "no_dismount", 0.5], [0.0, "shot", "steep_no_prompt"], [0.0, "tap", "interact"], [0.3, "wait", "mode:riding", 0.5],
		[0.2, "quit"],
	],
	"moto_scale": [
		[0.0, "wait", "art_ready", 10.0], [0.0, "player_x", T.PARK_X + 330.0], [0.6, "shot", "scale"],
		[0.2, "quit"],
	],
	"menu_moto": [
		[0.0, "wait", "art_ready", 10.0], [0.4, "shot", "moto_loaded"],
		[0.0, "press", "move_right"], [0.0, "wait", "near_bike", 6.0], [0.0, "release", "move_right"],
		[0.2, "tap", "interact"], [0.0, "wait", "mode:riding", 5.0],
		[0.3, "key", "Escape"], [0.0, "wait", "paused", 2.0],
		[0.3, "legend", false], [0.3, "shot", "pause_pad"], [0.2, "legend", true], [0.3, "shot", "pause_keys"],
		[0.2, "key", "Tab"], [0.2, "key", "Right"], [0.2, "key", "Right"], [0.3, "shot", "menu_selected"],
		[0.2, "after_scene", "back_to_title", 2.5], [0.0, "key", "Enter"],
	],
}

var level: Node
var _dir := ""
var _name := ""
var _steps: Array = []
var _time := 0.0
var _since := 0.0
var _releases: Array = []
var _bursts: Array = []
var _busy := 0
var _quit := false
var _trace := 0
var _frame := 0
var _landed := false
var _crashed := false
var _impact := 0.0


func configure(args: PackedStringArray) -> bool:
	var i := args.find("--capture")
	var s := args.find("--script")
	if i == -1 or s == -1 or s + 1 >= args.size():
		return false
	_name = args[s + 1]
	if not SCRIPTS.has(_name):
		return false
	_dir = args[i + 1] if i + 1 < args.size() else "res://captures"
	_steps = (SCRIPTS[_name] as Array).duplicate(true)
	# Only the script drives the actions (a pad or keyboard on the machine would leak in); Esc stays
	# on pause for the "key" op. In menu_moto the main scene's driver already did this.
	for action in InputMap.get_actions():
		if not String(action).begins_with("ui_"):
			InputMap.action_erase_events(action)
	if InputMap.has_action(&"pause"):
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		if not InputMap.action_has_event(&"pause", esc):
			InputMap.action_add_event(&"pause", esc)
	DirAccess.make_dir_recursive_absolute(_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	process_physics_priority = -100
	return true


func _ready() -> void:
	level.bike.landed.connect(func(impact: float) -> void:
		_landed = true
		_impact = impact
		_log(["landed"]))
	level.bike.crashed.connect(func() -> void:
		_crashed = true
		_log(["crashed"]))
	level.bike.took_off.connect(func() -> void: _log(["took_off"]))


func _physics_process(delta: float) -> void:
	_time += delta
	_frame += 1
	for r in _releases.duplicate():
		if _time >= r[0]:
			Input.action_release(r[1])
			_releases.erase(r)
	for bs in _bursts.duplicate():
		if _time >= bs[0]:
			_bursts.erase(bs)
			_shot(bs[1])
	if _trace > 0 and _frame % _trace == 0:
		_log(["trace"])
	_since += delta
	while not _steps.is_empty():
		var step: Array = _steps[0]
		if _since < step[0]:
			return
		if step[1] == "wait":
			var met := _condition(step[2])
			if not met and _since - step[0] < step[3]:
				return
			if not met:
				print("WAIT TIMEOUT ", step[2])
		_steps.pop_front()
		_since = 0.0
		_run(step)


func _condition(cond: String) -> bool:
	var bike = level.bike
	if cond.begins_with("mode:"):
		return bike.state_label() == cond.substr(5)
	if cond.begins_with("x>="):
		return bike.pos.x >= float(cond.substr(3))
	if cond.begins_with("rotated>="):
		return -rad_to_deg(bike.air_rotation) >= float(cond.substr(9)) or bike.wheels_down() > 0
	if cond.begins_with("spin>="):
		return bike.spin >= float(cond.substr(6)) or bike.wheels_down() > 0
	if cond.begins_with("speed<"):
		return bike.vel.length() < float(cond.substr(6))
	match cond:
		"art_ready":
			return level.art_ready
		"near_bike":
			return level.player.global_position.x >= bike.get_interact_point().x - 120.0
		"front_up":
			return bike.wheels_down() == 1 and bike.depth[0] > 0.0 and bike.angle < -0.15
		"front_down":
			return bike.wheels_down() == 2
		"no_dismount":
			return bike.is_ridden() and bike.vel.length() < T.DISMOUNT_MAX_SPEED and not bike.can_dismount()
		"reversing":
			return bike.vel.x < -60.0
		"can_dismount":
			return bike.can_dismount()
		"airborne":
			return bike.is_ridden() and bike.wheels_down() == 0 and bike.air_time > 0.05
		"landed":
			return _landed
		"crashed":
			return _crashed
		"landed_or_crashed":
			return _landed or _crashed
		"finished":
			return bike.finished
		"paused":
			return get_tree().paused
		"unpaused":
			return not get_tree().paused
	push_error("Unknown moto wait condition: %s" % cond)
	return true


func _run(step: Array) -> void:
	match step[1]:
		"press":
			Input.action_press(step[2], float(step[3]) if step.size() > 3 else 1.0)
		"release":
			Input.action_release(step[2])
		"tap":
			Input.action_press(step[2])
			_releases.append([_time + 0.1, step[2]])
		"shot":
			_shot(step[2])
		"spawn":
			level.restart(float(step[2]))
			_landed = false
			_crashed = false
		"restart":
			level.restart()
			_landed = false
			_crashed = false
		"trace":
			_trace = int(step[2])
		"player_x":
			var x: float = step[2]
			level.player.global_position = Vector2(x, level.track.height_at(x))
			level.player.velocity = Vector2.ZERO
			level.player.set_facing(-1)
			level.player.reset_physics_interpolation()
		"legend":
			var menu = level.pause.pause_menu if level.pause else null
			if menu and menu.has_method(&"set_keyboard"):
				menu.set_keyboard(bool(step[2]))
		"key":
			for pressed in [true, false]:
				var ev := InputEventKey.new()
				ev.keycode = OS.find_keycode_from_string(step[2])
				ev.physical_keycode = ev.keycode
				ev.pressed = pressed
				Input.parse_input_event(ev)
		"quit":
			_quit = true
		"burst":
			# ["burst", name, count, interval]: shots on a timer while the next steps run.
			for k in int(step[3]):
				_bursts.append([_time + k * float(step[4]), "%s_%d" % [step[2], k]])
		"after_scene":
			# This node leaves with the stage: a tree timer (runs while the title pauses) takes the
			# last shot of the next scene and quits, through a static method of this script.
			var path := _dir.path_join("%s_%s.png" % [_name, step[2]])
			var finish := Callable(get_script(), "_finish_after_scene").bind(get_tree(), path)
			get_tree().create_timer(float(step[3]), true, false, true).timeout.connect(finish)
	_log(step.slice(1))
	_try_quit()


func _log(what: Array) -> void:
	var bike = level.bike
	var p: Node2D = level.player
	print("[%6.2f] %-26s x=%7.1f y=%7.1f vx=%7.1f vy=%7.1f ang=%6.1f wheels=%d air=%.2f impact=%.0f crashed=%s state=%s rider=(%.0f,%.0f) rig=%s t=%.2f fps=%d" % [
		_time, " ".join(what.map(func(v): return str(v))),
		bike.pos.x, bike.pos.y, bike.vel.x, bike.vel.y, rad_to_deg(bike.angle), bike.wheels_down(),
		bike.air_time, _impact, bike.is_crashed(), bike.state_label(), p.global_position.x, p.global_position.y,
		_rig_action(), level.run_time, Engine.get_frames_per_second()])


func _rig_action() -> String:
	var rig = level.player.get(&"rig")
	if rig and rig.has_method(&"current_action"):
		var id: String = String(rig.current_action())
		return ("%s@%.2f" % [id, rig.action_elapsed()]) if not id.is_empty() else "-"
	return "?"


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	var path := _dir.path_join("%s_%s.png" % [_name, shot_name])
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("CAPTURE ", path, " size=", image.get_size(), " err=", err)
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _quit and _busy == 0:
		get_tree().quit()


static func _finish_after_scene(tree: SceneTree, path: String) -> void:
	await RenderingServer.frame_post_draw
	var image := tree.root.get_texture().get_image()
	print("CAPTURE ", path, " size=", image.get_size(), " err=", image.save_png(path))
	tree.quit()
