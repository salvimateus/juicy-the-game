class_name RigPush
extends RefCounted
## Push loop: leaning into a wall at +x, both palms flat on it, the legs driving with the boots
## scraping a little, the scarf hanging.

const S := preload("res://rig/clips/step_tuning.gd")
const B := preload("res://rig/rig_bone.gd")

var rig: RigData
var world := PackedFloat32Array()


func _init(rig_data: RigData) -> void:
	rig = rig_data
	world = RigMath.create_world(rig)


func sample(pose: RigPose, time: float, juice: bool, facing: int) -> void:
	var P: Dictionary = S.T.push
	RigLocomotion.sample_idle(rig, pose, 0.0, false)
	var heave := sin(TAU * P.heaveHz * time)
	var tremor: float = sin(TAU * P.tremorHz * time) * P.tremor if juice else 0.0
	pose.x[B.HIP] = P.hipX + heave * P.heave
	pose.y[B.HIP] = P.hipY - heave * P.heave * 0.4
	var lean := deg_to_rad(P.lean + tremor + heave * 1.5)
	pose.rot[B.TORSO] = lean
	pose.rot[B.NECK] = deg_to_rad(P.headAngle) - lean
	pose.y[B.NECK] = P.headSink
	pose.rot[B.SCARF1] = deg_to_rad(P.scarf1)
	pose.rot[B.SCARF2] = deg_to_rad(P.scarf2)
	var scrape: float = P.scrape * (0.5 + 0.5 * sin(TAU * P.scrapeHz * time)) if juice else 0.0
	var ff: Array = P.frontFoot
	var bf: Array = P.backFoot
	var fa := deg_to_rad(ff[1])
	var a := RigMath.planted_ankle(rig.rest_ankle_x("front") + ff[0] - scrape * 0.5, 0.0, fa)
	RigMath.solve_leg(rig, pose, "front", a.x, a.y, fa)
	var ba := deg_to_rad(bf[1])
	a = RigMath.planted_ankle(rig.rest_ankle_x("back") + bf[0] - scrape, 0.0, ba)
	RigMath.solve_leg(rig, pose, "back", a.x, a.y, ba)
	RigMath.derive_bones(rig, pose, 0.7)
	pose.x[B.UPPER_ARM_F] += P.shoulderF[0]
	pose.y[B.UPPER_ARM_F] += P.shoulderF[1]
	for side in ["back", "front"]:
		var h: Array = P.hands[side]
		var upper: int = B.UPPER_ARM_F if side == "front" else B.UPPER_ARM_B
		RigMath.solve_arm(rig, pose, side, P.wallX - P.handInset, h[0], world, false, 1.0)
		RigMath.compute_world(rig, pose, world)
		pose.rot[upper + 2] = deg_to_rad(h[1]) - RigMath.bone_angle(world, upper + 1)
	RigMath.derive_bones(rig, pose, 0.7)
	pose.facing = facing
