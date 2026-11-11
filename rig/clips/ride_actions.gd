class_name RideActions
extends RefCounted
## Motocross: mount_bike (chains into riding), riding (INF, ended by dismount_bike), dismount_bike.
##
## Contract with the game. Everything is authored facing 1 (bike pointing right), y down, in rig
## units, relative to the foot peg:
## - host meta &"ride" (Dictionary, every key optional): lean (-1 back .. 1 forward), squat (0..1),
##   throttle (0..1), read every riding sample; grip (handlebar), seat (seat top), mount_from
##   (rig origin when mount_bike starts, standing on the ground), dismount_to (rig origin when
##   dismount_bike ends). Geometry is read in begin and on every sample.
## - The game places the rig origin at peg + mount_from + root_motion(t) while mounting, at the
##   peg while riding and at peg + root_motion(t) while dismounting; the pose is authored against
##   that moving origin, so planted feet stay still in the world.
## - Signals (action_event): mount_bike &"seated" (back boot lands on its peg); dismount_bike
##   &"foot_down" (first boot touches the ground).
## The whole rider draws in front of the bike, so no extra draw order is needed.

const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7

## Riding pose tuning (distances in rig units, angles in degrees, times in seconds).
const T := {
	"hipDrop": 18.0,
	"squatDrop": 34.0,
	"hipX": -10.0,
	"leanHipX": 32.0,
	"torso": 18.0,
	"leanTorso": 14.0,
	"throttleTorso": -6.0,
	"neutralSquat": 0.3,
	# Head counter-rotation share of the torso lean (1 keeps the head level).
	"neckCounter": 0.8,
	# Ankles on the peg (the peg sits under the ball of the boot).
	"footXFront": -22.0,
	"footXBack": -28.0,
	"footAngle": 0.0,
	# Back hand relative to the front one on the handlebar.
	"handBack": Vector2(-6.0, -2.0),
	# Absolute hand angle (0 = pointing down, negative = toward the front).
	"handAngle": -35.0,
	# Natural elbow bend (down and out); -1 hyperextends in this rig.
	"armBend": 1.0,
	"shoulderFront": 40.0,
	"shoulderBack": -20.0,
	# Extra shoulder slide (along the torso) that keeps the wrist within this share of the arm.
	"shoulderMax": 65.0,
	"slideIterations": 3,
	"reachMin": 0.5,
	"reachMax": 0.95,
	"smoothing": 0.08,
	"breathPeriod": 3.2,
	"breathLift": 1.6,
	"breathRot": 0.8,
	"scarfWind": 14.0,
	"scarf2Wind": 8.0,
	"hairWind": -6.0,
	"flutterHz": 6.0,
	"flutter": 4.0,
}

## Mount timing; dismount_bike plays the same transfer backwards. k is the mount progress
## (0 standing on the ground, 1 riding neutral).
const MOUNT := {
	"duration": 0.9,
	"dismountDuration": 0.8,
	"crouch": 0.16,
	"crouchDip": 15.0,
	"crouchX": 8.0,
	"frontLift": 0.18,
	"frontMid": 0.30,
	"frontPlant": 0.40,
	"backLift": 0.20,
	"backSwing": 0.32,
	"backPeak": 0.46,
	"backOver": 0.60,
	"seated": 0.74,
	"apex": 0.45,
	"apexHip": Vector2(14.0, -46.0),
	"sitHip": Vector2(4.0, -30.0),
	# Back ankle path relative to the seat top: swing back, peak above the seat, come down onto the peg.
	"backSwingAt": Vector2(-60.0, -10.0),
	"backPeakAt": Vector2(-100.0, -100.0),
	"backOverAt": Vector2(-50.0, -40.0),
	"torsoKeys": [[0.0, 0.0], [0.16, 14.0], [0.45, 30.0], [0.72, 24.0]],
	"reachAt": 0.20,
	# Root rise window (the climb happens while the leg passes).
	"riseFrom": 0.16,
	"riseTo": 0.72,
	# Dismount: share spent leaving the current riding offsets, and the final blend into the idle.
	"releaseSpan": 0.3,
	"idleBlendFrom": 0.82,
}

const DEFAULT_GRIP := Vector2(126.0, -216.0)
const DEFAULT_SEAT := Vector2(-40.0, -120.0)
const DEFAULT_MOUNT_FROM := Vector2(-30.0, 150.0)
const DEFAULT_DISMOUNT_TO := Vector2(-30.0, 150.0)
const META := &"ride"
## Values used by the pose sheet.
const SHEET_META := {"lean": 0.3, "squat": 0.4, "throttle": 0.6, "grip": DEFAULT_GRIP, "seat": DEFAULT_SEAT, "mount_from": DEFAULT_MOUNT_FROM, "dismount_to": DEFAULT_DISMOUNT_TO}


static func create(rig: RigData) -> Dictionary:
	var core := Core.new(rig)
	return {
		&"mount_bike": MountBike.new(rig, core),
		&"riding": Riding.new(rig, core),
		&"dismount_bike": DismountBike.new(rig, core),
	}


static func _meta_of(host) -> Dictionary:
	if host == null:
		return {}
	var m = host.get_meta(META, {})
	return m if m is Dictionary else {}


static func _value(m: Dictionary, key: String, fallback):
	if m.has(key):
		return m[key]
	return m.get(StringName(key), fallback)


## Hermite spline through [[k, Vector3, flat?], ...]; holds (equal neighbours) and flat keys get a
## zero tangent so planted points never drift.
static func curve(keys: Array, k: float) -> Vector3:
	var n := keys.size()
	if k <= float(keys[0][0]):
		return keys[0][1]
	if k >= float(keys[n - 1][0]):
		return keys[n - 1][1]
	var i := 1
	while k >= float(keys[i][0]):
		i += 1
	var t0: float = keys[i - 1][0]
	var t1: float = keys[i][0]
	var p0: Vector3 = keys[i - 1][1]
	var p1: Vector3 = keys[i][1]
	var h := t1 - t0
	var s := (k - t0) / h
	var s2 := s * s
	var s3 := s2 * s
	var m0 := _tangent(keys, i - 1) * h
	var m1 := _tangent(keys, i) * h
	return p0 * (2.0 * s3 - 3.0 * s2 + 1.0) + m0 * (s3 - 2.0 * s2 + s) + p1 * (3.0 * s2 - 2.0 * s3) + m1 * (s3 - s2)


static func _tangent(keys: Array, i: int) -> Vector3:
	if i == 0 or i == keys.size() - 1 or (keys[i] as Array).size() > 2:
		return Vector3.ZERO
	var prev: Vector3 = keys[i - 1][1]
	var cur: Vector3 = keys[i][1]
	var next: Vector3 = keys[i + 1][1]
	if prev.is_equal_approx(cur) or next.is_equal_approx(cur):
		return Vector3.ZERO
	return (next - prev) / (float(keys[i + 1][0]) - float(keys[i - 1][0]))


static func _sheet_meta(adv) -> Dictionary:
	var m: Dictionary = SHEET_META.duplicate()
	adv.set_meta(META, m)
	return m


## Peg, seat and grip marks in the sheet cell (siblings of the adventurer, so root motion does
## not drag them along).
static func _sheet_marks(adv, peg: Vector2, m: Dictionary) -> void:
	var holder = adv.get_parent()
	if holder == null:
		return
	var f := -1.0 if adv.facing < 0 else 1.0
	var seat: Vector2 = m.seat
	var grip: Vector2 = m.grip
	var marks := [
		[Vector2(-14.0, -2.0), Vector2(28.0, 4.0), Color(1.0, 0.55, 0.1, 0.9)],
		[Vector2(seat.x - 50.0, seat.y - 1.0), Vector2(100.0, 2.0), Color(0.3, 1.0, 0.5, 0.8)],
		[Vector2(grip.x - 4.0, grip.y - 4.0), Vector2(8.0, 8.0), Color(1.0, 0.3, 0.4, 0.9)],
	]
	for mk: Array in marks:
		var r := ColorRect.new()
		var p: Vector2 = mk[0]
		var size: Vector2 = mk[1]
		r.color = mk[2]
		r.size = size
		r.position = peg + Vector2(p.x * f - (size.x if f < 0.0 else 0.0), p.y)
		holder.add_child(r)


## Shared geometry, the pose builder and the riding state handed from riding to dismount_bike.
class Core:
	var rig: RigData
	var world := PackedFloat32Array()
	var grip := RideActions.DEFAULT_GRIP
	var seat := RideActions.DEFAULT_SEAT
	var mount_from := RideActions.DEFAULT_MOUNT_FROM
	var dismount_to := RideActions.DEFAULT_DISMOUNT_TO
	var lean := 0.0
	var squat := 0.3
	var throttle := 0.0
	## Smoothed riding inputs of the last riding sample, and the host time of that sample.
	var last := Vector3(0.0, 0.3, 0.0)
	var last_time := -INF
	## Set when mount_bike reaches its end, so riding starts from the neutral it ended on.
	var from_mount := false

	func _init(rig_data: RigData) -> void:
		rig = rig_data
		world = RigMath.create_world(rig)
		squat = RideActions.T.neutralSquat
		last = neutral()

	func neutral() -> Vector3:
		return Vector3(0.0, RideActions.T.neutralSquat, 0.0)

	func read(host) -> void:
		var m := RideActions._meta_of(host)
		lean = clampf(float(RideActions._value(m, "lean", 0.0)), -1.0, 1.0)
		squat = clampf(float(RideActions._value(m, "squat", RideActions.T.neutralSquat)), 0.0, 1.0)
		throttle = clampf(float(RideActions._value(m, "throttle", 0.0)), 0.0, 1.0)
		grip = Vector2(RideActions._value(m, "grip", RideActions.DEFAULT_GRIP))
		seat = Vector2(RideActions._value(m, "seat", RideActions.DEFAULT_SEAT))
		mount_from = Vector2(RideActions._value(m, "mount_from", RideActions.DEFAULT_MOUNT_FROM))
		dismount_to = Vector2(RideActions._value(m, "dismount_to", RideActions.DEFAULT_DISMOUNT_TO))

	func ride_hip(l: float, s: float) -> Vector2:
		var D: Dictionary = RideActions.T
		return Vector2(rig.bone_x[B.HIP] + D.hipX + l * D.leanHipX, rig.bone_y[B.HIP] + D.hipDrop + s * D.squatDrop)

	func ride_torso(l: float, th: float) -> float:
		var D: Dictionary = RideActions.T
		return D.torso + l * D.leanTorso + th * D.throttleTorso

	func peg_ankle(side: String) -> Vector3:
		var D: Dictionary = RideActions.T
		var x: float = D.footXFront if side == "front" else D.footXBack
		return Vector3(x, -RigData.FOOT_ANKLE_HEIGHT, deg_to_rad(D.footAngle))

	func grip_back() -> Vector2:
		return grip + RideActions.T.handBack

	func ride_pose(pose: RigPose, l: float, s: float, th: float, time: float, juice: bool) -> void:
		var breath := 0.0
		if juice:
			breath = 0.5 - 0.5 * cos(TAU * time / RideActions.T.breathPeriod)
		build(pose, ride_hip(l, s), ride_torso(l, th), peg_ankle("front"), peg_ankle("back"), grip, grip_back(), 1.0, 1.0, breath, time, juice)

	## Rise of the rig origin over the transfer (0 on the ground, 1 at the peg).
	func rise(k: float) -> float:
		var M: Dictionary = RideActions.MOUNT
		return RigMath.smooth01((k - M.riseFrom) / (M.riseTo - M.riseFrom))

	## Transfer pose at mount progress k with the ground origin at `ground` (relative to the peg);
	## offset_hip / offset_torso add the riding offsets dismount_bike starts from.
	func transfer_pose(pose: RigPose, k: float, ground: Vector2, offset_hip := Vector2.ZERO, offset_torso := 0.0) -> void:
		var M: Dictionary = RideActions.MOUNT
		var o := ground * (1.0 - rise(k))
		var o3 := Vector3(o.x, o.y, 0.0)
		var rest_hip := Vector2(rig.bone_x[B.HIP], rig.bone_y[B.HIP] + IdleTuning.T.hipDrop)
		var hip_end := ride_hip(0.0, RideActions.T.neutralSquat)
		var hip_keys := [
			[0.0, _v3(ground + rest_hip)],
			[M.crouch, _v3(ground + rest_hip + Vector2(M.crouchX, M.crouchDip)), true],
			[M.apex, _v3(seat + M.apexHip)],
			[M.seated, _v3(seat + M.sitHip)],
			[1.0, _v3(hip_end)],
		]
		var pf := peg_ankle("front")
		var pb := peg_ankle("back")
		var af0 := Vector3(ground.x + rig.rest_ankle_x("front"), ground.y - RigData.FOOT_ANKLE_HEIGHT, 0.0)
		var ab0 := Vector3(ground.x + rig.rest_ankle_x("back"), ground.y - RigData.FOOT_ANKLE_HEIGHT, 0.0)
		var f_mid := Vector3(lerpf(af0.x, pf.x, 0.5) - 12.0, lerpf(af0.y, pf.y, 0.75) - 12.0, -0.15)
		var front_keys := [[0.0, af0], [M.frontLift, af0], [M.frontMid, f_mid], [M.frontPlant, pf], [1.0, pf]]
		var back_keys := [
			[0.0, ab0],
			[M.backLift, ab0],
			[M.backSwing, _v3(seat + M.backSwingAt, 0.3)],
			[M.backPeak, _v3(seat + M.backPeakAt, 0.5)],
			[M.backOver, _v3(seat + M.backOverAt, 0.2)],
			[M.seated, pb],
			[1.0, pb],
		]
		var torso_keys: Array = []
		for tk: Array in M.torsoKeys:
			torso_keys.append([tk[0], Vector3(tk[1], 0.0, 0.0)])
		torso_keys.append([1.0, Vector3(ride_torso(0.0, 0.0), 0.0, 0.0)])
		var reach := RigMath.smooth01(k / M.reachAt)
		var hip3 := RideActions.curve(hip_keys, k) - o3
		var hip := Vector2(hip3.x, hip3.y) + offset_hip
		var torso := RideActions.curve(torso_keys, k).x + offset_torso
		build(pose, hip, torso, RideActions.curve(front_keys, k) - o3, RideActions.curve(back_keys, k) - o3, grip - o, grip_back() - o, reach, k, 0.0, 0.0, false)

	func _v3(v: Vector2, z := 0.0) -> Vector3:
		return Vector3(v.x, v.y, z)

	## Full pose in character space (facing right, root at 0): hip bone at `hip`, ankles at
	## (x, y, boot angle), hands blended from hanging (reach 0) to the grips (reach 1).
	func build(pose: RigPose, hip: Vector2, torso_deg: float, af: Vector3, ab: Vector3, gf: Vector2, gb: Vector2, reach: float, wind: float, breath: float, time: float, juice: bool) -> void:
		var D: Dictionary = RideActions.T
		RigLocomotion.sample_idle(rig, pose, 0.0, false)
		pose.x[B.HIP] = hip.x - rig.bone_x[B.HIP]
		pose.y[B.HIP] = hip.y - rig.bone_y[B.HIP]
		var tr := deg_to_rad(torso_deg - D.breathRot * breath)
		pose.rot[B.TORSO] = tr
		pose.y[B.TORSO] = -D.breathLift * breath
		pose.rot[B.NECK] -= deg_to_rad(torso_deg) * D.neckCounter
		var flutter := 0.0
		if juice:
			flutter = sin(TAU * D.flutterHz * time) * D.flutter * wind
		pose.rot[B.SCARF1] = lerpf(pose.rot[B.SCARF1], deg_to_rad(D.scarfWind + flutter), wind)
		pose.rot[B.SCARF2] = lerpf(pose.rot[B.SCARF2], deg_to_rad(D.scarf2Wind - flutter * 1.4), wind)
		pose.rot[B.HAIR] = lerpf(pose.rot[B.HAIR], deg_to_rad(D.hairWind + flutter * 0.4), wind)
		RigMath.solve_leg(rig, pose, "front", af.x, af.y, af.z)
		RigMath.solve_leg(rig, pose, "back", ab.x, ab.y, ab.z)
		if reach > 0.001:
			_grab(pose, "front", gf, reach)
			_grab(pose, "back", gb, reach)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)

	## Puts the grip point of the hand on target, sliding the shoulder along the torso so the arm
	## neither overstretches nor folds flat.
	func _grab(pose: RigPose, side: String, target: Vector2, reach: float) -> void:
		var D: Dictionary = RideActions.T
		var front := side == "front"
		var upper := B.UPPER_ARM_F if front else B.UPPER_ARM_B
		var fore := upper + 1
		var hand := upper + 2
		var hand_len := rig.bone_y[B.GRIP_F if front else B.GRIP_B]
		var a := deg_to_rad(D.handAngle)
		var wrist := target + Vector2(sin(a) * hand_len, -cos(a) * hand_len)
		pose.x[upper] += (D.shoulderFront if front else D.shoulderBack) * reach
		RigMath.compute_world(rig, pose, world)
		if reach < 1.0:
			wrist = Vector2(world[hand * 6 + 4], world[hand * 6 + 5]).lerp(wrist, reach)
		var arm := Vector2(rig.bone_x[fore], rig.bone_y[fore]).length() + Vector2(rig.bone_x[hand], rig.bone_y[hand]).length()
		var base_x := pose.x[upper]
		var slide := 0.0
		for _i in D.slideIterations:
			var dist := Vector2(world[upper * 6 + 4], world[upper * 6 + 5]).distance_to(wrist)
			if dist > arm * D.reachMax:
				slide += dist - arm * D.reachMax
			elif dist < arm * D.reachMin:
				slide += dist - arm * D.reachMin
			else:
				break
			slide = clampf(slide, -D.shoulderMax, D.shoulderMax)
			pose.x[upper] = base_x + slide * reach
			RigMath.compute_world(rig, pose, world)
		RigMath.solve_arm(rig, pose, side, wrist.x, wrist.y, world, false, D.armBend)
		var chain := pose.rot[B.HIP] + pose.rot[B.TORSO] + pose.rot[upper] + pose.rot[fore]
		pose.rot[hand] = lerpf(pose.rot[hand], a - chain, reach)


class RideAction extends RigAction:
	var core: Core
	var host_ref: WeakRef

	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data)
		core = c
		requires = ""

	func begin(host) -> void:
		start_facing = host.facing
		host_ref = weakref(host)
		core.read(host)

	func _host():
		return host_ref.get_ref() if host_ref else null


class MountBike extends RideAction:
	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data, c)
		id = &"mount_bike"
		duration = RideActions.MOUNT.duration
		next_state = "action:riding"
		events = [{"t": RideActions.MOUNT.seated * duration, "signal": &"seated"}]

	func begin(host) -> void:
		super(host)
		core.from_mount = false

	func sheet_setup(adv) -> void:
		var m := RideActions._sheet_meta(adv)
		var from: Vector2 = m.mount_from
		var f := -1.0 if adv.facing < 0 else 1.0
		RideActions._sheet_marks(adv, adv.position - Vector2(from.x * f, from.y), m)

	func root_motion(t: float) -> Vector2:
		return -core.mount_from * core.rise(clampf(t / duration, 0.0, 1.0))

	func sample(t: float, pose: RigPose, _juice: bool) -> void:
		core.read(_host())
		var k := clampf(t / duration, 0.0, 1.0)
		core.transfer_pose(pose, k, core.mount_from)
		if k >= 1.0:
			core.from_mount = true
		pose.facing = start_facing


class Riding extends RideAction:
	var sheet_duration := 0.0
	var smooth := Vector3(0.0, 0.3, 0.0)
	var prev_t := 0.0

	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data, c)
		id = &"riding"
		duration = INF
		cancel_by.assign([&"dismount_bike", &"hurt", &"shot_hit"])
		sheet_duration = RideActions.T.breathPeriod

	func begin(host) -> void:
		super(host)
		duration = INF
		prev_t = 0.0
		# Straight from mount_bike: start on the neutral it ended on; otherwise on the live inputs.
		smooth = core.neutral() if core.from_mount else Vector3(core.lean, core.squat, core.throttle)
		core.from_mount = false

	func sheet_setup(adv) -> void:
		var m := RideActions._sheet_meta(adv)
		RideActions._sheet_marks(adv, adv.position, m)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var host = _host()
		core.read(host)
		var dt := t - prev_t
		prev_t = t
		if dt > 0.0:
			var w := 1.0 - exp(-dt / RideActions.T.smoothing)
			smooth = smooth.lerp(Vector3(core.lean, core.squat, core.throttle), w)
		core.ride_pose(pose, smooth.x, smooth.y, smooth.z, t, juice)
		core.last = smooth
		core.last_time = host.now() if host else -INF
		pose.facing = start_facing


class DismountBike extends RideAction:
	var start := Vector3(0.0, 0.3, 0.0)
	var scratch: RigPose

	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data, c)
		id = &"dismount_bike"
		duration = RideActions.MOUNT.dismountDuration
		scratch = RigPose.new(rig)
		events = [{"t": (1.0 - RideActions.MOUNT.backLift) * duration, "signal": &"foot_down"}]

	func begin(host) -> void:
		super(host)
		# Continue from the riding inputs when riding was sampled just before.
		start = core.last if host.now() - core.last_time < 0.25 else core.neutral()

	func sheet_setup(adv) -> void:
		var m := RideActions._sheet_meta(adv)
		RideActions._sheet_marks(adv, adv.position, m)
		adv.play_action(&"riding")
		for i in 30:
			adv.set_locomotion(0.0, 1.0 / 120.0)

	func root_motion(t: float) -> Vector2:
		return core.dismount_to * (1.0 - core.rise(1.0 - clampf(t / duration, 0.0, 1.0)))

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var M: Dictionary = RideActions.MOUNT
		var host = _host()
		core.read(host)
		var u := clampf(t / duration, 0.0, 1.0)
		var n := core.neutral()
		var keep := 1.0 - RigMath.smooth01(u / M.releaseSpan)
		var hip_off := (core.ride_hip(start.x, start.y) - core.ride_hip(n.x, n.y)) * keep
		var torso_off := (core.ride_torso(start.x, start.z) - core.ride_torso(n.x, n.z)) * keep
		core.transfer_pose(pose, 1.0 - u, core.dismount_to, hip_off, torso_off)
		# Land on the host's own ground pose so locomotion takes over without a jump.
		var w := RigMath.smooth01((u - M.idleBlendFrom) / (1.0 - M.idleBlendFrom))
		if host and w > 0.0:
			host.sample_ground(scratch, 0.0, juice)
			scratch.facing = 1
			if w >= 1.0:
				pose.copy_from(scratch)
			else:
				pose.blend_toward(scratch, w)
		pose.facing = start_facing
