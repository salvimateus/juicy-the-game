class_name RigLocomotion
extends RefCounted
## Idle and the shared gait clip (walk, run, sprint). Pure samplers: u is the normalized phase.
## `dip` lowers the hip before the legs are solved (landing, jump crouch).

const WAIST_FOLLOW := 0.7
const B := preload("res://rig/rig_bone.gd")


static func sample_idle(rig: RigData, pose: RigPose, u: float, juice: bool, dip := 0.0) -> void:
	var c: Dictionary = IdleTuning.T
	pose.reset()
	var breath := 0.5 - 0.5 * cos(TAU * 2.0 * u)
	pose.y[B.HIP] = c.hipDrop + c.hipBob * breath + dip
	pose.y[B.TORSO] = -c.breathLift * breath
	pose.rot[B.TORSO] = deg_to_rad(-c.breathRot * RigMath.wave(u, 2))
	pose.rot[B.NECK] = deg_to_rad(c.headRot * RigMath.wave(u, 2, c.headLag))
	pose.rot[B.UPPER_ARM_F] = deg_to_rad(c.armRot * RigMath.wave(u, 2, c.armLag))
	pose.rot[B.UPPER_ARM_B] = deg_to_rad(-c.armRot * 0.7 * RigMath.wave(u, 2, c.armLag))
	pose.rot[B.FORE_ARM_F] = deg_to_rad(c.elbowRot * (0.5 + 0.5 * RigMath.wave(u, 2, c.armLag * 2.0)))
	pose.rot[B.FORE_ARM_B] = deg_to_rad(c.elbowRot * (0.5 + 0.5 * RigMath.wave(u, 2, c.armLag * 2.0)))
	pose.rot[B.HAIR] = deg_to_rad(c.hairSway * RigMath.wave(u, 2, c.headLag * 2.0))
	pose.rot[B.SCARF1] = deg_to_rad(c.scarfDroop + c.scarfWave * RigMath.wave(u, 2))
	pose.rot[B.SCARF2] = deg_to_rad(c.scarfWave * 1.3 * RigMath.wave(u, 2, c.scarfPhaseStep))
	if juice:
		var j: Dictionary = c.juice
		var shift := sin(TAU * u)
		pose.x[B.HIP] += j.weightShift * shift
		pose.y[B.HIP] += absf(shift) * 1.5
		pose.rot[B.TORSO] -= deg_to_rad(shift * 1.2)
		pose.rot[B.NECK] += deg_to_rad(shift * 0.8)
		var w := clampf((u - j.gustAt) / j.gustLength, 0.0, 1.0)
		var env := sin(PI * w)
		var flutter: float = sin(TAU * 5.0 * w) * env * j.gustFlutter
		pose.rot[B.SCARF1] += deg_to_rad(j.gust * env + flutter)
		pose.rot[B.SCARF2] += deg_to_rad(j.gust * 0.6 * env - flutter * 1.4)
		pose.rot[B.HAIR] += deg_to_rad(env * 3.0)
		RigMath.squash(pose, B.TORSO, -j.squash * RigMath.wave(u, 2, 0.25))
	RigMath.plant_legs(rig, pose)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)


static func sample_gait(rig: RigData, pose: RigPose, u: float, g: RigGait, juice: bool, dip := 0.0) -> void:
	pose.reset()
	var low := g.hip_low_phase
	var bounce := cos(TAU * 2.0 * (u - low))
	pose.y[B.HIP] = g.hip_drop + g.hip_bob * bounce + dip
	pose.x[B.HIP] = g.hip_sway * RigMath.wave(u, 2)
	pose.rot[B.TORSO] = deg_to_rad(g.torso_lean + g.torso_rock * bounce)
	pose.rot[B.NECK] = deg_to_rad(g.head_counter - g.torso_rock * 0.6 * bounce)

	# Arms oppose legs: the front leg plants forward at u = 0, so the front arm is back.
	var swing := cos(TAU * (u - 0.03))
	var fwd_f := 0.5 - 0.5 * swing
	var fwd_b := 0.5 + 0.5 * swing
	pose.rot[B.UPPER_ARM_F] = deg_to_rad(lerpf(g.arm_back, g.arm_forward_front, fwd_f))
	pose.rot[B.FORE_ARM_F] = deg_to_rad(lerpf(g.elbow_back, g.elbow_forward_front, fwd_f))
	pose.rot[B.UPPER_ARM_B] = deg_to_rad(lerpf(g.arm_back, g.arm_forward, fwd_b))
	pose.rot[B.FORE_ARM_B] = deg_to_rad(lerpf(g.elbow_back, g.elbow_forward, fwd_b))

	pose.x[B.HAIR] = g.hair_back
	pose.rot[B.HAIR] = deg_to_rad(g.hair_rot + g.hair_sway * RigMath.wave(u, 2, 0.1))
	pose.rot[B.SCARF1] = deg_to_rad(g.scarf_lift + g.scarf_wave * RigMath.wave(u, 2))
	pose.rot[B.SCARF2] = deg_to_rad(g.scarf_wave * 1.3 * RigMath.wave(u, 2, g.scarf_phase_step))

	if juice:
		RigMath.squash(pose, B.TORSO, g.squash * bounce)
		pose.rot[B.NECK] += deg_to_rad(g.follow_head * sin(TAU * 2.0 * (u - low - g.follow_head_lag)))
		var lag_swing := sin(TAU * (u - 0.11))
		pose.rot[B.FORE_ARM_F] += deg_to_rad(g.follow_elbow * lag_swing)
		pose.rot[B.FORE_ARM_B] -= deg_to_rad(g.follow_elbow * lag_swing)
		pose.rot[B.HAIR] += deg_to_rad(g.follow_hair * sin(TAU * 2.0 * (u - low - 0.15)))
		pose.rot[B.SCARF1] += deg_to_rad(g.follow_scarf * sin(TAU * 2.0 * (u - low - 0.2)))
		pose.rot[B.SCARF2] += deg_to_rad(g.follow_scarf * sin(TAU * 2.0 * (u - low - 0.3)))

	RigMath.gait_leg(rig, pose, "front", u, g)
	RigMath.gait_leg(rig, pose, "back", fmod(u + 0.5, 1.0), g)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)


## Character-space x of the heel at contact and of the toe at toe-off (for step FX).
static func heel_contact_x(g: RigGait) -> float:
	return g.center_x + g.reach_x + g.stride * 0.5 + RigData.FOOT_HEEL


static func toe_off_x(g: RigGait) -> float:
	return g.center_x + g.reach_x - g.stride * 0.5 + RigData.FOOT_TOE
