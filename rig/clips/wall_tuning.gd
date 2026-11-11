class_name WallTuning
## Wall slide and wall jump. Character space facing the wall at +x; the wall plane is x = wallX.
## Angles in degrees (hand and foot angles absolute), times in seconds.

const T := {
	"wallX": 112.0,
	# Palms on the wall: the back hand above the head, the front hand at chest height (wrist target
	# height, inset from the wall plane, absolute hand angle, elbow bend side).
	"handB": {"y": -392.0, "inset": 32.0, "angle": -180.0, "bend": 1.0},
	"handF": {"y": -236.0, "inset": 32.0, "angle": -172.0, "bend": 1.0},
	# The near shoulder slides forward so the front hand reaches the wall across the chest.
	"shoulderF": [36.0, 4.0],
	# Near leg bent with the sole flat on the wall; the far leg hangs looser (FK).
	"footY": -132.0,
	"footAngle": -82.0,
	"freeThigh": 8.0,
	"freeShin": 30.0,
	"freeFootAbs": 34.0,
	"hipX": 2.0,
	"hipY": -8.0,
	"lean": 12.0,
	"neck": -6.0,
	# Cloth streaming up with the slide: angles at rest and at fastSpeed.
	"fastSpeed": 600.0,
	"scarf1": [-14.0, 46.0],
	"scarf2": [-6.0, 24.0],
	"hair": [0.0, 12.0],
	"flutter": 7.0,
	"flutterHz": 6.0,
	# Contact FX: one puff per hand/foot every (spacing / slide speed) seconds.
	"fxSpacing": 26.0,
	"fxMinSpeed": 40.0,
	"fxDust": {"count": 2, "life": 0.35, "speed": 18.0, "rise": -30.0, "spread": 6.0, "dir": -1},
	"fxChips": {"count": 2, "life": 0.6, "speed": 40.0, "gravity": 700.0, "spread": 6.0, "dir": -1},
	# Grab: jolt and scarf whip.
	"grab": {"duration": 0.2, "bounce": 12.0, "squash": 0.1, "whip": 34.0, "whipHz": 4.0, "whipDecay": 0.12},
	# Wall jump: coil, push (takeoff), turn (flip), into the rising air pose.
	"jump": {"duration": 0.14, "coil": 0.03, "push": 0.06, "flip": 0.09, "turn": [0.06, 0.12], "turnWidth": 0.3, "away": 18.0, "airVy": -900.0, "coilHipX": 10.0, "coilDip": 14.0, "stretch": 0.08},
}
