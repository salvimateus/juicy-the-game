extends "res://game/interactables/interactable.gd"

# Push button on a post. Interacting presses it (cap sinks, button_press sound and rumble) and
# emits `pressed`; other systems connect to that signal. The origin is the floor point under it.

const Art := preload("res://game/interactables/interactables_art.gd")
# Push button art: 14x31 art px, origin at the bottom of the post.
const ART_TOP_LEFT := Vector2(-7, -31)

signal pressed

@export var enabled := true
@export var press_time := 0.22
@export var cooldown := 0.5

# Whoever pressed it last through interact() (null when pressed from code).
var last_user: Node
var _sprite: Sprite2D
var _down := 0.0
var _wait := 0.0


func _ready() -> void:
	_sprite = art_sprite(Art.push_button(false), ART_TOP_LEFT)
	# The whole post is reachable, so the player on a block beside it still gets the prompt.
	if interact_height <= 0.0:
		interact_height = -ART_TOP_LEFT.y * GameScale.art_pixel()
	_sprite.name = "Sprite"
	add_child(_sprite)


func can_interact(_player: Node) -> bool:
	return enabled and _wait <= 0.0


func interact(player: Node) -> void:
	last_user = player
	press()


# Presses the button from code too (same feedback and signal).
func press() -> void:
	if not enabled or _wait > 0.0:
		return
	_down = press_time
	_wait = cooldown
	_sprite.texture = Art.push_button(true)
	Feedback.sfx(&"button_press", global_position + Vector2(0, -180))
	haptic(&"button_press", 0.6)
	pressed.emit()


func _process(delta: float) -> void:
	_wait = maxf(0.0, _wait - delta)
	if _down > 0.0:
		_down -= delta
		if _down <= 0.0:
			_sprite.texture = Art.push_button(false)
