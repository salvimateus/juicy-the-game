class_name DodgeAction
extends RigAction
## Quick dodge in place: a short hop back against the facing (root motion), torso and head pulled
## away, then back to the guard. iframes_start / iframes_end bracket the invulnerability window.

const DT := preload("res://rig/clips/dodge_tuning.gd")

var K := {}


func _init(rig_data: RigData) -> void:
	super(rig_data)
	id = &"dodge"
	duration = DT.T.duration / DT.T.speed
	K = RigTrack.compile(DT.T.tracks)
	var J: Dictionary = DT.T.juice
	events = [
		{"t": DT.T.IFRAMES[0] / DT.T.speed, "signal": &"iframes_start"},
		{"t": DT.T.IFRAMES[1] / DT.T.speed, "signal": &"iframes_end"},
		{"t": DT.T.WHOOSH_T / DT.T.speed, "signal": &"whoosh"},
		{"t": DT.T.moveStart / DT.T.speed, "fx": "dust", "anchor": "toeF", "params": _with(J.pushDust, "dir", 1)},
		{"t": (DT.T.moveStart + 0.02) / DT.T.speed, "fx": "ghost", "params": J.ghost},
		{"t": DT.T.LAND_T / DT.T.speed, "fx": "dust", "anchor": "soleB", "params": _with(J.landDust, "dir", 0)},
		{"t": DT.T.LAND_T / DT.T.speed, "footstep": &"back", "strength": 0.45},
	]
	sort_events()


static func _with(d: Dictionary, key: String, value) -> Dictionary:
	var out := d.duplicate()
	out[key] = value
	return out


func begin(host) -> void:
	start_facing = host.facing


func _move(t: float) -> float:
	var s := clampf((t - DT.T.moveStart) / (DT.T.moveEnd - DT.T.moveStart), 0.0, 1.0)
	return 1.0 - (1.0 - s) * (1.0 - s) * (1.0 - s)


func root_motion(t: float) -> Vector2:
	return Vector2(-DT.T.dodge_distance * _move(t * DT.T.speed), 0.0)


func _tk(name: String, t: float) -> float:
	return (K[name] as RigTrack).sample(t)


func sample(game_t: float, pose: RigPose, juice: bool) -> void:
	# Tracks are authored at showcase pace.
	var t := game_t * DT.T.speed
	var full: float = DT.T.duration
	RigLocomotion.sample_idle(rig, pose, 0.0, false)
	pose.y[B.HIP] += _tk("hipY", t)
	pose.x[B.HIP] += _tk("hipX", t)
	pose.rot[B.TORSO] = deg_to_rad(_tk("torso", t))
	pose.rot[B.NECK] = deg_to_rad(_tk("neck", t))
	pose.x[B.NECK] = _tk("headX", t)
	pose.rot[B.UPPER_ARM_F] = deg_to_rad(_tk("armF", t))
	pose.rot[B.FORE_ARM_F] = deg_to_rad(_tk("foreF", t))
	pose.rot[B.UPPER_ARM_B] = deg_to_rad(_tk("armB", t))
	pose.rot[B.FORE_ARM_B] = deg_to_rad(_tk("foreB", t))
	pose.rot[B.SCARF1] = deg_to_rad(_tk("scarf1", t))
	pose.rot[B.SCARF2] = deg_to_rad(_tk("scarf2", t))
	pose.rot[B.HAIR] = deg_to_rad(_tk("hair", t))
	# Feet: planted, then carried with the body through the hop (character space follows the body)
	# and landing slightly staggered before settling back to the rest stance.
	var m := _move(t)
	var air := sin(PI * clampf((t - DT.T.moveStart) / (DT.T.moveEnd - DT.T.moveStart), 0.0, 1.0))
	var settle := RigMath.smooth01((t - DT.T.LAND_T) / (full - DT.T.LAND_T))
	for side in ["front", "back"]:
		var stagger: float = DT.T.landStagger[side] * m * (1.0 - settle)
		var x := rig.rest_ankle_x(side) + stagger
		var angle := 0.0
		if side == "front":
			angle = deg_to_rad(DT.T.pushToe) * RigMath.smooth01(t / DT.T.moveStart) * (1.0 - m)
		var a := RigMath.planted_ankle(x, 0.0, angle)
		RigMath.solve_leg(rig, pose, side, a.x, a.y - air * DT.T.hopLift * (1.0 if side == "front" else 0.7), angle)
	pose.facing = start_facing
	if juice:
		var J: Dictionary = DT.T.juice
		var crouch := _bump(t, 0.0, 0.07)
		var stretch := _bump(t, 0.05, 0.1)
		var land := _bump(t, DT.T.LAND_T, 0.12)
		var sq: float = J.crouchSquash * crouch - J.stretch * stretch + J.landSquash * land
		RigMath.squash(pose, B.TORSO, sq * 0.6)
		pose.root_sy = 1.0 - sq
		pose.root_sx = 1.0 + sq * 0.6
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)


static func _bump(t: float, at: float, span: float) -> float:
	var k := (t - at) / span
	return sin(PI * k) if k > 0.0 and k < 1.0 else 0.0
