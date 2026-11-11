class_name GunActions
extends RefCounted
## Guns: the JS shoot, cock and rifle clips as game actions over the host's ground pose (idle or
## locomotion) with the weapon carry, aimed with Adventurer.set_gun_aim (LT) and fired with RT.
##
## Carry: apply_carry holds the equipped revolver low at the side and the AK low across the body
## while no action plays.
## Revolver: revolver_aim (game loop, INF) raises from the carry when entered directly and follows
## the aim angle. revolver_fire (&"shot") chains into revolver_recock (&"click") and back into the
## aim; revolver_cock (&"click", chest flourish) returns to the aim; revolver_draw chains into the
## aim; revolver_holster lowers to the carry. The hammer state carries between actions.
## Rifle: rifle_raise chains into rifle_aim (INF, follows the aim angle, burst while
## action_params.rifle_firing, one &"shot" per round); rifle_lower returns to the carry.

const X := preload("res://rig/clips/gun_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7
const ORDER_RIFLE := 10
const ORDER_RIFLE_RAISED := 11
const RAISE_ON := 4.0
const COCKED_META := &"gun_revolver_cocked"
## Host time of the last tick of a gun action that chains into an aim loop (the aim skips its raise).
const CHAIN_META := &"gun_chain_time"
const ARM_B := [B.UPPER_ARM_B, B.FORE_ARM_B, B.HAND_B]
## Pose sheet variants of the aim loops: [id, aim degrees].
const AIM_SHEETS := [[-60.0, "m60"], [-30.0, "m30"], [0.0, "0"], [45.0, "p45"]]

static var _carry_world := PackedFloat32Array()
## Rifle carry grip (torso-local) and angle offset from the torso, built once.
static var _rifle_carry := Vector3.INF


static func create(rig: RigData) -> Dictionary:
	var out := {}
	var list: Array = [
		RevolverDraw.new(rig), RevolverAim.new(rig), RevolverFire.new(rig), RevolverRecock.new(rig),
		RevolverCock.new(rig), RevolverHolster.new(rig),
		RifleRaise.new(rig), RifleAim.new(rig), RifleLower.new(rig), RifleAim.new(rig, true),
		CarryPreview.new(rig, &"revolver", -1), CarryPreview.new(rig, &"revolver", 0), CarryPreview.new(rig, &"revolver", 1),
		CarryPreview.new(rig, &"rifle", -1), CarryPreview.new(rig, &"rifle", 0), CarryPreview.new(rig, &"rifle", 1),
	]
	for s: Array in AIM_SHEETS:
		var ra := RevolverAim.new(rig)
		ra.id = StringName("revolver_aim_%s" % s[1])
		ra.sheet_aim = deg_to_rad(s[0])
		ra.sheet_duration = 1.0
		list.append(ra)
		var fa := RifleAim.new(rig)
		fa.id = StringName("rifle_aim_%s" % s[1])
		fa.sheet_aim = deg_to_rad(s[0])
		fa.sheet_duration = 1.0
		list.append(fa)
	for a: RigAction in list:
		out[a.id] = a
	return out


static func draw_orders() -> Dictionary:
	# Rifle in front of the torso with the trigger hand over it; the support arm stays on top.
	# Raised: the rifle and the trigger arm go over the head, the support forearm and fist on top.
	return {
		ORDER_RIFLE: [["ak47", "after", "body"], ["foreArmB", "after", "ak47"], ["handB", "after", "foreArmB"]],
		ORDER_RIFLE_RAISED: [["ak47", "after", "head"], ["foreArmB", "after", "ak47"], ["handB", "after", "foreArmB"], ["foreArmF", "after", "handB"], ["handF", "after", "foreArmF"]],
	}


# ---------------------------------------------------------------------------------------------
# Carry overlay

## Weapon carry on the base pose (idle, locomotion, crouch; host, no action playing): revolver and
## bow in a low ready at the hip with the elbow bent, AK low across the body with both hands.
static func apply_carry(rig: RigData, pose: RigPose, weapon: StringName, _time: float) -> void:
	match weapon:
		&"revolver":
			carry_revolver(pose)
		&"rifle":
			carry_rifle(rig, pose)
		&"bow":
			BowNinjaActions.carry_bow(pose)


static func carry_revolver(pose: RigPose) -> void:
	var R: Dictionary = X.T.revolver
	carry_arm(pose, R.rest, R.carry)


## Back (weapon) arm held at rest (upper as a world angle, fore and hand local, degrees), reaching
## forward by c.leanReach of the torso's forward lean (a crouch keeps the weapon off the ground) and
## keeping a share of the base pose's arm swing (c.swing, c.foreSwing) clamped to c.swingLimit.
static func carry_arm(pose: RigPose, rest: Dictionary, c: Dictionary) -> void:
	var torso := pose.rot[B.TORSO] + pose.rot[B.HIP]
	var lim := deg_to_rad(c.swingLimit)
	var up := clampf(wrapf(pose.rot[B.UPPER_ARM_B], -PI, PI), -lim, lim)
	var fore := clampf(wrapf(pose.rot[B.FORE_ARM_B], -PI, PI), -lim, lim)
	pose.rot[B.UPPER_ARM_B] = deg_to_rad(rest.upper) - torso * (1.0 + c.leanReach) + c.swing * up
	pose.rot[B.FORE_ARM_B] = deg_to_rad(rest.fore) + c.foreSwing * fore
	pose.rot[B.HAND_B] = deg_to_rad(rest.hand)


static func carry_rifle(rig: RigData, pose: RigPose) -> void:
	if _carry_world.is_empty():
		_carry_world = RigMath.create_world(rig)
	var world := _carry_world
	var facing := pose.facing
	pose.facing = 1
	var h := rifle_carry_hold(rig, pose, world)
	pose.x[B.UPPER_ARM_F] += X.T.rifle.shoulderShiftReady
	hold_rifle(rig, pose, world, h.x, h.y, h.z)
	pose.draw_order = ORDER_RIFLE
	pose.facing = facing


## Carry grip (character space, before the root) and rifle angle (degrees) riding the torso, the
## muzzle drop capped at carry.maxAngle.
static func rifle_carry_hold(rig: RigData, pose: RigPose, world: PackedFloat32Array) -> Vector3:
	if _rifle_carry == Vector3.INF:
		var rest := RigPose.new(rig)
		RigLocomotion.sample_idle(rig, rest, 0.0, false)
		RigMath.compute_world(rig, rest, world)
		var C: Dictionary = X.T.rifle.carry
		var l := to_local(world, B.TORSO, Vector2(C.x, C.y))
		_rifle_carry = Vector3(l.x, l.y, C.angle - rad_to_deg(RigMath.bone_angle(world, B.TORSO)))
	RigMath.compute_world(rig, pose, world)
	var p := RigMath.point(world, B.TORSO, _rifle_carry.x, _rifle_carry.y) - Vector2(pose.root_x, pose.root_y)
	return Vector3(p.x, p.y, minf(_rifle_carry.z + rad_to_deg(RigMath.bone_angle(world, B.TORSO)), X.T.rifle.carry.maxAngle))


static func to_local(world: PackedFloat32Array, bone: int, p: Vector2) -> Vector2:
	var o := bone * 6
	var a := world[o]
	var b := world[o + 1]
	var c := world[o + 2]
	var d := world[o + 3]
	var det := a * d - b * c
	var dx := p.x - world[o + 4]
	var dy := p.y - world[o + 5]
	return Vector2((d * dx - c * dy) / det, (-b * dx + a * dy) / det)


## Both hands on the rifle: back hand on the pistol grip at (gx, gy) (character space, before the
## root, facing right), rifle at angle_deg (+ muzzle down); front fist on the handguard.
static func hold_rifle(rig: RigData, pose: RigPose, world: PackedFloat32Array, gx: float, gy: float, angle_deg: float) -> void:
	var F: Dictionary = X.T.rifle
	var support := rifle_point(rig, "foregrip") - Vector2(F.supportShift, 0.0)
	var hand_len := rig.bone_y[B.GRIP_B]
	var gun := deg_to_rad(angle_deg)
	var hand_dir := gun - PI / 2.0
	gx += pose.root_x
	gy += pose.root_y
	RigMath.solve_arm(rig, pose, "back", gx + sin(hand_dir) * hand_len, gy - cos(hand_dir) * hand_len, world, false, F.backBend)
	var arm_world := pose.rot[B.HIP] + pose.rot[B.TORSO] + pose.rot[B.UPPER_ARM_B] + pose.rot[B.FORE_ARM_B]
	pose.rot[B.HAND_B] = hand_dir - arm_world
	var f := Vector2(gx, gy) + support.rotated(gun)
	RigMath.compute_world(rig, pose, world)
	var o := B.UPPER_ARM_F * 6
	var d := f - Vector2(world[o + 4], world[o + 5])
	var tgt: Vector2 = f - d.normalized() * F.fistReach
	var g := B.GRIP_F * 6
	for i in F.fistIterations:
		RigMath.solve_arm(rig, pose, "front", tgt.x, tgt.y, world, false, F.frontBend)
		RigMath.compute_world(rig, pose, world)
		tgt += f - Vector2(world[g + 4], world[g + 5])
	RigMath.solve_arm(rig, pose, "front", tgt.x, tgt.y, world, false, F.frontBend)


## A point of the AK image relative to its grip (rifle frame, level, facing right).
static func rifle_point(rig: RigData, name: String) -> Vector2:
	var defaults := {"grip": Vector2(75, 51), "foregrip": Vector2(168, 24), "stock": Vector2(6, 42)}
	var g: Vector2 = defaults.grip
	var p: Vector2 = defaults.get(name, Vector2.ZERO)
	if rig.props.has("ak47"):
		var pts: Dictionary = rig.props.ak47.points
		g = pts.get("grip", g)
		p = pts.get(name, p)
	return p - g


# ---------------------------------------------------------------------------------------------
# Helpers

static func prop_bit(rig: RigData, key: String) -> int:
	return rig.props[key].bit if rig.props.has(key) else 0


static func is_cocked(host) -> bool:
	return host != null and bool(host.get_meta(COCKED_META, false))


static func mark_chain(host) -> void:
	host.set_meta(CHAIN_META, host.now())


static func is_chained(host) -> bool:
	return host != null and absf(float(host.get_meta(CHAIN_META, -1.0)) - host.now()) < 0.0001


## Recoil envelope a seconds after a shot: fast kick then decay (juice adds a damped wobble).
static func kick(a: float, attack: float, decay: float, wobble: float, juice: bool) -> float:
	if a <= 0.0:
		return 0.0
	if a < attack:
		var k := a / attack
		return 1.0 - (1.0 - k) * (1.0 - k)
	var x := a - attack
	var env := exp(-x / decay)
	return env * cos(TAU * wobble * x) if juice else env


static func bump(u: float, start: float, end: float) -> float:
	var w := (u - start) / (end - start)
	return 0.0 if w <= 0.0 or w >= 1.0 else sin(PI * w)


static func vec(d: Dictionary) -> Vector3:
	return Vector3(d.upper, d.fore, d.hand)


## World point of an anchor plus a bone-local offset, in the host's current pose.
static func anchor_offset(rig: RigData, host, world: PackedFloat32Array, name: String, off: Vector2) -> Vector2:
	RigMath.compute_world(rig, host.pose, world)
	var a := rig.anchor(name)
	return host.global_position + RigMath.point(world, int(a.x), a.y + off.x, a.z + off.y)


## Spawns an FX at an anchor of the host's current pose (world space, anchor bone angle).
static func spawn_at(host, type: String, params: Dictionary, anchor: String) -> void:
	if not host.juice:
		return
	var p: Vector2 = host.get_anchor(anchor)
	var ground: float = host.global_position.y
	var angle: float = (host.get_anchor_direction(anchor) as Vector2).angle()
	host.fx.spawn(type, params, p.x, minf(p.y, ground), angle, host.pose.facing, ground, host.now())


## Muzzle flash that follows the anchor every frame. ev: host (WeakRef), anchor, sprite, frame
## (first half), next (second half).
static func emit_flash(fx: RigFx, ev: Dictionary) -> void:
	var host = (ev.host as WeakRef).get_ref()
	if host == null:
		return
	var p: Vector2 = host.get_anchor(ev.anchor)
	var angle: float = (host.get_anchor_direction(ev.anchor) as Vector2).angle()
	var frame: int = ev.frame if fx.e_age < fx.e_life * 0.5 else ev.next
	fx.add(fx.rig.fx_sprite(ev.sprite).id, frame, p.x, p.y, 1.0, 1.0, 1.0, angle)


static func emit_glint(fx: RigFx, _ev: Dictionary) -> void:
	var k := fx.e_age / fx.e_life
	if k > 0.9:
		return
	fx.add(fx.rig.fx_sprite("cockGlint").id, 0 if k < 0.12 else (1 if k < 0.55 else 2), fx.e_x, fx.e_y)


## Rifle casing thrown from the ejection port, bouncing on the ground. ev: i (round index).
static func emit_casing(fx: RigFx, ev: Dictionary) -> void:
	var cj: Dictionary = X.T.rifle.juice.casings
	var i: int = ev.i
	var angle := fx.mirror_angle(deg_to_rad(-40.0 + (RigMath.hash01(41, i) - 0.5) * cj.cone))
	var speed: float = cj.speed * (0.7 + 0.6 * RigMath.hash01(43, i))
	var floor_y: float = fx.e_ground + cj.floor
	var p := RigFx.ballistic(fx.e_x, fx.e_y, cos(angle) * speed, sin(angle) * speed - cj.up, cj.gravity, fx.e_age, true, floor_y, cj.restitution)
	var resting := p.y >= floor_y - 0.5 and fx.e_age > 0.4
	var rot: float = (0.0 if RigMath.hash01(47, i) < 0.5 else PI) if resting else fx.e_age * cj.spin * (1.0 if RigMath.hash01(59, i) < 0.5 else -1.0)
	fx.add(fx.rig.fx_sprite("rifleCasing").id, 0, p.x, p.y, 1.0, 1.0, 1.0, rot)


# ---------------------------------------------------------------------------------------------

## Shared pieces: the host's ground pose plus this weapon's carry as the base, the hip shift with
## the feet kept planted, the gun arm in world angles, the live aim angle.
class GunAction extends RigAction:
	var host_ref: WeakRef
	var world := PackedFloat32Array()
	var mask := 0
	var weapon: StringName
	var aim_min := 0.0
	var aim_max := 0.0
	## Fixed aim for pose sheet variants (NAN = live from the host).
	var sheet_aim := NAN
	var _ankles := [Vector2.ZERO, Vector2.ZERO]
	var _foot_angles := [0.0, 0.0]

	func _init(rig_data: RigData, action_id: StringName, prop: String, weapon_id: StringName) -> void:
		super(rig_data)
		id = action_id
		weapon = weapon_id
		requires = "ground"
		world = RigMath.create_world(rig)
		mask = GunActions.prop_bit(rig, prop)

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)

	func _host():
		return host_ref.get_ref() if host_ref else null

	## Aim angle (radians, + down) clamped to the weapon range.
	func aim() -> float:
		var a := 0.0
		if not is_nan(sheet_aim):
			a = sheet_aim
		else:
			var h = _host()
			if h:
				a = h.action_params.get(&"gun_aim", 0.0)
		return clampf(a, deg_to_rad(aim_min), deg_to_rad(aim_max))

	func _base(pose: RigPose, juice: bool) -> void:
		var host = _host()
		if host:
			host.sample_ground(pose, 0.0, juice)
		else:
			RigLocomotion.sample_idle(rig, pose, 0.0, juice)
		pose.facing = 1
		GunActions.apply_carry(rig, pose, weapon, 0.0)
		pose.facing = 1
		pose.draw_order = 0
		pose.props |= mask

	## Moves the hip by dx and re-solves both legs to the ankles they had (feet stay planted).
	func _shift_hip(pose: RigPose, dx: float) -> void:
		if absf(dx) < 0.001:
			return
		RigMath.compute_world(rig, pose, world)
		var sides := ["front", "back"]
		for k in 2:
			var leg: RigData.Leg = rig.legs[sides[k]]
			_ankles[k] = RigMath.point(world, leg.foot, 0.0, 0.0) - Vector2(pose.root_x, pose.root_y)
			_foot_angles[k] = pose.rot[leg.thigh] + pose.rot[leg.shin] + pose.rot[leg.foot]
		pose.x[B.HIP] += dx
		for k in 2:
			RigMath.solve_leg(rig, pose, sides[k], _ankles[k].x, _ankles[k].y, _foot_angles[k])

	## Gun arm channels (degrees): upper as a world angle, fore and hand local.
	func _arm_of(pose: RigPose) -> Vector3:
		return Vector3(rad_to_deg(pose.rot[B.UPPER_ARM_B] + pose.rot[B.TORSO] + pose.rot[B.HIP]), rad_to_deg(pose.rot[B.FORE_ARM_B]), rad_to_deg(pose.rot[B.HAND_B]))

	func _apply_arm(pose: RigPose, arm: Vector3) -> void:
		pose.rot[B.UPPER_ARM_B] = deg_to_rad(arm.x) - pose.rot[B.TORSO] - pose.rot[B.HIP]
		pose.rot[B.FORE_ARM_B] = deg_to_rad(arm.y)
		pose.rot[B.HAND_B] = deg_to_rad(arm.z)

	func _finish(pose: RigPose) -> void:
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		pose.facing = start_facing

	## Muzzle point and the exact barrel direction for the aim angle (no tremor or recoil).
	func _muzzle_at(host, anchor: String, angle: float) -> Dictionary:
		return {"point": host.get_anchor(anchor), "direction": Vector2(cos(angle) * host.pose.facing, sin(angle))}

	## Pose sheets: room in front for the aimed gun and its FX, the weapon equipped.
	func sheet_setup(adv) -> void:
		adv.position += Vector2(-130.0, 40.0)
		adv.set_weapon(weapon)


# ---------------------------------------------------------------------------------------------
# Revolver

class RevolverBase extends GunAction:
	var R: Dictionary = X.T.revolver
	var cocked_from := 0.0
	## Barrel world angle (radians) of the aim arm at gun_aim 0, before the offset.
	var phi0 := 0.0

	func _init(rig_data: RigData, action_id: StringName) -> void:
		super(rig_data, action_id, "revolver", &"revolver")
		aim_min = R.aimMin
		aim_max = R.aimMax
		max_turn = R.maxTurn
		var pose := RigPose.new(rig)
		RigLocomotion.sample_idle(rig, pose, 0.0, false)
		pose.rot[B.TORSO] += deg_to_rad(R.torsoAim)
		_apply_arm(pose, GunActions.vec(R.aim))
		RigMath.compute_world(rig, pose, world)
		phi0 = RigMath.bone_angle(world, B.GRIP_B)

	func begin(host) -> void:
		super(host)
		cocked_from = 1.0 if GunActions.is_cocked(host) else 0.0

	## Aim arm pointing the barrel at angle (radians).
	func aim_arm(angle: float) -> Vector3:
		return GunActions.vec(R.aim) + Vector3(rad_to_deg(angle - phi0), 0.0, 0.0)

	## Aim posture weighted by w (torso, hip, neck following the angle, support arm), plus extras.
	func _aim_body(pose: RigPose, w: float, angle: float, torso_deg: float, neck_deg: float, hip_x: float) -> void:
		_shift_hip(pose, R.hipAimX * w + hip_x)
		var ad := rad_to_deg(angle)
		pose.rot[B.TORSO] += deg_to_rad((R.torsoAim + ad * R.torsoFollow) * w + torso_deg)
		pose.rot[B.NECK] += deg_to_rad((R.neckAim + ad * R.neckFollow) * w + neck_deg)
		pose.rot[B.UPPER_ARM_F] += deg_to_rad(R.frontArmAim.upper * w)
		pose.rot[B.FORE_ARM_F] += deg_to_rad(R.frontArmAim.fore * w)

	func _set_cocked(host, on: bool) -> void:
		host.set_meta(GunActions.COCKED_META, on)

	func _click_fx(host, life: float, sparks: Dictionary) -> void:
		if not host.juice:
			return
		var off: Array = R.cock.juice.glintOffset
		var p := GunActions.anchor_offset(rig, host, world, "revolver.hammer", Vector2(off[0], off[1]))
		var ground: float = host.global_position.y
		host.fx.spawn("custom", {"emit": GunActions.emit_glint, "life": life}, p.x, p.y, 0.0, host.pose.facing, ground, host.now())
		host.fx.spawn("spark", sparks, p.x, p.y, 0.0, host.pose.facing, ground, host.now())

	func muzzle(host) -> Dictionary:
		return _muzzle_at(host, "revolver.muzzle", aim())

	## Sheets of the actions that start in the aim: settle the aim first, as in the game.
	func _sheet_from_aim(adv) -> void:
		adv.debug_set_locomotion(0.0, 0.0, 1.0)
		adv.play_action(&"revolver_aim")
		for i in 60:
			adv.set_locomotion(0.0, 1.0 / 120.0)


## Raise from the carry to the aim (JS shoot raise), the hammer cocked on the way. Shared by
## revolver_draw and the entry of revolver_aim.
class RevolverRaise:
	static func apply(a: RevolverBase, tt: float, pose: RigPose, base: Vector3) -> float:
		var D: Dictionary = a.R.draw
		var dur: float = D.duration
		var k := 0.0
		if tt < D.anticipationAt:
			k = D.anticipation * RigMath.smooth01(tt / D.anticipationAt)
		else:
			k = lerpf(D.anticipation, 1.0, RigTrack.apply_ease(RigTrack.Ease.BACK, clampf((tt - D.anticipationAt) / (dur - D.anticipationAt), 0.0, 1.0)))
		var w := RigTrack.apply_ease(RigTrack.Ease.BACK, clampf(tt / dur, 0.0, 1.0))
		var angle := a.aim()
		a._aim_body(pose, w, angle, 0.0, 0.0, 0.0)
		a._apply_arm(pose, base + (a.aim_arm(angle) - base) * k)
		var c: Array = D.cock
		return maxf(a.cocked_from, RigMath.smooth01((tt - c[0]) / (c[1] - c[0])))


class RevolverDraw extends RevolverBase:
	func _init(rig_data: RigData) -> void:
		super(rig_data, &"revolver_draw")
		duration = R.draw.duration
		next_state = "action:revolver_aim"

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		pose.hammer = RevolverRaise.apply(self, t, pose, _arm_of(pose))
		_finish(pose)

	func tick(host, _delta: float) -> bool:
		if host.action_elapsed() >= R.draw.cock[1]:
			_set_cocked(host, true)
		GunActions.mark_chain(host)
		return false


class RevolverAim extends RevolverBase:
	var sheet_duration := 4.0
	## Raise length (0 when chained from another revolver action).
	var raise_len := 0.0

	func _init(rig_data: RigData) -> void:
		super(rig_data, &"revolver_aim")
		duration = INF
		cancel_by.assign([&"revolver_fire", &"revolver_cock", &"revolver_recock", &"revolver_holster"])

	func begin(host) -> void:
		var chained := GunActions.is_chained(host)
		super(host)
		duration = INF
		raise_len = 0.0 if chained else float(R.aimRaise)

	func sheet_setup(adv) -> void:
		super(adv)
		adv.set_gun_aim(sheet_aim if not is_nan(sheet_aim) else 0.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		var angle := aim()
		if t < raise_len:
			pose.hammer = RevolverRaise.apply(self, t / raise_len * R.draw.duration, pose, _arm_of(pose))
			_finish(pose)
			return
		var Br: Dictionary = R.breath
		var ph: float = TAU * Br.freq * t
		var b := sin(ph)
		_aim_body(pose, 1.0, angle, Br.torso * b, Br.neck * sin(ph - 0.6), 0.0)
		pose.y[B.TORSO] -= Br.lift * (0.5 - 0.5 * cos(ph))
		_apply_arm(pose, aim_arm(angle) + Vector3(Br.upper * sin(ph - 0.3), 0.0, 0.0))
		pose.hammer = cocked_from
		_finish(pose)

	func tick(host, _delta: float) -> bool:
		if raise_len > 0.0 and host.action_elapsed() >= raise_len * R.draw.cock[1] / R.draw.duration:
			if cocked_from < 1.0:
				_set_cocked(host, true)
				cocked_from = 1.0
		return false


class RevolverFire extends RevolverBase:
	var shot_t := 0.0

	func _init(rig_data: RigData) -> void:
		super(rig_data, &"revolver_fire")
		var F: Dictionary = R.fire
		shot_t = F.trigger
		duration = F.trigger + R.juice.hitstop + F.settle
		next_state = "action:revolver_recock"
		cancel_by.assign([&"revolver_fire", &"revolver_cock", &"revolver_holster"])
		var J: Dictionary = R.juice
		events = [
			{"t": shot_t, "signal": &"shot"},
			{"t": shot_t, "custom": &"shot_fx"},
		]
		for k in J.wisps.count:
			events.append({"t": shot_t + J.hitstop + J.wisps.delay + k * J.wisps.spacing, "fx": "smoke", "anchor": "revolver.muzzle",
				"params": {"count": 1, "life": J.wisps.life, "rise": J.wisps.rise, "spread": J.wisps.spread}})
		sort_events()

	func sheet_setup(adv) -> void:
		super(adv)
		adv.set_gun_aim(0.0)
		_sheet_from_aim(adv)

	## Shot time is fixed; the hitstop holds the recoil peak (juice only).
	func _anim(t: float, juice: bool) -> float:
		var peak: float = shot_t + R.recoil.attack
		if not juice or t < peak:
			return t
		return maxf(peak, t - R.juice.hitstop)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		var rc: Dictionary = R.recoil
		var J: Dictionary = R.juice
		var a := _anim(t, juice)
		var age := a - shot_t
		var k := GunActions.kick(age, rc.attack, rc.decay, J.recoilWobbleFreq, juice)
		var kh := GunActions.kick(age - rc.neckLag, rc.attack, rc.decay, J.recoilWobbleFreq, juice)
		var angle := aim()
		_aim_body(pose, 1.0, angle, rc.torso * k, rc.neck * kh, rc.hipX * k)
		_apply_arm(pose, aim_arm(angle) + Vector3(rc.upper, rc.fore, rc.hand) * k)
		pose.hammer = lerpf(cocked_from, 1.0, RigMath.smooth01(t / shot_t)) if t < shot_t else 0.0
		if juice:
			pose.sy[B.TORSO] -= J.squash * k
			pose.sx[B.TORSO] += J.squash * 0.7 * k
			var spring := 0.0
			if age > 0.0:
				spring = J.springAmp * exp(-age / J.springDecay) * sin(TAU * J.springFreq * age) * (1.0 - RigMath.smooth01((t - (duration - 0.12)) / 0.12))
			pose.rot[B.HAIR] -= deg_to_rad(spring * 0.5)
			pose.rot[B.SCARF1] += deg_to_rad(spring)
			pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
			pose.rot[B.FORE_ARM_F] += deg_to_rad(spring * 0.4)
			var real := t - shot_t
			if real >= 0.0 and real < J.headBlinkSeconds:
				var bl := sin(PI * real / J.headBlinkSeconds)
				pose.sy[B.HEAD] = 1.0 - J.headBlink * bl
				pose.sx[B.HEAD] = 1.0 + J.headBlink * 0.4 * bl
			if real >= 0.0 and real < J.shakeSeconds:
				var decay := pow(1.0 - real / J.shakeSeconds, 2.0)
				var p: float = TAU * J.shakeFreq * real
				pose.shake_x = J.shakeAmp * decay * sin(p)
				pose.shake_y = J.shakeAmp * 0.5 * decay * sin(p * 1.3 + 1.0)
		_finish(pose)

	func tick(host, _delta: float) -> bool:
		if host.action_elapsed() >= shot_t:
			_set_cocked(host, false)
		GunActions.mark_chain(host)
		return false

	func custom_event(_ev: Dictionary, host) -> void:
		if not host.juice:
			return
		var J: Dictionary = R.juice
		var big: bool = R.fire.big
		var flash := {"emit": GunActions.emit_flash, "life": J.flashLife, "host": weakref(host), "anchor": "revolver.muzzle", "sprite": "revolverFlash", "frame": 2 if big else 0, "next": 3 if big else 1}
		host.fx.spawn("custom", flash, 0.0, 0.0, 0.0, host.pose.facing, 0.0, host.now())
		GunActions.spawn_at(host, "spark", J.sparks, "revolver.muzzle")
		GunActions.spawn_at(host, "smoke", J.smoke, "revolver.muzzle")


## Automatic thumb recock in the aim after a shot.
class RevolverRecock extends RevolverBase:
	var K: Dictionary
	var click_t := 0.0

	func _init(rig_data: RigData) -> void:
		super(rig_data, &"revolver_recock")
		K = R.recock
		duration = K.duration
		click_t = K.pull[1]
		next_state = "action:revolver_aim"
		cancel_by.assign([&"revolver_fire", &"revolver_cock", &"revolver_holster"])
		events = [{"t": click_t, "signal": &"click"}, {"t": click_t, "custom": &"click_fx"}]

	func sheet_setup(adv) -> void:
		super(adv)
		adv.set_gun_aim(0.0)
		_sheet_from_aim(adv)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		var angle := aim()
		_aim_body(pose, 1.0, angle, 0.0, 0.0, 0.0)
		var arm := aim_arm(angle)
		arm.z += K.wrist * GunActions.bump(t, 0.0, duration)
		if juice and t > click_t:
			var age := t - click_t
			var k: float = (1.0 - exp(-age / 0.01)) * exp(-age / K.clickKickDecay)
			arm.z += K.clickKick * k
			arm.y += K.clickKick * 0.5 * k
		_apply_arm(pose, arm)
		var p: Array = K.pull
		pose.hammer = maxf(cocked_from, RigMath.smooth01((t - p[0]) / (p[1] - p[0])))
		_finish(pose)

	func tick(host, _delta: float) -> bool:
		if host.action_elapsed() >= click_t:
			_set_cocked(host, true)
		GunActions.mark_chain(host)
		return false

	func custom_event(_ev: Dictionary, host) -> void:
		_click_fx(host, K.glintLife, K.sparks)


## JS cock flourish from the aim: the gun to the chest, thumb pull (click), wrist twist, back to
## the aim at the current angle.
class RevolverCock extends RevolverBase:
	var C: Dictionary
	var chest := Vector3.ZERO
	var wa_track: RigTrack
	var pull_track: RigTrack
	var twist_track: RigTrack
	var click_t := 0.0

	func _init(rig_data: RigData) -> void:
		super(rig_data, &"revolver_cock")
		C = R.cock
		duration = C.fromAim + (C.aim[1] - C.raiseEnd) * C.jsDuration + C.settle
		next_state = "action:revolver_aim"
		cancel_by.assign([&"revolver_fire", &"revolver_holster"])
		var a0: float = C.aim[0]
		var a1: float = C.aim[1]
		wa_track = RigTrack.from_keys([[C.raiseEnd, 0.0], [a0, 0.0], [lerpf(a0, a1, 0.7), 1.0 + C.aimOvershoot, "inOut"], [a1, 1.0]])
		pull_track = RigTrack.from_keys([[C.pull[0], 0.0], [C.pull[1], 1.0], [C.twist[1], 0.0]])
		twist_track = RigTrack.from_keys([[C.twist[0], 0.0], [lerpf(C.twist[0], C.twist[1], 0.35), 1.0, "out"], [C.twist[1], 0.0, "back"]])
		click_t = C.fromAim + (C.click - C.raiseEnd) * C.jsDuration
		chest = _solve_chest()
		events = [{"t": click_t, "signal": &"click"}, {"t": click_t, "custom": &"click_fx"}]

	func sheet_setup(adv) -> void:
		super(adv)
		adv.set_gun_aim(0.0)
		_sheet_from_aim(adv)

	func _u(t: float) -> float:
		return C.raiseEnd + maxf(0.0, t - C.fromAim) / C.jsDuration

	## Cocking pose solved once: grip at chestGrip, gun pointing up at chestGunAngle.
	func _solve_chest() -> Vector3:
		var pose := RigPose.new(rig)
		RigLocomotion.sample_idle(rig, pose, 0.0, false)
		pose.rot[B.TORSO] += deg_to_rad(C.torsoChest)
		var hand_len := rig.bone_y[B.GRIP_B]
		var hand_dir := deg_to_rad(C.chestGunAngle - 90.0)
		var g: Array = C.chestGrip
		RigMath.solve_arm(rig, pose, "back", g[0] + sin(hand_dir) * hand_len, g[1] - cos(hand_dir) * hand_len, world, false, C.chestBend)
		var upper := rad_to_deg(pose.rot[B.UPPER_ARM_B] + pose.rot[B.TORSO] + pose.rot[B.HIP])
		var fore := rad_to_deg(pose.rot[B.FORE_ARM_B])
		return Vector3(upper, fore, C.chestGunAngle - 90.0 - upper - fore)

	func _hammer(u: float) -> float:
		if u < C.pull[0]:
			return 0.0
		if u < C.click:
			return C.pullTravel * RigMath.smooth01((u - C.pull[0]) / (C.click - C.pull[0]))
		return lerpf(C.pullTravel, 1.0, clampf((u - C.click) / C.clickSnap, 0.0, 1.0))

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		var J: Dictionary = C.juice
		var u := _u(t)
		var wa := 1.0 - RigMath.smooth01(t / C.fromAim) if t < C.fromAim else wa_track.sample(u)
		var angle := aim()
		var ad := rad_to_deg(angle)
		var arm := chest.lerp(aim_arm(angle), wa)
		var torso := lerpf(C.torsoChest, R.torsoAim + ad * R.torsoFollow, wa)
		var neck := lerpf(C.neckChest, R.neckAim + ad * R.neckFollow, wa)
		_shift_hip(pose, R.hipAimX * wa)
		pose.rot[B.UPPER_ARM_F] += deg_to_rad(lerpf(C.frontArm.upper, R.frontArmAim.upper, wa))
		pose.rot[B.FORE_ARM_F] += deg_to_rad(lerpf(C.frontArm.fore, R.frontArmAim.fore, wa))
		arm.z += C.pullWrist * pull_track.sample(u) + C.twistWrist * twist_track.sample(u)
		if juice:
			arm.z += J.pullWindup * GunActions.bump(u, C.pull[0] - 0.07, C.pull[0] + 0.03)
			var age := t - click_t
			if age > 0.0:
				var k: float = (1.0 - exp(-age / 0.01)) * exp(-age / J.clickKickDecay)
				arm.z += J.clickKick * k
				arm.y += J.clickKick * 0.5 * k
				pose.sy[B.TORSO] -= J.squash * k
				pose.sx[B.TORSO] += J.squash * 0.7 * k
				var na: float = age - J.nodLag
				if na > 0.0:
					neck += J.nod * sin(minf(na / J.nodDecay, 1.0) * PI)
				var spring: float = J.springAmp * exp(-age / J.springDecay) * sin(TAU * J.springFreq * age) * (1.0 - RigMath.smooth01((t - (duration - 0.15)) / 0.15))
				pose.rot[B.HAIR] -= deg_to_rad(spring * 0.5)
				pose.rot[B.SCARF1] += deg_to_rad(spring)
				pose.rot[B.SCARF2] -= deg_to_rad(spring * 1.4)
				if age < J.shakeSeconds:
					var decay := pow(1.0 - age / J.shakeSeconds, 2.0)
					pose.shake_x = J.shakeAmp * decay * sin(TAU * J.shakeFreq * age)
		pose.rot[B.TORSO] += deg_to_rad(torso)
		pose.rot[B.NECK] += deg_to_rad(neck)
		_apply_arm(pose, arm)
		pose.hammer = maxf(cocked_from, _hammer(u))
		_finish(pose)

	func tick(host, _delta: float) -> bool:
		if host.action_elapsed() >= click_t:
			_set_cocked(host, true)
		GunActions.mark_chain(host)
		return false

	func custom_event(_ev: Dictionary, host) -> void:
		_click_fx(host, C.juice.glintLife, C.juice.sparks)


## Aim down to the carry with the JS two-turn finger spin; the hammer is let down.
class RevolverHolster extends RevolverBase:
	var H: Dictionary
	var arm_tracks: Array[RigTrack] = []
	var w_track: RigTrack

	func _init(rig_data: RigData) -> void:
		super(rig_data, &"revolver_holster")
		H = R.holster
		duration = H.duration
		max_turn = 0.0
		var lower: float = H.lower
		for c in ["upper", "fore", "hand"]:
			arm_tracks.append(RigTrack.from_keys([[0.0, R.aim[c]], [lower * 0.5, R.lowerMid[c]], [lower, R.rest[c], "out"]]))
		w_track = RigTrack.from_keys([[0.06, 1.0], [H.aimFade, 0.0]])

	func sheet_setup(adv) -> void:
		super(adv)
		adv.set_gun_aim(0.0)
		_sheet_from_aim(adv)

	## Rotates gripB around a point of the revolver image, keeping that point fixed in the hand.
	func _spin_grip(pose: RigPose, angle: float) -> void:
		if not rig.props.has("revolver"):
			return
		var pv: Vector2 = rig.props.revolver.pivot
		var sp: Array = H.spinPivot
		var q := Vector2(sp[0], sp[1]) - pv
		var r0 := rig.rest_rot[B.GRIP_B]
		pose.rot[B.GRIP_B] += angle
		var d := q.rotated(r0) - q.rotated(r0 + angle)
		pose.x[B.GRIP_B] += d.x
		pose.y[B.GRIP_B] += d.y

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		var base_rot := [pose.rot[B.UPPER_ARM_B], pose.rot[B.FORE_ARM_B], pose.rot[B.HAND_B]]
		var angle := aim()
		_aim_body(pose, w_track.sample(t), angle, 0.0, 0.0, 0.0)
		var arm := Vector3(arm_tracks[0].sample(t), arm_tracks[1].sample(t), arm_tracks[2].sample(t))
		arm.x += rad_to_deg(angle - phi0) * (1.0 - RigMath.smooth01(t / (H.lower * 0.5)))
		_apply_arm(pose, arm)
		var bw := RigMath.smooth01((t - H.lower) / (duration - H.lower))
		if bw > 0.0:
			for i in 3:
				var bone: int = GunActions.ARM_B[i]
				pose.rot[bone] = lerp_angle(pose.rot[bone], base_rot[i], bw)
		var sp: Array = H.spin
		var s := clampf((t - sp[0]) / (sp[1] - sp[0]), 0.0, 1.0)
		if s > 0.0 and s < 1.0:
			_spin_grip(pose, fmod(RigMath.smooth01(s) * H.spinTurns * TAU, TAU))
		var dc: Array = H.decock
		pose.hammer = cocked_from * (1.0 - RigMath.smooth01((t - dc[0]) / (dc[1] - dc[0])))
		_finish(pose)

	func tick(host, _delta: float) -> bool:
		if host.action_elapsed() >= H.decock[1]:
			_set_cocked(host, false)
		return false


# ---------------------------------------------------------------------------------------------
# Rifle

## Burst state the rifle body reads (anim seconds).
class Burst:
	var k := 0.0
	var kh := 0.0
	var since_shot := -1.0
	var s := 0.0
	var climb := 0.0
	var env := 0.0
	var after := INF


class RifleBase extends GunAction:
	var F: Dictionary = X.T.rifle
	var climb_track: RigTrack
	var mouth_i := -1
	var stock := Vector2.ZERO

	func _init(rig_data: RigData, action_id: StringName) -> void:
		super(rig_data, action_id, "ak47", &"rifle")
		aim_min = F.aimMin
		aim_max = F.aimMax
		max_turn = F.maxTurn
		climb_track = RigTrack.from_keys(F.climbKeys)
		mouth_i = rig.face_fields.find("mouth")
		stock = GunActions.rifle_point(rig, "stock")

	## Climb at burst time s (nominal burst = 1); longer bursts loop the second half.
	func climb_at(s: float) -> float:
		if s <= 0.0:
			return 0.0
		if s > 1.0:
			var lf: float = F.climbLoopFrom
			s = lf + fposmod(s - 1.0, 1.0 - lf)
		return climb_track.sample(s)

	## Shoulder hold at the aim angle: the rifle turns around its stock, which stays at the chest.
	func shoulder_hold(angle: float) -> Vector3:
		var S: Dictionary = F.shoulder
		var g0 := Vector2(S.x, S.y)
		var a0 := deg_to_rad(S.angle)
		var butt := g0 + stock.rotated(a0)
		var a1 := a0 + angle
		var g := butt - stock.rotated(a1)
		return Vector3(g.x, g.y, rad_to_deg(a1))

	## The rifle body at hold weight w (0 carry, 1 shouldered at the aim angle) with the burst b;
	## a is anim time (tremble), t game time.
	func body(pose: RigPose, w: float, angle: float, b: Burst, a: float, t: float, heave: float, juice: bool, sway := 0.0) -> void:
		var rc: Dictionary = F.recoil
		var pb: Dictionary = F.pushBack
		var tr: Dictionary = F.tremble
		var J: Dictionary = F.juice
		var env := b.env
		var trem_a := sin(TAU * tr.freqA * a)
		var trem_b := sin(TAU * tr.freqB * a + 1.0)
		var hip_dx: float = pb.hip * env + rc.hip * b.k
		_shift_hip(pose, hip_dx)
		var ad := rad_to_deg(angle)
		pose.rot[B.TORSO] += deg_to_rad((F.torsoShoulder + ad * F.torsoFollow) * w + pb.torso * env + rc.torso * b.k + tr.torso * env * trem_a)
		pose.rot[B.NECK] += deg_to_rad((F.neckShoulder + ad * F.neckFollow) * w + rc.neck * b.kh + tr.neck * env * trem_b)
		pose.y[B.TORSO] -= F.heave.lift * heave
		pose.rot[B.TORSO] -= deg_to_rad(F.heave.torso * heave)
		if juice:
			pose.sy[B.TORSO] -= J.squash * b.k
			pose.sx[B.TORSO] += J.squash * 0.7 * b.k
		pose.x[B.UPPER_ARM_F] += (F.shoulderShift - F.shoulderShiftReady) * w
		var c := GunActions.rifle_carry_hold(rig, pose, world)
		var s := shoulder_hold(angle)
		var ha: float = lerpf(c.z, s.z, w) + b.climb + rc.angle * b.k + tr.torso * env * trem_b + F.holdSway.angle * sway
		var axis := Vector2.from_angle(deg_to_rad(ha))
		var hx: float = lerpf(c.x, s.x + hip_dx, w) - axis.x * rc.back * b.k
		var hy: float = lerpf(c.y, s.y, w) - axis.y * rc.back * b.k - F.heave.shoulders * heave - F.holdSway.lift * sway
		GunActions.hold_rifle(rig, pose, world, hx, hy, ha)
		if juice:
			var amp: float = (J.shakeBase + J.shakeKick * minf(1.0, b.k)) * env
			var p: float = TAU * J.shakeFreq * t
			pose.shake_x = amp * sin(p)
			pose.shake_y = amp * 0.6 * sin(p * 1.3 + 1.0)
			var spring := 0.0
			if b.after > 0.0 and b.after < 2.0:
				spring = J.springAmp * exp(-b.after / J.springDecay) * sin(TAU * J.springFreq * b.after)
			var flutter: float = env * sin(TAU * J.flutterFreq * a) * J.flutterAmp
			pose.rot[B.HAIR] += deg_to_rad(flutter - spring * 0.5)
			pose.rot[B.SCARF1] += deg_to_rad(flutter * 1.5 + spring)
			pose.rot[B.SCARF2] -= deg_to_rad(flutter * 2.0 + spring * 1.4)

	func set_mouth(pose: RigPose, frame: int) -> void:
		if mouth_i >= 0:
			pose.face[mouth_i] = frame

	## Rifle draw order, over the head while the trigger arm rises above the neck.
	func _finish(pose: RigPose) -> void:
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		RigMath.compute_world(rig, pose, world)
		var neck_y := world[B.NECK * 6 + 5]
		var arm_y := minf(world[B.FORE_ARM_B * 6 + 5], world[B.HAND_B * 6 + 5])
		arm_y = minf(arm_y, RigMath.anchor_point(rig, world, "fistB").y)
		pose.draw_order = GunActions.ORDER_RIFLE_RAISED if arm_y < neck_y - GunActions.RAISE_ON else GunActions.ORDER_RIFLE
		pose.facing = start_facing


class RifleRaise extends RifleBase:
	var w_track: RigTrack
	var _none := Burst.new()

	func _init(rig_data: RigData) -> void:
		super(rig_data, &"rifle_raise")
		var r: float = F.raise
		duration = r
		next_state = "action:rifle_aim"
		w_track = RigTrack.from_keys([[0.0, 0.0], [r * 0.7, 1.0 + F.raiseOvershoot, "inOut"], [r, 1.0]])

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		body(pose, w_track.sample(t), aim(), _none, t, t, 0.0, juice)
		set_mouth(pose, 1 if t >= F.teethAt else 0)
		_finish(pose)

	func tick(host, _delta: float) -> bool:
		GunActions.mark_chain(host)
		return false


class RifleLower extends RifleBase:
	var w_track: RigTrack
	var _none := Burst.new()

	func _init(rig_data: RigData) -> void:
		super(rig_data, &"rifle_lower")
		duration = F.lower
		w_track = RigTrack.from_keys([[0.0, 1.0], [F.lower, 0.0]])

	func sheet_setup(adv) -> void:
		super(adv)
		adv.set_gun_aim(0.0)
		adv.debug_set_locomotion(0.0, 0.0, 1.0)
		adv.play_action(&"rifle_raise")
		for i in 90:
			adv.set_locomotion(0.0, 1.0 / 120.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		body(pose, w_track.sample(t), aim(), _none, t, t, 0.0, juice)
		_finish(pose)


## The shouldered hold following the aim; runs the burst while action_params.rifle_firing is true.
## Entered directly (not from rifle_raise) it raises first. preview: pose sheet variant that fires
## for preview_release seconds then releases (not for gameplay).
class RifleAim extends RifleBase:
	var sheet_duration := 4.0
	var preview := false
	var preview_release := 1.6
	var raise_len := 0.0
	var raise_track: RigTrack
	var burst := Burst.new()
	# Anim clock: game time minus the hitstops.
	var stop_offset := 0.0
	var last_stop := -INF
	# Burst (anim seconds).
	var firing := false
	var burst0 := -INF
	var burst1 := -INF
	var next_shot := 0.0
	var shot_i := 0
	var shots := PackedFloat32Array()
	var after_smoke := 0

	func _init(rig_data: RigData, is_preview := false) -> void:
		super(rig_data, &"rifle_burst_preview" if is_preview else &"rifle_aim")
		preview = is_preview
		duration = INF
		sheet_duration = 3.2 if preview else 4.0
		cancel_by.assign([&"rifle_lower"])
		var r: float = F.raise
		raise_track = RigTrack.from_keys([[0.0, 0.0], [r * 0.7, 1.0 + F.raiseOvershoot, "inOut"], [r, 1.0]])

	func begin(host) -> void:
		var chained := GunActions.is_chained(host)
		super(host)
		duration = INF
		raise_len = 0.0 if chained else float(F.raise)
		stop_offset = 0.0
		last_stop = -INF
		firing = false
		burst0 = -INF
		burst1 = -INF
		shot_i = 0
		shots.clear()
		after_smoke = F.juice.afterSmoke.count

	func sheet_setup(adv) -> void:
		super(adv)
		adv.set_gun_aim(sheet_aim if not is_nan(sheet_aim) else 0.0)
		if preview:
			adv.set_rifle_firing(true)

	func anim(t: float) -> float:
		return t - stop_offset - clampf(t - last_stop, 0.0, F.juice.hitstop)

	func _sample_burst(a: float, juice: bool, out: Burst) -> void:
		var rc: Dictionary = F.recoil
		out.k = 0.0
		out.kh = 0.0
		out.since_shot = -1.0
		for s in shots:
			var age := a - s
			if age < 0.0:
				continue
			out.since_shot = age if out.since_shot < 0.0 else minf(out.since_shot, age)
			if age < 0.3:
				out.k += GunActions.kick(age, rc.attack, rc.decay, 6.0, juice)
				out.kh += GunActions.kick(age - rc.neckLag, rc.attack, rc.decay, 6.0, juice)
		var nominal: float = F.nominalBurst + 1.0 / F.fireRate
		if burst0 == -INF:
			out.s = 0.0
			out.climb = 0.0
			out.env = 0.0
			out.after = INF
			return
		out.s = (a - burst0) / nominal
		var r: float = F.pushBack.rise
		if a < burst1:
			out.climb = climb_at(out.s)
			out.after = -1.0
		else:
			out.climb = climb_at((burst1 - burst0) / nominal) * (1.0 - RigMath.smooth01((a - burst1) / F.climbRecover))
			out.after = a - burst1
		out.env = RigMath.smooth01((a - burst0) / r) * (1.0 - RigMath.smooth01((a - burst1) / r))

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		_base(pose, juice)
		var a := anim(t)
		_sample_burst(a, juice, burst)
		var heave := 0.0
		if burst.after >= 0.0:
			var Br: Dictionary = F.breath
			var bw: float = clampf((burst.after - Br.delay) / Br.length, 0.0, 1.0)
			if bw > 0.0 and bw < 1.0:
				heave = sin(PI * bw) * (0.5 - 0.5 * cos(TAU * Br.breaths * bw))
		var w := raise_track.sample(t) if t < raise_len else 1.0
		var sway := sin(TAU * F.holdSway.freq * t) * (1.0 - burst.env) * w
		body(pose, w, aim(), burst, a, t, heave, juice, sway)
		var mouth := 1 if (raise_len <= 0.0 or t >= F.teethAt) else 0
		if burst0 > -INF and a >= burst0 - F.mouthLead and (burst.after < 0.0 or burst.after < F.mouthAfter[0]):
			var wide: bool = burst.s >= F.mouthPeakFrom and burst.after < 0.0 and burst.since_shot >= 0.0 and burst.since_shot < F.mouthWideFor
			mouth = 3 if wide else 2
		elif burst.after >= F.mouthAfter[1] and heave > 0.0:
			mouth = 0
		set_mouth(pose, mouth)
		_finish(pose)

	## Muzzle point and the barrel direction: aim angle plus the burst climb (no tremor, no kick).
	func muzzle(host) -> Dictionary:
		var t: float = host.action_elapsed()
		_sample_burst(anim(t), false, burst)
		return _muzzle_at(host, "ak47.muzzle", aim() + deg_to_rad(burst.climb))

	func tick(host, _delta: float) -> bool:
		var t: float = host.action_elapsed()
		if preview and t >= preview_release:
			host.set_rifle_firing(false)
		var a := anim(t)
		var want: bool = host.action_params.get(&"rifle_firing", false) and t >= raise_len
		var J: Dictionary = F.juice
		if want and not firing:
			firing = true
			burst0 = a
			burst1 = INF
			next_shot = a
			shot_i = 0
			after_smoke = 0
		var step: float = 1.0 / F.fireRate
		while firing and a >= next_shot:
			_shot(host, t + (next_shot - a))
			shots.append(next_shot)
			if shots.size() > 8:
				shots.remove_at(0)
			next_shot += step
			shot_i += 1
		if firing and not want:
			firing = false
			burst1 = shots[shots.size() - 1] + step if shots.size() > 0 else a
		if not firing and burst1 > -INF and after_smoke < J.afterSmoke.count and a >= burst1 + after_smoke * J.afterSmoke.spacing:
			var S: Dictionary = J.afterSmoke
			GunActions.spawn_at(host, "smoke", {"count": 1, "life": S.life, "rise": S.rise, "spread": S.spread}, "ak47.muzzle")
			after_smoke += 1
		return false

	func _shot(host, t_shot: float) -> void:
		var J: Dictionary = F.juice
		var i := shot_i
		if host.juice and i % int(J.hitstopEvery) == int(J.hitstopEvery) - 1:
			if last_stop > -INF:
				stop_offset += J.hitstop
			last_stop = t_shot + F.recoil.attack
		host.action_event.emit(id, &"shot")
		if not host.juice:
			return
		var flash := {"emit": GunActions.emit_flash, "life": J.flashLife, "host": weakref(host), "anchor": "ak47.muzzle", "sprite": "rifleFlash", "frame": i % 3, "next": 3}
		host.fx.spawn("custom", flash, 0.0, 0.0, 0.0, host.pose.facing, 0.0, host.now())
		if i % int(J.smokeEvery) == 0:
			GunActions.spawn_at(host, "smoke", J.smoke, "ak47.muzzle")
		var cj: Dictionary = J.casings
		var p: Vector2 = host.get_anchor(&"ak47.ejectPort")
		var life: float = cj.life * (0.75 + 0.25 * RigMath.hash01(53, i))
		host.fx.spawn("custom", {"emit": GunActions.emit_casing, "life": life, "i": i}, p.x, p.y, 0.0, host.pose.facing, host.global_position.y, host.now())


# ---------------------------------------------------------------------------------------------

## Pose sheet helper (not for gameplay): the host's ground pose with the weapon carry. gait < 0
## samples the host's idle; gait >= 0 runs that host gait cycle in place.
class CarryPreview extends RigAction:
	var host_ref: WeakRef
	var gait := -1
	var weapon: StringName
	var sheet_duration := 4.0

	func _init(rig_data: RigData, weapon_id: StringName, gait_index: int) -> void:
		super(rig_data)
		weapon = weapon_id
		gait = gait_index
		id = StringName("gun_carry_%s_%s" % [weapon, ["idle", "walk", "run"][gait + 1]])
		sheet_duration = 4.0 if gait < 0 else 1.0
		duration = sheet_duration + 0.1

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)

	func sheet_setup(adv) -> void:
		adv.set_weapon(weapon)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var host = host_ref.get_ref() if host_ref else null
		if host == null:
			return
		if gait < 0:
			host.sample_ground(pose, 0.0, juice)
		else:
			var g: RigGait = host.get("_gaits")[gait]
			RigLocomotion.sample_gait(rig, pose, fposmod(t / sheet_duration, 1.0), g, juice)
		pose.facing = 1
		pose.draw_order = 0
		GunActions.apply_carry(rig, pose, weapon, t)
		pose.props |= host.weapon_mask
		pose.facing = start_facing
