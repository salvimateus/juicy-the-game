## Hero landing after a long fall: slam into a deep three-point crouch (one leg stretched back, the
## other folded under the body, the front hand flat on the ground), hold, then rise. Authored facing
## right; times in seconds, distances in rig units (y down, ground at 0), angles in degrees.

const T := {
	"hero": {
		"duration": 1.05,
		# Slam: the hip overshoots below the hold depth and springs back by settle.
		"settle": 0.14,
		"overshoot": 16.0,
		# Hold until holdEnd (the head lifts during the hold), then rise to the idle stand.
		"holdEnd": 0.6,
		"breath": 1.5,
		"breathHz": 1.2,
		# Body: hip offset from the rest hip (rest hip 182 up: ~46% of it at the hold), torso lean
		# forward from vertical, head angle in the world (negative looks up).
		"hipX": 12.0,
		"hipY": 104.0,
		"lean": 50.0,
		"headDown": 12.0,
		"headUp": -8.0,
		# Forward leg: folded, foot planted under the chest, knee forward and up.
		"foldLeg": "back",
		"foldAnkle": [44.0, 0.0],
		# Open leg: thrown back, knee near the ground, boot up on its toes (contact x of the flat boot,
		# rolled by openFoot around the toe so the toe stays on the ground).
		"openLeg": "front",
		"openAnkle": [-171.0, 0.0],
		"openFoot": 70.0,
		# The near arm plants the hand flat on the ground ahead of the forward foot, nearly straight;
		# the far arm opens back and up for balance.
		"plantArm": "front",
		# The near shoulder slides to the chest side (like the crouch) so the arm reaches the ground.
		"plantShoulder": [60.0, 6.0],
		"plantHand": [126.0, 2.0],
		"freeArm": {"upper": 120.0, "fore": -20.0},
		"scarf": {"link1": -40.0, "link2": -24.0, "wave": 8.0, "waveHz": 2.0},
		"waistFollow": 0.7,
		"juice": {
			"squash": 0.12,
			"squashTime": 0.12,
			"dust": {"count": 7, "life": 0.4, "speed": 110.0, "rise": 26.0, "spread": 50.0, "dir": 0},
			"cloud": {"count": 7, "life": 0.45, "speed": 300.0, "rise": 30.0, "spread": 60.0, "scale": 2.0},
			"debris": {"sprite": "debris", "count": 9, "life": 0.8, "speed": 360.0, "up": 260.0, "gravity": 1500.0, "angle": -PI / 2.0, "cone": 2.4, "floor": 0.0, "restitution": 0.35, "spin": 10.0, "layer": "front"},
			"handDust": {"count": 5, "life": 0.45, "speed": 70.0, "rise": 18.0, "spread": 24.0, "dir": 1},
		},
	},
}
