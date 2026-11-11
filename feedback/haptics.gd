extends Node

# Autoload `Haptics`: mixes rumble pulses and loops (per-motor max, never summed) and drives the
# joypad that sent the last input. No joypad: everything is a no-op. handheld() is the separate
# phone-motor path of the touch controls (mobile only).
# Command line: `-- --haptics-sim` prints the mix timeline of a scripted scenario and quits.

const Tuning := preload("res://feedback/haptics_tuning.gd")
const HANDHELD_MIN_MS := 20
const HANDHELD_MAX_MS := 400
const HANDHELD_MERGE_MS := 90

var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			_emit(0.0, 0.0)

var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.5)

var device := -1

var _clock := 0.0
var _pulses: Array = [] # {t0, layers, scale}
var _loops: Dictionary = {} # handle -> {profile, scale, stop_at (or -1)}
var _next_handle := 1
var _sent_weak := 0.0
var _sent_strong := 0.0
var _emits := 0
var _simulating := false
var _paused := false
var _handheld_until_ms := 0
var _handheld_amp := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		device = pads[0]
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	if OS.get_cmdline_user_args().has("--haptics-sim"):
		_simulate()
		get_tree().quit()


func play(id: StringName, strength: float = 1.0) -> void:
	var profile: Dictionary = Tuning.PROFILES.get(id, {})
	if profile.is_empty() or profile.get("loop", false):
		return
	var s := clampf(strength, 0.0, Tuning.MAX_STRENGTH)
	if s < float(profile.get("gate", 0.0)):
		return
	_pulses.append({t0 = _clock, layers = profile.layers, scale = pow(s, float(profile.get("strength_exp", 1.0)))})


func start_loop(id: StringName, strength: float = 1.0) -> int:
	var profile: Dictionary = Tuning.PROFILES.get(id, {})
	if not profile.get("loop", false):
		return 0
	var handle := _next_handle
	_next_handle += 1
	_loops[handle] = {profile = profile, scale = clampf(strength, 0.0, Tuning.MAX_STRENGTH), t0 = _clock, stop_at = -1.0}
	return handle


## Live strength of a running loop (0..1.5), e.g. slide speed.
func set_loop_strength(handle: int, strength: float) -> void:
	if _loops.has(handle):
		_loops[handle].scale = clampf(strength, 0.0, Tuning.MAX_STRENGTH)


func stop_loop(handle: int) -> void:
	if _loops.has(handle) and _loops[handle].stop_at < 0.0:
		_loops[handle].stop_at = _clock


## Silences the motors and freezes loops (true); loops resume where they were (false). Pending pulses are dropped.
func pause_all(on: bool) -> void:
	_paused = on
	if on:
		_pulses.clear()
		_emit(0.0, 0.0)


## Phone motor pulse, for touch-button presses: amplitude 0..1, duration in seconds. A pulse landing
## inside the one still playing merges into it unless clearly stronger (no buzzing). No-op off mobile.
func handheld(amplitude: float, duration: float) -> void:
	if not enabled or not OS.has_feature("mobile"):
		return
	var amp := clampf(amplitude * intensity, 0.05, 1.0)
	var ms := clampi(int(duration * 1000.0), HANDHELD_MIN_MS, HANDHELD_MAX_MS)
	var now := Time.get_ticks_msec()
	if now < _handheld_until_ms + HANDHELD_MERGE_MS and amp <= _handheld_amp * 1.25:
		return
	_handheld_until_ms = now + ms
	_handheld_amp = amp
	Input.vibrate_handheld(ms, amp)


func has_profile(id: StringName) -> bool:
	return Tuning.PROFILES.has(id)


func _process(delta: float) -> void:
	if _simulating:
		return
	_step(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		device = event.device
	elif event is InputEventJoypadMotion and absf(event.axis_value) > Tuning.AXIS_DEADZONE:
		device = event.device


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_emit(0.0, 0.0)


func _on_joy_connection_changed(pad: int, connected: bool) -> void:
	var previous := device
	if connected:
		if device < 0:
			device = pad
	elif pad == device:
		var pads := Input.get_connected_joypads()
		device = pads[0] if not pads.is_empty() else -1
	if device != previous:
		# The new pad never received the current mix: force the next step to send it.
		_sent_weak = -1.0
		_sent_strong = -1.0


# Advances the clock, mixes and emits; returns [weak, strong] after quantization.
func _step(delta: float) -> Vector2:
	if _paused:
		return Vector2.ZERO
	var mix := _mix(_clock)
	_clock += delta
	var q := Tuning.QUANT_STEP
	var weak := snappedf(clampf(mix.x * intensity, 0.0, 1.0), q) if enabled else 0.0
	var strong := snappedf(clampf(mix.y * intensity, 0.0, 1.0), q) if enabled else 0.0
	if weak != _sent_weak or strong != _sent_strong:
		_emit(weak, strong)
	return Vector2(weak, strong)


func _mix(now: float) -> Vector2:
	var weak := 0.0
	var strong := 0.0
	var i := _pulses.size() - 1
	while i >= 0:
		var p: Dictionary = _pulses[i]
		var t := now - float(p.t0)
		var alive := false
		for layer: Dictionary in p.layers:
			var lt := t - float(layer.get("delay", 0.0))
			var dur := float(layer.dur)
			if lt > dur:
				continue
			alive = true
			if lt < 0.0:
				continue
			var hold := float(layer.get("hold", Tuning.DEFAULT_HOLD))
			var a := float(p.scale)
			if lt > hold:
				a *= pow(1.0 - (lt - hold) / maxf(dur - hold, 0.001), float(layer.get("curve", 1.0)))
			a *= _wobble(layer, lt)
			weak = maxf(weak, float(layer.weak) * a)
			strong = maxf(strong, float(layer.strong) * a)
		if not alive:
			_pulses.remove_at(i)
		i -= 1
	for handle in _loops.keys():
		var l: Dictionary = _loops[handle]
		var a := float(l.scale) * _wobble(l.profile, now - float(l.t0))
		if l.stop_at >= 0.0:
			var f := 1.0 - (now - float(l.stop_at)) / Tuning.LOOP_FADE
			if f <= 0.0:
				_loops.erase(handle)
				continue
			a *= f
		weak = maxf(weak, float(l.profile.weak) * a)
		strong = maxf(strong, float(l.profile.strong) * a)
	return Vector2(weak, strong)


func _wobble(source: Dictionary, t: float) -> float:
	var depth := float(source.get("wobble_depth", 0.0))
	if depth <= 0.0:
		return 1.0
	return 1.0 - depth * 0.5 * (1.0 - cos(TAU * float(source.get("wobble_hz", 10.0)) * t))


func _emit(weak: float, strong: float) -> void:
	_sent_weak = weak
	_sent_strong = strong
	_emits += 1
	if _simulating or device < 0:
		return
	if weak <= 0.0 and strong <= 0.0:
		Input.stop_joy_vibration(device)
	else:
		Input.start_joy_vibration(device, weak, strong, 0.0)


# Scenario: AK burst overlapping a heavy landing, a skid loop, then a wall break and a bullet hit.
func _simulate() -> void:
	_simulating = true
	var events := [[0.10, &"jump", 1.0]]
	for k in 10:
		events.append([0.20 + k * 0.09, &"rifle_shot", 1.0])
	events.append_array([[0.47, &"land", 1.0], [0.62, &"footstep", 1.0], [0.70, &"footstep", 0.5],
		[1.60, &"wall_break", 1.0], [1.68, &"punch_hit", 1.0], [2.40, &"bullet_hit_body", 1.0], [2.45, &"hurt_hit", 1.0]])
	var dt := 1.0 / 60.0
	var skid := 0
	var slide := 0
	var peak := Vector2.ZERO
	var frames := 0
	var lines := PackedStringArray()
	for f in int(3.4 / dt):
		var t := f * dt
		for e in events:
			if absf(float(e[0]) - t) < dt * 0.5:
				play(e[1], e[2])
				lines.append("        event %s(%.1f)" % [e[1], e[2]])
		if f == int(1.0 / dt):
			skid = start_loop(&"skid")
			lines.append("        loop start skid")
		if f == int(1.4 / dt):
			stop_loop(skid)
			lines.append("        loop stop skid")
		if f == int(2.7 / dt):
			slide = start_loop(&"wall_slide", 0.0)
			lines.append("        loop start wall_slide (strength ramps 0 -> 1)")
		if slide and t < 3.1:
			set_loop_strength(slide, (t - 2.7) / 0.4)
		if f == int(3.1 / dt):
			stop_loop(slide)
			lines.append("        loop stop wall_slide")
		var before := _emits
		var v := _step(dt)
		peak = Vector2(maxf(peak.x, v.x), maxf(peak.y, v.y))
		frames += 1
		lines.append("t=%.3f weak=%.2f strong=%.2f %s %s" % [t, v.x, v.y,
			"|" + "#".repeat(int(v.y * 20)).rpad(20) + "|", "EMIT" if _emits > before else ""])
	print("\n".join(lines))
	print("Haptics sim: %d frames, %d emits, peak weak=%.2f strong=%.2f, intensity=%.2f" % [frames, _emits, peak.x, peak.y, intensity])
	_simulating = false
