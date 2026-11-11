class_name TargetFx
extends Node2D

# Pixel-art hit effects of the training targets: blood spray and drips that stain the floor, straw
# slivers and small dust puffs. Everything lives in preallocated arrays and is drawn by this node in
# global coordinates (top_level), snapped to the art grid; ground stains sit on a child canvas item
# that redraws only when a stain appears, fades a step or goes away.

const GameScale := preload("res://game/game_scale.gd")

const MAX_PARTICLES := 220
const MAX_STAINS := 96
const MAX_DRIPS := 6
const BLOOD := [Color("#5e0b0e"), Color("#8c1418"), Color("#b81e22")]
const STRAW := [Color("#f0c862"), Color("#e2a843"), Color("#c7862f"), Color("#9c5f27")]
const DUST := [Color("#f4ece4"), Color("#d8ccc4")]
const BAG_DUST := [Color("#b09891"), Color("#8a7872"), Color("#c4aea6")]
const STRAW_DIRS := [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(1, -1)]

enum { BLOOD_DROP, STRAW_BIT, DUST_BIT, SHRED_BIT }

@export_group("Blood")
@export var blood_drops := 30
# Share of the drops drawn as 2x2 art-pixel clots.
@export_range(0.0, 1.0) var blood_big := 0.3
@export var blood_speed := Vector2(380.0, 1150.0)
@export var blood_spread := 0.55
@export var blood_back_ratio := 0.2
@export var blood_gravity := 2600.0
@export var stain_life := 8.0
@export var stain_fade := 1.6
@export_group("Straw")
@export var straw_bits := 10
@export var straw_speed := Vector2(300.0, 900.0)
@export var straw_gravity := 1300.0
@export var straw_drag := 2.2
@export var straw_rest_life := 3.0
@export_group("Drips")
@export var drip_count := 4
@export var drip_interval := 0.22

var floor_y := 0.0

var _a := 6.0
var _n := 0
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _floor := PackedFloat32Array()
var _ang := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _kind := PackedByteArray()
var _size := PackedByteArray()
var _rest := PackedByteArray()
var _col := PackedColorArray()

var _sn := 0
var _st_pos := PackedVector2Array()
var _st_w := PackedByteArray()
var _st_col := PackedColorArray()
var _st_age := PackedFloat32Array()
var _st_level := PackedByteArray()
var _stains: Node2D

var _drip_pos := PackedVector2Array()
var _drip_left := PackedInt32Array()
var _drip_t := PackedFloat32Array()
var _drip_floor := PackedFloat32Array()

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_a = float(GameScale.art_pixel())
	top_level = true
	global_position = Vector2.ZERO
	z_index = 3
	for arr in [_pos, _vel]:
		arr.resize(MAX_PARTICLES)
	for arr in [_life, _floor, _ang, _spin]:
		arr.resize(MAX_PARTICLES)
	_kind.resize(MAX_PARTICLES)
	_size.resize(MAX_PARTICLES)
	_rest.resize(MAX_PARTICLES)
	_col.resize(MAX_PARTICLES)
	_st_pos.resize(MAX_STAINS)
	_st_w.resize(MAX_STAINS)
	_st_col.resize(MAX_STAINS)
	_st_age.resize(MAX_STAINS)
	_st_level.resize(MAX_STAINS)
	_drip_pos.resize(MAX_DRIPS)
	_drip_left.resize(MAX_DRIPS)
	_drip_t.resize(MAX_DRIPS)
	_drip_floor.resize(MAX_DRIPS)
	_stains = Node2D.new()
	_stains.name = "Stains"
	_stains.z_as_relative = false
	_stains.z_index = 0
	_stains.draw.connect(_draw_stains)
	add_child(_stains)
	_rng.randomize()
	set_process(false)


# Blood burst at `point`, mostly along `direction` with a little back-spray; amount ~0..1.5.
func spray_blood(point: Vector2, direction: Vector2, amount := 1.0, ground_y := NAN) -> void:
	var fy := floor_y if is_nan(ground_y) else ground_y
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var count := maxi(2, roundi(blood_drops * amount))
	for i in count:
		var back := _rng.randf() < blood_back_ratio
		var base := -dir if back else dir
		var ang := base.angle() + _rng.randf_range(-blood_spread, blood_spread) - 0.25 * signf(base.x if absf(base.x) > 0.01 else 1.0) * _rng.randf()
		var speed := _rng.randf_range(blood_speed.x, blood_speed.y) * (0.55 if back else 1.0) * clampf(0.6 + amount * 0.4, 0.6, 1.3)
		var v := Vector2.from_angle(ang) * speed + Vector2(0, -_rng.randf_range(80.0, 320.0))
		var k := _emit(BLOOD_DROP, point + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)), v, 3.0, fy, BLOOD[_rng.randi() % BLOOD.size()])
		if k >= 0 and i < count * blood_big:
			_size[k] = 2
	set_process(true)


# Slow drops falling from a wound for a moment after the hit.
func drip(point: Vector2, count := -1, ground_y := NAN) -> void:
	var fy := floor_y if is_nan(ground_y) else ground_y
	var slot := 0
	for i in MAX_DRIPS:
		if _drip_left[i] <= 0:
			slot = i
			break
		if _drip_t[i] > _drip_t[slot]:
			slot = i
	_drip_pos[slot] = point
	_drip_left[slot] = drip_count if count < 0 else count
	_drip_t[slot] = drip_interval * 0.5
	_drip_floor[slot] = fy
	set_process(true)


func spray_straw(point: Vector2, direction: Vector2, amount := 1.0, ground_y := NAN) -> void:
	var fy := floor_y if is_nan(ground_y) else ground_y
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
	var count := maxi(2, roundi(straw_bits * amount))
	for i in count:
		var ang := dir.angle() + _rng.randf_range(-1.0, 1.0)
		var v := Vector2.from_angle(ang) * _rng.randf_range(straw_speed.x, straw_speed.y) + Vector2(0, -_rng.randf_range(200.0, 520.0))
		var k := _emit(STRAW_BIT, point + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12)), v, 6.0, fy, STRAW[_rng.randi() % STRAW.size()])
		if k >= 0:
			_ang[k] = _rng.randf() * TAU
			_spin[k] = _rng.randf_range(-16.0, 16.0)
	set_process(true)


# Rubber strips of a popped balloon, in its colour, flung all around and fluttering down.
func shreds(point: Vector2, color: Color, count := 10, ground_y := NAN) -> void:
	var fy := floor_y if is_nan(ground_y) else ground_y
	var dark := color.darkened(0.35)
	for i in count:
		var v := Vector2.from_angle(TAU * i / count + _rng.randf_range(-0.35, 0.35)) * _rng.randf_range(260.0, 620.0)
		var k := _emit(SHRED_BIT, point + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-12, 12)), v, _rng.randf_range(0.9, 1.6), fy, color if i % 3 != 0 else dark)
		if k >= 0:
			_ang[k] = _rng.randf() * TAU
			_spin[k] = _rng.randf_range(-20.0, 20.0)
	set_process(true)


# Dust knocked out of a bag or a sack: greyish puffs thrown back along `direction`, slowing fast.
func dust(point: Vector2, direction: Vector2, count := 8) -> void:
	var dir := direction.normalized() if direction.length_squared() > 0.0001 else Vector2.UP
	for i in count:
		var v := Vector2.from_angle(dir.angle() + _rng.randf_range(-1.1, 1.1)) * _rng.randf_range(140.0, 460.0) + Vector2(0, -_rng.randf_range(20.0, 140.0))
		_emit(DUST_BIT, point + Vector2(_rng.randf_range(-12, 12), _rng.randf_range(-24, 24)), v, _rng.randf_range(0.2, 0.42), INF, BAG_DUST[i % BAG_DUST.size()])
	set_process(true)


func puff(point: Vector2, count := 6) -> void:
	for i in count:
		var v := Vector2.from_angle(TAU * i / count + _rng.randf_range(-0.3, 0.3)) * _rng.randf_range(160.0, 320.0)
		_emit(DUST_BIT, point, v, _rng.randf_range(0.14, 0.24), INF, DUST[i % DUST.size()])
	set_process(true)


func clear_stains() -> void:
	_sn = 0
	_stains.queue_redraw()


func clear_all() -> void:
	_n = 0
	for i in MAX_DRIPS:
		_drip_left[i] = 0
	clear_stains()
	queue_redraw()


func _emit(kind: int, p: Vector2, v: Vector2, life: float, fy: float, color: Color) -> int:
	if _n >= MAX_PARTICLES:
		return -1
	var k := _n
	_n += 1
	_pos[k] = p
	_vel[k] = v
	_life[k] = life
	_floor[k] = fy
	_kind[k] = kind
	_size[k] = 1
	_rest[k] = 0
	_col[k] = color
	_ang[k] = 0.0
	_spin[k] = 0.0
	return k


func _kill(k: int) -> void:
	_n -= 1
	if k == _n:
		return
	_pos[k] = _pos[_n]
	_vel[k] = _vel[_n]
	_life[k] = _life[_n]
	_floor[k] = _floor[_n]
	_kind[k] = _kind[_n]
	_size[k] = _size[_n]
	_rest[k] = _rest[_n]
	_col[k] = _col[_n]
	_ang[k] = _ang[_n]
	_spin[k] = _spin[_n]


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 30.0)
	_update_drips(delta)
	var k := 0
	while k < _n:
		_life[k] -= delta
		if _life[k] <= 0.0:
			_kill(k)
			continue
		if _rest[k] == 0:
			var v := _vel[k]
			match _kind[k]:
				BLOOD_DROP:
					v.y += blood_gravity * delta
					v.x *= 1.0 - 0.6 * delta
				STRAW_BIT:
					v.y += straw_gravity * delta
					v *= 1.0 - straw_drag * delta
					_ang[k] += _spin[k] * delta
				SHRED_BIT:
					v.y += straw_gravity * 0.6 * delta
					v *= 1.0 - 4.0 * delta
					_ang[k] += _spin[k] * delta
				DUST_BIT:
					v *= 1.0 - 7.0 * delta
			_vel[k] = v
			var p := _pos[k] + v * delta
			if p.y >= _floor[k] - 1.0:
				p.y = _floor[k] - 1.0
				if _kind[k] == BLOOD_DROP:
					_add_stain(p, _col[k], absf(v.x) > 500.0 or _size[k] > 1)
					_kill(k)
					continue
				if _kind[k] == STRAW_BIT:
					_rest[k] = 1
					_life[k] = minf(_life[k], straw_rest_life + _rng.randf())
					_ang[k] = 0.0 if _rng.randf() < 0.7 else PI * 0.25
			_pos[k] = p
		k += 1
	_age_stains(delta)
	queue_redraw()
	if _n == 0 and _sn == 0 and not _drips_active():
		set_process(false)


func _drips_active() -> bool:
	for i in MAX_DRIPS:
		if _drip_left[i] > 0:
			return true
	return false


func _update_drips(delta: float) -> void:
	for i in MAX_DRIPS:
		if _drip_left[i] <= 0:
			continue
		_drip_t[i] -= delta
		if _drip_t[i] <= 0.0:
			_drip_t[i] = drip_interval * _rng.randf_range(0.7, 1.4)
			_drip_left[i] -= 1
			_emit(BLOOD_DROP, _drip_pos[i] + Vector2(_rng.randf_range(-6, 6), 6), Vector2(_rng.randf_range(-20, 20), 40), 3.0, _drip_floor[i], BLOOD[_rng.randi() % 2])


func _add_stain(p: Vector2, color: Color, smear: bool) -> void:
	var cell := Vector2(floorf(p.x / _a) * _a, floorf(p.y / _a) * _a)
	for i in _sn:
		if absf(_st_pos[i].y - cell.y) < 1.0 and cell.x >= _st_pos[i].x - _a and cell.x <= _st_pos[i].x + _st_w[i] * _a:
			if cell.x < _st_pos[i].x:
				_st_pos[i].x = cell.x
				_st_w[i] = mini(_st_w[i] + 1, 6)
			elif cell.x >= _st_pos[i].x + _st_w[i] * _a:
				_st_w[i] = mini(_st_w[i] + 1, 6)
			_st_age[i] = 0.0
			_st_level[i] = 3
			_stains.queue_redraw()
			return
	var j := _sn
	if _sn >= MAX_STAINS:
		j = 0
		for i in _sn:
			if _st_age[i] > _st_age[j]:
				j = i
	else:
		_sn += 1
	_st_pos[j] = cell
	_st_w[j] = 2 if smear else 1
	_st_col[j] = color
	_st_age[j] = 0.0
	_st_level[j] = 3
	_stains.queue_redraw()


func _age_stains(delta: float) -> void:
	var i := 0
	while i < _sn:
		_st_age[i] += delta
		var left := stain_life - _st_age[i]
		if left <= 0.0:
			_sn -= 1
			_st_pos[i] = _st_pos[_sn]
			_st_w[i] = _st_w[_sn]
			_st_col[i] = _st_col[_sn]
			_st_age[i] = _st_age[_sn]
			_st_level[i] = _st_level[_sn]
			_stains.queue_redraw()
			continue
		var level := 3 if left > stain_fade else clampi(ceili(left / stain_fade * 3.0), 1, 3)
		if level != _st_level[i]:
			_st_level[i] = level
			_stains.queue_redraw()
		i += 1


func _draw_stains() -> void:
	for i in _sn:
		var c := _st_col[i]
		c.a = _st_level[i] / 3.0
		_stains.draw_rect(Rect2(_st_pos[i], Vector2(_st_w[i] * _a, _a)), c)


func _draw() -> void:
	var a := _a
	for k in _n:
		var p := _pos[k]
		var cell := Vector2(floorf(p.x / a) * a, floorf(p.y / a) * a)
		var c := _col[k]
		match _kind[k]:
			BLOOD_DROP:
				var sz := a * _size[k]
				draw_rect(Rect2(cell, Vector2(sz, sz)), c)
				var v := _vel[k]
				if v.length_squared() > 810000.0:
					var back := Vector2(-signf(v.x), 0) if absf(v.x) > absf(v.y) else Vector2(0, -signf(v.y))
					draw_rect(Rect2(cell + back * a, Vector2(a, a)), BLOOD[0])
			STRAW_BIT:
				if _rest[k] == 1 and _life[k] < 0.5 and int(_life[k] * 16.0) % 2 == 1:
					continue
				var step := posmod(roundi(_ang[k] / (PI * 0.25)), 4)
				var d: Vector2 = STRAW_DIRS[step] * a
				draw_rect(Rect2(cell - d, Vector2(a, a)), c)
				draw_rect(Rect2(cell, Vector2(a, a)), c)
				draw_rect(Rect2(cell + d, Vector2(a, a)), STRAW[3])
			DUST_BIT:
				draw_rect(Rect2(cell, Vector2(a, a)), c)
			SHRED_BIT:
				if _life[k] < 0.3 and int(_life[k] * 20.0) % 2 == 1:
					continue
				var dir: Vector2 = STRAW_DIRS[posmod(roundi(_ang[k] / (PI * 0.25)), 4)] * a
				draw_rect(Rect2(cell, Vector2(a, a)), c)
				draw_rect(Rect2(cell + dir, Vector2(a, a)), c)
