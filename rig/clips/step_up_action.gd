class_name StepUpAction
extends RigAction
## Step up onto a ledge: the front foot goes onto the step by IK, the weight shifts onto it and the
## body rises with the back leg following. Root motion is (forward, -height).

const S := preload("res://rig/clips/step_tuning.gd")

var height := 60.0
var forward: float = S.T.forward
var _gait_arm := 0.0


func _init(rig_data: RigData) -> void:
	super(rig_data)
	id = &"step_up"


func begin(host) -> void:
	start_facing = host.facing
	height = clampf(host.step_height, 0.0, S.T.maxHeight)
	var run := clampf(host.get_entry_speed() / RunTuning.T.stride * RunTuning.T.duty * RunTuning.T.duration, 0.0, 1.0)
	duration = (S.T.base + height * S.T.perUnit) * lerpf(1.0, S.T.runFactor, run)
	events = [
		{"t": duration * S.T.frontLand, "footstep": &"front", "strength": 0.45},
		{"t": duration * S.T.frontLand, "fx": "dust", "anchor": "soleF", "params": S.T.stepDust},
		{"t": duration * S.T.onTop, "signal": &"on_top"},
		{"t": duration * S.T.backLand, "footstep": &"back", "strength": 0.35},
	]


func _rise(s: float) -> float:
	return RigMath.smooth01((s - S.T.riseStart) / (S.T.riseEnd - S.T.riseStart))


func _advance(s: float) -> float:
	return RigMath.smooth01(s / S.T.riseEnd)


func root_motion(t: float) -> Vector2:
	var s := t / duration
	return Vector2(forward * _advance(s), -height * _rise(s))


func sample(t: float, pose: RigPose, juice: bool) -> void:
	var s := clampf(t / duration, 0.0, 1.0)
	RigLocomotion.sample_idle(rig, pose, 0.0, false)
	var origin := root_motion(t)
	var effort := sin(PI * clampf((s - 0.2) / 0.7, 0.0, 1.0))
	pose.y[B.HIP] += S.T.hipDip * effort
	pose.rot[B.TORSO] = deg_to_rad(S.T.lean * effort)
	pose.rot[B.NECK] = deg_to_rad(-S.T.lean * 0.5 * effort)
	var A: Dictionary = S.T.arms
	pose.rot[B.UPPER_ARM_B] = deg_to_rad(A.forward * effort)
	pose.rot[B.FORE_ARM_B] = deg_to_rad(A.elbow * effort)
	pose.rot[B.UPPER_ARM_F] = deg_to_rad(A.back * effort)
	pose.rot[B.FORE_ARM_F] = deg_to_rad(A.elbow * 0.6 * effort)
	pose.rot[B.SCARF1] = deg_to_rad(-18.0 + 14.0 * effort)
	var ah := RigData.FOOT_ANKLE_HEIGHT
	# Feet in world (start frame), converted to character space by subtracting the origin.
	var fx0 := rig.rest_ankle_x("front")
	var bx0 := rig.rest_ankle_x("back")
	var top := Vector2(forward + fx0, -height - ah)
	var front: Vector2
	var fa := 0.0
	if s < S.T.frontLand:
		var w := s / S.T.frontLand
		front = Vector2(lerpf(fx0, top.x, RigMath.smooth01(w)), lerpf(-ah, top.y, 1.0 - (1.0 - w) * (1.0 - w)) - S.T.clearance * sin(PI * w))
		fa = deg_to_rad(-10.0) * sin(PI * w)
	else:
		front = top
	var back: Vector2
	var ba := 0.0
	if s < S.T.backLift:
		back = Vector2(bx0, -ah)
		ba = deg_to_rad(S.T.toePush) * RigMath.smooth01((s - 0.2) / (S.T.backLift - 0.2))
		back = RigMath.planted_ankle(bx0, 0.0, ba)
	elif s < S.T.backLand:
		var w := (s - S.T.backLift) / (S.T.backLand - S.T.backLift)
		var to := Vector2(forward + bx0, -height - ah)
		back = Vector2(lerpf(bx0, to.x, RigMath.smooth01(w)), lerpf(-ah, to.y, 1.0 - (1.0 - w) * (1.0 - w)) - S.T.clearance * sin(PI * w))
		ba = lerpf(deg_to_rad(S.T.toePush), 0.0, w)
	else:
		back = Vector2(forward + bx0, -height - ah)
	RigMath.solve_leg(rig, pose, "front", front.x - origin.x, front.y - origin.y, fa)
	RigMath.solve_leg(rig, pose, "back", back.x - origin.x, back.y - origin.y, ba)
	if juice:
		RigMath.squash(pose, B.TORSO, 0.04 * sin(PI * clampf((s - S.T.frontLand) / 0.2, 0.0, 1.0)))
	pose.facing = start_facing
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
