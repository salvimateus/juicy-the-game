extends Node2D

# Ricochet sparks on the art grid: a short star flash at the contact and a fan of hot sparks
# along the outgoing direction that cool from white to red as they fall. One node per scene draws
# every burst in a single canvas item (capped by max_sparks).

const GameScale := preload("res://game/game_scale.gd")

const COLORS := [Color("#ffffff"), Color("#fff3b0"), Color("#ffd040"), Color("#f08a24"), Color("#b0401c")]

var max_sparks := 160
var max_flashes := 12
var spark_count := Vector2i(9, 15)
var spark_speed := Vector2(450.0, 1400.0)
# Half angle of the fan around the outgoing direction; a few sparks spray along the surface.
var spark_spread := 0.7
var spark_life := Vector2(0.14, 0.38)
var spark_gravity := 1700.0
var spark_drag := 2.5
var flash_time := 0.09
var flash_arm := 4

# Each spark: [position, velocity, life left, life]; each flash: [position, time left].
var _sparks: Array = []
var _flashes: Array = []
var _a := 6.0


func _ready() -> void:
	top_level = true
	z_index = 7
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_a = float(GameScale.art_pixel())
	set_process(false)


func burst(point: Vector2, normal: Vector2, out_dir: Vector2, strength: float) -> void:
	var s := clampf(strength, 0.2, 1.2)
	var n := roundi(lerpf(spark_count.x, spark_count.y, clampf(s, 0.0, 1.0)))
	for i in n:
		if _sparks.size() >= max_sparks:
			_sparks.pop_front()
		# Two in three follow the bounce, the rest skid along the face.
		var base := out_dir if i % 3 != 2 else normal.orthogonal() * (1.0 if randf() < 0.5 else -1.0)
		var v := base.rotated(randf_range(-spark_spread, spark_spread)) * randf_range(spark_speed.x, spark_speed.y) * lerpf(0.6, 1.0, s)
		var life := randf_range(spark_life.x, spark_life.y)
		_sparks.append([point + normal * _a * 0.5, v, life, life])
	if _flashes.size() >= max_flashes:
		_flashes.pop_front()
	_flashes.append([point, flash_time])
	set_process(true)


func _process(delta: float) -> void:
	var drag := exp(-spark_drag * delta)
	for sp in _sparks:
		sp[1] = sp[1] * drag
		sp[1].y += spark_gravity * delta
		sp[0] += sp[1] * delta
		sp[2] -= delta
	_sparks = _sparks.filter(func(sp): return sp[2] > 0.0)
	for f in _flashes:
		f[1] -= delta
	_flashes = _flashes.filter(func(f): return f[1] > 0.0)
	queue_redraw()
	if _sparks.is_empty() and _flashes.is_empty():
		set_process(false)


func _snap(p: Vector2) -> Vector2:
	return (p / _a).floor() * _a


func _draw() -> void:
	var cell := Vector2(_a, _a)
	for f in _flashes:
		var c := _snap(f[0])
		var big: bool = f[1] > flash_time * 0.5
		var arm := flash_arm if big else 1
		draw_rect(Rect2(c, cell), COLORS[0])
		for k in range(1, arm + 1):
			var col: Color = COLORS[1] if k < arm or not big else COLORS[2]
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_rect(Rect2(c + d * k * _a, cell), col)
		if big:
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_rect(Rect2(c + d * _a, cell), COLORS[2])
	for sp in _sparks:
		var t: float = 1.0 - sp[2] / sp[3]
		var k := mini(int(t * (COLORS.size() - 1)), COLORS.size() - 2)
		var head := _snap(sp[0])
		draw_rect(Rect2(head, cell), COLORS[k])
		var v: Vector2 = sp[1]
		if v.length_squared() > 250000.0:
			# Fast sparks leave a one-cell streak behind them.
			var tail := _snap(sp[0] - v.normalized() * _a * 1.5)
			if tail != head:
				draw_rect(Rect2(tail, cell), COLORS[k + 1])
