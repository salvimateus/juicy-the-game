class_name CrawlTuning
## Crouch idle and crawl (gait from the JS crawl clip, without the showcase ceiling scrape).
## Distances in rig units, angles in degrees, times in seconds. Gait phases are fractions of one
## crawl cycle (one knee and one hand plant per half cycle).

const T := {
	"knee": {"stride": 46.0, "height": -27.0, "lift": 7.0, "shinLift": 14.0, "footRelMin": 0.0, "footRelMax": 120.0},
	"hand": {"duty": 0.62, "lead": 0.06, "lift": 16.0, "reachXFront": 158.0, "reachXBack": 170.0, "groundYFront": -1.0, "groundYBack": -4.0, "angle": -8.0, "swingTilt": 25.0},
	"shoulderShift": {"front": [70.0, 6.0], "back": [-10.0, 10.0]},
	"hipSpread": {"front": -16.0, "back": 16.0},
	"hipSway": 2.0,
	"torsoAngle": 80.0,
	"torsoWave": 2.5,
	"torsoWavePhase": 0.08,
	"waistFollow": 1.0,
	"beltScale": -0.5,
	"headAngle": 48.0,
	"headBob": 2.0,
	"neckShift": [26.0, -6.0],
	"headLag": 0.1,
	"scarf": {"wrap": 40.0, "link1": -75.0, "link2": -95.0, "wave": 6.0, "phase": 0.18},
	# The crawl body reaches far ahead of the hips; this shifts it back so it centers on the origin.
	"centerShift": -60.0,
	"juice": {
		"squash": {"head": 0.05, "dip": 1.6, "seconds": 0.16},
		"follow": {"head": 3.0, "scarf": 10.0, "elbow": 6.0},
		"dust": {"count": 3, "life": 0.36, "speed": 20.0, "rise": 12.0, "spread": 16.0, "dir": 0},
		"stepStrength": 0.25,
	},
	# Crouch idle: deep squat, torso forward, head up looking ahead, hands near the knees.
	"crouch": {
		"hipY": 68.0, "hipX": -10.0, "lean": 66.0, "headAngle": 28.0, "breath": 2.0, "breathHz": 0.45,
		"handF": [86.0, -46.0], "handB": [104.0, -40.0], "scarf1": -60.0, "scarf2": -30.0, "feetSpread": 6.0,
	},

	# Blend times (s).
	"crouchTime": 0.12,
	"crawlTime": 0.18,
	"crawlMinSpeed": 6.0,
}
