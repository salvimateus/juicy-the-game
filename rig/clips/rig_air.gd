class_name RigAir
extends RefCounted
## Air pose from the vertical speed (rise, apex and fall blended continuously) and the landing
## overlay applied on top of the ground pose.

const J := preload("res://rig/clips/jump_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7
const KEYS := ["hipY", "torso", "neck", "thighF", "shinF", "footAbsF", "thighB", "shinB", "footAbsB", "armF", "foreF", "armB", "foreB", "scarf1", "scarf2", "hair"]


static func _key(name: String, r: float) -> float:
	if r < 0.0:
		return lerpf(J.T.apex[name], J.T.rise[name], -r)
	return lerpf(J.T.apex[name], J.T.fall[name], r)


## vy in rig units/s (negative up); speed is the horizontal speed; air_time the seconds airborne.
static func sample_air(rig: RigData, pose: RigPose, vy: float, speed: float, juice: bool, air_time: float) -> void:
	RigLocomotion.sample_idle(rig, pose, 0.0, false)
	var r := clampf(vy / J.T.airVyRange, -1.0, 1.0)
	# Ease toward the extremes so the apex reads as a held moment.
	r = signf(r) * (1.0 - pow(1.0 - absf(r), 1.6))
	pose.y[B.HIP] = _key("hipY", r)
	pose.x[B.HIP] = 0.0
	var lean := _key("torso", r) + J.T.speedLean * minf(speed / RunTuning.T.stride * RunTuning.T.duty * RunTuning.T.duration, 1.5)
	pose.rot[B.TORSO] = deg_to_rad(lean)
	pose.rot[B.NECK] = deg_to_rad(_key("neck", r) - lean * 0.3)
	pose.rot[B.UPPER_ARM_F] = deg_to_rad(_key("armF", r))
	pose.rot[B.FORE_ARM_F] = deg_to_rad(_key("foreF", r))
	pose.rot[B.UPPER_ARM_B] = deg_to_rad(_key("armB", r))
	pose.rot[B.FORE_ARM_B] = deg_to_rad(_key("foreB", r))
	pose.rot[B.HAND_F] = 0.0
	pose.rot[B.HAND_B] = 0.0
	pose.rot[B.SCARF1] = deg_to_rad(_key("scarf1", r))
	pose.rot[B.SCARF2] = deg_to_rad(_key("scarf2", r))
	pose.rot[B.HAIR] = deg_to_rad(_key("hair", r))
	for side in ["F", "B"]:
		var thigh := deg_to_rad(_key("thigh" + side, r))
		var shin := deg_to_rad(_key("shin" + side, r))
		var foot_abs := deg_to_rad(_key("footAbs" + side, r))
		var leg: RigData.Leg = rig.legs["front" if side == "F" else "back"]
		pose.rot[leg.thigh] = thigh
		pose.rot[leg.shin] = shin
		pose.rot[leg.foot] = foot_abs - thigh - shin
	if juice:
		var jj: Dictionary = J.T.juice
		var stretch: float = jj.riseStretch * maxf(0.0, -r) + jj.fallStretch * maxf(0.0, r)
		pose.root_sy = 1.0 + stretch
		pose.root_sx = 1.0 - stretch * 0.6
		var flutter: float = jj.scarfFlutter * sin(TAU * jj.scarfFlutterHz * air_time) * (0.4 + 0.6 * absf(r))
		pose.rot[B.SCARF1] += deg_to_rad(flutter)
		pose.rot[B.SCARF2] -= deg_to_rad(flutter * 1.3)
		pose.rot[B.HAIR] += deg_to_rad(flutter * 0.4)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)


static func landing_strength(vy: float) -> float:
	return clampf((vy - J.T.landVyMin) / J.T.landVyRange, J.T.landMin, 1.0)


static func landing_duration(strength: float) -> float:
	return J.T.landTime + J.T.landTimeStrong * strength


## Hip dip (rig units) of the landing at time t; applied before the legs are solved.
static func landing_dip(t: float, strength: float) -> float:
	var d := landing_duration(strength)
	if t < 0.0 or t >= d:
		return 0.0
	var k := t / d
	# Fast compression, slower recovery.
	var env := sin(PI * pow(k, 0.55))
	return J.T.landDip * strength * env


## Squash and arm drop applied after the ground pose is sampled.
static func apply_landing(pose: RigPose, t: float, strength: float, juice: bool) -> void:
	var d := landing_duration(strength)
	if t < 0.0 or t >= d:
		return
	var env := sin(PI * pow(t / d, 0.55))
	pose.rot[B.UPPER_ARM_F] -= deg_to_rad(J.T.landArms * strength * env)
	pose.rot[B.UPPER_ARM_B] += deg_to_rad(J.T.landArms * strength * env)
	pose.rot[B.SCARF1] -= deg_to_rad(20.0 * strength * env)
	if not juice:
		return
	var jj: Dictionary = J.T.juice
	RigMath.squash(pose, B.TORSO, 1.0 - pose.sy[B.TORSO] + jj.landTorsoSquash * strength * env)
	var st: float = jj.landSquashTime
	if t < st:
		var s: float = sin(PI * t / st) * jj.landSquash * strength
		pose.root_sy *= 1.0 - s
		pose.root_sx *= 1.0 + s * 0.6
