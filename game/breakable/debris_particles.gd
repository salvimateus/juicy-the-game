extends MultiMeshInstance2D

# Pixel-art particle pool (chips and dust) drawn by a single MultiMesh in global coordinates.
# Positions snap to the art grid and sizes shrink in whole art pixels, so nothing renders off-grid.
# Storage is preallocated; emitting and simulating never allocate.

const MAX := 320
const FLOOR_BOUNCE := 0.3
const FLOOR_FRICTION := 0.55

var _a := 6.0
var _count := 0
var _pos := PackedVector2Array()
var _vel := PackedVector2Array()
var _life := PackedFloat32Array()
var _span := PackedFloat32Array()
var _grav := PackedFloat32Array()
var _drag := PackedFloat32Array()
var _floor := PackedFloat32Array()
var _size := PackedByteArray()
var _shrink := PackedByteArray()
var _color := PackedColorArray()


func setup(art_pixel: int) -> void:
	_a = float(art_pixel)
	_pos.resize(MAX)
	_vel.resize(MAX)
	_life.resize(MAX)
	_span.resize(MAX)
	_grav.resize(MAX)
	_drag.resize(MAX)
	_floor.resize(MAX)
	_size.resize(MAX)
	_shrink.resize(MAX)
	_color.resize(MAX)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)
	top_level = true
	global_position = Vector2.ZERO
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func active_count() -> int:
	return _count


func emit(pos: Vector2, vel: Vector2, life: float, size_px: int, color: Color, gravity: float,
		drag: float, floor_y: float = INF, shrink: bool = false) -> void:
	if _count >= MAX:
		return
	var i := _count
	_count += 1
	_pos[i] = pos
	_vel[i] = vel
	_life[i] = life
	_span[i] = life
	_grav[i] = gravity
	_drag[i] = drag
	_floor[i] = floor_y
	_size[i] = clampi(size_px, 1, 8)
	_shrink[i] = 1 if shrink else 0
	_color[i] = color


func clear() -> void:
	_count = 0
	multimesh.visible_instance_count = 0


func _process(delta: float) -> void:
	if _count == 0:
		return
	var i := 0
	while i < _count:
		var life := _life[i] - delta
		if life <= 0.0:
			_count -= 1
			_copy(_count, i)
			continue
		_life[i] = life
		var v := _vel[i]
		v.y += _grav[i] * delta
		v *= maxf(0.0, 1.0 - _drag[i] * delta)
		var p := _pos[i] + v * delta
		if p.y > _floor[i]:
			p.y = _floor[i]
			v.y *= -FLOOR_BOUNCE
			v.x *= FLOOR_FRICTION
		_pos[i] = p
		_vel[i] = v
		i += 1
	for j in _count:
		var s := float(_size[j])
		if _shrink[j] == 1:
			s = ceilf(s * _life[j] / _span[j])
		var side := s * _a
		var p := _pos[j]
		var tl := Vector2(roundf(p.x / _a) * _a, roundf(p.y / _a) * _a)
		multimesh.set_instance_transform_2d(j, Transform2D(0.0, Vector2(side, side), 0.0, tl + Vector2(side, -side) * 0.5))
		multimesh.set_instance_color(j, _color[j])
	multimesh.visible_instance_count = _count


func _copy(from: int, to: int) -> void:
	_pos[to] = _pos[from]
	_vel[to] = _vel[from]
	_life[to] = _life[from]
	_span[to] = _span[from]
	_grav[to] = _grav[from]
	_drag[to] = _drag[from]
	_floor[to] = _floor[from]
	_size[to] = _size[from]
	_shrink[to] = _shrink[from]
	_color[to] = _color[from]
