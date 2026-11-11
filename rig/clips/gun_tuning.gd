class_name GunTuning
## Revolver (JS shoot + cock) and AK-47 (JS rifle) as game actions. Distances in rig units, angles
## in degrees, times in seconds of action time.

const T := {
	"revolver": {
		# Aim (Adventurer.set_gun_aim): barrel angle range, torso and neck follow, per-bone turn limit.
		"aimMin": -75.0,
		"aimMax": 60.0,
		"torsoFollow": 0.12,
		"neckFollow": 0.28,
		"maxTurn": 24.0,
		# revolver_aim entered from the carry (not chained from draw/fire/cock/recock) raises in
		# this long, with the draw's anticipation and the hammer cocking.
		"aimRaise": 0.24,
		# Carry overlay: the rest hold keeps part of the base arm swing, clamped (degrees) so the
		# flailing air arms do not lift the gun.
		"carry": {"swing": 0.35, "foreSwing": 0.3, "swingLimit": 40.0, "leanReach": 0.4},
		# Recock after a shot: thumb pulls the hammer back, click, wrist roll.
		"recock": {"duration": 0.18, "pull": [0.02, 0.12], "wrist": 8.0, "clickKick": -5.0, "clickKickDecay": 0.04,
			"glintLife": 0.2, "sparks": {"count": 3, "speed": 110.0, "life": 0.14, "gravity": 250.0, "angle": -PI / 2.0, "cone": 1.6, "star": false}},
		# Gun arm poses: upper is the arm's world angle (torso lean does not swing the aim), the
		# rest are local. rest is the low hold the holster ends in before handing back to the base.
		# rest is also the carry: low ready, elbow bent, muzzle down and forward.
		"rest": {"upper": -12.0, "fore": -50.0, "hand": 22.0},
		"aim": {"upper": -94.0, "fore": 0.0, "hand": 0.0},
		"lowerMid": {"upper": -48.0, "fore": -40.0, "hand": -6.0},
		"torsoAim": -3.0,
		"hipAimX": 3.0,
		"neckAim": 5.0,
		"frontArmAim": {"upper": 12.0, "fore": -34.0},
		# Draw: JS shoot raise (raiseStart 0.05 u to aimAt 0.24 u of a 2 s clip) from the base arm.
		"draw": {
			"duration": 0.38,
			"anticipationAt": 0.08,
			"anticipation": -0.08,
			"cock": [0.2, 0.36],
		},
		# Aim hold breathing (game loop).
		"breath": {"freq": 0.45, "upper": 1.2, "torso": 0.8, "neck": 0.6, "lift": 1.5},
		# Holster: JS shoot lower (0.68..0.9 u) with the two-turn finger spin, then back to the base.
		"holster": {
			"lower": 0.44,
			"aimFade": 0.52,
			"spin": [0.0, 0.4],
			"spinTurns": 2,
			"spinPivot": [58.5, 46.5],
			"decock": [0.0, 0.12],
			"baseBlend": 0.1,
			"duration": 0.56,
		},
		# Fire: the trigger window raises an uncocked hammer (double action), the shot drops it.
		"fire": {
			"trigger": 0.05,
			"settle": 0.36,
			"big": false,
		},
		"recoil": {
			"attack": 0.025,
			"decay": 0.075,
			"upper": -4.0,
			"fore": -12.0,
			"hand": -10.0,
			"torso": -3.0,
			"hipX": -3.0,
			"neck": -6.0,
			"neckLag": 0.02,
		},
		"juice": {
			"hitstop": 0.045,
			"shakeAmp": 3.0,
			"shakeSeconds": 0.14,
			"shakeFreq": 40.0,
			"recoilWobbleFreq": 5.0,
			"squash": 0.04,
			"headBlink": 0.08,
			"headBlinkSeconds": 0.07,
			"springAmp": 10.0,
			"springDecay": 0.16,
			"springFreq": 4.5,
			"flashLife": 3.0 / 60.0,
			"smoke": {"count": 3, "life": 0.75, "rise": 34.0, "spread": 6.0, "stagger": 0.05},
			"sparks": {"count": 4, "speed": 220.0, "life": 0.16, "cone": 0.7, "gravity": 300.0, "star": false, "angle": 0.0},
			"wisps": {"delay": 0.09, "count": 4, "spacing": 0.02, "life": 0.5, "rise": 30.0, "spread": 2.0},
		},
		# Cock (JS cock clip from the chest raise to the aim): the gun leaves the aim for the chest,
		# the thumb pulls the hammer (click), wrist twist, back to the aim with an overshoot.
		"cock": {
			"jsDuration": 1.8,
			"fromAim": 0.26,
			"raiseEnd": 0.26,
			"pull": [0.34, 0.5],
			"click": 0.5,
			"twist": [0.53, 0.63],
			"aim": [0.62, 0.74],
			"aimOvershoot": 0.06,
			"settle": 0.12,
			"pullTravel": 0.82,
			"clickSnap": 0.02,
			"chestGrip": [122.0, -262.0],
			"chestGunAngle": -38.0,
			"chestBend": 1.0,
			"torsoChest": -2.0,
			"neckChest": 9.0,
			"pullWrist": 6.0,
			"twistWrist": 20.0,
			"frontArm": {"upper": 10.0, "fore": -30.0},
			"juice": {
				"pullWindup": -6.0,
				"clickKick": -7.0,
				"clickKickDecay": 0.06,
				"nod": 5.0,
				"nodLag": 0.03,
				"nodDecay": 0.12,
				"squash": 0.025,
				"springAmp": 7.0,
				"springDecay": 0.18,
				"springFreq": 4.0,
				"shakeAmp": 1.0,
				"shakeSeconds": 0.06,
				"shakeFreq": 45.0,
				"glintLife": 0.3,
				"glintOffset": [-9.0, -9.0],
				"sparks": {"count": 5, "speed": 130.0, "life": 0.18, "gravity": 250.0, "angle": -PI / 2.0, "cone": 1.8, "star": false},
			},
		},
	},
	"rifle": {
		"aimMin": -45.0,
		"aimMax": 60.0,
		"torsoFollow": 0.12,
		"neckFollow": 0.28,
		"maxTurn": 24.0,
		# Carry overlay: low hold across the body, grip and rifle angle in torso space (given at the
		# idle rest pose, character space; + angle = muzzle down). maxAngle caps the muzzle drop when
		# the torso leans (crouch) so the barrel stays off the ground.
		"carry": {"x": 22.0, "y": -205.0, "angle": 34.0, "maxAngle": 50.0},
		# Raise: JS rifle raise (0.05..0.18 u of a 3 s clip) from the ready hold, the arms leaving
		# the base pose over enterBlend.
		"raise": 0.36,
		"raiseOvershoot": 0.06,
		"enterBlend": 0.1,
		"teethAt": 0.21,
		# Lower: JS rifle lower (0.84..0.97 u), then the arms hand back to the base pose.
		"lower": 0.34,
		# Rifle holds: grip position (character space) and rifle angle (0 level, + muzzle down).
		"ready": {"x": 30.0, "y": -235.0, "angle": 40.0},
		"shoulder": {"x": 64.0, "y": -218.0, "angle": 0.0},
		"supportShift": 24.0,
		"fistReach": 30.0,
		"fistIterations": 3,
		"shoulderShiftReady": 20.0,
		"shoulderShift": 46.0,
		# solve_arm bend for both arms: 1 flexes the elbow (down, under the gun); -1 would hyperextend it.
		"backBend": 1.0,
		"frontBend": 1.0,
		"torsoReady": 5.0,
		"torsoShoulder": 8.0,
		"neckShoulder": -8.0,
		# Burst: rounds per second of animation time; climb keys over the nominal burst length
		# (degrees, negative = muzzle up), looping from loopFrom on longer bursts.
		"fireRate": 11.0,
		"nominalBurst": 1.6,
		"climbKeys": [[0.0, 0.0], [0.33, -9.0], [0.41, -2.0, "out"], [0.68, -11.0], [0.76, -3.0, "out"], [1.0, -10.0]],
		"climbLoopFrom": 0.33,
		"climbRecover": 0.18,
		"recoil": {"attack": 0.012, "decay": 0.04, "back": 7.0, "angle": -2.5, "hip": -1.5, "torso": -1.2, "neck": -2.0, "neckLag": 0.015},
		"pushBack": {"hip": -6.0, "torso": -2.0, "rise": 0.25},
		"tremble": {"torso": 0.7, "neck": 1.2, "freqA": 23.0, "freqB": 31.0},
		# Mouth (mouth_shout frames 1 teeth, 2 open, 3 wide): wide on each kick after peakFrom of
		# the nominal burst; open until mouthAfter[0] past the last round, teeth until mouthAfter[1].
		"mouthLead": 0.03,
		"mouthPeakFrom": 0.2,
		"mouthWideFor": 0.045,
		"mouthAfter": [0.18, 0.36],
		# Heavy breathing after a burst (seconds after the last round).
		"breath": {"delay": 0.2, "length": 0.39, "breaths": 2},
		"heave": {"lift": 4.0, "torso": 2.5, "shoulders": 4.0},
		# Idle hold sway in the aim loop.
		"holdSway": {"freq": 0.4, "angle": 0.8, "lift": 1.2},
		"juice": {
			"hitstop": 0.028,
			"hitstopEvery": 6,
			"shakeBase": 1.2,
			"shakeKick": 2.2,
			"shakeFreq": 47.0,
			"squash": 0.025,
			"springAmp": 8.0,
			"springDecay": 0.2,
			"springFreq": 4.5,
			"flutterFreq": 9.0,
			"flutterAmp": 4.0,
			"flashLife": 2.0 / 60.0,
			"smokeEvery": 3,
			"smoke": {"count": 1, "life": 0.6, "rise": 26.0, "spread": 4.0},
			"afterSmoke": {"count": 5, "spacing": 0.05, "life": 0.5, "rise": 38.0, "spread": 3.0},
			"casings": {"speed": 200.0, "up": 120.0, "cone": 26.0, "gravity": 1500.0, "restitution": 0.35, "spin": 14.0, "floor": -4.0, "life": 1.6},
		},
	},
}
