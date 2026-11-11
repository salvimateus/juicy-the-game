extends RefCounted

# Bow: hold aim (LT / right mouse / L) to draw; the right stick (or the mouse) points the shot and
# its deflection sets the power (smoothed); a centred stick keeps the angle and lets the power
# ease down to the minimum. fire (RT / left mouse / J) shoots on the rig's `release` event, never
# weaker than bow_min_power; letting aim go without firing cancels. The left stick turns the
# character. The dotted path uses the arrow's own physics.

const Feedback := preload("res://game/feedback.gd")
const Dots := preload("res://game/combat/trajectory_dots.gd")
const Aim := preload("res://game/combat/aim.gd")
const ARROW_SCRIPT_PATH := "res://game/targets/arrow.gd"

var min_speed := 900.0
var max_speed := 2600.0
var bow_min_power := 0.15
var power_smoothing_time := 0.05
var power_release_rate := 1.5
# Rig limits of the aim angle (radians from facing-forward; negative is up).
var angle_up := deg_to_rad(-80.0)
var angle_down := deg_to_rad(45.0)
var arrow_gravity := 1500.0
var dot_count := 16
var dot_dt := 0.05

var player
var aiming := false
var releasing := false
var angle := 0.0
var power := 0.5
var aim
var shots := 0
var _dots: Node2D
var _sfx := -1
var _haptic := -1
var _pending_shot := {}
var _fire_buffered := false
var _release_wait := 0.0


func _init(owner_player) -> void:
	player = owner_player
	aim = Aim.new(owner_player)
	var arrow_script := load(ARROW_SCRIPT_PATH) as Script if ResourceLoader.exists(ARROW_SCRIPT_PATH) else null
	if arrow_script:
		var defaults: Variant = arrow_script.get_property_default_value(&"gravity")
		if defaults != null:
			arrow_gravity = float(defaults)


# Movement is held while drawing, aiming and releasing.
func blocks_movement() -> bool:
	return aiming or releasing


func step(delta: float, can_act: bool) -> void:
	var aim_held: bool = can_act and player.combat.aim_down
	# RT with LT held is kept while the previous shot is still leaving the string.
	if aim_held and player.just_pressed(&"fire"):
		_fire_buffered = true
	if not aim_held:
		_fire_buffered = false
	if not aiming and not releasing:
		if aim_held and player.is_on_floor():
			_begin()
		return
	if releasing:
		_release_wait += delta
		if _release_wait < 1.5:
			return
		releasing = false
	if not aim_held:
		_cancel()
		return
	# Every frame: the rig must be in the bow's aim; enter again if it fell out (a landing, a
	# reaction...), or step out of the aim on the game side and retry next frame.
	if not player.combat.rig_in_aim_loop(&"bow") and not _play(&"bow_draw"):
		_suspend()
		return
	_update_aim(delta)
	if _fire_buffered:
		_fire_buffered = false
		_fire()


func _begin() -> void:
	# The aim starts only once the rig takes the draw (it may be busy finishing something).
	if player.rig.has_method(&"play_action") and not _play(&"bow_draw"):
		return
	aiming = true
	aim.reset()
	angle = 0.0
	power = bow_min_power
	player.velocity.x = 0.0
	if _dots == null:
		_dots = Dots.new()
		player.get_parent().add_child(_dots)
	_dots.visible = true
	_sfx = Feedback.sfx_loop(&"bow_aim", player.global_position)
	_haptic = Feedback.haptic_loop(_haptic_id(), 0.0)


func _update_aim(delta: float) -> void:
	aim.update(angle_up, angle_down)
	angle = aim.angle
	if aim.magnitude >= 0.01:
		power = lerpf(power, aim.magnitude, 1.0 - exp(-delta / power_smoothing_time))
	else:
		power = move_toward(power, bow_min_power, power_release_rate * delta)
	power = maxf(power, bow_min_power)
	if player.rig.has_method(&"set_bow_aim"):
		player.rig.set_bow_aim(angle, power)
	Feedback.sfx_loop_update(_sfx, power, player.global_position)
	Feedback.haptic_loop_strength(_haptic, power * 0.4)
	_dots.set_points(_trajectory())


func direction() -> Vector2:
	var f: int = player.rig.facing if "facing" in player.rig else player.facing
	return Vector2(f * cos(angle), sin(angle))


func speed() -> float:
	return lerpf(min_speed, max_speed, power)


func nock_point() -> Vector2:
	var rig = player.rig
	if rig.has_method(&"get_anchor") and not rig.get_script().resource_path.ends_with("adventurer_stub.gd"):
		return rig.get_anchor(&"arrow.nock")
	return player.global_position + Vector2(player.facing * 60.0, -290.0)


func _trajectory() -> PackedVector2Array:
	var out := PackedVector2Array()
	var p := nock_point()
	var v := direction() * speed()
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	for i in dot_count:
		var next := p + v * dot_dt + Vector2(0, 0.5 * arrow_gravity * dot_dt * dot_dt)
		var ray := PhysicsRayQueryParameters2D.create(p, next, 1, [player.get_rid()])
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			out.append(hit.position)
			break
		v.y += arrow_gravity * dot_dt
		p = next
		out.append(p)
	return out


func _fire() -> void:
	aiming = false
	releasing = true
	_release_wait = 0.0
	_pending_shot = {"direction": direction(), "speed": lerpf(min_speed, max_speed, maxf(power, bow_min_power))}
	_stop_loops()
	_dots.visible = false
	Feedback.sfx(&"bow_release", player.global_position, power)
	if not _play(&"bow_release"):
		on_release()


# Rig `release` event (or right away without the rig action): the arrow leaves the string.
func on_release() -> void:
	if _pending_shot.is_empty():
		return
	var point := nock_point()
	var dir: Vector2 = _pending_shot.direction
	var rig = player.rig
	if rig.has_method(&"get_arrow_release"):
		var r: Dictionary = rig.get_arrow_release()
		if r.has("point"):
			point = r.point
	_spawn_arrow(point, dir, _pending_shot.speed)
	_pending_shot = {}
	shots += 1
	# The rig may chain the release back into the aim without finishing it: free the bow here.
	releasing = false


func on_finished(id: StringName) -> void:
	if id == &"bow_release" or id == &"bow_cancel":
		if not _pending_shot.is_empty():
			on_release()
		releasing = false


# Out of the aim on the game side only (the rig already left it): no cancel action.
func _suspend() -> void:
	aiming = false
	_stop_loops()
	if _dots:
		_dots.visible = false


func _cancel() -> void:
	aiming = false
	_stop_loops()
	if _dots:
		_dots.visible = false
	_play(&"bow_cancel")


func _spawn_arrow(point: Vector2, dir: Vector2, spd: float) -> void:
	var parent: Node = player.get_parent()
	if ResourceLoader.exists(ARROW_SCRIPT_PATH):
		var arrow_class = load(ARROW_SCRIPT_PATH)
		arrow_class.spawn(parent, point, dir, spd, player)
	else:
		Feedback.sfx(&"arrow_whoosh", point)


func _play(id: StringName) -> bool:
	var rig = player.rig
	return rig.has_method(&"play_action") and rig.play_action(id)


func _stop_loops() -> void:
	Feedback.sfx_stop(_sfx)
	Feedback.haptic_stop(_haptic)
	_sfx = -1
	_haptic = -1


func _haptic_id() -> StringName:
	var h := Feedback.haptics()
	if h and h.has_method(&"has_profile") and h.has_profile(&"bow_aim"):
		return &"bow_aim"
	return &"wall_slide"
