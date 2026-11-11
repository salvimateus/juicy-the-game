class_name JumpAction
extends RigAction
## Jump anticipation and push-off on top of the current ground pose (a running jump keeps the
## stride under it). takeoff fires at the end, when the game applies the vertical speed.

const JT := preload("res://rig/clips/jump_tuning.gd")

var K := {}
var host_ref: WeakRef


func _init(rig_data: RigData) -> void:
	super(rig_data)
	id = &"jump"
	duration = JT.T.duration
	K = {"dip": RigTrack.from_keys(JT.T.dip), "lean": RigTrack.from_keys(JT.T.lean), "armWeight": RigTrack.from_keys(JT.T.armWeight), "armSwing": RigTrack.from_keys(JT.T.armSwing)}
	var J: Dictionary = JT.T.juice
	events = [
		{"t": duration - 0.02, "fx": "dust", "anchor": "soleF", "params": J.takeoffDust.merged({"dir": -1})},
		{"t": duration - 0.02, "fx": "dust", "anchor": "soleB", "params": J.takeoffDust.merged({"dir": -1, "count": 3})},
		{"t": duration, "signal": &"takeoff"},
	]


func begin(host) -> void:
	start_facing = host.facing
	host_ref = weakref(host)


func sample(t: float, pose: RigPose, juice: bool) -> void:
	var host = host_ref.get_ref()
	var dip: float = K.dip.sample(t)
	host.sample_ground(pose, dip, juice)
	pose.rot[B.TORSO] += deg_to_rad(K.lean.sample(t))
	var w: float = K.armWeight.sample(t)
	var s: float = K.armSwing.sample(t)
	var back: Dictionary = JT.T.armsBack
	var up: Dictionary = JT.T.armsUp
	pose.rot[B.UPPER_ARM_F] = lerpf(pose.rot[B.UPPER_ARM_F], deg_to_rad(lerpf(back.armF, up.armF, s)), w)
	pose.rot[B.FORE_ARM_F] = lerpf(pose.rot[B.FORE_ARM_F], deg_to_rad(lerpf(back.foreF, up.foreF, s)), w)
	pose.rot[B.UPPER_ARM_B] = lerpf(pose.rot[B.UPPER_ARM_B], deg_to_rad(lerpf(back.armB, up.armB, s)), w)
	pose.rot[B.FORE_ARM_B] = lerpf(pose.rot[B.FORE_ARM_B], deg_to_rad(lerpf(back.foreB, up.foreB, s)), w)
	pose.facing = start_facing
	if juice:
		var J: Dictionary = JT.T.juice
		var crouch := clampf(dip / 42.0, 0.0, 1.0)
		RigMath.squash(pose, B.TORSO, J.crouchSquash * crouch)
		var push := clampf((t - 0.05) / 0.05, 0.0, 1.0)
		pose.root_sy = 1.0 - J.crouchSquash * 0.5 * crouch + J.pushStretch * push
		pose.root_sx = 1.0 + J.crouchSquash * 0.3 * crouch - J.pushStretch * 0.6 * push
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
