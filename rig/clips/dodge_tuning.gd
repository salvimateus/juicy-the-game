class_name DodgeTuning
## Dodge: short explosive hop back against the facing, torso thrown back and head slipping away,
## then back to the guard. Times in seconds, distances in rig units, angles in degrees.

const T := {
	"duration": 0.7,
	# The showcase-paced tracks below play this many times faster in the game (0.7 s -> 0.35 s,
	# explosive part about 0.12 s).
	"speed": 2.0,
	# Another dodge, roll or roll_back may cancel this one from here on (game s); the game applies
	# its own threshold (dodge_chain_after) on top.
	"cancelFrom": 0.0,
	# Root motion back (distance and the window it happens in, eased out).
	"dodge_distance": 130.0,
	"moveStart": 0.035,
	"moveEnd": 0.2,
	# Feet: hop lift over the move window; the front foot pushes off on its toe first.
	"hopLift": 16.0,
	"pushToe": 18.0,
	"landStagger": {"front": 22.0, "back": -42.0},
	"IFRAMES": [0.04, 0.22],
	"WHOOSH_T": 0.05,
	"LAND_T": 0.2,
	"tracks": {
		"hipY": [[0, 0], [0.035, 12, "out"], [0.11, -4, "out"], [0.2, 4], [0.24, 16, "out"], [0.42, 10], [0.7, 0, "inOut"]],
		"hipX": [[0, 0], [0.035, 4], [0.11, -20, "out"], [0.22, -6], [0.42, -2], [0.7, 0, "inOut"]],
		"torso": [[0, 0], [0.035, 6], [0.1, -34, "out"], [0.2, -20], [0.3, 4, "out"], [0.42, 6], [0.7, 0, "inOut"]],
		"neck": [[0, 0], [0.035, 4], [0.1, -20, "out"], [0.22, -6], [0.32, 2], [0.7, 0, "inOut"]],
		"headX": [[0, 0], [0.1, -8, "out"], [0.24, -2], [0.7, 0, "inOut"]],
		"armF": [[0, 0], [0.06, -40, "out"], [0.42, -36], [0.7, 0, "inOut"]],
		"foreF": [[0, 0], [0.06, -105, "out"], [0.42, -100], [0.7, 0, "inOut"]],
		"armB": [[0, 0], [0.06, -24, "out"], [0.42, -22], [0.7, 0, "inOut"]],
		"foreB": [[0, 0], [0.06, -112, "out"], [0.42, -108], [0.7, 0, "inOut"]],
		"scarf1": [[0, -18], [0.06, -18], [0.14, 22, "out"], [0.26, 4], [0.4, -8], [0.7, -18, "inOut"]],
		"scarf2": [[0, 0], [0.08, 0], [0.16, 20, "out"], [0.28, -6], [0.4, 2], [0.7, 0, "inOut"]],
		"hair": [[0, 0], [0.12, 8, "out"], [0.4, 0, "inOut"]],
	},	"juice": {
		"crouchSquash": 0.05,
		"stretch": 0.05,
		"landSquash": 0.06,
		"ghost": {"count": 3, "spacing": 0.03, "alpha": 0.4, "life": 0.18},
		"pushDust": {"count": 4, "life": 0.3, "speed": 40.0, "rise": 12.0, "spread": 16.0},
		"landDust": {"count": 3, "life": 0.28, "speed": 26.0, "rise": 10.0, "spread": 20.0},
	},
}
