extends CharacterBody2D

signal state_changed(state: StringName)

const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const RIG_SCENE := "res://rig/adventurer.tscn"
const STUB_SCRIPT := preload("res://game/adventurer_stub.gd")
const CombatController := preload("res://game/combat/combat_controller.gd")
const SwimController := preload("res://game/swim/swim_controller.gd")
const StuckProjectiles := preload("res://game/combat/stuck_projectiles.gd")
const FogHooks := preload("res://game/fog_hooks.gd")
const SWIM_ACTIONS_PATH := "res://rig/clips/swim_actions.gd"

enum State { IDLE, WALK, RUN, SPRINT, SKID, ROLL, DODGE, JUMP, FALL, HANG, CLIMB, DESCEND, LEAP, WALL_SLIDE, CROUCH, CRAWL, STEP, PUSH, HURT, SWIM, DIVE }

# Actions whose horizontal root motion drives the body while they play.
const GROUND_ACTIONS: Array[StringName] = [&"skid_turn", &"roll", &"roll_back", &"dodge", &"punch_1", &"punch_2", &"punch_3", &"punch_4", &"ninja_strike"]
const EVADE_ACTIONS: Array[StringName] = [&"dodge", &"roll", &"roll_back"]
# Directional double jump: a puff thrown back along the launch (dir is relative to the facing).
const DOUBLE_JUMP_TRAIL := {"count": 8, "life": 0.4, "speed": 170.0, "rise": -14.0, "spread": 34.0, "dir": -1}

@export_group("Speed")
# Stick strength (after the action deadzone) at which walking reaches WALK_SPEED.
@export_range(0.0, 1.0) var walk_full_tilt := 0.5
# Stick strength at which the run reaches RUN_SPEED; keyboard is always 1.
@export_range(0.0, 1.0) var run_full_tilt := 0.8
@export_range(0.0, 1.0) var sprint_min_tilt := 0.2

@export_group("Acceleration")
@export var acceleration := 3300.0
# Run to sprint in ~0.39 s at SPRINT_SPEED ~1426.
@export var sprint_acceleration := 1900.0
@export var deceleration := 3800.0
@export var turn_deceleration := 8500.0
@export var air_acceleration := 2100.0
@export var air_deceleration := 800.0

@export_group("Jump")
@export var gravity := 2600.0
@export var fall_gravity_multiplier := 1.35
@export var max_fall_speed := 2400.0
# Peak height ~ jump_speed^2 / (2 * gravity) = 325 units; a double jump at the apex adds ~600.
@export var jump_speed := 1300.0
# Vertical speed kept when the button is released while rising.
@export_range(0.0, 1.0) var jump_cut := 0.45
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.12
# Takeoff fallback when the rig never sends the takeoff event.
@export var takeoff_timeout := 0.3

@export_group("Skid")
# Reversing the stick above this speed triggers skid_turn instead of a plain facing flip. Any
# tilt past the action deadzone counts: a real stick sweeps through low tilt on the way over.
# Above the run speed: a run turns on the spot, only the sprint skids.
@export var skid_min_speed := 800.0
@export_range(0.0, 1.0) var skid_min_tilt := 0.0

@export_group("Evade")
# B shortly after the stick turned the character counts as "against the facing": the turn is
# undone and roll_back plays, since the stick usually lands a few frames before the button.
@export var evade_turn_grace := 0.12
# Minimum time between the start of an evade (dodge, roll, roll_back) and the next B: earlier
# presses are ignored (no buffering). A B past it cancels the running evade and starts the new one
# at once, along the stick at that moment.
@export var dodge_chain_after := 0.15
# A chained evade only gets its invulnerability window when the last one granted started at least
# this long ago: spamming B keeps the movement but not endless i-frames.
@export var evade_iframe_rearm := 0.45

@export_group("Ledge")
# Hand point window around the corner, along the facing (behind, ahead) and vertically.
@export var grab_reach_behind := 70.0
@export var grab_reach_ahead := 30.0
@export var grab_tolerance_y := 30.0
# How far from the corner, on top of the platform, move_down still starts ledge_descend.
@export var top_grab_reach := 150.0
@export var regrab_delay := 0.35
# While hanging, A acts on the dominant stick axis once it passes this strength.
@export_range(0.0, 1.0) var hang_stick_threshold := 0.5
# ledge_leap launch, applied on its takeoff event (away from the wall, upwards).
@export var leap_speed_x := 760.0
@export var leap_speed_y := 1000.0

@export_group("Crouch")
@export var crawl_speed := 172.0
@export var crawl_acceleration := 1600.0
# Stick tilt at which crawling reaches crawl_speed.
@export_range(0.0, 1.0) var crawl_full_tilt := 0.5
# Fallback crouch height as a fraction of the standing height when the rig has no CROUCH_HEIGHT.
@export_range(0.2, 1.0) var crouch_height_ratio := 0.45
# Crouch by stick angle: within this cone around "down" and past crouch_enter_magnitude; once
# crouched, any stick in the lower half (down above crouch_keep_down) keeps it.
@export var crouch_cone_degrees := 65.0
@export var crouch_enter_magnitude := 0.35
@export var crouch_keep_down := 0.15
# Letting go of down stands up only after this long (down again in time keeps the crouch).
@export var crouch_release_grace := 0.22
# Moving into a low ceiling (a tunnel mouth) crouches by itself.
@export var auto_crouch_into_low_ceiling := true
@export var auto_crouch_recent := 0.3
@export var auto_crouch_probe := 40.0

@export_group("Steps")
# Steps lower than this are taken by a plain position nudge, without an action.
@export var small_step_height := 30.0
# Step-up duration when the rig has no play_step_up.
@export var step_fallback_time := 0.15
@export_range(0.0, 1.0) var push_min_tilt := 0.2

@export_group("Hero landing")
# Touchdown speed (units/s, ~660 units of free fall) that plays the hero landing instead of the
# plain one; its juice scales from here up to max_fall_speed.
@export var hero_landing_vy := 2150.0
# Movement or A ends the pose after this long; before it the body is locked in the slam.
@export var hero_cancel_after := 0.35
# Ground friction while the pose plays (a sprinting landing slides a little).
@export var hero_friction := 6000.0
@export var hero_shake := 36.0
@export var hero_shake_time := 0.35
@export var hero_hitstop := 0.08

@export_group("Look")
# Holding the stick down (crouched) or up (standing) this long while still moves the view and the
# head; past look_stick_threshold of raw stick strength.
@export var look_hold_time := 1.0
# From here on the view and the head start easing towards the look, reaching it at look_hold_time.
@export var look_lead_time := 0.35
@export_range(0.0, 1.0) var look_stick_threshold := 0.6
# Still on the floor, a stick within this angle of straight up or down is a pure vertical intent:
# its horizontal part neither walks nor breaks the look.
@export_range(0.0, 60.0) var look_cone_degrees := 35.0

@export_group("Hurt")
@export var knockback_x := 520.0
@export var knockback_y := 380.0
# Minimum control lock after a hit; it lasts until the rig's reaction sends can_move (or ends),
# capped by hurt_max_lock in case neither arrives.
@export var hurt_stun_time := 0.4
@export var hurt_max_lock := 4.0
# Grace after a hit so continuous damage (trap, burst) does not hit every frame.
@export var hurt_mercy_time := 0.6
# Blink (alpha toggling on the whole player) while the mercy window lasts.
@export var mercy_blink_period := 0.08
@export_range(0.0, 1.0) var mercy_blink_alpha := 0.3
@export var hurt_shake := 28.0
@export var hurt_shake_time := 0.3
@export var hurt_hitstop := 0.08
# Projectile damage (take_hit) that gives a full-strength reaction; less scales it down to half.
@export var arrow_hurt_reference := 34.0
# Cap of apply_push per call (units/s).
@export var push_max := 420.0

@export_group("Wall")
# Any vertical wall from the head down to mid body can be grabbed; off: only climbable_wall.
@export var wall_grab_any := true
@export var wall_slide_max_speed := 170.0
# Seconds in the air, off any wall or ledge, before the holstered weapon comes back.
@export var climb_holster_air_grace := 0.35
@export var wall_slide_fast_speed := 600.0
@export_range(0.0, 1.0) var wall_slide_gravity_scale := 0.35
# How fast upward speed dies after grabbing the wall (units/s^2).
@export var wall_grab_upward_damp := 5200.0
# Stick held away from the wall for this long releases it.
@export var wall_release_delay := 0.12
@export var wall_coyote_time := 0.08
@export var wall_jump_x := 650.0
@export var wall_jump_y := 1100.0
# Input towards the wall just left is ignored for this long after a wall jump.
@export var wall_jump_input_lock := 0.14
# Wall kick (A with the stick towards the wall or neutral): short hop up, Mega Man X style.
@export var wall_kick_x := 300.0
@export var wall_kick_y := 1000.0
@export var wall_kick_input_lock := 0.05

@export_group("Double jump")
@export var max_air_jumps := 1
# Double jump speed as a share of jump_speed: ~1.75x a single jump's height from where it is pressed
# (~600 up; ~720 with the stick up).
@export_range(0.0, 2.0) var double_jump_ratio := 1.36
# Pressed while still rising fast, the double jump adds at least this on top of the current rise,
# so it never slows the climb.
@export var double_jump_min_add := 150.0
# Horizontal speed the double jump sets along the left stick at takeoff, scaled by the stick's
# horizontal component up to double_jump_full_tilt (it reverses the motion and the facing when
# the stick points back); the current speed is ignored.
@export var double_jump_x_boost := 1250.0
@export_range(0.1, 1.0) var double_jump_full_tilt := 0.7
# Stick up adds up to this fraction of vertical speed; stick down never lowers the jump.
@export_range(0.0, 0.5) var double_jump_up_bonus := 0.1
# With the stick neutral the double jump goes straight up, keeping only this much horizontal speed.
@export_range(0.0, 1.0) var double_jump_neutral_keep := 0.0
@export_range(0.0, 1.0) var double_jump_neutral_tilt := 0.1
# After the double jump, air deceleration is off this long so the boost carries.
@export var double_jump_air_hold := 0.35
# Air acceleration until the next landing or grab after a wall jump: high enough to turn back
# to the same wall while still rising (zigzag climb), but only with good timing.
@export var wall_jump_air_acceleration := 6000.0

var rig
var combat: Node
var swim: Node
# Projectiles stuck in the body (arrows), following their bones.
var stuck: Node
# Held look: 1 down (crouched), -1 up (standing), 0 none; read by the camera.
var look_dir := 0
# Signed look weight (-1 up .. 1 down) easing in from look_lead_time; the camera follows it.
var look_amount := 0.0
# Hero landing: fastest fall speed since the body last rose, touched a wall, a ledge or water.
var _drop_vy := 0.0
var _was_airborne := false
var _hero_t := 0.0
# Hitstop of the slam, applied after the rig's next tick so the freeze shows the landing pose.
var _hero_hitstop := 0.0
var _look_want := 0
var _look_hold := 0.0
# Public handle to the Adventurer (or the stub) driven by this player.
var adventurer: Node2D:
	get:
		return rig
# Under take_control, gravity keeps acting unless the owner turns this off.
var controlled_gravity := true
var uses_stub := false
var walk_speed := 288.0
var run_speed := 602.0
var sprint_speed := 877.0
var hang_grip_offset := Vector2(72, -440)
var wall_contact_offset := 66.0
# Origin relative to the corner when standing on top (after ledge_climb, before ledge_descend).
var ledge_top_offset := Vector2(90, 0)
var step_max_height := 120.0
var step_forward := 60.0
var push_contact_offset := 80.0
# A visible CanvasItem/CanvasLayer (the sound board) that takes the input away from the player.
var input_blocker: Object

var state: State = State.IDLE
var facing := 1
var invulnerable := false
var current_action: StringName = &""
var input_axis := 0.0
var target_speed := 0.0
var surface: StringName = &"grass"
var hanging := false
var climbing := false
var descending := false
var leaping := false
var ledge
var wall_sliding := false
var _climb_air_left := 0.0
var crouching := false
var stepping := false
var pushing := false
# Direction from the body to the wall being slid (or last slid).
var wall_dir := 1

var _pending_facing := 1
var _action_done: StringName = &""
var _action_time := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _takeoff_pending := false
var _takeoff_wait := 0.0
var _rising_jump := false
var _leap_flight := false
var _regrab := 0.0
var _skid_sfx := -1
var _skid_haptic := -1
var _shape: CollisionShape2D
var _radius := 65.0
var _stand_capsule: CapsuleShape2D
var _crouch_capsule: CapsuleShape2D
var _crouch_height := 0.0
var _crouch_release := 0.0
var _since_crouched := INF
var _since_stick_turn := INF
var _since_dodge := INF
var _since_iframes := INF
var _evade_iframes := true
var _blocked := false
var _prev_sole := Vector2.ZERO
var _fall_vy := 0.0
var _swim_capsule: CapsuleShape2D
var _swim_center := Vector2(0, -200)
var _swim_shape_on := false
var _controllers: Array[Node] = []
var hurting := false
var _hurt_left := 0.0
var _hurt_total := 0.0
var _hurt_rig := false
var _hurt_released := false
var _mercy_left := 0.0
var _hitstop_until_ms := 0
var _step_rig := false
var _step_t := 0.0
var _step_from := Vector2.ZERO
var _step_to := Vector2.ZERO
var _step_speed := 0.0
var _push_sfx := -1
var _push_haptic := -1
var _wall_release := 0.0
var _wall_coyote := 0.0
var _wall_takeoff_pending := false
var _wall_takeoff_kind: StringName = &"wall_jump"
var _air_jumps := 1
var _double_pending := false
var _dj_hold := 0.0
# F1 hint: a grabbable wall touches the body right now. Counter for capture logs.
var wall_grab_hint := false
var wall_kick_count := 0
var _wall_lock := 0.0
var _wall_lock_dir := 0
var _wall_flight := false
var _wall_sfx := -1
var _wall_haptic := -1


func _ready() -> void:
	add_to_group(&"player")
	_shape = $Collision
	_spawn_rig()
	_fit_collision()
	combat = CombatController.new()
	combat.name = "Combat"
	add_child(combat)
	combat.setup(self)
	swim = SwimController.new()
	swim.name = "Swim"
	add_child(swim)
	swim.setup(self)
	stuck = StuckProjectiles.new()
	stuck.name = "Stuck"
	add_child(stuck)
	stuck.setup(self)


func _spawn_rig() -> void:
	var force_stub := "--stub-rig" in OS.get_cmdline_user_args()
	if not force_stub and ResourceLoader.exists(RIG_SCENE):
		var scene := load(RIG_SCENE) as PackedScene
		if scene:
			rig = scene.instantiate()
		# A rig whose script failed to load has no contract: fall back to the stub.
		if rig and not rig.has_method(&"set_locomotion"):
			push_warning("Adventurer rig at %s does not implement the contract; using the stub." % RIG_SCENE)
			rig.free()
			rig = null
	if rig == null:
		rig = Node2D.new()
		rig.set_script(STUB_SCRIPT)
		uses_stub = true
	rig.name = "Adventurer"
	add_child(rig)
	var c := _rig_constants()
	walk_speed = float(c.get("WALK_SPEED", walk_speed))
	run_speed = float(c.get("RUN_SPEED", run_speed))
	sprint_speed = float(c.get("SPRINT_SPEED", sprint_speed))
	hang_grip_offset = c.get("HANG_GRIP_OFFSET", hang_grip_offset)
	ledge_top_offset = c.get("LEDGE_TOP_OFFSET", ledge_top_offset)
	step_max_height = float(c.get("STEP_MAX_HEIGHT", step_max_height))
	var forward: Variant = c.get("STEP_FORWARD", step_forward)
	step_forward = forward.x if forward is Vector2 else float(forward)
	var push: Variant = c.get("PUSH_CONTACT_OFFSET", push_contact_offset)
	push_contact_offset = push.x if push is Vector2 else float(push)
	# One crouched capsule for crouch and crawl: the taller of the two.
	if c.has("CROUCH_HEIGHT") or c.has("CRAWL_HEIGHT"):
		_crouch_height = maxf(float(c.get("CROUCH_HEIGHT", 0.0)), float(c.get("CRAWL_HEIGHT", 0.0)))
	var contact: Variant = c.get("WALL_CONTACT_OFFSET", wall_contact_offset)
	wall_contact_offset = contact.x if contact is Vector2 else float(contact)
	if "juice" in rig:
		rig.juice = true
	rig.facing = facing
	_connect_rig(&"action_finished", _on_action_finished)
	_connect_rig(&"action_event", _on_action_event)
	_connect_rig(&"footstep", _on_footstep)
	_connect_rig(&"landed", _on_landed)


func _connect_rig(sig: StringName, callable: Callable) -> void:
	if rig.has_signal(sig):
		rig.connect(sig, callable)


func _rig_constants() -> Dictionary:
	var out := {}
	var script := rig.get_script() as Script
	while script:
		var map := script.get_script_constant_map()
		for key in map:
			if not out.has(key):
				out[key] = map[key]
		script = script.get_base_script()
	return out


func _fit_collision() -> void:
	var height := GameScale.character_height()
	_stand_capsule = CapsuleShape2D.new()
	_stand_capsule.radius = roundf(height * 0.17)
	_stand_capsule.height = roundf(height * 0.96)
	_radius = _stand_capsule.radius
	if _crouch_height <= 0.0:
		_crouch_height = roundf(height * crouch_height_ratio)
	_crouch_capsule = CapsuleShape2D.new()
	_crouch_capsule.radius = _radius
	_crouch_capsule.height = maxf(_crouch_height, _radius * 2.0 + 2.0)
	_apply_capsule(_stand_capsule)
	# Swimming body lying along the motion: shorter than standing, covering torso and head.
	_swim_capsule = CapsuleShape2D.new()
	_swim_capsule.radius = roundf(_radius * 0.8)
	_swim_capsule.height = roundf(_stand_capsule.height * 0.62)
	if ResourceLoader.exists(SWIM_ACTIONS_PATH):
		var map := (load(SWIM_ACTIONS_PATH) as Script).get_script_constant_map()
		if map.has("SWIM_CENTER"):
			_swim_center = map.SWIM_CENTER


func _apply_capsule(capsule: CapsuleShape2D) -> void:
	_shape.shape = capsule
	_shape.rotation = 0.0
	_shape.position = Vector2(0, -capsule.height * 0.5)


# Lying swim collision (surface / under): a capsule along the swim direction around the body
# centre. Back to the standing capsule only where it fits, else the body is pushed out first.
func set_swim_shape(on: bool, direction: Vector2 = Vector2.RIGHT) -> void:
	if on:
		_shape.shape = _swim_capsule
		_shape.position = _swim_center
		var d := direction if direction.length() > 1.0 else Vector2(facing, 0.0)
		_shape.rotation = d.angle() + PI * 0.5
		_swim_shape_on = true
		return
	if not _swim_shape_on:
		return
	if not _capsule_fits(global_position):
		for step in range(1, 31):
			var up := global_position + Vector2(0, -12.0 * step)
			if _capsule_fits(up):
				global_position = up
				break
			var side := global_position + Vector2(-facing * 12.0 * step, 0)
			if _capsule_fits(side):
				global_position = side
				break
	_swim_shape_on = false
	_apply_capsule(_crouch_capsule if crouching else _stand_capsule)


# Left stick (raw, before the action deadzones) decides crouching by angle, with hysteresis and a
# short release grace; heading into a low ceiling crouches automatically.
func _update_crouch(delta: float, dir: int, low_ceiling: bool) -> void:
	_since_crouched = 0.0 if crouching else _since_crouched + delta
	var stick := Vector2.ZERO
	if not _blocked:
		stick = Vector2(
			Input.get_action_raw_strength(&"move_right") - Input.get_action_raw_strength(&"move_left"),
			Input.get_action_raw_strength(&"move_down") - Input.get_action_raw_strength(&"move_up"))
	var length := stick.length()
	var enter := length >= crouch_enter_magnitude and stick.y / maxf(length, 0.001) >= cos(deg_to_rad(crouch_cone_degrees))
	var keep := crouching and stick.y >= crouch_keep_down
	if enter or keep:
		_crouch_release = 0.0
		_set_crouch(true)
		return
	if not crouching and auto_crouch_into_low_ceiling and dir != 0 and _low_ceiling_ahead(dir):
		if _since_crouched <= auto_crouch_recent or absf(velocity.x) > 40.0:
			_set_crouch(true)
			return
	if crouching and not low_ceiling:
		_crouch_release += delta
		if _crouch_release >= crouch_release_grace and not _low_ceiling_ahead(dir):
			_crouch_release = 0.0
			_set_crouch(false)


# A low ceiling right ahead: the standing body does not fit there but the crouched one does.
func _low_ceiling_ahead(dir: int) -> bool:
	if dir == 0:
		return false
	var ahead := global_position + Vector2(dir * (auto_crouch_probe + absf(velocity.x) / Engine.physics_ticks_per_second), -1.0)
	return not _capsule_fits(ahead) and _capsule_fits(ahead, _crouch_capsule)


func _set_crouch(value: bool) -> void:
	if crouching == value:
		return
	crouching = value
	_apply_capsule(_crouch_capsule if value else _stand_capsule)


func crouch_collision_height() -> float:
	return _crouch_capsule.height


# True when the standing capsule fits here (no low ceiling above the crouched body).
func can_stand() -> bool:
	var probe := CapsuleShape2D.new()
	probe.radius = _stand_capsule.radius - 2.0
	probe.height = _stand_capsule.height - 4.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, global_position + Vector2(0, -_stand_capsule.height * 0.5 - 2.0))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- Input (silenced while the sound board is open) ----------------------------------------

func _just(action: StringName) -> bool:
	return not _blocked and Input.is_action_just_pressed(action)


func _held(action: StringName) -> bool:
	return not _blocked and Input.is_action_pressed(action)


func _axis(negative: StringName, positive: StringName) -> float:
	return 0.0 if _blocked else Input.get_axis(negative, positive)


func _physics_process(delta: float) -> void:
	# Hitstop runs at time_scale 0: physics still ticks with delta 0 (root motion / delta would be NaN).
	if delta <= 0.0:
		return
	_blocked = (input_blocker != null and input_blocker.visible) or is_controlled()
	_mercy_left = maxf(0.0, _mercy_left - delta)
	if _mercy_left > 0.0:
		modulate.a = mercy_blink_alpha if int(_mercy_left / mercy_blink_period) % 2 == 0 else 1.0
	elif modulate.a != 1.0:
		modulate.a = 1.0
	input_axis = _axis(&"move_left", &"move_right")
	_regrab = maxf(0.0, _regrab - delta)
	_since_stick_turn += delta
	_since_dodge += delta
	_since_iframes += delta
	_action_time += delta
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if _just(&"jump"):
		_jump_buffer = jump_buffer_time
	var on_floor := is_on_floor()
	if on_floor and _vertical_intent() != 0:
		input_axis = 0.0
	var landed_now := on_floor and _was_airborne
	_was_airborne = not on_floor
	if hanging or wall_sliding or swim.active():
		_drop_vy = 0.0
	_coyote = coyote_time if on_floor else maxf(0.0, _coyote - delta)
	_wall_coyote = maxf(0.0, _wall_coyote - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)
	_dj_hold = maxf(0.0, _dj_hold - delta)
	if on_floor:
		_leap_flight = false
		_wall_flight = false
		_air_jumps = max_air_jumps
	_update_look(delta, on_floor)

	if not hanging and not stepping and swim.update(delta):
		# set_locomotion is the rig's tick: its actions (water_exit, a drowning hurt) only advance
		# through it, also while swimming.
		if swim.exiting():
			rig.set_locomotion(0.0, delta)
			if swim.exit_step(rig.take_root_motion()):
				_update_state()
				return
			_update_state()
			return
		swim.control(delta)
		if swim.exiting():
			rig.set_locomotion(0.0, delta)
			swim.exit_step(rig.take_root_motion())
			_update_state()
			return
		if swim.active() and not swim.exiting():
			rig.set_locomotion(absf(velocity.x), delta)
			rig.take_root_motion()
			move_and_slide()
			swim.after_move()
			_update_state()
			return
		on_floor = false

	_update_climb_holster(delta, on_floor)
	var can_act := not hanging and not wall_sliding and not stepping and not hurting and not crouching
	combat.step(delta, on_floor, can_act)

	if hurting:
		# Knockback, then friction to a stop: no sliding while down; no input until can_move.
		_hurt_left -= delta
		_hurt_total += delta
		if on_floor:
			velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		if (_hurt_left <= 0.0 and (_hurt_released or not _hurt_rig)) or _hurt_total >= hurt_max_lock:
			hurting = false
	elif stepping:
		pass
	elif hanging:
		_hang_control()
	elif combat.blocks_movement():
		_set_pushing(false)
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
	elif wall_sliding:
		_wall_control(delta)
	elif current_action == &"hero_landing":
		_hero_control(delta, on_floor)
	elif current_action.is_empty():
		_control(delta, on_floor)
	elif current_action in EVADE_ACTIONS and on_floor and _just(&"roll"):
		_chain_dodge()

	if _takeoff_pending or _wall_takeoff_pending or _double_pending:
		_takeoff_wait += delta
		if _takeoff_wait >= takeoff_timeout:
			if _wall_takeoff_pending:
				_wall_takeoff()
			elif _double_pending:
				_double_takeoff()
			else:
				_takeoff()

	if not on_floor and crouching and can_stand():
		_set_crouch(false)
	rig.set_locomotion(0.0 if hanging else absf(velocity.x), delta)
	if _hero_hitstop > 0.0:
		hitstop(_hero_hitstop)
		_hero_hitstop = 0.0
	if rig.has_method(&"set_crouch"):
		rig.set_crouch(crouching, absf(velocity.x) if crouching else 0.0, delta)
	if rig.has_method(&"set_airborne"):
		rig.set_airborne(not hanging and not on_floor and not wall_sliding, velocity.y)
	if landed_now:
		var drop := _drop_vy
		_drop_vy = 0.0
		if drop >= hero_landing_vy:
			_start_hero_landing(drop)
	if rig.has_method(&"set_wall_slide"):
		rig.set_wall_slide(wall_sliding, maxf(velocity.y, 0.0) if wall_sliding else 0.0)
	if rig.has_method(&"set_push"):
		rig.set_push(pushing, delta)
	var motion: Vector2 = rig.take_root_motion()

	if stepping:
		_advance_step(motion, delta)
		_update_state()
		return

	if hanging:
		if climbing or descending:
			global_position += motion
		match _action_done:
			&"ledge_climb":
				_finish_climb()
			&"ledge_descend":
				_finish_descend()
			&"ledge_leap":
				# Fallback when the rig never sent takeoff.
				_leap_takeoff()
		_action_done = &""
		if hanging:
			_update_state()
			return

	var kicking := current_action == &"flying_kick"
	if kicking:
		# The flying kick's root motion is the whole trajectory: X and Y, no gravity.
		velocity = motion / delta
	elif current_action in GROUND_ACTIONS or _action_done in GROUND_ACTIONS:
		velocity.x = motion.x / delta
	if not _action_done.is_empty() and _action_done == current_action:
		current_action = &""
		invulnerable = false
		_stop_skid_loop()
		_set_facing(_pending_facing)
	_action_done = &""

	if not wall_sliding and not kicking:
		_apply_gravity(delta, on_floor)
	if not on_floor:
		_fall_vy = maxf(_fall_vy, velocity.y)
		_drop_vy = maxf(_drop_vy, velocity.y) if velocity.y > 0.0 else 0.0
	var hand_before := _hand_point()
	var vx_before := velocity.x
	move_and_slide()
	_read_surface()
	_fog_frame()
	if kicking and current_action == &"flying_kick":
		combat.kick.probe()
		if is_on_floor():
			# The kick has its own heavy landing.
			_drop_vy = 0.0
			combat.kick.landed()
	if wall_sliding:
		_wall_after_move()
	elif not is_on_floor() and current_action.is_empty() and not _takeoff_pending and not _wall_takeoff_pending:
		_try_wall_grab(vx_before)
	if not is_on_floor() and current_action.is_empty() and not _takeoff_pending:
		_try_air_grab(hand_before.y)
	_update_state()


func _control(delta: float, on_floor: bool) -> void:
	var dir := int(signf(input_axis))
	var tilt := absf(input_axis)

	var low_ceiling := crouching and not can_stand()
	if on_floor and _jump_buffer > 0.0 and _held(&"move_down") and not low_ceiling and _try_top_grab():
		_jump_buffer = 0.0
		return
	var air_wall := 0 if on_floor else _air_wall_side()
	wall_grab_hint = air_wall != 0
	var busy_takeoff := _takeoff_pending or _wall_takeoff_pending or _double_pending
	# Ground coyote first (normal jump), then a touching wall (wall jump), then the double jump.
	if _jump_buffer > 0.0 and _coyote <= 0.0 and not on_floor and not busy_takeoff and (air_wall != 0 or _wall_coyote > 0.0):
		# Touching a grabbable wall (or just left one): wall jump before the double jump.
		if air_wall != 0:
			wall_dir = air_wall
		_start_wall_jump(_wall_jump_kind())
	elif _jump_buffer > 0.0 and _coyote <= 0.0 and not on_floor and not busy_takeoff and _air_jumps > 0:
		_start_double_jump()
	elif _jump_buffer > 0.0 and _coyote > 0.0 and not _takeoff_pending:
		# Under a low ceiling jumping is off; otherwise a crouched jump stands up first.
		if low_ceiling:
			_jump_buffer = 0.0
		else:
			_set_crouch(false)
			_start_jump()

	if on_floor and not _takeoff_pending:
		_update_crouch(delta, dir, low_ceiling)
		low_ceiling = crouching and not can_stand()

	var momentum := _leap_flight or _wall_flight or _dj_hold > 0.0
	if _wall_lock > 0.0 and dir == _wall_lock_dir:
		dir = 0
		tilt = 0.0
		momentum = true

	if on_floor and not _takeoff_pending:
		if _just(&"roll") and not low_ceiling and _since_dodge >= dodge_chain_after:
			_set_crouch(false)
			if _start_evade(dir):
				return
		var reversing := dir != 0 and velocity.x != 0.0 and dir != int(signf(velocity.x))
		if reversing and not crouching and absf(velocity.x) >= skid_min_speed and tilt >= skid_min_tilt:
			if _start_action(&"skid_turn", dir):
				return

	if on_floor and dir != 0 and not crouching and not _takeoff_pending:
		var front := _probe_front(dir)
		if front.has("crate"):
			if dir == facing and tilt >= push_min_tilt:
				_push_crate(front.crate, dir, delta)
				return
		elif not front.is_empty():
			if _try_step(front, dir):
				return
			if dir == facing and tilt >= push_min_tilt:
				_set_pushing(true)
				global_position.x = front.wall_x - dir * maxf(push_contact_offset, _radius + 0.5)
				velocity.x = 0.0
				target_speed = 0.0
				return
	_set_pushing(false)

	# While still moving fast the old way on the ground, the facing stays: only skid_turn (its flip)
	# may turn the character, otherwise the rig would slide the skid towards the new side.
	var fast_the_old_way := on_floor and absf(velocity.x) >= skid_min_speed and int(signf(velocity.x)) == facing
	if dir != 0 and dir != facing and not fast_the_old_way:
		_set_facing(dir)
		_since_stick_turn = 0.0

	target_speed = _speed_for_tilt(tilt) if dir != 0 else 0.0
	if crouching:
		target_speed = crawl_speed * clampf(tilt / crawl_full_tilt, 0.0, 1.0) if dir != 0 else 0.0
	var target := target_speed * dir
	var rate: float
	if on_floor and crouching:
		rate = crawl_acceleration if absf(target) > absf(velocity.x) and dir == int(signf(velocity.x)) else deceleration
	elif on_floor:
		rate = deceleration
		if dir != 0 and dir != int(signf(velocity.x)) and velocity.x != 0.0:
			rate = turn_deceleration
		elif dir != 0 and absf(target) > absf(velocity.x):
			rate = sprint_acceleration if absf(velocity.x) >= run_speed else acceleration
	else:
		# Air control keeps momentum above the target speed in the same direction; a ledge leap
		# also keeps it with the stick released, so it can reach the opposite ledge.
		if (dir != 0 and signf(velocity.x) == dir and absf(velocity.x) > absf(target)) or (dir == 0 and momentum):
			target = velocity.x
		rate = air_acceleration if dir != 0 else air_deceleration
		if _wall_flight and dir != 0:
			rate = wall_jump_air_acceleration
	velocity.x = move_toward(velocity.x, target, rate * delta)


func _speed_for_tilt(tilt: float) -> float:
	if _held(&"sprint") and tilt >= sprint_min_tilt:
		return sprint_speed
	if tilt >= run_full_tilt:
		return run_speed
	if tilt <= walk_full_tilt:
		return walk_speed * tilt / walk_full_tilt
	return lerpf(walk_speed, run_speed, inverse_lerp(walk_full_tilt, run_full_tilt, tilt))


# B: neutral stick dodges in place, towards the facing rolls forward, against it rolls back.
func _evade_id(dir: int) -> StringName:
	if dir == facing:
		return &"roll"
	if dir == -facing:
		return &"roll_back"
	return &"dodge"


func _start_evade(dir: int) -> bool:
	if dir != 0 and dir == facing and _since_stick_turn <= evade_turn_grace:
		_set_facing(-dir)
	return _start_action(_evade_id(dir), facing)


func _chain_dodge() -> void:
	if _since_dodge < dodge_chain_after:
		return
	# The rig cancels the running evade itself; the new one's i-frames only count once rearmed.
	var rearmed := _since_iframes >= evade_iframe_rearm
	if _start_evade(int(signf(input_axis))):
		_evade_iframes = rearmed


func _start_action(id: StringName, end_facing: int) -> bool:
	if not rig.play_action(id):
		return false
	var sole := global_position
	if id in [&"roll", &"roll_back"]:
		FogHooks.burst(sole, 170.0, 0.8)
	elif id == &"dodge":
		var vx := velocity.x if absf(velocity.x) > 50.0 else -facing * 400.0
		FogHooks.push(sole + Vector2(0, -200), Vector2(1.2 * vx, -200), 200.0, 1.2)
		FogHooks.swirl(sole + Vector2(0, -150), 190.0, 1.2 * signf(vx))
	if id in EVADE_ACTIONS:
		_since_dodge = 0.0
		_evade_iframes = true
	current_action = id
	_action_time = 0.0
	_pending_facing = end_facing
	_action_done = &""
	invulnerable = false
	return true


func _set_facing(dir: int) -> void:
	facing = dir
	if rig.facing != dir:
		rig.facing = dir


# --- Jump -------------------------------------------------------------------------------------

func _start_jump() -> void:
	_jump_buffer = 0.0
	_coyote = 0.0
	_takeoff_pending = true
	_takeoff_wait = 0.0
	if not rig.play_action(&"jump"):
		_takeoff()


func _takeoff() -> void:
	_takeoff_pending = false
	# The crouch before the takeoff kept refilling coyote time: without this, A pressed again right
	# after leaving the ground replayed the ground jump instead of the double jump.
	_coyote = 0.0
	velocity.y = -jump_speed
	_rising_jump = true
	if not _held(&"jump"):
		_cut_jump()


func _cut_jump() -> void:
	if _rising_jump and velocity.y < 0.0:
		velocity.y *= jump_cut
	_rising_jump = false


func _apply_gravity(delta: float, on_floor: bool) -> void:
	if is_controlled() and not controlled_gravity:
		return
	if _rising_jump and (velocity.y >= 0.0 or not _held(&"jump")):
		_cut_jump()
	if on_floor and velocity.y >= 0.0:
		return
	var g := gravity * (fall_gravity_multiplier if velocity.y > 0.0 else 1.0)
	velocity.y = minf(velocity.y + g * delta, max_fall_speed)


# --- Ledges -----------------------------------------------------------------------------------

func _hand_point() -> Vector2:
	return global_position + Vector2(hang_grip_offset.x * facing, hang_grip_offset.y)


func _hang_position(corner: Vector2, dir: int) -> Vector2:
	return corner - Vector2(hang_grip_offset.x * dir, hang_grip_offset.y)


func _try_air_grab(prev_hand_y: float) -> void:
	if _regrab > 0.0:
		return
	var hand := _hand_point()
	var y0 := minf(prev_hand_y, hand.y)
	var y1 := maxf(prev_hand_y, hand.y)
	for node in get_tree().get_nodes_in_group(&"ledges"):
		var l = node
		if l.face_dir != facing:
			continue
		var corner: Vector2 = l.global_position
		var along := (hand.x - corner.x) * facing
		if along < -grab_reach_behind or along > grab_reach_ahead:
			continue
		if y1 < corner.y - grab_tolerance_y or y0 > corner.y + grab_tolerance_y:
			continue
		_grab(l)
		return


func _grab(l) -> void:
	if not rig.play_action(&"ledge_grab"):
		return
	_enter_hang(l)
	global_position = _hang_position(l.global_position, l.face_dir)


func _enter_hang(l) -> void:
	_air_jumps = max_air_jumps
	_double_pending = false
	_set_crouch(false)
	_leave_wall(false)
	_wall_coyote = 0.0
	_wall_flight = false
	ledge = l
	hanging = true
	_update_climb_holster(0.0, false)
	climbing = false
	descending = false
	leaping = false
	_leap_flight = false
	current_action = &""
	_takeoff_pending = false
	_rising_jump = false
	invulnerable = false
	velocity = Vector2.ZERO
	_set_facing(l.face_dir)
	_shape.set_deferred(&"disabled", true)


# move_down + A at the top edge: step to the edge and let ledge_descend lower the body to the hang.
func _try_top_grab() -> bool:
	for node in get_tree().get_nodes_in_group(&"ledges"):
		var l = node
		var corner: Vector2 = l.global_position
		if absf(global_position.y - corner.y) > 8.0:
			continue
		var inward: float = (global_position.x - corner.x) * l.face_dir
		if inward < 0.0 or inward > top_grab_reach:
			continue
		var previous_facing := facing
		_set_facing(l.face_dir)
		if not rig.play_action(&"ledge_descend"):
			_set_facing(previous_facing)
			return false
		_enter_hang(l)
		descending = true
		global_position = corner + Vector2(ledge_top_offset.x * l.face_dir, ledge_top_offset.y)
		return true
	return false


# Hanging: the stick alone does nothing; A acts on the dominant axis (up climbs, down drops,
# away from the wall leaps). Neutral A or A towards the wall does nothing.
func _hang_control() -> void:
	if climbing or descending or leaping or not _just(&"jump"):
		return
	_jump_buffer = 0.0
	var x := input_axis
	var y := _axis(&"move_up", &"move_down")
	if maxf(absf(x), absf(y)) < hang_stick_threshold:
		return
	if absf(y) >= absf(x):
		if y < 0.0:
			climbing = rig.play_action(&"ledge_climb")
		else:
			_drop()
	elif int(signf(x)) == -facing:
		leaping = rig.play_action(&"ledge_leap")


func _leave_hang() -> void:
	var corner: Vector2 = ledge.global_position
	var wall_dir: int = ledge.face_dir
	hanging = false
	climbing = false
	descending = false
	leaping = false
	# Keep the hang offset (it already clears the wall); only push out if the capsule would overlap.
	global_position.x = corner.x - wall_dir * maxf(hang_grip_offset.x, _radius + 2.0)
	velocity = Vector2.ZERO
	_shape.set_deferred(&"disabled", false)


func _drop() -> void:
	if not rig.play_action(&"ledge_drop"):
		return
	_leave_hang()
	_regrab = regrab_delay


func _leap_takeoff() -> void:
	if not hanging:
		return
	var wall_dir: int = ledge.face_dir
	_leave_hang()
	_set_facing(-wall_dir)
	velocity = Vector2(-wall_dir * leap_speed_x, -leap_speed_y)
	_leap_flight = true


func _finish_climb() -> void:
	var corner: Vector2 = ledge.global_position
	global_position = corner + Vector2(ledge_top_offset.x * facing, ledge_top_offset.y)
	hanging = false
	climbing = false
	velocity = Vector2.ZERO
	_shape.set_deferred(&"disabled", false)


func _finish_descend() -> void:
	descending = false
	global_position = _hang_position(ledge.global_position, ledge.face_dir)


# --- Steps and pushing ------------------------------------------------------------------------

# What blocks the way ahead on the ground: {wall_x, height, top}. Height is INF when the obstacle
# reaches past STEP_MAX_HEIGHT or there is no room to stand on top of it.
func _probe_front(dir: int) -> Dictionary:
	var gap := maxf(push_contact_offset - _radius, 0.0) if pushing else 0.0
	var reach := gap + 4.0 + absf(velocity.x) / Engine.physics_ticks_per_second
	var hit := move_and_collide(Vector2(dir * reach, 0.0), true)
	if hit == null or absf(hit.get_normal().x) < 0.7 or int(-signf(hit.get_normal().x)) != dir:
		return {}
	var wall_x := hit.get_position().x
	var collider := hit.get_collider() as Node
	if collider and collider.is_in_group(&"push_crate"):
		return {"wall_x": wall_x, "height": INF, "top": -INF, "crate": collider}
	var feet := global_position.y
	var space := get_world_2d().direct_space_state
	var probe_x := wall_x + dir * 6.0
	var above := Vector2(probe_x, feet - step_max_height - 2.0)
	var point := PhysicsPointQueryParameters2D.new()
	point.position = above
	point.collision_mask = collision_mask
	point.exclude = [get_rid()]
	if not space.intersect_point(point, 1).is_empty():
		return {"wall_x": wall_x, "height": INF, "top": -INF}
	var ray := PhysicsRayQueryParameters2D.create(above, Vector2(probe_x, feet + 2.0), collision_mask, [get_rid()])
	var r := space.intersect_ray(ray)
	if r.is_empty():
		return {}
	var top: float = r.position.y
	var land := Vector2(wall_x + dir * (_radius + 4.0), top)
	if not _capsule_fits(land):
		return {"wall_x": wall_x, "height": INF, "top": top}
	return {"wall_x": wall_x, "height": feet - top, "top": top}


# Pushing a PushCrate: it slides on its own (push returns false when blocked); the body keeps
# touching its face at the crate's contact offset for this capsule. Nothing pushes the body back.
func _push_crate(crate: Node, dir: int, delta: float) -> void:
	var moved: bool = crate.push(dir, delta)
	var starting := not pushing
	_set_pushing(true)
	velocity.x = 0.0
	target_speed = 0.0
	# Follow the face only when the crate slid (or once, on contact); a blocked crate leaves the
	# body free, like the tall wall: letting go or reversing releases it the same frame.
	if moved or starting:
		global_position.x = crate.global_position.x + crate.push_contact_offset(dir, _radius).x


func _capsule_fits(feet: Vector2, capsule: CapsuleShape2D = null) -> bool:
	var base := capsule if capsule else _stand_capsule
	var probe := CapsuleShape2D.new()
	probe.radius = base.radius - 2.0
	probe.height = base.height - 4.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe
	query.transform = Transform2D(0.0, feet + Vector2(0, -base.height * 0.5 - 2.0))
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _try_step(front: Dictionary, dir: int) -> bool:
	var h: float = front.height
	if h > step_max_height or h <= 0.5:
		return false
	_set_pushing(false)
	if h <= small_step_height:
		global_position.y = front.top - 0.5
		return false
	_step_from = global_position
	_step_to = Vector2(front.wall_x + dir * maxf(step_forward * 0.5, _radius + 4.0), front.top)
	_step_speed = velocity.x
	_step_t = 0.0
	_step_rig = rig.has_method(&"play_step_up") and rig.play_step_up(h)
	stepping = true
	_set_facing(dir)
	velocity = Vector2.ZERO
	_shape.set_deferred(&"disabled", true)
	return true


func _advance_step(motion: Vector2, delta: float) -> void:
	if _step_rig:
		global_position += motion
		return
	_step_t += delta
	var u := smoothstep(0.0, step_fallback_time, _step_t)
	global_position = Vector2(lerpf(_step_from.x, _step_to.x, u), lerpf(_step_from.y, _step_to.y, minf(1.0, u * 1.6)))
	if _step_t >= step_fallback_time:
		_finish_step()


func _finish_step() -> void:
	stepping = false
	var dir := int(signf(_step_to.x - _step_from.x))
	if (global_position.x - _step_to.x) * dir < 0.0:
		global_position.x = _step_to.x
	global_position.y = _step_to.y - 0.5
	velocity = Vector2(_step_speed, 0.0)
	_shape.set_deferred(&"disabled", false)


func _set_pushing(value: bool) -> void:
	if pushing == value:
		return
	pushing = value
	if value:
		_push_sfx = Feedback.sfx_loop(&"wall_slide", global_position)
		Feedback.sfx_loop_update(_push_sfx, 0.25)
		_push_haptic = Feedback.haptic_loop(&"wall_slide", 0.3)
	else:
		Feedback.sfx_stop(_push_sfx)
		Feedback.haptic_stop(_push_haptic)
		_push_sfx = -1
		_push_haptic = -1


# --- Wall slide / wall jump / wall kick ------------------------------------------------------

# A wall counts when it is vertical, reaches at least the head (top above the standing capsule)
# and goes down at least to mid body; with wall_grab_any off it must also be a climbable_wall.
func _is_grab_wall(body: Node) -> bool:
	if body == null or body.is_in_group(&"push_crate"):
		return false
	if not wall_grab_any and not body.is_in_group(&"climbable_wall"):
		return false
	var feet := global_position.y
	var top: float = body.get_meta(&"wall_top", -INF)
	var bottom: float = body.get_meta(&"wall_bottom", INF)
	return top <= feet - _stand_capsule.height and bottom >= feet - _stand_capsule.height * 0.5


func _grab_wall_contact(dir_hint: int) -> KinematicCollision2D:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.x) < 0.7:
			continue
		if dir_hint != 0 and int(-signf(n.x)) != dir_hint:
			continue
		if _is_grab_wall(c.get_collider() as Node):
			return c
	return null


# Test-only probe to a grabbable wall on one side, across the rig's contact gap.
func _wall_probe(dir: int) -> KinematicCollision2D:
	var reach := maxf(wall_contact_offset - _radius, 0.0) + 6.0
	var hit := move_and_collide(Vector2(dir * reach, 0.0), true)
	if hit == null or absf(hit.get_normal().x) < 0.7 or int(-signf(hit.get_normal().x)) != dir:
		return null
	return hit if _is_grab_wall(hit.get_collider() as Node) else null


# Side of a grabbable wall touching the body in the air (0 when none); also drives the F1 hint.
func _air_wall_side() -> int:
	for d in [facing, -facing]:
		if _wall_probe(d):
			return d
	return 0


func _try_wall_grab(vx_before: float) -> void:
	var c := _grab_wall_contact(0)
	if c == null:
		return
	var wd := int(-signf(c.get_normal().x))
	var pushing := int(signf(input_axis)) == wd or signf(vx_before) == wd
	if not pushing or (_wall_lock > 0.0 and wd == _wall_lock_dir):
		return
	rig.play_action(&"wall_grab")
	wall_sliding = true
	_update_climb_holster(0.0, false)
	wall_dir = wd
	_wall_release = 0.0
	_wall_flight = false
	_leap_flight = false
	_rising_jump = false
	_air_jumps = max_air_jumps
	_set_facing(wd)
	global_position.x = c.get_position().x - wd * maxf(wall_contact_offset, _radius + 0.5)
	velocity.x = 0.0
	_wall_sfx = Feedback.sfx_loop(&"wall_slide", global_position)
	_wall_haptic = Feedback.haptic_loop(&"wall_slide", 0.0)


func _wall_control(delta: float) -> void:
	if _jump_buffer > 0.0 and not _wall_takeoff_pending:
		_start_wall_jump(_wall_jump_kind())
		return
	if int(signf(input_axis)) == -wall_dir:
		_wall_release += delta
		if _wall_release >= wall_release_delay:
			_leave_wall(true)
			velocity.x = -wall_dir * 150.0
			return
	else:
		_wall_release = 0.0
	if velocity.y < 0.0:
		velocity.y = minf(0.0, velocity.y + wall_grab_upward_damp * delta)
	else:
		var fast := _axis(&"move_up", &"move_down") >= hang_stick_threshold
		var cap := wall_slide_fast_speed if fast else wall_slide_max_speed
		var g := gravity * (1.0 if fast else wall_slide_gravity_scale)
		velocity.y = move_toward(velocity.y, cap, (g if velocity.y < cap else wall_grab_upward_damp) * delta)
	# The body holds at the rig's contact offset, which may leave a gap to the wall.
	velocity.x = 0.0
	var strength := clampf(maxf(velocity.y, 0.0) / wall_slide_max_speed, 0.0, 1.0)
	Feedback.sfx_loop_update(_wall_sfx, strength, global_position)
	Feedback.haptic_loop_strength(_wall_haptic, strength)


# Stick away from the wall: long wall_jump; towards it or neutral: short wall_kick upwards.
func _wall_jump_kind() -> StringName:
	return &"wall_jump" if int(signf(input_axis)) == -wall_dir else &"wall_kick"


func _wall_after_move() -> void:
	if is_on_floor() or _wall_probe(wall_dir) == null:
		_leave_wall(true)


func _leave_wall(with_coyote: bool) -> void:
	if not wall_sliding:
		return
	wall_sliding = false
	if with_coyote:
		_wall_coyote = wall_coyote_time
	Feedback.sfx_stop(_wall_sfx)
	Feedback.haptic_stop(_wall_haptic)
	_wall_sfx = -1
	_wall_haptic = -1
	if rig.has_method(&"set_wall_slide"):
		rig.set_wall_slide(false, 0.0)


func _start_wall_jump(kind: StringName) -> void:
	_jump_buffer = 0.0
	_wall_coyote = 0.0
	_wall_takeoff_pending = true
	_wall_takeoff_kind = kind
	_takeoff_wait = 0.0
	if not rig.play_action(kind):
		_wall_takeoff()


func _wall_takeoff() -> void:
	if not _wall_takeoff_pending:
		return
	_wall_takeoff_pending = false
	_leave_wall(false)
	if _wall_takeoff_kind == &"wall_kick":
		# Short hop off the wall, still facing it: holding towards the wall brings the body back
		# higher up within ~0.2 s.
		velocity = Vector2(-wall_dir * wall_kick_x, -wall_kick_y)
		_wall_lock = wall_kick_input_lock
	else:
		_set_facing(-wall_dir)
		velocity = Vector2(-wall_dir * wall_jump_x, -wall_jump_y)
		_wall_lock = wall_jump_input_lock
	_wall_lock_dir = wall_dir
	_wall_flight = true
	_rising_jump = false
	wall_kick_count += 1 if _wall_takeoff_kind == &"wall_kick" else 0


# --- Double jump -------------------------------------------------------------------------------

func _start_double_jump() -> void:
	_jump_buffer = 0.0
	_air_jumps -= 1
	# Turn first: the rig holds facing changes while an action plays, and its flip must spin
	# towards the chosen side.
	if absf(input_axis) >= double_jump_neutral_tilt:
		_set_facing(int(signf(input_axis)))
	_double_pending = true
	_takeoff_wait = 0.0
	if not rig.play_action(&"double_jump"):
		_double_takeoff()


func _double_takeoff() -> void:
	if not _double_pending:
		return
	_double_pending = false
	# The left stick at takeoff decides: back reverses, forward pushes, up adds height, neutral
	# goes straight up.
	var up := clampf(-_axis(&"move_up", &"move_down"), 0.0, 1.0)
	var boost := jump_speed * double_jump_ratio * (1.0 + double_jump_up_bonus * up)
	velocity.y = -maxf(boost, -velocity.y + double_jump_min_add)
	var tilt := absf(input_axis)
	if tilt < double_jump_neutral_tilt:
		velocity.x *= double_jump_neutral_keep
		_dj_hold = 0.0
	else:
		var dir := int(signf(input_axis))
		_set_facing(dir)
		velocity.x = dir * double_jump_x_boost * clampf(tilt / double_jump_full_tilt, 0.0, 1.0)
		_dj_hold = double_jump_air_hold
		# Dust thrown back against the launch.
		if rig.has_method(&"spawn_fx_local"):
			rig.spawn_fx_local("dust", DOUBLE_JUMP_TRAIL, Vector2(0, -30), false)
	# The air is pushed opposite to the launch (straight down for a neutral jump).
	FogHooks.push(global_position, Vector2(-velocity.x * 0.6, 900), 140.0, 0.8)
	# A fixed-height double jump: releasing A does not cut it (a quick tap must still lift clearly).
	_rising_jump = false
	_wall_flight = false


# --- Hero landing ------------------------------------------------------------------------------

# Touchdown after a long fall: the three-point slam, with juice scaled by the fall speed. A
# buffered jump, a crouch under a low ceiling or a busy rig keep the plain landing.
func _start_hero_landing(drop_vy: float) -> void:
	if not current_action.is_empty() or _takeoff_pending or hurting or stepping or _rig_busy():
		return
	if crouching and not can_stand():
		return
	_set_crouch(false)
	if not _start_action(&"hero_landing", facing):
		return
	_hero_t = 0.0
	var k := clampf(inverse_lerp(hero_landing_vy, max_fall_speed, drop_vy), 0.0, 1.0)
	camera_shake(hero_shake * lerpf(0.6, 1.0, k), hero_shake_time)
	_hero_hitstop = hero_hitstop * lerpf(0.5, 1.0, k)
	Feedback.sfx(&"land", global_position, 1.0, surface)
	Feedback.haptic(&"land", 1.0)
	FogHooks.burst(global_position, lerpf(260.0, 360.0, k), lerpf(1.2, 1.8, k))


func _hero_control(delta: float, on_floor: bool) -> void:
	_hero_t += delta
	velocity.x = move_toward(velocity.x, 0.0, hero_friction * delta)
	# Slid off an edge: the pose has no air version.
	if not on_floor:
		rig.stop_action()
		return
	if _hero_t >= hero_cancel_after and (absf(input_axis) >= 0.3 or _jump_buffer > 0.0):
		rig.stop_action()


# Starts a combat action on the rig and locks movement while it plays (punches, flying kick).
func start_combat_action(id: StringName) -> bool:
	if not rig.play_action(id):
		return false
	current_action = id
	_pending_facing = facing
	_action_done = &""
	return true


# Fog: the body always stirs it; rolls sweep a lane, the flying kick pushes along the foot.
func _fog_frame() -> void:
	var sole := global_position
	FogHooks.set_body(1, sole + Vector2(0, -70), velocity, 80.0)
	FogHooks.set_body(2, sole + Vector2(0, -250), velocity, 110.0)
	if current_action in [&"roll", &"roll_back"]:
		FogHooks.sweep(_prev_sole + Vector2(0, -50), sole + Vector2(0, -50), 130.0, 1.1)
	elif current_action == &"flying_kick":
		var foot := sole
		if rig.has_method(&"get_kick_contact"):
			var c: Dictionary = rig.get_kick_contact()
			if c.has("point"):
				foot = c.point
		FogHooks.push(foot, velocity, 160.0, 0.8)
	_prev_sole = sole


# Stops every loop the player owns (skid, wall slide, push, aim, underwater) and the hitstop.
func release_feedback() -> void:
	_stop_skid_loop()
	_leave_wall(false)
	_set_pushing(false)
	_hitstop_until_ms = 0
	if combat:
		if combat.bow.aiming:
			combat.bow._cancel()
		combat.guns.end()
	if swim:
		swim.release_feedback()


func set_facing(dir: int) -> void:
	_set_facing(1 if dir >= 0 else -1)


# Global damage box of the body (shrinks while crouched; standing size while swimming).
func get_hurt_rect() -> Rect2:
	var capsule := _shape.shape as CapsuleShape2D
	if _swim_shape_on:
		# Lying in the water: a standing-size box around the swim centre (the origin may sink
		# below the body there).
		var c := global_position + _swim_center
		return Rect2(c - Vector2(_radius, _stand_capsule.height * 0.5), Vector2(_radius * 2.0, _stand_capsule.height))
	return Rect2(global_position - Vector2(capsule.radius, capsule.height), Vector2(capsule.radius * 2.0, capsule.height))


# Short shove from debris and similar (never pins the body): adds to the velocity, capped.
func apply_push(push: Vector2) -> void:
	if hanging or stepping or is_controlled():
		return
	velocity.x += clampf(push.x, -push_max, push_max)
	if push.y < 0.0:
		velocity.y = minf(velocity.y, maxf(push.y, -push_max))


func just_pressed(action: StringName) -> bool:
	return _just(action)


func held(action: StringName) -> bool:
	return _held(action)


func axis(negative: StringName, positive: StringName) -> float:
	return _axis(negative, positive)


# Entering the water: drop wall, crouch, push, aim and pending jumps.
func prepare_for_swim() -> void:
	# The flying kick only ends on landing or contact: the water counts as its landing.
	if current_action == &"flying_kick":
		rig.stop_action()
	_leave_wall(false)
	_set_crouch(false)
	_set_pushing(false)
	current_action = &""
	_action_done = &""
	_takeoff_pending = false
	_wall_takeoff_pending = false
	_double_pending = false
	_rising_jump = false
	if combat.bow.aiming:
		combat.bow._cancel()


# Leaving the water with A: a fixed-height jump that can reach the bank's ledge.
func set_collision_enabled(on: bool) -> void:
	_shape.set_deferred(&"disabled", not on)


func exit_water_jump() -> void:
	_rising_jump = false
	_coyote = 0.0
	_jump_buffer = 0.0
	_air_jumps = max_air_jumps
	# The bank wall is right there: no wall grab or wall jump off it while climbing out.
	_wall_lock = 0.4
	_wall_lock_dir = facing


# --- Public API for interactables, targets, hazards and weapons ---------------------------------

func can_interact_now() -> bool:
	return is_on_floor() and current_action.is_empty() and not _rig_busy() and not wall_sliding \
		and not hanging and not stepping and not hurting and not (crouching and not can_stand())


const CLIMB_ACTIONS: Array[StringName] = [&"ledge_grab", &"ledge_climb", &"ledge_descend", &"ledge_leap", &"wall_grab", &"wall_kick", &"wall_jump"]


# Hanging, on a ledge move or on a wall: the weapon stays in the holster.
func _in_climb() -> bool:
	return hanging or wall_sliding or current_action in CLIMB_ACTIONS


# Back on the floor the weapon returns at once; in the air only after a short stretch without a
# wall, so the AK does not flash between kicks up a column.
func _update_climb_holster(delta: float, on_floor: bool) -> void:
	if _in_climb():
		_climb_air_left = climb_holster_air_grace
		combat.set_holstered(true, &"climb")
		return
	_climb_air_left -= delta
	if on_floor or _climb_air_left <= 0.0:
		combat.set_holstered(false, &"climb")


func _rig_busy() -> bool:
	return rig.has_method(&"is_action_playing") and rig.is_action_playing()


# While any owner holds control the player ignores movement, jump, attack and B input; the owner
# may set position, facing and play rig actions. Gravity stays on unless controlled_gravity is off.
func take_control(owner: Node) -> void:
	if owner not in _controllers:
		_controllers.append(owner)
	_set_pushing(false)
	combat.set_holstered(true)


func release_control(owner: Node) -> void:
	_controllers.erase(owner)
	if not is_controlled():
		controlled_gravity = true
		combat.set_holstered(false)


func is_controlled() -> bool:
	_controllers = _controllers.filter(func(n): return is_instance_valid(n))
	return not _controllers.is_empty()


# kind: &"hit", &"shot" or &"drown" (no knockback). Returns false (and does nothing) while invulnerable.
func hurt(kind: StringName, from_global: Vector2, strength: float = 1.0) -> bool:
	if invulnerable or _mercy_left > 0.0:
		return false
	_cancel_for_hurt()
	var reaction := &"shot_hit" if kind == &"shot" else &"hurt"
	_hurt_rig = rig.play_action(reaction)
	if not _hurt_rig and _rig_busy():
		# The rig refused the reaction: end its action anyway so the pose does not outlive the hit.
		rig.stop_action()
		_hurt_rig = rig.play_action(reaction)
	_hurt_released = false
	if not _hurt_rig:
		_flash()
	_mercy_left = hurt_mercy_time
	if kind == &"drown":
		# Drowning: damage without knockback, the body keeps swimming.
		Feedback.sfx(&"drown_hit", global_position, strength)
		Feedback.haptic(&"drown_hit", strength)
		camera_shake(hurt_shake * 0.3, 0.2)
		return true
	var away := signf(global_position.x - from_global.x)
	if away == 0.0:
		away = -facing
	velocity = Vector2(away * knockback_x * strength, -knockback_y * strength)
	hurting = true
	_hurt_left = hurt_stun_time
	_hurt_total = 0.0
	if kind == &"shot":
		Feedback.sfx(&"bullet_hit_body", global_position, strength)
		Feedback.sfx(&"blood_splat", global_position, strength)
		Feedback.haptic(&"bullet_hit_body", strength)
	else:
		Feedback.sfx(&"hurt_hit", global_position, strength)
		Feedback.haptic(&"hurt_hit", strength)
	camera_shake(hurt_shake * strength, hurt_shake_time)
	hitstop(hurt_hitstop)
	return true


# Projectile hit (arrow): the shot reaction from the incoming side, scaled by damage.
func take_hit(point: Vector2, direction: Vector2, damage: float, _kind: StringName) -> void:
	if rig.has_method(&"set_hit_direction"):
		rig.set_hit_direction(direction)
	hurt(&"shot", point - direction * 200.0, clampf(damage / arrow_hurt_reference, 0.5, 1.0))


# Sticks a projectile in the body at point; false when it cannot (it then falls or bounces).
func attach_projectile(projectile: Node2D, point: Vector2) -> bool:
	var angle = projectile.get(&"_angle")
	return stuck.attach(projectile, point, float(angle) if angle != null else 0.0)


# Dodge and roll i-frames let projectiles fly through the body.
func lets_projectiles_through() -> bool:
	return invulnerable


# Held look: still on the floor, down (crouched) or up (standing) past look_stick_threshold for
# look_hold_time sets look_dir; anything else resets it.
func _update_look(delta: float, on_floor: bool) -> void:
	var rig_idle: bool = not rig.has_method(&"current_action") or rig.current_action().is_empty()
	var still: bool = on_floor and not _blocked and current_action.is_empty() and rig_idle \
		and not hanging and not wall_sliding and not stepping and not hurting and not pushing \
		and not swim.active() and not combat.blocks_movement() \
		and not combat.guns.aiming and not combat.bow.aiming \
		and is_zero_approx(input_axis) and absf(velocity.x) < 5.0
	var want := 0
	if still:
		var v := _vertical_intent()
		if crouching and v > 0:
			want = 1
		elif not crouching and v < 0:
			want = -1
	if want != _look_want:
		_look_want = want
		_look_hold = 0.0
	elif want != 0:
		_look_hold += delta
	look_dir = want if want != 0 and _look_hold >= look_hold_time else 0
	var lead := RigMath.smooth01((_look_hold - look_lead_time) / maxf(look_hold_time - look_lead_time, 0.01))
	look_amount = want * lead if want != 0 else 0.0
	if rig.has_method(&"set_look"):
		rig.set_look(want if lead > 0.0 else 0, delta, lead)


# 1 down, -1 up, 0 none: the left stick past look_stick_threshold within look_cone_degrees of
# vertical, while still on the floor and not aiming, hanging, swimming or under control.
func _vertical_intent() -> int:
	if _blocked or hanging or wall_sliding or swim.active() or combat.aim_down or absf(velocity.x) >= 5.0:
		return 0
	var x := Input.get_action_raw_strength(&"move_right") - Input.get_action_raw_strength(&"move_left")
	var y := Input.get_action_raw_strength(&"move_down") - Input.get_action_raw_strength(&"move_up")
	if Vector2(x, y).length() < look_stick_threshold or absf(x) > absf(y) * tan(deg_to_rad(look_cone_degrees)):
		return 0
	return int(signf(y))


func camera_shake(amount: float, duration: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method(&"add_shake"):
		cam.add_shake(amount, duration)


# Near-freezes the game for a few real-time seconds (overlapping calls extend it). Not a full
# stop: time_scale 0 would hand every physics script a zero delta.
@export var hitstop_time_scale := 0.02


func hitstop(seconds: float) -> void:
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = hitstop_time_scale


func _process(_delta: float) -> void:
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0


func _cancel_for_hurt() -> void:
	if hanging:
		_leave_hang()
	_leave_wall(false)
	if stepping:
		_finish_step()
	_set_pushing(false)
	_stop_skid_loop()
	current_action = &""
	_action_done = &""
	_takeoff_pending = false
	_wall_takeoff_pending = false
	_double_pending = false
	_rising_jump = false
	_set_crouch(false) if can_stand() else null


func _flash() -> void:
	var tween := create_tween()
	rig.modulate = Color(4, 4, 4)
	tween.tween_property(rig, ^"modulate", Color.WHITE, 0.25)


# --- Rig events -------------------------------------------------------------------------------

func _on_action_event(id: StringName, event_name: StringName) -> void:
	if event_name == &"can_move" and id in [&"hurt", &"shot_hit"]:
		_hurt_released = true
	match event_name:
		&"flip":
			if id == &"skid_turn":
				facing = _pending_facing
			elif id == &"ledge_leap":
				facing = -facing
		&"takeoff":
			var strength := 0.8 if id == &"double_jump" else 1.0
			Feedback.sfx(&"jump", global_position, strength, surface)
			Feedback.haptic(&"jump", strength)
			if id in [&"wall_jump", &"wall_kick", &"double_jump"]:
				Feedback.sfx(&"whoosh_small", global_position)
			if id == &"double_jump":
				FogHooks.burst(global_position, 150.0, 0.6)
			elif id == &"jump":
				FogHooks.burst(global_position, 110.0, 0.45)
			if id == &"ledge_leap":
				_leap_takeoff()
			elif id == &"wall_jump" or id == &"wall_kick":
				_wall_takeoff()
			elif id == &"double_jump":
				_double_takeoff()
			elif _takeoff_pending:
				_takeoff()
		&"iframes_start":
			if id == current_action and (_evade_iframes or not (id in EVADE_ACTIONS)):
				invulnerable = true
				_since_iframes = 0.0
		&"iframes_end":
			if id == current_action:
				invulnerable = false
		&"skid_start":
			_stop_skid_loop()
			_skid_sfx = Feedback.sfx_loop(&"skid", global_position)
			_skid_haptic = Feedback.haptic_loop(&"skid")
		&"skid_stop":
			_stop_skid_loop()
		&"roll_contact":
			Feedback.sfx(&"roll", global_position, 1.0, surface)
			Feedback.haptic(&"roll")
		&"whoosh":
			Feedback.sfx(&"whoosh_small", global_position)
			Feedback.haptic(&"roll", 0.5)
		&"grip":
			Feedback.sfx(&"ledge_grab", _hand_point())
			Feedback.haptic(&"ledge_grab", 0.7 if id == &"wall_grab" else 1.0)
		&"pull":
			Feedback.sfx(&"climb", global_position)


func _on_action_finished(id: StringName) -> void:
	if id in [&"roll", &"roll_back"]:
		FogHooks.burst(global_position, 170.0, 0.8)
	if id in [&"hurt", &"shot_hit"]:
		_hurt_released = true
	if id == &"step_up" and stepping and _step_rig:
		_finish_step()
		return
	_action_done = id
	if id == &"jump" and _takeoff_pending:
		_takeoff()


func _on_footstep(_foot: Variant, strength: float) -> void:
	if state == State.SPRINT:
		FogHooks.burst(global_position, 90.0, 0.35)
	else:
		FogHooks.burst(global_position, 70.0, 0.22)
	Feedback.sfx(&"footstep", global_position, strength, surface)
	Feedback.haptic(&"footstep", strength)


func _on_landed(strength: float) -> void:
	FogHooks.burst(global_position, 230.0, clampf(_fall_vy / 1300.0, 0.3, 1.4))
	_fall_vy = 0.0
	Feedback.sfx(&"land", global_position, strength, surface)
	Feedback.haptic(&"land", strength)


func _stop_skid_loop() -> void:
	Feedback.sfx_stop(_skid_sfx)
	Feedback.haptic_stop(_skid_haptic)
	_skid_sfx = -1
	_skid_haptic = -1


func _read_surface() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_normal().y < -0.7:
			var collider := c.get_collider() as Object
			if collider and collider.has_meta(&"surface"):
				surface = collider.get_meta(&"surface")
			return


# --- State ------------------------------------------------------------------------------------

func _update_state() -> void:
	var next: State
	var speed := absf(velocity.x)
	if swim.active():
		next = State.DIVE if swim.mode_name() == &"dive" else State.SWIM
	elif hurting:
		next = State.HURT
	elif stepping:
		next = State.STEP
	elif hanging:
		if climbing:
			next = State.CLIMB
		elif descending:
			next = State.DESCEND
		elif leaping:
			next = State.LEAP
		else:
			next = State.HANG
	elif wall_sliding:
		next = State.WALL_SLIDE
	elif current_action == &"skid_turn":
		next = State.SKID
	elif current_action in [&"roll", &"roll_back"]:
		next = State.ROLL
	elif current_action == &"dodge":
		next = State.DODGE
	elif not is_on_floor():
		next = State.JUMP if velocity.y < 0.0 else State.FALL
	elif crouching:
		next = State.CRAWL if speed >= 5.0 else State.CROUCH
	elif pushing:
		next = State.PUSH
	elif speed < 5.0:
		next = State.IDLE
	elif speed <= walk_speed + 1.0:
		next = State.WALK
	elif speed <= run_speed + 1.0:
		next = State.RUN
	else:
		next = State.SPRINT
	if next != state:
		state = next
		state_changed.emit(state_name())


func state_name() -> StringName:
	return StringName(State.keys()[state].to_lower())


func rig_action() -> StringName:
	if not current_action.is_empty():
		return current_action
	if climbing:
		return &"ledge_climb"
	if descending:
		return &"ledge_descend"
	if leaping:
		return &"ledge_leap"
	if _wall_takeoff_pending:
		return _wall_takeoff_kind
	if _double_pending:
		return &"double_jump"
	return &"jump" if _takeoff_pending else &""
