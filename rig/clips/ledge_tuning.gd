class_name LedgeTuning
## Ledge hang, grab and climb (from the JS ledge clip). Ledge space L: the stone face is x = 0 and
## the grass top y = 0 (y down), the character hangs at x < 0 facing +x. Times in seconds.

const T := {
	"duration": 4.0,
	"ANTICIPATION_T": 0.62,
	"PULL_T": 0.86,
	"CHEST_T": 1.36,
	"PALMS_T": 1.6,
	"KNEE_T": 1.9,
	"STAND_T": 2.42,
	"STEP_BACK_T": 2.92,
	"DROP_T": 3.2,
	"GRAB_T": 3.52,
	"fistCenter": 38.0,
	"grip": {"front": {"x": 34.0, "y": -14.0, "angle": -100.0}, "back": {"x": 58.0, "y": -16.0, "angle": -94.0}},
	"palms": {"front": {"x": 14.0, "y": -26.0, "angle": -40.0}, "back": {"x": 44.0, "y": -26.0, "angle": -36.0}},
	"defaultOrderDelay": 0.12,
	"kneeRaise": {"thigh": -150.0, "shin": 140.0, "foot": 80.0, "reachShin": 100.0, "reachFoot": 36.0},
	"headDodge": {"x": -22.0, "y": 26.0},
	"hunch": {"shoulder": 18.0, "neck": 22.0, "shoulderXFront": 40.0, "shoulderXBack": -10.0},
	# solve_arm bend per arm: 1 flexes the elbow (anatomical); -1 would hyperextend it.
	"bend": {"front": 1.0, "back": 1.0},
	"hang": {"x": -90.0, "lean": 6.0, "reach": 0.955, "dipReach": 0.985, "neck": -20.0},
	"chest": {"x": -84.0, "y": 150.0, "lean": 6.0, "neck": -6.0},
	"palmsHip": {"x": -76.0, "y": 60.0},
	"mantle": {"x": -44.0, "y": -16.0, "lean": 30.0, "neck": 12.0},
	# Game: the stand spot sits 8 units further in than the showcase (62) so the body capsule
	# clears the corner; the feet move with it.
	"stand": {"x": 70.0, "y": -178.0, "lean": 0.0, "neck": 0.0},
	"feet": {
		"stepUp": 44.0, "standFront": 50.0, "standBack": 84.0,
		"wallLow": [-68.0, 226.0], "wall": [-68.0, 96.0], "wallAngle": -55.0, "lip": [-42.0, -76.0], "climbSplit": 0.45,
		"plantTime": 0.1, "reachTime": 0.1,
	},
	"dangle": {"thigh": -5.0, "shin": 12.0, "foot": 48.0, "spread": 5.0, "swing": 5.0, "swingHz": 1.15, "swingDecay": 1.4},
	# Hanging breath (rig units) and its rate.
	"breath": 1.5,
	"breathHz": 0.35,
	# Game actions.
	"climbEnd": 0.28,  # showcase seconds after STAND_T
	# The climb plays the showcase timeline this many times faster (2.08 s -> 1.04 s).
	"climbSpeed": 2.0,
	# Bone turn limit while climbing (degrees per 1/60 s), smoothing the fast arm swaps.
	"climbMaxTurn": 22.0,
	"descendSpeed": 1.3,  # the descend is the climb played backwards, this much faster
	"descendCatchAge": 0.5,
	"juice": {
		"catchSwing": 7.0,
		"catchSwingHz": 1.1,
		"catchDecay": 0.7,
		"catchStretch": 0.07,
		"catchBounce": 10.0,
		"catchShake": 3.0,
		"catchShakeSeconds": 0.14,
		"tremor": 0.9,
		"tremorHz": 17.0,
		"tremorPx": 1.2,
		"strainSquash": 0.04,
		"landSquash": 0.08,
		"landDip": 7.0,
		"landSeconds": 0.22,
		"scarfGravity": 0.85,
		"scarfFall": 46.0,
		"scarfWhip": 26.0,
		"scarfWhipHz": 3.2,
		"scarfWhipDecay": 0.35,
		"headWhip": 5.0,
		"debrisGrab": {"count": 12, "life": 1.3, "speed": 70.0, "gravity": 900.0, "spread": 14.0},
		"debrisClimb": {"count": 8, "life": 1.2, "speed": 55.0, "gravity": 900.0, "spread": 12.0},
		"dust": {"count": 9, "life": 0.55, "speed": 60.0, "rise": 18.0, "spread": 70.0},
		"gripPuff": {"count": 3, "life": 0.35, "speed": 18.0, "rise": 10.0, "spread": 12.0},
		# Catch strength from the incoming speed: k = clamp(speed / catchSpeed, catchMin, catchMax).
		"catchSpeed": 900.0,
		"catchMin": 0.4,
		"catchMax": 1.5,
	},
	# Leap away from the wall: coil, push (takeoff), turn in the air (flip).
	"leap": {"duration": 0.26, "coil": 0.08, "push": 0.1, "flip": 0.17, "turn": [0.11, 0.23], "turnWidth": 0.24, "away": 40.0, "airVy": -900.0, "coilTuck": 0.8, "coilHipX": 8.0},
	# Drop: hands let go and the body blends into the falling pose.
	"drop": {"duration": 0.12, "airVy": 300.0, "away": 8.0},
}
