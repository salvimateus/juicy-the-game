class_name RigSwim
extends RefCounted
## The swimmer the Adventurer drives through set_swim: per-mode samplers (tread, front crawl,
## breaststroke, float) cross-faded by weight, one smoothed body heading applied as a root
## rotation around the center of mass, scarf follow-through and the water FX. tick builds the
## pose (with a per-bone turn limit against the previous frame); sample copies it.
##
## Origin convention: the same as on the ground (under the hip at rest), so entering the water
## from the air does not move the body; the center of mass sits at origin + COM in every mode.

const S := preload("res://rig/clips/swim_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7
const MODES: Array[StringName] = [&"tread", &"surface", &"under", &"under_idle"]
const TREAD := 0
const SURFACE := 1
const UNDER := 2
const IDLE := 3
const SIDES := ["front", "back"]
## Draw order preset (see SwimActions.draw_orders): base order without the raised-arm swap.
const ORDER_HORIZONTAL := 41

var rig: RigData
var world := PackedFloat32Array()
var tracks := {}
var poses: Array[RigPose] = []
var out: RigPose
var prev: RigPose
var has_out := false
var mouth_field := -1
var mouth_anchor := "chest"
var has_sprites := false
var com := Vector2.ZERO

# State.
var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])
var active := TREAD
var theta := -PI * 0.5
var vis_facing := 1
var turn_via := 0.0
var turn_w := 0.0
var horizontal := false
var tread_u := 0.0
var surface_u := 0.0
var under_u := 0.0
var idle_u := 0.0
var time := 0.0
var speed := 0.0
var scarf1 := PI
var scarf2 := PI
var last_now := -100.0
## Previews: suppress FX (warm-up) and force the target facing (0 = host.facing).
var quiet := false
var target_facing := 0

# FX params (built once; spawn keeps a reference).
var fx_bubbles: Dictionary
var fx_kick_bubbles: Dictionary
var fx_idle_bubbles: Dictionary
var fx_splash: Dictionary
var fx_kick_foam: Dictionary
var fx_tread_foam: Dictionary


func _init(rig_data: RigData) -> void:
	rig = rig_data
	world = RigMath.create_world(rig)
	for i in 4:
		poses.append(RigPose.new(rig))
	out = RigPose.new(rig)
	prev = RigPose.new(rig)
	var T: Dictionary = S.T
	com = Vector2(T.com[0], T.com[1])
	for group in ["tread", "surface", "under"]:
		for key in T[group]:
			var v = T[group][key]
			if v is Array and v.size() > 0 and v[0] is Array:
				tracks[group + "." + key] = RigTrack.from_keys(v)
	mouth_field = rig.face_fields.find("mouth")
	if rig.anchors.has("mouth_shout.anchor"):
		mouth_anchor = "mouth_shout.anchor"
	has_sprites = rig.fx_sprites.has("swimBubble") and rig.fx_sprites.has("swimDrop") and rig.fx_sprites.has("swimFoam")
	var J: Dictionary = T.juice
	fx_bubbles = J.bubbles.merged({"emit": RigSwim.emit_bubbles})
	fx_kick_bubbles = J.kickBubbles.merged({"emit": RigSwim.emit_bubbles})
	fx_idle_bubbles = J.idleBubbles.merged({"emit": RigSwim.emit_bubbles})
	fx_splash = J.splash.merged({"emit": RigSwim.emit_splash})
	fx_kick_foam = J.kickFoam.merged({"emit": RigSwim.emit_foam})
	fx_tread_foam = J.treadFoam.merged({"emit": RigSwim.emit_foam})


## Water line relative to the origin for a mode (tread and surface), y down.
static func water_line(mode: StringName) -> float:
	return S.T.waterLineSurface if mode == &"surface" else S.T.waterLineTread


func trk(name: String, u: float) -> float:
	return (tracks[name] as RigTrack).sample(u, true)


func trk_once(name: String, u: float) -> float:
	return (tracks[name] as RigTrack).sample(u, false)


## Starts fresh in a mode (entering the water or after a gap): upright, current facing.
func reset_state(mode: int, facing: int) -> void:
	weights.fill(0.0)
	weights[mode] = 1.0
	active = mode
	theta = -PI * 0.5
	vis_facing = facing
	turn_via = 0.0
	turn_w = 0.0
	horizontal = false
	scarf1 = deg_to_rad(S.T.scarf.tread) if mode <= SURFACE else deg_to_rad(S.T.scarf.float)
	scarf2 = scarf1
	has_out = false


# ---------------------------------------------------------------------------------------------
# Tick

func tick(host, mode: StringName, velocity: Vector2, delta: float) -> float:
	if delta <= 0.0:
		return 0.0
	var T: Dictionary = S.T
	var m := MODES.find(mode)
	if m < 0:
		m = TREAD
	var f_target: int = target_facing if target_facing != 0 else host.facing
	var now: float = host.now()
	if now - last_now > 0.25 or not has_out:
		reset_state(m, f_target)
	last_now = now
	time += delta
	active = m
	for i in 4:
		weights[i] = move_toward(weights[i], 1.0 if i == m else 0.0, delta / T.modeBlend)
	var spd := velocity.length()
	speed = lerpf(speed, spd, 1.0 - exp(-delta / T.speedSmoothing))

	var p_tread := tread_u
	var p_surface := surface_u
	var p_under := under_u
	var p_idle := idle_u
	tread_u = RigMath.frac(tread_u + delta / T.tread.duration)
	surface_u = RigMath.frac(surface_u + minf(speed / T.surface.cycleLength, T.surface.maxRate) * delta)
	under_u = RigMath.frac(under_u + clampf(speed / T.under.cycleLength, T.under.minRate, T.under.maxRate) * delta)
	idle_u = RigMath.frac(idle_u + delta / T.idle.duration)

	_update_heading(m, velocity, spd, f_target, delta)
	_update_scarf(delta)

	var stroke := 0.0
	var fx_on: bool = not quiet and host.juice and has_sprites
	match m:
		TREAD:
			var at: float = T.tread.pushAt
			if _crossed(p_tread, tread_u, at) or _crossed(p_tread, tread_u, RigMath.frac(at + 0.5)):
				stroke = T.tread.stroke
				if fx_on:
					_spawn(host, fx_tread_foam, host.global_position.x, host.global_position.y + T.waterLineTread)
		SURFACE:
			var k := clampf(speed / T.surface.speedRef, 0.0, 1.0)
			for side in 2:
				if _crossed(p_surface, surface_u, 0.5 * side):
					stroke = lerpf(T.surface.strokeMin, T.surface.strokeMax, k)
					if fx_on:
						var hand: Vector2 = host.anchor_world("fistF" if side == 0 else "fistB")
						_spawn(host, fx_splash, hand.x, host.global_position.y + T.waterLineSurface)
			if fx_on:
				var beats: float = T.surface.kickBeats * 2.0 / T.surface.foamEvery
				for b in int(beats):
					if _crossed(p_surface, surface_u, b / beats):
						var toe: Vector2 = host.anchor_world("toeF" if b % 2 == 0 else "toeB")
						_spawn(host, fx_kick_foam, toe.x, host.global_position.y + T.waterLineSurface)
		UNDER:
			if _crossed(p_under, under_u, T.under.kickAt):
				stroke = lerpf(T.under.strokeMin, T.under.strokeMax, clampf(speed / T.under.speedRef, 0.0, 1.0))
				if fx_on:
					for a in ["toeF", "toeB"]:
						var toe: Vector2 = host.anchor_world(a)
						_spawn(host, fx_kick_bubbles, toe.x, toe.y)
			if fx_on and _crossed(p_under, under_u, T.under.exhaleAt):
				var mouth: Vector2 = host.anchor_world(mouth_anchor)
				_spawn(host, fx_bubbles, mouth.x, mouth.y)
		IDLE:
			if fx_on and _crossed(p_idle, idle_u, T.idle.bubbleAt):
				var mouth: Vector2 = host.anchor_world(mouth_anchor)
				_spawn(host, fx_idle_bubbles, mouth.x, mouth.y)

	_build(host.juice, delta)
	return stroke


func sample(_host, pose: RigPose, juice: bool) -> void:
	if not has_out:
		_build(juice, 0.0)
	pose.copy_from(out)


static func _crossed(a: float, b: float, edge: float) -> bool:
	if a == b:
		return false
	if b >= a:
		return edge > a and edge <= b
	return edge > a or edge <= b


func _spawn(host, params: Dictionary, x: float, y: float) -> void:
	host.fx.spawn("custom", params, x, y, 0.0, vis_facing, y, host.now())


# ---------------------------------------------------------------------------------------------
# Heading and scarf

func _desired_angle(m: int, velocity: Vector2, spd: float) -> float:
	var T: Dictionary = S.T
	match m:
		TREAD:
			var lean: float = T.tread.leanBySpeed * clampf(velocity.x * vis_facing / T.tread.leanSpeedRef, -1.0, 1.0)
			return deg_to_rad(T.tread.angle + lean)
		SURFACE:
			return deg_to_rad(T.surface.angle)
		UNDER:
			if spd < T.underMinSpeed:
				return theta
			return atan2(velocity.y, absf(velocity.x))
	return deg_to_rad(T.idle.angle + T.idle.angleWave * sin(TAU * idle_u))


func _approach(goal: float, delta: float) -> void:
	var T: Dictionary = S.T
	var d := goal - theta
	var k := 1.0 - exp(-delta / T.turnSmoothing)
	var step := clampf(absf(d) * k, minf(absf(d), deg_to_rad(T.turnMinRate) * delta), deg_to_rad(T.turnRate) * delta)
	theta += signf(d) * step


func _update_heading(m: int, velocity: Vector2, spd: float, f_target: int, delta: float) -> void:
	var T: Dictionary = S.T
	var desired := clampf(_desired_angle(m, velocity, spd), -PI * 0.5, PI * 0.5)
	var turning := vis_facing != f_target
	turn_w = move_toward(turn_w, 1.0 if turning else 0.0, delta / T.turnSquashTime)
	if turning:
		if turn_via == 0.0:
			# Underwater the body may turn through either vertical; at the surface it goes upright.
			turn_via = -1.0
			if m == UNDER and theta + desired > 0.05:
				turn_via = 1.0
		var goal := turn_via * PI * 0.5
		_approach(goal, delta)
		if absf(theta - goal) < 0.01 and turn_w >= T.turnFlipAt:
			theta = goal
			vis_facing = f_target
			scarf1 = PI - scarf1
			scarf2 = PI - scarf2
			turn_via = 0.0
	else:
		turn_via = 0.0
		_approach(desired, delta)
	var off := absf(rad_to_deg(theta) + 90.0)
	if horizontal and off < T.horizontalOff:
		horizontal = false
	elif not horizontal and off > T.horizontalOn:
		horizontal = true


func _update_scarf(delta: float) -> void:
	var C: Dictionary = S.T.scarf
	var trail := theta + PI
	var float_dir := deg_to_rad(C.float + C.floatDrift * sin(TAU * C.floatHz * time))
	var flutter := deg_to_rad(C.flutter) * sin(TAU * C.flutterHz * time)
	var lift := deg_to_rad(C.trailLift)
	var under_dir := _mix_angle(float_dir, trail + lift + flutter, clampf(speed / C.trailSpeed, 0.0, 1.0))
	var dirs := [deg_to_rad(C.tread) + flutter * 0.3, trail + deg_to_rad(C.surfaceLift) + flutter * 0.4, under_dir, float_dir]
	var v := Vector2.ZERO
	for i in 4:
		v += Vector2.from_angle(dirs[i]) * weights[i]
	var target := v.angle() if v.length() > 0.001 else scarf1
	scarf1 = lerp_angle(scarf1, target, 1.0 - exp(-delta / C.lag1))
	var wave := deg_to_rad(C.link2Wave) * sin(TAU * C.link2Hz * time + 1.3)
	scarf2 = lerp_angle(scarf2, scarf1 + wave, 1.0 - exp(-delta / C.lag2))


static func _mix_angle(a: float, b: float, w: float) -> float:
	return a + wrapf(b - a, -PI, PI) * w


# ---------------------------------------------------------------------------------------------
# Pose

func _build(juice: bool, delta: float) -> void:
	var T: Dictionary = S.T
	var first := true
	var acc := 0.0
	var mouth := 0.0
	# A surface turn passes through tread (no crawl stroke while upright).
	var shift := weights[SURFACE] * turn_w
	for i in 4:
		var wi := weights[i]
		if i == SURFACE:
			wi -= shift
		elif i == TREAD:
			wi += shift
		var w := RigMath.smooth01(wi)
		if w <= 0.001:
			continue
		var p := poses[i]
		mouth += w * _sample_mode(i, p, juice)
		acc += w
		if first:
			out.copy_from(p)
			first = false
		else:
			blend(out, p, w / acc)
	if first:
		mouth = _sample_mode(TREAD, out, juice)
		acc = 1.0
	mouth /= acc
	# Turn squash, then keep the center of mass in place under the root scale.
	out.root_sx *= 1.0 - (1.0 - T.turnWidth) * turn_w * (1.0 - absf(cos(theta)))
	if absf(out.root_sy - 1.0) > 0.0001:
		out.y[B.HIP] += com.y / out.root_sy - com.y
	RigMath.spin_root(out, theta + PI * 0.5, com.x, com.y)
	_pose_scarf()
	RigMath.derive_bones(rig, out, WAIST_FOLLOW)
	if mouth_field >= 0:
		out.face[mouth_field] = 1.0 if mouth > 0.45 else 0.0
	out.facing = vis_facing
	out.draw_order = ORDER_HORIZONTAL if horizontal else 0
	if has_out and delta > 0.0:
		var lim := deg_to_rad(T.maxBoneTurn) * delta * 60.0
		for i in rig.bone_count:
			var d := wrapf(out.rot[i] - prev.rot[i], -PI, PI)
			if absf(d) > lim:
				out.rot[i] = prev.rot[i] + signf(d) * lim
	prev.copy_from(out)
	has_out = true


## Moves a toward b by w; bone rotations take the short way around.
static func blend(a: RigPose, b: RigPose, w: float) -> void:
	for i in a.rot.size():
		a.rot[i] = lerp_angle(a.rot[i], b.rot[i], w)
		a.x[i] = lerpf(a.x[i], b.x[i], w)
		a.y[i] = lerpf(a.y[i], b.y[i], w)
		a.sx[i] = lerpf(a.sx[i], b.sx[i], w)
		a.sy[i] = lerpf(a.sy[i], b.sy[i], w)
	a.root_x = lerpf(a.root_x, b.root_x, w)
	a.root_y = lerpf(a.root_y, b.root_y, w)
	a.root_rot = lerp_angle(a.root_rot, b.root_rot, w)
	a.pivot_x = lerpf(a.pivot_x, b.pivot_x, w)
	a.pivot_y = lerpf(a.pivot_y, b.pivot_y, w)
	a.root_sx = lerpf(a.root_sx, b.root_sx, w)
	a.root_sy = lerpf(a.root_sy, b.root_sy, w)
	a.shake_x = lerpf(a.shake_x, b.shake_x, w)
	a.shake_y = lerpf(a.shake_y, b.shake_y, w)
	if w >= 0.5:
		for i in a.face.size():
			a.face[i] = b.face[i]
		a.props = b.props
		a.draw_order = b.draw_order
		a.facing = b.facing


## Scarf links toward the smoothed directions, measured in the facing frame after the root.
func _pose_scarf() -> void:
	var C: Dictionary = S.T.scarf
	var f := out.facing
	out.facing = 1
	out.rot[B.SCARF1] = 0.0
	RigMath.compute_world(rig, out, world)
	out.facing = f
	var wrap := RigMath.bone_angle(world, B.SCARF_WRAP)
	var d1 := scarf1 - deg_to_rad(C.restLink1)
	out.rot[B.SCARF1] = wrapf(d1 - wrap, -PI, PI)
	out.rot[B.SCARF2] = wrapf(scarf2 - deg_to_rad(C.restLink2) - d1, -PI, PI)


## Samples one mode into p (authored upright, facing right); returns the mouth opening 0..1.
func _sample_mode(m: int, p: RigPose, juice: bool) -> float:
	match m:
		TREAD:
			return sample_tread(p, tread_u, juice)
		SURFACE:
			return sample_surface(p, surface_u, juice)
		UNDER:
			return sample_under(p, under_u, juice)
	return sample_float(p, idle_u, juice)


func sample_tread(p: RigPose, u: float, juice: bool) -> float:
	var T: Dictionary = S.T.tread
	p.reset()
	var lean: float = T.lean + T.leanWave * sin(TAU * 2.0 * u)
	p.rot[B.TORSO] = deg_to_rad(lean)
	p.rot[B.NECK] = deg_to_rad(T.neck - lean * 0.5 + T.headBob * sin(TAU * 2.0 * (u - 0.1)))
	for side in SIDES:
		var leg: RigData.Leg = rig.legs[side]
		var uu := RigMath.frac(u + (0.0 if side == "front" else 0.5))
		var s := 1.0 if side == "front" else -1.0
		p.rot[leg.thigh] = deg_to_rad(trk("tread.thigh", uu) + s * T.spread)
		p.rot[leg.shin] = deg_to_rad(trk("tread.shin", uu))
		p.rot[leg.foot] = deg_to_rad(trk("tread.foot", uu))
	var sc := sin(TAU * 2.0 * u)
	var sl := sin(TAU * (2.0 * u - T.scullLag))
	for side in SIDES:
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		var k := 1.0 if side == "front" else -1.0
		p.rot[upper] = deg_to_rad(T.armUpper[side] + T.scullUpper * sc * k)
		p.rot[upper + 1] = deg_to_rad(T.armFore[side] + T.scullFore * sl * k)
		p.rot[upper + 2] = deg_to_rad(T.scullPitch * cos(TAU * 2.0 * u) * k)
	var push := RigMath.frac(T.pushAt + 0.08)
	p.root_y = -T.bob * cos(TAU * 2.0 * (u - push))
	if juice:
		RigMath.squash(p, B.TORSO, T.squash * sin(TAU * 2.0 * (u - push)))
	RigMath.derive_bones(rig, p, WAIST_FOLLOW)
	return 0.0


## Crawl arm angle (degrees, -180 overhead .. 180 overhead again through the pull and recovery).
static func windmill(u: float) -> float:
	var T: Dictionary = S.T.surface
	var a: float = T.warp
	var c: float = T.warpSlow + 0.5
	var g := u + a / TAU * (sin(TAU * (u - c)) - sin(-TAU * c))
	return -180.0 + 360.0 * g


func sample_surface(p: RigPose, u: float, juice: bool) -> float:
	var T: Dictionary = S.T.surface
	p.reset()
	for side in SIDES:
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		var a := windmill(RigMath.frac(u + (0.0 if side == "front" else 0.5)))
		var pull_end: float = T.pullEnd
		var flex := 0.0
		var pitch := 0.0
		if a <= pull_end:
			var k := (a + 180.0) / (pull_end + 180.0)
			flex = T.pullFlex * sin(PI * k)
			pitch = T.pullPitch * sin(PI * k)
		else:
			var k := (a - pull_end) / (180.0 - pull_end)
			flex = wrapf(trk_once("surface.recoverDir", k) - 90.0 - a, -180.0, 180.0)
			pitch = T.recoverPitch * sin(PI * k)
		p.rot[upper] = deg_to_rad(a)
		p.rot[upper + 1] = deg_to_rad(flex)
		p.rot[upper + 2] = deg_to_rad(pitch)
	for side in SIDES:
		var leg: RigData.Leg = rig.legs[side]
		var ph: float = TAU * (T.kickBeats * u + (0.0 if side == "front" else 0.5))
		p.rot[leg.thigh] = deg_to_rad(T.kickThigh * sin(ph))
		p.rot[leg.shin] = deg_to_rad(T.kickKnee + T.kickKneeAmp * maxf(0.0, sin(ph - 0.9)))
		p.rot[leg.foot] = deg_to_rad(T.footPoint + 8.0 * sin(ph - 0.5))
	var wave: float = T.torsoWave * sin(TAU * 2.0 * u)
	p.rot[B.TORSO] = deg_to_rad(wave)
	var bw := clampf((u - T.breathFrom) / (T.breathTo - T.breathFrom), 0.0, 1.0)
	var breath := sin(PI * bw)
	breath = breath * breath * (3.0 - 2.0 * breath)
	p.rot[B.NECK] = deg_to_rad(T.neck - T.breathTurn * breath - wave)
	p.y[B.NECK] = -T.breathLift * breath
	p.root_y = T.bob * sin(TAU * 2.0 * u)
	if juice:
		RigMath.squash(p, B.NECK, -0.04 * breath)
	RigMath.derive_bones(rig, p, WAIST_FOLLOW)
	return breath


func sample_under(p: RigPose, u: float, juice: bool) -> float:
	var T: Dictionary = S.T.under
	p.reset()
	for side in SIDES:
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		var uu := RigMath.frac(u - (0.0 if side == "front" else T.armLag))
		p.rot[upper] = deg_to_rad(trk("under.upper", uu) + (0.0 if side == "front" else T.farSpread))
		p.rot[upper + 1] = deg_to_rad(trk("under.fore", uu))
		p.rot[upper + 2] = deg_to_rad(trk("under.hand", uu))
	for side in SIDES:
		var leg: RigData.Leg = rig.legs[side]
		var s := 0.0 if side == "front" else 1.0
		p.rot[leg.thigh] = deg_to_rad(trk("under.thigh", u) + s * T.legSpread)
		p.rot[leg.shin] = deg_to_rad(trk("under.shin", u) - s * T.legSpread)
		p.rot[leg.foot] = deg_to_rad(trk("under.foot", u))
	var torso := trk("under.torso", u)
	p.rot[B.TORSO] = deg_to_rad(torso)
	p.rot[B.NECK] = deg_to_rad(trk("under.neck", u) - torso * 0.5)
	p.y[B.HIP] = trk("under.surge", u)
	if juice:
		var kw := clampf((u - T.kickFrom) / (T.kickTo - T.kickFrom), 0.0, 1.0)
		var k := sin(PI * kw) * (1.0 - kw)
		p.root_sy = 1.0 + T.kickStretch * k * 1.5
		p.root_sx = 1.0 - T.kickStretch * 0.6 * k * 1.5
	RigMath.derive_bones(rig, p, WAIST_FOLLOW)
	var bw := clampf((u - T.breathFrom) / (T.breathTo - T.breathFrom), 0.0, 1.0)
	return sin(PI * bw)


func sample_float(p: RigPose, u: float, juice: bool) -> float:
	var T: Dictionary = S.T.idle
	p.reset()
	var w := sin(TAU * u)
	var torso: float = T.torso + T.torsoWave * sin(TAU * (u - 0.15))
	p.rot[B.TORSO] = deg_to_rad(torso)
	p.rot[B.NECK] = deg_to_rad(T.neck - torso * 0.4 + 2.0 * sin(TAU * (u - 0.3)))
	for side in SIDES:
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		var k := 1.0 if side == "front" else -1.0
		var sw := sin(TAU * (u + (0.0 if side == "front" else 0.5)))
		p.rot[upper] = deg_to_rad(T.upper[side] + T.scullUpper * sw)
		p.rot[upper + 1] = deg_to_rad(T.fore[side] + T.scullFore * sin(TAU * (u - 0.12)) * k)
		p.rot[upper + 2] = deg_to_rad(T.scullPitch * cos(TAU * u) * k)
	for side in SIDES:
		var leg: RigData.Leg = rig.legs[side]
		var o := 0.0 if side == "front" else 0.5
		p.rot[leg.thigh] = deg_to_rad(T.thigh + T.thighWave * sin(TAU * (u + o)) - (0.0 if side == "front" else 6.0))
		p.rot[leg.shin] = deg_to_rad(T.shin + T.shinWave * sin(TAU * (u + o - 0.15)))
		p.rot[leg.foot] = deg_to_rad(T.foot + 8.0 * sin(TAU * (u + o - 0.3)))
	p.y[B.HIP] = -T.bob * w
	if juice:
		RigMath.squash(p, B.TORSO, 0.015 * sin(TAU * (u - 0.1)))
	RigMath.derive_bones(rig, p, WAIST_FOLLOW)
	return 0.0


# ---------------------------------------------------------------------------------------------
# FX emitters (RigFx custom): e_x/e_y is the spawn point, e_ground the water line.

## Bubbles rising and wobbling from the spawn point, staggered, popping at the end.
static func emit_bubbles(fx: RigFx, ev: Dictionary) -> void:
	var sprite := fx.rig.fx_sprite("swimBubble").id
	var n: int = ev.get("count", 4)
	for i in n:
		var r1 := fx.rand(i * 4)
		var r2 := fx.rand(i * 4 + 1)
		var r3 := fx.rand(i * 4 + 2)
		var age: float = fx.e_age - r1 * ev.get("stagger", 0.3)
		var life: float = fx.e_life * (0.6 + 0.4 * r3) - ev.get("stagger", 0.3) * r1
		if age < 0.0 or age >= life:
			continue
		var k := age / life
		var rise: float = ev.get("rise", 60.0) * (0.7 + 0.6 * r2)
		var x: float = fx.e_x + (r2 - 0.5) * ev.get("spread", 10.0) + ev.get("wobble", 4.0) * sin(age * 9.0 + r3 * 6.0)
		var y: float = fx.e_y - rise * age - 30.0 * age * age
		var frame := 2 if k > 0.86 else (1 if r3 > 0.55 else 0)
		fx.add(sprite, frame, x, y, 1.0)


## Droplets thrown up from the water line that fall back into it, plus foam at the base.
static func emit_splash(fx: RigFx, ev: Dictionary) -> void:
	var drop := fx.rig.fx_sprite("swimDrop").id
	var n: int = ev.get("count", 6)
	var speed: float = ev.get("speed", 240.0)
	var g: float = ev.get("gravity", 1500.0)
	for i in n:
		var r1 := fx.rand(i * 3)
		var r2 := fx.rand(i * 3 + 1)
		var r3 := fx.rand(i * 3 + 2)
		var vx: float = (r1 - 0.5) * speed * 0.9
		var vy := -speed * (0.5 + 0.5 * r2)
		var t := fx.e_age
		var x: float = fx.e_x + (r3 - 0.5) * ev.get("spread", 16.0) + vx * t
		var y := fx.e_y + vy * t + 0.5 * g * t * t
		if t > 0.02 and y > fx.e_ground:
			continue
		var frame := 0 if vy + g * t < 0.0 else 1
		fx.add(drop, frame, x, y, RigFx.fade_end(t / fx.e_life))
	var foam := fx.rig.fx_sprite("swimFoam").id
	var nf: int = ev.get("foam", 2)
	var k := fx.e_age / fx.e_life
	for i in nf:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x: float = fx.e_x + side * (6.0 + 50.0 * fx.e_age * (1.0 + i * 0.5))
		fx.add(foam, mini(2, int(k * 3.0)), x, fx.e_ground, RigFx.stepped_alpha(k))


## Foam crests sliding apart along the water line.
static func emit_foam(fx: RigFx, ev: Dictionary) -> void:
	var foam := fx.rig.fx_sprite("swimFoam").id
	var n: int = ev.get("count", 2)
	var k := fx.e_age / fx.e_life
	for i in n:
		var r := fx.rand(i)
		var side := -1.0 if i % 2 == 0 else 1.0
		var x: float = fx.e_x + side * ((r * 0.5 + 0.25) * ev.get("spread", 20.0) + ev.get("speed", 50.0) * fx.e_age * (1.0 - k * 0.5))
		fx.add(foam, mini(2, int(k * 3.0 + r * 0.5)), x, fx.e_y, RigFx.stepped_alpha(k))


## Drips falling from a point (staggered) down to the water line.
static func emit_drips(fx: RigFx, ev: Dictionary) -> void:
	var drop := fx.rig.fx_sprite("swimDrop").id
	var n: int = ev.get("count", 5)
	var g: float = ev.get("gravity", 1300.0)
	for i in n:
		var r1 := fx.rand(i * 2)
		var r2 := fx.rand(i * 2 + 1)
		var t: float = fx.e_age - i * ev.get("stagger", 0.08) - r2 * 0.05
		if t < 0.0:
			continue
		var x: float = fx.e_x + (r1 - 0.5) * ev.get("spread", 24.0)
		var y := fx.e_y + 0.5 * g * t * t
		if y > fx.e_ground:
			continue
		fx.add(drop, 1 if t > 0.12 else 2, x, y, 1.0)
