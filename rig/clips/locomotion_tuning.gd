class_name LocomotionTuning
## Game-side locomotion blending (speeds in rig units/s, times in seconds).

const T := {
	# Below this speed the idle pose fades in; at 0 it is pure idle.
	"idleSpeed": 90.0,
	# Exponential smoothing of the idle weight (s).
	"idleSmoothing": 0.08,
	# Exponential smoothing of the gait parameter blend (s).
	"gaitSmoothing": 0.06,
	# Crossfade from an action, the air pose or hanging back to locomotion (s).
	"exitBlend": 0.12,
	# Crossfade into an action (s).
	"enterBlend": 0.06,
	# Footstep strength at the walk and sprint speeds.
	"stepStrengthWalk": 0.4,
	"stepStrengthSprint": 1.0,
	# Minimum gait weight (1 - idle weight) for footsteps and step FX.
	"stepMinWeight": 0.3,
	# Held look up / down while still: degrees added to the ground pose (authored facing right),
	# blended in and out over these times.
	"look": {"blendIn": 0.18, "blendOut": 0.14, "up": {"torso": -3.0, "neck": -18.0}, "down": {"torso": 2.0, "neck": 10.0}},
}
