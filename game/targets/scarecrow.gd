class_name Scarecrow
extends Node2D

# Straw training dummy on a stake (art: res://game/targets/art/scarecrow.png). The origin is the
# ground point at the foot of the stake. The art is cut in three parts: the stake with the grass tufts
# stays still, the body sways on a damped spring around the top of the visible stake and the head
# nods on its own spring around the neck. Body and head show pre-rotated frames (no mixels); cuts and
# blood stay on top of them as art-pixel marks rotated with the part. Hits come through the Hurtbox
# child (group `damageable`) or take_hit directly.

signal hit(point: Vector2, damage: float)
signal died
signal healed

const ART := preload("res://game/targets/art/scarecrow.png")
const PixelRotate := preload("res://game/targets/pixel_rotate.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const FLASH_SHADER := preload("res://game/targets/flash.gdshader")
const RESET_BUTTON := "res://game/interactables/reset_button.tscn"

# Art-pixel layout of scarecrow.png.
const ORIGIN := Vector2(34, 83)
const BODY_PIVOT := Vector2(34, 70)
const HEAD_PIVOT := Vector2(33, 31)
const STAKE_ROW := 70
const HEAD_ROWS := 30
const NECK_ROWS := 32
const NECK_COLS := Vector2i(12, 55)
const OUTLINE := Color("#141013")

const BODY_STEP := 2.0 * PI / 180.0
const BODY_MAX := 24.0 * PI / 180.0
const HEAD_STEP := 5.0 * PI / 180.0
const HEAD_MAX := 75.0 * PI / 180.0

const CUT := Color("#2a1016")
const STRAW_CUT := Color("#e2a843")
const BLOOD := [Color("#5e0b0e"), Color("#8c1418"), Color("#b81e22")]
const BAR_BACK := Color("#2c242a")
const BAR_LAG := Color("#f4ece4")
const BAR_COLORS := [Color("#b81e22"), Color("#d8a038"), Color("#6e9448")]
const MAX_STUCK := 8
const MAX_MARKS := 900

@export var max_health := 100.0
@export_group("Sway")
@export var stiffness := 95.0
@export var damping := 4.2
@export var sway_per_damage := 0.07
@export var head_stiffness := 70.0
@export var head_damping := 5.0
@export var head_follow := 0.8
@export var head_kick := 0.09
@export var dead_tilt := 12.0
@export var dead_head := 28.0
@export_group("Feedback")
@export var hitstop := 0.06
@export var flash_time := 0.08
@export var bar_show_time := 2.6
# Blood and straw amounts per hit kind (multipliers of TargetFx counts).
@export var blood_by_kind := {&"slash": 1.0, &"bullet": 0.9, &"arrow": 0.75, &"punch": 0.3, &"kick": 0.4}
@export var straw_by_kind := {&"slash": 0.8, &"bullet": 0.6, &"arrow": 0.5, &"punch": 1.0, &"kick": 1.3}
@export_group("Reset")
@export var button_offset := Vector2(360, 0)
@export var button_prompt := "Curar o espantalho"

var health := 100.0
var dead := false

static var _parts: Dictionary = {}

var _a := 6.0
var _body: Sprite2D
var _head: Sprite2D
var _stake: Sprite2D
var _body_marks: Node2D
var _head_marks: Node2D
var _bar: Node2D
var _fx: TargetFx
var _hurtbox: Hurtbox
var _button: Node
var _material: ShaderMaterial

var _theta := 0.0
var _omega := 0.0
var _phi := 0.0
var _phi_v := 0.0
var _dead_side := 1.0
var _hold := 0.0
var _flash := 0.0
var _bar_t := 0.0
var _lag := 100.0
var _lag_wait := 0.0
var _bar_drawn := Vector2i(-1, -1)
var _kb := -1
var _kh := -1
var _neck := Vector2.ZERO

# Marks: part image index -> color.
var _marks_body := {}
var _marks_head := {}
# Stuck projectiles: node, part (0 body, 1 head), tip in part art coords, angle relative to the part.
var _stuck: Array[Node2D] = []
var _stuck_part := PackedByteArray()
var _stuck_src := PackedVector2Array()
var _stuck_rel := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


static func parts() -> Dictionary:
	if _parts.is_empty():
		var img := PixelRotate.load_art(ART)
		var w := img.get_width()
		var body := Image.create(w, STAKE_ROW, false, Image.FORMAT_RGBA8)
		var head := Image.create(w, NECK_ROWS, false, Image.FORMAT_RGBA8)
		for y in STAKE_ROW:
			for x in w:
				var c := img.get_pixel(x, y)
				if _is_head(x, y):
					head.set_pixel(x, y, c)
				else:
					body.set_pixel(x, y, c)
		var stake := img.get_region(Rect2i(0, STAKE_ROW, w, img.get_height() - STAKE_ROW))
		_parts = {
			body_img = body,
			head_img = head,
			stake = ImageTexture.create_from_image(stake),
			body = PixelRotate.build(body, BODY_PIVOT, PixelRotate.angle_range(-BODY_MAX, BODY_MAX, BODY_STEP)),
			head = PixelRotate.build(head, HEAD_PIVOT, PixelRotate.angle_range(-HEAD_MAX, HEAD_MAX, HEAD_STEP)),
		}
	return _parts


static func _is_head(x: int, y: int) -> bool:
	return y <= HEAD_ROWS - 1 or (y < NECK_ROWS and x >= NECK_COLS.x and x <= NECK_COLS.y)


func _ready() -> void:
	_a = float(GameScale.art_pixel())
	global_position = global_position.snapped(Vector2(_a, _a))
	_rng.randomize()
	health = max_health
	_lag = max_health
	var p := parts()
	_material = ShaderMaterial.new()
	_material.shader = FLASH_SHADER
	_stake = _art_sprite(p.stake, "Stake")
	_stake.position = (Vector2(0, STAKE_ROW) - ORIGIN) * _a
	_body = _art_sprite(p.body.texture, "Body")
	_body_marks = _mark_layer("BodyMarks", _draw_body_marks)
	_head = _art_sprite(p.head.texture, "Head")
	_head_marks = _mark_layer("HeadMarks", _draw_head_marks)
	_build_bar()
	_build_hurtbox()
	_fx = TargetFx.new()
	_fx.name = "Fx"
	add_child(_fx)
	_fx.floor_y = global_position.y
	_build_button()
	_apply_pose(true)


func _art_sprite(texture: Texture2D, node_name: String) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = texture
	s.centered = false
	s.scale = Vector2(_a, _a)
	s.material = _material
	s.region_enabled = node_name != "Stake"
	add_child(s)
	return s


func _mark_layer(node_name: String, painter: Callable) -> Node2D:
	var n := Node2D.new()
	n.name = node_name
	n.draw.connect(painter)
	add_child(n)
	return n


func _build_hurtbox() -> void:
	_hurtbox = Hurtbox.new()
	_hurtbox.name = "Hurtbox"
	_hurtbox.target = self
	# Torso, head and hat in one box, the outstretched arms in another (art px of scarecrow.png).
	for r in [Rect2(12, 2, 42, 66), Rect2(0, 30, 65, 18)]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size * _a
		shape.shape = rect
		shape.position = (r.position + r.size * 0.5 - ORIGIN) * _a
		_hurtbox.add_child(shape)
	add_child(_hurtbox)


func _build_button() -> void:
	if not ResourceLoader.exists(RESET_BUTTON):
		return
	_button = (load(RESET_BUTTON) as PackedScene).instantiate()
	_button.name = "HealButton"
	_button.set(&"prompt", button_prompt)
	add_child(_button)
	_button.position = button_offset
	if _button.has_signal(&"pressed"):
		_button.connect(&"pressed", heal)


func _build_bar() -> void:
	_bar = Node2D.new()
	_bar.name = "HealthBar"
	_bar.position = (Vector2(ORIGIN.x - 8, -6) - ORIGIN) * _a
	_bar.z_index = 4
	_bar.visible = false
	_bar.draw.connect(_draw_bar)
	add_child(_bar)


# --------------------------------------------------------------------------- combat contract

func take_hit(point: Vector2, direction: Vector2, damage: float, kind: StringName) -> void:
	var s := clampf(damage / 30.0, 0.15, 1.3)
	var side := signf(direction.x) if absf(direction.x) > 0.05 else (1.0 if point.x >= global_position.x else -1.0)
	var height := clampf((global_position.y + (BODY_PIVOT.y - ORIGIN.y) * _a - point.y) / 300.0, 0.25, 1.3)
	_omega += side * sway_per_damage * damage * height
	_phi_v += side * head_kick * damage
	_hold = hitstop
	_flash = flash_time
	_material.set_shader_parameter(&"flash", 1.0)
	if not dead:
		health = maxf(0.0, health - damage)
		_lag_wait = 0.35
	_bar_t = bar_show_time
	_bar.visible = true
	_bar.queue_redraw()
	var blood: float = blood_by_kind.get(kind, 0.5)
	var straw: float = straw_by_kind.get(kind, 0.6)
	var ground := global_position.y
	if blood > 0.0:
		_fx.spray_blood(point, direction, blood * clampf(0.5 + s * 0.6, 0.5, 1.4), ground)
		if kind != &"punch" and kind != &"kick":
			_fx.drip(point + Vector2(0, 12), -1, ground)
	_fx.spray_straw(point, direction, straw * clampf(0.5 + s * 0.6, 0.5, 1.4), ground)
	_mark(point, direction, kind)
	Feedback.sfx(&"scarecrow_hit", point, s, &"slash" if kind == &"slash" else &"blunt")
	if blood >= 0.5:
		Feedback.sfx(&"blood_splat", point, s * blood)
	Feedback.haptic(&"scarecrow_hit", s)
	hit.emit(point, damage)
	if not dead and health <= 0.0:
		dead = true
		_dead_side = side
		_fx.spray_straw(point, Vector2(side, -0.4), 1.6, ground)
		died.emit()
	set_process(true)


# Keeps a stuck projectile riding the sway; returns false when the point misses the art.
func attach_projectile(projectile: Node2D, point: Vector2) -> bool:
	var loc := _locate(point, 2)
	if loc.x < 0:
		return false
	if _stuck.size() >= MAX_STUCK:
		var old := _stuck[0]
		_remove_stuck(0)
		if is_instance_valid(old) and old.has_method(&"vanish"):
			old.vanish()
	var part := int(loc.x)
	var src := _to_part(point, part)
	_stuck.append(projectile)
	_stuck_part.append(part)
	_stuck_src.append(src)
	var base := _part_angle(part)
	var ang: float = projectile.get(&"_angle") if &"_angle" in projectile else 0.0
	_stuck_rel.append(ang - base)
	projectile.tree_exiting.connect(_on_stuck_gone.bind(projectile), CONNECT_ONE_SHOT)
	_place_stuck(_stuck.size() - 1)
	return true


# Back to full health: straight, clean (no cuts or blood on the body), stuck arrows gone.
func heal() -> void:
	health = max_health
	_lag = max_health
	dead = false
	_marks_body.clear()
	_marks_head.clear()
	_body_marks.queue_redraw()
	_head_marks.queue_redraw()
	for i in range(_stuck.size() - 1, -1, -1):
		var n := _stuck[i]
		_remove_stuck(i)
		if is_instance_valid(n) and n.has_method(&"vanish"):
			n.vanish()
	_flash = flash_time * 2.0
	_material.set_shader_parameter(&"flash", 1.0)
	_fx.spray_straw(global_position + Vector2(0, (20 - ORIGIN.y) * _a), Vector2.UP, 0.8)
	_bar_t = 1.2
	_bar.visible = true
	_bar.queue_redraw()
	healed.emit()
	set_process(true)


func get_health_ratio() -> float:
	return health / max_health


# --------------------------------------------------------------------------- motion

func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	if _flash > 0.0:
		_flash -= delta
		_material.set_shader_parameter(&"flash", 1.0 if _flash > 0.0 else 0.0)
	if _hold > 0.0:
		_hold -= delta
	else:
		_integrate(delta)
	_update_bar(delta)
	_apply_pose(false)


func _integrate(delta: float) -> void:
	var steps := maxi(1, ceili(delta * 240.0))
	var dt := delta / steps
	var tb := deg_to_rad(dead_tilt) * _dead_side if dead else 0.0
	var th := deg_to_rad(dead_head) * _dead_side if dead else 0.0
	for i in steps:
		var acc := -stiffness * (_theta - tb) - damping * _omega
		_omega += acc * dt
		_theta += _omega * dt
		if absf(_theta) > BODY_MAX:
			_theta = clampf(_theta, -BODY_MAX, BODY_MAX)
			_omega *= -0.3
		var acc_h := -head_stiffness * (_phi - th) - head_damping * _phi_v - acc * head_follow
		_phi_v += acc_h * dt
		_phi += _phi_v * dt
		_phi = clampf(_phi, -HEAD_MAX + BODY_MAX, HEAD_MAX - BODY_MAX)


func _update_bar(delta: float) -> void:
	if _lag_wait > 0.0:
		_lag_wait -= delta
	elif _lag > health:
		_lag = maxf(health, _lag - max_health * 0.8 * delta)
	if _bar_t > 0.0:
		_bar_t -= delta
		if _bar_t <= 0.0 and _lag <= health:
			_bar.visible = false
	var key := Vector2i(roundi(health / max_health * 14.0), roundi(_lag / max_health * 14.0))
	if key != _bar_drawn:
		_bar_drawn = key
		_bar.queue_redraw()


func _body_index(theta: float) -> int:
	return clampi(roundi((theta + BODY_MAX) / BODY_STEP), 0, roundi(2.0 * BODY_MAX / BODY_STEP))


func _head_index(theta: float) -> int:
	return clampi(roundi((theta + HEAD_MAX) / HEAD_STEP), 0, roundi(2.0 * HEAD_MAX / HEAD_STEP))


func _body_angle() -> float:
	return -BODY_MAX + _kb * BODY_STEP


func _head_angle() -> float:
	return -HEAD_MAX + _kh * HEAD_STEP


func _part_angle(part: int) -> float:
	return _head_angle() if part == 1 else _body_angle()


func _apply_pose(force: bool) -> void:
	var kb := _body_index(_theta)
	var kh := _head_index(_body_angle_of(kb) + _phi)
	if not force and kb == _kb and kh == _kh:
		return
	var p := parts()
	var body_changed := kb != _kb
	_kb = kb
	_kh = kh
	var pivot := (BODY_PIVOT - ORIGIN) * _a
	if body_changed or force:
		_body.region_rect = p.body.rects[kb]
		_body.position = pivot + p.body.offsets[kb] * _a
		_body_marks.position = pivot
		_body_marks.queue_redraw()
	var ba := _body_angle()
	var d := (HEAD_PIVOT - BODY_PIVOT).rotated(ba)
	_neck = BODY_PIVOT - ORIGIN + Vector2(roundf(d.x), roundf(d.y))
	_head.region_rect = p.head.rects[kh]
	_head.position = _neck * _a + p.head.offsets[kh] * _a
	_head_marks.position = _neck * _a
	_head_marks.queue_redraw()
	for i in _stuck.size():
		_place_stuck(i)


func _body_angle_of(kb: int) -> float:
	return -BODY_MAX + kb * BODY_STEP


# --------------------------------------------------------------------------- marks

# Part (0 body, 1 head) and pixel of the art under a global point, searching `radius` art px around
# it; x < 0 when nothing opaque is there.
func _locate(point: Vector2, radius: int) -> Vector2i:
	var p := parts()
	for part in [1, 0]:
		var img: Image = p.head_img if part == 1 else p.body_img
		var src := _to_part(point, part)
		var base := Vector2i(floori(src.x), floori(src.y))
		for r in radius + 1:
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dy)) != r:
						continue
					var q := base + Vector2i(dx, dy)
					if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() and img.get_pixelv(q).a > 0.0:
						return Vector2i(part, q.y * img.get_width() + q.x)
	return Vector2i(-1, -1)


# Global point to art coords of a part image (inverse of the current frame rotation).
func _to_part(point: Vector2, part: int) -> Vector2:
	var local := to_local(point) / _a
	if part == 1:
		return HEAD_PIVOT + (local - _neck).rotated(-_head_angle())
	return BODY_PIVOT + (local - (BODY_PIVOT - ORIGIN)).rotated(-_body_angle())


func _mark(point: Vector2, direction: Vector2, kind: StringName) -> void:
	var loc := _locate(point, 3)
	if loc.x < 0:
		return
	var part := loc.x
	var w: int = (parts().head_img if part == 1 else parts().body_img).get_width()
	var c := Vector2i(loc.y % w, loc.y / w)
	match kind:
		&"slash":
			# A cut across the swing: dark core, wet red lip under it and a drip.
			var slope := -1 if direction.y < -0.2 or (direction.y <= 0.2 and _rng.randf() < 0.5) else 1
			var shallow := _rng.randf() < 0.5
			var length := _rng.randi_range(5, 7)
			# Straw shows through the torn cloth between a dark upper lip and a bloody lower one.
			for i in length:
				var dx := i - length / 2
				var dy := (dx / 2 if shallow else dx) * slope
				_paint(part, c + Vector2i(dx, dy - 1), CUT)
				_paint(part, c + Vector2i(dx, dy), STRAW_CUT if i > 0 and i < length - 1 else CUT)
				_paint(part, c + Vector2i(dx, dy + 1), BLOOD[2] if i % 2 == 0 else BLOOD[1])
			_paint(part, c + Vector2i(0, 2), BLOOD[1])
			_paint(part, c + Vector2i(0, 3), BLOOD[0])
		&"bullet", &"arrow":
			_paint(part, c, CUT)
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]:
				_paint(part, c + o, BLOOD[1])
			_paint(part, c + Vector2i(0, 2), BLOOD[0])
	var spatter := 3 if kind == &"slash" else (2 if kind != &"punch" else 1)
	for i in spatter:
		_paint(part, c + Vector2i(_rng.randi_range(-3, 3), _rng.randi_range(-2, 3)), BLOOD[_rng.randi_range(1, 2)])
	(_head_marks if part == 1 else _body_marks).queue_redraw()


func _paint(part: int, q: Vector2i, color: Color) -> void:
	var img: Image = parts().head_img if part == 1 else parts().body_img
	if q.x < 0 or q.y < 0 or q.x >= img.get_width() or q.y >= img.get_height():
		return
	var base := img.get_pixelv(q)
	if base.a == 0.0 or base.is_equal_approx(OUTLINE):
		return
	var marks := _marks_head if part == 1 else _marks_body
	if marks.size() >= MAX_MARKS:
		return
	marks[q.y * img.get_width() + q.x] = color


func _draw_body_marks() -> void:
	_draw_marks(_body_marks, _marks_body, parts().body_img.get_width(), BODY_PIVOT, _body_angle())


func _draw_head_marks() -> void:
	_draw_marks(_head_marks, _marks_head, parts().head_img.get_width(), HEAD_PIVOT, _head_angle())


func _draw_marks(canvas: Node2D, marks: Dictionary, w: int, pivot: Vector2, angle: float) -> void:
	var cs := cos(angle)
	var sn := sin(angle)
	var size := Vector2(_a, _a)
	for idx in marks:
		var dx: float = idx % w + 0.5 - pivot.x
		var dy: float = idx / w + 0.5 - pivot.y
		var cell := Vector2(floorf(dx * cs - dy * sn), floorf(dx * sn + dy * cs))
		canvas.draw_rect(Rect2(cell * _a, size), marks[idx])


func _draw_bar() -> void:
	var a := _a
	var fill := roundi(health / max_health * 14.0)
	var lag := roundi(_lag / max_health * 14.0)
	_bar.draw_rect(Rect2(0, 0, 16 * a, 4 * a), OUTLINE)
	_bar.draw_rect(Rect2(a, a, 14 * a, 2 * a), BAR_BACK)
	if lag > fill:
		_bar.draw_rect(Rect2(a + fill * a, a, (lag - fill) * a, 2 * a), BAR_LAG)
	if fill > 0:
		var ratio := health / max_health
		var color: Color = BAR_COLORS[2] if ratio > 0.6 else (BAR_COLORS[1] if ratio > 0.3 else BAR_COLORS[0])
		_bar.draw_rect(Rect2(a, a, fill * a, 2 * a), color)
		_bar.draw_rect(Rect2(a, a, fill * a, a), color.lightened(0.25))


# --------------------------------------------------------------------------- stuck projectiles

func _place_stuck(i: int) -> void:
	var n := _stuck[i]
	if not is_instance_valid(n):
		return
	var part := _stuck_part[i]
	var ang := _part_angle(part)
	var pivot := HEAD_PIVOT if part == 1 else BODY_PIVOT
	var at := _neck if part == 1 else BODY_PIVOT - ORIGIN
	var tip := at + (_stuck_src[i] - pivot).rotated(ang)
	n.set_carried_pose(to_global(tip * _a), _stuck_rel[i] + ang)


func _remove_stuck(i: int) -> void:
	var n := _stuck[i]
	if is_instance_valid(n) and n.tree_exiting.is_connected(_on_stuck_gone):
		n.tree_exiting.disconnect(_on_stuck_gone)
	_stuck.remove_at(i)
	_stuck_part.remove_at(i)
	_stuck_src.remove_at(i)
	_stuck_rel.remove_at(i)


func _on_stuck_gone(n: Node2D) -> void:
	var i := _stuck.find(n)
	if i >= 0:
		_remove_stuck(i)
