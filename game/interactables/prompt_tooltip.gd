extends Node2D

# World-space prompt: pixel-art box with the button icon and the action text, its tail pointing
# at the anchor. Pops in by rising a few art pixels in steps and fades out softly.

const Art := preload("res://game/interactables/interactables_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")

# Art-pixel offsets (positive is down) per pop step, each held for POP_STEP seconds.
const POP_OFFSETS := [3, 1, -1, 0]
const POP_ALPHA := [0.35, 0.8, 1.0, 1.0]
const POP_STEP := 0.04
const FADE_TIME := 0.14
const FADE_DROP := 1
# Art pixels kept between the box and the edges of the view.
const VIEW_MARGIN := 2

var text := ""
var gamepad := false
var anchor := Vector2.ZERO
var key_letter := "E"
var _sprite: Sprite2D
var _tip := Vector2i.ZERO
var _pop_t := -1.0
var _fade_t := -1.0
var _shown := false


func _ready() -> void:
	top_level = true
	z_as_relative = false
	z_index = 100
	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.scale = Vector2.ONE * GameScale.art_pixel()
	add_child(_sprite)
	visible = false


func is_shown() -> bool:
	return _shown


# Shows (or retargets) the prompt; a new text or a hidden prompt pops again.
func show_prompt(new_text: String, at: Vector2, use_gamepad: bool) -> void:
	anchor = at
	var changed := new_text != text or use_gamepad != gamepad
	if not _shown or new_text != text:
		_pop_t = 0.0
		Feedback.sfx(&"prompt_pop")
	text = new_text
	gamepad = use_gamepad
	if changed or _sprite.texture == null:
		_rebuild()
	_shown = true
	_fade_t = -1.0
	visible = true
	_place()


func hide_prompt() -> void:
	if not _shown:
		return
	_shown = false
	_fade_t = 0.0


func _rebuild() -> void:
	var box := Art.prompt_box(text, gamepad, key_letter)
	_sprite.texture = box.texture
	_tip = box.tip


func _process(delta: float) -> void:
	if not visible:
		return
	if _pop_t >= 0.0:
		_pop_t += delta
		if _pop_t >= POP_STEP * POP_OFFSETS.size():
			_pop_t = -1.0
	if _fade_t >= 0.0:
		_fade_t += delta
		if _fade_t >= FADE_TIME:
			_fade_t = -1.0
			visible = false
			return
	_place()


func _place() -> void:
	var a := GameScale.art_pixel()
	var rise := 0
	var alpha := 1.0
	if _pop_t >= 0.0:
		var i := mini(int(_pop_t / POP_STEP), POP_OFFSETS.size() - 1)
		rise = POP_OFFSETS[i]
		alpha = POP_ALPHA[i]
	if _fade_t >= 0.0:
		var k := _fade_t / FADE_TIME
		alpha = 1.0 - k
		rise = FADE_DROP if k > 0.5 else 0
	var snapped := Vector2(roundf(anchor.x / a) * a, roundf(anchor.y / a) * a)
	global_position = _inside_view(snapped + Vector2(-_tip.x * a, (-_tip.y - 1 + rise) * a), a)
	modulate.a = alpha


# Keeps the whole box on screen (a camera framed low, as over the river, would cut it off above
# the player), on the art grid.
func _inside_view(pos: Vector2, a: float) -> Vector2:
	if _sprite.texture == null or not is_inside_tree():
		return pos
	var size := Vector2(_sprite.texture.get_size()) * a
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
	var margin := VIEW_MARGIN * a
	var lo := Vector2(ceilf((view.position.x + margin) / a), ceilf((view.position.y + margin) / a)) * a
	var hi := Vector2(floorf((view.end.x - margin - size.x) / a), floorf((view.end.y - margin - size.y) / a)) * a
	if hi.x < lo.x or hi.y < lo.y:
		return pos
	return pos.clamp(lo, hi)
