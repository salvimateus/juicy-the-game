extends RefCounted

# One round touch button: squash on press, springy pop on release, ripple, optional glow. Dark
# translucent face, rim in the pad colour of its action, the pad letter (A, B, X, Y, LT, RT...) in
# the pixel font, so every hint written for the gamepad also reads on the touch layout.
# Pure state + drawing; TouchControls owns the input routing and calls draw() on its canvas.

const EndingArt := preload("res://game/ending/ending_art.gd")

const FACE := Color(0.06, 0.05, 0.09)
const OUTLINE := Color(0.03, 0.02, 0.05)
const SPRING_K := 620.0
const SPRING_DAMP := 17.0
const HIT_SLOP := 1.18
const RIPPLE_TIME := 0.42
const IDLE_ALPHA := 0.6
const PRESSED_ALPHA := 0.85
const FILL_ALPHA := 0.6
const DIM_ALPHA := 0.28
const LIT_ALPHA := 0.9
const PULSE_HZ := 1.6

var kind: StringName
var center := Vector2.ZERO
var radius := 40.0
var accent := Color.WHITE
var shown := true
# Interact style: dim until lit_target, then a pulsing glow in the accent colour.
var dim_when_unlit := false
var lit_target := false
var lit := 0.0
# Optional custom glyph drawn instead of the label: &"pause", &"restart", &"aim".
var glyph: StringName = &""
var pressed := false
var appear := 1.0

var _label: Texture2D
var _press := 0.0
var _s := 1.0
var _v := 0.0
var _ripples: Array[Vector3] = []
var _clock := 0.0
var _lit_pop := 0.0


func _init(p_kind: StringName, label := "", p_accent := Color.WHITE) -> void:
	kind = p_kind
	accent = p_accent
	set_label(label)


func set_label(text: String) -> void:
	if text.is_empty():
		_label = null
		return
	var t := EndingArt.text_image(text, Color.WHITE, Color("#e8e0d8"))
	_label = ImageTexture.create_from_image(t.image)


func hit(p: Vector2) -> bool:
	return shown and appear > 0.5 and p.distance_to(center) <= radius * HIT_SLOP


func press(p: Vector2) -> void:
	pressed = true
	_v -= 6.0
	_ripples.append(Vector3(p.x - center.x, p.y - center.y, 0.0))


func release() -> void:
	if not pressed:
		return
	pressed = false
	_v += 9.0


func update(delta: float) -> void:
	_clock += delta
	var target := 0.88 if pressed else 1.0
	# Semi-implicit damped spring: overshoots a little on release (the "pop").
	_v += ((target - _s) * SPRING_K - _v * SPRING_DAMP) * delta
	_s += _v * delta
	_press = move_toward(_press, 1.0 if pressed else 0.0, delta / (0.05 if pressed else 0.2))
	var was_lit := lit > 0.5
	lit = move_toward(lit, 1.0 if lit_target else 0.0, delta / 0.18)
	if lit > 0.5 and not was_lit:
		_lit_pop = 1.0
		_v += 10.0
	_lit_pop = maxf(_lit_pop - delta / 0.5, 0.0)
	appear = move_toward(appear, 1.0 if shown else 0.0, delta / 0.16)
	for i in range(_ripples.size() - 1, -1, -1):
		var r := _ripples[i]
		r.z += delta / RIPPLE_TIME
		if r.z >= 1.0:
			_ripples.remove_at(i)
		else:
			_ripples[i] = r


func opacity() -> float:
	var rest := IDLE_ALPHA
	if dim_when_unlit:
		rest = lerpf(DIM_ALPHA, LIT_ALPHA, lit)
	var k := lerpf(rest, maxf(rest, PRESSED_ALPHA), _press)
	return k * appear * appear * (3.0 - 2.0 * appear)


func draw(ci: CanvasItem) -> void:
	if appear <= 0.01:
		return
	var a := appear * appear * (3.0 - 2.0 * appear)
	var k := opacity()
	var sy := _s * lerpf(0.6, 1.0, a)
	var sx := (1.0 - (1.0 - _s) * 0.3) * lerpf(0.6, 1.0, a)
	var pulse := 0.5 + 0.5 * sin(_clock * TAU * PULSE_HZ)
	var r := radius
	if lit > 0.0:
		var phase := fmod(_clock * PULSE_HZ, 1.0)
		ci.draw_circle(center, r * (1.08 + 0.4 * phase), Color(accent.lightened(0.4), 0.8 * (1.0 - phase) * lit * a), false, maxf(3.0, r * 0.08 * (1.0 - phase)))
	ci.draw_set_transform(center, 0.0, Vector2(sx, sy))
	var face := FACE.lerp(accent.darkened(0.45), lit * 0.8)
	ci.draw_circle(Vector2.ZERO, r, Color(face, k * lerpf(FILL_ALPHA, 0.85, lit)))
	if _press > 0.0:
		ci.draw_circle(Vector2.ZERO, r * 0.94, Color(1, 1, 1, 0.14 * _press * a))
	var rim_w := maxf(3.0, roundf(r * 0.07))
	ci.draw_circle(Vector2.ZERO, r + 1.0, Color(OUTLINE, 0.6 * k), false, 2.0)
	var rim := accent.lerp(Color.WHITE, lit * (0.3 + 0.5 * pulse))
	ci.draw_circle(Vector2.ZERO, r - rim_w * 0.5, Color(rim, minf(k * 1.4, 1.0)), false, rim_w)
	for rp in _ripples:
		var t := rp.z
		var e := 1.0 - pow(1.0 - t, 3.0)
		var o := Vector2(rp.x, rp.y).lerp(Vector2.ZERO, e)
		ci.draw_circle(o, lerpf(r * 0.35, r * 1.05, e), Color(1, 1, 1, 0.5 * (1.0 - t) * a), false, lerpf(r * 0.14, 2.0, t))
	var icon_alpha := minf(0.95 * k / IDLE_ALPHA, 1.0)
	ci.draw_set_transform(center, 0.0, Vector2(sx, sy) * (1.0 + 0.18 * _lit_pop))
	if glyph != &"":
		_draw_glyph(ci, r * 0.5, Color(1, 1, 1, icon_alpha))
	elif _label:
		# Whole texels only: the pixel font stays crisp at any button size.
		var px := maxf(1.0, floorf(r * 0.85 / _label.get_height()))
		var sz := _label.get_size() * px
		ci.draw_texture_rect(_label, Rect2((-sz * 0.5).round(), sz), false, Color(1, 1, 1, icon_alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_glyph(ci: CanvasItem, s: float, color: Color) -> void:
	var shadow := Color(OUTLINE, color.a * 0.6)
	match glyph:
		&"pause":
			for x in [-0.42, 0.14]:
				ci.draw_rect(Rect2(Vector2(x - 0.04, -0.6) * s, Vector2(0.36, 1.28) * s), shadow)
				ci.draw_rect(Rect2(Vector2(x, -0.62) * s, Vector2(0.28, 1.24) * s), color)
		&"restart":
			var w := maxf(3.0, s * 0.2)
			ci.draw_arc(Vector2.ZERO, s * 0.62, -PI * 0.15, PI * 1.45, 24, shadow, w + 2.0)
			ci.draw_arc(Vector2.ZERO, s * 0.62, -PI * 0.15, PI * 1.45, 24, color, w)
			var tip := Vector2.from_angle(-PI * 0.15) * s * 0.62
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(-0.38, -0.05) * s, tip + Vector2(0.3, -0.12) * s, tip + Vector2(0.0, 0.42) * s]), color)
		&"aim":
			var w := maxf(3.0, s * 0.14)
			ci.draw_arc(Vector2.ZERO, s * 0.62, 0.0, TAU, 28, shadow, w + 2.0)
			ci.draw_arc(Vector2.ZERO, s * 0.62, 0.0, TAU, 28, color, w)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				ci.draw_line(d * s * 0.3, d * s * 1.0, color, w)
			ci.draw_rect(Rect2(Vector2(-0.1, -0.1) * s, Vector2(0.2, 0.2) * s), color)
