extends "res://game/interactables/interactable.gd"

# The motocross bike: a rigid body (position, velocity, angle, spin) on two elastic wheel contacts
# that act as the suspension, simulated against the track analytically in SUBSTEPS per physics
# frame. It is also the interactable that the player mounts and gets off; while ridden it drives
# the player's own rig (riding pose, rotation, position at the footpeg).
# The node stays at the origin: the state lives in `pos` and the sprites are placed in world units
# from the interpolated state in _process, at the quantized angle of the pre-rotated sheets.

signal landed(impact: float)
signal took_off
signal crashed
signal respawned
signal mounted
# A whole turn (or more) in the air that landed on the wheels; dir -1 backflip, 1 frontflip.
signal flipped(turns: int, dir: int)
signal dismounted

const T := preload("res://game/moto/moto_tuning.gd")
const MotoArt := preload("res://game/moto/moto_art.gd")

enum Mode { PARKED, APPROACH, MOUNTING, RIDING, DISMOUNTING, CRASHED }

const MOUNT_ACTION := &"mount_bike"
const RIDE_ACTION := &"riding"
const DISMOUNT_ACTION := &"dismount_bike"
const CRASH_ACTION := &"hurt"
# Safety net when an animation never reports its end.
const ACTION_TIMEOUT := 2.5
const APPROACH_TIMEOUT := 3.0
const APPROACH_TOLERANCE := 8.0
const SWING_EYE := T.SWING_PIVOT - Vector2(3, 3)

var track: Node
var mode := Mode.PARKED
var rider: CharacterBody2D
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var angle := 0.0
var spin := 0.0
var depth := PackedFloat32Array([0.0, 0.0])
var air_time := 0.0
var throttle := 0.0
var brake := 0.0
var lean := 0.0
# Ground speed along the surface under the rear wheel (positive forward).
var ground_speed := 0.0
# Rear wheel slip for the roost (0..1): drive force over what the grip allows.
var rear_slip := 0.0
var input_enabled := true
# Rotation accumulated during the current flight (negative = backwards, nose up).
var air_rotation := 0.0
var finished := false

var _crashed := false
var _flip_turns := 0
var _flip_dir := 0
var _flip_wait := -1.0
var _reversing := false
var _stop_hold := 0.0
var _brake_was_held := false
var _prev_pos := Vector2.ZERO
var _prev_angle := 0.0
var _impact := 0.0
var _was_touching := true
var _wheel_angle := PackedFloat32Array([0.0, 0.0])
var _wheel_spin := PackedFloat32Array([0.0, 0.0])
var _mode_t := 0.0
var _mount_start := Vector2.ZERO
var _fix := Vector2.ZERO
var _dis_peg := Vector2.ZERO
var _dis_angle := 0.0
var _rider_layer := 1
var _rider_mask := 1
var _rider_attached := false
var _land_squat := 0.0
var _lean_smooth := 0.0
var _a := 6.0
var _body: Sprite2D
var _swing: Sprite2D
var _wheels: Array[Sprite2D] = []
var _stand: Sprite2D
var _rig_tween: Tween


func _ready() -> void:
	prompt = "Montar"
	interact_radius = 200.0
	_a = float(GameScale.art_pixel())
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_physics_priority = -10
	z_index = T.BIKE_Z
	_stand = _make_stand()
	add_child(_stand)
	for i in 2:
		var w := Sprite2D.new()
		w.centered = false
		w.region_enabled = true
		w.scale = Vector2.ONE * _a
		_wheels.append(w)
		add_child(w)
	_swing = Sprite2D.new()
	_body = Sprite2D.new()
	for s in [_swing, _body]:
		s.centered = false
		s.region_enabled = true
		s.scale = Vector2.ONE * _a
		add_child(s)
	visible = false


func setup(track_node: Node, player: CharacterBody2D) -> void:
	track = track_node
	rider = player
	var rig := _rig()
	if rig and rig.has_signal(&"action_event"):
		rig.action_event.connect(_on_rig_event)


# Call once MotoArt is ready.
func show_art() -> void:
	_body.texture = MotoArt.body.texture
	_swing.texture = MotoArt.swing.texture
	for w in _wheels:
		w.texture = MotoArt.wheel.texture
	visible = true
	_render(true)


# --- Interaction contract -----------------------------------------------------------------------

func get_prompt(_player: Node) -> String:
	return "Descer" if mode == Mode.RIDING else "Montar"


func can_interact(player: Node) -> bool:
	if player != rider:
		return false
	match mode:
		Mode.PARKED:
			return true
		Mode.RIDING:
			return can_dismount()
	return false


func interact(player: Node) -> void:
	if player != rider:
		return
	if mode == Mode.PARKED:
		_begin_approach()
	elif mode == Mode.RIDING and can_dismount():
		_begin_dismount()


func get_interact_point() -> Vector2:
	if mode == Mode.PARKED:
		var peg := peg_world()
		var x := peg.x + T.MOUNT_DX
		return Vector2(x, track.height_at(x) if track else peg.y)
	return peg_world()


func can_dismount() -> bool:
	if mode != Mode.RIDING or wheels_down() < 2 or vel.length() >= T.DISMOUNT_MAX_SPEED:
		return false
	var limit := deg_to_rad(T.DISMOUNT_MAX_SLOPE_DEG)
	var gx := peg_world().x + T.DISMOUNT_DX
	return absf(wrapf(angle, -PI, PI)) <= limit and absf(wrapf(track.slope_at(gx), -PI / 2, PI / 2)) <= limit


# --- Public state -------------------------------------------------------------------------------

func is_ridden() -> bool:
	return mode == Mode.RIDING


func is_crashed() -> bool:
	return mode == Mode.CRASHED


func rider_on_bike() -> bool:
	return mode in [Mode.MOUNTING, Mode.RIDING, Mode.DISMOUNTING]


func state_label() -> String:
	return ["parked", "approach", "mounting", "riding", "dismounting", "crashed"][mode]


func wheels_down() -> int:
	return int(depth[0] > 0.0) + int(depth[1] > 0.0)


func peg_world() -> Vector2:
	return pos + T.PEG.rotated(angle)


func render_position() -> Vector2:
	return _prev_pos.lerp(pos, Engine.get_physics_interpolation_fraction())


func render_angle() -> float:
	return lerp_angle(_prev_angle, angle, Engine.get_physics_interpolation_fraction())


func wheel_contact(w: int) -> Vector2:
	var axle := pos + (T.REAR_AXLE if w == 0 else T.FRONT_AXLE).rotated(angle)
	return Vector2(axle.x, track.height_at(axle.x))


# --- Placement ----------------------------------------------------------------------------------

# Parks the bike at x on its stand (suspension settled, physics frozen).
func park_at(x: float) -> void:
	_reset_body(x)
	mode = Mode.PARKED
	_show_stand(true)


# The bike at x with the rider already on it (start of a run, after a crash or a restart).
func spawn_mounted(x: float) -> void:
	_stop_rig_tween()
	_reset_body(x)
	_show_stand(false)
	finished = false
	if rider and is_instance_valid(rider):
		_attach_rider()
		var rig := _rig()
		if rig:
			_set_ride_meta(0.0, T.SQUAT_BASE, 0.0)
			if rig.has_method(&"stop_action"):
				rig.stop_action()
			rig.rotation = angle
			if rig.has_method(&"play_action"):
				rig.play_action(RIDE_ACTION)
	mode = Mode.RIDING
	_mode_t = 0.0
	_render(true)
	respawned.emit()


func _reset_body(x: float) -> void:
	_crashed = false
	_reversing = false
	pos = Vector2(x, track.height_at(x) - T.CAMERA_FLOOR_OFFSET)
	angle = track.slope_at(x)
	vel = Vector2.ZERO
	spin = 0.0
	throttle = 0.0
	lean = 0.0
	# Holds the bike without engaging the reverse (that needs brake > 0.5).
	brake = 0.45
	var h := 1.0 / (Engine.physics_ticks_per_second * T.SUBSTEPS)
	for i in T.SETTLE_STEPS * T.SUBSTEPS:
		_step(h)
	brake = 0.0
	pos.x = x
	vel = Vector2.ZERO
	spin = 0.0
	_prev_pos = pos
	_prev_angle = angle
	_was_touching = true
	air_time = 0.0
	air_rotation = 0.0
	_flip_wait = -1.0
	_wheel_spin.fill(0.0)
	_land_squat = 0.0


# --- Physics ------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if track == null or delta <= 0.0:
		return
	_prev_pos = pos
	_prev_angle = angle
	_mode_t += delta
	match mode:
		Mode.APPROACH:
			_approach(delta)
		Mode.MOUNTING:
			var rig := _rig()
			if rig == null or _current_action(rig) == RIDE_ACTION or _mode_t > ACTION_TIMEOUT:
				_enter_riding()
		Mode.DISMOUNTING:
			var rig := _rig()
			if rig == null or _current_action(rig) != DISMOUNT_ACTION or _mode_t > ACTION_TIMEOUT:
				_finish_dismount()
		Mode.RIDING, Mode.CRASHED:
			_read_input()
			_simulate(delta)
	if mode in [Mode.RIDING, Mode.CRASHED, Mode.MOUNTING, Mode.DISMOUNTING]:
		_update_ride_meta(delta)


func _read_input() -> void:
	var blocked := not input_enabled or mode != Mode.RIDING or finished
	if not blocked and rider:
		var blocker = rider.get(&"input_blocker")
		blocked = blocker is Object and is_instance_valid(blocker) and blocker.get(&"visible") == true
	if blocked:
		throttle = 0.0
		brake = 1.0 if finished and mode == Mode.RIDING else 0.0
		lean = 0.0
		return
	throttle = Input.get_action_strength(&"moto_throttle")
	brake = Input.get_action_strength(&"moto_brake")
	lean = Input.get_action_strength(&"moto_lean_forward") - Input.get_action_strength(&"moto_lean_back")


func _simulate(delta: float) -> void:
	_update_reverse(delta)
	_impact = 0.0
	var h := delta / T.SUBSTEPS
	var before := angle
	for i in T.SUBSTEPS:
		_step(h)
		if mode == Mode.RIDING and _body_hits_ground():
			_crash()
	air_rotation += wrapf(angle - before, -PI, PI)
	var touching := wheels_down() > 0
	if touching:
		if not _was_touching and air_time >= T.LAND_MIN_AIR:
			_land_squat = clampf(_impact / T.HARD_LANDING, 0.0, 1.0) * T.SQUAT_LANDING
			landed.emit(_impact)
			var turns := floori((absf(air_rotation) + T.FLIP_TOLERANCE) / TAU)
			if turns > 0 and mode == Mode.RIDING:
				_flip_turns = turns
				_flip_dir = 1 if air_rotation > 0.0 else -1
				_flip_wait = T.FLIP_CONFIRM
		air_time = 0.0
		air_rotation = 0.0
	else:
		if _was_touching:
			took_off.emit()
		air_time += delta
	_was_touching = touching
	if _flip_wait >= 0.0:
		_flip_wait -= delta
		if mode != Mode.RIDING:
			_flip_wait = -1.0
		elif _flip_wait < 0.0:
			flipped.emit(_flip_turns, _flip_dir)
	_spin_wheels(delta)


func _step(h: float) -> void:
	var acc := Vector2(0.0, T.GRAVITY)
	var ang := 0.0
	var touching := 0
	var drive_slip := 0.0
	for w in 2:
		var center := pos + (T.REAR_AXLE if w == 0 else T.FRONT_AXLE).rotated(angle)
		var c: Dictionary = track.probe(center, T.WHEEL_RADIUS)
		depth[w] = maxf(0.0, T.WHEEL_RADIUS - c.dist) if c.hit or c.dist < 0.0 else 0.0
		if depth[w] <= 0.0:
			continue
		touching += 1
		var n: Vector2 = c.normal
		var r: Vector2 = c.point - pos
		var pv := vel + Vector2(-spin * r.y, spin * r.x)
		var vn := pv.dot(n)
		_impact = maxf(_impact, -vn)
		var nf := maxf(0.0, T.SPRING * depth[w] - T.DAMP * vn)
		var t := Vector2(-n.y, n.x)
		var vt := pv.dot(t)
		if w == 0:
			ground_speed = vt
		var drive := -vt * T.ROLL_DRAG
		if not _crashed:
			drive += _drive(w, vt, h)
		var limit := T.GRIP * nf
		if w == 0 and limit > 0.0:
			drive_slip = clampf(absf(drive) / limit, 0.0, 1.0)
		drive = clampf(drive, -limit, limit)
		var f := n * nf + t * drive
		acc += f
		ang += r.cross(f) / T.INERTIA
		if depth[w] > T.TRAVEL:
			_bottom_out(n, r, vn, depth[w] - T.TRAVEL)
	if _crashed:
		for p in T.CRASH_POINTS + T.BODY_POINTS:
			var f := _frame_contact(p, h)
			if f != Vector2.ZERO:
				touching += 1
				acc += f
				ang += (p.rotated(angle)).cross(f) / T.INERTIA
	rear_slip = drive_slip if depth[0] > 0.0 else 0.0
	if not _crashed:
		ang += lean * ((T.GROUND_LEAN_BACK if lean < 0.0 else T.GROUND_LEAN_FORWARD) if touching else T.AIR_LEAN)
		if touching == 0:
			ang += (brake - throttle) * T.AIR_THROTTLE_PITCH
			if absf(lean) < 0.1 and vel.length() > T.AIR_ALIGN_MIN_SPEED:
				ang += wrapf(vel.angle() - angle, -PI, PI) * T.AIR_ALIGN
	ang -= spin * (T.SPIN_DAMP_GROUND if touching else T.SPIN_DAMP_AIR)
	vel += acc * h
	spin = clampf(spin + ang * h, -T.MAX_SPIN, T.MAX_SPIN)
	pos += vel * h
	angle = wrapf(angle + spin * h, -PI, PI)


# Reverse gear: see REVERSE_HOLD (braking to a stop never rolls straight into the reverse).
func _update_reverse(delta: float) -> void:
	var held := brake > 0.5 and throttle <= 0.1 and not finished and not _crashed
	if not held:
		_reversing = false
		_stop_hold = 0.0
	elif not _reversing:
		var still := wheels_down() > 0 and absf(ground_speed) < T.REVERSE_ENGAGE_SPEED
		if not still:
			_stop_hold = 0.0
		elif not _brake_was_held:
			_reversing = true
		else:
			_stop_hold += delta
			_reversing = _stop_hold >= T.REVERSE_HOLD
	_brake_was_held = held


# Tangential force (per unit mass) the rider asks of wheel w: throttle on the rear, brakes on both,
# and the reverse when braking at a standstill.
func _drive(w: int, vt: float, h: float) -> float:
	var d := 0.0
	if _reversing:
		if w == 0:
			d -= T.REVERSE_ACCEL * brake * maxf(0.0, 1.0 + vt / T.REVERSE_MAX)
		return d
	if w == 0:
		d += throttle * T.ENGINE_ACCEL * maxf(0.0, 1.0 - vt / T.TOP_SPEED)
	var b: float = T.BRAKE_ACCEL[w]
	d -= signf(vt) * minf(absf(vt) / h, brake * b)
	return d


# Past the end of the suspension: push out of the ground and kill the speed into it at the contact
# (an impulse on the rigid body, so it also stops the rotation into the ground).
func _bottom_out(n: Vector2, r: Vector2, vn: float, excess: float) -> void:
	pos += n * excess
	if vn >= 0.0:
		return
	var rn := r.cross(n)
	var j := -vn / (1.0 + rn * rn / T.INERTIA)
	vel += n * j
	spin += rn * j / T.INERTIA


# A crashed frame point sliding on the ground: spring, damper and Coulomb friction.
func _frame_contact(local: Vector2, h: float) -> Vector2:
	var p := pos + local.rotated(angle)
	var c: Dictionary = track.probe(p, T.CRASH_RADIUS)
	if not c.hit and c.dist >= 0.0:
		return Vector2.ZERO
	var d: float = T.CRASH_RADIUS - c.dist
	var n: Vector2 = c.normal
	var r := local.rotated(angle)
	var pv := vel + Vector2(-spin * r.y, spin * r.x)
	var vn := pv.dot(n)
	var nf := maxf(0.0, T.SPRING * 2.0 * d - T.DAMP * 2.0 * vn)
	var t := Vector2(-n.y, n.x)
	var vt := pv.dot(t)
	var ft := clampf(-vt / h, -T.CRASH_FRICTION * nf, T.CRASH_FRICTION * nf)
	if d > T.TRAVEL:
		_bottom_out(n, c.point - pos, vn, d - T.TRAVEL)
	return n * nf + t * ft


func _body_hits_ground() -> bool:
	for p in T.CRASH_POINTS + [T.HEAD_POINT]:
		var w := pos + (p as Vector2).rotated(angle)
		if w.y > track.height_at(w.x):
			return true
	return false


func _spin_wheels(delta: float) -> void:
	for w in 2:
		if depth[w] > 0.0:
			var c := wheel_contact(w)
			var n: Vector2 = track.probe(c, 4.0).normal
			var along := vel.dot(Vector2(-n.y, n.x))
			_wheel_spin[w] = along / T.WHEEL_RADIUS
		else:
			var target := throttle * T.TOP_SPEED / T.WHEEL_RADIUS if w == 0 and not _crashed else 0.0
			if w == 0 and throttle > 0.05:
				_wheel_spin[w] = move_toward(_wheel_spin[w], target, T.WHEEL_AIR_SPIN_UP * delta)
			else:
				_wheel_spin[w] *= exp(-T.WHEEL_AIR_DECAY * delta)
		_wheel_angle[w] = wrapf(_wheel_angle[w] + _wheel_spin[w] * delta, 0.0, TAU)


# --- Crash --------------------------------------------------------------------------------------

func _crash() -> void:
	if mode != Mode.RIDING:
		return
	mode = Mode.CRASHED
	_mode_t = 0.0
	_crashed = true
	_reversing = false
	throttle = 0.0
	brake = 0.0
	lean = 0.0
	_eject_rider()
	crashed.emit()


func _eject_rider() -> void:
	if rider == null or not is_instance_valid(rider):
		return
	var at := peg_world()
	at.y = minf(at.y, track.height_at(at.x) - 4.0)
	_detach_rider(false)
	rider.global_position = at
	rider.reset_physics_interpolation()
	rider.controlled_gravity = true
	rider.velocity = vel * 0.7 + Vector2(0.0, -520.0)
	var rig := _rig()
	if rig == null:
		return
	if rig.has_method(&"stop_action"):
		rig.stop_action()
	if rig.has_method(&"set_hit_direction"):
		rig.set_hit_direction(Vector2(signf(vel.x) if absf(vel.x) > 1.0 else 1.0, 0.0))
	if rig.has_method(&"play_action"):
		rig.play_action(CRASH_ACTION)
	_tween_rig_rotation(0.0, 0.15)


# --- Mount / dismount ---------------------------------------------------------------------------

func _begin_approach() -> void:
	if rider == null or not is_instance_valid(rider):
		return
	rider.take_control(self)
	_rider_attached = false
	mode = Mode.APPROACH
	_mode_t = 0.0


func _approach(_delta: float) -> void:
	if rider == null or not is_instance_valid(rider):
		mode = Mode.PARKED
		return
	var target := get_interact_point()
	var dx: float = target.x - rider.global_position.x
	var step: float = rider.walk_speed / Engine.physics_ticks_per_second
	if absf(dx) <= maxf(APPROACH_TOLERANCE, step) or _mode_t > APPROACH_TIMEOUT:
		rider.global_position.x = target.x
		rider.velocity = Vector2.ZERO
		_begin_mount()
		return
	var dir := 1 if dx > 0.0 else -1
	set_facing(rider, dir)
	rider.velocity.x = dir * float(rider.walk_speed)


func _begin_mount() -> void:
	set_facing(rider, 1)
	_mount_start = rider.global_position
	var peg := peg_world()
	_attach_rider()
	var rig := _rig()
	var mount_from := (_mount_start - peg).rotated(-angle)
	_set_ride_meta(0.0, T.SQUAT_BASE, 0.0, mount_from)
	mode = Mode.MOUNTING
	_mode_t = 0.0
	_fix = peg - _mount_start + mount_from
	if rig == null or not rig.has_method(&"play_action") or not rig.play_action(MOUNT_ACTION):
		_enter_riding()
		return
	_tween_rig_rotation(angle, _action_duration(rig, MOUNT_ACTION))


func _enter_riding() -> void:
	var rig := _rig()
	if rig and _current_action(rig) != RIDE_ACTION and rig.has_method(&"play_action"):
		if rig.has_method(&"stop_action"):
			rig.stop_action()
		rig.play_action(RIDE_ACTION)
	_show_stand(false)
	finished = false
	mode = Mode.RIDING
	_mode_t = 0.0
	_was_touching = true
	air_time = 0.0
	mounted.emit()


func _begin_dismount() -> void:
	var rig := _rig()
	_dis_peg = peg_world()
	_dis_angle = angle
	var gx := _dis_peg.x + T.DISMOUNT_DX
	var ground := Vector2(gx, float(track.height_at(gx)))
	var to := (ground - _dis_peg).rotated(-angle)
	_set_ride_meta(0.0, T.SQUAT_BASE, 0.0, Vector2.ZERO, to)
	_fix = ground - _dis_peg - to
	vel = Vector2.ZERO
	spin = 0.0
	throttle = 0.0
	brake = 0.0
	lean = 0.0
	_show_stand(true)
	mode = Mode.DISMOUNTING
	_mode_t = 0.0
	if rig == null or not rig.has_method(&"play_action") or not rig.play_action(DISMOUNT_ACTION):
		rider.global_position = ground
		_finish_dismount()
		return
	_tween_rig_rotation(0.0, _action_duration(rig, DISMOUNT_ACTION))


func _finish_dismount() -> void:
	if rider and is_instance_valid(rider):
		var gx := _dis_peg.x + T.DISMOUNT_DX
		rider.global_position = Vector2(gx, track.height_at(gx))
	_detach_rider(true)
	mode = Mode.PARKED
	_mode_t = 0.0
	dismounted.emit()


func _attach_rider() -> void:
	if rider == null or not is_instance_valid(rider):
		return
	if not rider.is_controlled():
		rider.take_control(self)
	if not _rider_attached:
		_rider_layer = rider.collision_layer
		_rider_mask = rider.collision_mask
	_rider_attached = true
	rider.collision_layer = 0
	rider.collision_mask = 0
	rider.controlled_gravity = false
	rider.velocity = Vector2.ZERO
	rider.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_facing(rider, 1)


# Gives the body back its collision and interpolation; release also hands the control back.
func _detach_rider(release: bool) -> void:
	if rider == null or not is_instance_valid(rider):
		_rider_attached = false
		return
	if _rider_attached:
		rider.collision_layer = _rider_layer
		rider.collision_mask = _rider_mask
	_rider_attached = false
	rider.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	rider.reset_physics_interpolation()
	rider.controlled_gravity = true
	rider.velocity = Vector2.ZERO
	var rig := _rig()
	if rig:
		rig.set_meta(&"ride", {})
	if release:
		_stop_rig_tween()
		if rig:
			rig.rotation = 0.0
		rider.release_control(self)


# Before leaving the stage: never leave the player controlled or without collision.
func release_rider() -> void:
	_stop_rig_tween()
	if rider and is_instance_valid(rider):
		var rig := _rig()
		if rig:
			rig.rotation = 0.0
		_detach_rider(true)


func _on_rig_event(id: StringName, event_name: StringName) -> void:
	if id == MOUNT_ACTION and event_name == &"seated":
		Feedback.sfx(&"land", peg_world(), 0.35, &"dirt")
		haptic(&"land", 0.3)
	elif id == DISMOUNT_ACTION and event_name == &"foot_down":
		Feedback.sfx(&"footstep", rider.global_position if rider else peg_world(), 0.6, &"dirt")
		haptic(&"footstep", 0.4)


# --- Rider pose ---------------------------------------------------------------------------------

func _update_ride_meta(delta: float) -> void:
	if mode != Mode.RIDING:
		return
	_land_squat = maxf(0.0, _land_squat - T.SQUAT_DECAY * delta * _land_squat - delta * 0.2)
	_lean_smooth = lerpf(_lean_smooth, lean, 1.0 - exp(-T.LEAN_SMOOTHING * delta))
	var travel := (minf(depth[0], T.TRAVEL) + minf(depth[1], T.TRAVEL)) * 0.5 / T.TRAVEL
	var squat := clampf(T.SQUAT_BASE + travel * T.SQUAT_FROM_TRAVEL + _land_squat, 0.0, 1.0)
	_set_ride_meta(_lean_smooth, squat, throttle)


func _set_ride_meta(lean_v: float, squat: float, throttle_v: float, mount_from := Vector2.INF, dismount_to := Vector2.INF) -> void:
	var rig := _rig()
	if rig == null:
		return
	var m: Dictionary = rig.get_meta(&"ride", {}).duplicate()
	m[&"lean"] = lean_v
	m[&"squat"] = squat
	m[&"throttle"] = throttle_v
	m[&"grip"] = T.GRIP_POINT - T.PEG
	m[&"seat"] = T.SEAT - T.PEG
	if mount_from != Vector2.INF:
		m[&"mount_from"] = mount_from
	if dismount_to != Vector2.INF:
		m[&"dismount_to"] = dismount_to
	rig.set_meta(&"ride", m)


func _rig() -> Node2D:
	if rider == null or not is_instance_valid(rider):
		return null
	var r = rider.get(&"rig")
	return r if r is Node2D and is_instance_valid(r) else null


func _current_action(rig: Node) -> StringName:
	return rig.current_action() if rig.has_method(&"current_action") else &""


func _action_duration(rig: Node, id: StringName) -> float:
	if rig.has_method(&"get_action"):
		var a = rig.get_action(id)
		if a and is_finite(a.duration):
			return a.duration
	return 0.9


func _root_motion(rig: Node, id: StringName) -> Vector2:
	if not rig.has_method(&"get_action") or _current_action(rig) != id:
		return Vector2.ZERO
	var a = rig.get_action(id)
	return a.root_motion(rig.action_elapsed()) if a else Vector2.ZERO


func _tween_rig_rotation(to: float, time: float) -> void:
	var rig := _rig()
	if rig == null:
		return
	_stop_rig_tween()
	rig.rotation = wrapf(rig.rotation, -PI, PI)
	to = rig.rotation + wrapf(to - rig.rotation, -PI, PI)
	_rig_tween = create_tween()
	_rig_tween.tween_property(rig, ^"rotation", to, maxf(time, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_rig_tween() -> void:
	if _rig_tween and _rig_tween.is_valid():
		_rig_tween.kill()
	_rig_tween = null


# --- Render -------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_render(false)


func _snap(v: Vector2) -> Vector2:
	return Vector2(roundf(v.x / _a) * _a, roundf(v.y / _a) * _a)


func _render(force: bool) -> void:
	if not visible or not MotoArt.is_ready():
		return
	var p := pos if force else render_position()
	var a := angle if force else render_angle()
	var n := MotoArt.body_steps()
	var step := TAU / n
	var k := posmod(roundi(a / step), n)
	var qa := k * step
	var rp := _snap(p)
	_body.region_rect = MotoArt.body.rects[k]
	_body.position = rp + MotoArt.body.offsets[k] * _a
	# Rear wheel on the swingarm arc, front wheel up the fork, by the suspension compression.
	var c0 := minf(depth[0], T.TRAVEL)
	var c1 := minf(depth[1], T.TRAVEL)
	var swing_d := asin(clampf(c0 / T.SWING_LENGTH, -1.0, 1.0))
	var rear := SWING_EYE + (T.REAR_AXLE - SWING_EYE).rotated(swing_d)
	var front := T.FRONT_AXLE + T.FORK_AXIS * (c1 / -T.FORK_AXIS.y)
	var sa := qa + deg_to_rad(T.SWING_REST_DEG) + swing_d
	var ks := posmod(roundi(sa / step), n)
	var corner := (SWING_EYE.rotated(qa) + Vector2(3, 3).rotated(ks * step))
	_swing.region_rect = MotoArt.swing.rects[ks]
	_swing.position = rp + _snap(corner) + MotoArt.swing.offsets[ks] * _a
	var axles := [rear, front]
	for w in 2:
		var center := rp + _snap((axles[w] as Vector2).rotated(qa))
		var sprite := _wheels[w]
		if absf(_wheel_spin[w]) > T.WHEEL_BLUR_SPEED:
			sprite.region_rect = MotoArt.wheel.rects[T.WHEEL_FRAMES]
			sprite.position = center + MotoArt.wheel_blur_offset * _a
		else:
			var kw := posmod(roundi(_wheel_angle[w] / TAU * T.WHEEL_FRAMES), T.WHEEL_FRAMES)
			sprite.region_rect = MotoArt.wheel.rects[kw]
			sprite.position = center + MotoArt.wheel.offsets[kw] * _a
	_place_rider(rp, qa)


func _place_rider(rp: Vector2, qa: float) -> void:
	if rider == null or not is_instance_valid(rider) or not _rider_attached:
		return
	var rig := _rig()
	var peg := rp + T.PEG.rotated(qa)
	match mode:
		Mode.RIDING:
			rider.global_position = peg.round()
			if rig and (_rig_tween == null or not _rig_tween.is_valid()):
				# Wrapped: a tween from here (dismount, crash) must turn the short way.
				rig.rotation = wrapf(qa, -PI, PI)
		Mode.MOUNTING:
			if rig:
				var d := _action_duration(rig, MOUNT_ACTION)
				var u: float = smoothstep(0.0, 1.0, clampf(rig.action_elapsed() / d, 0.0, 1.0)) if _current_action(rig) == MOUNT_ACTION else 1.0
				var at := _mount_start + _root_motion(rig, MOUNT_ACTION) + _fix * u
				rider.global_position = (peg if _current_action(rig) == RIDE_ACTION else at).round()
		Mode.DISMOUNTING:
			if rig:
				var d := _action_duration(rig, DISMOUNT_ACTION)
				var u: float = smoothstep(0.0, 1.0, clampf(rig.action_elapsed() / d, 0.0, 1.0))
				rider.global_position = (_dis_peg + _root_motion(rig, DISMOUNT_ACTION) + _fix * u).round()


# Side stand: a leg from the footpeg to the ground STAND_BACK behind it, outlined, rebuilt for the
# slope where the bike parks (the bike is frozen while parked).
func _make_stand() -> Sprite2D:
	var s := Sprite2D.new()
	s.centered = false
	s.scale = Vector2.ONE * _a
	s.visible = false
	return s


func _show_stand(on: bool) -> void:
	_stand.visible = on
	if not on or track == null:
		return
	var n := MotoArt.body_steps()
	var qa := posmod(roundi(angle / (TAU / n)), n) * (TAU / n)
	var top := _snap(pos) + _snap(T.PEG.rotated(qa))
	var gx := top.x - T.STAND_BACK
	var foot := _snap(Vector2(gx, track.height_at(gx)))
	var d := Vector2i(((foot - top) / _a).round())
	var w := absi(d.x) + 3
	var h := maxi(d.y, 1) + 3
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var origin := Vector2(w - 2 if d.x < 0 else 1, 1)
	var steps := maxi(absi(d.x), absi(d.y))
	var pts: Array[Vector2i] = []
	for i in steps + 1:
		pts.append(Vector2i((origin + Vector2(d) * (float(i) / maxf(steps, 1))).round()))
	for p in pts:
		for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var q: Vector2i = p + o
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and img.get_pixelv(q).a == 0.0:
				img.set_pixelv(q, Color("#141013"))
	for p in pts:
		img.set_pixelv(p, T.STAND_COLOR)
	_stand.texture = ImageTexture.create_from_image(img)
	_stand.offset = -origin
	_stand.position = top
