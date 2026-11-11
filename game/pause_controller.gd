extends Node

# Instances the title and pause menus. The PauseMenu owns the `pause` input and the tree pause;
# this node holds the feedback loops while it is open and reports when a menu covers the screen.
# It also routes the scene changes: the title's Motocross pick and the pause's "Menu inicial".

signal covered_changed(covered: bool)

const START_MENU_SCENE := "res://game/ui/start_menu.tscn"
const START_MENU_SCRIPT := "res://game/ui/start_menu.gd"
const PAUSE_MENU_SCENE := "res://game/ui/pause_menu.tscn"
const MOTO_SCENE := "res://game/moto/moto_level.tscn"
const Feedback := preload("res://game/feedback.gd")
const BACK_QUIT_WINDOW := 2.0

var start_menu: Node
var pause_menu: Node
var _held := false
var _leaving := false
var _back_time := -100.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


# `legends` empty keeps the Aventura controls; otherwise {"pad": Array, "keys": Array} with rows in
# the PAD_LEGEND / KEY_LEGEND formats of game/ui/pause_menu.gd.
func setup(show_title: bool, legends := {}) -> void:
	if show_title and ResourceLoader.exists(START_MENU_SCENE) and load(START_MENU_SCRIPT).will_show():
		start_menu = (load(START_MENU_SCENE) as PackedScene).instantiate()
		add_child(start_menu)
		start_menu.tree_exited.connect(func() -> void: covered_changed.emit(is_covered()))
		if is_instance_valid(start_menu) and start_menu.has_signal(&"start_requested"):
			start_menu.start_requested.connect(_on_start)
			# The start fades to black instead of to the game when a scene change follows it.
			start_menu.set(&"black_out_modes", [&"moto"] if ResourceLoader.exists(MOTO_SCENE) else [])
	if ResourceLoader.exists(PAUSE_MENU_SCENE):
		pause_menu = (load(PAUSE_MENU_SCENE) as PackedScene).instantiate()
		add_child(pause_menu)
		pause_menu.opened.connect(_on_opened)
		pause_menu.closed.connect(_on_closed)
		pause_menu.menu_requested.connect(_on_menu)
		if not legends.is_empty():
			pause_menu.set_legends(legends.get("pad", pause_menu.pad_legend), legends.get("keys", pause_menu.key_legend))
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


func is_covered() -> bool:
	var title := is_instance_valid(start_menu) and start_menu.is_inside_tree() and not start_menu.is_queued_for_deletion()
	return title or (pause_menu != null and pause_menu.is_open())


func is_paused_by_menu() -> bool:
	return pause_menu != null and pause_menu.is_open()


func _on_opened() -> void:
	_hold(true)
	covered_changed.emit(true)


func _on_closed() -> void:
	_hold(false)
	Feedback.haptic(&"menu_select")
	covered_changed.emit(is_covered())


func _on_start() -> void:
	if is_instance_valid(start_menu) and start_menu.get(&"mode") == &"moto" and ResourceLoader.exists(MOTO_SCENE):
		_change_scene(MOTO_SCENE)


func _on_menu() -> void:
	load(START_MENU_SCRIPT).show_again()
	_change_scene(ProjectSettings.get_setting("application/run/main_scene"))


func _change_scene(path: String) -> void:
	if _leaving:
		return
	_leaving = true
	_hold(false)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(path)


# A controller dropping mid-game pauses it, as the consoles require.
func _on_joy_connection_changed(_pad: int, connected: bool) -> void:
	if connected or pause_menu == null or _leaving or is_covered() or not pause_menu.can_open():
		return
	pause_menu.open()
	# The TouchControls autoload already switched the mode: on a phone the last pad leaving goes
	# back to touch, which shows the pad view.
	var touch := get_node_or_null(^"/root/TouchControls")
	pause_menu.set_keyboard(Input.get_connected_joypads().is_empty() if touch == null else not touch.uses_pad_glyphs())


# Android back (gesture, system button, and pads that send KEYCODE_BACK): closes the pause, opens
# it in game, and elsewhere (title, ending) quits only on a second press within BACK_QUIT_WINDOW.
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or _leaving:
		return
	if pause_menu and pause_menu.is_open():
		pause_menu.close()
		return
	if pause_menu and pause_menu.can_open():
		pause_menu.open()
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _back_time <= BACK_QUIT_WINDOW:
		get_tree().quit()
		return
	_back_time = now
	var touch := get_node_or_null(^"/root/TouchControls")
	if touch:
		touch.toast("Voltar de novo para sair", "", BACK_QUIT_WINDOW)


func _hold(on: bool) -> void:
	if _held == on:
		return
	_held = on
	var sfx := get_node_or_null(^"/root/Sfx")
	if sfx and sfx.has_method(&"pause_loops"):
		sfx.pause_loops(on)
	var haptics := get_node_or_null(^"/root/Haptics")
	if haptics and haptics.has_method(&"pause_all"):
		haptics.pause_all(on)


# "Reiniciar fase" and the scene changes leave without closing: the autoloads must not stay held,
# and the reloaded controller connects its own handler.
func _exit_tree() -> void:
	_hold(false)
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)
