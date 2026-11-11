extends Node2D

# Base for the interactables in this folder. The manager only relies on the duck-typed contract
# (group `interactable`, get_prompt, can_interact, interact, get_prompt_anchor, optional
# interact_radius, interact_height and get_interact_point), so other systems may implement it without extending this.

const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")

const GROUP := &"interactable"
# Standing body box used for hit tests when the player does not expose one (sole at the origin).
const BODY_HALF_WIDTH := 54.0
const BODY_HEIGHT := 426.0

@export var prompt := "Interagir"
@export var interact_radius := 160.0
# Height above the interact point that also counts as reachable (a post the player can stand
# beside on a block or step); 0 keeps the reach a single point.
@export var interact_height := 0.0
# Where the prompt tail points, relative to the interact point (above the character's head).
@export var prompt_offset := Vector2(0, -462)


func _enter_tree() -> void:
	add_to_group(GROUP)


func get_prompt(_player: Node) -> String:
	return prompt


func can_interact(_player: Node) -> bool:
	return true


func interact(_player: Node) -> void:
	pass


# Point the player has to be near (feet level); defaults to this node.
func get_interact_point() -> Vector2:
	return global_position


func get_prompt_anchor() -> Vector2:
	return get_interact_point() + prompt_offset


static func adventurer_of(player: Node) -> Node:
	if player == null:
		return null
	var a = player.get(&"adventurer")
	return a if a is Node else null


static func play_rig(player: Node, id: StringName) -> bool:
	var a := adventurer_of(player)
	return a != null and a.has_method(&"play_action") and a.play_action(id)


static func set_facing(player: Node, dir: int) -> void:
	if player.has_method(&"set_facing"):
		player.set_facing(dir)
		return
	if &"facing" in player:
		player.facing = dir
	var a := adventurer_of(player)
	if a and &"facing" in a:
		a.facing = dir


# World-space hurt box of the player (sole at its origin).
static func body_rect(player: Node2D) -> Rect2:
	if player.has_method(&"get_hurt_rect"):
		return player.get_hurt_rect()
	var p := player.global_position
	return Rect2(p.x - BODY_HALF_WIDTH, p.y - BODY_HEIGHT, BODY_HALF_WIDTH * 2.0, BODY_HEIGHT)


static func hurt(player: Node, kind: StringName, from_global: Vector2, direction: Vector2, strength := 1.0) -> bool:
	var a := adventurer_of(player)
	if a and a.has_method(&"set_hit_direction"):
		a.set_hit_direction(direction)
	return player.has_method(&"hurt") and player.hurt(kind, from_global, strength)


# Haptic profile with a fallback id when the first one does not exist yet.
static func haptic(id: StringName, strength: float, fallback: StringName = &"") -> void:
	var h := Feedback.haptics()
	if h == null:
		return
	if h.has_method(&"has_profile") and not h.has_profile(id) and fallback != &"":
		h.play(fallback, strength)
	else:
		h.play(id, strength)


func art_sprite(texture: Texture2D, top_left_art: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = texture
	s.centered = false
	s.offset = top_left_art
	s.scale = Vector2.ONE * GameScale.art_pixel()
	return s
