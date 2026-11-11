class_name BoxingTuning
## Boxing punches and guard. Distances in rig units, angles in degrees, times in seconds.
## Each punch is one JS strike (start, impact, end in showcase u) played as its own action: the
## showcase timeline (anim_seconds per u) plus one hitstop on the impact.

const T := {
	# Seconds of animation per showcase u (JS duration 2.4 minus four 0.065 s hitstops).
	"anim_seconds": 2.14,
	# Guard stance the punches start and end in: crouch, staggered feet (lead = back leg forward).
	"crouch": 16.0,
	"leadAnkleX": 44.0,
	"rearAnkleX": -52.0,
	"heelLift": 7.0,
	"torsoLean": 7.0,
	"neckCounter": -5.0,
	# Guard wrists (torso-local) and glove angles relative to the torso; lead = back arm.
	"guardLead": {"x": 92.0, "y": -104.0, "angle": -48.0},
	"guardRear": {"x": 38.0, "y": -100.0, "angle": -70.0},
	"elbowBend": 1.0,
	"handLimit": 80.0,
	# Strikes: wind pulls the glove back before the snap, over overshoots past the reach; body
	# channels scale with the extension (negative during the wind-up).
	"punches": [
		{"id": &"punch_1", "name": "jab1", "arm": "back", "start": 0.17, "impact": 0.215, "end": 0.28, "aim": -8.0, "reach": 0.93, "wind": 0.14, "over": 0.08,
			"lean": 6.0, "hipX": 6.0, "hipY": 0.0, "shoulderLead": 10.0, "shoulderRear": -4.0, "rearHeel": 0.0, "neck": -3.0, "heavy": false},
		{"id": &"punch_2", "name": "jab2", "arm": "back", "start": 0.3, "impact": 0.345, "end": 0.41, "aim": -10.0, "reach": 0.95, "wind": 0.14, "over": 0.08,
			"lean": 7.0, "hipX": 7.0, "hipY": 0.0, "shoulderLead": 10.0, "shoulderRear": -4.0, "rearHeel": 0.0, "neck": -3.0, "heavy": false},
		{"id": &"punch_3", "name": "cross", "arm": "front", "start": 0.42, "impact": 0.5, "end": 0.58, "aim": -6.0, "reach": 0.95, "wind": 0.45, "over": 0.1,
			"lean": 20.0, "hipX": 20.0, "hipY": 2.0, "shoulderLead": -14.0, "shoulderRear": 50.0, "rearHeel": 30.0, "neck": -8.0, "heavy": true},
		{"id": &"punch_4", "name": "uppercut", "arm": "back", "start": 0.59, "impact": 0.665, "end": 0.75, "aim": -58.0, "reach": 0.7, "glove": -84.0, "wind": 0.75, "over": 0.1,
			"lean": -6.0, "hipX": 8.0, "hipY": -12.0, "shoulderLead": 8.0, "shoulderRear": -6.0, "rearHeel": 10.0, "neck": 4.0, "heavy": true},
	],
	# Wind-up key at this fraction of start..impact, overshoot key at this fraction of impact..end.
	"windAt": 0.45,
	"overAt": 0.18,
	# Next punch may start once this fraction of the recovery (after the hitstop) has played.
	"comboWindow": 0.3,
	# Guard overlay (set_guard) on top of idle and locomotion: arms, torso lean and neck only.
	"guard": {
		"torsoLean": 7.0,
		"neckCounter": -5.0,
		"bob": 1.5,
		"bobFreq": 1.6,
	},
	"juice": {
		"hitstop": 0.065,
		"shakeAmp": 4.0,
		"shakeHeavy": 1.4,
		"shakeSeconds": 0.14,
		"shakeFreq": 40.0,
		"gloveSquash": 0.22,
		"gloveStretch": 0.14,
		"squashNear": 0.02,
		"springAmp": 12.0,
		"springDecay": 0.16,
		"springFreq": 5.0,
		"springLife": 0.6,
		"sparks": 6,
		"sparkSpeed": 220.0,
		"sparkGravity": 300.0,
		"sparkLife": 0.2,
		"impactLife": 0.2,
		"impactLifeHeavy": 0.24,
		"ghostAlpha": 0.35,
		"ghostCount": 2,
		"ghostSpacing": 0.022,
		"ghostTail": 0.04,
		# Reach wind (Punch.reach_fx): lanes are [perpendicular offset px, fraction of the reach, delay s].
		"wind": {"life": 0.16, "lanes": [[-18.0, 0.8, 0.0], [0.0, 1.0, 0.0], [18.0, 0.65, 0.06]]},
	},
}
