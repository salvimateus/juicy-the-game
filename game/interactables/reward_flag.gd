class_name RewardFlag
extends Node2D

# Reward flag on top of a climb: a wooden pole with a waving cloth. When the player touches it,
# the flag is captured once: it pops up the pole in steps and turns red with a gold star,
# confetti and sparkles burst, "Topo alcançado!" rises and fades, and the achievement sound and
# rumble play. Afterwards it keeps waving in the captured state. Not an interactable (no prompt).
# Origin: foot of the pole on the floor.

const Art := preload("res://game/interactables/interactables_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")

signal captured

const FRAME_TIME := 0.11
# Flag top-left row (art px, relative to the origin) lowered and raised.
const LOWERED_TOP := -32
const RAISED_TOP := -52
# Rise in steps: art-pixel offsets from LOWERED_TOP, each held RISE_STEP seconds (overshoot at the end).
const RISE_STEPS := [0, -3, -7, -11, -15, -18, -20, -22, -21]
const RISE_STEP := 0.045
const TEXT := "Topo alcançado!"
const TEXT_TIME := 1.6
const TEXT_RISE := 14
const CONFETTI_COLORS := [Color("#d84a3c"), Color("#e8b030"), Color("#fbe07a"), Color("#58c860"), Color("#4a90d8"), Color("#f2e8d0")]

@export var touch_size := Vector2(150, 330)

var is_captured := false
var _a := 6.0
var _flag: Sprite2D
var _text: Sprite2D
var _fx: Node2D
var _t := 0.0
var _rise_t := -1.0
var _text_t := -1.0
var _flash := 0.0
var _bits: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_a = GameScale.art_pixel()
	_rng.seed = 7
	var pole := _sprite(Art.flag_pole(), Vector2(Art.POLE_ORIGIN))
	pole.name = "Pole"
	add_child(pole)
	_flag = _sprite(Art.flag_frame(0, false), Vector2.ZERO)
	_flag.name = "Flag"
	add_child(_flag)
	_place_flag(LOWERED_TOP)
	_fx = Node2D.new()
	_fx.name = "Burst"
	_fx.z_index = 5
	_fx.draw.connect(_draw_fx)
	add_child(_fx)
	_text = _sprite(null, Vector2.ZERO)
	_text.name = "Text"
	_text.z_index = 6
	_text.visible = false
	add_child(_text)
	var area := Area2D.new()
	area.name = "Touch"
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitorable = false
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = touch_size
	shape.shape = rect
	shape.position = Vector2(0, -touch_size.y / 2.0)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)


func _sprite(tex: Texture2D, top_left_art: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = top_left_art
	s.scale = Vector2.ONE * _a
	return s


func _place_flag(top_row: int) -> void:
	# Hoist column overlaps the pole's right edge.
	_flag.position = Vector2(2, top_row) * _a


func _on_body_entered(body: Node) -> void:
	if body.is_in_group(&"player"):
		capture()


# Captures the flag (once); callable from code too.
func capture() -> void:
	if is_captured:
		return
	is_captured = true
	_rise_t = 0.0
	_text_t = 0.0
	_flash = 0.08
	_spawn_burst()
	var info := Art.outlined_text(TEXT, Color("#fbe07a"))
	_text.texture = info.texture
	_text.offset = Vector2(-info.size.x / 2, 0)
	_text.visible = true
	Feedback.sfx(&"achievement", global_position + Vector2(0, RAISED_TOP * _a))
	Feedback.haptic(&"achievement", 1.0)
	captured.emit()


func _spawn_burst() -> void:
	var top := Vector2(12, RAISED_TOP + 6) * _a
	for i in 34:
		var star := i % 5 == 0
		var dir := Vector2.from_angle(_rng.randf_range(-PI * 0.95, -PI * 0.05))
		_bits.append({
			p = top + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-20, 20)),
			v = dir * _rng.randf_range(420.0, 980.0),
			c = CONFETTI_COLORS[i % CONFETTI_COLORS.size()],
			star = star,
			life = _rng.randf_range(0.9, 1.4),
			age = 0.0,
			spin = _rng.randi_range(0, 3),
		})


func _process(delta: float) -> void:
	_t += delta
	var frame := int(_t / FRAME_TIME) % Art.FLAG_FRAMES
	var red := is_captured and _flash <= 0.0
	_flag.texture = Art.flag_frame(frame, red)
	_flag.modulate = Color(3, 3, 3) if _flash > 0.0 else Color.WHITE
	_flash = maxf(0.0, _flash - delta)
	if _rise_t >= 0.0:
		_rise_t += delta
		var i := mini(int(_rise_t / RISE_STEP), RISE_STEPS.size() - 1)
		_place_flag(LOWERED_TOP + RISE_STEPS[i])
		if i == RISE_STEPS.size() - 1:
			_rise_t = -1.0
	if _text_t >= 0.0:
		_text_t += delta
		var k := _text_t / TEXT_TIME
		var rise := floorf(minf(k * 2.0, 1.0) * TEXT_RISE)
		_text.position = Vector2(12 * _a, (RAISED_TOP - 16 - rise) * _a)
		_text.modulate.a = 1.0 if k < 0.65 else clampf((1.0 - k) / 0.35, 0.0, 1.0)
		if k >= 1.0:
			_text_t = -1.0
			_text.visible = false
	if not _bits.is_empty():
		for b in _bits:
			b.age += delta
			b.v.y += 1500.0 * delta
			b.v.x *= 1.0 - 1.5 * delta
			b.p += b.v * delta
		_bits = _bits.filter(func(b): return b.age < b.life)
		_fx.queue_redraw()
	elif _fx.visible:
		_fx.queue_redraw()


func _draw_fx() -> void:
	var cell := Vector2(_a, _a)
	for b in _bits:
		var q: Vector2 = (b.p / _a).floor() * _a
		var c: Color = b.c
		if b.age > b.life * 0.7:
			c.a = 1.0 - (b.age - b.life * 0.7) / (b.life * 0.3)
		if b.star:
			for d in [Vector2(0, 0), Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				_fx.draw_rect(Rect2(q + d * _a, cell), Color("#fff6d0", c.a) if d == Vector2.ZERO else c)
		else:
			var flip := int(b.age * 12.0 + b.spin) % 2 == 0
			_fx.draw_rect(Rect2(q, Vector2(_a * (2 if flip else 1), _a * (1 if flip else 2))), c)
