class_name InteractionActions
extends RefCounted
## Interaction: sit on a chair and sleep in a bed. Ports of the JS sit and sleep clips.
##
## Chair: sit_down (chains into the sitting loop), sitting (INF, ended by stand_up), stand_up.
## Bed: lie_down (chains into the sleeping loop), sleeping (INF, Zs, ended by get_up), get_up.
## No root motion.
##
## Contract with the game (furniture art and numbers: FURNITURE_JSON, origin at the PNG's
## bottom-left, y up):
## - Anchor: the chair's seat_center_x on its seat top, the bed's center x on its mattress top.
##   The player origin stands SEAT_BACK (120) in front of the anchor, on the floor, back to the
##   furniture: CHAIR_SEAT / BED_SEAT are the anchor relative to the origin for facing 1 (x
##   mirrors for facing -1). furniture_origin gives the origin x from the PNG's left edge;
##   furniture_position / origin_for convert to the PNG top-left.
## - action_params (set by the interactable before the enter action; read in begin()):
##   rest_height = seat / mattress top above the floor; for the bed also pillow_x (pillow center
##   relative to the origin, facing 1). Missing keys fall back to FURNITURE_JSON. The host always holds a rest_height (default 90),
##   so the interactable must set it.
## - The hips go back onto the seat (butt at -rest_height); on the bed the body then lies back
##   flat on the mattress, head centered over the pillow, legs stretched toward the foot, and
##   gets up to the same spot. The game draws the furniture behind the Adventurer.
##
## Signals (action_event): sit_down &"seated"; stand_up &"lift_off", &"standing";
## lie_down &"seated", &"under_blanket", &"lying"; get_up &"awake", &"out_of_blanket", &"lift_off",
## &"standing". under_blanket / out_of_blanket: draw bed_front in front of / behind the character.

const X := preload("res://rig/clips/interaction_tuning.gd")
const B := preload("res://rig/rig_bone.gd")
const WAIST_FOLLOW := 0.7
const DEG := PI / 180.0
const FURNITURE_JSON := "res://game/art/furniture/furniture.json"
## Distance from the player origin back to the furniture anchor.
const SEAT_BACK := 120.0
## Anchor relative to the player origin, facing 1, for the shipped furniture.json (chair seat
## top 72, mattress top 138); seat_offset() recomputes them from the file.
const CHAIR_SEAT := Vector2(-120, -72)
const BED_SEAT := Vector2(-120, -138)
## Used when furniture.json is missing.
const FALLBACK := {
	"chair": {"texture": "res://game/art/furniture/chair.png", "width": 84, "height": 138, "seat_top_y": 72, "seat_center_x": 52},
	"bed": {"texture": "res://game/art/furniture/bed.png", "width": 570, "height": 222, "mattress_top_y": 138, "pillow_x": 96, "foot_x": 522},
}
## Draw preset while lying: the default order without the raised-back-arm swap (lying, the far
## arm is "above" the neck and would draw over the chest).
const ORDER_LYING := 50
const SETTLE_UPPER := ["body", "head", "thighF", "thighB"]

static var _furniture := {}


static func create(rig: RigData) -> Dictionary:
	var core := Core.new(rig)
	var sitting := Sitting.new(rig, core)
	var sleeping := Sleeping.new(rig, core)
	var out := {
		&"sit_down": SitDown.new(rig, core),
		&"sitting": sitting,
		&"stand_up": StandUp.new(rig, core, sitting),
		&"lie_down": LieDown.new(rig, core),
		&"sleeping": sleeping,
		&"get_up": GetUp.new(rig, core, sleeping),
	}
	# Pose sheet variants at another seat height (not for gameplay).
	var high := SitDown.new(rig, core)
	high.id = &"sit_down_h144"
	high.sheet_height = 144.0
	out[high.id] = high
	var high_loop := Sitting.new(rig, core)
	high_loop.id = &"sitting_h144"
	high_loop.sheet_height = 144.0
	out[high_loop.id] = high_loop
	return out


static func draw_orders() -> Dictionary:
	return {ORDER_LYING: []}


# ---------- furniture (for the game) ----------

## furniture.json entry for "chair" or "bed" (cached).
static func furniture(prop: String) -> Dictionary:
	if _furniture.is_empty():
		_furniture = FALLBACK.duplicate(true)
		if FileAccess.file_exists(FURNITURE_JSON):
			var data = JSON.parse_string(FileAccess.get_file_as_string(FURNITURE_JSON))
			if data is Dictionary:
				for key in data:
					if data[key] is Dictionary and _furniture.has(key):
						(_furniture[key] as Dictionary).merge(data[key], true)
	return _furniture[prop]


## Anchor in the PNG (x from the left, y up from the bottom): chair seat center on the seat top,
## bed center on the mattress top.
static func anchor(prop: String) -> Vector2:
	var f := furniture(prop)
	if prop == "chair":
		return Vector2(float(f.seat_center_x), float(f.seat_top_y))
	return Vector2(float(f.width) * 0.5, float(f.mattress_top_y))


## Anchor relative to the player origin, facing 1 (CHAIR_SEAT / BED_SEAT from the file).
static func seat_offset(prop: String) -> Vector2:
	return Vector2(-SEAT_BACK, -anchor(prop).y)


## Surface height (seat top / mattress top) from the file.
static func surface_height(prop: String) -> float:
	return anchor(prop).y


## World top-left of the furniture PNG for an Adventurer at origin; draw it with
## flip_h = facing < 0.
static func furniture_position(prop: String, origin: Vector2, facing: int) -> Vector2:
	var f := furniture(prop)
	var ax := anchor(prop).x
	var x := origin.x - SEAT_BACK - ax if facing >= 0 else origin.x + SEAT_BACK - (float(f.width) - ax)
	return Vector2(x, origin.y - float(f.height))


## Adventurer origin for furniture whose PNG top-left is at top_left (inverse of
## furniture_position).
static func origin_for(prop: String, top_left: Vector2, facing: int) -> Vector2:
	var f := furniture(prop)
	var ax := anchor(prop).x
	var x := top_left.x + SEAT_BACK + ax if facing >= 0 else top_left.x - SEAT_BACK + (float(f.width) - ax)
	return Vector2(x, top_left.y + float(f.height))


## Bed pillow center and foot x relative to the player origin, facing 1, from the file.
static func bed_offsets() -> Vector2:
	var f := furniture("bed")
	var ax := anchor("bed").x
	return Vector2(float(f.pillow_x) - ax - SEAT_BACK, float(f.foot_x) - ax - SEAT_BACK)


static func height_of(host, prop: String) -> float:
	return float(host.action_params.get(&"rest_height", surface_height(prop)))


## Height of the sleeper's spine above the floor (sunk into the mattress, under the blanket): the
## furniture dictionary in action_params, then furniture.json body_line_y, then rest_height minus
## SLEEP.sinkDefault.
static func body_line_of(host, rest: float) -> float:
	var spec = host.action_params.get(&"furniture", {})
	if spec is Dictionary and spec.has("body_line_y"):
		return float(spec.body_line_y)
	var f := furniture("bed")
	if f.has("body_line_y"):
		return float(f.body_line_y)
	return rest - float(X.SLEEP.sinkDefault)


static func pillow_of(host) -> float:
	return float(host.action_params.get(&"pillow_x", bed_offsets().x))


## Character origin x measured from the PNG's left edge (y 0 = floor), facing 1, for a
## furniture.json entry (used by the game's interactable to place the character).
static func furniture_origin(prop: String, spec: Dictionary) -> Vector2:
	var ax: float = float(spec.get("seat_center_x", 0.0)) if prop == "chair" else float(spec.get("width", 0.0)) * 0.5
	return Vector2(ax + SEAT_BACK, 0.0)


# ---------- FX ----------

static func _emit_creak(fx: RigFx, ev: Dictionary) -> void:
	var k := fx.e_age / fx.e_life
	if k > 0.9:
		return
	var frame := 0 if (k < 0.25 or (k > 0.5 and k < 0.7)) else 1
	fx.add(fx.rig.fx_sprite("sitCreak").id, frame, fx.e_x, fx.e_y, 1.0, float(ev.get("dir", 1)) * fx.e_facing, 1.0, 0.0)


static func _emit_z(fx: RigFx, ev: Dictionary) -> void:
	var S: Dictionary = X.SLEEP
	var k := fx.e_age / fx.e_life
	var sway: float = sin(TAU * (fx.e_age * 0.8 + fx.rand(1))) * S.zSway
	var x: float = fx.e_x + (sway + S.zDrift * k) * fx.e_facing
	var y: float = fx.e_y - S.zRise * k
	var frame := 1 if (ev.get("big", false) and k > 0.18) else 0
	fx.add(fx.rig.fx_sprite("sleepZ").id, frame, x, y, 1.0)


static func _ring(ts: float, amp: float, decay: float, freq: float) -> float:
	if ts < 0.0:
		return 0.0
	return amp * exp(-ts / decay) * sin(TAU * freq * ts)


## 0 -> 1 -> 0 over `seconds` after ts = 0.
static func _bump(ts: float, seconds: float) -> float:
	var k := ts / seconds
	return sin(PI * minf(1.0, k * 2.0)) * (1.0 - k) if (k > 0.0 and k < 1.0) else 0.0


static func _w01(u: float, a: float, b: float) -> float:
	return clampf((u - a) / (b - a), 0.0, 1.0)


## First time in [0, duration] where the track crosses value (rising or falling).
static func _cross(track: RigTrack, value: float, duration: float, rising: bool) -> float:
	var steps := 400
	for i in steps + 1:
		var t := duration * i / steps
		var v := track.sample(t)
		if (rising and v >= value) or (not rising and v <= value):
			return t
	return duration


static func _tracks(keys: Dictionary, names: Array, time_scale := 1.0) -> Dictionary:
	var out := {}
	for n: String in names:
		out[n] = RigTrack.from_keys(keys[n], time_scale)
	return out


## Shared solver: seated hip height per seat height, seated legs, hands on the knees, the JS sit
## pose and the bed pose.
class Core:
	var rig: RigData
	var world := PackedFloat32Array()
	var butt: Array = []
	var sit: Dictionary
	var _hip_cache := {}
	var _bed_cache := {}
	var _upper := PackedStringArray()

	func _init(rig_data: RigData) -> void:
		rig = rig_data
		world = RigMath.create_world(rig)
		var S: Dictionary = X.SIT
		var M: Dictionary = S.moments
		for b in [B.THIGH_F, B.THIGH_B]:
			butt.append([b, S.buttPoint[0], S.buttPoint[1]])
		_upper = PackedStringArray(InteractionActions.SETTLE_UPPER)
		var mid: float = (M.sinkStart + M.seatContact) / 2.0 + 0.02
		sit = {
			"sinkX": RigTrack.from_keys([[0.0, 0.0], [M.sinkStart, 0.0], [M.seatContact - 0.03, 1.0, "inOut"], [M.pushStart, 1.0], [M.standUp - 0.02, 0.0, "inOut"]]),
			"sinkY": RigTrack.from_keys([[0.0, 0.0], [M.sinkStart + 0.02, 0.0], [M.seatContact, 1.0, "in"], [M.liftOff, 1.0], [M.standUp, 0.0, "inOut"]]),
			"lean": RigTrack.from_keys([[0.0, 0.0], [M.lookBack, S.lookBackTorso], [M.sinkStart, 4.0], [mid, S.leanDown], [M.seatContact, S.leanDown * 0.7, "out"], [M.settled, S.leanSeated, "inOut"], [M.pushStart, S.leanSeated], [M.liftOff, S.leanPush, "inOut"], [M.standUp, 4.0, "inOut"], [1.0, 0.0, "inOut"]]),
			"look": RigTrack.from_keys([[0.0, 0.0], [M.lookBack, S.lookBackNeck], [M.sinkStart + 0.04, S.lookBackNeck * 0.6], [M.seatContact, 0.0]] + S.lookAround + [[1.0, 0.0]]),
			"hands": RigTrack.from_keys([[0.0, 0.0], [M.sinkStart + 0.04, 0.0], [M.seatContact - 0.04, 1.0, "inOut"], [M.pushStart + 0.04, 1.0], [M.standUp - 0.01, 0.0, "inOut"]]),
		}

	## Hip y offset that rests the butt on a seat h above the ground (feet seated).
	func seat_hip_y(h: float) -> float:
		var key := snappedf(h, 0.01)
		if _hip_cache.has(key):
			return _hip_cache[key]
		var p := RigPose.new(rig)
		var y := 60.0
		for i in 8:
			p.reset()
			p.x[B.HIP] = X.SIT.seatHipX
			p.y[B.HIP] = y
			seated_legs(p, 1.0, 0.0, 0.0, h, y)
			y += -h - lowest(p, butt)
		_hip_cache[key] = y
		return y

	func lowest(pose: RigPose, points: Array) -> float:
		RigMath.compute_world(rig, pose, world)
		var m := -INF
		for c: Array in points:
			var o: int = c[0] * 6
			m = maxf(m, world[o + 1] * c[1] + world[o + 3] * c[2] + world[o + 5])
		return m

	## Ankles at their seated spot (s = 1) or at rest (s = 0) for a seat h high; angles roll the
	## boots (radians). hip_y overrides the seated hip height (used while solving it).
	func seated_legs(pose: RigPose, s: float, front_angle: float, back_angle: float, h: float, hip_y := INF) -> void:
		for side in ["front", "back"]:
			var angle := front_angle if side == "front" else back_angle
			var a := seated_ankle(side, s, angle, h, hip_y)
			RigMath.solve_leg(rig, pose, side, a.x, a.y, angle)

	## Ankle (character space) between rest (s = 0) and seated (s = 1), the front foot first.
	func seated_ankle(side: String, s: float, angle: float, h: float, hip_y := INF) -> Vector2:
		var k := _step(side, s)
		var rest := RigMath.planted_ankle(rig.rest_ankle_x(side), 0.0, angle)
		var a := rest.lerp(_seat_target(side, angle, h, seat_hip_y(h) if is_inf(hip_y) else hip_y), k)
		a.y -= float(X.SIT.stepLift) * sin(PI * k)
		return a

	## Seated ankle: planted ahead on the floor (JS sit) whenever the leg reaches it; on a seat too
	## high for that the thigh rests on the seat and the shin hangs, the foot off the floor.
	func _seat_target(side: String, angle: float, h: float, hip_y: float) -> Vector2:
		var S: Dictionary = X.SIT
		var leg: RigData.Leg = rig.legs[side]
		var floor_a := RigMath.planted_ankle(seated_ankle_x(side, 1.0), 0.0, angle)
		var jx := rig.bone_x[B.HIP] + float(S.seatHipX) + leg.hip_x
		var jy := rig.bone_y[B.HIP] + hip_y + leg.hip_y
		var ts: float = deg_to_rad(S.hangThigh)
		var ss: float = deg_to_rad(S.hangShin[side])
		var hang := Vector2(jx + leg.upper * cos(ts) + leg.lower * sin(ss), jy + leg.upper * sin(ts) + leg.lower * cos(ss))
		# Hang only when the planted ankle is out of the leg's reach.
		var reach: float = (leg.upper + leg.lower) * float(S.hangReach)
		var d := clampf((floor_a.distance_to(Vector2(jx, jy)) - reach) / float(S.hangBlend), 0.0, 1.0)
		return Vector2(lerpf(floor_a.x, hang.x, d), lerpf(floor_a.y, minf(hang.y, floor_a.y), d))

	func _step(side: String, s: float) -> float:
		return RigMath.smooth01(s * 1.6) if side == "front" else RigMath.smooth01(s * 1.6 - 0.6)

	func seated_ankle_x(side: String, s: float) -> float:
		return rig.rest_ankle_x(side) + float(X.SIT.seatFootX[side]) * s

	## Fists on the thighs / knees, blended over the current arm rotation by w.
	func hands_on_legs(pose: RigPose, w: float, on_knee: float) -> void:
		if w <= 0.0:
			return
		RigMath.compute_world(rig, pose, world)
		var sides := [["front", B.THIGH_F, B.SHIN_F, B.UPPER_ARM_F], ["back", B.THIGH_B, B.SHIN_B, B.UPPER_ARM_B]]
		var targets: Array = []
		for sd: Array in sides:
			var kx := world[sd[2] * 6 + 4]
			var ky := world[sd[2] * 6 + 5]
			var hx := world[sd[1] * 6 + 4]
			var hy := world[sd[1] * 6 + 5]
			targets.append(Vector2(lerpf(lerpf(hx, kx, 0.6), kx - 4.0, on_knee), lerpf(lerpf(hy, ky, 0.6), ky, on_knee) - 18.0))
		for i in sides.size():
			var sd: Array = sides[i]
			var upper: int = sd[3]
			var free0 := pose.rot[upper]
			var free1 := pose.rot[upper + 1]
			var free2 := pose.rot[upper + 2]
			var tg: Vector2 = targets[i]
			RigMath.solve_arm(rig, pose, sd[0], tg.x, tg.y, world, true, 1.0)
			pose.rot[upper] = lerpf(free0, pose.rot[upper], w)
			pose.rot[upper + 1] = lerpf(free1, pose.rot[upper + 1], w)
			pose.rot[upper + 2] = lerpf(free2, pose.rot[upper + 2], w)

	# ---------- chair (JS sit) ----------

	## JS sit pose at phase u on a seat seat_top high; since_contact is the time since the seat contact
	## (s), which drives the seated breath and the contact follow-through across the loop.
	func sit_pose(u: float, since_contact: float, seat_top: float, pose: RigPose, juice: bool) -> void:
		var S: Dictionary = X.SIT
		# The hips sink into the cushion: the butt rests seat_sink below the seat top.
		var h: float = seat_top - float(S.seat_sink)
		var M: Dictionary = S.moments
		var J: Dictionary = S.juice
		var D: float = S.duration
		RigLocomotion.sample_idle(rig, pose, 0.0, juice)
		var sx: float = sit.sinkX.sample(u)
		var sy: float = sit.sinkY.sample(u)
		var seated := InteractionActions._w01(u, M.seatContact, M.settled) * (1.0 - InteractionActions._w01(u, M.pushStart, M.liftOff))
		var lean: float = sit.lean.sample(u)
		var look: float = sit.look.sample(u)
		var breath := (0.5 - 0.5 * cos(TAU * since_contact / S.breathPeriod)) * seated

		pose.x[B.HIP] = lerpf(pose.x[B.HIP], S.seatHipX, sx)
		pose.y[B.HIP] = lerpf(pose.y[B.HIP], seat_hip_y(h), sy)
		pose.rot[B.TORSO] += (lean + S.breathRot * breath) * DEG
		pose.y[B.TORSO] -= S.breathLift * breath
		pose.rot[B.NECK] += (look - lean * 0.45) * DEG
		pose.rot[B.UPPER_ARM_F] -= lean * 0.5 * DEG
		pose.rot[B.UPPER_ARM_B] -= lean * 0.4 * DEG

		if juice:
			var span: float = J.contactSeconds / D
			var c := InteractionActions._w01(u, M.seatContact, M.seatContact + span)
			var hit := sin(PI * minf(1.0, c * 2.2)) * sqrt(1.0 - c) if (c > 0.0 and c < 1.0) else 0.0
			pose.y[B.HIP] += J.contactDrop * hit
			RigMath.squash(pose, B.TORSO, J.contactSquash * hit)
			var p := InteractionActions._w01(u, M.standUp - 0.04, M.standUp + 0.07)
			var pop := sin(PI * p) if (p > 0.0 and p < 1.0) else 0.0
			pose.y[B.HIP] -= J.standOvershoot * pop
			if hit == 0.0:
				RigMath.squash(pose, B.TORSO, -J.standStretch * pop)
			var fade := clampf((1.0 - u) / 0.04, 0.0, 1.0)
			var since_stand: float = (u - M.standUp) * D
			var rc := func(amp: float) -> float: return InteractionActions._ring(since_contact, amp, J.springDecay, J.springFreq) * fade
			var rs := func(ts: float, amp: float) -> float: return InteractionActions._ring(ts, amp, J.springDecay, J.springFreq) * fade
			pose.rot[B.NECK] += (rc.call(J.headLag) - rs.call(since_stand, J.headLag * 0.6)) * DEG
			var spring: float = rc.call(J.springAmp) + rs.call(since_stand + 0.03 * D, -J.springAmp * 0.8)
			pose.rot[B.HAIR] += spring * 0.5 * DEG
			pose.rot[B.SCARF1] += spring * DEG
			pose.rot[B.SCARF2] -= spring * 1.4 * DEG
			pose.rot[B.FORE_ARM_F] += rc.call(-J.elbowFlare) * DEG
			pose.rot[B.FORE_ARM_B] += rc.call(-J.elbowFlare) * DEG
		# Seated, the scarf tail droops over the backrest instead of floating.
		pose.rot[B.SCARF1] += 10.0 * seated * DEG

		var tap := 0.0
		var w := InteractionActions._w01(u, S.tapWindow[0], S.tapWindow[1])
		if w > 0.0 and w < 1.0:
			tap = -S.tapAngle * pow(maxf(0.0, sin(PI * S.taps * w)), 0.6) * DEG
		var swing := 0.0
		if juice:
			var ws := InteractionActions._w01(u, M.settled, M.pushStart)
			swing = J.legSwing * sin(PI * ws) * maxf(0.0, sin(TAU * 3.0 * ws)) * DEG
		seated_legs(pose, sx, tap, swing, h)
		hands_on_legs(pose, sit.hands.sample(u), 1.0)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)

	# ---------- bed ----------

	## Channels (optional, default 0): h (mattress height), yawn, slouch, sx, sy, seatLean, hands,
	## sitBack, lie, wake, swing, asleep, breathT (s into the breath cycle) and the times since the
	## key moments (s, negative before): tYawnEnd, tSeat, tLie, tWake, tStand.
	func sleep_pose(ch: Dictionary, pose: RigPose, juice: bool, slide := true) -> void:
		var L: Dictionary = X.SLEEP
		var J: Dictionary = L.juice
		var h: float = ch.get("h", 90.0)
		var yawn: float = ch.get("yawn", 0.0)
		var slouch: float = ch.get("slouch", 0.0)
		var sx: float = ch.get("sx", 0.0)
		var sy: float = ch.get("sy", 0.0)
		var seat_lean: float = ch.get("seatLean", 0.0)
		var sit_back: float = ch.get("sitBack", 0.0)
		var lie: float = ch.get("lie", 0.0)
		var wake: float = ch.get("wake", 0.0)
		var swing: float = ch.get("swing", 0.0)
		var asleep: float = ch.get("asleep", 0.0)
		var never := -100.0
		var t_yawn_end: float = ch.get("tYawnEnd", never)
		var t_seat: float = ch.get("tSeat", never)
		var t_lie: float = ch.get("tLie", never)
		var t_wake: float = ch.get("tWake", never)
		var t_stand: float = ch.get("tStand", never)
		var breath := (0.5 - 0.5 * cos(TAU * float(ch.get("breathT", 0.0)) / L.breathPeriod)) * asleep
		RigLocomotion.sample_idle(rig, pose, 0.0, juice)

		# Lying, the hip straightens back out of the seated crouch so the legs can stretch.
		pose.y[B.HIP] = lerpf(pose.y[B.HIP], seat_hip_y(h), sy * (1.0 - lie))
		pose.x[B.HIP] = lerpf(pose.x[B.HIP], X.SIT.seatHipX, sx * (1.0 - lie))
		var lean: float = L.yawnArch * yawn + L.slouchLean * slouch + lerpf(seat_lean, L.lieLean, lie) + L.sitLean * sit_back
		pose.rot[B.TORSO] += lean * DEG
		pose.rot[B.NECK] += (L.yawnNeck * yawn + L.slouchNeck * slouch - lean * 0.4 * (1.0 - lie) + L.lieNeck * lie * (1.0 - wake)) * DEG

		for arm_def in [[B.UPPER_ARM_F, B.FORE_ARM_F, L.yawnArmF, L.lieArmF, 0.5], [B.UPPER_ARM_B, B.FORE_ARM_B, L.yawnArmB, L.lieArmB, 0.4]]:
			var upper: int = arm_def[0]
			var fore: int = arm_def[1]
			var lie_arm: Array = arm_def[3]
			var arm := pose.rot[upper] - seat_lean * float(arm_def[4]) * DEG * (1.0 - lie)
			var elbow := pose.rot[fore]
			arm = lerpf(arm, L.sitArm * DEG, sit_back * sy)
			arm = lerpf(arm, float(lie_arm[0]) * DEG, lie)
			elbow = lerpf(elbow, float(lie_arm[1]) * DEG, lie * (1.0 - wake))
			arm = lerpf(arm, L.wakeArm * DEG, wake)
			arm += L.sitUpArm * swing * DEG
			arm = lerpf(arm, float(arm_def[2]) * DEG, yawn)
			elbow = lerpf(elbow, L.yawnElbow * DEG, yawn) + L.yawnElbowMid * sin(PI * minf(1.0, yawn * 1.15)) * DEG
			pose.rot[upper] = arm
			pose.rot[fore] = elbow
		# Scarf: droops over the bed edge while seated, lies along the body when lying.
		pose.rot[B.SCARF1] += (float(L.lieScarf[0]) * lie + 10.0 * sy * (1.0 - lie)) * DEG
		pose.rot[B.SCARF2] += float(L.lieScarf[1]) * lie * DEG
		pose.rot[B.HAIR] += -6.0 * lie * DEG

		var tiptoe := 0.0
		if juice:
			var ring := func(ts: float, amp: float) -> float: return InteractionActions._ring(ts, amp, J.springDecay, J.springFreq)
			tiptoe = J.tiptoe * yawn
			RigMath.squash(pose, B.TORSO, -J.yawnStretch * yawn - J.yawnStretch * 0.8 * wake)
			var drop: float = ring.call(t_yawn_end + 0.08, J.armDropOvershoot) * (1.0 - sx)
			pose.rot[B.UPPER_ARM_F] += drop * DEG
			pose.rot[B.UPPER_ARM_B] += drop * 0.8 * DEG
			var seat_hit := InteractionActions._bump(t_seat, J.landSeconds)
			var land := seat_hit + InteractionActions._bump(t_lie, J.landSeconds) * 0.7
			pose.y[B.HIP] += J.contactDrop * seat_hit
			if land > 0.0:
				RigMath.squash(pose, B.TORSO, J.landSquash * land)
			var spring: float = ring.call(t_seat, J.springAmp) + ring.call(t_lie, J.springAmp * 0.6) + ring.call(t_yawn_end, J.springAmp * 0.5) + ring.call(t_stand, -J.springAmp * 0.8)
			pose.rot[B.HAIR] += spring * 0.5 * DEG
			pose.rot[B.SCARF1] += spring * DEG * (1.0 - lie * 0.7)
			pose.rot[B.SCARF2] -= spring * 1.4 * DEG * (1.0 - lie * 0.7)
			pose.rot[B.NECK] += (ring.call(t_seat, 5.0) - J.wakeJolt * InteractionActions._bump(t_wake, 0.5)) * DEG
			var pop := InteractionActions._bump(t_stand + 0.2, 0.55)
			pose.y[B.HIP] -= J.standOvershoot * pop
			if land <= 0.0:
				RigMath.squash(pose, B.TORSO, -J.standStretch * pop)

		seated_legs(pose, sx, tiptoe * DEG, tiptoe * DEG, h)
		hands_on_legs(pose, ch.get("hands", 0.0), 1.0)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		if lie > 0.0:
			# Lying, the body flattens a little front to back so it fits under the blanket; the
			# head keeps its shape.
			var thin := lerpf(1.0, L.lieThin, RigMath.smooth01(lie))
			pose.sx[B.TORSO] *= thin
			pose.sx[B.WAIST] *= thin
			pose.sx[B.HEAD] /= thin
		_place_on_bed(pose, h, float(ch.get("line", h)), lie, sx, wake, bed_shift(h, float(ch.get("line", h)), ch.get("pillow", InteractionActions.bed_offsets().x)) if slide else 0.0)
		if lie > X.SLEEP.quiltAt:
			pose.draw_order = InteractionActions.ORDER_LYING
		# Breath after the settle: the chest rises, nothing slides.
		if breath > 0.0:
			var k: float = 1.0 + L.bellyBreath * breath
			pose.sx[B.TORSO] *= k
			pose.sx[B.HEAD] /= k

	## Lying spins the body around the butt, slides it so the head ends on the pillow and settles
	## it on the mattress; the feet go from the floor onto the mattress, legs stretched.
	func _place_on_bed(pose: RigPose, h: float, line: float, lie: float, sx: float, wake: float, shift: float) -> void:
		if lie <= 0.0:
			return
		var L: Dictionary = X.SLEEP
		var hip_x := rig.bone_x[B.HIP] + pose.x[B.HIP]
		var hip_y := rig.bone_y[B.HIP] + pose.y[B.HIP]
		RigMath.spin_root(pose, L.lieAngle * lie * DEG, hip_x - 12.0, hip_y + 30.0)
		pose.root_x = shift * RigMath.smooth01(lie)
		var k := RigMath.smooth01(lie / L.settleIn)
		var e := RigMath.smooth01(lie)
		var root0 := pose.root_y
		pose.root_y = root0 + _bed_gap(pose, h) * k
		_lying_legs(pose, h, lie, sx, wake)
		RigMath.derive_bones(rig, pose, WAIST_FOLLOW)
		pose.rot[B.WAIST] += L.lieWaist * RigMath.smooth01(lie) * DEG
		# Resting on the mattress while sitting up; lying, the spine (hip joint) sinks onto the body
		# line, under the blanket.
		var rest := root0 + _bed_gap(pose, h) * k
		pose.root_y = rest
		RigMath.compute_world(rig, pose, world)
		var spine := rest - line - world[B.HIP * 6 + 5]
		pose.root_y = lerpf(rest, spine, e)
		# Keep everything above the bottom of the covered band (as far below the spine as the
		# blanket peak is above it), so nothing shows under the bed rail.
		var peak: float = float(InteractionActions.furniture("bed").get("blanket_peak_y", line + 60.0))
		var low := RigMath.lowest_point(rig, pose, world)
		var limit := -(2.0 * line - peak + float(L.coverMargin))
		if low > limit:
			pose.root_y -= (low - limit) * e

	## Distance to move the body down so its back rests at `surface` above the floor.
	func _bed_gap(pose: RigPose, surface: float) -> float:
		return -surface - RigMath.lowest_point(rig, pose, world, _upper)

	## Seated feet (world, on the floor) blended into legs stretched straight along the body.
	func _lying_legs(pose: RigPose, h: float, lie: float, sx: float, wake: float) -> void:
		var L: Dictionary = X.SLEEP
		var theta := pose.root_rot
		var c := cos(theta)
		var s := sin(theta)
		var e := RigMath.smooth01(lie)
		for side in ["front", "back"]:
			var leg: RigData.Leg = rig.legs[side]
			var a0 := seated_ankle(side, sx, 0.0, h)
			a0.y -= L.legLift * sin(PI * e)
			# Seated foot (world) mapped into character space through the root.
			var dx := a0.x - pose.pivot_x - pose.root_x
			var dy := a0.y - pose.pivot_y - pose.root_y
			var seated := Vector2(c * dx + s * dy + pose.pivot_x, -s * dx + c * dy + pose.pivot_y)
			var jx := rig.bone_x[B.HIP] + pose.x[B.HIP] + leg.hip_x
			var jy := rig.bone_y[B.HIP] + pose.y[B.HIP] + leg.hip_y
			var straight := Vector2(jx + L.lieAnkle[side], jy + (leg.upper + leg.lower) * L.lieReach)
			var t := seated.lerp(straight, e)
			var toe: float = (L.lieToe[side] + L.wakeToe * wake) * DEG
			RigMath.solve_leg(rig, pose, side, t.x, t.y, lerpf(-theta, toe, e))

	## Character space (before the root) to world, facing 1.
	func _char_to_world(pose: RigPose, p: Vector2) -> Vector2:
		var c := cos(pose.root_rot)
		var s := sin(pose.root_rot)
		var d := p - Vector2(pose.pivot_x, pose.pivot_y)
		return Vector2(c * d.x - s * d.y, s * d.x + c * d.y) + Vector2(pose.pivot_x + pose.root_x, pose.pivot_y + pose.root_y)

	## Root slide that centers the head over the pillow (pillow x relative to the origin).
	func bed_shift(h: float, line: float, pillow: float) -> float:
		return _bed(h, line, pillow).shift

	func z_point(h: float, line: float, pillow: float) -> Vector2:
		return _bed(h, line, pillow).z

	func _bed(h: float, line: float, pillow: float) -> Dictionary:
		var key := Vector3(snappedf(h, 0.01), snappedf(line, 0.01), snappedf(pillow, 0.01))
		if _bed_cache.has(key):
			return _bed_cache[key]
		var L: Dictionary = X.SLEEP
		var p := RigPose.new(rig)
		var ch := sleeping_channels(h, line, pillow, 0.0)
		ch.asleep = 0.0
		sleep_pose(ch, p, false, false)
		var box := _head_box(p)
		var shift: float = pillow - box.get_center().x
		var z := Vector2(pillow + L.zOffset[0], box.position.y - L.zOffset[1])
		var out := {"shift": shift, "z": z}
		_bed_cache[key] = out
		return out

	func _head_box(p: RigPose) -> Rect2:
		RigMath.compute_world(rig, p, world)
		var head: RigData.Part = rig.parts[rig.part_index["head"]]
		var b := head.box
		var r := Rect2(RigMath.point(world, B.HEAD, b.position.x, b.position.y), Vector2.ZERO)
		for corner in [Vector2(b.end.x, b.position.y), Vector2(b.position.x, b.end.y), b.end]:
			r = r.expand(RigMath.point(world, B.HEAD, corner.x, corner.y))
		return r

	## Sleeping channels at loop time t (s).
	func sleeping_channels(h: float, line: float, pillow: float, t: float) -> Dictionary:
		var LD: Dictionary = X.SLEEP.lieDown
		var since: float = LD.duration - LD.lieContact + t
		return {"h": h, "line": line, "pillow": pillow, "sx": 1.0, "sy": 1.0, "seatLean": -2.0, "lie": 1.0, "asleep": 1.0, "breathT": since, "tLie": since}


# ---------- pose sheet helpers (not for gameplay) ----------

static func _sheet_furniture(adv, prop: String, h: float) -> void:
	adv.set_rest_height(h)
	var s := Sprite2D.new()
	s.texture = load(furniture(prop).texture)
	s.centered = false
	# Another seat height than the art's: the art moves with it and is cut at the ground.
	var dy := surface_height(prop) - h
	s.position = furniture_position(prop, Vector2.ZERO, adv.facing) + Vector2(0.0, dy)
	var tex_h := float(s.texture.get_height())
	s.region_enabled = true
	s.region_rect = Rect2(0, 0, s.texture.get_width(), minf(tex_h, tex_h - dy))
	s.flip_h = adv.facing < 0
	adv.add_child(s)
	adv.move_child(s, 0)
	var line := ColorRect.new()
	line.color = Color(0.3, 1.0, 0.5, 0.8)
	line.position = Vector2(s.position.x, -h - 1.0)
	line.size = Vector2(float(s.texture.get_width()), 2)
	adv.add_child(line)


static func _sheet_chair(adv, h: float) -> void:
	_sheet_furniture(adv, "chair", h if h >= 0.0 else surface_height("chair"))


static func _sheet_bed(adv, under := false) -> void:
	# The bed is wider than the cell: center it, both ends cut by a few units.
	adv.position.x = 380.0
	var f := furniture("bed")
	var layers: Dictionary = f.get("layers", {})
	if layers.is_empty():
		_sheet_furniture(adv, "bed", surface_height("bed"))
	else:
		adv.set_rest_height(surface_height("bed"))
		var top_left := furniture_position("bed", Vector2.ZERO, adv.facing)
		var back := _sheet_sprite(layers.back, top_left, adv.facing)
		adv.add_child(back)
		adv.move_child(back, 0)
		var front := _sheet_sprite(layers.front, top_left, adv.facing)
		adv.add_child(front)
		var place := func(on_top: bool) -> void:
			adv.move_child(front, adv.get_child_count() - 1 if on_top else 1)
		place.call(under)
		adv.action_event.connect(func(_id: StringName, ev: StringName) -> void:
			if ev == &"under_blanket":
				place.call(true)
			elif ev == &"out_of_blanket":
				place.call(false))
	var body := ColorRect.new()
	body.color = Color(1.0, 0.8, 0.2, 0.8)
	body.position = Vector2(-400.0, -body_line_of(adv, surface_height("bed")) - 1.0)
	body.size = Vector2(560, 2)
	adv.add_child(body)
	var o := bed_offsets()
	for x in [o.x, o.y]:
		var mark := ColorRect.new()
		mark.color = Color(1.0, 0.3, 0.4, 0.9)
		mark.position = Vector2(x - 2.0, -surface_height("bed") - 14.0)
		mark.size = Vector2(4, 14)
		adv.add_child(mark)


static func _sheet_sprite(path: String, top_left: Vector2, facing: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(path)
	s.centered = false
	s.position = top_left
	s.flip_h = facing < 0
	return s


static func _run_until(adv, id: StringName, max_seconds: float) -> void:
	var t := 0.0
	while t < max_seconds and adv.current_action() != id:
		adv.set_locomotion(0.0, 1.0 / 120.0)
		t += 1.0 / 120.0
	for i in 12:
		adv.set_locomotion(0.0, 1.0 / 120.0)


# ---------- chair actions ----------

class SitDown extends RigAction:
	var core: Core
	var height := 90.0
	var sheet_height := -1.0

	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data)
		core = c
		id = &"sit_down"
		requires = "ground"
		next_state = "action:sitting"
		var S: Dictionary = X.SIT
		duration = S.moments.settled * S.duration
		_build_events()

	func _build_events() -> void:
		var S: Dictionary = X.SIT
		var J: Dictionary = S.juice
		var tc: float = S.moments.seatContact * S.duration
		events = [{"t": tc, "signal": &"seated"}]
		for p: Array in S.puffs:
			events.append({"t": tc, "fx": "dust", "x": S.seatX + p[0], "y": -height + p[1], "params": {"count": J.puffCount, "life": 0.45, "speed": 26.0, "rise": 10.0, "spread": 12.0, "dir": p[2]}})
		for k: Array in S.creaks:
			events.append({"t": tc + k[3], "fx": "custom", "x": S.seatX + k[0], "y": -height + k[1], "params": {"emit": InteractionActions._emit_creak, "life": J.creakLife, "dir": k[2]}})
		sort_events()

	func begin(host) -> void:
		start_facing = host.facing
		height = InteractionActions.height_of(host, "chair")
		_build_events()

	func sheet_setup(adv) -> void:
		InteractionActions._sheet_chair(adv, sheet_height)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var S: Dictionary = X.SIT
		core.sit_pose(t / S.duration, t - S.moments.seatContact * S.duration, height, pose, juice)
		pose.facing = start_facing


class Sitting extends RigAction:
	var core: Core
	var height := 90.0
	var sheet_height := -1.0
	var window := 0.0
	var period := 0.0
	var tap_times := PackedFloat32Array()
	## Last sampled loop time, read by stand_up to continue the breath.
	var last_t := 0.0
	var sheet_duration := 0.0

	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data)
		core = c
		id = &"sitting"
		requires = "ground"
		duration = INF
		cancel_by.assign([&"stand_up"])
		var S: Dictionary = X.SIT
		var M: Dictionary = S.moments
		window = (M.pushStart - M.settled) * S.duration
		period = window + S.fidgetRest
		sheet_duration = period
		var a: float = S.tapWindow[0]
		var b: float = S.tapWindow[1]
		for i in int(S.taps):
			var u: float = a + float(i + 1) / S.taps * (b - a)
			tap_times.append((u - M.settled) * S.duration - 0.01)

	func begin(host) -> void:
		start_facing = host.facing
		height = InteractionActions.height_of(host, "chair")
		duration = INF
		last_t = 0.0

	func sheet_setup(adv) -> void:
		InteractionActions._sheet_chair(adv, sheet_height)

	func since_contact(t: float) -> float:
		var S: Dictionary = X.SIT
		return (S.moments.settled - S.moments.seatContact) * S.duration + t

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var S: Dictionary = X.SIT
		var u: float = S.moments.settled + minf(fposmod(t, period), window) / S.duration
		core.sit_pose(u, since_contact(t), height, pose, juice)
		pose.facing = start_facing

	func tick(host, delta: float) -> bool:
		var t: float = host.action_elapsed()
		last_t = t
		if not X.SIT.juice.tapDust:
			return false
		var c0 := fposmod(t - delta, period)
		var c1 := fposmod(t, period)
		var x: float = core.seated_ankle_x("front", 1.0) + RigData.FOOT_TOE - 8.0
		for ct in tap_times:
			if (c0 < ct and c1 >= ct) or (c1 < c0 and (ct > c0 or ct <= c1)):
				host.spawn_fx_local("dust", {"count": 1, "life": 0.25, "speed": 16.0, "rise": 8.0, "spread": 6.0, "dir": 1}, Vector2(x * host.facing, 0.0), true)
		return false


class StandUp extends RigAction:
	var core: Core
	var sitting: Sitting
	var height := 90.0
	var since0 := 0.0

	func _init(rig_data: RigData, c: Core, sitting_action: Sitting) -> void:
		super(rig_data)
		core = c
		sitting = sitting_action
		id = &"stand_up"
		requires = "ground"
		var S: Dictionary = X.SIT
		var M: Dictionary = S.moments
		var D: float = S.duration
		duration = (1.0 - M.pushStart) * D
		var lift: float = (M.liftOff - M.pushStart) * D
		events = [
			{"t": lift, "signal": &"lift_off"},
			{"t": lift, "fx": "dust", "x": core.seated_ankle_x("front", 1.0) + RigData.FOOT_TOE, "y": 0.0, "params": {"count": 3, "life": 0.35, "speed": 30.0, "rise": 12.0, "spread": 14.0, "dir": 1}},
			{"t": (M.standUp - M.pushStart) * D, "signal": &"standing"},
		]
		sort_events()

	func begin(host) -> void:
		start_facing = host.facing
		height = InteractionActions.height_of(host, "chair")
		since0 = sitting.since_contact(sitting.last_t)

	func sheet_setup(adv) -> void:
		InteractionActions._sheet_chair(adv, -1.0)
		adv.play_action(&"sit_down")
		InteractionActions._run_until(adv, &"sitting", 4.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var S: Dictionary = X.SIT
		core.sit_pose(S.moments.pushStart + t / S.duration, since0 + t, height, pose, juice)
		pose.facing = start_facing


# ---------- bed actions ----------

class LieDown extends RigAction:
	var core: Core
	var height := 90.0
	var pillow := 0.0
	var line := 0.0
	var tracks := {}
	var ch := {}

	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data)
		core = c
		id = &"lie_down"
		requires = "ground"
		next_state = "action:sleeping"
		duration = X.SLEEP.lieDown.duration
		tracks = InteractionActions._tracks(X.SLEEP.lieDown, ["yawn", "slouch", "sinkX", "sinkY", "seatLean", "hands", "sitBack", "lie", "asleep"])
		_build_events()

	func _build_events() -> void:
		var P: Dictionary = X.SLEEP.lieDown
		var J: Dictionary = X.SLEEP.juice
		events = [
			{"t": P.seatContact, "signal": &"seated"},
			{"t": P.seatContact, "fx": "dust", "x": X.SIT.seatHipX - 20.0, "y": -height, "params": {"count": J.dustCount, "life": 0.45, "speed": 30.0, "rise": 12.0, "spread": 30.0}},
			{"t": InteractionActions._cross(tracks.lie, X.SLEEP.quiltAt, P.duration, true), "signal": &"under_blanket"},
			{"t": P.lieContact, "signal": &"lying"},
			{"t": P.lieContact, "fx": "dust", "x": X.SIT.seatHipX - 150.0, "y": -height, "params": {"count": J.dustCount, "life": 0.45, "speed": 26.0, "rise": 10.0, "spread": 60.0}},
		]
		sort_events()

	func begin(host) -> void:
		start_facing = host.facing
		height = InteractionActions.height_of(host, "bed")
		pillow = InteractionActions.pillow_of(host)
		line = InteractionActions.body_line_of(host, height)
		_build_events()

	func sheet_setup(adv) -> void:
		InteractionActions._sheet_bed(adv)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var P: Dictionary = X.SLEEP.lieDown
		ch.h = height
		ch.line = line
		ch.pillow = pillow
		for n in ["yawn", "slouch", "seatLean", "hands", "sitBack", "lie", "asleep"]:
			ch[n] = tracks[n].sample(t)
		ch.sx = tracks.sinkX.sample(t)
		ch.sy = tracks.sinkY.sample(t)
		ch.breathT = t - P.lieContact
		ch.tYawnEnd = t - 1.12
		ch.tSeat = t - P.seatContact
		ch.tLie = t - P.lieContact
		core.sleep_pose(ch, pose, juice)
		pose.facing = start_facing


class Sleeping extends RigAction:
	var core: Core
	var height := 90.0
	var pillow := 0.0
	var line := 0.0
	var last_t := 0.0
	var sheet_duration := 0.0

	func _init(rig_data: RigData, c: Core) -> void:
		super(rig_data)
		core = c
		id = &"sleeping"
		requires = "ground"
		duration = INF
		cancel_by.assign([&"get_up"])
		var L: Dictionary = X.SLEEP
		sheet_duration = L.zCount * L.zInterval + L.zPause

	func begin(host) -> void:
		start_facing = host.facing
		height = InteractionActions.height_of(host, "bed")
		pillow = InteractionActions.pillow_of(host)
		line = InteractionActions.body_line_of(host, height)
		duration = INF
		last_t = 0.0

	func sheet_setup(adv) -> void:
		InteractionActions._sheet_bed(adv, true)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		core.sleep_pose(core.sleeping_channels(height, line, pillow, t), pose, juice)
		pose.facing = start_facing

	## Z z Z z Z bursts: letter i of a burst at zFirst + i * zInterval, bursts every period.
	func tick(host, delta: float) -> bool:
		var L: Dictionary = X.SLEEP
		var t: float = host.action_elapsed()
		last_t = t
		var period: float = L.zCount * L.zInterval + L.zPause
		var t0 := t - delta
		for i in int(L.zCount):
			var at: float = L.zFirst + i * L.zInterval
			var n := floorf((t - at) / period)
			var hit := at + n * period
			if hit > t0 and hit <= t and hit >= 0.0:
				var p := core.z_point(height, line, pillow)
				host.spawn_fx_local("custom", {"emit": InteractionActions._emit_z, "life": L.zLife, "big": i % 2 == 0, "seed": i + 1}, Vector2(p.x * host.facing, p.y), false)
		return false


class GetUp extends RigAction:
	var core: Core
	var sleeping: Sleeping
	var height := 90.0
	var pillow := 0.0
	var line := 0.0
	var tracks := {}
	var ch := {}
	var breath0 := 0.0

	func _init(rig_data: RigData, c: Core, sleeping_action: Sleeping) -> void:
		super(rig_data)
		core = c
		sleeping = sleeping_action
		id = &"get_up"
		requires = "ground"
		var P: Dictionary = X.SLEEP.getUp
		duration = P.duration
		tracks = InteractionActions._tracks(P, ["asleep", "wake", "lie", "swing", "hands", "seatLean", "sinkX", "sinkY"])
		events = [
			{"t": P.wakeAt, "signal": &"awake"},
			{"t": InteractionActions._cross(tracks.lie, X.SLEEP.quiltAt, P.duration, false), "signal": &"out_of_blanket"},
			{"t": P.liftOff, "signal": &"lift_off"},
			{"t": P.liftOff, "fx": "dust", "x": core.seated_ankle_x("front", 1.0) + RigData.FOOT_TOE, "y": 0.0, "params": {"count": 3, "life": 0.35, "speed": 26.0, "rise": 10.0, "spread": 16.0, "dir": 1}},
			{"t": P.standUp, "signal": &"standing"},
		]
		sort_events()

	func begin(host) -> void:
		start_facing = host.facing
		height = InteractionActions.height_of(host, "bed")
		pillow = InteractionActions.pillow_of(host)
		line = InteractionActions.body_line_of(host, height)
		breath0 = float(core.sleeping_channels(height, line, pillow, sleeping.last_t).breathT)

	func sheet_setup(adv) -> void:
		InteractionActions._sheet_bed(adv)
		adv.play_action(&"lie_down")
		InteractionActions._run_until(adv, &"sleeping", 4.0)

	func sample(t: float, pose: RigPose, juice: bool) -> void:
		var P: Dictionary = X.SLEEP.getUp
		ch.h = height
		ch.line = line
		ch.pillow = pillow
		for n in ["asleep", "wake", "lie", "swing", "hands", "seatLean"]:
			ch[n] = tracks[n].sample(t)
		ch.sx = tracks.sinkX.sample(t)
		ch.sy = tracks.sinkY.sample(t)
		ch.breathT = breath0 + t
		ch.tWake = t - P.wakeAt
		ch.tStand = t - P.standUp
		core.sleep_pose(ch, pose, juice)
		pose.facing = start_facing
