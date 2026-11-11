extends RefCounted
## Flying kick (air only). Windup into the kick pose, then an open-ended dive (root motion forward
## and down) until the game reports contact through Adventurer.kick_impact() or the ground ends it.
## On contact: comic burst at the sole, hitstop (frozen pose), recoil back flip back and up, then
## the action finishes and the host returns to the air pose.
##
## Signals (action_event): &"hit_active" once when the leg arms (end of the windup, not sent if
## the contact came first), &"impact" when impact() runs.

const K := preload("res://rig/clips/kick_tuning.gd")
const B := preload("res://rig/rig_bone.gd")


static func create(rig: RigData) -> Dictionary:
	return {
		&"flying_kick": FlyingKick.new(rig),
		&"flying_kick_impact": FlyingKick.new(rig, K.T.sheetImpactAt),
	}


class FlyingKick extends RigAction:
	var tracks := {}
	var world := PackedFloat32Array()
	var frozen: RigPose
	var air: RigPose
	## Action time of the contact (-1 while diving).
	var impact_t := -1.0
	## Sheet variant: calls impact() itself at this action time (-1 = never).
	var auto_impact := -1.0
	## Pose sheet span.
	var sheet_duration := 0.0
	var _armed := false
	var _next_ghost := 0.0
	var _recoil_ghost := false
	var _windup_ghost := false

	func _init(rig_data: RigData, auto_impact_at := -1.0) -> void:
		super(rig_data)
		auto_impact = auto_impact_at
		id = &"flying_kick" if auto_impact < 0.0 else &"flying_kick_impact"
		requires = "air"
		ends_on_landing = true
		duration = INF
		var T: Dictionary = K.T
		max_turn = T.maxTurn
		sheet_duration = T.windup + 0.3 if auto_impact < 0.0 else auto_impact + T.hitstop + T.recoil
		var keys := {}
		for name in ["rootRot", "squash", "hipY", "hipX", "torso", "neck", "kickLeg", "tuckLeg", "armF", "armB"]:
			keys[name] = T[name]
		tracks = RigTrack.compile(keys)
		world = RigMath.create_world(rig)
		frozen = RigPose.new(rig)
		air = RigPose.new(rig)

	func begin(host) -> void:
		start_facing = host.facing
		duration = INF
		impact_t = -1.0
		_armed = false
		_windup_ghost = false
		_recoil_ghost = false
		_next_ghost = K.T.windup

	func sheet_setup(adv) -> void:
		adv.position += Vector2(-90.0, 30.0)

	## True while the foot can hit (armed and no contact yet), for games that poll.
	func is_hit_active(t: float) -> bool:
		return impact_t < 0.0 and t >= K.T.windup

	# ---------- timeline ----------

	## JS phase shown at action time t before the contact.
	func _dive_u(t: float) -> float:
		var T: Dictionary = K.T
		return lerpf(T.U_START, T.U_CONTACT, clampf(t / T.windup, 0.0, 1.0))

	## Seconds into the recoil (negative before it starts).
	func _recoil_time(t: float) -> float:
		return t - impact_t - K.T.hitstop if impact_t >= 0.0 else -1.0

	func _dive_offset(t: float) -> Vector2:
		var T: Dictionary = K.T
		var v0 := Vector2(T.windupVel[0], T.windupVel[1])
		var v1 := Vector2(T.diveVel[0], T.diveVel[1])
		var w: float = T.windup
		var tw := minf(t, w)
		var d := v0 * tw + (v1 - v0) * (tw * tw / (2.0 * w))
		if t > w:
			d += v1 * (minf(t, 1e5) - w)
		return d

	func root_motion(t: float) -> Vector2:
		if impact_t < 0.0:
			return _dive_offset(t)
		var d := _dive_offset(impact_t)
		var tr := _recoil_time(t)
		if tr > 0.0:
			var T: Dictionary = K.T
			var k := clampf(tr / T.recoil, 0.0, 1.0)
			var e := 1.0 - (1.0 - k) * (1.0 - k)
			d += Vector2(-T.recoilBack * e, -T.recoilUp * e)
		return d

	# ---------- pose ----------

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var T: Dictionary = K.T
		var tr := _recoil_time(t)
		if impact_t < 0.0 or tr <= 0.0:
			# Windup, dive, and the hitstop holding the contact pose.
			var tp := t if impact_t < 0.0 else impact_t
			_body(_dive_u(tp), tp, _dive_tilt(tp), pose, juice)
		else:
			var u := lerpf(T.U_CONTACT, T.U_FLIP_END, clampf(tr / T.recoil, 0.0, 1.0))
			var tilt := _dive_tilt(impact_t) * (1.0 - RigMath.smooth01(tr / T.tiltRelease))
			_body(u, t, tilt, pose, juice)
			# Contact before the leg armed: ease out of the frozen pose.
			if impact_t < T.windup and tr < T.earlyBlend:
				_body(_dive_u(impact_t), impact_t, _dive_tilt(impact_t), frozen, juice)
				frozen.blend_toward(pose, RigMath.smooth01(tr / T.earlyBlend))
				pose.copy_from(frozen)
			# Open into the air pose the host returns to.
			var ex: float = T.exitBlend
			if tr > T.recoil - ex:
				RigAir.sample_air(rig, air, T.exitAirVy, 0.0, juice, t)
				pose.blend_toward(air, RigMath.smooth01((tr - (T.recoil - ex)) / ex))
		if juice and impact_t >= 0.0:
			_contact_juice(t - impact_t, pose)
		pose.facing = start_facing
		pose.draw_order = 0

	## Extra forward tilt (degrees) that aims the straight leg along the dive.
	func _dive_tilt(t: float) -> float:
		return K.T.diveTilt * RigMath.smooth01(t / K.T.windup)

	func _tk(name: String, u: float) -> float:
		return (tracks[name] as RigTrack).sample(u)

	## Body at JS phase u; t (action time) drives the cloth.
	func _body(u: float, t: float, tilt: float, pose: RigPose, juice: bool) -> void:
		var T: Dictionary = K.T
		var J: Dictionary = T.juice
		RigLocomotion.sample_idle(rig, pose, 0.0, false)
		var piv: Array = T.pivot
		var angle := deg_to_rad(_tk("rootRot", u) + tilt)
		RigMath.spin_root(pose, atan2(sin(angle), cos(angle)), piv[0], piv[1])
		if juice:
			var s := _tk("squash", u)
			var amount: float = s * J.takeoffStretch
			pose.root_sy = 1.0 - amount
			pose.root_sx = 1.0 + amount * 0.7
		pose.x[B.HIP] = _tk("hipX", u)
		pose.y[B.HIP] = _tk("hipY", u)
		pose.rot[B.TORSO] = deg_to_rad(_tk("torso", u))
		pose.rot[B.NECK] = deg_to_rad(_tk("neck", u))
		pose.rot[B.UPPER_ARM_F] = deg_to_rad(_tk("armF0", u))
		pose.rot[B.FORE_ARM_F] = deg_to_rad(_tk("armF1", u))
		pose.rot[B.UPPER_ARM_B] = deg_to_rad(_tk("armB0", u))
		pose.rot[B.FORE_ARM_B] = deg_to_rad(_tk("armB1", u))
		_leg(pose, "front", [T.legHang, T.legChamber, T.legKick], _tk("kickLeg", u))
		_leg(pose, "back", [T.legHang, T.legTuck], _tk("tuckLeg", u))
		# Cloth trails the motion; JS airborne envelope, flutter on game time.
		var airborne := sin(PI * clampf((u - 0.28) / (0.74 - 0.28), 0.0, 1.0))
		var flutter: float = sin(TAU * J.diveFlutterHz * t) * airborne
		pose.rot[B.SCARF1] = deg_to_rad(-18.0 + 26.0 * airborne + 8.0 * flutter)
		pose.rot[B.SCARF2] = deg_to_rad(14.0 * airborne - 12.0 * flutter)
		pose.rot[B.HAIR] = deg_to_rad(-6.0 * airborne)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)

	## Piecewise blend through the leg shapes by p, solved from the hip joint (always airborne).
	func _leg(pose: RigPose, side: String, shapes: Array, p: float) -> void:
		var i := clampi(floori(p), 0, shapes.size() - 2)
		var w := clampf(p - i, 0.0, 1.0)
		var a: Array = shapes[i]
		var b: Array = shapes[i + 1]
		var leg: RigData.Leg = rig.legs[side]
		var jx := rig.bone_x[B.HIP] + pose.x[B.HIP] + leg.hip_x
		var jy := rig.bone_y[B.HIP] + pose.y[B.HIP] + leg.hip_y
		RigMath.solve_leg(rig, pose, side, jx + lerpf(a[0], b[0], w), jy + lerpf(a[1], b[1], w), deg_to_rad(lerpf(a[2], b[2], w)))

	## Shake, flash and cloth spring after the contact (age since impact()).
	func _contact_juice(age: float, pose: RigPose) -> void:
		var J: Dictionary = K.T.juice
		if age < J.springLife:
			var spring: float = J.springAmp * exp(-age / J.springDecay) * sin(TAU * J.springFreq * age) * (1.0 - age / J.springLife)
			pose.rot[B.SCARF1] += deg_to_rad(spring)
			pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.3)
			pose.rot[B.HAIR] += deg_to_rad(spring * 0.5)
		if age < J.shakeSeconds:
			var decay: float = pow(1.0 - age / J.shakeSeconds, 2.0)
			var ph: float = TAU * J.shakeFreq * age
			pose.shake_x = J.shakeAmp * decay * sin(ph)
			pose.shake_y = J.shakeAmp * 0.6 * decay * sin(ph * 1.3 + 1.0)
		if age < J.flashSeconds:
			pose.flash = J.flash

	# ---------- game hooks ----------

	func tick(host, _delta: float) -> bool:
		var T: Dictionary = K.T
		var J: Dictionary = T.juice
		var t: float = host.action_elapsed()
		if auto_impact >= 0.0 and impact_t < 0.0 and t >= auto_impact:
			impact(host)
		if impact_t < 0.0:
			if not _windup_ghost and t >= J.windupGhost.at:
				_windup_ghost = true
				host.spawn_fx_local("ghost", J.windupGhost, Vector2.ZERO)
			if not _armed and t >= T.windup:
				_armed = true
				host.action_event.emit(id, &"hit_active")
			if t >= _next_ghost:
				_next_ghost = t + J.diveGhost.every
				host.spawn_fx_local("ghost", J.diveGhost, Vector2.ZERO)
		elif not _recoil_ghost and _recoil_time(t) >= J.recoilGhost.at:
			_recoil_ghost = true
			host.spawn_fx_local("ghost", J.recoilGhost, Vector2.ZERO)
		return false

	## Contact (Adventurer.kick_impact): burst at the sole, hitstop, recoil. Once per kick.
	func impact(host) -> void:
		if impact_t >= 0.0:
			return
		var T: Dictionary = K.T
		var J: Dictionary = T.juice
		impact_t = host.action_elapsed()
		duration = impact_t + T.hitstop + T.recoil
		if host.juice:
			var p := contact_point(host)
			var params: Dictionary = J.impact.merged({"emit": _emit_impact})
			host.fx.spawn("custom", params, p.x, p.y, 0.0, host.pose.facing, p.y + 4000.0, host.now())
			host.fx.spawn("spark", J.spark, p.x, p.y, 0.0, host.pose.facing, p.y + 4000.0, host.now())
		host.action_event.emit(id, &"impact")

	## World point of the sole contact on the kicking boot.
	func contact_point(host) -> Vector2:
		var sole: Array = K.T.sole
		RigMath.compute_world(rig, host.pose, world)
		return host.global_position + RigMath.point(world, B.FOOT_F, sole[0], sole[1])

	## World direction of the kick (hip joint to the ankle of the kicking leg).
	func kick_direction(host) -> Vector2:
		RigMath.compute_world(rig, host.pose, world)
		var hip := RigMath.point(world, B.THIGH_F, 0.0, 0.0)
		var ankle := RigMath.point(world, B.FOOT_F, 0.0, 0.0)
		return (ankle - hip).normalized()

	## Comic impact: burst plus radial lines on the 45 degree directions away from the kicker.
	func _emit_impact(fx: RigFx, ev: Dictionary) -> void:
		var k := fx.e_age / fx.e_life
		var frame := 0 if k < 0.12 else (1 if k < 0.5 else (2 if k < 0.78 else 3))
		fx.add(fx.rig.fx_sprite("kickBurst").id, frame, fx.e_x, fx.e_y)
		var line := fx.rig.fx_sprite("kickLine").id
		var dist: float = ev.radius + ev.speed * fx.e_age
		for i in range(-2, 3):
			var a := fx.mirror_angle(i * TAU / 8.0)
			fx.add(line, 0 if k < 0.6 else 1, fx.e_x + cos(a) * dist, fx.e_y + sin(a) * dist, 1.0, 1.0, 1.0, a)
