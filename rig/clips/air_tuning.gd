class_name AirTuning
## Double jump (kick down, tucked forward flip, open) and the short wall kick (straight up, still
## facing the wall). Times in seconds, angles in degrees, distances in rig units.

const T := {
	"doubleJump": {
		"duration": 0.36,
		"kickEnd": 0.06,
		"flipEnd": 0.31,
		"openVy": -300.0,
		# Kick: legs stretched down, toes pointing down, arms up.
		"kick": {"thigh": 4.0, "shin": 6.0, "footAbs": 50.0, "armF": 150.0, "armB": -150.0, "fore": -18.0, "stretch": 0.12},
		# Open: each arm to its side and up (dir/B forward-up, esq/F back-up), elbows slightly bent.
		"open": {"armF": 138.0, "foreF": -22.0, "armB": -138.0, "foreB": -22.0},
		# Tuck: knees to the chest, fists hugging the shins.
		"tuck": {"thighF": -118.0, "shinF": 132.0, "thighB": -104.0, "shinB": 128.0, "footAbs": 20.0, "lean": 18.0, "neck": 14.0},
		# Spin pivot relative to the hip joint (center of mass of the ball).
		"pivot": [16.0, -40.0],
		"puff": {"count": 9, "life": 0.4, "speed": 70.0, "rise": -30.0, "spread": 34.0, "dir": 0},
		"ghost": {"count": 3, "spacing": 0.04, "alpha": 0.4, "life": 0.24},
	},
	"wallKick": {
		"duration": 0.09,
		"push": 0.03,
		"away": 10.0,
		"airVy": -900.0,
		"stretch": 0.07,
	},
}
