class_name StepTuning
## Step up onto a ledge up to knee height, and the push-against-a-wall loop.
## Distances in rig units, angles in degrees, times in seconds.

const T := {
	# Highest step the front leg can take (knee height of the rig).
	"maxHeight": 110.0,
	# Forward root motion of a step up.
	"forward": 90.0,
	# Duration = (base + height * perUnit) * lerp(1, runFactor, entry speed / RUN_SPEED).
	"base": 0.26,
	"perUnit": 0.0024,
	"runFactor": 0.6,
	# Phases (fractions of the duration): the front foot lands on the step at frontLand, the back
	# foot leaves the ground at backLift and lands beside it at backLand; the body rises between
	# riseStart and riseEnd.
	"frontLand": 0.34,
	"backLift": 0.46,
	"backLand": 0.94,
	"riseStart": 0.3,
	"riseEnd": 0.86,
	"onTop": 0.86,
	# Swing clearance above the step edge, the back toe push and the body lean.
	"clearance": 26.0,
	"toePush": 30.0,
	"lean": 14.0,
	"hipDip": 10.0,
	"arms": {"forward": -34.0, "back": 28.0, "elbow": -30.0},
	"stepDust": {"count": 3, "life": 0.3, "speed": 24.0, "rise": 10.0, "spread": 18.0, "dir": 0},

	# Push loop (character space facing the wall at +x).
	"push": {
		"wallX": 198.0,
		# Strong lean, head sunk between the nearly straight arms.
		"lean": 40.0,
		"hipX": -24.0,
		"hipY": 20.0,
		"headAngle": 34.0,
		"headSink": 10.0,
		"shoulderF": [70.0, 6.0],
		# Wrist heights on the wall (between shoulder and head) and absolute hand angles.
		"hands": {"front": [-252.0, -176.0], "back": [-266.0, -180.0]},
		"handInset": 30.0,
		# Front foot planted under the hips, back leg straight behind pushing on the toe.
		"frontFoot": [14.0, 0.0],
		"backFoot": [-128.0, 34.0],
		"scarf1": -50.0,
		"scarf2": -26.0,
		# Effort pulse: the body drives in and gives a few units; boots scrape a little.
		"heaveHz": 0.9,
		"heave": 5.0,
		"scrape": 4.0,
		"scrapeHz": 1.6,
		"tremor": 0.8,
		"tremorHz": 15.0,
		"stepStrength": 0.15,
		"blend": 0.15,
		"dust": {"count": 2, "life": 0.3, "speed": 18.0, "rise": 8.0, "spread": 10.0, "dir": -1},
	},
}
