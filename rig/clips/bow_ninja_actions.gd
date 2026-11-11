class_name BowNinjaActions
extends RefCounted
## Bow (bow.js) as game actions, the bow string node, and the ninja kunai strike (ninja.js).
##
## Bow: bow_draw (grab, raise, nock, draw) chains into bow_aim (open-ended full draw that follows
## Adventurer.set_bow_aim). bow_aim ends with bow_release (shot, event &"release") or bow_cancel
## (lowers the bow without shooting). The aim angle and power are read live from
## host.action_params while drawing and aiming; release and cancel keep the values they started with.
## Ninja: ninja_strike (crouch, smoke vanish, dash with ghosts, reverse-grip cut with the slash,
## event &"hit", recovery into idle at the arrival point); the advance leaves as root motion.

const X := preload("res://rig/clips/bow_ninja_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7
const BOW_IDS: Array[StringName] = [&"bow_draw", &"bow_aim", &"bow_release", &"bow_cancel"]
## Pose sheet variants of bow_aim: [id, aim degrees, power].
const AIM_SHEETS := [
	[&"bow_aim_m80_p03", -80.0, 0.3], [&"bow_aim_m80_p10", -80.0, 1.0],
	[&"bow_aim_m40_p03", -40.0, 0.3], [&"bow_aim_m40_p10", -40.0, 1.0],
	[&"bow_aim_0_p03", 0.0, 0.3], [&"bow_aim_0_p10", 0.0, 1.0],
	[&"bow_aim_p45_p03", 45.0, 0.3], [&"bow_aim_p45_p10", 45.0, 1.0],
]


static func create(rig: RigData) -> Dictionary:
	var out := {}
	for mode in BowAction.Mode.values():
		var a := BowAction.new(rig, mode)
		out[a.id] = a
	for s: Array in AIM_SHEETS:
		var p := BowAction.new(rig, BowAction.Mode.AIM)
		p.id = s[0]
		p.sheet_aim = deg_to_rad(s[1])
		p.sheet_power = s[2]
		p.sheet_duration = 0.6
		out[p.id] = p
	var n := NinjaStrike.new(rig)
	out[n.id] = n
	return out


static func attach(host) -> void:
	var node := BowString.new()
	node.name = "BowString"
	host._parts_node.add_child(node)
	node.setup(host)


## Bow carry: the bow arm in a low ready at the hip over the base pose (see GunActions.carry_arm).
static func carry_bow(pose: RigPose) -> void:
	GunActions.carry_arm(pose, X.BOW.carry, X.BOW.carry)


# ---------- ninja FX ----------

## Vanish poof: puffs burst out from the body, rise and break up at full opacity.
static func _emit_poof(fx: RigFx, ev: Dictionary) -> void:
	var puff := fx.rig.fx_sprite("ninjaPuff").id
	var n: int = ev.get("count", 7)
	var k := fx.e_age / fx.e_life
	var spread := 1.0 - pow(1.0 - k, 4.0)
	for i in n:
		var a := (float(i) / n) * TAU + fx.rand(i) * 0.6
		var r: float = ev.get("radius", 40.0) * (0.35 + 0.65 * fx.rand(i + 50)) * spread
		var x := fx.e_x + cos(a) * r
		var y: float = fx.e_y + sin(a) * r * 1.3 - ev.get("rise", 30.0) * k
		var local := k + fx.rand(i + 90) * 0.15
		var frame := 0 if local < 0.12 else (1 if local < 0.5 else (2 if local < 0.8 else 3))
		fx.add(puff, frame, x, y)


## Crescent slash at the cut, mirrored with the facing.
static func _emit_slash(fx: RigFx, ev: Dictionary) -> void:
	var k := fx.e_age / fx.e_life
	var s := maxf(1.0, roundf(ev.get("scale", 1.0) * (0.9 + 0.3 * k)))
	fx.add(fx.rig.fx_sprite("ninjaSlash").id, int(k * 3.0), fx.e_x, fx.e_y, 1.0 - k * k, s * fx.e_facing, s, ev.get("angle", 0.0) * fx.e_facing)


# ---------------------------------------------------------------------------------------------

class BowAction extends RigAction:
	const X := preload("res://rig/clips/bow_ninja_tuning.gd")
	enum Mode { DRAW, AIM, RELEASE, CANCEL }

	var mode := Mode.DRAW
	var host_ref: WeakRef
	## Aim (radians) and power used by release and cancel (taken from the host when they start).
	var _aim := 0.0
	var _power := 1.0
	## Pose sheet overrides (NAN = read the host).
	var sheet_aim := NAN
	var sheet_power := NAN
	var sheet_duration := 0.0
	var world := PackedFloat32Array()
	var scratch: RigPose
	var tk := {}
	var path: Array[RigTrack] = []
	var bow_bit := 0
	var arrow_bit := 0
	var grip_len_f := 0.0
	var grip_len_b := 0.0
	var rest_offset := 0.0
	var draw_offset := 0.0
	var draw_point := Vector2.ZERO
	var path_end := 0.0
	var _target := Vector2.ZERO

	func _init(rig_data: RigData, m: int) -> void:
		super(rig_data)
		mode = m
		var T: Dictionary = X.BOW
		id = BowNinjaActions.BOW_IDS[m]
		requires = "ground"
		max_turn = T.maxTurn if m == Mode.AIM else 0.0
		world = RigMath.create_world(rig)
		scratch = RigPose.new(rig)
		bow_bit = rig.props.bow.bit if rig.props.has("bow") else 0
		arrow_bit = rig.props.arrow.bit if rig.props.has("arrow") else 0
		grip_len_f = rig.bone_y[B.GRIP_F]
		grip_len_b = rig.bone_y[B.GRIP_B]
		var string_x := -45.0
		if rig.props.has("bow"):
			var pts: Dictionary = rig.props.bow.points
			var grip: Vector2 = rig.props.bow.pivot
			string_x = (pts.stringTop.x + pts.stringBottom.x) * 0.5 - grip.x
		var arrow_len := 120.0
		if rig.props.has("arrow"):
			arrow_len = rig.props.arrow.points.tip.x - rig.props.arrow.points.nock.x
		rest_offset = string_x
		draw_offset = T.tipPastGrip - arrow_len
		var ba := deg_to_rad(T.bowAngle)
		var nock_at := _nock(Vector2(T.bowGripNock[0], T.bowGripNock[1]), 0.0, ba)
		draw_point = _nock(Vector2(T.bowGrip[0], T.bowGrip[1]), 1.0, ba)
		# Front hand path keys in seconds; snappy onto the string and right after the release.
		var fp: Array = T.frontPath
		var keys := [[], [], []]
		for i in fp.size():
			var k: Array = fp[i]
			var v: Array = [k[1], k[2], k[3]] if k.size() > 2 else ([nock_at.x, nock_at.y, T.bowAngle] if k[1] == "nock" else [draw_point.x, draw_point.y, T.bowAngle])
			var ease := "out" if (k[1] is String and k[1] == "nock") or (i > 0 and fp[i - 1][1] is String and fp[i - 1][1] == "draw") else "inOut"
			for c in 3:
				keys[c].append([k[0], v[c], ease])
		for c in 3:
			path.append(RigTrack.from_keys(keys[c]))
		path_end = fp[fp.size() - 1][0]
		var J: Dictionary = T.juice
		var R: float = T.releaseAt
		var D: float = T.duration
		var tracks := {
			"raise": [[0, 0], [0.72, 1.0 + T.bowRaiseOvershoot], [1, 1]],
			"kick": [[0, 0], [R, 0], [R + T.bowKickSeconds[0], 1, "out"], [R + T.bowKickSeconds[1], 0, "back"]],
			"drop": [[0, 0], [0.1, 0], [0.26, T.anticipationDrop], [0.55, 1.5, "back"], [1.78, 1.5], [2.2, 0]],
			"torso": [[0, 0], [0.3, 0], [0.62, -1.5], [T.drawEnd, T.drawLean], [R, T.drawLean], [R + 0.06, T.drawLean + T.releaseRecoil, "out"], [1.8, -1], [2.25, 0]],
			"neck": [[0, 0], [0.4, 0], [0.62, T.headAim * 0.5], [T.drawEnd, T.headAim], [R, T.headAim], [R + 0.08, T.headRelease, "out"], [1.9, 0, "back"]],
			"squash": [[0, 0], [0.08, 0], [0.24, 1], [0.4, 0, "back"], [0.66, 0], [T.drawEnd, -J.drawStretch / J.squash], [R, -J.drawStretch / J.squash], [R + 0.04, J.releaseSquash / J.squash, "out"], [R + 0.2, 0, "back"]],
		}
		tk = RigTrack.compile(tracks)
		match mode:
			Mode.DRAW:
				duration = T.drawEnd
				next_state = "action:bow_aim"
				cancel_by.assign([&"bow_cancel"])
			Mode.AIM:
				duration = INF
				sheet_duration = 1.0
				cancel_by.assign([&"bow_release", &"bow_cancel"])
			Mode.RELEASE:
				duration = D - R
				events = [
					{"t": 0.0, "signal": &"release"},
					{"t": 0.0, "fx": "spark", "anchor": "arrow.nock", "params": J.snap},
				]
			Mode.CANCEL:
				duration = T.drawEnd / T.cancelSpeed
		if mode != Mode.AIM:
			sheet_duration = duration

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)
		_aim = _live_aim()
		_power = _live_power()

	func sheet_setup(adv) -> void:
		adv.set_weapon(&"bow")
		if mode == Mode.RELEASE or mode == Mode.CANCEL:
			# Start from a settled aim, as in the game.
			adv.set_bow_aim(deg_to_rad(-25.0), 1.0)
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.play_action(&"bow_aim")
			for i in 36:
				adv.set_locomotion(0.0, 1.0 / 120.0)

	func _host():
		return host_ref.get_ref() if host_ref else null

	func _live_aim() -> float:
		var T: Dictionary = X.BOW
		var a := 0.0
		if not is_nan(sheet_aim):
			a = sheet_aim
		else:
			var h = _host()
			if h:
				a = h.action_params.get(&"bow_aim", 0.0)
		return clampf(a, deg_to_rad(T.aimMin), deg_to_rad(T.aimMax))

	func _live_power() -> float:
		if not is_nan(sheet_power):
			return sheet_power
		var h = _host()
		return clampf(h.action_params.get(&"bow_power", 1.0), 0.0, 1.0) if h else 1.0

	## JS clip time shown at action time t.
	func clip_time(t: float) -> float:
		var T: Dictionary = X.BOW
		match mode:
			Mode.DRAW:
				return minf(t, T.drawEnd)
			Mode.AIM:
				return T.drawEnd
			Mode.RELEASE:
				return minf(T.releaseAt + t, T.duration)
		return maxf(0.0, T.drawEnd - t * T.cancelSpeed)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var live := mode == Mode.DRAW or mode == Mode.AIM
		var aim := _live_aim() if live else _aim
		var power := _live_power() if live else _power
		var trem := 0.0
		if mode == Mode.AIM:
			var T: Dictionary = X.BOW
			trem = T.tremor * (0.4 + 0.6 * clampf(t / T.tremorRamp, 0.0, 1.0)) * _draw_amount(power)
		body(clip_time(t), X.BOW.drawEnd + t, aim, power, trem, pose, juice)
		pose.facing = start_facing

	func _draw_amount(power: float) -> float:
		return lerpf(X.BOW.powerMin, 1.0, power)

	## Nock point (torso-local) riding the string: draw 0 rest, 1 full; g is the bow grip.
	func _nock(g: Vector2, draw: float, angle: float) -> Vector2:
		var x := rest_offset + (draw_offset - rest_offset) * draw
		var y: float = -X.BOW.arrowAboveGrip
		return Vector2(g.x + x * cos(angle) - y * sin(angle), g.y + x * sin(angle) + y * cos(angle))

	func _tk(name: String, tj: float) -> float:
		return (tk[name] as RigTrack).sample(tj)

	## The JS bow pose at clip time tj, rotated to the aim; tt drives the tremor, trem its amplitude.
	func body(tj: float, tt: float, aim: float, power: float, trem: float, pose: RigPose, juice: bool) -> void:
		var T: Dictionary = X.BOW
		var J: Dictionary = T.juice
		var R: float = T.releaseAt
		RigLocomotion.sample_idle(rig, pose, 0.0, juice)
		pose.props |= bow_bit
		if tj >= T.grabAt and tj < R:
			pose.props |= arrow_bit
		var raise := clampf((tj - T.bowRaise[0]) / (T.bowRaise[1] - T.bowRaise[0]), 0.0, 1.0)
		var lower := clampf((tj - T.bowLower[0]) / (T.bowLower[1] - T.bowLower[0]), 0.0, 1.0)
		var weight_b := _tk("raise", raise) * (1.0 - RigMath.smooth01(lower))
		var aw := clampf(weight_b, 0.0, 1.0)

		pose.y[B.HIP] += _tk("drop", tj)
		pose.x[B.HIP] += T.aimHip * aim * aw
		pose.rot[B.TORSO] += deg_to_rad(_tk("torso", tj)) + aim * T.aimTorso * aw
		pose.rot[B.NECK] += deg_to_rad(_tk("neck", tj))
		if juice:
			RigMath.squash(pose, B.TORSO, J.squash * _tk("squash", tj))
			var ts := tj - R
			if ts >= 0.0:
				var spring: float = J.springAmp * exp(-ts / J.springDecay) * sin(TAU * J.springFreq * ts)
				pose.rot[B.HAIR] += deg_to_rad(spring * 0.5)
				pose.rot[B.SCARF1] += deg_to_rad(spring)
				pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
				if ts < J.shakeSeconds:
					var decay: float = pow(1.0 - ts / J.shakeSeconds, 2.0)
					pose.shake_x = J.shakeAmp * decay * sin(TAU * J.shakeFreq * ts)
		RigMath.plant_legs(rig, pose)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)

		var f: float = T.tremorFreq
		var tx := trem * (sin(TAU * f * tt) * 0.6 + sin(TAU * f * 1.7 * tt + 1.0) * 0.4)
		var ty := trem * (sin(TAU * f * 1.3 * tt + 2.0) * 0.7 + sin(TAU * f * 2.3 * tt) * 0.3)

		# Aim: the local grip angle that points the arrow along the aim, reached by swinging the bow
		# arm targets around the bow shoulder.
		RigMath.compute_world(rig, pose, world)
		var torso_angle := RigMath.bone_angle(world, B.TORSO)
		var base := deg_to_rad(T.bowAngle)
		var theta := lerpf(base, wrapf(aim - torso_angle, -PI, PI), aw)
		var swing := theta - base
		var shoulder := Vector2(rig.bone_x[B.UPPER_ARM_B] + pose.x[B.UPPER_ARM_B], rig.bone_y[B.UPPER_ARM_B] + pose.y[B.UPPER_ARM_B])

		# The head turns with the swing so the full-draw nock stays at the jaw.
		var neck := Vector2(rig.bone_x[B.NECK] + pose.x[B.NECK], rig.bone_y[B.NECK] + pose.y[B.NECK])
		var jaw := shoulder + (draw_point - shoulder).rotated(swing)
		var follow := wrapf((jaw - neck).angle() - (draw_point - neck).angle(), -PI, PI)
		var lim := deg_to_rad(T.aimNeckLimit)
		pose.rot[B.NECK] += clampf(follow * T.aimNeck, -lim, lim)

		# The bow arm leaves from and returns to the carry hold.
		BowNinjaActions.carry_bow(pose)
		pose.x[B.UPPER_ARM_F] += T.shoulderShift * aw
		var kick: float = T.bowKick * (J.bowKickBoost if juice else 1.0) * _tk("kick", tj)
		var push := RigMath.smooth01((tj - (T.nockAt + 0.02)) / (T.drawEnd - T.nockAt - 0.02))
		var draw := RigMath.smooth01((tj - (T.nockAt + 0.04)) / (T.drawEnd - T.nockAt - 0.04)) * _draw_amount(power)
		var g := Vector2(lerpf(T.bowGripNock[0], T.bowGrip[0], push), lerpf(T.bowGripNock[1], T.bowGrip[1], push))
		g = shoulder + (g - shoulder).rotated(swing) + Vector2(tx, ty)
		_grip_ik(pose, "back", g, theta + deg_to_rad(kick), weight_b, 1.0)

		var fin := RigMath.smooth01((tj - T.frontIn[0]) / (T.frontIn[1] - T.frontIn[0]))
		var fout := RigMath.smooth01((tj - T.frontOut[0]) / (T.frontOut[1] - T.frontOut[0]))
		var weight_f := fin * (1.0 - fout)
		if tj >= T.nockAt and tj < R:
			_grip_ik(pose, "front", _nock(g, draw, theta), theta, weight_f, T.drawBend)
		else:
			var p := Vector2(path[0].sample(tj), path[1].sample(tj))
			if tj >= R and tj < path_end:
				# Released from a partial draw: start the follow-through from the actual nock.
				var s := (tj - R) / (path_end - R)
				var off := Vector2((_draw_amount(power) - 1.0) * (draw_offset - rest_offset), 0.0).rotated(base)
				p += off * (1.0 - s) * (1.0 - s)
			p = shoulder + (p - shoulder).rotated(swing * aw)
			_grip_ik(pose, "front", p, deg_to_rad(path[2].sample(tj)) + swing * aw, weight_f, T.drawBend)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)

	## Puts a hand's grip point (gripF/gripB origin) on a torso-local point with the grip axis at a
	## torso-local angle, blended with the forward-kinematics arm by weight.
	func _grip_ik(pose: RigPose, side: String, local: Vector2, angle: float, weight: float, bend: float) -> void:
		if weight <= 0.0:
			return
		var up := B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		var fore := up + 1
		var hand := up + 2
		var fk0 := pose.rot[up]
		var fk1 := pose.rot[fore]
		var fk2 := pose.rot[hand]
		RigMath.compute_world(rig, pose, world)
		var ga := angle + RigMath.bone_angle(world, B.TORSO)
		var target := RigMath.point(world, B.TORSO, local.x, local.y)
		var len := grip_len_f if side == "front" else grip_len_b
		RigMath.solve_arm(rig, pose, side, target.x - len * cos(ga), target.y - len * sin(ga), world, false, bend)
		RigMath.compute_world(rig, pose, world)
		pose.rot[hand] = ga - PI / 2.0 - RigMath.bone_angle(world, fore)
		pose.rot[up] = lerp_angle(fk0, pose.rot[up], weight)
		pose.rot[fore] = lerp_angle(fk1, pose.rot[fore], weight)
		pose.rot[hand] = lerp_angle(fk2, pose.rot[hand], weight)

	## String hookup at action time t: x = pull toward the drawing hand (0..1), y = vibration.
	func bow_string(t: float, juice: bool) -> Vector2:
		var T: Dictionary = X.BOW
		var tj := clip_time(t)
		var R: float = T.releaseAt
		if tj < R:
			return Vector2(clampf((tj - (T.nockAt - 0.03)) / 0.03, 0.0, 1.0), 0.0)
		var sv: Dictionary = T.stringVibe
		var age := tj - R
		var amp: float = sv.amplitude * (T.juice.stringVibeBoost if juice else 1.0)
		return Vector2(0.0, amp * exp(-age / sv.decay) * sin(TAU * sv.frequency * age))

	## World point and direction of the arrow tip when it leaves the string (the held arrow of the
	## last aim frame, without tremor).
	func arrow_release(host) -> Dictionary:
		var aim := _aim if mode == Mode.RELEASE else _live_aim()
		var power := _power if mode == Mode.RELEASE else _live_power()
		body(X.BOW.drawEnd, 0.0, aim, power, 0.0, scratch, false)
		scratch.facing = host.facing
		RigMath.compute_world(rig, scratch, world)
		var a := rig.anchor("arrow.tip")
		return {
			"point": host.global_position + RigMath.point(world, int(a.x), a.y, a.z),
			"direction": Vector2.from_angle(RigMath.bone_angle(world, int(a.x))),
		}


## 1 px pixel-art bow string (JS renderer drawString): top anchor, pull point toward the drawing
## hand, vibration across the string, bottom anchor. Drawn right after the bow sprite, in the
## character space of the parts node; redraws only when a string pixel moves.
class BowString extends Node2D:
	const X := preload("res://rig/clips/bow_ninja_tuning.gd")
	var host
	var bow_sprite: Sprite2D
	var top := Vector3(-1, 0, 0)
	var bottom := Vector3(-1, 0, 0)
	var hand := Vector3(-1, 0, 0)
	var cell := 6.0
	var color := Color.WHITE
	var _key := PackedInt32Array()
	var _shown := false

	func setup(h) -> void:
		host = h
		var rig: RigData = h.rig
		if not rig.part_index.has("bow"):
			return
		bow_sprite = h._sprites[rig.part_index["bow"]]
		top = rig.anchor("bow.stringTop")
		bottom = rig.anchor("bow.stringBottom")
		hand = rig.anchor("gripF")
		cell = float(X.BOW.stringPixel)
		color = Color.html(X.BOW.stringColor)
		_key.resize(6)
		visible = false

	func _process(_delta: float) -> void:
		if bow_sprite == null:
			return
		var parent := get_parent()
		var bi := bow_sprite.get_index()
		var mi := get_index()
		if mi != bi + 1:
			parent.move_child(self, bi + 1 if mi > bi else bi)
		var show := bow_sprite.visible and top.x >= 0.0 and bottom.x >= 0.0
		if show != _shown:
			_shown = show
			visible = show
		if not show:
			return
		var world: PackedFloat32Array = host._world
		var t := RigMath.point(world, int(top.x), top.y, top.z)
		var b := RigMath.point(world, int(bottom.x), bottom.y, bottom.z)
		var m := (t + b) * 0.5
		var s := Vector2.ZERO
		var action: RigAction = host.get_action(host.current_action()) if host.is_action_playing() else null
		if action and action.has_method("bow_string"):
			s = action.bow_string(host.action_elapsed(), host.juice)
		if s.x > 0.0:
			m += (RigMath.point(world, int(hand.x), hand.y, hand.z) - m) * s.x
		var d := b - t
		var len := maxf(d.length(), 1.0)
		m += Vector2(-d.y / len, d.x / len) * s.y
		var changed := _set_key(0, t.x)
		changed = _set_key(1, t.y) or changed
		changed = _set_key(2, m.x) or changed
		changed = _set_key(3, m.y) or changed
		changed = _set_key(4, b.x) or changed
		changed = _set_key(5, b.y) or changed
		if changed:
			queue_redraw()

	func _set_key(i: int, v: float) -> bool:
		var c := roundi(v / cell)
		if c == _key[i]:
			return false
		_key[i] = c
		return true

	func _draw() -> void:
		_line(_key[0], _key[1], _key[2], _key[3])
		_line(_key[2], _key[3], _key[4], _key[5])

	## Bresenham line of string pixels between two cells.
	func _line(x0: int, y0: int, x1: int, y1: int) -> void:
		var dx := absi(x1 - x0)
		var dy := -absi(y1 - y0)
		var sx := 1 if x0 < x1 else -1
		var sy := 1 if y0 < y1 else -1
		var err := dx + dy
		for guard in 2048:
			draw_rect(Rect2(x0 * cell - cell * 0.5, y0 * cell - cell * 0.5, cell, cell), color)
			if x0 == x1 and y0 == y1:
				break
			var e2 := 2 * err
			if e2 >= dy:
				err += dy
				x0 += sx
			if e2 <= dx:
				err += dx
				y0 += sy


# ---------------------------------------------------------------------------------------------

class NinjaStrike extends RigAction:
	const X := preload("res://rig/clips/bow_ninja_tuning.gd")
	var tk := {}
	var world := PackedFloat32Array()
	var kunai_bit := 0
	var hitstop := 0.0
	var end_a := 0.0
	var advance := 0.0
	var rest_f := 0.0
	var rest_b := 0.0
	var foot_b_from := Vector3.ZERO
	var _juice := true
	var sheet_duration := 0.0
	var _events_juice: Array = []
	var _events_plain: Array = []

	func _init(rig_data: RigData) -> void:
		super(rig_data)
		var N: Dictionary = X.NINJA
		id = &"ninja_strike"
		requires = "ground"
		max_turn = N.maxTurn
		tk = RigTrack.compile(N.tracks)
		world = RigMath.create_world(rig)
		kunai_bit = rig.props.kunai.bit if rig.props.has("kunai") else 0
		hitstop = N.juice.hitstop
		end_a = N.end
		var ff: Array = N.tracks.footF
		advance = ff[ff.size() - 1][1][0]
		rest_f = rig.rest_ankle_x("front")
		rest_b = rig.rest_ankle_x("back")
		var rf: float = N.recoverFrom
		foot_b_from = Vector3(_tk("footB0", rf), _tk("footB1", rf), _tk("footB2", rf))
		_events_juice = _build_events(true)
		_events_plain = _build_events(false)
		duration = end_a + hitstop
		sheet_duration = duration
		events = _events_juice

	func begin(host) -> void:
		start_facing = host.facing
		_juice = host.juice
		duration = end_a + (hitstop if _juice else 0.0)
		events = _events_juice if _juice else _events_plain

	func sheet_setup(adv) -> void:
		adv.set_weapon(&"kunai")
		adv.position.x -= 130.0

	func _tk(name: String, ta: float) -> float:
		return (tk[name] as RigTrack).sample(ta)

	## Game time -> animation time; the hitstop holds the cut (juice only).
	func _anim_t(t: float, juice: bool) -> float:
		var cut: float = X.NINJA.CUT_T
		if not juice or t <= cut:
			return minf(t, end_a)
		if t <= cut + hitstop:
			return cut
		return minf(t - hitstop, end_a)

	func _near(ta: float, a: float) -> float:
		return clampf(1.0 - absf(ta - a) / 0.08, 0.0, 1.0)

	func _real_t(ta: float, juice: bool) -> float:
		return ta + (hitstop if juice and ta > X.NINJA.CUT_T else 0.0)

	func _recover(ta: float) -> float:
		var N: Dictionary = X.NINJA
		return RigMath.smooth01((ta - N.recoverFrom) / (N.recoverTo - N.recoverFrom))

	## Forward displacement at animation time ta: the dash, then the step over the front foot.
	func _root_x(ta: float) -> float:
		var N: Dictionary = X.NINJA
		if ta < N.VANISH_T:
			return 0.0
		var s := minf((ta - N.VANISH_T) / (N.ARRIVE_T - N.VANISH_T), 1.0)
		return N.dashDistance * (1.0 - pow(1.0 - s, 3.0)) + advance * _recover(ta)

	func root_motion(t: float) -> Vector2:
		return Vector2(_root_x(_anim_t(t, _juice)), 0.0)

	func _build_events(juice: bool) -> Array:
		var N: Dictionary = X.NINJA
		var J: Dictionary = N.juice
		var dash: float = N.dashDistance
		var out: Array = []
		var at := func(ta: float) -> float: return _real_t(ta, juice)
		var vt: float = N.VANISH_T - 0.03
		out.append({"t": at.call(vt), "fx": "custom", "x": 10.0 - _root_x(vt), "y": -190.0, "params": J.poof.merged({"emit": BowNinjaActions._emit_poof})})
		out.append({"t": at.call(N.VANISH_T), "fx": "dust", "x": rest_b, "y": 0.0, "params": J.dust.merged({"dir": -1})})
		out.append({"t": at.call(N.VANISH_T), "fx": "ghost", "params": J.ghost})
		var pt: float = N.ARRIVE_T - 0.02
		out.append({"t": at.call(pt), "fx": "custom", "x": dash - 30.0 - _root_x(pt), "y": -140.0, "params": J.arrivePoof.merged({"emit": BowNinjaActions._emit_poof})})
		out.append({"t": at.call(N.ARRIVE_T), "fx": "dust", "x": rest_f + RigData.FOOT_TOE + advance, "y": 0.0, "params": J.dust.merged({"dir": 1, "count": 5})})
		var st: float = N.CUT_T - 0.03
		out.append({"t": at.call(st), "fx": "custom", "x": dash + J.slash.x - _root_x(st), "y": J.slash.y, "params": J.slash.merged({"emit": BowNinjaActions._emit_slash})})
		out.append({"t": at.call(N.CUT_T), "signal": &"hit"})
		out.append({"t": at.call(N.CUT_T), "fx": "spark", "anchor": "kunai.tip", "params": J.slashSpark})
		out.append({"t": at.call(N.recoverTo), "footstep": &"back", "strength": 0.5})
		out.append({"t": at.call(N.recoverTo), "fx": "dust", "x": rest_b, "y": 0.0, "params": J.stepDust})
		out.sort_custom(func(a, b): return a.t < b.t)
		return out

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var N: Dictionary = X.NINJA
		var J: Dictionary = N.juice
		var cut: float = N.CUT_T
		var ta := _anim_t(t, juice)
		RigLocomotion.sample_idle(rig, pose, 0.0, juice)
		pose.props |= kunai_bit
		pose.x[B.HIP] += _tk("hipX", ta)
		pose.y[B.HIP] += _tk("hipY", ta)
		pose.rot[B.TORSO] += deg_to_rad(_tk("torso", ta))
		pose.rot[B.NECK] += deg_to_rad(_tk("neck", ta))
		pose.rot[B.UPPER_ARM_F] += deg_to_rad(_tk("armF", ta))
		pose.rot[B.FORE_ARM_F] += deg_to_rad(_tk("elbowF", ta))
		pose.rot[B.UPPER_ARM_B] += deg_to_rad(_tk("armB", ta))
		pose.rot[B.FORE_ARM_B] += deg_to_rad(_tk("elbowB", ta))
		pose.rot[B.HAIR] += deg_to_rad(_tk("hair", ta))
		var scarf := _tk("scarf", ta)
		pose.rot[B.SCARF1] += deg_to_rad(scarf)
		pose.rot[B.SCARF2] += deg_to_rad(scarf * 0.6)
		# Reverse grip in over the crouch, twirled back to the forward grip at the end.
		var tw: Array = N.gripTwirl
		var grip: float = N.gripAngle * RigMath.smooth01(ta / N.gripIn) * (1.0 - RigMath.smooth01((ta - tw[0]) / (tw[1] - tw[0])))
		pose.rot[B.GRIP_F] = deg_to_rad(grip)

		# Legs: the front foot stays planted while the body advances over it; the back foot steps up.
		var rec := _recover(ta)
		var fa := RigMath.planted_ankle(rest_f + _tk("footF0", ta) - advance * rec, -_tk("footF1", ta), deg_to_rad(_tk("footF2", ta)))
		RigMath.solve_leg(rig, pose, "front", fa.x, fa.y, deg_to_rad(_tk("footF2", ta)))
		var bx := _tk("footB0", ta)
		var lift := _tk("footB1", ta)
		var roll := _tk("footB2", ta)
		if ta > N.recoverFrom:
			var w := clampf((ta - N.recoverFrom) / (N.recoverTo - N.recoverFrom), 0.0, 1.0)
			bx = lerpf(foot_b_from.x, 0.0, rec)
			lift = lerpf(foot_b_from.y, 0.0, rec) + sin(PI * w) * N.recoverLift
			roll = lerpf(foot_b_from.z, 0.0, rec) - sin(PI * w) * 8.0
		var ba := RigMath.planted_ankle(rest_b + bx, -lift, deg_to_rad(roll))
		RigMath.solve_leg(rig, pose, "back", ba.x, ba.y, deg_to_rad(roll))

		if juice:
			var s: Dictionary = J.squash
			RigMath.squash(pose, B.TORSO, s.crouch * _near(ta, 0.16) + s.dash * _near(ta, 0.28) + s.cut * _near(ta, cut + 0.02) + s.settle * _near(ta, N.recoverTo + 0.04))
			# Elbows trail the shoulder swing.
			var h := 0.0076
			var vel := (_tk("armF", minf(ta + h, end_a)) - _tk("armF", maxf(ta - h, 0.0))) / (2.0 * h)
			vel *= clampf(ta / h, 0.0, 1.0) * clampf((end_a - ta) / h, 0.0, 1.0)
			pose.rot[B.FORE_ARM_F] += deg_to_rad(clampf(vel / 900.0, -1.0, 1.0) * J.elbowLag)
			# Cloth spring after the cut, faded out before the end.
			var ts := ta - cut
			if ts >= 0.0:
				var spring: float = clampf((end_a - ta) / 0.2, 0.0, 1.0) * J.springAmp * exp(-ts / J.springDecay) * sin(TAU * J.springFreq * ts)
				pose.rot[B.HAIR] += deg_to_rad(spring * 0.6)
				pose.rot[B.SCARF1] += deg_to_rad(spring)
				pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
				pose.rot[B.NECK] += deg_to_rad(spring * 0.2)
			var cs := t - cut
			if cs >= 0.0 and cs < J.shakeSeconds:
				var decay: float = pow(1.0 - cs / J.shakeSeconds, 2.0)
				var ph: float = TAU * J.shakeFreq * cs
				pose.shake_x = J.shakeAmp * decay * sin(ph)
				pose.shake_y = J.shakeAmp * 0.6 * decay * sin(ph * 1.3 + 1.0)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		pose.facing = start_facing
