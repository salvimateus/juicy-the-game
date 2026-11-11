extends RefCounted

# Revolver and AK-47: hold aim (LT / right mouse / L) to raise and aim, fire (RT / left mouse / J)
# to shoot. The right stick (or the mouse) points the shot; centred keeps the last angle, which
# starts level; the left stick turns the character.
# Revolver: cocks itself on raise and after every shot (rig revolver_recock), RT presses while not
# ready are buffered. AK: RT held fires a burst whose spread and camera shake grow. Each rig
# `shot` event casts a ray from the muzzle: damageables take a &"bullet" hit, solids get sparks.
# Ricochet surfaces (meta ricochet) mirror the ray, which goes on with the range left: a tracer
# per segment, a spark and a ping at each bounce, the damage only on what it finally hits, the
# shooter included once the round has bounced.

const Feedback := preload("res://game/feedback.gd")
const Laser := preload("res://game/combat/laser_sight.gd")
const ImpactFx := preload("res://game/combat/impact_fx.gd")
const Aim := preload("res://game/combat/aim.gd")
const FogHooks := preload("res://game/fog_hooks.gd")
const Ricochet := preload("res://game/ricochet/ricochet.gd")
const LIGHTING_PATH := "res://game/lighting/lighting.gd"
static var _lighting: Script

const AIM_UP := deg_to_rad(-75.0)
const AIM_DOWN := deg_to_rad(60.0)

# 0 keeps the player still while aiming; otherwise a fraction of the walk speed.
var aim_move_speed := 0.0
var revolver_fire_interval := 0.4
var revolver_damage := 24.0
var rifle_damage := 12.0
var rifle_spread_start := deg_to_rad(0.6)
var rifle_spread_max := deg_to_rad(5.0)
var rifle_spread_growth := deg_to_rad(4.0)
var range_max := 1400.0
var shot_range := 4000.0
var max_ricochets := 2
# Damage kept per bounce.
var ricochet_damage_keep := 0.7
# Micro hitstop on a revolver ricochet; the AK's automatic fire keeps its rhythm (none).
var revolver_ricochet_hitstop := 0.025
var revolver_ricochet_strength := 1.0
var rifle_ricochet_strength := 0.7
var ricochets := 0
var self_hits := 0

var player
var weapon: StringName = &""
var aiming := false
var angle := 0.0
var shots := 0
var hits := 0
var aim
var _ready_to_fire := false
var _since_fire := INF
var _buffered := false
var _firing := false
var _burst_time := 0.0
var _laser: Node2D
var _fx: Node2D
var _rng := RandomNumberGenerator.new()


func _init(owner_player) -> void:
	player = owner_player
	aim = Aim.new(owner_player)


func blocks_movement() -> bool:
	return aiming and aim_move_speed <= 0.0


func step(delta: float, gun: StringName, can_act: bool) -> void:
	_since_fire += delta
	var aim_held: bool = can_act and player.combat.aim_down and player.is_on_floor()
	if not aiming:
		if aim_held:
			_begin(gun)
		return
	if not aim_held or gun != weapon:
		end()
		return
	# Every frame: the rig must be in this gun's aim; enter again (straight into the aim loop) or
	# step out on the game side and retry next frame.
	if not player.combat.rig_in_aim_loop(weapon):
		var entry := &"revolver_aim" if weapon == &"revolver" else &"rifle_raise"
		if not _play(entry):
			_suspend()
			return
		_ready_to_fire = true
	_update_aim()
	if weapon == &"revolver":
		if player.just_pressed(&"fire"):
			_buffered = true
		if _buffered and _ready_to_fire and _since_fire >= revolver_fire_interval:
			_fire_revolver()
	else:
		var want: bool = player.held(&"fire")
		if want != _firing:
			_firing = want
			_burst_time = 0.0
			if player.rig.has_method(&"set_rifle_firing"):
				player.rig.set_rifle_firing(want)
		if _firing:
			_burst_time += delta
			player.camera_shake(minf(3.0 + _burst_time * 8.0, 14.0), 0.12)


func _begin(gun: StringName) -> void:
	# The aim starts only once the rig takes the raise (it may be busy finishing something).
	var entry := &"revolver_cock" if gun == &"revolver" else &"rifle_raise"
	var has_rig: bool = player.rig.has_method(&"play_action")
	var played := _play(entry)
	if has_rig and not played and not (gun == &"revolver" and _play(&"revolver_aim")):
		return
	weapon = gun
	aiming = true
	aim.reset()
	angle = 0.0
	_buffered = false
	_firing = false
	_since_fire = INF
	player.velocity.x = 0.0
	# The revolver cocks itself on the way up and is ready on its click; otherwise ready now.
	_ready_to_fire = not (gun == &"revolver" and played)
	if _laser == null:
		_laser = Laser.new()
		player.get_parent().add_child(_laser)
		_fx = ImpactFx.new()
		player.get_parent().add_child(_fx)
	_laser.visible = true


# Out of the aim on the game side only (the rig already left it).
func _suspend() -> void:
	aiming = false
	if _firing and player.rig.has_method(&"set_rifle_firing"):
		player.rig.set_rifle_firing(false)
	_firing = false
	if _laser:
		_laser.visible = false


func end() -> void:
	if not aiming:
		return
	aiming = false
	if _firing and player.rig.has_method(&"set_rifle_firing"):
		player.rig.set_rifle_firing(false)
	_firing = false
	if _laser:
		_laser.visible = false
	# The rig may refuse the lower from inside its aim loop: then end the loop outright, or it
	# would hold the aim pose forever and block the next weapon.
	if not _play(&"revolver_holster" if weapon == &"revolver" else &"rifle_lower"):
		var rig = player.rig
		if rig.has_method(&"stop_action") and player.combat.rig_in_aim_loop(weapon):
			rig.stop_action()


# Upward aim limit per gun from the rig (REVOLVER_AIM_MIN_DEG / RIFLE_AIM_MIN_DEG), else AIM_UP.
func _aim_up() -> float:
	var script: Script = player.rig.get_script()
	if script:
		var key := "REVOLVER_AIM_MIN_DEG" if weapon == &"revolver" else "RIFLE_AIM_MIN_DEG"
		var map := script.get_script_constant_map()
		if map.has(key):
			return deg_to_rad(float(map[key]))
	return AIM_UP


func _update_aim() -> void:
	aim.update(_aim_up(), AIM_DOWN)
	angle = aim.angle
	if player.rig.has_method(&"set_gun_aim"):
		player.rig.set_gun_aim(angle)
	var m := muzzle()
	_laser.set_path(_aim_path(m.point, direction()))


# Laser path through the same ricochets a shot would take (no scatter), within range_max.
func _aim_path(from: Vector2, dir: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array([from])
	var remaining := range_max
	for i in max_ricochets + 1:
		var hit := _ray(from, dir, remaining, i > 0)
		var end: Vector2 = hit.get("position", from + dir * remaining)
		points.append(end)
		if hit.is_empty() or i == max_ricochets or _damageable(hit.collider) or not Ricochet.is_surface(hit.collider):
			break
		var n := Ricochet.normal_of(hit.normal, dir)
		remaining -= from.distance_to(end)
		if remaining <= 1.0:
			break
		dir = Ricochet.deflect(dir, n, 0.0)
		from = end + n * Ricochet.CLEARANCE
	return points


# Aim direction. The rig's muzzle direction wins when it has one: the rig may hold a facing change
# back during gun actions, and the shot must leave where the barrel points on screen.
func direction() -> Vector2:
	var m := muzzle()
	if m.has("direction") and m.direction is Vector2 and (m.direction as Vector2).length() > 0.5:
		return (m.direction as Vector2).normalized()
	return _computed_direction()


func _computed_direction() -> Vector2:
	var f: int = player.rig.facing if "facing" in player.rig else player.facing
	return Vector2(f * cos(angle), sin(angle))


func muzzle() -> Dictionary:
	var rig = player.rig
	if rig.has_method(&"get_muzzle"):
		var m: Dictionary = rig.get_muzzle()
		if m.has("point"):
			return m
	return {"point": player.global_position + Vector2(player.facing * 130.0, -270.0), "direction": _computed_direction()}


func _fire_revolver() -> void:
	_buffered = false
	_ready_to_fire = false
	_since_fire = 0.0
	if not _play(&"revolver_fire"):
		on_shot()
		_ready_to_fire = true


# Rig `click` (cock or recock): the hammer is back, the next shot may go.
func on_click() -> void:
	Feedback.sfx(&"revolver_cock", player.global_position)
	_ready_to_fire = true


# Rig `shot` event: one round leaves the muzzle.
func on_shot() -> void:
	var m := muzzle()
	var dir := direction()
	if weapon == &"rifle":
		var spread := minf(rifle_spread_start + _burst_time * rifle_spread_growth, rifle_spread_max)
		dir = dir.rotated(_rng.randf_range(-spread, spread))
	var revolver := weapon == &"revolver"
	var fog_k := 1.0 if revolver else 0.8
	var damage := revolver_damage if revolver else rifle_damage
	var shot_dir := dir
	var from: Vector2 = m.point
	var remaining := shot_range
	var hit := {}
	var end_point := from
	var target: Node = null
	var bounces := 0
	while true:
		hit = _ray(from, dir, remaining, bounces > 0)
		end_point = hit.get("position", from + dir * remaining)
		_fx.tracer(from, end_point)
		FogHooks.line(from, end_point, 16.0, fog_k)
		target = player if bounces > 0 and _is_shooter(hit.get("collider")) else _damageable(hit.get("collider"))
		if target or hit.is_empty() or bounces >= max_ricochets or not Ricochet.is_surface(hit.collider):
			break
		var n := Ricochet.normal_of(hit.normal, dir)
		var out := Ricochet.deflect(dir, n)
		remaining -= from.distance_to(end_point)
		bounces += 1
		ricochets += 1
		damage *= ricochet_damage_keep
		Ricochet.impact(end_point, n, out, revolver_ricochet_strength if revolver else rifle_ricochet_strength, &"bullet", hit.collider, player, revolver_ricochet_hitstop if revolver else 0.0)
		dir = out
		from = end_point + n * Ricochet.CLEARANCE
		if remaining <= 1.0:
			hit = {}
			break
	shots += 1
	if target == player:
		# A ricochet came back: the regular shot reaction (it cancels the aim and the burst).
		self_hits += 1
		player.take_hit(end_point, dir, damage, &"bullet")
	elif target:
		hits += 1
		target.take_hit(end_point, dir, damage, &"bullet")
	elif not hit.is_empty():
		_fx.impact(end_point, hit.normal)
	FogHooks.push(m.point, shot_dir * 500.0, 60.0, 0.6 * fog_k)
	if not hit.is_empty() and target == null:
		var body := hit.get("collider") as Node
		if body and body.get_meta(&"surface", &"") in [&"grass", &"dirt"]:
			FogHooks.burst(end_point, 70.0, 0.4)
	if _lighting == null and ResourceLoader.exists(LIGHTING_PATH):
		_lighting = load(LIGHTING_PATH)
	if _lighting:
		_lighting.flash(m.point)
	var id := &"revolver_shot" if weapon == &"revolver" else &"rifle_shot"
	Feedback.sfx(id, m.point)
	Feedback.haptic(id)
	if weapon == &"revolver":
		player.camera_shake(7.0, 0.15)


# The shooter is skipped until the round has bounced (then it may come back at them), and always
# while dodging or rolling (i-frames).
func _ray(from: Vector2, dir: Vector2, length: float, bounced := false) -> Dictionary:
	var exclude: Array[RID] = []
	if not bounced or player.lets_projectiles_through():
		exclude.append(player.get_rid())
	var query := PhysicsRayQueryParameters2D.create(from, from + dir * length, 1 | (1 << 6), exclude)
	query.collide_with_areas = true
	return player.get_world_2d().direct_space_state.intersect_ray(query)


# The shooter's body (or a part of it) when the ray hit it.
func _is_shooter(collider: Variant) -> bool:
	var node := collider as Node
	while node:
		if node == player:
			return true
		node = node.get_parent()
	return false


func _damageable(collider: Variant) -> Node:
	var node := collider as Node
	while node and not node.is_in_group(&"damageable"):
		node = node.get_parent()
	return node if node and node.has_method(&"take_hit") else null


func _play(id: StringName) -> bool:
	var rig = player.rig
	return rig.has_method(&"play_action") and rig.play_action(id)
