extends MultiMeshInstance2D

# Fixed-capacity point pool drawn as one MultiMesh (one draw call). Storage is packed arrays and
# dead points are swap-removed, so the live points are always 0..count-1 and nothing is allocated
# after setup. The owner runs the motion; this node only stores, snaps to the art grid and draws.

const ART := 6.0

var capacity := 0
var count := 0
var px := PackedFloat32Array()
var py := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
# Seconds left; the owner decides what happens at 0.
var life := PackedFloat32Array()
# Free per-point value for the owner (carried volume, phase, bounce count).
var aux := PackedFloat32Array()
# Size in art pixels (1..4) and colour index into `palette`.
var size_px := PackedByteArray()
var tint := PackedByteArray()
var palette: PackedColorArray = PackedColorArray([Color.WHITE])
# Extra horizontal render offset in units (bubble wobble), not part of the motion.
var draw_dx := PackedFloat32Array()

var _buffer := PackedFloat32Array()
var _quad_px := 1


func setup(cap: int, colors: PackedColorArray, tex: Texture2D = null, quad_px := 1) -> void:
	capacity = cap
	palette = colors
	px.resize(cap); py.resize(cap); vx.resize(cap); vy.resize(cap); life.resize(cap); aux.resize(cap); draw_dx.resize(cap)
	size_px.resize(cap)
	tint.resize(cap)
	var quad := QuadMesh.new()
	_quad_px = quad_px
	quad.size = Vector2.ONE * ART * quad_px
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = cap
	mm.visible_instance_count = 0
	# Points roam the whole level; a fixed bound keeps the canvas from culling them by a stale box.
	mm.custom_aabb = AABB(Vector3(-1e6, -1e6, -1.0), Vector3(2e6, 2e6, 2.0))
	multimesh = mm
	_buffer.resize(cap * 12)
	if tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		tex = ImageTexture.create_from_image(img)
	texture = tex
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Points are written from _process already snapped; interpolating them would smear the grid.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func spawn(x: float, y: float, svx: float, svy: float, t: float, size := 1, color := 0, extra := 0.0) -> int:
	if count >= capacity:
		return -1
	var i := count
	count += 1
	px[i] = x; py[i] = y; vx[i] = svx; vy[i] = svy; life[i] = t; aux[i] = extra
	size_px[i] = size
	tint[i] = color
	draw_dx[i] = 0.0
	return i


func kill(i: int) -> void:
	count -= 1
	if i == count:
		return
	px[i] = px[count]; py[i] = py[count]; vx[i] = vx[count]; vy[i] = vy[count]
	life[i] = life[count]; aux[i] = aux[count]; size_px[i] = size_px[count]; tint[i] = tint[count]
	draw_dx[i] = draw_dx[count]


func clear() -> void:
	count = 0
	multimesh.visible_instance_count = 0


# Writes the live points to the MultiMesh, each snapped to the art grid (top-left corner).
func flush() -> void:
	var k := 0
	for i in count:
		var s := float(size_px[i])
		var half := ART * _quad_px * s * 0.5
		var ox := floorf((px[i] + draw_dx[i]) / ART) * ART + half
		var oy := floorf(py[i] / ART) * ART + half
		var c: Color = palette[tint[i]]
		_buffer[k] = s; _buffer[k + 1] = 0.0; _buffer[k + 2] = 0.0; _buffer[k + 3] = ox
		_buffer[k + 4] = 0.0; _buffer[k + 5] = s; _buffer[k + 6] = 0.0; _buffer[k + 7] = oy
		_buffer[k + 8] = c.r; _buffer[k + 9] = c.g; _buffer[k + 10] = c.b; _buffer[k + 11] = c.a
		k += 12
	RenderingServer.multimesh_set_buffer(multimesh.get_rid(), _buffer)
	multimesh.visible_instance_count = count
