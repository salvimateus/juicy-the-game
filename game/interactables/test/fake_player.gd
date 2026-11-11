extends Node2D

# Minimal stand-in for game/player.gd with the interaction contract: group `player`,
# `adventurer`, can_interact_now, take/release_control, is_controlled, hurt and invulnerable.
# Walks with move_left/move_right when input_enabled.

const FakeAdventurer := preload("res://game/interactables/test/fake_adventurer.gd")

signal was_hurt(kind: StringName, landed: bool)

@export var input_enabled := true
@export var walk_speed := 600.0

var adventurer: Node2D
var facing := 1
var velocity := Vector2.ZERO
var invulnerable := false
var input_blocker: Object
var _controllers: Array = []
var _stun := 0.0
var _mercy := 0.0


func _enter_tree() -> void:
	add_to_group(&"player")


func _ready() -> void:
	adventurer = FakeAdventurer.new()
	adventurer.name = "FakeAdventurer"
	add_child(adventurer)


func set_facing(dir: int) -> void:
	facing = dir
	adventurer.facing = dir


func can_interact_now() -> bool:
	return not is_controlled() and _stun <= 0.0 and not adventurer.is_action_playing()


func take_control(owner: Node) -> void:
	if owner not in _controllers:
		_controllers.append(owner)


func release_control(owner: Node) -> void:
	_controllers.erase(owner)


func is_controlled() -> bool:
	_controllers = _controllers.filter(func(n): return is_instance_valid(n))
	return not _controllers.is_empty()


func hurt(kind: StringName, from_global: Vector2, strength: float = 1.0) -> bool:
	if invulnerable or _mercy > 0.0:
		print("FAKE PLAYER escaped ", kind)
		was_hurt.emit(kind, false)
		return false
	adventurer.play_action(&"shot_hit" if kind == &"shot" else &"hurt")
	var away := signf(global_position.x - from_global.x)
	velocity.x = (away if away != 0.0 else -facing) * 520.0 * strength
	_stun = 0.4
	_mercy = 0.6
	print("FAKE PLAYER hurt ", kind, " from ", from_global)
	was_hurt.emit(kind, true)
	return true


func _physics_process(delta: float) -> void:
	_mercy = maxf(0.0, _mercy - delta)
	if _stun > 0.0:
		_stun -= delta
		position.x += velocity.x * delta
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
		return
	if is_controlled() or not input_enabled:
		return
	var axis := Input.get_axis(&"move_left", &"move_right")
	if absf(axis) > 0.2:
		set_facing(1 if axis > 0.0 else -1)
		position.x += axis * walk_speed * delta
