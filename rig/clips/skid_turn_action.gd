class_name SkidTurnAction
extends RigAction
## Skid turn: dig the feet in and slide to a stop, hop-turn, crouch and launch the other way in a
## full run. The slide comes out as root motion; facing flips at FLIP_T (event "flip").

const S := preload("res://rig/clips/skid_turn_tuning.gd")

var K := {}
var run_gait: RigGait
var run_pose: RigPose
var run_l := 1.0
var v_in := 0.0
var v_out := 0.0
var skid_span := S.STOP_T - S.SKID_T
var ramp_span := S.HALF - S.LAUNCH_T
var skid_dist := 0.0
var ramp_dist := 0.0
var phase0 := 0.0
var launch_phase := 0.0
var trail_slots := 0
var _trail_params := {}
var _speed := 0.0
var _world := 0.0


func _init(rig_data: RigData, gait: RigGait) -> void:
	super(rig_data)
	id = &"skid_turn"
	duration = S.HALF - S.SKID_T
	run_gait = gait
	run_pose = RigPose.new(rig)
	K = RigTrack.compile(S.T.tracks)


func begin(host) -> void:
	start_facing = host.facing
	v_out = run_gait.ground_speed()
	v_in = maxf(host.get_entry_speed(), S.T.minEntrySpeed)
	run_l = run_gait.cycle_length()
	skid_dist = v_in * skid_span / (S.T.skidEase + 1.0)
	ramp_dist = v_out * ramp_span / (S.T.launchEase + 1.0)
	phase0 = host.get_loco_phase()
	launch_phase = RigMath.frac(S.T.skidLeadPhase - v_out * S.SKID_T / run_l - ramp_dist / run_l)
	exit_phase = RigMath.frac(launch_phase + ramp_dist / run_l)
	_build_events()


func _motion(tau: float) -> void:
	if tau < S.SKID_T:
		_world = 0.0
		_speed = v_in
	elif tau < S.STOP_T:
		var s := (tau - S.SKID_T) / skid_span
		_world = skid_dist * (1.0 - pow(1.0 - s, S.T.skidEase + 1.0))
		_speed = v_in * pow(1.0 - s, S.T.skidEase)
	elif tau < S.LAUNCH_T:
		_world = skid_dist
		_speed = 0.0
	else:
		var s := minf(1.0, (tau - S.LAUNCH_T) / ramp_span)
		_world = skid_dist - ramp_dist * pow(s, S.T.launchEase + 1.0)
		_speed = -v_out * pow(s, S.T.launchEase)


func root_motion(t: float) -> Vector2:
	_motion(S.SKID_T + t)
	return Vector2(_world, 0.0)


func facing_sign(t: float) -> int:
	return 1 if S.SKID_T + t < S.FLIP_T else -1


func _run_weight(tau: float) -> float:
	if tau < S.SKID_T:
		return 1.0
	if tau < S.LAUNCH_T:
		return 1.0 - RigMath.smooth01((tau - S.SKID_T) / S.T.skidBlend)
	return RigMath.smooth01((tau - S.LAUNCH_T) / S.T.launchBlend)


func _phase(tau: float) -> float:
	_motion(tau)
	if tau < S.STOP_T:
		return RigMath.frac(phase0 + _world / run_l)
	return RigMath.frac(launch_phase + (skid_dist - _world) / run_l)


func _turn_width(tau: float) -> float:
	if tau <= S.TURN_T or tau >= S.TURN_END:
		return 1.0
	var s := (tau - S.TURN_T) / (S.FLIP_T - S.TURN_T) if tau < S.FLIP_T else (S.TURN_END - tau) / (S.TURN_END - S.FLIP_T)
	return lerpf(1.0, S.T.flipWidth, s * s)


func _tk(name: String, tau: float) -> float:
	return (K[name] as RigTrack).sample(tau)


func _action_pose(tau: float, pose: RigPose, juice: bool) -> void:
	RigLocomotion.sample_idle(rig, pose, 0.0, false)
	pose.y[B.HIP] = _tk("hipY", tau)
	pose.x[B.HIP] = _tk("hipX", tau)
	pose.rot[B.TORSO] = deg_to_rad(_tk("torso", tau))
	pose.rot[B.NECK] = deg_to_rad(_tk("neck", tau))
	pose.rot[B.UPPER_ARM_F] = deg_to_rad(_tk("armF", tau))
	pose.rot[B.FORE_ARM_F] = deg_to_rad(_tk("foreF", tau))
	pose.rot[B.UPPER_ARM_B] = deg_to_rad(_tk("armB", tau))
	pose.rot[B.FORE_ARM_B] = deg_to_rad(_tk("foreB", tau))
	pose.rot[B.HAIR] = deg_to_rad(_tk("hair", tau))
	pose.rot[B.SCARF1] = deg_to_rad(_tk("scarf1", tau))
	pose.rot[B.SCARF2] = deg_to_rad(_tk("scarf2", tau))
	var J: Dictionary = S.T.juice
	if juice:
		for at in [S.STOP_T, S.LAUNCH_T]:
			var ts: float = tau - at
			if ts < 0.0 or ts > 0.6:
				continue
			var spring: float = J.springAmp * exp(-ts / J.springDecay) * sin(TAU * J.springFreq * ts)
			pose.rot[B.HAIR] += deg_to_rad(spring * 0.6)
			pose.rot[B.SCARF1] += deg_to_rad(spring)
			pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
		var crouch := clampf((tau - S.SKID_T) / 0.1, 0.0, 1.0) * clampf((S.TURN_T - tau) / 0.1, 0.0, 1.0)
		RigMath.squash(pose, B.TORSO, J.skidSquash * crouch)
	var sliding := tau > S.SKID_T and tau < S.STOP_T
	var jitter: float = J.skidJitter * (1.0 - (tau - S.SKID_T) / skid_span) if juice and sliding else 0.0
	var fa := deg_to_rad(_tk("frontAngle", tau)) + (deg_to_rad(sin(tau * 173.0) * jitter * 1.5) if jitter != 0.0 else 0.0)
	var a := RigMath.planted_ankle(_tk("frontX", tau), 0.0, fa)
	RigMath.solve_leg(rig, pose, "front", a.x, a.y - _tk("frontLift", tau) - (absf(sin(tau * 131.0)) * jitter if jitter != 0.0 else 0.0), fa)
	var ba := deg_to_rad(_tk("backAngle", tau))
	a = RigMath.planted_ankle(_tk("backX", tau), 0.0, ba)
	RigMath.solve_leg(rig, pose, "back", a.x, a.y - _tk("backLift", tau), ba)


func sample(t: float, pose: RigPose, juice: bool) -> void:
	var tau := S.SKID_T + t
	var w := _run_weight(tau)
	if w < 1.0:
		_action_pose(tau, pose, juice)
	if w > 0.0:
		var phase := _phase(tau)
		RigLocomotion.sample_gait(rig, run_pose if w < 1.0 else pose, phase, run_gait, juice)
		if w < 1.0:
			pose.blend_toward(run_pose, w)
	pose.root_x = 0.0
	pose.root_y = 0.0
	pose.facing = start_facing * facing_sign(t)
	if tau > S.TURN_T and tau < S.TURN_END:
		var s := (tau - S.TURN_T) / (S.TURN_END - S.TURN_T)
		pose.root_y = -S.T.hop * 4.0 * s * (1.0 - s)
		pose.root_sx = _turn_width(tau)
		pose.rot[B.TORSO] += deg_to_rad(S.T.flipTilt * sin(PI * s))
	if juice:
		var J: Dictionary = S.T.juice
		var sq: float = J.stopSquash * _pulse(tau, S.STOP_T - 0.04, J.stopSquashSeconds) + J.landSquash * _pulse(tau, S.TURN_END - 0.01, 0.12) - J.launchStretch * _pulse(tau, S.LAUNCH_T, 0.16)
		pose.root_sy *= 1.0 - sq
		pose.root_sx *= 1.0 + sq * 0.6
		var cs := tau - S.STOP_T + 0.03
		if cs >= 0.0 and cs < J.shakeSeconds:
			var decay := pow(1.0 - cs / J.shakeSeconds, 2.0)
			var p: float = TAU * J.shakeFreq * cs
			pose.shake_x = start_facing * J.shakeAmp * decay * sin(p)
			pose.shake_y = J.shakeAmp * 0.5 * decay * sin(p * 1.3 + 1.0)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)


static func _pulse(tau: float, at: float, span: float) -> float:
	var k := (tau - at) / span
	return sin(PI * k) if k > 0.0 and k < 1.0 else 0.0


func _build_events() -> void:
	events.clear()
	var J: Dictionary = S.T.juice
	var t0 := S.SKID_T
	events.append({"t": 0.0, "signal": &"skid_start"})
	events.append({"t": 0.02, "fx": "burst", "anchor": "toeF", "params": _merge(J.digDebris, {"sprite": "debris", "angle": -0.7, "cone": 0.9, "floor": 0.0, "restitution": 0.3, "spin": 14.0})})
	events.append({"t": 0.02, "fx": "dust", "anchor": "heelF", "params": _merge(J.digDust, {"dir": 1})})
	events.append({"t": S.STOP_T - 0.02 - t0, "fx": "skidCloud", "anchor": "soleF", "params": _merge(J.stopCloud, {"dir": 1})})
	events.append({"t": S.STOP_T - 0.02 - t0, "fx": "skidCloud", "anchor": "soleB", "params": _merge(J.stopCloud, {"dir": 1, "count": 5, "scale": 1.8})})
	events.append({"t": S.STOP_T - t0, "signal": &"skid_stop"})
	events.append({"t": S.FLIP_T - t0, "flip": true})
	events.append({"t": S.FLIP_T - t0, "signal": &"flip"})
	events.append({"t": S.TURN_END - t0, "fx": "dust", "anchor": "soleF", "params": _merge(J.landDust, {"dir": 0})})
	events.append({"t": S.TURN_END - t0, "footstep": &"front", "strength": 0.6})
	events.append({"t": S.LAUNCH_T + 0.03 - t0, "fx": "skidCloud", "anchor": "toeF", "params": _merge(J.launchPuff, {"dir": -1})})
	events.append({"t": S.LAUNCH_T + 0.03 - t0, "fx": "burst", "anchor": "toeF", "params": _merge(J.launchDebris, {"sprite": "debris", "angle": PI + 0.6, "cone": 0.8, "floor": 0.0, "restitution": 0.3, "spin": 12.0, "layer": "back"})})
	events.append({"t": S.LAUNCH_T + 0.04 - t0, "fx": "ghost", "params": J.launchGhost})
	# Footfalls of the launch run (phase crossings of 0 and 0.5).
	var prev := _phase(S.LAUNCH_T)
	var tau := S.LAUNCH_T
	while tau < S.HALF:
		tau += 1.0 / 240.0
		var p := _phase(tau)
		for edge in [0.0, 0.5]:
			if _crossed(prev, p, edge):
				events.append({"t": tau - t0, "footstep": &"front" if edge == 0.0 else &"back", "strength": 0.8})
		prev = p
	# Sole trail while sliding.
	var tr: Dictionary = J.trail
	_trail_params = _merge(tr, {"speed": v_in})
	trail_slots = int(skid_span / tr.interval)
	for k in trail_slots:
		events.append({"t": k * tr.interval, "custom": "trail", "slot": k})
	sort_events()


static func _crossed(a: float, b: float, edge: float) -> bool:
	var d := RigMath.frac(edge - a)
	return d > 0.0 and d <= RigMath.frac(b - a)


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func custom_event(ev: Dictionary, host) -> void:
	if ev.custom != "trail" or not host.juice:
		return
	_motion(S.SKID_T + ev.t)
	var vk := _speed / v_in
	var sole: Vector2 = host.anchor_world("soleF")
	var heel: Vector2 = host.anchor_world("heelB")
	var toe: Vector2 = host.anchor_world("toeF")
	var ground: float = host.global_position.y
	var aux := PackedFloat32Array([sole.x, minf(ground, sole.y), heel.x, minf(ground, heel.y), vk, float(ev.slot)])
	host.fx.spawn("skidTrail", _trail_params, toe.x, minf(ground, toe.y), 0.0, host.pose.facing, ground, host.now(), aux)
