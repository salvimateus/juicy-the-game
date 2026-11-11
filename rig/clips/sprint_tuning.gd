class_name SprintTuning
## Sprint gait: the run gait with a longer stride over a shorter cycle, more air time, a stronger lean
## and a wider arm pump. Keys missing here come from RunTuning.

const OVERRIDES := {
	# Ground speed stride / (duty * duration) = 1426 units/s.
	"duration": 0.445,
	"stride": 184.0,
	"duty": 0.29,
	"lift": 50.0,
	"kickBack": 30.0,
	# Contact closer under the hip and the hips a touch lower, so the planted leg is never locked
	# straight at heel strike (the knee would snap more than 20 degrees in a frame).
	"reachX": -48.0,
	"hipDrop": 20.0,
	"torsoLean": 24.0,
	"headCounter": -9.0,
	"scarfLift": -6.0,
	"scarfWave": 7.0,
	"hairRot": -9.0,
	"arms": {"back": 62.0, "forward": -40.0, "forwardFront": -16.0, "elbowBack": -70.0, "elbowForward": -100.0, "elbowForwardFront": -76.0},
	"juice": {
		"squash": 0.03,
		"follow": {"headLag": 0.08, "head": 2.0, "elbow": 6.0, "hair": 5.0, "scarf": 9.0},
		"dust": {"count": 3, "life": 0.3, "speed": 40.0, "rise": 14.0, "spread": 14.0},
	},
}


static func data() -> Dictionary:
	var t: Dictionary = RunTuning.T.duplicate(true)
	t.merge(OVERRIDES, true)
	return t
