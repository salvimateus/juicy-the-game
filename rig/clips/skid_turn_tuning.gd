class_name SkidTurnTuning
## Skid turn: one half of the JS skid as a one-shot. The action starts where the feet dig in
## (SKID_T) and ends at HALF in a full run the other way. Times are seconds inside the JS half.

const HALF := 1.4
const SKID_T := 0.34
const STOP_T := 0.76
const TURN_T := 0.86
const FLIP_T := 0.95
const TURN_END := 1.04
const LAUNCH_T := 1.16

const T := {
	"skidEase": 1.4,
	"launchEase": 1.5,
	"skidBlend": 0.1,
	"launchBlend": 0.16,
	"skidLeadPhase": 0.0,
	"hop": 16.0,
	"flipWidth": 0.24,
	"flipTilt": -6.0,
	# Entry speed is clamped to this range (rig units/s) so a walk-speed skid still reads.
	"minEntrySpeed": 240.0,
	"tracks": {
		"hipY": [[SKID_T, 22], [SKID_T + 0.09, 46, "out"], [STOP_T - 0.06, 42], [STOP_T + 0.04, 52, "out"], [TURN_T, 46], [FLIP_T, 32, "out"], [TURN_END, 34, "in"], [TURN_END + 0.05, 50, "out"], [LAUNCH_T, 52], [LAUNCH_T + 0.1, 26, "out"], [LAUNCH_T + 0.2, 20]],
		"hipX": [[SKID_T, 0], [SKID_T + 0.09, 0, "out"], [STOP_T, -2], [STOP_T + 0.06, 4, "out"], [TURN_T, 4], [TURN_END, -4], [LAUNCH_T, -10], [LAUNCH_T + 0.12, 4, "out"], [LAUNCH_T + 0.2, 0]],
		"torso": [[SKID_T, 16], [SKID_T + 0.09, -28, "out"], [STOP_T - 0.06, -24], [STOP_T + 0.06, 8, "out"], [TURN_T, 2], [FLIP_T, -4], [TURN_END, 6], [TURN_END + 0.06, 18, "out"], [LAUNCH_T, 24], [LAUNCH_T + 0.08, 34, "out"], [LAUNCH_T + 0.2, 20]],
		"neck": [[SKID_T, -7], [SKID_T + 0.09, 12, "out"], [STOP_T - 0.06, 10], [STOP_T + 0.06, -10, "out"], [TURN_T, -2], [TURN_END, 0], [LAUNCH_T, -8], [LAUNCH_T + 0.08, -14], [LAUNCH_T + 0.2, -7]],
		"armF": [[SKID_T, 20], [SKID_T + 0.12, -38], [STOP_T - 0.06, -34], [STOP_T + 0.06, -64, "out"], [TURN_T, -36], [FLIP_T, 10], [TURN_END, 30], [LAUNCH_T, 52], [LAUNCH_T + 0.1, -30, "out"], [LAUNCH_T + 0.2, 0]],
		"foreF": [[SKID_T, -62], [SKID_T + 0.09, -16, "out"], [STOP_T, -14], [STOP_T + 0.06, -44, "out"], [TURN_T, -50], [FLIP_T, -100], [TURN_END, -70], [LAUNCH_T, -60], [LAUNCH_T + 0.2, -80]],
		"armB": [[SKID_T, -20], [SKID_T + 0.09, -52, "out"], [STOP_T - 0.06, -48], [STOP_T + 0.06, -80, "out"], [TURN_T, -72], [FLIP_T, -30], [TURN_END, 30], [LAUNCH_T, 48], [LAUNCH_T + 0.1, 60, "out"], [LAUNCH_T + 0.2, 40]],
		"foreB": [[SKID_T, -80], [SKID_T + 0.09, -16, "out"], [STOP_T, -16], [STOP_T + 0.06, -64, "out"], [TURN_T, -50], [FLIP_T, -100], [TURN_END, -70], [LAUNCH_T, -62], [LAUNCH_T + 0.2, -70]],
		"hair": [[SKID_T, -6], [SKID_T + 0.12, 4], [STOP_T - 0.06, 8], [STOP_T + 0.06, 22, "out"], [TURN_T, 8], [FLIP_T, -8], [TURN_END, -4], [LAUNCH_T, 2], [LAUNCH_T + 0.12, -12, "out"], [LAUNCH_T + 0.24, -6]],
		"scarf1": [[SKID_T, 10], [SKID_T + 0.14, 26], [STOP_T - 0.06, 32], [STOP_T + 0.08, 40, "out"], [TURN_T, 24], [FLIP_T, 20], [TURN_END, -10], [LAUNCH_T, 0], [LAUNCH_T + 0.14, 18, "out"], [LAUNCH_T + 0.24, 10]],
		"scarf2": [[SKID_T, 0], [SKID_T + 0.16, 10], [STOP_T - 0.04, 20], [STOP_T + 0.12, 34, "out"], [TURN_T + 0.04, 10], [FLIP_T + 0.03, -20], [TURN_END, -10], [LAUNCH_T, -6], [LAUNCH_T + 0.16, 12, "out"], [LAUNCH_T + 0.26, 0]],
		"frontX": [[SKID_T, 52], [SKID_T + 0.09, 90, "out"], [STOP_T, 88], [TURN_T, 88], [FLIP_T, 24], [TURN_END, -40, "out"], [LAUNCH_T, -40]],
		"frontAngle": [[SKID_T, -6], [SKID_T + 0.09, -26, "out"], [STOP_T, -22], [STOP_T + 0.05, -6, "out"], [TURN_T, 0], [FLIP_T, 14], [TURN_END, 0], [LAUNCH_T, 0], [LAUNCH_T + 0.06, 14]],
		"backX": [[SKID_T, -60], [SKID_T + 0.11, 18, "out"], [STOP_T, 22], [TURN_T, 22], [FLIP_T, -24], [TURN_END, 30, "out"], [LAUNCH_T, 30]],
		"backAngle": [[SKID_T, 26], [SKID_T + 0.11, -4, "out"], [STOP_T, -2], [TURN_T, 0], [FLIP_T, -12], [TURN_END, 0]],
		"backLift": [[SKID_T, 0], [SKID_T + 0.05, 30, "out"], [SKID_T + 0.11, 0, "in"], [TURN_T, 0], [FLIP_T, 22, "out"], [TURN_END, 0, "in"]],
		"frontLift": [[TURN_T, 0], [FLIP_T, 16, "out"], [TURN_END, 0, "in"]],
	},
	"juice": {
		"stopSquash": 0.1,
		"stopSquashSeconds": 0.18,
		"landSquash": 0.08,
		"launchStretch": 0.07,
		"skidSquash": 0.05,
		"springAmp": 10.0,
		"springFreq": 5.0,
		"springDecay": 0.12,
		"shakeAmp": 2.5,
		"shakeFreq": 26.0,
		"shakeSeconds": 0.2,
		"skidJitter": 1.6,
		"trail": {"interval": 0.024, "life": 0.6, "rise": 26.0, "kick": 70.0, "grow": 1.7, "smokeEvery": 2, "pebbleEvery": 3, "pebbleSpeed": 150.0, "pebbleUp": 210.0, "gravity": 900.0},
		"digDebris": {"count": 7, "life": 0.55, "speed": 170.0, "up": 140.0, "gravity": 800.0},
		"digDust": {"count": 7, "life": 0.45, "speed": 50.0, "rise": 20.0, "spread": 30.0},
		"stopCloud": {"count": 9, "life": 0.7, "speed": 90.0, "rise": 34.0, "spread": 40.0, "scale": 2.4},
		"landDust": {"count": 5, "life": 0.35, "speed": 40.0, "rise": 16.0, "spread": 34.0},
		"launchPuff": {"count": 8, "life": 0.5, "speed": 110.0, "rise": 22.0, "spread": 26.0, "scale": 1.8},
		"launchDebris": {"count": 5, "life": 0.5, "speed": 150.0, "up": 160.0, "gravity": 800.0},
		"launchGhost": {"count": 3, "spacing": 0.035, "alpha": 0.35, "life": 0.22},
	},
}
