extends Node2D

# River crossing with a stone dam on its right bank and a valley beyond it. Its own terrain spans
# x = TERRAIN_X0..TERRAIN_X1 with ground level y = 0 at both ends (local units, y down), so a level
# replaces its ground on that span with this scene. A button on the dam top opens a hole in the
# dam (the plug's collider goes away, the WaterBody re-reads the colliders and the water jets into
# the valley); a second one closes it, refills the river and puts every PushCrate child back. The
# crates on the left bank are placed in river.tscn, spaced so the player fits between them.

signal hole_opened
signal refilled

const Art := preload("res://game/water/water_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const Feedback := preload("res://game/feedback.gd")
const Particles := preload("res://game/water/water_particles.gd")
const BUTTON_PATH := "res://game/interactables/reset_button.tscn"

const TERRAIN_X0 := -1200.0
const TERRAIN_X1 := 3300.0
const TERRAIN_TOP := -96.0
const TERRAIN_BOTTOM := 1800.0
const DOMAIN := Rect2(-120, -288, 3216, 1200)
const WATER_LEVEL := 36.0
const RIVER_X0 := 0.0
const RIVER_X1 := 1680.0

const DAM_X0 := 1680.0
const DAM_X1 := 1872.0
const DAM_TOP := -72.0
const DAM_BASE := 600.0
# Low step on the river side of the dam top, so a swimmer can climb out.
const NOTCH_X1 := 1740.0
const NOTCH_TOP := 0.0
const HOLE_TOP := 120.0
const HOLE_BOTTOM := 324.0

# [x0, x1, top, kind]; dam carries the y where its buried dirt starts.
const SEGMENTS := [
	[-1200.0, 0.0, 0.0, &"grass"],
	[0.0, 96.0, 132.0, &"bed"],
	[96.0, 216.0, 240.0, &"bed"],
	[216.0, 420.0, 384.0, &"bed"],
	[420.0, 660.0, 528.0, &"bed"],
	[660.0, 1080.0, 720.0, &"bed"],
	[1080.0, 1320.0, 540.0, &"bed"],
	[1320.0, 1680.0, 468.0, &"bed"],
	[1680.0, 1872.0, -72.0, &"dam", 552.0],
	[1872.0, 1956.0, 552.0, &"valley"],
	[1956.0, 2016.0, 588.0, &"valley"],
	[2016.0, 2076.0, 624.0, &"valley"],
	[2076.0, 2136.0, 660.0, &"valley"],
	[2136.0, 2232.0, 780.0, &"valley"],
	[2232.0, 2292.0, 696.0, &"valley"],
	[2292.0, 2352.0, 732.0, &"valley"],
	[2352.0, 2412.0, 768.0, &"valley"],
	[2412.0, 2472.0, 804.0, &"valley"],
	[2472.0, 2700.0, 864.0, &"valley"],
	[2700.0, 2748.0, 768.0, &"valley"],
	[2748.0, 2796.0, 672.0, &"valley"],
	[2796.0, 2844.0, 576.0, &"valley"],
	[2844.0, 2892.0, 480.0, &"valley"],
	[2892.0, 2940.0, 384.0, &"valley"],
	[2940.0, 2988.0, 288.0, &"valley"],
	[2988.0, 3036.0, 192.0, &"valley"],
	[3036.0, 3084.0, 96.0, &"valley"],
	[3084.0, 3300.0, 0.0, &"grass"],
]

# Underwater decor: [x, floor y, height art px] kelp; [x, floor y, w, h] rocks.
const KELP := [
	[300.0, 384.0, 9], [450.0, 528.0, 12], [600.0, 528.0, 16], [690.0, 720.0, 26], [762.0, 720.0, 18],
	[906.0, 720.0, 30], [1008.0, 720.0, 22], [1050.0, 720.0, 14], [1122.0, 540.0, 14],
	[1254.0, 540.0, 20], [1404.0, 468.0, 10], [1566.0, 468.0, 15],
]
const ROCKS := [
	[240.0, 384.0, 7, 4], [504.0, 528.0, 8, 5], [726.0, 720.0, 12, 7], [966.0, 720.0, 9, 6],
	[1182.0, 540.0, 14, 8], [1482.0, 468.0, 10, 6], [2580.0, 864.0, 11, 6],
]
const CRYSTALS_AT := Vector2(840.0, 720.0)

# Solid earth and the dam are drawn in front of the character (absolute z, the band of the level
# ground) so any body part that pushes into them is hidden; the water (40) stays above them.
const SOLID_Z := 35
const BACK_Z := -2
const DECOR_Z := -1

const OPEN_BUTTON_X := 1830.0
const RESET_BUTTON_X := 1770.0

var water: WaterBody
var hole_open := false
var open_button: Node2D
var reset_button: Node2D

var _dam_sprite: Sprite2D
var _hole_back: Sprite2D
var _plug_shape: CollisionShape2D
var _kelp: Array[Sprite2D] = []
var _kelp_frames: Array = []
var _kelp_t := 0.0
var _debris: Particles
var _rng := RandomNumberGenerator.new()
var _busy := false


func _ready() -> void:
	_rng.seed = 2207
	var a := GameScale.art_pixel()
	_build_terrain(a)
	_build_dam(a)
	_build_decor(a)
	water = WaterBody.new()
	water.name = "Water"
	water.domain = DOMAIN
	add_child(water)
	water.fill_level(to_global(Vector2(RIVER_X0, 0)).x, to_global(Vector2(RIVER_X1, 0)).x, to_global(Vector2(0, WATER_LEVEL)).y)
	water.rasterized.connect(water.store_rest_state, CONNECT_ONE_SHOT)
	_debris = Particles.new()
	_debris.name = "Debris"
	_debris.z_as_relative = false
	_debris.z_index = 39
	add_child(_debris)
	_debris.setup(120, PackedColorArray([Color("#8a7676"), Color("#b39a94"), Color("#6e5c5c"), Color("#967e79")]))
	_build_buttons()


func is_ready() -> bool:
	return water != null and water.is_ready()


func open_hole() -> void:
	if hole_open or _busy or not is_ready():
		return
	_busy = true
	hole_open = true
	_set_buttons()
	var a := GameScale.art_pixel()
	_dam_sprite.texture = _dam_texture(a, true)
	_hole_back.visible = true
	_plug_shape.set_deferred(&"disabled", true)
	var center := to_global(Vector2((DAM_X0 + DAM_X1) * 0.5, (HOLE_TOP + HOLE_BOTTOM) * 0.5))
	Feedback.sfx(&"dam_break", center, 1.0)
	Feedback.haptic(&"dam_break", 1.0)
	_spawn_debris()
	await get_tree().physics_frame
	await get_tree().physics_frame
	water.rasterize(_hole_rect_global())
	water.emit_bubbles(to_global(Vector2(DAM_X0 - 30, HOLE_BOTTOM - 30)), 14, Vector2(-80, -40))
	_busy = false
	hole_opened.emit()


func refill() -> void:
	if not hole_open or _busy:
		return
	_busy = true
	for c in get_tree().get_nodes_in_group(&"push_crate"):
		if is_ancestor_of(c) and c.has_method(&"reset_to_start"):
			c.reset_to_start()
	hole_open = false
	_set_buttons()
	var a := GameScale.art_pixel()
	_dam_sprite.texture = _dam_texture(a, false)
	_hole_back.visible = false
	_plug_shape.set_deferred(&"disabled", false)
	_debris.clear()
	water.restore_rest_state(0.7)
	Feedback.sfx(&"splash", to_global(Vector2((RIVER_X0 + RIVER_X1) * 0.5, WATER_LEVEL)), 0.7)
	await get_tree().physics_frame
	await get_tree().physics_frame
	water.rasterize(_hole_rect_global())
	_busy = false
	refilled.emit()


func _hole_rect_global() -> Rect2:
	return Rect2(to_global(Vector2(DAM_X0 - 12, HOLE_TOP - 12)), Vector2(DAM_X1 - DAM_X0 + 24, HOLE_BOTTOM - HOLE_TOP + 24))


func _physics_process(delta: float) -> void:
	_step_debris(delta)


func _process(delta: float) -> void:
	_kelp_t += delta
	for i in _kelp.size():
		var f := int(_kelp_t * 1.6 + i * 0.37) % 2
		var frames: Array = _kelp_frames[i]
		if _kelp[i].texture != frames[f]:
			_kelp[i].texture = frames[f]
	if _debris.count > 0:
		_debris.flush()


# --- Build ----------------------------------------------------------------------------------------

func _build_terrain(a: int) -> void:
	var layers := Art.terrain(SEGMENTS, TERRAIN_X0, TERRAIN_X1, TERRAIN_TOP, TERRAIN_BOTTOM, a)
	for i in 2:
		var sprite := Sprite2D.new()
		sprite.name = "Terrain" if i == 0 else "TerrainBackdrop"
		sprite.texture = layers[i]
		sprite.centered = false
		sprite.position = Vector2(TERRAIN_X0, TERRAIN_TOP)
		sprite.scale = Vector2(a, a)
		if i == 0:
			_front(sprite)
		else:
			sprite.z_index = BACK_Z
		add_child(sprite)
	for seg in SEGMENTS:
		if seg[3] == &"dam":
			continue
		var surface := &"grass" if seg[3] == &"grass" else (&"dirt" if seg[3] == &"valley" else &"stone")
		_add_body(Rect2(seg[0], seg[2], seg[1] - seg[0], TERRAIN_BOTTOM - seg[2]), surface)


func _build_dam(a: int) -> void:
	_dam_sprite = Sprite2D.new()
	_dam_sprite.name = "Dam"
	_dam_sprite.texture = _dam_texture(a, false)
	_dam_sprite.centered = false
	_dam_sprite.position = Vector2(DAM_X0, DAM_TOP)
	_dam_sprite.scale = Vector2(a, a)
	_front(_dam_sprite)
	add_child(_dam_sprite)
	_hole_back = Sprite2D.new()
	_hole_back.name = "DamHoleBack"
	_hole_back.texture = Art.dam_hole(int((DAM_X1 - DAM_X0) / a), int((HOLE_BOTTOM - HOLE_TOP) / a))
	_hole_back.centered = false
	_hole_back.position = Vector2(DAM_X0, HOLE_TOP)
	_hole_back.scale = Vector2(a, a)
	_hole_back.z_index = BACK_Z
	_hole_back.visible = false
	add_child(_hole_back)
	_add_body(Rect2(DAM_X0, NOTCH_TOP, NOTCH_X1 - DAM_X0, HOLE_TOP - NOTCH_TOP), &"stone")
	_add_body(Rect2(NOTCH_X1, DAM_TOP, DAM_X1 - NOTCH_X1, HOLE_TOP - DAM_TOP), &"stone")
	_add_body(Rect2(DAM_X0, HOLE_BOTTOM, DAM_X1 - DAM_X0, TERRAIN_BOTTOM - HOLE_BOTTOM), &"stone")
	var plug := _add_body(Rect2(DAM_X0, HOLE_TOP, DAM_X1 - DAM_X0, HOLE_BOTTOM - HOLE_TOP), &"stone")
	plug.name = "DamPlug"
	_plug_shape = plug.get_child(0)


func _dam_texture(a: int, broken: bool) -> ImageTexture:
	var w := int((DAM_X1 - DAM_X0) / a)
	var h := int((DAM_BASE - DAM_TOP) / a)
	var notch := Vector2i(int((NOTCH_X1 - DAM_X0) / a), int((NOTCH_TOP - DAM_TOP) / a))
	var waterline := int((WATER_LEVEL - DAM_TOP) / a)
	var hole := Rect2i(0, int((HOLE_TOP - DAM_TOP) / a), w, int((HOLE_BOTTOM - HOLE_TOP) / a)) if broken else Rect2i()
	return Art.dam(w, h, notch, waterline, hole)


func _add_body(r: Rect2, surface: StringName) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.set_meta(&"surface", surface)
	body.position = r.position
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	shape.shape = rect
	shape.position = r.size * 0.5
	body.add_child(shape)
	add_child(body)
	return body


func _build_decor(a: int) -> void:
	var seed := 0
	for k in KELP:
		seed += 1
		var frames := [Art.kelp(k[2], 0, seed), Art.kelp(k[2], 1, seed)]
		var s := _decor_sprite(frames[0], k[0], k[1], a)
		_kelp.append(s)
		_kelp_frames.append(frames)
	for r in ROCKS:
		seed += 1
		_decor_sprite(Art.rock(r[2], r[3], seed), r[0], r[1], a)
	_decor_sprite(Art.crystals(), CRYSTALS_AT.x, CRYSTALS_AT.y, a)


func _decor_sprite(tex: Texture2D, x: float, floor_y: float, a: int) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.scale = Vector2(a, a)
	s.position = Vector2(snappedf(x - tex.get_width() * a * 0.5, a), floor_y - tex.get_height() * a)
	s.z_index = DECOR_Z
	add_child(s)
	return s


func _front(item: CanvasItem) -> void:
	item.z_as_relative = false
	item.z_index = SOLID_Z


func _build_buttons() -> void:
	if not ResourceLoader.exists(BUTTON_PATH):
		push_warning("river: %s is missing, the dam has no buttons" % BUTTON_PATH)
		return
	var scene := load(BUTTON_PATH) as PackedScene
	open_button = scene.instantiate()
	open_button.name = "OpenHoleButton"
	open_button.set(&"prompt", "Abrir o buraco")
	open_button.position = Vector2(OPEN_BUTTON_X, DAM_TOP)
	add_child(open_button)
	reset_button = scene.instantiate()
	reset_button.name = "RefillButton"
	reset_button.set(&"prompt", "Encher o rio de novo")
	reset_button.position = Vector2(RESET_BUTTON_X, DAM_TOP)
	add_child(reset_button)
	if open_button.has_signal(&"pressed"):
		open_button.connect(&"pressed", open_hole)
	if reset_button.has_signal(&"pressed"):
		reset_button.connect(&"pressed", refill)
	_set_buttons()


func _set_buttons() -> void:
	if open_button:
		open_button.set(&"enabled", not hole_open)
	if reset_button:
		reset_button.set(&"enabled", hole_open)


# --- Debris ---------------------------------------------------------------------------------------

func _spawn_debris() -> void:
	for i in 56:
		var x := _rng.randf_range(DAM_X0 + 6, DAM_X1 - 6)
		var y := _rng.randf_range(HOLE_TOP, HOLE_BOTTOM - 6)
		var left := _rng.randf() < 0.15
		var vx := -_rng.randf_range(80.0, 300.0) if left else _rng.randf_range(250.0, 1100.0)
		var size := 1 if _rng.randf() < 0.6 else (2 if _rng.randf() < 0.75 else 3)
		_debris.spawn(x, y, vx, -_rng.randf_range(60.0, 520.0), 30.0, size, _rng.randi_range(0, 3))


func _step_debris(delta: float) -> void:
	if _debris.count == 0:
		return
	var a := float(GameScale.art_pixel())
	for i in _debris.count:
		var x := _debris.px[i]
		var y := _debris.py[i]
		var gp := to_global(Vector2(x, y))
		var wet := water.is_point_in_water(gp)
		var g := 2600.0 * (0.35 if wet else 1.0)
		if wet:
			var drag := 1.0 - 3.0 * delta
			_debris.vx[i] *= drag
			_debris.vy[i] *= drag
			_debris.vx[i] += water.get_flow_at(gp).x * 1.5 * delta
		_debris.vy[i] += g * delta
		x += _debris.vx[i] * delta
		y += _debris.vy[i] * delta
		var size := float(_debris.size_px[i]) * a
		var floor_y := to_local(Vector2(0, water.get_floor_y(to_global(Vector2(x, 0)).x))).y
		if x > DAM_X0 and x < DAM_X1:
			floor_y = HOLE_BOTTOM
		if y + size > floor_y:
			y = floor_y - size
			_debris.vy[i] *= -0.25
			_debris.vx[i] *= 0.55
			if absf(_debris.vy[i]) < 80.0:
				_debris.vy[i] = 0.0
		_debris.px[i] = x
		_debris.py[i] = y
