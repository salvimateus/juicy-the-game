extends Node2D

# Placeholder rig for the interactables test: the Adventurer calls the interactables use, drawn
# as blocky postures (standing, seated, lying with Z's, hurt flash).

const PixelFont := preload("res://game/interactables/pixel_font.gd")

signal action_finished(id: StringName)

const DURATIONS := {
	&"sit_down": 0.45, &"stand_up": 0.4, &"lie_down": 0.7, &"get_up": 0.6,
	&"hurt": 0.45, &"shot_hit": 0.6,
}
const LOOPS: Array[StringName] = [&"sitting", &"sleeping"]
const CHAINS := {&"sit_down": &"sitting", &"lie_down": &"sleeping"}
const A := 6.0
const OUTLINE := Color("#141013")
const SKIN := Color("#e0b090")
const HAIR := Color("#5a3424")
const SHIRT := Color("#3a6c80")
const PANTS := Color("#34303c")
const BLOOD := Color("#b0202a")

var facing := 1:
	set(v):
		facing = v
		queue_redraw()
var action_params := {}
var _action: StringName = &""
var _t := 0.0
var _flash := 0.0


func play_action(id: StringName) -> bool:
	if not DURATIONS.has(id) and id not in LOOPS:
		return false
	_action = id
	_t = 0.0
	if id == &"hurt" or id == &"shot_hit":
		_flash = 0.3
	queue_redraw()
	return true


func current_action() -> StringName:
	return _action


func is_action_playing() -> bool:
	return _action != &""


func set_hit_direction(direction: Vector2) -> void:
	action_params[&"hit_direction"] = direction


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	if DURATIONS.has(_action) and _t >= DURATIONS[_action]:
		var done := _action
		_action = CHAINS.get(done, &"")
		_t = 0.0
		action_finished.emit(done)
	queue_redraw()


func _box(x: float, y: float, w: float, h: float, c: Color) -> void:
	var r := Rect2(x, y, w, h).abs()
	draw_rect(r.grow(A), OUTLINE)
	draw_rect(r, c)


func _fx(x: float) -> float:
	return x * facing


func _draw() -> void:
	var rest: float = action_params.get(&"rest_height", 90.0)
	match _action:
		&"sit_down", &"sitting":
			_draw_seated(rest)
		&"lie_down", &"sleeping":
			_draw_lying(rest)
		_:
			_draw_standing()
	if _flash > 0.0:
		draw_rect(Rect2(-60, -432, 120, 432), Color(1, 0.2, 0.2, 0.45))
	if _action == &"shot_hit":
		for p in [Vector2(6, -300), Vector2(18, -306), Vector2(-6, -288), Vector2(24, -282)]:
			draw_rect(Rect2(Vector2(_fx(p.x), p.y), Vector2(A, A)), BLOOD)


func _head(cx: float, top: float) -> void:
	_box(cx - 36, top, 72, 84, SKIN)
	draw_rect(Rect2(cx - 36, top, 72, 24), HAIR)
	draw_rect(Rect2(cx + _fx(18) - 3, top + 42, A, 12), OUTLINE)


func _draw_standing() -> void:
	_box(-30, -174, 60, 174, PANTS)
	_box(-42, -336, 84, 162, SHIRT)
	_head(0, -426)


func _draw_seated(h: float) -> void:
	_box(_fx(-18) - 30, -h - 156 - 36, 60, 156, SHIRT)
	_box(_fx(-48), -h - 36, _fx(150), 36, PANTS)
	_box(_fx(96), -h - 36, _fx(36), h + 36, PANTS)
	_head(_fx(-18), -h - 36 - 156 - 84)


func _draw_lying(h: float) -> void:
	_box(_fx(-138), -h - 60, _fx(150), 60, SHIRT)
	_box(_fx(12), -h - 54, _fx(186), 48, PANTS)
	_box(_fx(-222), -h - 72, _fx(78), 66, SKIN)
	if _action == &"sleeping":
		for i in 3:
			var s := 1.0 + i * 0.5
			var at := Vector2(_fx(-180) + 30 * i * facing, -h - 150 - 54 * i - fmod(_t * 30.0, 18.0))
			for p in PixelFont.glyph("Z").pixels:
				draw_rect(Rect2(at + Vector2(p) * A * s / 1.5, Vector2(A, A)), Color("#e8e0f8"))
