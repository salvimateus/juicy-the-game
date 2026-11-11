class_name RigGait
extends RefCounted
## Parameters of the shared gait clip (walk, run, sprint) in runtime units (radians for leg
## angles, degrees for the upper body as in the tuning). Gaits blend by interpolating parameters,
## so a blended gait stays a valid gait: the planted foot always moves back stride / duty per cycle.

const FIELDS := [
	"duration", "stride", "duty", "reach_x", "lift", "lift_bias", "kick_back", "heel_angle", "toe_angle",
	"heel_phase", "toe_phase", "swing_toe", "hip_drop", "hip_low_phase", "hip_bob", "hip_sway",
	"torso_lean", "torso_rock", "head_counter", "scarf_lift", "scarf_wave", "scarf_phase_step",
	"hair_back", "hair_rot", "hair_sway", "arm_back", "arm_forward", "arm_forward_front", "elbow_back",
	"elbow_forward", "elbow_forward_front", "squash", "follow_head_lag", "follow_head", "follow_elbow",
	"follow_hair", "follow_scarf", "dust_count", "dust_life", "dust_speed", "dust_rise", "dust_spread",
	"debris", "debris_count", "debris_life", "debris_speed", "debris_up", "debris_gravity",
]

var duration := 1.0
var stride := 0.0
var duty := 0.5
var reach_x := 0.0
var lift := 0.0
var lift_bias := 1.0
var kick_back := 0.0
var heel_angle := 0.0
var toe_angle := 0.0
var heel_phase := 0.1
var toe_phase := 0.4
var swing_toe := 0.0
var hip_drop := 0.0
var hip_low_phase := 0.0
var hip_bob := 0.0
var hip_sway := 0.0
var torso_lean := 0.0
var torso_rock := 0.0
var head_counter := 0.0
var scarf_lift := 0.0
var scarf_wave := 0.0
var scarf_phase_step := 0.0
var hair_back := 0.0
var hair_rot := 0.0
var hair_sway := 0.0
var arm_back := 0.0
var arm_forward := 0.0
var arm_forward_front := 0.0
var elbow_back := 0.0
var elbow_forward := 0.0
var elbow_forward_front := 0.0
var squash := 0.0
var follow_head_lag := 0.0
var follow_head := 0.0
var follow_elbow := 0.0
var follow_hair := 0.0
var follow_scarf := 0.0
var dust_count := 0.0
var dust_life := 0.4
var dust_speed := 0.0
var dust_rise := 0.0
var dust_spread := 0.0
var debris := 0.0  # 1 when the gait kicks debris at toe-off
var debris_count := 0.0
var debris_life := 0.45
var debris_speed := 0.0
var debris_up := 0.0
var debris_gravity := 700.0
# Shared foot track so the front/back hip offset doesn't make one step look shorter.
var center_x := 0.0


static func from_tuning(rig: RigData, t: Dictionary) -> RigGait:
	var g := RigGait.new()
	g.duration = t.duration
	g.stride = t.stride
	g.duty = t.duty
	g.reach_x = t.reachX
	g.lift = t.lift
	g.lift_bias = t.liftBias
	g.kick_back = t.kickBack
	g.heel_angle = deg_to_rad(t.heelAngle)
	g.toe_angle = deg_to_rad(t.toeAngle)
	g.heel_phase = t.heelPhase
	g.toe_phase = t.toePhase
	g.swing_toe = deg_to_rad(t.swingToe)
	g.hip_drop = t.hipDrop
	g.hip_low_phase = t.hipLowPhase
	g.hip_bob = t.hipBob
	g.hip_sway = t.get("hipSway", 0.0)
	g.torso_lean = t.torsoLean
	g.torso_rock = t.torsoRock
	g.head_counter = t.headCounter
	g.scarf_lift = t.scarfLift
	g.scarf_wave = t.scarfWave
	g.scarf_phase_step = t.scarfPhaseStep
	g.hair_back = t.get("hairBack", 0.0)
	g.hair_rot = t.get("hairRot", 0.0)
	g.hair_sway = t.hairSway
	var a: Dictionary = t.arms
	g.arm_back = a.back
	g.arm_forward = a.forward
	g.arm_forward_front = a.forwardFront
	g.elbow_back = a.elbowBack
	g.elbow_forward = a.elbowForward
	g.elbow_forward_front = a.elbowForwardFront
	var j: Dictionary = t.juice
	g.squash = j.squash
	g.follow_head_lag = j.follow.headLag
	g.follow_head = j.follow.head
	g.follow_elbow = j.follow.elbow
	g.follow_hair = j.follow.hair
	g.follow_scarf = j.follow.scarf
	g.dust_count = j.dust.count
	g.dust_life = j.dust.life
	g.dust_speed = j.dust.speed
	g.dust_rise = j.dust.rise
	g.dust_spread = j.dust.spread
	if j.has("debris"):
		g.debris = 1.0
		g.debris_count = j.debris.count
		g.debris_life = j.debris.life
		g.debris_speed = j.debris.speed
		g.debris_up = j.debris.up
		g.debris_gravity = j.debris.gravity
	g.center_x = (rig.rest_ankle_x("front") + rig.rest_ankle_x("back")) * 0.5
	return g


## Ground distance per gait cycle.
func cycle_length() -> float:
	return stride / duty


## Ground speed when the clip plays at its own duration.
func ground_speed() -> float:
	return stride / (duty * duration)


func blend(a: RigGait, b: RigGait, t: float) -> void:
	for f in FIELDS:
		set(f, lerpf(a.get(f), b.get(f), t))
	center_x = lerpf(a.center_x, b.center_x, t)


func copy_from(a: RigGait) -> void:
	blend(a, a, 0.0)
