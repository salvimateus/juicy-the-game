extends Node2D

# Picks the nearest available interactable around the player each physics frame, shows its prompt
# and calls interact() on the interact action (Y on the pad, E on the keyboard). While the player
# is controlled by the interactable it entered (seated, asleep), the prompt shows that one's exit.

const Tooltip := preload("res://game/interactables/prompt_tooltip.gd")

const DEFAULT_RADIUS := 160.0
const ACTION := &"interact"
# Joypad axis motion below this does not count as "last input was the pad".
const PAD_AXIS_THRESHOLD := 0.5

@export var player_path: NodePath
# Icon shown before any input arrives (a connected joypad also selects the pad).
@export var start_with_gamepad := false

var player: Node2D
var tooltip: Node2D
# True while the last input event came from a joypad.
var use_gamepad := false
var target: Node
var _active: Node
var _touch: Node


func _ready() -> void:
	tooltip = Tooltip.new()
	tooltip.name = "PromptTooltip"
	add_child(tooltip)
	use_gamepad = start_with_gamepad or not Input.get_connected_joypads().is_empty()
	# The TouchControls autoload owns the input mode when present; touch shows the pad glyphs.
	_touch = get_node_or_null(^"/root/TouchControls")
	if _touch:
		use_gamepad = start_with_gamepad or _touch.uses_pad_glyphs()
	if not player_path.is_empty():
		player = get_node_or_null(player_path) as Node2D


func _input(event: InputEvent) -> void:
	if _touch:
		use_gamepad = _touch.uses_pad_glyphs()
		return
	if event is InputEventJoypadButton:
		use_gamepad = true
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= PAD_AXIS_THRESHOLD:
			use_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		use_gamepad = false


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node2D
	if player == null:
		_set_target(null)
		return
	var next: Node = null
	var free := false
	if player.is_controlled():
		if is_instance_valid(_active) and _active.can_interact(player):
			next = _active
	else:
		_active = null
		free = true
		if player.can_interact_now():
			next = _nearest()
	_set_target(next, free)
	if target and Input.is_action_just_pressed(ACTION) and not _input_blocked():
		_active = target
		target.interact(player)
		_set_target(target if target.can_interact(player) else null, free and not player.is_controlled())


func _nearest() -> Node:
	var best: Node = null
	var best_d := INF
	var from := player.global_position
	for node in get_tree().get_nodes_in_group(&"interactable"):
		if not node.is_inside_tree() or not node.can_interact(player):
			continue
		var at: Vector2 = node.get_interact_point() if node.has_method(&"get_interact_point") else node.global_position
		var radius: float = node.get(&"interact_radius") if &"interact_radius" in node else DEFAULT_RADIUS
		var height: float = node.get(&"interact_height") if &"interact_height" in node else 0.0
		var d := _reach(from, at, height)
		if d <= radius and d < best_d:
			best_d = d
			best = node
	return best


# Distance from the feet to the reachable column (interact point up to `height` above it).
static func _reach(from: Vector2, at: Vector2, height: float) -> float:
	var top := at.y - maxf(height, 0.0)
	var dy := 0.0
	if from.y < top:
		dy = top - from.y
	elif from.y > at.y:
		dy = from.y - at.y
	return Vector2(from.x - at.x, dy).length()


# free: the player walks on its own, so a prompt anchored at floor level rises with the player
# standing higher than the interact point (on a block beside a button) instead of covering the body.
func _set_target(node: Node, free := false) -> void:
	target = node
	if node == null:
		tooltip.hide_prompt()
		return
	var anchor: Vector2 = node.get_prompt_anchor()
	if free:
		var at: Vector2 = node.get_interact_point() if node.has_method(&"get_interact_point") else node.global_position
		anchor.y += minf(0.0, player.global_position.y - at.y)
	tooltip.show_prompt(node.get_prompt(player), anchor, use_gamepad)


func _input_blocked() -> bool:
	var blocker = player.get(&"input_blocker")
	return blocker is Object and is_instance_valid(blocker) and blocker.get(&"visible") == true
