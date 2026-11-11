class_name PushCrate
extends RigidBody2D

# Wooden crate the player pushes into the river. On solid ground it is frozen (kinematic), so the
# player neither carries it with his body nor gets shoved by it, and stands on it like a block;
# push() slides it at PUSH_SPEED. With no floor under it, or in water, it turns dynamic: it falls,
# floats on the WaterBody buoyancy, bobs with the waves and drifts with the current. Weight on top
# (any CharacterBody2D standing on it) sinks it a little while it floats.
# Origin at the centre of the box.

const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const Particles := preload("res://game/water/water_particles.gd")

const GROUP := &"push_crate"
const SIZE_PX := 22
const PUSH_SPEED := 170.0
# Default half width of whoever pushes (the player's capsule radius).
const PUSHER_HALF_WIDTH := 73.0
# Reach of an open dam hole's pull on a floating crate.
const SUCTION_RADIUS := 420.0
const SCRAPE_EVERY := 0.2
const SETTLE_TIME := 0.25

@export var crate_mass := 6.0
# Buoyant force over weight when fully submerged (WaterBody reads the `buoyancy` meta).
@export var float_density := 2.4
# Extra downward force while someone stands on it in water, as a fraction of its weight.
@export var rider_load := 0.4

var half := 66.0
var start_position := Vector2.ZERO
var moving := false

var _grounded := true
var _settle := 0.0
var _scrape := 0.0
var _was_wet := false
var _dust: Particles
var _rng := RandomNumberGenerator.new()
var _rider_query := PhysicsShapeQueryParameters2D.new()
var _floor_query := PhysicsShapeQueryParameters2D.new()


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	_rng.randomize()
	var a := GameScale.art_pixel()
	half = SIZE_PX * a * 0.5
	start_position = global_position
	mass = crate_mass
	lock_rotation = true
	gravity_scale = 2600.0 / float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	can_sleep = false
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	set_meta(&"buoyancy", float_density)
	set_meta(&"surface", &"wood")
	# Couples harder to the current than the default, so the leak carries it off.
	set_meta(&"water_drag", 5.0)
	# The crate makes its own splash on entry (bigger than the generic one).
	set_meta(&"water_custom_splash", true)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.25
	pm.bounce = 0.0
	physics_material_override = pm
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2.ONE * half * 2.0
	shape.shape = rect
	add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = crate_texture()
	sprite.scale = Vector2(a, a)
	add_child(sprite)
	_dust = Particles.new()
	_dust.top_level = true
	_dust.z_as_relative = false
	_dust.z_index = 36
	add_child(_dust)
	_dust.setup(48, PackedColorArray([Color("#7a6250"), Color("#5a4030", 0.9), Color("#967e79", 0.8)]))
	var top := RectangleShape2D.new()
	top.size = Vector2(half * 2.0 - 12.0, 24.0)
	_rider_query.shape = top
	_rider_query.collide_with_areas = false
	var foot := RectangleShape2D.new()
	foot.size = Vector2(half * 2.0 - 12.0, 6.0)
	_floor_query.shape = foot
	_floor_query.collide_with_areas = false
	_freeze_on_ground()


# Called every physics frame while the player pushes. Returns false when the crate cannot move
# that way (wall, another crate, or it is not resting on the ground).
func push(dir: int, delta: float) -> bool:
	if dir == 0:
		return false
	if not _grounded:
		if _in_water():
			apply_central_force(Vector2(dir * mass * 900.0, 0.0))
			return true
		return false
	var motion := Vector2(dir * PUSH_SPEED * delta, 0.0)
	# Tested from a hair above the floor, so resting contact does not count as blocked. A crate in
	# the way is pushed along (a row of crates moves together).
	var from := global_transform.translated(Vector2(0, -2))
	var hit := KinematicCollision2D.new()
	if test_move(from, motion, hit):
		var other := hit.get_collider() as PushCrate
		if other == null or other == self or not other.push(dir, delta) or test_move(from, motion):
			return false
	global_position += motion
	moving = true
	_scrape -= delta
	if _scrape <= 0.0:
		_scrape = SCRAPE_EVERY
		Feedback.sfx(&"footstep", global_position + Vector2(0, half), 0.25, &"wood")
	_spawn_dust(-dir)
	if not _has_floor():
		_release(Vector2(dir * PUSH_SPEED, 0.0))
	return true


# Offset from the crate origin to where the pusher's origin (feet) should be, pushing toward dir.
func push_contact_offset(dir: int, pusher_half_width := PUSHER_HALF_WIDTH) -> Vector2:
	return Vector2(-signi(dir) * (half + pusher_half_width), half)


func is_grounded() -> bool:
	return _grounded


func reset_to_start() -> void:
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	global_position = start_position
	_was_wet = false
	_freeze_on_ground()
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_dust_step(delta)
	if _grounded:
		# Water rising around a resting crate (the valley filling up) lifts it off.
		if not moving and (not _has_floor() or _in_water()):
			_release(Vector2.ZERO)
		moving = false
		return
	var water := _water()
	var wet := water != null and water.is_point_in_water(global_position + Vector2(0, half * 0.4))
	if wet and not _was_wet and linear_velocity.y > 60.0:
		water.emit_splash(Vector2(global_position.x, water.get_surface_y(global_position.x, global_position.y)),
			clampf(0.5 + linear_velocity.y / 1400.0, 0.6, 1.3))
		water.emit_bubbles(global_position, 10, Vector2(0, -60))
	_was_wet = wet
	_suction(water)
	if wet and _rider():
		apply_central_force(Vector2(0.0, mass * _gravity() * rider_load))
	if not wet and _has_floor() and linear_velocity.length() < 25.0:
		_settle += delta
		if _settle > SETTLE_TIME:
			_freeze_on_ground()
	else:
		_settle = 0.0


# An open dam hole drags a floating crate to its inlet, lines it up with the opening (under the
# lip, over the sill), shoves it through the tunnel and out with the jet.
func _suction(water: WaterBody) -> void:
	if water == null:
		return
	var o := water.get_active_orifice_near(global_position, SUCTION_RADIUS)
	if o.is_empty():
		return
	var dir: int = o.dir
	var speed: float = o.speed
	var g := _gravity() * mass
	var top: float = o.top
	var bottom: float = o.bottom
	var x_in: float = o.x_in
	var x_out: float = o.x_out
	var fit_y := clampf(global_position.y, top + half + 10.0, bottom - half - 6.0)
	var x := global_position.x
	var past_inlet := (x - x_in) * dir > -half - 20.0
	var past_outlet := (x - x_out) * dir > -half
	if past_outlet:
		# Leaving the tunnel: carried out with the jet until it clears the sill.
		if (x - x_out) * dir < half + 30.0:
			apply_central_force(Vector2((dir * minf(speed * 0.4, 420.0) - linear_velocity.x) * mass * 8.0, 0.0))
		return
	var inlet: Vector2 = o.inlet
	var near := 1.0 - global_position.distance_to(inlet) / SUCTION_RADIUS
	var force := Vector2(dir * g * (1.2 + 1.8 * near), (fit_y - global_position.y) * mass * 160.0)
	if past_inlet:
		# Carried through at a fraction of the jet speed, not shot out like a bullet.
		force.x = (dir * minf(speed * 0.4, 420.0) - linear_velocity.x) * mass * 8.0
		# Inside the tunnel the water would float it into the ceiling; hold it level instead.
		force.y -= linear_velocity.y * mass * 8.0
	apply_central_force(force)


func _freeze_on_ground() -> void:
	_grounded = true
	_settle = 0.0
	linear_velocity = Vector2.ZERO
	# Snap to the art grid so the resting box sits on whole pixels.
	var a := float(GameScale.art_pixel())
	global_position = Vector2(roundf(global_position.x / a) * a, global_position.y)
	freeze = true


func _release(velocity: Vector2) -> void:
	_grounded = false
	_settle = 0.0
	freeze = false
	linear_velocity = velocity


func _has_floor() -> bool:
	_floor_query.transform = Transform2D(0.0, global_position + Vector2(0, half + 3.0))
	_floor_query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(_floor_query, 4):
		var c: Object = hit.collider
		# Another crate is ground only while it rests on ground itself (not while it floats).
		if c is StaticBody2D or c is TileMapLayer or (c is PushCrate and c != self and c.is_grounded()):
			return true
	return false


func _rider() -> bool:
	_rider_query.transform = Transform2D(0.0, global_position - Vector2(0, half + 12.0))
	_rider_query.exclude = [get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(_rider_query, 4):
		if hit.collider is CharacterBody2D:
			return true
	return false


func _in_water() -> bool:
	var w := _water()
	return w != null and w.is_point_in_water(global_position + Vector2(0, half * 0.5))


func _water() -> WaterBody:
	for n in get_tree().get_nodes_in_group(&"water"):
		if n is WaterBody:
			return n
	return null


func _gravity() -> float:
	return float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)) * gravity_scale


func _spawn_dust(side: int) -> void:
	if _dust.count >= _dust.capacity - 1 or _rng.randf() > 0.45:
		return
	var foot := global_position + Vector2(side * (half - 6.0), half - 6.0)
	_dust.spawn(foot.x, foot.y, side * _rng.randf_range(20.0, 70.0), -_rng.randf_range(30.0, 90.0),
		_rng.randf_range(0.25, 0.5), 1, _rng.randi_range(0, 2))


func _dust_step(delta: float) -> void:
	if _dust.count == 0:
		return
	var i := _dust.count - 1
	while i >= 0:
		_dust.life[i] -= delta
		_dust.vy[i] += 200.0 * delta
		_dust.px[i] += _dust.vx[i] * delta
		_dust.py[i] += _dust.vy[i] * delta
		if _dust.life[i] <= 0.0:
			_dust.kill(i)
		i -= 1
	_dust.flush()


# 22x22 art px crate: planks, a cross brace and a dark rim.
static func crate_texture() -> ImageTexture:
	var n := SIZE_PX
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var wood := Color("#8a5a34")
	var light := Color("#b07a48")
	var dark := Color("#5a3a22")
	var seam := Color("#6e4a2a")
	var outline := Color("#141013")
	img.fill(wood)
	for y in n:
		if y % 5 == 4:
			img.fill_rect(Rect2i(0, y, n, 1), seam)
	for i in range(2, n - 2):
		img.set_pixel(i, i, dark)
		img.set_pixel(i + 1 if i + 1 < n - 2 else i, i, light)
		img.set_pixel(n - 1 - i, i, seam)
	img.fill_rect(Rect2i(0, 0, n, 2), light)
	img.fill_rect(Rect2i(0, n - 2, n, 2), dark)
	img.fill_rect(Rect2i(0, 0, 2, n), light)
	img.fill_rect(Rect2i(n - 2, 0, 2, n), dark)
	for v in [Vector2i(3, 3), Vector2i(n - 4, 3), Vector2i(3, n - 4), Vector2i(n - 4, n - 4)]:
		img.set_pixelv(v, Color("#d8d0c0"))
	for i in n:
		img.set_pixel(i, 0, outline)
		img.set_pixel(i, n - 1, outline)
		img.set_pixel(0, i, outline)
		img.set_pixel(n - 1, i, outline)
	return ImageTexture.create_from_image(img)
