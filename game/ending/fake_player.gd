extends CharacterBody2D

# Stand-in player for the ending test: the minimal API EndingWall reads (group `player`,
# `pushing`, `facing`, `camera_shake`, `take_control`, `release_control`, `is_controlled`).

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")

var pushing := false
var facing := 1
var scripted := false
var _controllers: Array[Node] = []


func _ready() -> void:
	add_to_group(&"player")
	var a := GameScale.art_pixel()
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 60.0
	cap.height = 400.0
	shape.shape = cap
	shape.position = Vector2(0, -200)
	add_child(shape)
	# Blocky leaning figure, art pixels of 6 units.
	var img := Image.create(16, 70, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(4, 0, 9, 11), PixelArt.OUTLINE)
	img.fill_rect(Rect2i(5, 1, 7, 9), Color("#d8a878"))
	img.fill_rect(Rect2i(3, 11, 11, 32), PixelArt.OUTLINE)
	img.fill_rect(Rect2i(4, 12, 9, 30), Color("#3d5a8a"))
	img.fill_rect(Rect2i(10, 16, 6, 4), PixelArt.OUTLINE)
	img.fill_rect(Rect2i(4, 43, 4, 27), PixelArt.OUTLINE)
	img.fill_rect(Rect2i(10, 43, 4, 27), PixelArt.OUTLINE)
	img.fill_rect(Rect2i(5, 43, 2, 26), Color("#5a4030"))
	img.fill_rect(Rect2i(11, 43, 2, 26), Color("#5a4030"))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(img)
	sprite.centered = false
	sprite.scale = Vector2(a, a)
	sprite.position = Vector2(-8 * a, -70 * a)
	add_child(sprite)


func _physics_process(delta: float) -> void:
	if not scripted:
		pushing = not is_controlled() and Input.is_action_pressed(&"move_right")
	if is_controlled():
		pushing = false
	velocity.x = 0.0
	velocity.y += 2600.0 * delta
	move_and_slide()


func camera_shake(amount: float, duration: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method(&"add_shake"):
		cam.add_shake(amount, duration)


func hitstop(_seconds: float) -> void:
	pass


func take_control(owner: Node) -> void:
	if owner not in _controllers:
		_controllers.append(owner)
	pushing = false


func release_control(owner: Node) -> void:
	_controllers.erase(owner)


func is_controlled() -> bool:
	return not _controllers.is_empty()
