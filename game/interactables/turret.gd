extends Node2D

# Turret (pedestal, swivelling barrel, warning light) fired by a push button next to it. Pressing
# the button makes it track the player's chest, blink its light for warn_time and fire one fast
# round with a tracer; the round calls player.hurt(&"shot", ...) and flies through when the player
# dodges. The button stays disabled until the cooldown ends. Origin: floor point under the turret.

const Art := preload("res://game/interactables/interactables_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const Interactable := preload("res://game/interactables/interactable.gd")
const Bullet := preload("res://game/interactables/turret_bullet.gd")
const BUTTON_SCENE := preload("res://game/interactables/reset_button.tscn")

signal fired(bullet: Node)
signal shot_resolved(player: Node, hit: bool)
signal ready_again

enum State { READY, AIMING, WARNING, COOLDOWN }

const LIGHT_READY := Color("#58c860")
const LIGHT_ALERT := Color("#ff4434")
const LIGHT_OFF := Color("#4a1a1a")
const LIGHT_COOL := Color("#a07428")

@export var prompt := "Levar tiro"
# Direction the barrel rests in and the side the button sits on.
@export var facing := -1
# Button position relative to the turret (x mirrors with facing).
@export var button_distance := 540.0
@export var aim_time := 0.25
@export var warn_time := 0.4
@export var blink_period := 0.1
@export var cooldown := 2.2
@export var bullet_speed := 4200.0
@export var aim_speed := 14.0

var state := State.READY
var button: Node2D
var _victim: Node2D
var _t := 0.0
var _a := 6.0
var _barrel: Sprite2D
var _light: Sprite2D
var _flash: Node2D
var _flash_t := 0.0
var _recoil := 0.0
var _aim_angle := 0.0


func _ready() -> void:
	_a = GameScale.art_pixel()
	_aim_angle = 0.0 if facing > 0 else PI
	var base := Sprite2D.new()
	base.name = "Base"
	base.texture = Art.turret_base()
	base.centered = false
	base.offset = Vector2(Art.TURRET_BASE_ORIGIN)
	base.scale = Vector2.ONE * _a
	add_child(base)
	_barrel = Sprite2D.new()
	_barrel.name = "Barrel"
	_barrel.texture = Art.turret_barrel()
	_barrel.centered = false
	_barrel.offset = -Vector2(Art.BARREL_PIVOT)
	_barrel.scale = Vector2.ONE * _a
	add_child(_barrel)
	_light = Sprite2D.new()
	_light.name = "Light"
	_light.texture = Art.light_bulb()
	_light.centered = false
	_light.offset = Vector2(-3, -27)
	_light.scale = Vector2.ONE * _a
	add_child(_light)
	_flash = Node2D.new()
	_flash.name = "MuzzleFlash"
	_flash.z_index = 1
	_flash.draw.connect(_draw_flash)
	add_child(_flash)
	button = BUTTON_SCENE.instantiate()
	button.name = "Button"
	button.prompt = prompt
	button.position = Vector2(button_distance * facing, 0)
	add_child(button)
	button.pressed.connect(_on_button_pressed)
	_update_visuals()


func pivot_global() -> Vector2:
	return global_position + Vector2(Art.TURRET_PIVOT) * _a


func muzzle_global() -> Vector2:
	var local := Vector2(Art.BARREL_MUZZLE - Art.BARREL_PIVOT) * _a
	return pivot_global() + local.rotated(_aim_angle)


func _on_button_pressed() -> void:
	if state != State.READY:
		return
	_victim = button.last_user as Node2D
	if _victim == null:
		_victim = get_tree().get_first_node_in_group(&"player") as Node2D
	state = State.AIMING
	_t = 0.0
	button.enabled = false


func _physics_process(delta: float) -> void:
	_t += delta
	_recoil = maxf(0.0, _recoil - delta)
	_flash_t = maxf(0.0, _flash_t - delta)
	match state:
		State.AIMING, State.WARNING:
			_track(delta)
			if state == State.AIMING and _t >= aim_time:
				state = State.WARNING
				_t = 0.0
			elif state == State.WARNING and _t >= warn_time:
				_fire()
		State.COOLDOWN:
			var rest := 0.0 if facing > 0 else PI
			_aim_angle = lerp_angle(_aim_angle, rest, 1.0 - exp(-3.0 * delta))
			if _t >= cooldown:
				state = State.READY
				button.enabled = true
				ready_again.emit()
	_update_visuals()


func _track(delta: float) -> void:
	if not is_instance_valid(_victim):
		return
	var r := Interactable.body_rect(_victim)
	var chest := Vector2(r.get_center().x, r.position.y + r.size.y * 0.32)
	var want := (chest - pivot_global()).angle()
	_aim_angle = lerp_angle(_aim_angle, want, 1.0 - exp(-aim_speed * delta))


func _fire() -> void:
	state = State.COOLDOWN
	_t = 0.0
	_recoil = 0.08
	_flash_t = 0.06
	var b := Bullet.new()
	b.name = "Bullet"
	b.direction = Vector2.RIGHT.rotated(_aim_angle)
	b.speed = bullet_speed
	b.origin = muzzle_global()
	b.target = _victim
	b.hit.connect(func(target: Node, landed: bool): shot_resolved.emit(target, landed))
	add_child(b)
	Feedback.sfx(&"turret_shot", muzzle_global())
	Feedback.haptic(&"turret_shot", 0.7)
	fired.emit(b)


func _update_visuals() -> void:
	var dir := Vector2.RIGHT.rotated(_aim_angle)
	_barrel.position = Vector2(Art.TURRET_PIVOT) * _a - (dir * _a if _recoil > 0.0 else Vector2.ZERO)
	_barrel.rotation = _aim_angle
	_barrel.flip_v = dir.x < 0.0
	match state:
		State.READY:
			_light.modulate = LIGHT_READY
		State.AIMING:
			_light.modulate = LIGHT_ALERT
		State.WARNING:
			_light.modulate = LIGHT_ALERT if int(_t / blink_period) % 2 == 0 else LIGHT_OFF
		State.COOLDOWN:
			_light.modulate = LIGHT_COOL
	_flash.queue_redraw()


func _draw_flash() -> void:
	if _flash_t <= 0.0:
		return
	var m := muzzle_global() - global_position
	var dir := Vector2.RIGHT.rotated(_aim_angle)
	var cell := Vector2(_a, _a)
	for i in 4:
		var p: Vector2 = ((m + dir * _a * i) / _a).floor() * _a
		_flash.draw_rect(Rect2(p, cell), Color("#fff6d0") if i < 2 else Color("#ffc040"))
	var side := dir.orthogonal()
	for s in [-1.0, 1.0]:
		var p: Vector2 = ((m + dir * _a + side * s * _a * 1.5) / _a).floor() * _a
		_flash.draw_rect(Rect2(p, cell), Color("#ffc040"))
