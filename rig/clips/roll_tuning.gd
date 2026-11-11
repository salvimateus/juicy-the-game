class_name RollTuning
## Dodge roll. Tracks are [time, value, ease?] added on top of the rest pose; feet are
## [x offset from the rest ankle, lift, roll angle].

const T := {
	"duration": 1.75,
	"ROLL_START": 0.22,
	"ROLL_EXIT": 0.74,
	"HOP1": [1.0, 1.16],
	"HOP2": [1.22, 1.38],
	"pivotX": 30.0,
	"pivotY": -46.0,
	"PLANT_T": 0.2,
	"plantSpread": 10.0,
	"fistRadius": 15.0,
	"hopLift": 12.0,
	"clothStep": 12.0,
	# Game: ground covered by the roll (the showcase used 160 to fit its panel).
	"roll_distance": 440.0,
	"tuckFeet": {"front": [40.0, 46.0, 24.0], "back": [52.0, 56.0, 24.0]},
	"spinLinear": 0.3,
	"tracks": {
		"hipX": [[0, 0], [0.1, -6, "out"], [0.22, 24, "out"], [0.4, 6, "inOut"], [0.74, 0], [0.92, 0, "inOut"]],
		"hipY": [[0, 0], [0.1, 36, "out"], [0.2, 44, "inOut"], [0.7, 44], [0.76, 44, "out"], [0.92, 22, "back"], [1.0, 26], [1.08, 14], [1.16, 30, "in"], [1.22, 26], [1.3, 14], [1.38, 30, "in"], [1.46, 24], [1.6, -3, "inOut"], [1.72, 0, "inOut"]],
		"torso": [[0, 0], [0.1, 18, "out"], [0.2, 60, "inOut"], [0.28, 84, "out"], [0.62, 84], [0.7, 50], [0.78, 24, "out"], [0.92, 8, "back"], [1.38, 10], [1.6, -2, "inOut"], [1.72, 0, "inOut"]],
		"neck": [[0, 0], [0.1, -8, "out"], [0.2, -16], [0.3, 80, "out"], [0.6, 80], [0.7, 30], [0.8, -10, "out"], [0.94, -6], [1.38, -4], [1.62, 0, "inOut"]],
		"armF": [[0, 0], [0.1, 40, "out"], [0.22, -80, "inOut"], [0.6, -80], [0.74, 10, "inOut"], [0.86, -10, "out"], [0.94, -26, "out"], [1.38, -26], [1.62, 0, "inOut"]],
		"elbowF": [[0, 0], [0.1, -20, "out"], [0.22, -10, "inOut"], [0.6, -10], [0.74, -110, "inOut"], [0.86, -110, "out"], [0.94, -116, "out"], [1.38, -116], [1.62, 0, "inOut"]],
		"armB": [[0, 0], [0.1, 44, "out"], [0.22, -76, "inOut"], [0.6, -76], [0.74, 10, "inOut"], [0.86, -6, "out"], [0.94, -18, "out"], [1.38, -18], [1.62, 0, "inOut"]],
		"elbowB": [[0, 0], [0.1, -24, "out"], [0.22, -14, "inOut"], [0.6, -14], [0.74, -120, "inOut"], [0.86, -116, "out"], [0.94, -124, "out"], [1.38, -124], [1.62, 0, "inOut"]],
		"hair": [[0, 0], [0.1, 6], [0.22, 14], [0.74, 0], [0.84, -10, "out"], [1.0, 4], [1.6, 0, "inOut"]],
		"scarf": [[0, 0], [0.1, -8], [0.22, 30, "out"], [0.74, 20], [0.84, -12, "out"], [1.0, 8], [1.16, 20], [1.22, 6], [1.38, 20], [1.5, 4], [1.7, 0, "inOut"]],
		"hug": [[0, 0], [0.32, 0], [0.42, 1, "out"], [0.68, 1], [0.8, 0, "inOut"]],
		"tuck": [[0, 0], [0.24, 0], [0.32, 1, "out"], [0.6, 1], [0.7, 0, "inOut"]],
		"plant": [[0, 0], [0.12, 0], [0.2, 1, "inOut"], [0.34, 1], [0.42, 0, "inOut"]],
		"footF": [[0, [0, 0, 0]], [0.1, [0, 0, 14], "out"], [0.22, [0, 0, 24]], [0.3, [24, 10, 20], "out"], [0.38, [24, 0, 0], "inOut"], [0.7, [24, 0, 0]], [0.76, [24, 0, 14], "out"], [0.9, [24, 0, 0], "inOut"], [1.44, [24, 0, 0]], [1.52, [10, 10, -6], "out"], [1.6, [0, 0, 0], "in"]],
		"footB": [[0, [0, 0, 0]], [0.1, [0, 0, 12], "out"], [0.18, [0, 0, 16], "inOut"], [0.24, [0, 0, 26]], [0.32, [-14, 12, 10], "out"], [0.4, [-24, 0, 0], "inOut"], [0.7, [-24, 0, 0]], [0.76, [-24, 0, 18], "out"], [0.9, [-24, 0, 0], "inOut"], [1.38, [-24, 0, 0]], [1.48, [-10, 10, 8], "out"], [1.56, [0, 0, 0], "in"]],
	},
	"juice": {
		"squash": {"crouch": 0.07, "dive": -0.06, "exit": -0.08, "hop": 0.06},
		"exitSquash": 0.08,
		"exitSquashSeconds": 0.18,
		"spinTrail": 1.6,
		"springAmp": 12.0,
		"springDecay": 0.16,
		"springFreq": 5.0,
		"dust": {"count": 7, "life": 0.42, "speed": 46.0, "rise": 18.0, "spread": 40.0},
		"rollDust": {"count": 4, "life": 0.35, "speed": 30.0, "rise": 14.0, "spread": 30.0},
		"hopDust": {"count": 3, "life": 0.3, "speed": 24.0, "rise": 12.0, "spread": 18.0},
	},
	# Game timeline: [game start, game end, showcase start, showcase end] segments (s). The forward
	# roll skips the showcase crouch, rolls ROLL_START..ROLL_EXIT fast, pops into the guard and cuts
	# the two back hops (crossfaded over CUT_BLEND at the jump between segments).
	"timeline": [[0.0, 0.025, 0.12, 0.22], [0.025, 0.345, 0.22, 0.74], [0.345, 0.385, 0.74, 0.92], [0.385, 0.44, 1.5, 1.72]],
	# Backward roll: the forward roll played in reverse from the guard crouch.
	"timelineBack": [[0.0, 0.04, 0.92, 0.74], [0.04, 0.36, 0.74, 0.22], [0.36, 0.42, 0.22, 0.0]],
	"CUT_BLEND": 0.03,
	# Invulnerability (game seconds).
	"iframes": [0.02, 0.345],
	"iframesBack": [0.03, 0.36],
}
