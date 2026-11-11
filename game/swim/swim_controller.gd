extends Node

# Swimming for the player against the WaterBody API (real or res://game/water_stub). While active
# it owns the body's velocity: buoyancy and drag, surface swimming, diving, 8-way movement
# underwater, oxygen with drowning damage, strokes, bubbles, splashes and the muffled underwater mix.

const Feedback := preload("res://game/feedback.gd")
const OxygenBar := preload("res://game/swim/oxygen_bar.gd")
const FogHooks := preload("res://game/fog_hooks.gd")

enum Mode { NONE, SURFACE, UNDER, EXIT }

# Enter when this much of the body is submerged; leave below exit_ratio.
@export var enter_ratio := 0.45
@export var exit_ratio := 0.2
# Feet below the surface while floating, as a fraction of the standing height (head out).
@export var float_depth := 0.66
@export var surface_speed := 380.0
@export var under_speed := 340.0
@export var accel := 1400.0
@export var drag := 3.0
@export var buoyancy_spring := 18.0
@export var buoyancy_damping := 6.0
# Net upward drift underwater with no input.
@export var under_float := 60.0
@export var dive_speed := 320.0
# A at the surface: next to a bank (within bank_reach) a jump that clears its edge and lands on
# it; in open water a small hop.
@export var exit_jump_speed := 1500.0
@export var hop_speed := 650.0
@export var bank_reach := 90.0
# Floating crates are found this far beyond their half width (they drift as the body nears).
@export var crate_reach := 200.0
@export var exit_push := 320.0
# Falling in faster than this goes straight under.
@export var dive_entry_speed := 1500.0
@export var reenter_delay := 0.35
@export var oxygen_time := 10.0
@export var oxygen_refill_rate := 3.0
@export_range(0.0, 1.0) var oxygen_warning_ratio := 0.3
@export var drown_interval := 1.0
@export var stroke_fallback_time := 0.55
@export var trail_interval := 0.22

var player
var water: Node
var mode := Mode.NONE
var oxygen := 1.0
var head_under := false
var _cooldown := 0.0
var _drown_t := 0.0
var _warn_t := 0.0
var _stroke_t := 0.0
var _trail_t := 0.0
var _underwater_loop := -1
var _bar: Node2D


func setup(owner_player) -> void:
	player = owner_player
	_bar = OxygenBar.new()
	_bar.position = Vector2(0, -player.get_hurt_rect().size.y - 90.0)
	_bar.visible = false
	player.add_child(_bar)
	if player.rig.has_signal(&"swim_stroke"):
		player.rig.swim_stroke.connect(_on_stroke)
	if player.rig.has_signal(&"action_finished"):
		player.rig.action_finished.connect(_on_action_finished)


func active() -> bool:
	return mode != Mode.NONE


func mode_name() -> StringName:
	match mode:
		Mode.SURFACE:
			return &"swim"
		Mode.UNDER:
			return &"dive"
	return &""


func _find_water(point: Vector2) -> Node:
	for w in player.get_tree().get_nodes_in_group(&"water"):
		if w.has_method(&"is_point_in_water") and (not w.has_method(&"is_ready") or w.is_ready()):
			if w.is_point_in_water(point):
				return w
	return null


# Enter or leave the water. Returns true while swimming.
func update(delta: float) -> bool:
	_cooldown = maxf(0.0, _cooldown - delta)
	var rect: Rect2 = player.get_hurt_rect()
	var center := rect.get_center()
	var w := _find_water(center) if water == null else water
	var ratio := 0.0
	if w:
		ratio = w.get_submerged_ratio(rect)
	if mode == Mode.NONE:
		if w and ratio >= enter_ratio and _cooldown <= 0.0:
			_enter(w)
	elif mode != Mode.EXIT and (ratio < exit_ratio or w == null or not w.is_point_in_water(center)):
		_leave()
	_update_oxygen(delta)
	return active()


func _enter(w: Node) -> void:
	water = w
	var impact: float = maxf(player.velocity.y, 0.0)
	mode = Mode.UNDER if impact > dive_entry_speed else Mode.SURFACE
	player.prepare_for_swim()
	# The water body plays the entry splash itself (auto_bodies); only the rumble and the fog are ours.
	_fog_splash(w)
	Feedback.haptic(&"splash", clampf(impact / 1600.0, 0.15, 1.0))
	player.velocity *= 0.35


func _fog_splash(w: Node) -> void:
	var y: float = w.get_surface_y(player.global_position.x, player.global_position.y)
	if y != INF:
		var p := Vector2(player.global_position.x, y)
		FogHooks.add_density(p, 120.0, 0.5)
		FogHooks.burst(p, 100.0, 0.4)


func _leave() -> void:
	if water:
		_fog_splash(water)
	player.set_swim_shape(false)
	mode = Mode.NONE
	water = null
	_cooldown = reenter_delay
	_set_head_under(false)
	_bar.visible = false



# Velocity while swimming; the player moves the body afterwards.
func control(delta: float) -> void:
	var x: float = player.axis(&"move_left", &"move_right")
	var y: float = player.axis(&"move_up", &"move_down")
	var dir := int(signf(x))
	if dir != 0:
		player.set_facing(dir)
	var surface_y: float = water.get_surface_y(player.global_position.x, player.global_position.y)
	if surface_y == INF:
		surface_y = player.global_position.y - 400.0
	var height: float = player.get_hurt_rect().size.y
	var float_y := surface_y + height * float_depth
	var v: Vector2 = player.velocity
	v += water.get_flow_at(player.global_position) * delta
	if mode == Mode.SURFACE:
		# Dive with down or B; jump out with A (towards a bank it clears the edge or reaches a ledge).
		if y >= 0.5 or player.just_pressed(&"roll"):
			mode = Mode.UNDER
			v.y = dive_speed
		elif player.just_pressed(&"jump"):
			# A floating crate drifts as the body nears it: look for one a bit further out first.
			var crate := _crate_near()
			if crate and _start_water_exit(int(signf(crate.global_position.x - player.global_position.x)), crate):
				return
			var bank := _bank_side()
			if bank != 0 and _start_water_exit(bank):
				return
			if bank == 0:
				v.y = -hop_speed
			else:
				player.set_facing(bank)
				v = Vector2(bank * exit_push, -exit_jump_speed)
				player.velocity = v
				_leave()
				player.exit_water_jump()
				return
		else:
			v.x = move_toward(v.x, x * surface_speed, accel * delta)
			v.y += ((float_y - player.global_position.y) * buoyancy_spring - v.y * buoyancy_damping) * delta
	if mode == Mode.UNDER:
		var target := Vector2(x, y)
		if player.held(&"jump"):
			target.y = -1.0
		target = target.limit_length(1.0) * under_speed
		if absf(y) < 0.2 and not player.held(&"jump"):
			target.y = -under_float
		v = v.move_toward(target, accel * delta)
		v -= v * minf(1.0, drag * delta) * 0.3
		# Back at the surface: float again.
		if player.global_position.y <= float_y and v.y <= 0.0:
			mode = Mode.SURFACE
	player.velocity = v
	_effects(delta, absf(x) + absf(y) > 0.1)
	var rig_mode := _rig_mode(absf(x) + absf(y) > 0.1)
	# Lying body (surface / under) collides as a capsule along the motion; upright only treading.
	player.set_swim_shape(rig_mode != &"tread", v)
	if player.rig.has_method(&"set_swim"):
		player.rig.set_swim(rig_mode, v, delta)


# Side of a bank wall right next to the body (0 when none).
# Rig water_exit: lunge to the bank corner and climb onto it. The corner (relative to the origin,
# facing 1) goes in action_params; the body then follows the root motion with collision off.
var _exit_corner := Vector2.ZERO
var _exit_done := false


func exiting() -> bool:
	return mode == Mode.EXIT


# A push crate floating within reach of the body (centre to centre, along x), else null.
func _crate_near() -> Node:
	for c in player.get_tree().get_nodes_in_group(&"push_crate"):
		var half: float = float(c.get(&"half")) if c.get(&"half") != null else 66.0
		var d: Vector2 = (c as Node2D).global_position - player.global_position
		if absf(d.x) <= half + crate_reach and d.y > -900.0 and d.y < 0.0:
			return c
	return null


func _start_water_exit(bank: int, crate: Node = null) -> bool:
	var rig = player.rig
	if not rig.has_method(&"play_action") or not "action_params" in rig:
		return false
	var corner: Vector2
	if crate:
		var half: float = float(crate.get(&"half")) if crate.get(&"half") != null else 66.0
		var c: Vector2 = (crate as Node2D).global_position
		corner = Vector2(c.x - bank * half, c.y - half)
	else:
		var hit: KinematicCollision2D = player.move_and_collide(Vector2(bank * bank_reach, 0.0), true)
		if hit == null:
			return false
		var wall_x := hit.get_position().x
		var probe_x := wall_x + bank * 8.0
		var from := Vector2(probe_x, player.global_position.y - 900.0)
		var ray := PhysicsRayQueryParameters2D.create(from, Vector2(probe_x, player.global_position.y + 50.0), 1, [player.get_rid()])
		var top: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(ray)
		if top.is_empty():
			return false
		corner = Vector2(wall_x, float(top.position.y))
	player.set_facing(bank)
	var rel: Vector2 = corner - player.global_position
	rel.x *= bank
	rig.action_params[&"water_exit_corner"] = rel
	if not rig.play_action(&"water_exit"):
		return false
	_exit_corner = corner
	_exit_done = false
	mode = Mode.EXIT
	player.velocity = Vector2.ZERO
	player.set_swim_shape(false)
	player.set_collision_enabled(false)
	_set_head_under(false)
	return true


# While exiting: follow the rig's root motion; returns true while the exit lasts.
func exit_step(motion: Vector2) -> bool:
	player.global_position += motion
	if not _exit_done:
		return true
	var top_offset: Vector2 = player.ledge_top_offset
	player.global_position = _exit_corner + Vector2(top_offset.x * player.facing, top_offset.y)
	player.set_collision_enabled(true)
	mode = Mode.NONE
	water = null
	_cooldown = reenter_delay
	_bar.visible = false
	return false


func _on_action_finished(id: StringName) -> void:
	if id == &"water_exit":
		_exit_done = true


func _bank_side() -> int:
	for d in [player.facing, -player.facing]:
		var hit: KinematicCollision2D = player.move_and_collide(Vector2(d * bank_reach, 0.0), true)
		if hit and absf(hit.get_normal().x) > 0.7:
			return d
	return 0


func _rig_mode(moving: bool) -> StringName:
	if mode == Mode.UNDER:
		return &"under" if moving else &"under_idle"
	return &"surface" if moving else &"tread"


func after_move() -> void:
	if not active():
		return
	var head: Vector2 = player.get_hurt_rect().position + Vector2(player.get_hurt_rect().size.x * 0.5, 30.0)
	_set_head_under(water.is_point_in_water(head))


func _effects(delta: float, moving: bool) -> void:
	if not player.rig.has_signal(&"swim_stroke") and moving:
		_stroke_t -= delta
		if _stroke_t <= 0.0:
			_stroke_t = stroke_fallback_time
			_on_stroke(0.7)
	if mode == Mode.UNDER and moving:
		_trail_t -= delta
		if _trail_t <= 0.0:
			_trail_t = trail_interval
			water.emit_bubbles(player.global_position + Vector2(0, -200), 1, player.velocity)
	if mode == Mode.SURFACE and moving:
		water.apply_disturbance(player.global_position, player.velocity * 0.3)


func _on_stroke(strength: float) -> void:
	if not active():
		return
	var head: Vector2 = player.global_position + Vector2(player.facing * 30.0, -player.get_hurt_rect().size.y + 40.0)
	if mode == Mode.UNDER:
		water.emit_bubbles(head, 3, player.velocity)
		Feedback.sfx(&"swim_under", player.global_position, strength)
		Feedback.sfx(&"bubble", head, 0.5)
	else:
		water.apply_disturbance(player.global_position, Vector2(0, 600.0 * strength))
		Feedback.sfx(&"swim_stroke", player.global_position, strength)
	Feedback.haptic(&"swim_stroke", strength)


func release_feedback() -> void:
	_set_head_under(false)


func _set_head_under(value: bool) -> void:
	if head_under == value:
		return
	head_under = value
	var sfx := Feedback._node("Sfx")
	if sfx and sfx.has_method(&"set_underwater"):
		sfx.set_underwater(value)
	if value:
		_underwater_loop = Feedback.sfx_loop(&"underwater")
	else:
		Feedback.sfx_stop(_underwater_loop, 0.3)
		_underwater_loop = -1


func _update_oxygen(delta: float) -> void:
	if head_under:
		oxygen = maxf(0.0, oxygen - delta / oxygen_time)
	else:
		oxygen = minf(1.0, oxygen + delta * oxygen_refill_rate / oxygen_time)
	var low := oxygen < oxygen_warning_ratio
	_bar.set_state(oxygen, low, head_under or (active() and oxygen < 1.0))
	if head_under and low and oxygen > 0.0:
		_warn_t -= delta
		if _warn_t <= 0.0:
			_warn_t = 1.0
			Feedback.sfx(&"oxygen_warning", player.global_position)
	if head_under and oxygen <= 0.0:
		_drown_t -= delta
		if _drown_t <= 0.0:
			_drown_t = drown_interval
			player.hurt(&"drown", player.global_position, 0.6)
	else:
		_drown_t = 0.0
