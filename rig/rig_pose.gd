class_name RigPose
extends RefCounted
## Per-frame animation state as deltas on top of the rest pose (radians, rig units).
## facing (1 right, -1 left) mirrors everything around root_x and is applied last, so clips are
## always authored facing right.

var rot := PackedFloat32Array()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var sx := PackedFloat32Array()
var sy := PackedFloat32Array()
var face := PackedFloat32Array()  # one value per RigData.face_fields entry
var root_x := 0.0
var root_y := 0.0
var root_rot := 0.0
var pivot_x := 0.0
var pivot_y := 0.0
var root_sx := 1.0
var root_sy := 1.0
var props := 0
var flash := 0.0
var tint := 0.0
var tint_color := Color("#ff3030")
var shake_x := 0.0
var shake_y := 0.0
var hammer := 0.0
var facing := 1
var draw_order := 0  # RigDrawOrder preset id


func _init(rig: RigData) -> void:
	for arr in [rot, x, y, sx, sy]:
		arr.resize(rig.bone_count)
	face.resize(rig.face_fields.size())
	reset()


func reset() -> void:
	rot.fill(0.0)
	x.fill(0.0)
	y.fill(0.0)
	sx.fill(1.0)
	sy.fill(1.0)
	face.fill(0.0)
	root_x = 0.0
	root_y = 0.0
	root_rot = 0.0
	pivot_x = 0.0
	pivot_y = 0.0
	root_sx = 1.0
	root_sy = 1.0
	props = 0
	flash = 0.0
	tint = 0.0
	shake_x = 0.0
	shake_y = 0.0
	hammer = 0.0
	facing = 1
	draw_order = 0


func copy_from(o: RigPose) -> void:
	for i in rot.size():
		rot[i] = o.rot[i]
		x[i] = o.x[i]
		y[i] = o.y[i]
		sx[i] = o.sx[i]
		sy[i] = o.sy[i]
	for i in face.size():
		face[i] = o.face[i]
	root_x = o.root_x
	root_y = o.root_y
	root_rot = o.root_rot
	pivot_x = o.pivot_x
	pivot_y = o.pivot_y
	root_sx = o.root_sx
	root_sy = o.root_sy
	props = o.props
	flash = o.flash
	tint = o.tint
	tint_color = o.tint_color
	shake_x = o.shake_x
	shake_y = o.shake_y
	hammer = o.hammer
	facing = o.facing
	draw_order = o.draw_order


## Moves this pose toward `o` by w (bones, root offsets and scales). Facing, props and the draw
## order are taken from `o` once w passes one half.
func blend_toward(o: RigPose, w: float) -> void:
	if w <= 0.0:
		return
	for i in rot.size():
		rot[i] = lerpf(rot[i], o.rot[i], w)
		x[i] = lerpf(x[i], o.x[i], w)
		y[i] = lerpf(y[i], o.y[i], w)
		sx[i] = lerpf(sx[i], o.sx[i], w)
		sy[i] = lerpf(sy[i], o.sy[i], w)
	root_x = lerpf(root_x, o.root_x, w)
	root_y = lerpf(root_y, o.root_y, w)
	root_rot = lerpf(root_rot, o.root_rot, w)
	pivot_x = lerpf(pivot_x, o.pivot_x, w)
	pivot_y = lerpf(pivot_y, o.pivot_y, w)
	root_sx = lerpf(root_sx, o.root_sx, w)
	root_sy = lerpf(root_sy, o.root_sy, w)
	flash = lerpf(flash, o.flash, w)
	tint = lerpf(tint, o.tint, w)
	shake_x = lerpf(shake_x, o.shake_x, w)
	shake_y = lerpf(shake_y, o.shake_y, w)
	hammer = lerpf(hammer, o.hammer, w)
	if w >= 0.5:
		facing = o.facing
		props = o.props
		draw_order = o.draw_order
