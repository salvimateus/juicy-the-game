class_name JumpTuning
## Jump, air pose and landing. Times in seconds, distances in rig units, angles in degrees.
## Leg angles in the air are FK: thigh (negative swings the knee forward), shin (positive bends the
## knee), footAbs (absolute boot angle, positive points the toes down).

const T := {
	# Jump action: anticipation crouch, then the push; takeoff fires at the end.
	"duration": 0.1,
	"dip": [[0, 0], [0.055, 42, "out"], [0.1, -8, "in"]],
	"lean": [[0, 0], [0.05, 8, "out"], [0.1, 4]],
	"armWeight": [[0, 0], [0.04, 1, "out"], [0.1, 1]],
	"armSwing": [[0, 0], [0.055, 0, "out"], [0.1, 1, "in"]],
	"armsBack": {"armF": 34.0, "foreF": -20.0, "armB": -12.0, "foreB": -24.0},
	# Push: the arms open up, each to its side, elbows slightly bent. The dir arm (B) hangs from the
	# chest side of the 3/4 torso, so it opens forward and the esq arm (F) back: opened the other way
	# round both would cross the face.
	"armsUp": {"armF": 148.0, "foreF": -20.0, "armB": -148.0, "foreB": -20.0},
	# Hold the takeoff pose until the game reports airborne (s).
	"holdMax": 0.12,

	# Air: vertical speed mapped to -1 (rising fast) .. 0 (apex) .. 1 (falling fast).
	"airVyRange": 1000.0,
	# The arm opening forward (B) stays at least 30 degrees above horizontal (|armB| >= 120) so it
	# never reads as a punch; the back arm may sit level.
	"rise": {"hipY": -4.0, "torso": 8.0, "neck": -4.0, "thighF": -72.0, "shinF": 96.0, "footAbsF": 24.0, "thighB": -16.0, "shinB": 78.0, "footAbsB": 40.0,
		"armF": 148.0, "foreF": -20.0, "armB": -148.0, "foreB": -20.0, "scarf1": -32.0, "scarf2": -10.0, "hair": -8.0},
	"apex": {"hipY": 0.0, "torso": 4.0, "neck": 0.0, "thighF": -56.0, "shinF": 84.0, "footAbsF": 20.0, "thighB": -30.0, "shinB": 72.0, "footAbsB": 30.0,
		"armF": 96.0, "foreF": -22.0, "armB": -122.0, "foreB": -24.0, "scarf1": 2.0, "scarf2": 0.0, "hair": 0.0},
	"fall": {"hipY": 0.0, "torso": -4.0, "neck": 6.0, "thighF": -26.0, "shinF": 30.0, "footAbsF": 12.0, "thighB": 8.0, "shinB": 34.0, "footAbsB": 22.0,
		"armF": 108.0, "foreF": -30.0, "armB": -78.0, "foreB": -34.0, "scarf1": 40.0, "scarf2": 22.0, "hair": 10.0},
	# Running takeoff: the stride pose fades out over inheritDecay (s); lean per unit of run speed.
	"inherit": 0.85,
	"inheritDecay": 0.18,
	"speedLean": 9.0,
	# Crossfade from the ground into the air pose (s).
	"airBlend": 0.08,

	# Landing: strength = clamp((vy - landVyMin) / landVyRange, landMin, 1).
	"landVyMin": 200.0,
	"landVyRange": 1600.0,
	"landMin": 0.15,
	"landDip": 40.0,
	"landTime": 0.16,
	"landTimeStrong": 0.16,
	"landArms": 16.0,

	"juice": {
		"crouchSquash": 0.13,
		"pushStretch": 0.06,
		"riseStretch": 0.05,
		"fallStretch": 0.03,
		"scarfFlutter": 6.0,
		"scarfFlutterHz": 7.0,
		"landSquash": 0.12,
		"landSquashTime": 0.1,
		"landTorsoSquash": 0.06,
		"takeoffDust": {"count": 4, "life": 0.3, "speed": 36.0, "rise": 12.0, "spread": 20.0},
		"landDust": {"count": 4, "life": 0.4, "speed": 50.0, "rise": 16.0, "spread": 30.0},
		"landDustStrong": 6,
	},
}
