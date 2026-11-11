## Interaction: sit on a chair (sit_down, sitting loop, stand_up) and sleep in a bed (lie_down,
## sleeping loop, get_up). Distances in rig units (6 per art pixel), angles in degrees.
##
## The seat / mattress height comes from the host (action_params rest_height, read when each
## action begins). The origin stands 120 in front of the seat point, back to the furniture.
##
## SIT keeps the JS sit clip timing: phases u in [0, 1) over SIT.duration; the game actions play
## slices of it (sit_down 0..settled, sitting loops the seated window, stand_up pushStart..1).
## SLEEP: yawn, sit on the bed edge (the chair sit), lie back flat along the bed; timelines in
## seconds per action.

const SIT := {
	"duration": 4.8,
	"moments": {
		"lookBack": 0.07,
		"sinkStart": 0.15,
		"seatContact": 0.33,
		"settled": 0.42,
		"pushStart": 0.74,
		"liftOff": 0.8,
		"standUp": 0.9,
	},
	# Seat point x (props.json chair.seat / bed.seat) and the seated hip x, character space.
	"seatX": -120.0,
	"seatHipX": -80.0,
	# Chair: the butt rests this far below the seat top, sunk into the cushion (the thighs cover
	# the seat edge); lower hips put the feet on the ground.
	"seat_sink": 34.0,
	# Thigh-local point of the butt underside that sits on the seat.
	"buttPoint": [-36.0, 6.0],
	# Seated ankles, x offset from rest. Front shin upright under its knee, back leg reaching
	# ahead, so the shins never cross.
	"seatFootX": {"front": 12.0, "back": 28.0},
	# Feet lift while they slide to the seated spot (0: they slide flat, as in the JS).
	"stepLift": 0.0,
	# Seats too high for the planted feet (hip-to-ankle beyond hangReach of the leg length): the
	# thigh rests on the seat sloping hangThigh down and the shins hang hangShin forward of
	# vertical (deg); blends in over hangBlend units past the reach.
	"hangReach": 0.98,
	"hangThigh": 8.0,
	"hangShin": {"front": 4.0, "back": 16.0},
	"hangBlend": 40.0,
	"leanDown": 30.0,
	"leanSeated": -2.0,
	"leanPush": 38.0,
	"lookBackNeck": -14.0,
	"lookBackTorso": -5.0,
	"breathLift": 1.6,
	"breathRot": 1.2,
	"breathPeriod": 1.5,
	"lookAround": [[0.46, -9.0], [0.53, -9.0], [0.58, 6.0], [0.64, 6.0], [0.69, 0.0]],
	"tapWindow": [0.5, 0.66],
	"taps": 4,
	"tapAngle": 16.0,
	# Sitting loop: the JS seated window (fidgets: look around, foot taps, heel bounce) plays
	# once, then the character only breathes for fidgetRest seconds.
	"fidgetRest": 2.6,
	# Chair FX points relative to the seat point (x, y down) and their delay.
	"puffs": [[-30.0, 0.0, -1], [44.0, 0.0, 1]],
	"creaks": [[48.0, 6.0, 1, 0.0], [-42.0, 8.0, -1, 0.03]],
	"juice": {
		"contactDrop": 6.0,
		"contactSquash": 0.09,
		"contactSeconds": 0.32,
		"standOvershoot": 6.0,
		"standStretch": 0.05,
		"springAmp": 14.0,
		"springFreq": 3.2,
		"springDecay": 0.22,
		"headLag": 5.0,
		"elbowFlare": 10.0,
		"legSwing": 10.0,
		"puffCount": 4,
		"creakLife": 0.32,
		"tapDust": true,
	},
}

const SLEEP := {

	# lie_down: yawn, sit on the bed edge (as on the chair), lie back flat with the legs swinging
	# up onto the bed. Keys in seconds.
	"lieDown": {
		"duration": 2.94,
		"seatContact": 1.86,
		"lieContact": 2.7,
		"yawn": [[0.0, 0.0], [0.08, 0.0], [0.56, 1.0, "out"], [0.76, 1.0], [1.12, 0.0, "in"]],
		"slouch": [[0.0, 0.0], [0.76, 0.0], [1.12, 1.0], [1.45, 0.3], [1.85, 0.0]],
		"sinkX": [[0.0, 0.0], [1.0, 0.0], [1.72, 1.0]],
		"sinkY": [[0.0, 0.0], [1.1, 0.0], [1.86, 1.0, "in"]],
		"seatLean": [[0.0, 0.0], [1.0, 4.0], [1.5, 30.0], [1.86, 21.0, "out"], [2.06, -2.0]],
		"hands": [[0.0, 0.0], [1.2, 0.0], [1.7, 1.0], [1.95, 1.0], [2.15, 0.0]],
		"sitBack": [[0.0, 0.0], [1.95, 0.0], [2.2, 1.0], [2.3, 1.0], [2.6, 0.0]],
		"lie": [[0.0, 0.0], [2.15, 0.0], [2.7, 1.0]],
		"asleep": [[0.0, 0.0], [2.7, 0.0], [2.94, 1.0, "linear"]],
	},
	# get_up: stretch on the bed, sit up with the legs swinging down, push on the knees and stand
	# (the chair stand-up). Keys in seconds.
	"getUp": {
		"duration": 2.2,
		"wakeAt": 0.16,
		"liftOff": 1.24,
		"standUp": 1.72,
		"asleep": [[0.0, 1.0], [0.16, 0.0, "linear"]],
		"wake": [[0.0, 0.0], [0.16, 0.0], [0.37, 1.0], [0.45, 1.0], [0.72, 0.0]],
		"lie": [[0.0, 1.0], [0.52, 1.0], [0.92, 0.0]],
		"swing": [[0.0, 0.0], [0.52, 0.0], [0.72, 1.0], [1.0, 0.3], [1.2, 0.0]],
		"hands": [[0.0, 0.0], [0.9, 0.0], [1.14, 1.0], [1.5, 1.0], [1.71, 0.0]],
		"seatLean": [[0.0, -2.0], [0.95, -2.0], [1.24, 38.0], [1.72, 4.0], [2.2, 0.0]],
		"sinkX": [[0.0, 1.0], [0.95, 1.0], [1.62, 0.0]],
		"sinkY": [[0.0, 1.0], [1.24, 1.0], [1.72, 0.0]],
	},

	"yawnArmF": -168.0,
	"yawnArmB": -158.0,
	"yawnElbow": -14.0,
	"yawnElbowMid": -85.0,
	"yawnArch": -9.0,
	"yawnNeck": -18.0,
	"slouchLean": 7.0,
	"slouchNeck": 8.0,
	"sitLean": -14.0,
	"sitArm": 32.0,
	"lieAngle": -80.0,
	# Lying flat: torso and neck (deg); legs straight along the body (ankle lieAnkle forward of
	# the hip joint, lieReach of the leg length below it), toes relaxed.
	"lieLean": 0.0,
	"lieNeck": 14.0,
	"lieAnkle": {"front": 22.0, "back": 2.0},
	"lieReach": 0.99,
	# Waist turn while lying (deg): swings the belt pouch toward the feet instead of below the back.
	"lieWaist": -40.0,
	"lieToe": {"front": 60.0, "back": 66.0},
	# Spine (body_line_y) below the mattress top when the bed gives none.
	"sinkDefault": 36.0,
	# Gap kept above the bottom of the covered band (units).
	"coverMargin": 4.0,
	# Front-to-back scale of the torso and waist while lying (fits the body in the covered band).
	"lieThin": 0.72,
	# Lie weight at which the legs are over the mattress: lie_down sends &"under_blanket" and
	# get_up &"out_of_blanket" there (the game swaps bed_front in front of / behind the character).
	"quiltAt": 0.55,
	# Arms along the body. [upper arm, elbow] (deg).
	"lieArmB": [58.0, -8.0],
	"lieArmF": [-18.0, -12.0],
	# Scarf [wrap tail, tip] turn while lying (deg), kept inside the covered band.
	"lieScarf": [-75.0, -20.0],
	# Feet arc above the straight path while the legs swing onto or off the bed.
	"legLift": 30.0,
	# Root settle onto the mattress fades in over this much of the lie weight.
	"settleIn": 0.25,
	"wakeArm": 4.0,
	"wakeToe": 28.0,
	"sitUpArm": -48.0,
	"breathPeriod": 2.4,
	# Chest rise while asleep (torso scale along its front, head counter-scaled).
	"bellyBreath": 0.045,

	# Zs (sleeping loop): [x from the head's center, gap above the top of the head]. Bursts of
	# zCount letters every zInterval, then zPause seconds of quiet.
	"zOffset": [6.0, 30.0],
	"zFirst": 0.0,
	"zCount": 5,
	"zInterval": 0.55,
	"zPause": 1.4,
	"zLife": 1.2,
	"zRise": 120.0,
	"zSway": 9.0,
	"zDrift": 60.0,

	"juice": {
		"yawnStretch": 0.06,
		"tiptoe": 12.0,
		"armDropOvershoot": 18.0,
		"landSquash": 0.09,
		"landSeconds": 0.28,
		"contactDrop": 5.0,
		"standOvershoot": 6.0,
		"standStretch": 0.05,
		"springAmp": 14.0,
		"springFreq": 3.0,
		"springDecay": 0.24,
		"wakeJolt": 6.0,
		"dustCount": 4,
	},
}
