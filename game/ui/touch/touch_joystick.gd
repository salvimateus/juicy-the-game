extends RefCounted

# Dynamic move stick: rests as a ghost at `home`, spawns under the finger, drags its base along
# when the finger passes the rim and eases back home on release. Pure state + drawing.

const SPRINT_COLOR := Color("#ffb03a")
const FACE := Color(0.06, 0.05, 0.09)
const OUTLINE := Color(0.03, 0.02, 0.05)
const DEADZONE := 0.08
# Deflection that already gives full output (full run); past SPRINT_BAND the stick also sprints.
const FULL_AT := 0.85
const SPRINT_BAND := 0.97
const RETURN_TIME := 0.22
const GHOST_ALPHA := 0.3
const ACTIVE_ALPHA := 0.65
const FILL_ALPHA := 0.32
const KNOB_ALPHA := 0.8
const FADE_TIME := 0.25

var home := Vector2.ZERO
var radius := 100.0
var knob_radius := 42.0
var active := false
var base := Vector2.ZERO
# Knob offset from the base, length <= radius.
var knob := Vector2.ZERO
# Dims the ghost (the moto layout only uses the horizontal axis).
var horizontal_only := false

var _return_from := Vector2.ZERO
var _return_t := 1.0
var _presence := 0.0
var _sprint_glow := 0.0
var _sprint_flash := 0.0
var _press_pop := 0.0


func place(p_home: Vector2, p_radius: float, p_knob_radius: float) -> void:
	home = p_home
	radius = p_radius
	knob_radius = p_knob_radius
	if not active and _return_t >= 1.0:
		base = home


func press(p: Vector2) -> void:
	active = true
	base = p
	knob = Vector2.ZERO
	_return_t = 1.0
	_press_pop = 1.0


func drag(p: Vector2) -> void:
	if not active:
		return
	var off := p - base
	if off.length() > radius:
		# Past the rim the base follows the finger instead of locking.
		base = p - off.normalized() * radius
		off = off.normalized() * radius
	knob = off


func release() -> void:
	if not active:
		return
	active = false
	_return_from = base
	_return_t = 0.0


func deflection() -> float:
	return knob.length() / radius if active else 0.0


# Analog output 0..1 per axis (screen space: +x right, +y down), radial deadzone removed.
func output() -> Vector2:
	var d := deflection()
	if d <= DEADZONE:
		return Vector2.ZERO
	return knob.normalized() * minf((d - DEADZONE) / (FULL_AT - DEADZONE), 1.0)


func in_sprint_band() -> bool:
	return deflection() >= SPRINT_BAND


func flash_sprint() -> void:
	_sprint_flash = 1.0


func update(delta: float) -> void:
	if not active:
		knob = knob.lerp(Vector2.ZERO, 1.0 - exp(-delta * 22.0))
		if _return_t < 1.0:
			_return_t = minf(_return_t + delta / RETURN_TIME, 1.0)
			base = _return_from.lerp(home, 1.0 - pow(1.0 - _return_t, 3.0))
		else:
			base = home
	_presence = move_toward(_presence, 1.0 if active else 0.0, delta / (0.08 if active else FADE_TIME))
	_sprint_glow = move_toward(_sprint_glow, 1.0 if active and in_sprint_band() and not horizontal_only else 0.0, delta / 0.12)
	_sprint_flash = maxf(_sprint_flash - delta / 0.45, 0.0)
	_press_pop = maxf(_press_pop - delta / 0.25, 0.0)


func draw(ci: CanvasItem) -> void:
	var a := lerpf(GHOST_ALPHA, ACTIVE_ALPHA, _presence)
	var r := radius * (1.0 + 0.06 * _press_pop * _press_pop)
	var c := base
	ci.draw_circle(c, r, Color(FACE, FILL_ALPHA * _presence + 0.06))
	ci.draw_circle(c, r * 0.62, Color(1, 1, 1, 0.12 * a), false, 2.0)
	ci.draw_circle(c, r + 1.5, Color(OUTLINE, 0.5 * a), false, 2.0)
	ci.draw_circle(c, r - 1.5, Color(1, 1, 1, a), false, 3.0)
	# Direction chevrons; the moto layout keeps only left and right.
	for i in 4:
		if horizontal_only and i % 2 == 1:
			continue
		var d := Vector2.from_angle(TAU * float(i) / 4.0)
		var side := Vector2(-d.y, d.x)
		var tip := c + d * r * 0.86
		var back := c + d * r * 0.74
		var chev := PackedVector2Array([back + side * r * 0.1, tip, back - side * r * 0.1])
		ci.draw_polyline(chev, Color(OUTLINE, 0.4 * a), 6.0)
		ci.draw_polyline(chev, Color(1, 1, 1, 0.85 * a), 3.0)
	if _sprint_glow > 0.0:
		ci.draw_circle(c, r - 2.0, Color(SPRINT_COLOR, 0.95 * _sprint_glow), false, 6.0 + 4.0 * _sprint_flash)
	if active and knob.length() > radius * DEADZONE:
		var ang := knob.angle()
		var col := Color.WHITE.lerp(SPRINT_COLOR, _sprint_glow)
		ci.draw_arc(c, r - 2.0, ang - 0.55, ang + 0.55, 16, Color(col, 0.85 * clampf(deflection(), 0.0, 1.0)), 7.0)
	var k := c + knob
	var kr := knob_radius * (1.0 + 0.08 * _press_pop)
	var ka := lerpf(GHOST_ALPHA, KNOB_ALPHA, _presence)
	var knob_col := Color("#fff6dc").lerp(Color("#ffd98a"), _sprint_glow * 0.7)
	ci.draw_circle(k, kr + 1.5, Color(OUTLINE, 0.6 * ka), false, 2.0)
	ci.draw_circle(k, kr, Color(knob_col.darkened(0.25), ka))
	ci.draw_circle(k + Vector2(0, -kr * 0.08), kr * 0.86, Color(knob_col, ka))
