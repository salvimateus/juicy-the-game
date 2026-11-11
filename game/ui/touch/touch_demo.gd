extends Node

# Dev: `-- --touch-demo=<scenario> [--touch-shot=<abs .png>]` injects synthetic touches through
# Input.parse_input_event() so screenshots show each control state, prints the overlay state and
# quits after the shot. The title (when up) is passed by tapping, like a player would.
# Scenarios: foot, drag, sprint, aim, swim, moto, moto_foot, title, pause, back, joy.
# Positions are canvas units, converted to window pixels on injection.

const START_FRAMES := 30
# Where the swim capture script enters the river from the left bank.
const SWIM_SPAWN := Vector2(37460, 0)

var _controls: Node
var _shot_path := ""


func run(controls: Node, scenario: String) -> void:
	_controls = controls
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--touch-shot="):
			_shot_path = a.trim_prefix("--touch-shot=")
		elif a.begins_with("--touch-canvas="):
			# Renders the canvas a phone of that size gets (scale 1) into a smaller desktop window.
			var v := a.trim_prefix("--touch-canvas=").split("x")
			get_window().content_scale_size = Vector2i(int(v[0]), int(v[1]))
			get_window().content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	await _frames(START_FRAMES)
	if scenario != "title":
		await _pass_title()
		await _frames(30)
	var vp := get_viewport().get_visible_rect().size
	var r: float = _controls.get(&"_stick").get(&"radius")
	var home: Vector2 = _controls.get(&"_stick").get(&"home")
	match scenario:
		"drag":
			_touch(0, home, true)
			await _slide(0, home, home + Vector2(r * 0.7, -r * 0.15), 12)
			await _frames(30)
		"sprint":
			_touch(0, home, true)
			await _slide(0, home, home + Vector2(r * 1.0, 0), 12)
			await _frames(40)
		"aim":
			# Two taps on the weapon bar: unarmed -> fists -> revolver.
			for i in 2:
				var rect: Rect2 = _controls.get(&"_weapon_rect")
				await _tap(1, rect.get_center())
				await _frames(20)
			var aim: Vector2 = _controls.get(&"_aim").get(&"center")
			var reach: float = _controls.get(&"_aim").get(&"radius") * 1.6
			_touch(2, aim, true)
			await _slide(2, aim, aim + Vector2(0.8, -0.45).normalized() * reach * 0.8, 10)
			await _frames(50)
			print("TOUCH_DEMO aim weapon=%s aiming=%s" % [_player().combat.weapon, _player().combat.guns.aiming])
			if _shot_path.is_empty():
				_touch(2, aim, false)
				await _frames(60)
				print("TOUCH_DEMO aim released shots=%d aiming=%s" % [_player().combat.guns.shots, _player().combat.guns.aiming])
		"swim":
			var p := _player()
			p.global_position = SWIM_SPAWN
			p.velocity = Vector2.ZERO
			p.reset_physics_interpolation()
			await _frames(10)
			_touch(0, home, true)
			await _slide(0, home, home + Vector2(r * 0.8, 0), 8)
			for i in 900:
				if p.swim.active():
					break
				await get_tree().process_frame
			await _frames(40)
			_touch(0, home + Vector2(r * 0.8, 0), false)
			await _frames(20)
			print("TOUCH_DEMO swim active=%s" % p.swim.active())
		"moto":
			var level := get_tree().current_scene
			await _frames(60)
			level.bike.spawn_mounted(level.bike.pos.x + 200.0)
			await _frames(30)
			var gas: Vector2 = _controls.get(&"_throttle").get(&"center")
			_touch(1, gas, true)
			await _frames(70)
			_touch(0, home, true)
			await _slide(0, home, home + Vector2(-r * 0.6, 0), 6)
			await _frames(4)
			print("TOUCH_DEMO moto mode=%s throttle=%.2f lean=%.2f" % [level.bike.state_label(), level.bike.throttle, level.bike.lean])
		"moto_foot":
			await _frames(60)
		"title":
			# The title runs on wall-clock time: wait for its prompt, not a frame count.
			var title: Node = get_tree().current_scene.get_node(^"Menus").get(&"start_menu")
			for i in 3000:
				if bool(title.get(&"_accept")):
					break
				await get_tree().process_frame
			await _frames(30)
			# Back on the title: the first press only warns (toast), the second would quit.
			get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
			await _frames(20)
		"pause":
			await _tap(0, _controls.get(&"_pause").get(&"center"))
			await _frames(30)
			print("TOUCH_DEMO pause paused=%s" % get_tree().paused)
		"back":
			get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
			await _frames(20)
			print("TOUCH_DEMO back opened paused=%s" % get_tree().paused)
			get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
			await _frames(20)
			print("TOUCH_DEMO back closed paused=%s" % get_tree().paused)
			get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
			await _frames(20)
			var menu: Node = get_tree().current_scene.get_node(^"Menus").get(&"pause_menu")
			var cont: Sprite2D = menu.get(&"_options")[0][1]
			await _tap(0, cont.position + cont.region_rect.size * cont.scale * 0.5)
			await _frames(20)
			print("TOUCH_DEMO back tap-continue paused=%s" % get_tree().paused)
		"joy":
			print("TOUCH_DEMO joy before mode=%s showing=%s" % [_controls.input_mode, _controls.is_showing()])
			Input.joy_connection_changed.emit(0, true)
			for pressed in [true, false]:
				var jb := InputEventJoypadButton.new()
				jb.device = 0
				jb.button_index = JOY_BUTTON_A
				jb.pressed = pressed
				Input.parse_input_event(jb)
				await _frames(2)
			await _frames(30)
			print("TOUCH_DEMO joy after-pad mode=%s showing=%s" % [_controls.input_mode, _controls.is_showing()])
			await _tap(0, Vector2(vp.x * 0.6, vp.y * 0.5))
			await _frames(30)
			print("TOUCH_DEMO joy after-touch mode=%s showing=%s" % [_controls.input_mode, _controls.is_showing()])
			Input.parse_input_event(_joy_motion())
			await _frames(30)
			print("TOUCH_DEMO joy after-stick mode=%s showing=%s" % [_controls.input_mode, _controls.is_showing()])
	print("TOUCH_DEMO %s done mode=%s showing=%s paused=%s context=%s" % [scenario, _controls.input_mode, _controls.is_showing(), get_tree().paused, _controls.get(&"_context")])
	if not _shot_path.is_empty():
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(_shot_path.get_base_dir())
		print("TOUCH_DEMO shot %s size=%s err=%s" % [_shot_path, img.get_size(), img.save_png(_shot_path)])
	_release_all()
	get_tree().quit()


func _player() -> Node:
	return get_tree().get_first_node_in_group(&"player")


func _joy_motion() -> InputEventJoypadMotion:
	var jm := InputEventJoypadMotion.new()
	jm.device = 0
	jm.axis = JOY_AXIS_LEFT_X
	jm.axis_value = 0.8
	return jm


# Taps through the title (skip the intro, then start) and waits for the game to take input.
func _pass_title() -> void:
	var vp := get_viewport().get_visible_rect().size
	for i in 240:
		if get_tree().get_nodes_in_group(&"pause_blocker").is_empty() and not get_tree().paused:
			return
		if i % 20 == 0:
			await _tap(9, Vector2(vp.x * 0.5, vp.y * 0.4))
		await get_tree().process_frame
	await _frames(20)


func _release_all() -> void:
	for i in 10:
		_touch(i, Vector2.ZERO, false)


func _tap(index: int, p: Vector2) -> void:
	_touch(index, p, true)
	await _frames(3)
	_touch(index, p, false)


func _slide(index: int, from: Vector2, to: Vector2, steps: int) -> void:
	for i in steps:
		await get_tree().process_frame
		_drag(index, from.lerp(to, float(i + 1) / float(steps)))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _to_window(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(index: int, canvas_pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = _to_window(canvas_pos)
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, canvas_pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = _to_window(canvas_pos)
	Input.parse_input_event(ev)
