extends CanvasLayer

# F1 / Back: debug readout. While open, up/down picks a setting row (vibration, fog on/off, fog
# density 0.5..1.5, fog quality 0..2, fog opacity 0.5..1.5) and the d-pad left/right (Q/R) changes it.

const Feedback := preload("res://game/feedback.gd")
const HAPTIC_LEVELS := [0.0, 0.25, 0.5, 0.75, 1.0]

var player: CharacterBody2D
# While this (the sound board) is visible the HUD ignores the d-pad and F1.
var input_blocker: Object
var _label: Label
var _level := 4
var _row := 0
const ROWS := 5


func _ready() -> void:
	layer = 10
	# Starts closed: while open, the d-pad left/right adjusts the vibration instead of the weapon.
	visible = false
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.position = Vector2(12, 12)
	add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override(&"font_size", 14)
	_label.add_theme_color_override(&"font_color", Color("#e8e0c8"))
	panel.add_child(_label)
	var h := Feedback.haptics()
	if h:
		_level = HAPTIC_LEVELS.find(snappedf(float(h.intensity), 0.25)) if h.enabled else 0
		if _level < 0:
			_level = 4


func _process(_delta: float) -> void:
	var blocked: bool = input_blocker != null and input_blocker.visible
	if not blocked and Input.is_action_just_pressed(&"toggle_debug"):
		visible = not visible
	if not visible or player == null:
		return
	if blocked:
		pass
	elif Input.is_action_just_pressed(&"move_up"):
		_row = posmod(_row - 1, ROWS)
	elif Input.is_action_just_pressed(&"move_down"):
		_row = posmod(_row + 1, ROWS)
	elif Input.is_action_just_pressed(&"weapon_prev"):
		_adjust(-1)
	elif Input.is_action_just_pressed(&"weapon_next"):
		_adjust(1)
	var p := player
	var lines := PackedStringArray([
		"Estado: %s" % p.state_name(),
		"Velocidade: %4d  (alvo %d)" % [roundi(absf(p.velocity.x)), roundi(p.target_speed)],
		"Vel. vertical: %d" % roundi(p.velocity.y),
		"Ação: %s" % (p.rig_action() if not p.rig_action().is_empty() else "-"),
		"Facing: %s   Chão: %s (%s)" % ["dir" if p.facing > 0 else "esq", "sim" if p.is_on_floor() else "não", p.surface],
		"Invulnerável: %s   Parede agarrável: %s   Pulos no ar: %d" % ["SIM" if p.invulnerable else "não", "SIM" if (p.wall_grab_hint or p.wall_sliding) else "não", p._air_jumps],
		"Analógico: %.2f" % p.input_axis,
		"Rig: %s   FPS: %d" % ["provisório" if p.uses_stub else "Adventurer", Engine.get_frames_per_second()],
		_mark(0) + _haptics_line(),
		_mark(1) + _fog_line(),
		_mark(2) + "Densidade da neblina: %.1f" % (_fog().density_scale if _fog() else 0.0),
		_mark(3) + "Qualidade da neblina: %d" % (_fog().quality if _fog() else 0),
		_mark(4) + "Opacidade da neblina: %.1f" % (_fog().opacity_scale if _fog() else 0.0),
		"Cima/baixo escolhe · direcional ◀ ▶ ajusta",
		"F1 esconde   F2 mesa de sons",
	])
	_label.text = "\n".join(lines)


func _mark(row: int) -> String:
	return "> " if row == _row else "  "


func _fog() -> Node:
	return get_node_or_null(^"/root/Fog")


func _fog_line() -> String:
	var f := _fog()
	if f == null:
		return "Neblina: indisponível"
	return "Neblina: %s   FPS sim: %s" % ["ligada" if f.enabled else "desligada", str(f.stats().get("cpu_usec", "-")) if f.has_method(&"stats") else "-"]


func _adjust(step: int) -> void:
	var f := _fog()
	match _row:
		0:
			_set_haptics(_level + step)
		1:
			if f:
				f.enabled = not f.enabled
		2:
			if f:
				f.density_scale = clampf(snappedf(f.density_scale + 0.1 * step, 0.1), 0.5, 1.5)
		3:
			if f:
				f.quality = clampi(f.quality + step, 0, 2)
		4:
			if f:
				f.opacity_scale = clampf(snappedf(f.opacity_scale + 0.1 * step, 0.1), 0.5, 1.5)


func _haptics_line() -> String:
	if Feedback.haptics() == null:
		return "Vibração: indisponível"
	var value := "desligada" if _level == 0 else "%d%%" % roundi(HAPTIC_LEVELS[_level] * 100.0)
	return "Vibração: %s   (direcional ◀ ▶)" % value


func _set_haptics(level: int) -> void:
	_level = clampi(level, 0, HAPTIC_LEVELS.size() - 1)
	var h := Feedback.haptics()
	if h == null:
		return
	h.enabled = _level > 0
	if _level > 0:
		h.intensity = HAPTIC_LEVELS[_level]
	if h.enabled:
		Feedback.haptic(&"roll", 0.6)


func is_open() -> bool:
	return visible
