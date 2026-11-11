class_name BoxingActions
extends RefCounted
## Boxing: the JS combo (jab, jab, cross, uppercut) as four chainable one-shot punches that start
## and end in the boxing guard, plus the guard overlay used by Adventurer.set_guard. The lead hand
## is the back arm (its shoulder is toward the target); the rear hand is the front arm.

const X := preload("res://rig/clips/boxing_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7
const PUNCH_IDS: Array[StringName] = [&"punch_1", &"punch_2", &"punch_3", &"punch_4"]
const ARM_BONES := {
	"back": [B.UPPER_ARM_B, B.FORE_ARM_B, B.HAND_B],
	"front": [B.UPPER_ARM_F, B.FORE_ARM_F, B.HAND_F],
}

static var _guard_world := PackedFloat32Array()


static func create(rig: RigData) -> Dictionary:
	var out := {}
	for i in X.T.punches.size():
		var p := Punch.new(rig, i)
		out[p.id] = p
	out[&"boxing_guard_preview"] = GuardPreview.new(rig, -1)
	out[&"boxing_guard_run_preview"] = GuardPreview.new(rig, 1)
	return out


## Guard overlay: fists up as in the JS boxing guard, the torso leaning into it; legs untouched.
static func apply_guard(rig: RigData, pose: RigPose, weight: float, time: float) -> void:
	if weight <= 0.0:
		return
	if _guard_world.is_empty():
		_guard_world = RigMath.create_world(rig)
	var world := _guard_world
	var G: Dictionary = X.T.guard
	var facing := pose.facing
	pose.facing = 1
	var saved := {}
	for side in ARM_BONES:
		for b: int in ARM_BONES[side]:
			saved[b] = pose.rot[b]
	pose.rot[B.TORSO] += deg_to_rad(G.torsoLean) * weight
	pose.rot[B.NECK] += deg_to_rad(G.neckCounter) * weight
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
	var bob: float = G.bob * sin(TAU * G.bobFreq * time)
	RigMath.compute_world(rig, pose, world)
	var t_angle := RigMath.bone_angle(world, B.TORSO)
	for side in ["back", "front"]:
		var g: Dictionary = X.T.guardLead if side == "back" else X.T.guardRear
		var target := RigMath.point(world, B.TORSO, g.x, g.y + bob)
		place_glove(rig, pose, side, target.x, target.y, t_angle + deg_to_rad(g.angle), world)
	for b: int in saved:
		pose.rot[b] = lerp_angle(saved[b], pose.rot[b], weight)
	pose.facing = facing


## Puts the wrist on (wx, wy) (character space, facing right) and points the glove along angle.
static func place_glove(rig: RigData, pose: RigPose, side: String, wx: float, wy: float, angle: float, world: PackedFloat32Array) -> void:
	RigMath.solve_arm(rig, pose, side, wx, wy, world, false, X.T.elbowBend)
	RigMath.compute_world(rig, pose, world)
	var bones: Array = ARM_BONES[side]
	var o: int = bones[1] * 6
	var r := wrapf(angle - atan2(world[o + 3], world[o + 2]), -PI, PI)
	var lim := deg_to_rad(X.T.handLimit)
	pose.rot[bones[2]] = clampf(r, -lim, lim)


static func glove_mask(rig: RigData) -> int:
	var mask := 0
	for key in ["glove_front", "glove_back"]:
		if rig.props.has(key):
			mask |= rig.props[key].bit
	return mask


static func _emit_impact(fx: RigFx, _ev: Dictionary) -> void:
	var k := fx.e_age / fx.e_life
	var frame := 0 if k < 0.2 else (1 if k < 0.65 else 2)
	fx.add(fx.rig.fx_sprite("boxImpact").id, frame, fx.e_x, fx.e_y, 1.0)


## Punch wind: streaks (ev.lanes = [perpendicular offset, fraction of ev.length, delay]) whose head
## eases out along e_angle, thinning through the three frames as it goes.
static func _emit_wind(fx: RigFx, ev: Dictionary) -> void:
	var sprite := fx.rig.fx_sprite("boxWind").id
	var dir := Vector2.from_angle(fx.e_angle)
	var side := dir.orthogonal()
	var length: float = ev.length
	for lane: Array in ev.lanes:
		var delay: float = lane[2]
		var span := fx.e_life - delay
		if fx.e_age < delay or span <= 0.0:
			continue
		var u := clampf((fx.e_age - delay) / span, 0.0, 1.0)
		var head := 1.0 - (1.0 - u) * (1.0 - u)
		var p := Vector2(fx.e_x, fx.e_y) + dir * (length * float(lane[1]) * head) + side * float(lane[0])
		var frame := 0 if u < 0.45 else (1 if u < 0.8 else 2)
		fx.add(sprite, frame, p.x, p.y, RigFx.stepped_alpha(u), 1.0, 1.0, fx.e_angle)


class Punch extends RigAction:
	var P: Dictionary
	var index := 0
	var side := "back"
	## Animation seconds of the strike (no hitstop): impact and end.
	var impact_a := 0.0
	var end_a := 0.0
	var hitstop := 0.0
	var ext: RigTrack
	var world := PackedFloat32Array()
	var arm_length := 0.0
	var mask := 0
	var boot_parts := {}
	var hit_t := 0.0
	var window_t := 0.0
	var _impact_params := {}
	var _spark_params := {}

	func _init(rig_data: RigData, i: int) -> void:
		super(rig_data)
		index = i
		P = X.T.punches[i]
		id = P.id
		side = P.arm
		requires = "ground"
		cancel_by.assign(BoxingActions.PUNCH_IDS)
		var J: Dictionary = X.T.juice
		var A: float = X.T.anim_seconds
		impact_a = (P.impact - P.start) * A
		end_a = (P.end - P.start) * A
		hitstop = J.hitstop
		duration = end_a + hitstop
		var wind_a: float = impact_a * X.T.windAt
		var over_a: float = impact_a + (end_a - impact_a) * X.T.overAt
		ext = RigTrack.from_keys([[0.0, 0.0], [wind_a, -P.wind, "inOut"], [impact_a, 1.0, "in"], [over_a, 1.0 + P.over, "out"], [end_a, 0.0, "inOut"]])
		world = RigMath.create_world(rig)
		arm_length = Vector2(rig.bone_x[B.FORE_ARM_B], rig.bone_y[B.FORE_ARM_B]).length() + Vector2(rig.bone_x[B.HAND_B], rig.bone_y[B.HAND_B]).length()
		mask = BoxingActions.glove_mask(rig)
		for s in ["front", "back"]:
			var leg: RigData.Leg = rig.legs[s]
			var names := PackedStringArray()
			for part in rig.parts:
				if part.has_box and (part.bone == leg.foot or part.bone == leg.shin):
					names.append(part.name)
			boot_parts[s] = names
		hit_t = impact_a
		window_t = impact_a + hitstop + (end_a - impact_a) * X.T.comboWindow
		_build_events()

	func begin(host) -> void:
		start_facing = host.facing

	func _build_events() -> void:
		var J: Dictionary = X.T.juice
		var snap := impact_a * 0.5
		events = [
			{"t": snap, "fx": "ghost", "params": {"count": J.ghostCount, "spacing": J.ghostSpacing, "alpha": J.ghostAlpha, "life": impact_a - snap + J.ghostTail}},
			{"t": hit_t, "signal": &"hit"},
			{"t": window_t, "signal": &"combo_window"},
		]
		sort_events()
		_impact_params = {"emit": BoxingActions._emit_impact, "life": J.impactLifeHeavy if P.heavy else J.impactLife, "seed": 31 + index}
		_spark_params = {"count": J.sparks + index, "speed": J.sparkSpeed, "gravity": J.sparkGravity, "star": false, "life": J.sparkLife, "seed": 77 + index}

	## Reach feedback (Adventurer.punch_reach, juice only): wind streaks from the glove to the end of
	## the reach, plus the impact star and sparks where the punch connected.
	func reach_fx(host, from: Vector2, to: Vector2, hit: bool) -> void:
		var d := to - from
		var f: int = host.pose.facing
		if d.length_squared() > 1.0:
			var wind: Dictionary = X.T.juice.wind.merged({"emit": BoxingActions._emit_wind, "length": d.length()})
			host.fx.spawn("custom", wind, from.x, from.y, d.angle(), f, from.y + 4000.0, host.now())
		if hit:
			host.fx.spawn("custom", _impact_params, to.x, to.y, 0.0, f, to.y + 4000.0, host.now())
			host.fx.spawn("spark", _spark_params, to.x, to.y, 0.0, f, to.y + 4000.0, host.now())

	## Game time -> strike animation time; the hitstop holds the impact frame (juice only).
	func _anim_t(t: float, juice: bool) -> float:
		if not juice:
			return t * end_a / duration
		if t < impact_a:
			return t
		if t < impact_a + hitstop:
			return impact_a
		return minf(t - hitstop, end_a)

	func _plant_foot(pose: RigPose, s: String, x: float, roll: float) -> void:
		var leg: RigData.Leg = rig.legs[s]
		var a := RigMath.planted_ankle(x, 0.0, roll)
		RigMath.solve_leg(rig, pose, s, a.x, a.y, roll)
		var y := a.y
		for i in 3:
			pose.rot[leg.cap] = pose.rot[leg.shin] * 0.5
			var dip := RigMath.lowest_point(rig, pose, world, boot_parts[s]) - pose.root_y
			if dip <= 0.25:
				break
			y -= dip
			RigMath.solve_leg(rig, pose, s, a.x, y, roll)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var J: Dictionary = X.T.juice
		RigLocomotion.sample_idle(rig, pose, 0.0, false)
		pose.props |= mask
		var ta := _anim_t(t, juice)
		var e := ext.sample(ta) if ta > 0.0 and ta < end_a else 0.0
		var ec := minf(e, 1.0)
		var lean: float = P.lean * ec
		var neck: float = P.neck * ec
		pose.x[B.HIP] = P.hipX * ec
		pose.y[B.HIP] = X.T.crouch + P.hipY * ec
		pose.rot[B.TORSO] = deg_to_rad(X.T.torsoLean + lean)
		pose.rot[B.NECK] = deg_to_rad(X.T.neckCounter + neck)
		pose.x[B.UPPER_ARM_B] = P.shoulderLead * ec
		pose.x[B.UPPER_ARM_F] = P.shoulderRear * ec
		var roll := deg_to_rad(X.T.heelLift)
		_plant_foot(pose, "back", X.T.leadAnkleX, roll)
		_plant_foot(pose, "front", X.T.rearAnkleX, roll + deg_to_rad(P.rearHeel * maxf(0.0, ec)))

		# Hair and scarf react to the impact.
		var spring := 0.0
		var age := t - hit_t
		if juice and age >= 0.0 and age < J.springLife:
			spring = J.springAmp * exp(-age / J.springDecay) * sin(TAU * J.springFreq * age) * (1.0 - age / J.springLife)
		pose.rot[B.HAIR] = deg_to_rad(spring * 0.5 - lean * 0.3)
		pose.rot[B.SCARF1] = deg_to_rad(-18.0 + spring - lean * 0.8)
		pose.rot[B.SCARF2] = deg_to_rad(-spring * 1.4 - lean * 0.5)

		# Arms: guard targets ride the torso; the striking arm blends to its reach by e.
		RigMath.compute_world(rig, pose, world)
		var t_angle := RigMath.bone_angle(world, B.TORSO)
		for s in ["back", "front"]:
			var g: Dictionary = X.T.guardLead if s == "back" else X.T.guardRear
			var target := RigMath.point(world, B.TORSO, g.x, g.y)
			var angle := t_angle + deg_to_rad(g.angle)
			if s == side and e != 0.0:
				var upper: int = BoxingActions.ARM_BONES[s][0]
				var aim := deg_to_rad(P.aim)
				var tx: float = world[upper * 6 + 4] + cos(aim) * arm_length * P.reach
				var ty: float = world[upper * 6 + 5] + sin(aim) * arm_length * P.reach
				target = Vector2(lerpf(target.x, tx, e), lerpf(target.y, ty, e))
				angle = lerpf(angle, deg_to_rad(P.get("glove", P.aim)), clampf(e, 0.0, 1.0))
				if juice:
					# Stretch on the way out, squash on contact.
					var near := 1.0 - minf(1.0, absf(ta - impact_a) / (J.squashNear * X.T.anim_seconds))
					var amount: float = -J.gloveStretch * e if (e > 0.0 and ta < impact_a) else J.gloveSquash * near
					RigMath.squash(pose, BoxingActions.ARM_BONES[s][2], amount)
			BoxingActions.place_glove(rig, pose, s, target.x, target.y, angle, world)
			RigMath.compute_world(rig, pose, world)

		# Impact shake.
		if juice and age >= 0.0 and age < J.shakeSeconds:
			var decay := pow(1.0 - age / J.shakeSeconds, 2.0)
			var ph: float = TAU * J.shakeFreq * age
			var amp: float = J.shakeAmp * (J.shakeHeavy if P.heavy else 1.0)
			pose.shake_x = amp * decay * sin(ph)
			pose.shake_y = amp * 0.5 * decay * sin(ph * 1.3 + 1.0)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		pose.facing = start_facing


## Pose sheet helper (not for gameplay): the host's ground pose with the guard overlay. gait < 0
## samples the host's idle through set_guard; gait >= 0 runs that host gait cycle in place.
class GuardPreview extends RigAction:
	var host_ref: WeakRef
	var gait := -1
	var sheet_duration := 4.0

	func _init(rig_data: RigData, gait_index: int) -> void:
		super(rig_data)
		gait = gait_index
		id = &"boxing_guard_preview" if gait < 0 else &"boxing_guard_run_preview"
		sheet_duration = 4.0 if gait < 0 else 1.0
		duration = sheet_duration + 0.1

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)

	func sheet_setup(adv) -> void:
		adv.set_guard(true)
		for i in 30:
			adv.set_locomotion(0.0, 1.0 / 120.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var host = host_ref.get_ref() if host_ref else null
		if host == null:
			return
		if gait < 0:
			host.sample_ground(pose, 0.0, juice)
		else:
			var g: RigGait = host.get("_gaits")[gait]
			RigLocomotion.sample_gait(rig, pose, fposmod(t / sheet_duration, 1.0), g, juice)
			BoxingActions.apply_guard(rig, pose, 1.0, t)
		pose.facing = start_facing
