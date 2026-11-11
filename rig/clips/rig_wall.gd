class_name RigWall
extends RefCounted
## Wall slide pose: facing the wall, both palms flat on it, the near foot braced, the far leg
## tucked, leaning in; the cloth streams up faster as the slide speeds up.

const W := preload("res://rig/clips/wall_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7

var rig: RigData
var world := PackedFloat32Array()


func _init(rig_data: RigData) -> void:
	rig = rig_data
	world = RigMath.create_world(rig)


## speed: slide speed (rig units/s, down positive); age: seconds on the wall; bounce, extra_lean,
## dip: grab and jump offsets.
func sample(pose: RigPose, speed: float, age: float, juice: bool, bounce := 0.0, extra_lean := 0.0, coil_x := 0.0) -> void:
	RigLocomotion.sample_idle(rig, pose, 0.0, false)
	var T: Dictionary = W.T
	var f := clampf(speed / T.fastSpeed, 0.0, 1.0)
	pose.x[B.HIP] = T.hipX + coil_x
	pose.y[B.HIP] = T.hipY + bounce
	pose.rot[B.TORSO] = deg_to_rad(T.lean + extra_lean)
	pose.rot[B.NECK] = deg_to_rad(T.neck)
	pose.rot[B.SCARF1] = deg_to_rad(lerpf(T.scarf1[0], T.scarf1[1], f))
	pose.rot[B.SCARF2] = deg_to_rad(lerpf(T.scarf2[0], T.scarf2[1], f))
	pose.rot[B.HAIR] = deg_to_rad(lerpf(T.hair[0], T.hair[1], f))
	if juice:
		var fl: float = T.flutter * f * sin(TAU * T.flutterHz * age)
		pose.rot[B.SCARF1] += deg_to_rad(fl)
		pose.rot[B.SCARF2] -= deg_to_rad(fl * 1.4)
		pose.rot[B.HAIR] += deg_to_rad(fl * 0.5)
	# Near foot on the wall, far leg tucked.
	var fa := deg_to_rad(T.footAngle)
	var foot_x: float = T.wallX - RigData.FOOT_ANKLE_HEIGHT * cos(fa + PI * 0.5) - 6.0
	RigMath.solve_leg(rig, pose, "front", foot_x, T.footY, fa)
	var leg: RigData.Leg = rig.legs["back"]
	var th := deg_to_rad(T.freeThigh)
	var sh := deg_to_rad(T.freeShin)
	pose.rot[leg.thigh] = th
	pose.rot[leg.shin] = sh
	pose.rot[leg.foot] = deg_to_rad(T.freeFootAbs) - th - sh
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
	# Palms flat on the wall.
	pose.x[B.UPPER_ARM_F] += T.shoulderF[0]
	pose.y[B.UPPER_ARM_F] += T.shoulderF[1]
	for side in ["back", "front"]:
		var h: Dictionary = T.handF if side == "front" else T.handB
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		RigMath.solve_arm(rig, pose, side, T.wallX - h.inset, h.y + bounce * 0.3, world, false, h.bend)
		RigMath.compute_world(rig, pose, world)
		pose.rot[upper + 2] = deg_to_rad(h.angle) - RigMath.bone_angle(world, upper + 1)
	RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
	pose.draw_order = 0
