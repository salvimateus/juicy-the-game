extends Node2D

# Fast turret round with a pixel tracer. Each physics step it sweeps the segment it travelled
# against the target's body box; on overlap it calls hurt(&"shot") once, and when that returns
# false (dodge, roll, mercy time) the round keeps flying through. Other solids are ignored, but a
# ricochet surface (meta ricochet) mirrors it, and the tracer bends around the bounce.

const Interactable := preload("res://game/interactables/interactable.gd")
const GameScale := preload("res://game/game_scale.gd")
const Ricochet := preload("res://game/ricochet/ricochet.gd")

signal hit(target: Node, landed: bool)

const TRAIL_COLORS := [Color("#fff6d0"), Color("#ffd860"), Color("#f09030"), Color("#c04a28"), Color("#6e2a20")]

var direction := Vector2.LEFT
var speed := 4200.0
var max_distance := 2600.0
var target: Node2D
var strength := 1.0
var origin := Vector2.ZERO
var max_ricochets := 2
var ricochet_strength := 0.8
var world_mask := 1
var ricochets := 0
# Bounce points, oldest first (the tracer walks back through them).
var _path := PackedVector2Array()
var _ray := PhysicsRayQueryParameters2D.new()
var _head := Vector2.ZERO
var _travelled := 0.0
var _tested := false
var _spark := -1.0
var _a := 6.0


func _ready() -> void:
	top_level = true
	z_index = 50
	global_position = Vector2.ZERO
	_a = GameScale.art_pixel()
	_head = origin


func _physics_process(delta: float) -> void:
	if _spark >= 0.0:
		_spark += delta
		if _spark > 0.12:
			queue_free()
		queue_redraw()
		return
	var step := direction * speed * delta
	var from := _head
	var corner := from
	var to := from + step
	if ricochets < max_ricochets:
		_ray.from = from
		_ray.to = to
		_ray.collision_mask = world_mask
		var w := get_world_2d().direct_space_state.intersect_ray(_ray)
		if not w.is_empty() and Ricochet.is_surface(w.collider):
			var n := Ricochet.normal_of(w.normal, direction)
			var out := Ricochet.deflect(direction, n)
			corner = w.position
			Ricochet.impact(corner, n, out, ricochet_strength, &"bullet", w.collider)
			ricochets += 1
			_path.append(corner)
			direction = out
			to = corner + n * Ricochet.CLEARANCE + out * maxf(0.0, step.length() - from.distance_to(corner))
			# A new line: it may catch the target it missed on the way in.
			_tested = false
	_head = to
	_travelled += step.length()
	var hits := false
	if not _tested and is_instance_valid(target):
		var r := Interactable.body_rect(target)
		hits = _segment_hits(corner, _head, r) or (corner != from and _segment_hits(from, corner, r))
	if hits:
		_tested = true
		var landed := Interactable.hurt(target, &"shot", origin, direction, strength)
		hit.emit(target, landed)
		if landed:
			_spark = 0.0
	if _travelled >= max_distance:
		queue_free()
	queue_redraw()


static func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var n := int(ceilf(a.distance_to(b) / 12.0)) + 1
	for i in n + 1:
		if r.has_point(a.lerp(b, float(i) / n)):
			return true
	return false


func _draw() -> void:
	var cell := Vector2(_a, _a)
	if _spark >= 0.0:
		var c := (_head / _a).floor() * _a
		for d in [Vector2(0, 0), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(-2, 0), Vector2(2, 0)]:
			draw_rect(Rect2(c + d * _a * (1.0 + _spark * 8.0), cell), TRAIL_COLORS[1 if d == Vector2.ZERO else 2])
		return
	# Tracer: head two texels thick, tail cooling down over ~30 art px.
	var length := minf(30.0, _travelled / _a)
	for i in int(length):
		var p := _trail_point(i * _a)
		var q: Vector2 = (p / _a).floor() * _a
		var k: int = mini(i * TRAIL_COLORS.size() / maxi(1, int(length)), TRAIL_COLORS.size() - 1)
		var col: Color = TRAIL_COLORS[k]
		col.a = 1.0 - 0.6 * float(i) / length
		draw_rect(Rect2(q, cell), col)
		if i < 3:
			draw_rect(Rect2(q + Vector2(0, -_a), cell), TRAIL_COLORS[0])


# Point `d` source px back along the flight path (through the bounces) from the head.
func _trail_point(d: float) -> Vector2:
	var p := _head
	for i in range(_path.size() - 1, -2, -1):
		var q: Vector2 = _path[i] if i >= 0 else origin
		var seg := p.distance_to(q)
		if d <= seg:
			return p.move_toward(q, d)
		d -= seg
		p = q
	return p
