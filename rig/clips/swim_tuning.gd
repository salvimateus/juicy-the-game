class_name SwimTuning
## Swimming (new, no JS source): tread, front crawl at the surface, breaststroke underwater, the
## underwater float and the water exit. Angles in degrees, distances in rig units, times in
## seconds. Cycle tracks are keyed on the normalized stroke phase u (periodic, wrap at 1).
## Body angles are the head direction in the facing frame: -90 upright, 0 head forward, 90 head
## down.

const T := {
	# Center of mass relative to the origin (all swim modes): the body rotates around it.
	"com": [0.0, -200.0],
	# Water line relative to the origin (y up negative) where the game keeps the body.
	"waterLineTread": -272.0,
	"waterLineSurface": -250.0,
	# Mode cross-fade and the per-bone turn limit of the final pose (degrees per 1/60 s).
	"modeBlend": 0.3,
	"maxBoneTurn": 18.0,
	"speedSmoothing": 0.12,
	# Body heading: exponential approach plus a rate clamp; a facing change rotates the body
	# through the vertical, where the side flips with a narrowing squash (turnWidth).
	"turnSmoothing": 0.1,
	"turnRate": 380.0,
	"turnMinRate": 60.0,
	"turnSquashTime": 0.16,
	"turnWidth": 0.5,
	"turnFlipAt": 0.6,
	"underMinSpeed": 30.0,
	# Draw order: near horizontal bodies keep the far arm behind the head (custom preset).
	"horizontalOn": 55.0,
	"horizontalOff": 42.0,

	"tread": {
		"duration": 1.15,
		"angle": -90.0,
		"leanBySpeed": 10.0,
		"leanSpeedRef": 160.0,
		"lean": 7.0,
		"leanWave": 1.5,
		"neck": -6.0,
		"headBob": 2.0,
		"bob": 4.0,
		# Pedalling: one track per leg (the back leg runs half a cycle later).
		"thigh": [[0.0, -12.0], [0.25, -48.0], [0.5, -34.0], [0.75, -4.0]],
		"shin": [[0.0, 34.0], [0.25, 74.0], [0.5, 98.0], [0.75, 52.0]],
		"foot": [[0.0, 44.0], [0.25, 14.0], [0.5, 22.0], [0.75, 58.0]],
		"spread": 5.0,
		# The leg's push (stroke) phase.
		"pushAt": 0.85,
		"stroke": 0.22,
		# Sculling: two sweeps per cycle.
		"armUpper": {"front": -10.0, "back": -2.0},
		"armFore": {"front": -54.0, "back": -48.0},
		"scullUpper": 10.0,
		"scullFore": 12.0,
		"scullPitch": 26.0,
		"scullLag": 0.12,
		"squash": 0.025,
	},

	"surface": {
		"cycleLength": 330.0,
		"maxRate": 1.5,
		"angle": -7.0,
		# Windmill arms: angle = -180 + 360 g(u), g slowest at warpSlow (catch) and fastest half a
		# cycle later (recovery).
		"warp": 0.42,
		"warpSlow": 0.3,
		# The pull ends with the hand by the hip at this arm angle; the recovery bends the elbow.
		"pullEnd": 12.0,
		"pullFlex": -42.0,
		# Recovery forearm direction over the recovery (0..1), in the body frame (0 toward the belly,
		# 90 toward the feet, -90 overhead): it trails back, hangs to the water under the high
		# elbow, then reaches forward for the entry.
		"recoverDir": [[0.0, 102.0], [0.45, 62.0], [0.8, -24.0], [1.0, -90.0]],
		"pullPitch": 14.0,
		"recoverPitch": -24.0,
		# Six-beat flutter kick (three per leg per cycle).
		"kickBeats": 3.0,
		"kickThigh": 13.0,
		"kickKnee": 14.0,
		"kickKneeAmp": 16.0,
		"footPoint": 72.0,
		"neck": -18.0,
		# Breath once per cycle while the near arm recovers: the chin lifts, the mouth opens.
		"breathFrom": 0.5,
		"breathTo": 0.95,
		"breathTurn": 52.0,
		"breathLift": 5.0,
		"torsoWave": 3.0,
		"bob": 3.0,
		"strokeMin": 0.4,
		"strokeMax": 0.85,
		"speedRef": 380.0,
		# Foam from the kicks every this many beats.
		"foamEvery": 2.0,
	},

	"under": {
		"cycleLength": 400.0,
		"minRate": 0.25,
		"maxRate": 0.95,
		"armLag": 0.025,
		"upper": [[0.0, -150.0], [0.06, -146.0], [0.3, -80.0], [0.4, -58.0], [0.56, -150.0]],
		# The far arm reaches higher so both arms read in the glide.
		"farSpread": -16.0,
		"fore": [[0.0, -34.0], [0.06, -30.0], [0.28, -48.0], [0.4, -112.0], [0.48, -70.0], [0.6, -34.0]],
		"hand": [[0.0, 32.0], [0.28, 38.0], [0.4, -16.0], [0.56, 32.0]],
		"thigh": [[0.0, 0.0], [0.36, 0.0], [0.52, -58.0], [0.58, -54.0], [0.74, 2.0], [0.82, 0.0]],
		"shin": [[0.0, 2.0], [0.36, 6.0], [0.52, 118.0], [0.58, 116.0], [0.74, 0.0], [0.82, 2.0]],
		"foot": [[0.0, 76.0], [0.36, 70.0], [0.52, 4.0], [0.58, -4.0], [0.68, 40.0], [0.76, 78.0]],
		"torso": [[0.0, 0.0], [0.28, -12.0], [0.44, -6.0], [0.6, 6.0], [0.78, 0.0]],
		"neck": [[0.0, -22.0], [0.26, -38.0], [0.42, -44.0], [0.56, -20.0]],
		# Hip offset along the body (y, negative toward the head): the body surges on the kick.
		"surge": [[0.0, 0.0], [0.56, 5.0], [0.74, -9.0], [0.95, 0.0]],
		"legSpread": 6.0,
		"kickAt": 0.62,
		"kickStretch": 0.05,
		"kickFrom": 0.6,
		"kickTo": 0.86,
		"breathFrom": 0.18,
		"breathTo": 0.48,
		"exhaleAt": 0.78,
		"strokeMin": 0.5,
		"strokeMax": 1.0,
		"speedRef": 420.0,
	},

	"idle": {
		"duration": 2.8,
		"angle": -66.0,
		"angleWave": 4.0,
		"upper": {"front": -28.0, "back": -18.0},
		"fore": {"front": -52.0, "back": -44.0},
		"scullUpper": 12.0,
		"scullFore": 12.0,
		"scullPitch": 22.0,
		"thigh": -26.0,
		"thighWave": 9.0,
		"shin": 58.0,
		"shinWave": 12.0,
		"foot": 46.0,
		"torso": 6.0,
		"torsoWave": 3.0,
		"neck": -6.0,
		"bob": 5.0,
		"bubbleAt": 0.3,
	},

	# Scarf links: target directions in the facing frame, smoothed into a two-link follow-through.
	"scarf": {
		"restLink1": 158.0,
		"restLink2": 150.0,
		"tread": 172.0,
		"surfaceLift": 10.0,
		# Underwater the trailing scarf rides a little above the body line so it stays in view.
		"trailLift": 22.0,
		"float": -100.0,
		"floatDrift": 16.0,
		"floatHz": 0.35,
		"trailSpeed": 160.0,
		"flutter": 10.0,
		"flutterHz": 1.6,
		"link2Wave": 12.0,
		"link2Hz": 0.9,
		"lag1": 0.16,
		"lag2": 0.28,
	},

	"juice": {
		"bubbles": {"count": 5, "life": 1.1, "rise": 70.0, "spread": 10.0, "stagger": 0.35, "wobble": 5.0},
		"kickBubbles": {"count": 4, "life": 0.8, "rise": 55.0, "spread": 14.0, "stagger": 0.12, "wobble": 4.0},
		"idleBubbles": {"count": 3, "life": 1.3, "rise": 50.0, "spread": 6.0, "stagger": 0.4, "wobble": 4.0},
		"splash": {"count": 7, "life": 0.6, "speed": 260.0, "spread": 18.0, "gravity": 1500.0, "foam": 2},
		"kickFoam": {"count": 2, "life": 0.4, "speed": 50.0, "spread": 10.0},
		"treadFoam": {"count": 4, "life": 0.55, "speed": 70.0, "spread": 50.0},
		"exitSplash": {"count": 12, "life": 0.7, "speed": 320.0, "spread": 50.0, "gravity": 1500.0, "foam": 4},
		"exitDrips": {"count": 6, "life": 0.9, "spread": 30.0, "stagger": 0.09, "gravity": 1300.0},
	},

	# Water exit: from any swim pose, a lunge that grabs the bank corner (RigLedge hang) and the
	# ledge climb at its game speed.
	"exit": {
		"reach": 0.34,
		# Default bank corner relative to the origin at the start (facing 1); the game may pass the
		# real one in action_params[&"water_exit_corner"], clamped to cornerMin..cornerMax.
		"corner": [120.0, -410.0],
		"cornerMin": [70.0, -470.0],
		"cornerMax": [220.0, -330.0],
		"catchK": 0.5,
		"maxTurn": 22.0,
	},
}
