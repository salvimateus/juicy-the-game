extends CanvasLayer

# Autoload `TouchControls`: on-screen controls for phones, and the one tracker of the input mode
# (&"touch", &"pad" or &"keys") the prompts, the pause legend and the weapon bar follow.
#
# Layout by context: on foot a dynamic move stick (left; its rim sprints) and the A/B/X/Y diamond
# (right) with an aim stick for the firearms and the bow (drag to point, release to shoot); on the
# bike the stick leans and RT/LT throttle and brake. A pause button sits top right, the weapon bar
# moves top left and a tap on it cycles the weapon. Every finger stays bound to the control it
# started on. Buttons drive the same input actions as the pad, so everything reading actions works.
#
# Shows only on a touchscreen (or with `-- --touch-ui=1`), hides on keyboard or pad input and
# comes back on the next touch. Hidden while the tree is paused or a `pause_blocker` is up: the
# menus read their own taps. Dev: `--touch-demo=<scenario>` (touch_demo.gd), `--touch-safe=l,t,r,b`
# fakes notch insets in window pixels, `--touch-mouse` turns mouse clicks into touches.

signal input_mode_changed(mode: StringName)

const TouchButton := preload("res://game/ui/touch/touch_button.gd")
const Joystick := preload("res://game/ui/touch/touch_joystick.gd")
const Toast := preload("res://game/ui/touch/touch_toast.gd")

const LAYER := 100
# Pad id of the capture driver's scripted stick: never counts as a real pad.
const SCRIPT_PAD := 7
const PAD_AXIS_SWITCH := 0.5
const REFERENCE_SHORT_SIDE := 900.0
const SCALE_MIN := 0.7
const SCALE_MAX := 1.4
const FADE_TIME := 0.2
const MIN_HOLD := 0.07
const LEFT_ZONE := 0.45
const TOP_BAND := 0.22
const STICK_HOME := Vector2(230, 215)
const STICK_RADIUS := 110.0
const KNOB_RADIUS := 46.0
const DIAMOND := Vector2(230, 215)
const DIAMOND_GAP := 108.0
const AIM_OFFSET := Vector2(-262, 64)
const AIM_RANGE := 1.6
const THROTTLE_INSET := Vector2(175, 190)
const BRAKE_OFFSET := Vector2(-215, 38)
const DISMOUNT_OFFSET := Vector2(-48, -192)
const GADGET_RADIUS := 34.0
const GADGET_INSET := 62.0
const FIRE_WAIT := 0.5
const FIRE_HOLD := 0.35
const FIRE_GIVE_UP := 1.2
const AIMED_WEAPONS: Array[StringName] = [&"revolver", &"rifle", &"bow"]
const MOTO_ON_BIKE := 2

const GREEN := Color("#6ccf4a")
const RED := Color("#ef5a44")
const BLUE := Color("#4f8fea")
const YELLOW := Color("#f2c53a")
const ORANGE := Color("#ffb03a")

const BIND_STICK := &"stick"

var input_mode: StringName = &"keys"
var touch_enabled := false

var _canvas: Control
var _toast: CanvasLayer
var _stick: Joystick
var _jump: TouchButton
var _roll: TouchButton
var _attack: TouchButton
var _interact: TouchButton
var _aim: TouchButton
var _pause: TouchButton
var _throttle: TouchButton
var _brake: TouchButton
var _restart: TouchButton
var _buttons: Array[TouchButton] = []
var _weapon_rect := Rect2()
var _weapon_flash := 0.0
# finger index -> BIND_STICK | TouchButton | &"weapon"
var _bindings: Dictionary = {}
var _pressed: Dictionary = {}
var _hold_until: Dictionary = {}
var _clock := 0.0
var _context: StringName = &""
var _shown := false
var _alpha := 0.0
var _scale := 1.0
var _safe := Rect2()
var _forced_insets := Vector4.ZERO
var _was_sprint := false
var _aim_vec := Vector2.ZERO
var _fire_t := -1.0
var _fire_pressed_t := -1.0
var _fire_shots := 0
var _player: Node
var _bike: Node
var _manager: Node


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var forced := false
	var demo := ""
	for a in OS.get_cmdline_user_args():
		if a == "--touch-ui" or a == "--touch-ui=1":
			forced = true
		elif a.begins_with("--touch-demo"):
			forced = true
			demo = a.trim_prefix("--touch-demo").trim_prefix("=")
		elif a == "--touch-mouse":
			Input.emulate_touch_from_mouse = true
		elif a.begins_with("--touch-safe="):
			var v := a.trim_prefix("--touch-safe=").split(",")
			if v.size() == 4:
				_forced_insets = Vector4(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	touch_enabled = forced or DisplayServer.is_touchscreen_available()
	if touch_enabled and (forced or Input.get_connected_joypads().is_empty()):
		input_mode = &"touch"
	elif not Input.get_connected_joypads().is_empty():
		input_mode = &"pad"
	_canvas = Control.new()
	_canvas.name = "TouchCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	_canvas.visible = false
	add_child(_canvas)
	_toast = Toast.new()
	_toast.name = "Toast"
	add_child(_toast)
	_stick = Joystick.new()
	_jump = TouchButton.new(&"jump", "A", GREEN)
	_roll = TouchButton.new(&"roll", "B", RED)
	_attack = TouchButton.new(&"attack", "X", BLUE)
	_interact = TouchButton.new(&"interact", "Y", YELLOW)
	_interact.dim_when_unlit = true
	_aim = TouchButton.new(&"aim", "", ORANGE)
	_aim.glyph = &"aim"
	_pause = TouchButton.new(&"pause")
	_pause.glyph = &"pause"
	_throttle = TouchButton.new(&"throttle", "RT", GREEN)
	_brake = TouchButton.new(&"brake", "LT", RED)
	_restart = TouchButton.new(&"restart")
	_restart.glyph = &"restart"
	_buttons = [_pause, _restart, _interact, _aim, _attack, _roll, _jump, _brake, _throttle]
	get_tree().root.window_input.connect(_on_window_input)
	Input.joy_connection_changed.connect(_on_joy_connection)
	set_process_input(touch_enabled)
	if touch_enabled and not demo.is_empty():
		var d: Node = (load("res://game/ui/touch/touch_demo.gd") as GDScript).new()
		d.name = "TouchDemo"
		add_child(d)
		d.call(&"run", self, demo)


func _exit_tree() -> void:
	_release_all_actions()


# --- Public -------------------------------------------------------------------------------------

func is_showing() -> bool:
	return _shown


func is_touch_mode() -> bool:
	return input_mode == &"touch"


# True when prompts and legends should show the pad buttons: the touch buttons carry the pad letters.
func uses_pad_glyphs() -> bool:
	return input_mode != &"keys"


func toast(title: String, detail := "", hold := 2.4) -> void:
	_toast.show_toast(title, detail, hold)


# --- Input mode ---------------------------------------------------------------------------------

# Runs before any node's _input, so a menu that consumes the event still switches the mode.
func _on_window_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_enabled:
			_set_mode(&"touch")
	elif event is InputEventKey:
		if event.pressed and not event.echo:
			_set_mode(&"keys")
	elif event is InputEventMouseButton:
		if event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
			_set_mode(&"keys")
	elif event is InputEventJoypadButton:
		if event.pressed and event.device != SCRIPT_PAD:
			_set_mode(&"pad")
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > PAD_AXIS_SWITCH and event.device != SCRIPT_PAD:
			_set_mode(&"pad")


func _set_mode(mode: StringName) -> void:
	if mode == input_mode:
		return
	input_mode = mode
	_refresh_shown()
	input_mode_changed.emit(mode)


func _on_joy_connection(device: int, connected: bool) -> void:
	if device == SCRIPT_PAD:
		return
	var joy_name := Input.get_joy_name(device)
	toast("Controle conectado" if connected else "Controle desconectado", joy_name)
	if connected:
		_set_mode(&"pad")
	elif Input.get_connected_joypads().filter(func(d: int) -> bool: return d != device).is_empty():
		_set_mode(&"touch" if touch_enabled else &"keys")


# --- Context and visibility ---------------------------------------------------------------------

func _find_context() -> StringName:
	var tree := get_tree()
	if tree.paused or not tree.get_nodes_in_group(&"pause_blocker").is_empty():
		return &""
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = tree.get_first_node_in_group(&"player")
		var scene := tree.current_scene
		_bike = scene.get(&"bike") if scene else null
		_manager = scene.get_node_or_null(^"InteractionManager") if scene else null
	if _player == null:
		return &""
	if is_instance_valid(_bike) and _bike is Node and int(_bike.get(&"mode")) >= MOTO_ON_BIKE:
		return &"moto"
	return &"foot"


func _refresh_shown() -> void:
	_context = _find_context() if touch_enabled else &""
	var on := touch_enabled and input_mode == &"touch" and _context != &""
	if on != _shown:
		_shown = on
		if not on:
			_cancel_all()


# --- Layout -------------------------------------------------------------------------------------

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_scale = clampf(minf(vp.x, vp.y) / REFERENCE_SHORT_SIDE, SCALE_MIN, SCALE_MAX)
	_safe = _safe_rect(vp)
	var s := _scale
	_stick.place(Vector2(_safe.position.x + STICK_HOME.x * s, _safe.end.y - STICK_HOME.y * s), STICK_RADIUS * s, KNOB_RADIUS * s)
	var c := _safe.end - DIAMOND * s
	var d := DIAMOND_GAP * s
	_place(_jump, c + Vector2(0, d), 62.0)
	_place(_roll, c + Vector2(d, 0), 52.0)
	_place(_attack, c + Vector2(-d, 0), 52.0)
	_place(_aim, c + AIM_OFFSET * s, 60.0)
	var t := _safe.end - THROTTLE_INSET * s
	_place(_throttle, t, 78.0)
	_place(_brake, t + BRAKE_OFFSET * s, 60.0)
	if _context == &"moto":
		_place(_interact, t + DISMOUNT_OFFSET * s, 46.0)
	else:
		_place(_interact, c + Vector2(0, -d), 46.0)
	var g := Vector2(_safe.end.x - GADGET_INSET * s, _safe.position.y + GADGET_INSET * s)
	_place(_pause, g, GADGET_RADIUS)
	_place(_restart, g + Vector2(0, 92.0 * s), GADGET_RADIUS)


func _place(b: TouchButton, at: Vector2, r: float) -> void:
	b.center = at.round()
	b.radius = roundf(r * _scale)


# Safe area (notches) in canvas coordinates. Desktop windows use the whole viewport.
func _safe_rect(vp: Vector2) -> Rect2:
	var rect := Rect2(Vector2.ZERO, vp)
	var to_canvas := get_viewport().get_final_transform().affine_inverse()
	if OS.has_feature("mobile"):
		var win := Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
		var safe := Rect2(DisplayServer.get_display_safe_area()).intersection(win)
		if safe.has_area():
			safe.position -= win.position
			rect = rect.intersection(to_canvas * safe)
	if _forced_insets != Vector4.ZERO:
		var k := to_canvas.get_scale().x
		rect = rect.grow_individual(-_forced_insets.x * k, -_forced_insets.y * k, -_forced_insets.z * k, -_forced_insets.w * k)
	return rect


func _apply_shown_flags() -> void:
	var moto := _context == &"moto"
	var combat: Object = _player.get(&"combat") if _player else null
	var armed: bool = combat != null and not bool(combat.get(&"holstered"))
	_jump.shown = not moto
	_roll.shown = not moto
	_attack.shown = not moto and armed
	_aim.shown = not moto and armed and StringName(combat.get(&"weapon")) in AIMED_WEAPONS
	_throttle.shown = moto
	_brake.shown = moto
	_restart.shown = moto
	_stick.horizontal_only = moto
	if moto:
		_interact.lit_target = _bike.has_method(&"can_dismount") and bool(_bike.call(&"can_dismount"))
	else:
		_interact.lit_target = is_instance_valid(_manager) and _manager.get(&"target") != null
	_weapon_rect = Rect2()
	if not moto and armed:
		var hud := get_tree().get_first_node_in_group(&"weapon_hud")
		if hud and hud.visible and hud.has_method(&"touch_rect"):
			_weapon_rect = hud.call(&"touch_rect")


# --- Touch input --------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	_refresh_shown()
	if not _shown:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_finger_down(event.index, event.position)
		else:
			_finger_up(event.index)
	else:
		_finger_drag(event.index, event.position)


func _finger_down(index: int, p: Vector2) -> void:
	if _bindings.has(index):
		_finger_up(index)
	_layout()
	_apply_shown_flags()
	for b in _buttons:
		if b.hit(p):
			_bindings[index] = b
			_press_button(b, p)
			return
	if _weapon_rect.has_area() and _weapon_rect.grow(12.0 * _scale).has_point(p):
		_bindings[index] = &"weapon"
		_pulse(&"weapon_next")
		_weapon_flash = 1.0
		Haptics.handheld(0.3, 0.03)
		return
	var left := p.x < _safe.position.x + _safe.size.x * LEFT_ZONE and p.y > _safe.position.y + _safe.size.y * TOP_BAND
	if left and not _stick.active:
		_bindings[index] = BIND_STICK
		_stick.press(p)
		Haptics.handheld(0.15, 0.02)


func _finger_drag(index: int, p: Vector2) -> void:
	var bound: Variant = _bindings.get(index)
	if bound is StringName and bound == BIND_STICK:
		_stick.drag(p)
	elif bound is TouchButton and bound == _aim:
		var v := (p - _aim.center) / (_aim.radius * AIM_RANGE)
		_aim_vec = v.limit_length(1.0)


func _finger_up(index: int) -> void:
	var bound: Variant = _bindings.get(index)
	_bindings.erase(index)
	if bound is StringName and bound == BIND_STICK:
		_stick.release()
	elif bound is TouchButton:
		var b: TouchButton = bound
		b.release()
		if b == _aim:
			_begin_fire()
		else:
			var action := _button_action(b)
			if not action.is_empty():
				_release_soon(action)


func _button_action(b: TouchButton) -> StringName:
	match b.kind:
		&"jump": return &"jump"
		&"roll": return &"roll"
		&"attack": return &"attack"
		&"interact": return &"interact"
		&"throttle": return &"moto_throttle"
		&"brake": return &"moto_brake"
	return &""


func _press_button(b: TouchButton, p: Vector2) -> void:
	b.press(p)
	match b.kind:
		&"pause":
			# The pause menu reads the event, not the action state.
			for on in [true, false]:
				var ev := InputEventAction.new()
				ev.action = &"pause"
				ev.pressed = on
				Input.parse_input_event(ev)
			Haptics.handheld(0.3, 0.03)
		&"restart":
			_pulse(&"moto_restart")
			Haptics.handheld(0.3, 0.03)
		&"aim":
			_cancel_fire()
			_aim_vec = Vector2.ZERO
			_press_action(&"aim", 1.0)
			Haptics.handheld(0.25, 0.03)
		_:
			_press_action(_button_action(b), 1.0)
			Haptics.handheld(0.35 if b == _jump or b == _throttle else 0.25, 0.035)


func _cancel_all() -> void:
	_stick.release()
	for b in _buttons:
		b.release()
	_bindings.clear()
	_aim_vec = Vector2.ZERO
	_fire_t = -1.0
	_release_all_actions()


# --- Actions ------------------------------------------------------------------------------------

func _press_action(action: StringName, strength: float) -> void:
	if action.is_empty() or not InputMap.has_action(action):
		return
	_hold_until.erase(action)
	if strength <= 0.0:
		if _pressed.has(action):
			Input.action_release(action)
			_pressed.erase(action)
		return
	Input.action_press(action, clampf(strength, 0.0, 1.0))
	if not _pressed.has(action):
		_pressed[action] = _clock


# Taps can be shorter than a physics tick: the action stays held for a minimum time.
func _release_soon(action: StringName) -> void:
	if _pressed.has(action):
		_hold_until[action] = float(_pressed[action]) + MIN_HOLD


func _pulse(action: StringName) -> void:
	_press_action(action, 1.0)
	_release_soon(action)


func _release_all_actions() -> void:
	for action: StringName in _pressed.keys():
		if InputMap.has_action(action):
			Input.action_release(action)
	_pressed.clear()
	_hold_until.clear()


# Axis halves are pressed only past their InputMap deadzone, like a pad's axis events.
func _feed_axis(negative: StringName, positive: StringName, v: float) -> void:
	for pair in [[positive, maxf(v, 0.0)], [negative, maxf(-v, 0.0)]]:
		var action: StringName = pair[0]
		var k: float = pair[1]
		if InputMap.has_action(action) and k < InputMap.action_get_deadzone(action):
			k = 0.0
		_press_action(action, k)


func _feed() -> void:
	var v := _stick.output()
	if _context == &"moto":
		_feed_axis(&"move_left", &"move_right", 0.0)
		_feed_axis(&"move_up", &"move_down", 0.0)
		_press_action(&"sprint", 0.0)
		_feed_axis(&"moto_lean_back", &"moto_lean_forward", v.x)
		return
	_feed_axis(&"moto_lean_back", &"moto_lean_forward", 0.0)
	_feed_axis(&"move_left", &"move_right", v.x)
	_feed_axis(&"move_up", &"move_down", v.y)
	var sprint := _stick.active and _stick.in_sprint_band()
	if sprint and not _was_sprint:
		_stick.flash_sprint()
		Haptics.handheld(0.2, 0.025)
	_was_sprint = sprint
	_press_action(&"sprint", 1.0 if sprint else 0.0)
	if _aim.pressed or _fire_t >= 0.0:
		_feed_axis(&"aim_left", &"aim_right", _aim_vec.x)
		_feed_axis(&"aim_up", &"aim_down", _aim_vec.y)


# Release of the aim stick: keep the aim held, press fire once the weapon is in its aim (a quick
# tap has not raised it yet), and let go when a shot left or after a short wait.
func _begin_fire() -> void:
	var guns: Object = _combat_part(&"guns")
	_fire_shots = int(guns.get(&"shots")) if guns else 0
	_fire_t = _clock
	_fire_pressed_t = -1.0


func _cancel_fire() -> void:
	if _fire_t < 0.0:
		return
	_fire_t = -1.0
	_press_action(&"fire", 0.0)
	_press_action(&"aim", 0.0)


func _step_fire() -> void:
	if _fire_t < 0.0:
		return
	var guns: Object = _combat_part(&"guns")
	var bow: Object = _combat_part(&"bow")
	var aiming: bool = (guns != null and bool(guns.get(&"aiming"))) or (bow != null and bool(bow.get(&"aiming")))
	if _fire_pressed_t < 0.0:
		if aiming or _clock - _fire_t >= FIRE_WAIT:
			_press_action(&"fire", 1.0)
			_fire_pressed_t = _clock
		return
	var shot: bool = (guns != null and int(guns.get(&"shots")) > _fire_shots) or (bow != null and bool(bow.get(&"releasing")))
	if (shot and _clock - _fire_pressed_t >= MIN_HOLD) or _clock - _fire_pressed_t >= FIRE_HOLD or _clock - _fire_t >= FIRE_GIVE_UP:
		_fire_t = -1.0
		_press_action(&"fire", 0.0)
		_press_action(&"aim", 0.0)
		_aim_vec = Vector2.ZERO
		_feed_axis(&"aim_left", &"aim_right", 0.0)
		_feed_axis(&"aim_up", &"aim_down", 0.0)


func _combat_part(part: StringName) -> Object:
	if not is_instance_valid(_player):
		return null
	var combat: Object = _player.get(&"combat")
	return combat.get(part) if combat else null


# --- Frame --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	for action: StringName in _hold_until.keys():
		if _clock >= float(_hold_until[action]):
			_hold_until.erase(action)
			if _pressed.has(action):
				Input.action_release(action)
				_pressed.erase(action)
	if not touch_enabled:
		return
	_refresh_shown()
	if _shown:
		_layout()
		_apply_shown_flags()
		_feed()
		_step_fire()
	_alpha = move_toward(_alpha, 1.0 if _shown else 0.0, delta / FADE_TIME)
	_canvas.modulate.a = _alpha
	_canvas.visible = _alpha > 0.0
	if _alpha <= 0.0:
		return
	_stick.update(delta)
	for b in _buttons:
		b.update(delta)
	_weapon_flash = maxf(_weapon_flash - delta / 0.3, 0.0)
	_canvas.queue_redraw()


func _draw_controls() -> void:
	_stick.draw(_canvas)
	for i in range(_buttons.size() - 1, -1, -1):
		_buttons[i].draw(_canvas)
	if _aim.pressed and _aim.appear > 0.5:
		var reach := _aim.radius * AIM_RANGE
		_canvas.draw_circle(_aim.center, reach, Color(ORANGE, 0.5), false, 3.0)
		var k := _aim.center + _aim_vec * reach
		_canvas.draw_line(_aim.center, k, Color(ORANGE, 0.6), 3.0)
		_canvas.draw_circle(k, _aim.radius * 0.42, Color(ORANGE, 0.85))
	if _weapon_rect.has_area():
		# A small cycle badge on the right of the weapon bar: the bar is the button.
		var s := _scale
		var at := Vector2(_weapon_rect.end.x + 22.0 * s, _weapon_rect.position.y + _weapon_rect.size.y * 0.5).round()
		var r := roundf(18.0 * s)
		_canvas.draw_circle(at, r, Color(0.06, 0.05, 0.09, 0.55 + 0.3 * _weapon_flash))
		_canvas.draw_circle(at, r, Color(1, 1, 1, 0.7), false, 2.0)
		for side in [-1.0, 1.0]:
			var tip := at + Vector2(side * r * 0.55, 0)
			_canvas.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-side * r * 0.4, -r * 0.35), tip + Vector2(-side * r * 0.4, r * 0.35)]), Color(1, 1, 1, 0.9))
