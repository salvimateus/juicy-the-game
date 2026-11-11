class_name RigFx
extends RefCounted
## Analytic FX in world space: every particle is a pure function of the age of the instance that
## spawned it. Instances and particles live in preallocated arrays; each frame the particles are
## written into two MultiMesh buffers (behind and in front of the character) that sample the
## shared rig atlas, snapped to the art grid.

enum Type { DUST, SMOKE, BURST, GHOST, SKID_CLOUD, SKID_TRAIL, LEDGE_DEBRIS, LEDGE_DUST, SPARK, CUSTOM }
const TYPE_NAMES := {"dust": Type.DUST, "smoke": Type.SMOKE, "burst": Type.BURST, "ghost": Type.GHOST, "skidCloud": Type.SKID_CLOUD, "skidTrail": Type.SKID_TRAIL, "ledgeDebris": Type.LEDGE_DEBRIS, "ledgeDust": Type.LEDGE_DUST, "spark": Type.SPARK, "custom": Type.CUSTOM}
const DEFAULT_LIFE := [0.4, 0.7, 0.8, 0.3, 0.7, 0.6, 1.2, 0.5, 0.26, 0.5]
enum Layer { BACK, FRONT }

const MAX_INSTANCES := 96
const MAX_PARTICLES := 160
const MAX_GHOSTS := 6
const FLOATS := 16  # Transform2D (8) + color (4) + custom data (4)

var rig: RigData
var art := float(RigConfig.ART_PIXEL)

# Instances.
var _type := PackedInt32Array()
var _active := PackedByteArray()
var _t0 := PackedFloat64Array()
var _life := PackedFloat32Array()
var _x := PackedFloat32Array()
var _y := PackedFloat32Array()
var _angle := PackedFloat32Array()
var _facing := PackedInt32Array()
var _seed := PackedInt32Array()
var _ground := PackedFloat32Array()
var _aux := PackedFloat32Array()  # 6 per instance
var _params: Array = []
var _next_seed := 13

# Particles of the current frame.
var count := 0
var _sprite := PackedInt32Array()
var _frame := PackedInt32Array()
var _layer := PackedInt32Array()
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _alpha := PackedFloat32Array()
var _sx := PackedFloat32Array()
var _sy := PackedFloat32Array()
var _rot := PackedFloat32Array()

# Ghost requests of the current frame (lag s, alpha).
var ghost_count := 0
var ghost_lag := PackedFloat32Array()
var ghost_alpha := PackedFloat32Array()

# Emitter state for the instance being emitted.
var e_x := 0.0
var e_y := 0.0
var e_angle := 0.0
var e_age := 0.0
var e_life := 1.0
var e_seed := 0
var e_facing := 1
var e_ground := 0.0
var e_index := 0

var _buffers: Array[PackedFloat32Array] = []
var _counts := PackedInt32Array([0, 0])
var _sprite_dust: int
var _sprite_smoke: int
var _sprite_debris: int


func _init(rig_data: RigData) -> void:
	rig = rig_data
	for arr in [_type, _facing, _seed]:
		arr.resize(MAX_INSTANCES)
	_active.resize(MAX_INSTANCES)
	_t0.resize(MAX_INSTANCES)
	for arr in [_life, _x, _y, _angle, _ground]:
		arr.resize(MAX_INSTANCES)
	_aux.resize(MAX_INSTANCES * 6)
	_params.resize(MAX_INSTANCES)
	for arr in [_sprite, _frame, _layer]:
		arr.resize(MAX_PARTICLES)
	for arr in [_px, _py, _alpha, _sx, _sy, _rot]:
		arr.resize(MAX_PARTICLES)
	ghost_lag.resize(MAX_GHOSTS)
	ghost_alpha.resize(MAX_GHOSTS)
	for i in 2:
		var buf := PackedFloat32Array()
		buf.resize(MAX_PARTICLES * FLOATS)
		_buffers.append(buf)
	_sprite_dust = rig.fx_sprite("dust").id
	_sprite_smoke = rig.fx_sprite("smoke").id
	_sprite_debris = rig.fx_sprite("debris").id


static func create_multimesh() -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.use_custom_data = true
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var quad := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)])
	arrays[Mesh.ARRAY_VERTEX] = quad
	arrays[Mesh.ARRAY_TEX_UV] = quad
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mm.mesh = mesh
	mm.instance_count = MAX_PARTICLES
	mm.visible_instance_count = 0
	return mm


func clear() -> void:
	_active.fill(0)


## Spawns an instance at a world point. params is the event dictionary (type params); aux carries
## per-type extra values.
func spawn(type_name: String, params: Dictionary, x: float, y: float, angle: float, facing: int, ground_y: float, now: float, aux := PackedFloat32Array()) -> void:
	var slot := _active.find(0)
	if slot < 0:
		return
	var t: int = TYPE_NAMES[type_name]
	_active[slot] = 1
	_type[slot] = t
	_t0[slot] = now
	_life[slot] = params.get("life", DEFAULT_LIFE[t])
	_x[slot] = x
	_y[slot] = y
	_angle[slot] = angle
	_facing[slot] = facing
	_ground[slot] = ground_y
	_seed[slot] = params.get("seed", _next_seed)
	_next_seed = (_next_seed * 7919 + 13) % 1000003
	_params[slot] = params
	for k in mini(aux.size(), 6):
		_aux[slot * 6 + k] = aux[k]


func update(now: float) -> void:
	count = 0
	ghost_count = 0
	for i in MAX_INSTANCES:
		if _active[i] == 0:
			continue
		var age := now - _t0[i]
		if age >= _life[i] or age < 0.0:
			_active[i] = 0
			continue
		e_x = _x[i]
		e_y = _y[i]
		e_angle = _angle[i]
		e_age = age
		e_life = _life[i]
		e_seed = _seed[i]
		e_facing = _facing[i]
		e_ground = _ground[i]
		e_index = i
		var ev: Dictionary = _params[i]
		match _type[i]:
			Type.DUST: _emit_dust(ev)
			Type.SMOKE: _emit_smoke(ev)
			Type.BURST: _emit_burst(ev)
			Type.GHOST: _emit_ghost(ev)
			Type.SKID_CLOUD: _emit_skid_cloud(ev)
			Type.SKID_TRAIL: _emit_skid_trail(ev)
			Type.LEDGE_DEBRIS: _emit_ledge_debris(ev)
			Type.LEDGE_DUST: _emit_ledge_dust(ev)
			Type.SPARK: _emit_spark(ev)
			# params.emit: Callable(fx: RigFx, ev: Dictionary) using the e_* state and add().
			Type.CUSTOM: (ev.emit as Callable).call(self, ev)


## Writes the particles into the two MultiMeshes, relative to `origin` (the drawing node's global
## position); positions snap to the art grid in world space.
func upload(back: MultiMesh, front: MultiMesh, origin: Vector2) -> void:
	_counts[0] = 0
	_counts[1] = 0
	var tex_size := rig.atlas.get_size()
	for i in count:
		var s: RigData.FxSprite = rig.fx_sprite_list[_sprite[i]]
		var variant := 0
		if s.steps > 1:
			variant = posmod(roundi(_rot[i] / s.rotation_step), s.steps)
		var idx := _frame[i] * s.steps + variant
		var region: Rect2 = s.regions[idx]
		var o: Vector2 = s.origins[idx]
		var scale_x := maxf(1.0, roundf(absf(_sx[i])))
		var scale_y := maxf(1.0, roundf(absf(_sy[i])))
		var flip := _sx[i] < 0.0
		var cell_x := roundf(_px[i] / art)
		var cell_y := roundf(_py[i] / art)
		var left := cell_x - ((region.size.x - o.x) if flip else o.x) * scale_x
		var top := cell_y - o.y * scale_y
		var layer := _layer[i]
		var buf := _buffers[layer]
		var b: int = _counts[layer] * FLOATS
		_counts[layer] += 1
		buf[b] = region.size.x * scale_x * art
		buf[b + 1] = 0.0
		buf[b + 2] = 0.0
		buf[b + 3] = left * art - origin.x
		buf[b + 4] = 0.0
		buf[b + 5] = region.size.y * scale_y * art
		buf[b + 6] = 0.0
		buf[b + 7] = top * art - origin.y
		buf[b + 8] = 1.0
		buf[b + 9] = 1.0
		buf[b + 10] = 1.0
		buf[b + 11] = _alpha[i]
		if flip:
			buf[b + 12] = region.end.x / tex_size.x
			buf[b + 14] = -region.size.x / tex_size.x
		else:
			buf[b + 12] = region.position.x / tex_size.x
			buf[b + 14] = region.size.x / tex_size.x
		buf[b + 13] = region.position.y / tex_size.y
		buf[b + 15] = region.size.y / tex_size.y
	back.buffer = _buffers[Layer.BACK]
	back.visible_instance_count = _counts[Layer.BACK]
	front.buffer = _buffers[Layer.FRONT]
	front.visible_instance_count = _counts[Layer.FRONT]


# ---------- emitter API ----------

func add(sprite: int, frame: int, x: float, y: float, alpha := 1.0, sx := 1.0, sy := 1.0, rot := 0.0, layer := Layer.FRONT) -> void:
	if count >= MAX_PARTICLES or alpha <= 0.02:
		return
	var s: RigData.FxSprite = rig.fx_sprite_list[sprite]
	var i := count
	count += 1
	_sprite[i] = sprite
	_frame[i] = clampi(frame, 0, s.frame_count - 1)
	_layer[i] = layer
	_px[i] = x
	_py[i] = y
	_alpha[i] = minf(alpha, 1.0)
	_sx[i] = sx
	_sy[i] = sy
	_rot[i] = rot


func ghost(lag: float, alpha: float) -> void:
	if ghost_count >= MAX_GHOSTS or alpha <= 0.02:
		return
	ghost_lag[ghost_count] = lag
	ghost_alpha[ghost_count] = alpha
	ghost_count += 1


func rand(k: int) -> float:
	return RigMath.hash01(e_seed, k)


func mirror_angle(a: float) -> float:
	return a if e_facing > 0 else PI - a


static func ballistic(x0: float, y0: float, vx: float, vy: float, gravity: float, t: float, has_floor: bool, floor_y: float, restitution: float, max_bounces := 3) -> Vector2:
	var x := x0
	var y := y0
	var dvx := vx
	var dvy := vy
	var time := t
	if has_floor and gravity > 0.0:
		for b in max_bounces + 1:
			var qa := gravity * 0.5
			var qc := y - floor_y
			var disc := dvy * dvy - 4.0 * qa * qc
			if disc < 0.0:
				break
			var s := (-dvy + sqrt(disc)) / (2.0 * qa)
			if s < 0.0 or s >= time:
				break
			x += dvx * s
			y = floor_y
			dvy = -(dvy + gravity * s) * restitution
			dvx *= 0.7
			time -= s
			if b == max_bounces:
				time = 0.0
				dvy = 0.0
	var out := Vector2(x + dvx * time, y + dvy * time + 0.5 * gravity * time * time)
	if has_floor and out.y > floor_y:
		out.y = floor_y
	return out


# Full opacity for most of the life, then two hard steps: reads as pixel art, not a blur.
static func stepped_alpha(k: float) -> float:
	return 1.0 if k < 0.6 else (0.66 if k < 0.82 else 0.33)


static func fade_end(k: float) -> float:
	return 1.0 if k < 0.75 else (1.0 - k) / 0.25


# ---------- types ----------

func _emit_dust(ev: Dictionary) -> void:
	var n: int = ev.get("count", 4)
	for i in n:
		var r1 := rand(i * 3)
		var r2 := rand(i * 3 + 1)
		var r3 := rand(i * 3 + 2)
		var life := e_life * (0.6 + 0.4 * r3)
		if e_age >= life:
			continue
		var k := e_age / life
		var dir: int = int(ev.get("dir", 0)) * e_facing
		var side := (-1 if r1 < 0.5 else 1) if dir == 0 else dir
		var speed: float = ev.get("speed", 34.0) * (0.5 + r2)
		var x: float = e_x + (r1 - 0.5) * ev.get("spread", 20.0) + side * speed * e_age * (1.0 - k * 0.5)
		var y: float = minf(e_ground, e_y - ev.get("rise", 20.0) * e_age * (0.6 + r3))
		add(_sprite_dust, int(k * 3.0), x, y, stepped_alpha(k))


func _emit_smoke(ev: Dictionary) -> void:
	var n: int = ev.get("count", 3)
	for i in n:
		var delay: float = i * ev.get("stagger", 0.06)
		var age := e_age - delay
		var life := e_life - delay
		if age < 0.0 or age >= life:
			continue
		var k := age / life
		var r := rand(i)
		var x: float = e_x + sin(k * 3.0 + r * 6.0) * 4.0 + (r - 0.5) * ev.get("spread", 6.0)
		var y: float = e_y - ev.get("rise", 40.0) * age
		add(_sprite_smoke, int(k * 3.0), x, y, stepped_alpha(k))


func _emit_burst(ev: Dictionary) -> void:
	var n: int = ev.get("count", 12)
	var sprite := rig.fx_sprite(ev.get("sprite", "confetti"))
	var frames := sprite.frame_count
	var has_floor: bool = ev.has("floor")
	var floor_y: float = e_ground + ev.get("floor", 0.0)
	for i in n:
		var r1 := rand(i * 4)
		var r2 := rand(i * 4 + 1)
		var r3 := rand(i * 4 + 2)
		var r4 := rand(i * 4 + 3)
		var life := e_life * (0.7 + 0.3 * r3)
		if e_age >= life:
			continue
		var k := e_age / life
		var angle: float = mirror_angle(ev.get("angle", -PI / 2.0)) + (r1 - 0.5) * ev.get("cone", PI)
		var speed: float = ev.get("speed", 200.0) * (0.5 + 0.7 * r2)
		var p := ballistic(e_x, e_y, cos(angle) * speed, sin(angle) * speed - ev.get("up", 0.0), ev.get("gravity", 600.0), e_age, has_floor, floor_y, ev.get("restitution", 0.4))
		var frame := int(k * frames) if ev.get("frames", "") == "age" else int(r4 * frames)
		var layer := Layer.BACK if ev.get("layer", "") == "back" else Layer.FRONT
		add(sprite.id, frame, p.x, p.y, (1.0 - k) / 0.3 if k > 0.7 else 1.0, 1.0, 1.0, ev.get("spin", 0.0) * e_age * (r4 - 0.5) * 2.0, layer)


func _emit_ghost(ev: Dictionary) -> void:
	var n: int = ev.get("count", 3)
	var fade := 1.0 - e_age / e_life
	for i in range(1, n + 1):
		ghost(i * ev.get("spacing", 0.04), ev.get("alpha", 0.45) * fade * (1.0 - float(i - 1) / n))


func _emit_skid_cloud(ev: Dictionary) -> void:
	var n: int = ev.get("count", 8)
	for i in n:
		var r1 := rand(i * 3)
		var r2 := rand(i * 3 + 1)
		var r3 := rand(i * 3 + 2)
		var life := e_life * (0.65 + 0.35 * r3)
		if e_age >= life:
			continue
		var k := e_age / life
		var travel: float = ev.get("speed", 80.0) * (0.4 + r2) * life * (1.0 - (1.0 - k) * (1.0 - k)) * 0.6
		var side: float = ev.get("dir", 1) * e_facing * (-0.4 if r1 < 0.2 else 1.0)
		var x: float = e_x + (r1 - 0.5) * ev.get("spread", 30.0) + side * travel
		var y: float = minf(e_ground, e_y - ev.get("rise", 30.0) * k * (0.5 + r3)) - 4.0
		var s := maxf(1.0, roundf((0.8 + ev.get("scale", 2.0) * k) * (0.8 + 0.4 * r2)))
		add(_sprite_dust, int(k * 3.0), x, y, fade_end(k), s, s, 0.0, Layer.BACK if r1 < 0.35 else Layer.FRONT)


# Skid trail slot: aux = [soleF x, soleF y, heelB x, heelB y, speed ratio, slot]; pebbles leave
# from the toe (instance position). The ground does not move in the game, so puffs stay put.
func _emit_skid_trail(ev: Dictionary) -> void:
	var a := e_index * 6
	var vk := _aux[a + 4]
	var slot := int(_aux[a + 5])
	var d := e_facing
	for k in 2:
		var r1 := RigMath.hash01(slot, k * 5)
		var r2 := RigMath.hash01(slot, k * 5 + 1)
		var r3 := RigMath.hash01(slot, k * 5 + 2)
		var life: float = ev.life * (0.55 + 0.45 * r3) * (0.5 + 0.5 * vk)
		if e_age >= life:
			continue
		var k2 := e_age / life
		var kick: float = d * ev.kick * vk * (0.4 + r1) * life * (1.0 - (1.0 - k2) * (1.0 - k2)) * 0.5
		var x: float = _aux[a + k * 2] + kick + (r2 - 0.5) * 10.0
		var y: float = minf(e_ground, _aux[a + k * 2 + 1] - ev.rise * k2 * (0.5 + r3))
		var s := maxf(1.0, roundf((0.7 + ev.grow * k2) * (0.6 + 0.6 * vk)))
		add(_sprite_dust, int(k2 * 3.0), x, y, fade_end(k2) * (0.6 + 0.4 * vk), s, s, 0.0, Layer.BACK if k else Layer.FRONT)
		if k == 0 and slot % int(ev.smokeEvery) == 0:
			var ks := minf(1.0, e_age / (life * 1.2))
			var ss := roundf(1.0 + 1.6 * ks)
			add(_sprite_smoke, int(ks * 3.0), x - d * 8.0, y - 10.0 - 18.0 * ks, 0.8 * fade_end(ks) * vk, ss, ss, 0.0, Layer.BACK)
	if slot % int(ev.pebbleEvery) == 0 and vk > 0.15 and e_age < 0.5:
		var r1 := RigMath.hash01(slot, 40)
		var r2 := RigMath.hash01(slot, 41)
		var vx: float = d * (ev.pebbleSpeed * (0.5 + r1) + ev.speed * vk * 0.4)
		var p := ballistic(e_x, e_y - 2.0, vx, -ev.pebbleUp * (0.5 + r2) * vk, ev.gravity, e_age, true, e_ground, 0.3)
		var kp := e_age / 0.5
		add(_sprite_debris, 0 if r2 < 0.5 else 1, p.x, p.y, (1.0 - kp) / 0.3 if kp > 0.7 else 1.0, 1.0, 1.0, e_age * 18.0 * (r1 - 0.5), Layer.BACK if r1 < 0.4 else Layer.FRONT)


func _emit_ledge_debris(ev: Dictionary) -> void:
	var n: int = ev.get("count", 8)
	var chip := rig.fx_sprite("ledgeChip").id
	for i in n:
		var r1 := rand(i * 4)
		var r2 := rand(i * 4 + 1)
		var r3 := rand(i * 4 + 2)
		var r4 := rand(i * 4 + 3)
		var age := e_age - r3 * 0.12
		if age < 0.0:
			continue
		var vx: float = ev.get("dir", -1) * e_facing * ev.get("speed", 60.0) * (0.2 + r2)
		var vy: float = -ev.get("speed", 60.0) * 0.6 * r4
		var p := ballistic(e_x + (r1 - 0.5) * ev.get("spread", 20.0), e_y, vx, vy, ev.get("gravity", 900.0), age, false, 0.0, 0.0)
		var fade := clampf((e_life - e_age) / 0.25, 0.0, 1.0)
		add(chip, int(r4 * 4.0), p.x, p.y, fade)


func _emit_ledge_dust(ev: Dictionary) -> void:
	var n: int = ev.get("count", 4)
	for i in n:
		var r1 := rand(i * 3)
		var r2 := rand(i * 3 + 1)
		var r3 := rand(i * 3 + 2)
		var life := e_life * (0.6 + 0.4 * r3)
		if e_age >= life:
			continue
		var k := e_age / life
		var side := -1.0 if r1 < 0.5 else 1.0
		var speed: float = ev.get("speed", 30.0) * (0.5 + r2)
		var x: float = e_x + (r1 - 0.5) * ev.get("spread", 20.0) + side * speed * e_age * (1.0 - k * 0.5)
		var y: float = e_y - ev.get("rise", 14.0) * e_age * (0.6 + r3)
		add(_sprite_dust, int(k * 3.0), x, y, 0.9 * (1.0 - k * k))


# Radial sparks with gravity plus an optional star pop. ev: count, speed, gravity, angle, cone, star.
func _emit_spark(ev: Dictionary) -> void:
	var n: int = ev.get("count", 8)
	var spark := rig.fx_sprite("spark").id
	var k := e_age / e_life
	for i in n:
		var angle: float = mirror_angle(ev.get("angle", 0.0)) + (rand(i * 2) - 0.5) * ev.get("cone", TAU)
		var speed: float = ev.get("speed", 260.0) * (0.5 + rand(i * 2 + 1) * 0.7)
		var x := e_x + cos(angle) * speed * e_age
		var y: float = e_y + sin(angle) * speed * e_age + 0.5 * ev.get("gravity", 400.0) * e_age * e_age
		add(spark, 0 if k < 0.5 else 1, x, y, 1.0 if k < 0.7 else (1.0 - k) / 0.3, 1.0, 1.0, angle)
	if ev.get("star", true):
		var star_life: float = ev.get("starLife", 0.16)
		if e_age < star_life:
			var ks := e_age / star_life
			add(rig.fx_sprite("star").id, 0 if ks < 0.4 else 1, e_x, e_y, 1.0 - ks * ks, 1.0, 1.0, ks * 0.6)
