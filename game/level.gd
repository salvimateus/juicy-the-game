extends Node2D

# Phase 1 test level, built from the layout below. Units are source px (6 per art pixel);
# y = 0 is the main ground and negative is up. Every value is a multiple of the art pixel.

const PixelArt := preload("res://game/pixel_art.gd")
const GameScale := preload("res://game/game_scale.gd")
const LedgeScript := preload("res://game/ledge.gd")
# User ground art (res://game/art/ground.json): grass tops per 330-unit column and dirt rows.
const GROUND_JSON := "res://game/art/ground.json"
const GROUND_SEED := 1729
# Draw order with the fog: background -20..-17, back fog -3, grass 0, player 1, effects 2..6,
# front fog 30, ground dirt 31 (it hides the front fog's straight bottom edge), water 40.
const GROUND_DIRT_Z := 31
const BACKGROUND_Z := -20
# User background (res://game/art/background/background.json): screen-fixed sky, drifting clouds,
# two mountain planes, fog and mist with horizontal and vertical parallax.
const BACKGROUND_JSON := "res://game/art/background/background.json"
const CloudLayer := preload("res://game/cloud_layer.gd")
# Extra solid colour under the mist, for views that drop below the ground line.
const MIST_BASE_DEPTH := 4000.0
# Scenes placed on the area slot markers (origin on the floor).
const SLOT_SCENES := {
	"Chair": "res://game/interactables/chair.tscn",
	"Scarecrow": "res://game/targets/scarecrow.tscn",
	"CupTable": "res://game/targets/cup_range.tscn",
	"BalloonLauncher": "res://game/targets/balloon_launcher.tscn",
	# Shooting range targets: scarecrows until dedicated range targets exist.
	"TargetNear": "res://game/targets/scarecrow.tscn",
	"TargetMid": "res://game/targets/scarecrow.tscn",
	"TargetFar": "res://game/targets/scarecrow.tscn",
	"Bed": "res://game/interactables/bed.tscn",
	"DamageTrap": "res://game/interactables/damage_trap.tscn",
	"Turret": "res://game/interactables/turret.tscn",
	"BreakableWall": "res://game/breakable/breakable_wall.tscn",
}
# Punching bag in the Boxing area (punches), in front of the breakable wall (kicks).
const PUNCHING_BAG_X := 23500.0
const TUNNEL_CEILING := preload("res://game/art/tunnel_ceiling.png")
const TUNNEL_WALL := preload("res://game/art/tunnel_wall.png")
const TUNNEL_FLOOR := preload("res://game/art/tunnel_floor.png")
# Anchors from pecas_extra/props.json (source px inside each image).
const TUNNEL_CEILING_EDGE_Y := 88.0
const TUNNEL_FLOOR_SURFACE_Y := 9.0

const LENGTH := 42000.0
const WALL_THICKNESS := 600.0
const WALL_HEIGHT := 4800.0
const DIRT_DEPTH := 1800.0
const SPAWN := Vector2(600, 0)

# Low tunnel: crawl only. Ceiling edge y (crouched body fits, standing does not) and mouth frames.
const TUNNEL_X0 := 19000.0
const TUNNEL_X1 := 20600.0
# Default ceiling edge; build() lowers or raises it to clear the crouched body by TUNNEL_CLEARANCE.
const TUNNEL_CEILING_Y := -240.0
const TUNNEL_CLEARANCE := 24.0
const TUNNEL_TOP_Y := -2400.0
const TUNNEL_FRAME_WIDTH := 96.0

# Test pool for swimming (provisional water from res://game/water_stub until the river lands).
# River crossing (res://game/water/river.tscn): its own terrain spans RIVER_X + TERRAIN_X0..X1
# with the ground at y = 0 on both ends, so the level ground stops there.
const RIVER_SCENE := "res://game/water/river.tscn"
const RIVER_X := 37800.0
const RIVER_TERRAIN_X0 := -240.0
const RIVER_TERRAIN_X1 := 3300.0
const CameraZoneScript := preload("res://game/camera_zone.gd")
# Camera inside the river zone: centre at least this low, view bottom at the water domain bottom.
const RIVER_CAMERA_CENTER_Y := 260.0
const RIVER_CAMERA_BOTTOM := 960.0

# [x0, x1, floor y, surface]
const GROUND := [
	[-WALL_THICKNESS, 6900.0, 0.0, &"grass"],
	[6900.0, 7500.0, 180.0, &"grass"],
	[7500.0, TUNNEL_X0, 0.0, &"grass"],
	[TUNNEL_X0, TUNNEL_X1, 0.0, &"dirt"],
	[TUNNEL_X1, RIVER_X + RIVER_TERRAIN_X0, 0.0, &"grass"],
	[RIVER_X + RIVER_TERRAIN_X1, LENGTH + WALL_THICKNESS, 0.0, &"grass"],
]

# [x0, x1, top y, thickness (0 = down to the ground), grabbable corners "L"/"R", climbable walls]
const BLOCKS := [
	# Steps.
	[4800.0, 6600.0, -96.0, 0.0, ""],
	[5100.0, 6300.0, -192.0, 0.0, ""],
	[5400.0, 6000.0, -288.0, 0.0, ""],
	# Isolated wall at ground level, too tall to step on: push.
	[6804.0, 6900.0, -288.0, 0.0, ""],
	# Platforms: a low box, two grab-only platforms and a low floating one.
	[8100.0, 8600.0, -180.0, 0.0, ""],
	[9000.0, 9600.0, -738.0, 96.0, "LR"],
	[9900.0, 10400.0, -600.0, 96.0, "LR"],
	[10700.0, 11100.0, -210.0, 72.0, ""],
	# Tower: each tier is reached by grabbing the edge and climbing.
	[11400.0, 13000.0, -540.0, 0.0, "L"],
	[12000.0, 13000.0, -1080.0, 0.0, "L"],
	[12600.0, 13000.0, -1620.0, 0.0, "LR"],
	[13400.0, 13800.0, -1260.0, 96.0, "LR"],
	# Twin towers facing each other across a gap: ledge_leap from one ledge to the other.
	[14000.0, 14600.0, -900.0, 0.0, "R"],
	[15200.0, 15800.0, -900.0, 0.0, "L"],
	# Tall climbable column (zigzag wall jumps) with a reward on top.
	[16400.0, 16640.0, -1800.0, 0.0, "LR", true],
	# Narrow well: two climbable walls facing each other, bounce up between them.
	[17400.0, 17640.0, -1800.0, 0.0, "LR", true],
	[18072.0, 18312.0, -1800.0, 0.0, "LR", true],
]

# Rewards on top of the wall challenges: [x, y].
# Near the far edge of each top, so the player arrives beside the pole instead of in front of it.
const REWARDS := [
	[16600.0, -1800.0],
	[18272.0, -1800.0],
]

# Training areas on flat ground after the tunnel, off the platforming route. Each area is a Node2D
# under TrainingAreas with Bounds (x0..x1) and one Marker2D per object slot: [name, x, footprint].
# PlayerStart marks where the player stands to use the area (shooting distance, approach run).
const AREAS := [
	["Rest", 21000.0, 22600.0, [["PlayerStart", 21200.0, 0.0], ["Chair", 21600.0, 300.0], ["Bed", 22150.0, 500.0]]],
	["Boxing", 22800.0, 24600.0, [["PlayerStart", 23000.0, 0.0], ["BreakableWall", 24100.0, 240.0]]],
	["Kunai", 24800.0, 27000.0, [["PlayerStart", 25100.0, 0.0], ["Scarecrow", 26300.0, 240.0]]],
	# The balloon launcher stands past the cup table, with open sky above it.
	["Bow", 27200.0, 30600.0, [["PlayerStart", 27500.0, 0.0], ["CupTable", 29100.0, 480.0], ["BalloonLauncher", 30100.0, 240.0]]],
	["ShootingRange", 30800.0, 34000.0, [["PlayerStart", 31100.0, 0.0], ["TargetNear", 32500.0, 120.0], ["TargetMid", 33100.0, 120.0], ["TargetFar", 33700.0, 120.0]]],
	# The trap spans x -96..+576 around its origin; the turret's button sits 540 to its facing
	# side (-1), so they do not overlap.
	["Danger", 34200.0, 36400.0, [["PlayerStart", 34300.0, 0.0], ["DamageTrap", 34500.0, 672.0], ["Turret", 36100.0, 240.0]]],
]

# Steel ricochet surfaces (res://game/ricochet): [x0, x1, top y, bottom y, hanging].
# Shooting range: a plate hanging between the start and the near target, high enough to walk and
# shoot level under it (shots aimed up glance off it), and a ground barricade just behind the start
# (clear of the balloon reset button, its left face past the muzzle of a gun turned left at the
# start), at the AK's level line, flat arrows and the kunai, low enough to clear with a running jump
# (apex ~325). Step right and turn around to shoot it: a straight bounce comes back into the
# shooter. The revolver's level line (~318) passes over it.
const SteelPlateScript := preload("res://game/ricochet/steel_plate.gd")
const STEEL_PLATES := [
	[31968.0, 32088.0, -1500.0, -480.0, true],
	[30816.0, 30888.0, -276.0, 0.0, false],
]
const STEEL_CHAIN_TOP := -2700.0

# Still reserved for a later phase: [name, x, footprint width].
const SLOTS := [
	["Ladder", 36900.0, 240.0],
]


var bounds: Rect2
# RewardFlag instances on the reward spots (column first, then the well).
var reward_flags: Array[Node] = []
# Instanced slot pieces by slot name (Chair, Bed, DamageTrap, Turret, BreakableWall).
var slot_scenes := {}
var tunnel_ceiling_y := TUNNEL_CEILING_Y
var _layers: Array[Node2D] = []
var _layer_factors: Array[Vector2] = []
var _ref_camera_y := 0.0


func build(crouch_height := 0.0) -> void:
	var a := GameScale.art_pixel()
	if crouch_height > 0.0:
		tunnel_ceiling_y = -ceilf((crouch_height + TUNNEL_CLEARANCE) / a) * a
	bounds = Rect2(-360, -4200, LENGTH + 720, 4200 + 420)
	_build_backdrop(a)
	for g in GROUND:
		_add_ground(g[0], g[1], g[2], g[3], a)
	_build_tunnel(a)
	_build_river()
	_add_block(-WALL_THICKNESS, 0.0, -WALL_HEIGHT, WALL_HEIGHT, "", false, a)
	_add_ending_wall(a)
	for b in BLOCKS:
		_add_block(b[0], b[1], b[2], b[3], b[4], true, a, b.size() > 5 and b[5])
	# Spots for the RewardFlag on top of the climbing columns (group reward_flag_spots).
	for r in REWARDS:
		var spot := Marker2D.new()
		spot.name = "RewardFlagSpot"
		spot.position = Vector2(r[0], r[1])
		spot.add_to_group(&"reward_flag_spots")
		add_child(spot, true)
		if ResourceLoader.exists(REWARD_FLAG_SCENE):
			var flag := (load(REWARD_FLAG_SCENE) as PackedScene).instantiate()
			spot.add_child(flag)
			reward_flags.append(flag)
	_build_areas()
	for p in STEEL_PLATES:
		var plate := SteelPlateScript.new()
		plate.name = "SteelPlate" if p[4] else "SteelBarricade"
		plate.setup(Rect2(p[0], p[2], p[1] - p[0], p[3] - p[2]), STEEL_CHAIN_TOP if p[4] else p[2])
		add_child(plate, true)
	var bag_scene := load("res://game/targets/punching_bag.tscn") as PackedScene
	if bag_scene:
		var bag := bag_scene.instantiate()
		bag.name = "PunchingBag"
		bag.position = Vector2(PUNCHING_BAG_X, 0)
		area("Boxing").add_child(bag)
		slot_scenes["PunchingBag"] = bag
	var slots := Node2D.new()
	slots.name = "NextPhaseSlots"
	add_child(slots)
	for s in SLOTS:
		var m := Marker2D.new()
		m.name = s[0]
		m.position = Vector2(s[1], 0)
		m.set_meta(&"footprint", s[2])
		m.add_to_group(&"next_phase_slots")
		slots.add_child(m)


const REWARD_FLAG_SCENE := "res://game/interactables/reward_flag.tscn"
const ENDING_WALL_SCENE := "res://game/ending/ending_wall.tscn"


# The right end of the level: the ending wall (push it, it collapses, "FIM"). Origin at the base of
# its left face on the floor; the stretch 820..420 before it stays free for its sign.
func _add_ending_wall(a: int) -> void:
	if not ResourceLoader.exists(ENDING_WALL_SCENE):
		_add_block(LENGTH, LENGTH + WALL_THICKNESS, -WALL_HEIGHT, WALL_HEIGHT, "", false, a)
		return
	var wall := (load(ENDING_WALL_SCENE) as PackedScene).instantiate()
	wall.width_px = WALL_THICKNESS
	wall.height_px = WALL_HEIGHT
	wall.position = Vector2(LENGTH, 0)
	add_child(wall)
	slot_scenes["EndingWall"] = wall


func _build_areas() -> void:
	var root := Node2D.new()
	root.name = "TrainingAreas"
	add_child(root)
	for area in AREAS:
		var node := Node2D.new()
		node.name = area[0]
		node.add_to_group(&"training_areas")
		node.set_meta(&"x0", area[1])
		node.set_meta(&"x1", area[2])
		root.add_child(node)
		var bounds := Marker2D.new()
		bounds.name = "Bounds"
		bounds.set_meta(&"footprint", area[2] - area[1])
		bounds.position = Vector2((area[1] + area[2]) * 0.5, 0)
		node.add_child(bounds)
		for slot in area[3]:
			var m := Marker2D.new()
			m.name = slot[0]
			m.position = Vector2(slot[1], 0)
			var scene_path: String = SLOT_SCENES.get(slot[0], "")
			if not scene_path.is_empty() and ResourceLoader.exists(scene_path):
				var piece := (load(scene_path) as PackedScene).instantiate()
				m.add_child(piece)
				slot_scenes[slot[0]] = piece
			elif slot[2] > 0.0:
				m.set_meta(&"footprint", slot[2])
				m.add_to_group(&"next_phase_slots")
			node.add_child(m)


# Training area node by name (Rest, Boxing, Kunai, Bow, ShootingRange, Danger), or null.
func area(area_name: String) -> Node2D:
	return get_node_or_null(NodePath("TrainingAreas/" + area_name)) as Node2D


func _add_ground(x0: float, x1: float, y: float, surface: StringName, a: int) -> void:
	var body := StaticBody2D.new()
	body.name = "Ground"
	body.set_meta(&"surface", surface)
	body.set_meta(&"wall_top", y)
	body.set_meta(&"wall_bottom", y + DIRT_DEPTH)
	body.position = Vector2(x0, y)
	add_child(body)
	_add_rect_shape(body, Rect2(0, 0, x1 - x0, DIRT_DEPTH))
	var fill := ColorRect.new()
	fill.color = PixelArt.DIRT_DARK
	fill.position = Vector2(0, PixelArt.GROUND_TILE_H * a)
	fill.size = Vector2(x1 - x0, DIRT_DEPTH)
	body.add_child(fill)
	if surface == &"dirt":
		fill.color = Color("#221c20")
		var floor_sprite := _strip(TUNNEL_FLOOR, x1 - x0, TUNNEL_FLOOR.get_height())
		floor_sprite.position = Vector2(0, -TUNNEL_FLOOR_SURFACE_Y)
		body.add_child(floor_sprite)
		return
	if not _add_ground_art(body, x0, x1):
		var sprite := Sprite2D.new()
		sprite.texture = PixelArt.ground_tile()
		sprite.centered = false
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, (x1 - x0) / a, PixelArt.GROUND_TILE_H)
		sprite.scale = Vector2(a, a)
		body.add_child(sprite)


var _ground_art := {}


# Grass tops (one per world-aligned column, variant drawn from a fixed seed) and dirt rows below,
# from ground.json. The dark fill behind starts under the tops so the transparent tufts show sky.
func _add_ground_art(body: StaticBody2D, x0: float, x1: float) -> bool:
	if _ground_art.is_empty():
		if not FileAccess.file_exists(GROUND_JSON):
			return false
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROUND_JSON))
		if not data is Dictionary:
			return false
		# Each top is grass plus dirt (two layers, same order: grass, then dirt; the player in front);
		# the fog will later go between them.
		var tops: Array = []
		var fills: Array[Texture2D] = []
		for v in data.variants:
			if v.has("top_grass") and v.has("top_dirt"):
				tops.append([load(v.top_grass), load(v.top_dirt)])
			else:
				tops.append([load(v.top)])
			fills.append(load(v.fill))
		_ground_art = {"w": float(data.tile_width), "top_h": float(data.top_height), "fill_h": float(data.fill_height), "surface": float(data.surface_y), "tops": tops, "fills": fills}
	var g := _ground_art
	var w: float = g.w
	var fill_top: float = g.top_h - g.surface
	var dark := body.get_child(body.get_child_count() - 1) as ColorRect
	dark.position.y = fill_top
	dark.z_index = GROUND_DIRT_Z
	var rng := RandomNumberGenerator.new()
	var col0 := floori(x0 / w)
	var col1 := ceili(x1 / w)
	for col in range(col0, col1):
		rng.seed = hash([GROUND_SEED, col])
		var cx := col * w
		var left := maxf(cx, x0)
		var right := minf(cx + w, x1)
		if right - left < 1.0:
			continue
		var pair: Array = g.tops[rng.randi() % g.tops.size()]
		for k in pair.size():
			var tex: Texture2D = pair[k]
			var top := Sprite2D.new()
			# Grass behind the player (0); the dirt edge in front of the front fog (31).
			top.z_index = GROUND_DIRT_Z if k == 1 else 0
			top.texture = tex
			top.centered = false
			top.region_enabled = true
			top.region_rect = Rect2(left - cx, 0, right - left, g.top_h)
			top.position = Vector2(left - x0, -g.surface)
			body.add_child(top)
	var rows := ceili((DIRT_DEPTH - fill_top) / g.fill_h)
	for row in rows:
		var strip := Sprite2D.new()
		strip.texture = g.fills[(row + absi(col0)) % g.fills.size()]
		strip.centered = false
		strip.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		strip.region_enabled = true
		strip.region_rect = Rect2(fposmod(x0, w), 0, x1 - x0, g.fill_h)
		strip.position = Vector2(0, fill_top + row * g.fill_h)
		strip.z_index = GROUND_DIRT_Z
		body.add_child(strip)
	return true


func _add_block(x0: float, x1: float, top: float, thickness: float, ledges: String, grass: bool, a: int, climbable := false) -> void:
	var floating := thickness > 0.0
	var bottom := top + thickness if floating else _ground_y(x0)
	var body := StaticBody2D.new()
	body.name = "Stone"
	body.set_meta(&"surface", &"stone")
	body.set_meta(&"wall_top", top)
	body.set_meta(&"wall_bottom", bottom)
	if climbable:
		body.name = "ClimbableWall"
		body.add_to_group(&"climbable_wall")
	body.position = Vector2(x0, top)
	add_child(body)
	_add_rect_shape(body, Rect2(0, 0, x1 - x0, bottom - top))
	var tuft := PixelArt.STONE_TUFT_ROWS if grass else 0
	var sprite := Sprite2D.new()
	sprite.texture = PixelArt.stone_block(int((x1 - x0) / a), int((bottom - top) / a), grass, floating, climbable)
	sprite.centered = false
	sprite.position = Vector2(0, -tuft * a)
	sprite.scale = Vector2(a, a)
	body.add_child(sprite)
	for side in ledges:
		var ledge := Marker2D.new()
		ledge.set_script(LedgeScript)
		ledge.name = "Ledge" + side
		ledge.face_dir = 1 if side == "L" else -1
		ledge.position = Vector2(0.0 if side == "L" else x1 - x0, 0)
		body.add_child(ledge)


# Source-px art (pecas_extra) repeated over a width/height, drawn at 1:1.
func _strip(texture: Texture2D, width: float, height: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sprite.region_enabled = true
	sprite.region_rect = Rect2(0, 0, width, height)
	return sprite


# Ceiling mass (solid), back wall behind the player and stone frames at both mouths.
const LIGHTING_ZONE_SCENE := "res://game/lighting/lighting_zone.tscn"


func _build_tunnel(a: int) -> void:
	# Darkness outside, a warm torch around the player inside (it finds the player by group).
	if ResourceLoader.exists(LIGHTING_ZONE_SCENE):
		var zone := (load(LIGHTING_ZONE_SCENE) as PackedScene).instantiate()
		zone.tunnel_rect = Rect2(TUNNEL_X0, tunnel_ceiling_y - 260.0, TUNNEL_X1 - TUNNEL_X0, 380.0 - tunnel_ceiling_y)
		add_child(zone)
	var length := TUNNEL_X1 - TUNNEL_X0
	var back := _strip(TUNNEL_WALL, length, -TUNNEL_TOP_Y)
	back.name = "TunnelBackWall"
	back.z_index = -5
	back.position = Vector2(TUNNEL_X0, TUNNEL_TOP_Y)
	add_child(back)
	var body := StaticBody2D.new()
	body.name = "TunnelCeiling"
	body.set_meta(&"surface", &"dirt")
	body.set_meta(&"wall_top", TUNNEL_TOP_Y)
	body.set_meta(&"wall_bottom", tunnel_ceiling_y)
	body.position = Vector2(TUNNEL_X0, TUNNEL_TOP_Y)
	add_child(body)
	var mass_height := tunnel_ceiling_y - TUNNEL_TOP_Y
	_add_rect_shape(body, Rect2(0, 0, length, mass_height))
	var mass := ColorRect.new()
	mass.color = Color("#2a2226")
	mass.size = Vector2(length, mass_height - TUNNEL_CEILING_EDGE_Y)
	body.add_child(mass)
	var edge := _strip(TUNNEL_CEILING, length, TUNNEL_CEILING.get_height())
	edge.position = Vector2(0, mass_height - TUNNEL_CEILING_EDGE_Y)
	body.add_child(edge)
	for x in [TUNNEL_X0, TUNNEL_X1 - TUNNEL_FRAME_WIDTH]:
		var frame := Sprite2D.new()
		frame.name = "TunnelFrame"
		frame.texture = PixelArt.stone_block(int(TUNNEL_FRAME_WIDTH / a), int(mass_height / a) + 1, true, true)
		frame.centered = false
		frame.scale = Vector2(a, a)
		frame.position = Vector2(x, TUNNEL_TOP_Y - PixelArt.STONE_TUFT_ROWS * a)
		frame.z_index = 1
		add_child(frame)


func _build_river() -> void:
	if not ResourceLoader.exists(RIVER_SCENE):
		return
	var river := (load(RIVER_SCENE) as PackedScene).instantiate()
	river.name = "River"
	river.position = Vector2(RIVER_X, 0)
	add_child(river)
	slot_scenes["River"] = river
	# Frame the river and the valley lower: surface in the upper third, bed in view.
	var zone := Node2D.new()
	zone.set_script(CameraZoneScript)
	zone.name = "RiverCameraZone"
	zone.rect = Rect2(RIVER_X - 120.0, -1200.0, 3420.0, 2200.0)
	zone.min_center_y = RIVER_CAMERA_CENTER_Y
	zone.limit_bottom = RIVER_CAMERA_BOTTOM
	add_child(zone)


func in_tunnel(x: float) -> bool:
	return x > TUNNEL_X0 and x < TUNNEL_X1


func _ground_y(x: float) -> float:
	for g in GROUND:
		if x >= g[0] and x < g[1]:
			return g[2]
	return 0.0


func _add_rect_shape(body: StaticBody2D, rect: Rect2) -> void:
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)


var sky_color := Color("#4e80c2")
var _sky_layer: CanvasLayer
var _sky_sprite: Sprite2D
var _sky_height := 1440.0
var _clouds: Node2D
var _cloud_factor := 0.06


# Only the sky, clouds and parallax layers (other stages reuse the backdrop without the level).
func build_backdrop() -> void:
	_build_backdrop(GameScale.art_pixel())


func _build_backdrop(_a: int) -> void:
	if not FileAccess.file_exists(BACKGROUND_JSON):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BACKGROUND_JSON))
	if not data is Dictionary:
		return
	sky_color = Color(data.get("clear_color", "#4e80c2"))
	var span := 9000.0
	for layer_data in data.layers:
		var f: float = layer_data.parallax
		match String(layer_data.name):
			"sky":
				_build_sky(layer_data)
			"clouds":
				_clouds = Node2D.new()
				_clouds.set_script(CloudLayer)
				_clouds.z_index = BACKGROUND_Z
				_clouds.wrap_width = float(layer_data.get("wrap_width", 6400.0))
				_clouds.drift_dir = float(layer_data.get("drift_direction", -1))
				for c in layer_data.sprites:
					_clouds.clouds.append([load(c.path), float(c.suggested_x), float(c.suggested_y), float(c.drift_speed)])
				add_child(_clouds)
				_cloud_factor = f
				_layers.append(_clouds)
				_layer_factors.append(Vector2(f, f))
			_:
				var layer := Node2D.new()
				layer.z_index = BACKGROUND_Z + int(layer_data.z_order) - 2
				add_child(layer)
				var tex := load(layer_data.path) as Texture2D
				var tile: float = layer_data.tile_width
				var sprite := Sprite2D.new()
				sprite.texture = tex
				sprite.centered = false
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
				sprite.region_enabled = true
				var width := ceilf((LENGTH * f + span * 2.0) / tile) * tile
				sprite.region_rect = Rect2(0, 0, width, tex.get_height())
				sprite.position = Vector2(-span, float(layer_data.y))
				layer.add_child(sprite)
				if layer_data.name == "mist":
					var base := ColorRect.new()
					base.color = Color(data.palette.get("mist3", "#4e6a92"))
					base.position = Vector2(-span, float(layer_data.bottom_y) - 2.0)
					base.size = Vector2(width, MIST_BASE_DEPTH)
					layer.add_child(base)
				_layers.append(layer)
				_layer_factors.append(Vector2(f, f))


# Sky fixed on screen: one tiled strip as tall as the view (1440 world units at zoom 0.5).
func _build_sky(layer_data: Dictionary) -> void:
	_sky_layer = CanvasLayer.new()
	_sky_layer.layer = -100
	add_child(_sky_layer)
	_sky_sprite = Sprite2D.new()
	_sky_sprite.texture = load(layer_data.path)
	_sky_sprite.centered = false
	_sky_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sky_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_sky_sprite.region_enabled = true
	_sky_layer.add_child(_sky_sprite)
	_sky_height = float(layer_data.size[1])


# Call every frame with the camera's screen center; reference_y is the camera y when standing on y = 0.
func update_parallax(center: Vector2, reference_y: float, view: Vector2 = Vector2(2560, 1440)) -> void:
	for i in _layers.size():
		var f := _layer_factors[i]
		_layers[i].position = Vector2(
			roundf(center.x * (1.0 - f.x)),
			roundf((center.y - reference_y) * (1.0 - f.y)))
	if _clouds:
		var left := center.x - _clouds.position.x - view.x * 0.5
		_clouds.set_view(left, left + view.x)
	if _sky_sprite:
		# Screen pixels: the texture covers the view height; tile across the width.
		var vp := get_viewport().get_visible_rect().size
		var k := vp.y / _sky_height
		_sky_sprite.scale = Vector2(k, k)
		_sky_sprite.region_rect = Rect2(0, 0, ceilf(vp.x / k) + 96.0, _sky_height)
