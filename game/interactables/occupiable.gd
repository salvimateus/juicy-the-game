extends "res://game/interactables/interactable.gd"

# Something the player gets into and out of (chair, bed): takes control of the player, moves it
# to the rest point with the right facing, plays the enter action (which the rig chains into its
# loop) and leaves on interact again or on movement input.

enum State { FREE, ENTERING, OCCUPIED, EXITING }

@export var exit_prompt := "Levantar"
@export var enter_action := &"sit_down"
@export var loop_action := &"sitting"
@export var exit_action := &"stand_up"
@export var sound := &"chair_creak"
@export var haptic_id := &"chair_creak"
@export var haptic_strength := 0.35
# Facing the player takes while resting; flips the art when negative.
@export var facing := 1:
	set(value):
		facing = 1 if value >= 0 else -1
		if is_node_ready():
			_apply_facing()
# Feet position of the resting player relative to the origin (x mirrors with facing).
@export var rest_offset := Vector2.ZERO
# Height of the surface the body rests on, passed to the rig as action_params[&"rest_height"].
@export var rest_height := 90.0
@export var slide_time := 0.12
# Input is ignored right after entering so the press that entered does not leave at once.
@export var min_rest_time := 0.35
@export var exit_timeout := 1.6
@export var reuse_delay := 0.3

var state := State.FREE
var occupant: Node2D
var _t := 0.0
var _cooldown := 0.0
var _rig: Node
# Leave asked while the enter action still plays: stands up as soon as the rest loop starts.
var _exit_pending := false


func _apply_facing() -> void:
	pass


func get_rest_point() -> Vector2:
	return global_position + Vector2(rest_offset.x * facing, rest_offset.y)


func get_prompt(player: Node) -> String:
	return exit_prompt if occupant == player else prompt


func can_interact(player: Node) -> bool:
	if occupant != null:
		return occupant == player and state == State.OCCUPIED and _t >= min_rest_time
	return state == State.FREE and _cooldown <= 0.0


func interact(player: Node) -> void:
	if state == State.FREE:
		_enter(player as Node2D)
	elif state == State.OCCUPIED and occupant == player:
		leave()


func _enter(player: Node2D) -> void:
	occupant = player
	state = State.ENTERING
	_t = 0.0
	_exit_pending = false
	player.take_control(self)
	if &"velocity" in player:
		player.velocity = Vector2.ZERO
	set_facing(player, facing)
	var tween := create_tween()
	tween.tween_property(player, ^"global_position", get_rest_point(), slide_time)
	tween.tween_callback(_start_rest)


func _start_rest() -> void:
	if occupant == null:
		return
	_rig = adventurer_of(occupant)
	if _rig:
		if &"action_params" in _rig:
			_rig.action_params[&"rest_height"] = rest_height
		if _rig.has_signal(&"action_finished") and not _rig.action_finished.is_connected(_on_rig_action_finished):
			_rig.action_finished.connect(_on_rig_action_finished)
	if not play_rig(occupant, enter_action):
		play_rig(occupant, loop_action)
	Feedback.sfx(sound, get_rest_point())
	haptic(haptic_id, haptic_strength, &"button_press")
	state = State.OCCUPIED
	_t = 0.0


func leave() -> void:
	if state != State.OCCUPIED or occupant == null:
		return
	# The enter action does not accept the exit one: leaving now would free the player still posed.
	if _settling():
		_exit_pending = true
		return
	_exit_pending = false
	state = State.EXITING
	_t = 0.0
	Feedback.sfx(sound, get_rest_point(), 0.7)
	haptic(haptic_id, haptic_strength * 0.7, &"button_press")
	if not play_rig(occupant, exit_action):
		if _rig_action() == loop_action and _rig.has_method(&"stop_action"):
			_rig.stop_action()
		_release()


func _settling() -> bool:
	return _rig_action() == enter_action


func _rig_action() -> StringName:
	if _rig == null or not is_instance_valid(_rig) or not _rig.has_method(&"current_action"):
		return &""
	return _rig.current_action()


func _release() -> void:
	if occupant and is_instance_valid(occupant):
		occupant.release_control(self)
	if _rig and is_instance_valid(_rig) and _rig.has_signal(&"action_finished") \
			and _rig.action_finished.is_connected(_on_rig_action_finished):
		_rig.action_finished.disconnect(_on_rig_action_finished)
	_rig = null
	_exit_pending = false
	occupant = null
	state = State.FREE
	_cooldown = reuse_delay


func _on_rig_action_finished(id: StringName) -> void:
	if occupant == null:
		return
	if id == enter_action and state == State.OCCUPIED:
		# Rigs whose enter action does not chain into the loop get it started here.
		if _rig.has_method(&"current_action") and _rig.current_action() != loop_action:
			play_rig(occupant, loop_action)
	elif id == exit_action and state == State.EXITING:
		_release()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if state == State.FREE or state == State.ENTERING:
		return
	_t += delta
	if not is_instance_valid(occupant):
		_release()
		return
	if state == State.EXITING:
		if _t >= exit_timeout:
			_release()
		return
	if _exit_pending or (_t >= min_rest_time and _wants_out()):
		leave()


func _wants_out() -> bool:
	return absf(Input.get_axis(&"move_left", &"move_right")) >= 0.5 \
		or Input.get_action_strength(&"move_up") >= 0.5 \
		or Input.is_action_just_pressed(&"jump")
