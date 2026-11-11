## Flying kick (air only): windup into the kick pose (leg straight, sole forward), open-ended dive
## until contact or the ground, contact burst with a hitstop, recoil back flip. JS tracks are keyed
## on the JS animation phase u (before its hitstop); the game maps its own timeline onto it.
## Times in seconds, angles in degrees, distances in rig units, speeds in units/s.

const T := {
	# Game timeline.
	"windup": 0.2,
	"hitstop": 0.09,
	"recoil": 0.44,
	# JS phases the timeline plays: windup U_START..U_CONTACT, dive holds U_CONTACT, recoil
	# U_CONTACT..U_FLIP_END.
	"U_START": 0.29,
	"U_CONTACT": 0.46,
	"U_FLIP_END": 0.72,
	# Root motion: velocity ramps linearly from windupVel to diveVel over the windup, then holds.
	"windupVel": [300.0, -80.0],
	"diveVel": [1100.0, 380.0],
	# Recoil displacement (back and up), ease-out so it ends at rest at the flip apex.
	"recoilBack": 160.0,
	"recoilUp": 120.0,
	# Blend from the frozen pose into the recoil when the contact came before the leg armed.
	"earlyBlend": 0.08,
	# Forward tilt added to the JS body tilt while diving so the straight leg points along the dive
	# (0 keeps the JS horizontal kick); released over tiltRelease into the recoil.
	"diveTilt": 18.0,
	"tiltRelease": 0.15,
	# The last exitBlend of the recoil opens into the air pose at exitAirVy (the recoil ends at its
	# apex), so the host's exit crossfade has nothing left to snap.
	"exitBlend": 0.14,
	"exitAirVy": 0.0,
	# Per-bone turn limit (degrees per 1/60 s): smooths the entry crossfade, the kick snap and the
	# recoil arm swing.
	"maxTurn": 24.0,
	# Sheet only: when flying_kick_impact calls impact().
	"sheetImpactAt": 0.26,

	# JS clip (kick.tuning.js), phases u.
	"kickTilt": -54.0,
	"pivot": [0.0, -250.0],
	"rootRot": [[0.28, 0], [0.34, -16.2, "in"], [0.44, -54, "out"], [0.49, -58, "out"], [0.72, -360, "inOut"]],
	"squash": [[0.28, -1], [0.34, 0, "inOut"]],
	"hipY": [[0.28, -4], [0.34, 10, "inOut"], [0.7, 4, "inOut"]],
	"hipX": [[0.24, -8], [0.3, 6, "out"], [0.7, 0, "inOut"]],
	"torso": [[0.24, 26], [0.3, -8, "out"], [0.4, 2, "inOut"], [0.46, 0, "out"], [0.56, 20, "inOut"], [0.7, 6, "inOut"], [0.74, 4]],
	"neck": [[0.24, -10], [0.3, -6], [0.42, 34, "out"], [0.5, 34], [0.56, 30, "inOut"], [0.7, 0, "inOut"]],
	# Leg shapes, piecewise: kick 0 hang, 1 chamber, 2 straight; tuck 0 hang, 1 knee to the chest.
	"kickLeg": [[0.28, 0], [0.34, 1, "out"], [0.38, 1], [0.46, 2, "in"], [0.51, 2], [0.57, 1, "inOut"], [0.64, 1], [0.72, 0, "inOut"]],
	"tuckLeg": [[0.28, 0], [0.34, 1, "out"], [0.64, 1], [0.72, 0, "inOut"]],
	# Ankle targets from the hip joint and absolute foot angles.
	"legHang": [4.0, 146.0, 22.0],
	"legChamber": [58.0, 46.0, -10.0],
	"legTuck": [62.0, 26.0, 40.0],
	"legKick": [98.0, 109.0, -36.0],
	# Arms [u, upper, fore]: rise back and up, kick back and down, flip hugging the knees.
	"armF": [[0.24, [40, -20]], [0.31, [78, -24]], [0.38, [82, -20]], [0.46, [76, -14]], [0.51, [76, -14]], [0.56, [-55, -80]], [0.66, [-55, -80]], [0.72, [-40, -50]]],
	"armB": [[0.24, [46, -24]], [0.31, [88, -20]], [0.38, [100, -18]], [0.46, [104, -10]], [0.51, [104, -10]], [0.56, [-45, -80]], [0.66, [-45, -80]], [0.72, [-30, -50]]],

	# Contact point on the boot (bone space, footF): toe tip (58, 30) pushed toward the sole center.
	"sole": [32.0, 38.0],

	"juice": {
		"shakeAmp": 8.0,
		"shakeSeconds": 0.24,
		"shakeFreq": 36.0,
		"flash": 0.15,
		"flashSeconds": 0.04,
		"takeoffStretch": 0.1,
		"springAmp": 18.0,
		"springDecay": 0.2,
		"springFreq": 4.0,
		"springLife": 0.7,
		# Cloth flutter while diving (JS: 7 cycles over the clip).
		"diveFlutterHz": 6.0,
		"impact": {"life": 0.3, "radius": 72.0, "speed": 220.0},
		"spark": {"count": 10, "speed": 320.0, "gravity": 500.0, "star": false, "life": 0.3, "seed": 9},
		"windupGhost": {"at": 0.13, "count": 3, "spacing": 0.03, "alpha": 0.4, "life": 0.1},
		# Repeated while diving.
		"diveGhost": {"every": 0.12, "count": 3, "spacing": 0.03, "alpha": 0.35, "life": 0.12},
		"recoilGhost": {"at": 0.05, "count": 2, "spacing": 0.04, "alpha": 0.24, "life": 0.24},
	},
}
