## Bow (bow.tuning.js) and ninja strike (ninja.tuning.js) for the game actions. Distances in rig
## units, angles in degrees, times in seconds. Bow arm targets are torso-local (relative to the
## torso joint, before the torso rotation), as in the JS clip.

const BOW := {
	# JS timeline (s). bow_draw plays 0..drawEnd, bow_aim holds drawEnd, bow_release plays
	# releaseAt..duration, bow_cancel plays drawEnd..0 backwards.
	"duration": 2.4,
	"grabAt": 0.24,
	"nockAt": 0.62,
	"drawEnd": 1.02,
	"releaseAt": 1.44,

	"bowGripNock": [172.0, -138.0],
	"bowGrip": [198.0, -142.0],
	"bowAngle": -2.0,
	"shoulderShift": 46.0,
	# solve_arm bend of the drawing (front) arm: 1 flexes the elbow (under the hand at the jaw);
	# -1 would hyperextend it (elbow pointing up past the shoulder).
	"drawBend": 1.0,
	# Carry (no action playing): bow arm in a low ready, elbow bent and the bow nearly upright at the
	# hip (upper is a world angle, fore and hand local, degrees). The base pose and the draw start
	# from it; swing keeps part of the base arm swing, clamped to swingLimit; leanReach swings the
	# arm forward with part of the torso's forward lean.
	"carry": {"upper": -10.0, "fore": -55.0, "hand": -15.0, "swing": 0.35, "foreSwing": 0.3, "swingLimit": 40.0, "leanReach": 0.4},
	"bowRaise": [0.28, 0.62],
	"bowRaiseOvershoot": 0.08,
	"bowLower": [1.78, 2.2],
	"bowKick": 16.0,
	"bowKickSeconds": [0.06, 0.32],

	"frontIn": [0.0, 0.2],
	"frontOut": [1.6, 2.08],
	# [time, x, y, gripAngle]; "nock" / "draw" keys come from the bow geometry.
	"frontPath": [
		[0.2, -86.0, 6.0, 100.0],
		[0.32, -82.0, -30.0, 95.0],
		[0.44, 0.0, -20.0, 60.0],
		[0.54, 40.0, -100.0, 25.0],
		[0.62, "nock"],
		[1.44, "draw"],
		[1.52, 22.0, -152.0, -10.0],
	],
	"tipPastGrip": 0.0,
	"arrowAboveGrip": 6.0,

	"anticipationDrop": 5.0,
	"drawLean": -5.0,
	"releaseRecoil": -3.0,
	"headAim": 5.0,
	"headRelease": -6.0,
	"tremor": 1.4,
	"tremorFreq": 9.0,
	"stringVibe": {"amplitude": 5.0, "frequency": 16.0, "decay": 0.12},

	# Game aim (set_bow_aim): world arrow angle relative to facing-forward, clamped to this range.
	"aimMin": -80.0,
	"aimMax": 45.0,
	# Share of the aim taken by the torso lean; the bow arm swings the rest around the bow shoulder,
	# so the arrow points exactly along the aim. The neck follows the swing (aimNeck 1 keeps the
	# full-draw nock exactly at the jaw) up to aimNeckLimit. aimHip shifts the hip against the lean
	# (rig units per radian of aim).
	"aimTorso": 0.32,
	"aimNeck": 0.9,
	"aimNeckLimit": 40.0,
	"aimHip": 14.0,
	# Draw at power 0 (fraction of the full draw): the string stays visibly pulled.
	"powerMin": 0.15,
	# Tremor reaches full strength after this hold (JS: drawEnd to releaseAt); scaled by the draw.
	"tremorRamp": 0.42,
	# bow_cancel plays the draw backwards at this speed.
	"cancelSpeed": 1.3,
	# bow_aim per-bone turn limit (degrees per 1/60 s) for fast aim swings; the other bow actions
	# play the JS keys unlimited.
	"maxTurn": 24.0,
	# Bow string: rig units per string pixel (6 = one art pixel, 1 = the JS source-pixel line).
	"stringPixel": 6,
	"stringColor": "#e8e0c8",

	"juice": {
		"squash": 0.04,
		"drawStretch": 0.03,
		"releaseSquash": 0.05,
		"stringVibeBoost": 1.6,
		"bowKickBoost": 1.5,
		"springAmp": 10.0,
		"springDecay": 0.22,
		"springFreq": 3.5,
		"shakeAmp": 2.0,
		"shakeSeconds": 0.12,
		"shakeFreq": 30.0,
		"snap": {"count": 5, "speed": 160.0, "life": 0.16, "gravity": 0.0, "star": false, "seed": 41},
	},
}

const NINJA := {
	# Key moments (animation time before the hitstop). The cut is the hit frame.
	"VANISH_T": 0.2,
	"ARRIVE_T": 0.36,
	"CUT_T": 0.47,
	# Game ending (replaces the JS backflip home): the follow-through holds, then the back foot steps
	# up while the body advances over the planted front foot (root motion) into the idle stance.
	"recoverFrom": 0.64,
	"recoverTo": 0.9,
	"end": 1.08,
	# Back foot step lift during the recovery.
	"recoverLift": 16.0,
	# Reverse grip (grip bone degrees): ramps in over the crouch, twirls back to the forward grip
	# at the end (twirl window in animation time).
	"gripAngle": 150.0,
	"gripIn": 0.14,
	"gripTwirl": [0.86, 1.0],
	"dashDistance": 110.0,
	"maxTurn": 0.0,

	# JS tracks to the follow-through, then the recovery keys. Feet: [x offset, lift, roll].
	"tracks": {
		"hipX": [[0, 0], [0.16, -4], [0.36, 12, "out"], [0.47, 18, "out"], [0.62, 14], [0.9, 2, "inOut"], [1.0, 0, "inOut"]],
		"hipY": [[0, 0], [0.16, 36, "out"], [0.2, 30, "in"], [0.3, 22], [0.36, 40, "out"], [0.47, 44], [0.62, 40], [0.7, 38], [0.86, 4, "inOut"], [0.94, 8, "out"], [1.06, 0, "inOut"]],
		"torso": [[0, 0], [0.16, 24, "out"], [0.2, 30], [0.36, 34, "out"], [0.42, 14, "out"], [0.47, 46, "out"], [0.62, 36, "inOut"], [0.7, 32], [0.86, 2, "inOut"], [0.94, 5, "out"], [1.06, 0, "inOut"]],
		"neck": [[0, 0], [0.16, -10, "out"], [0.36, -18], [0.42, -4], [0.47, -24, "out"], [0.62, -16], [0.72, -12], [0.88, 2, "inOut"], [1.02, 0, "inOut"]],
		"armF": [[0, 0], [0.16, 24, "out"], [0.2, 60, "out"], [0.32, 70], [0.42, -160, "inOut"], [0.47, -40, "in"], [0.6, 18, "out"], [0.7, 22], [0.9, 2, "inOut"], [1.04, 0, "inOut"]],
		"elbowF": [[0, 0], [0.16, -24, "out"], [0.32, -40], [0.42, -100, "inOut"], [0.47, -12, "in"], [0.6, -46, "out"], [0.7, -44], [0.9, -6, "inOut"], [1.04, 0, "inOut"]],
		"armB": [[0, 0], [0.16, 30, "out"], [0.2, 70, "out"], [0.32, 74], [0.42, -50, "inOut"], [0.47, 40, "out"], [0.62, 30], [0.7, 28], [0.9, 2, "inOut"], [1.04, 0, "inOut"]],
		"elbowB": [[0, 0], [0.16, -30, "out"], [0.32, -50], [0.42, -100, "inOut"], [0.47, -70, "out"], [0.62, -60], [0.7, -56], [0.9, -6, "inOut"], [1.04, 0, "inOut"]],
		"hair": [[0, 0], [0.2, 10], [0.36, 18], [0.47, -6, "out"], [0.62, 10], [0.8, 6], [0.92, -3, "inOut"], [1.06, 0, "inOut"]],
		"scarf": [[0, 0], [0.16, -6], [0.24, 40, "out"], [0.36, 50], [0.47, 10, "out"], [0.62, 26], [0.8, 18], [0.94, -6, "inOut"], [1.06, 0, "inOut"]],
		"footF": [[0, [0, 0, 0]], [0.2, [0, 0, 0]], [0.28, [10, 14, 10], "out"], [0.36, [48, 0, 0], "in"]],
		"footB": [[0, [0, 0, 0]], [0.2, [0, 0, 18], "out"], [0.3, [-30, 16, 20], "out"], [0.36, [-60, 0, 14], "in"], [0.62, [-60, 0, 18]], [0.68, [-60, 0, 26], "inOut"]],
	},

	"juice": {
		"hitstop": 0.08,
		"shakeAmp": 4.0,
		"shakeSeconds": 0.14,
		"shakeFreq": 40.0,
		"squash": {"crouch": 0.07, "dash": -0.06, "cut": 0.05, "settle": 0.05},
		"springAmp": 14.0,
		"springDecay": 0.16,
		"springFreq": 5.0,
		"elbowLag": 10.0,
		"poof": {"count": 10, "radius": 52.0, "rise": 30.0, "life": 0.5, "seed": 23},
		"arrivePoof": {"count": 4, "radius": 26.0, "rise": 30.0, "life": 0.36, "seed": 57},
		"ghost": {"count": 5, "spacing": 0.03, "alpha": 0.55, "life": 0.32},
		"slash": {"x": 165.0, "y": -215.0, "angle": 0.0, "scale": 1.1, "life": 0.2},
		"slashSpark": {"count": 7, "speed": 240.0, "angle": 0.4, "cone": 2.2, "life": 0.24, "star": true, "seed": 61},
		"dust": {"count": 8, "life": 0.42, "speed": 50.0, "rise": 20.0, "spread": 44.0},
		"stepDust": {"count": 4, "life": 0.3, "speed": 30.0, "rise": 14.0, "spread": 30.0, "dir": 0},
	},
}
