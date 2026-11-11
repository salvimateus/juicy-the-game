extends Node2D

# Test bench for PushCrate on the river bank. A stand-in pusher (CharacterBody2D with the player's
# capsule, radius 73, height 411) pushes the edge crate into the river the way the player layer
# will (push() every physics frame, feet kept at push_contact_offset), walks into the water through
# the freed corridor, stands on the floating crate, then pushes the middle crate in too. Both are
# swum toward the dam, the dam opens, the current pulls them through the hole and the jet drops
# them into the valley, where they float; the refill puts every crate back.
# Capture: godot --path <project> res://game/water/crate_test.tscn -- --capture <dir>

const PixelArt := preload("res://game/pixel_art.gd")
const RIVER_SCENE := preload("res://game/water/river.tscn")

const RADIUS := 73.0
const HEIGHT := 411.0
const PUSH_EDGE_AT := 0.4
const WALK_IN_AT := 1.7
const BOARD_AT := 3.2
const SECOND_AT := 5.5
const SWIM := [9.6, 13.0]
const OPEN_AT := 13.0
const REFILL_AT := 26.0
const NEAR := Vector2(-280, 60)
const OVERVIEW := Vector2(1488, 330)
# [time, name, camera centre, zoom]
const SHOTS := [
	[0.30, "c01_bank", NEAR, 0.5],
	[0.95, "c02_pushing", NEAR, 0.5],
	[1.80, "c03_splash", NEAR, 0.5],
	[2.60, "c04_walk_in", NEAR, 0.5],
	[3.80, "c05_boarded", Vector2(0, 0), 0.5],
	[5.20, "c06_standing", Vector2(0, 0), 0.5],
	[7.00, "c07_second_push", NEAR, 0.5],
	[12.8, "c08_swum_to_dam", Vector2(1300, 120), 0.5],
	[13.30, "c09_pulled", Vector2(1700, 200), 0.5],
	[13.60, "c10_through_hole", Vector2(1800, 240), 0.5],
	[13.95, "c11_second_in_hole", Vector2(1850, 300), 0.5],
	[14.30, "c12_jet", Vector2(1950, 380), 0.5],
	[15.20, "c12_jet_late", OVERVIEW, 1.0 / 3.0],
	[22.0, "c13_valley", OVERVIEW, 1.0 / 3.0],
	[22.05, "c14_valley_close", Vector2(2350, 380), 0.5],
	[25.5, "c15_valley_settled", Vector2(2350, 380), 0.5],
	[27.3, "c16_reset", NEAR, 0.5],
]

var river: Node2D
var camera: Camera2D
var pusher: CharacterBody2D
var edge: PushCrate
var middle: PushCrate
var _target: PushCrate
var _dir := ""
var _tick := 0
var _time := 0.0
var _shots: Array = []
var _busy := 0
var _done := false
var _phase := ""
var _float_y := INF


func _ready() -> void:
	RenderingServer.set_default_clear_color(PixelArt.SKY)
	river = RIVER_SCENE.instantiate()
	add_child(river)
	edge = river.get_node("CrateNearEdge")
	middle = river.get_node("CrateMiddle")
	pusher = _make_pusher()
	add_child(pusher)
	pusher.global_position = edge.global_position + edge.push_contact_offset(1, RADIUS)
	print("CRATE layout edge=%s middle=%s back=%s gap_middle_edge=%.0f" % [edge.position, middle.position,
		river.get_node("CrateBack").position, (edge.position.x - edge.half) - (middle.position.x + middle.half)])
	camera = Camera2D.new()
	camera.position = NEAR
	camera.zoom = Vector2.ONE * 0.5
	add_child(camera)
	camera.make_current()
	var args := OS.get_cmdline_user_args()
	var i := args.find("--capture")
	if i != -1:
		_dir = args[i + 1] if i + 1 < args.size() else "res://captures/crate"
		DirAccess.make_dir_recursive_absolute(_dir)
		_shots = SHOTS.duplicate()


func _physics_process(delta: float) -> void:
	if not river.is_ready():
		return
	_tick += 1
	_time = _tick / float(Engine.physics_ticks_per_second)
	pusher.velocity.y += 2600.0 * delta
	pusher.velocity.x = 0.0
	if _time >= PUSH_EDGE_AT and _time < WALK_IN_AT:
		_push(edge, delta)
	elif _time >= WALK_IN_AT and _time < BOARD_AT:
		# The corridor to the water is free once the edge crate is in: walk in, onto the crate.
		if pusher.global_position.x < 40.0:
			pusher.velocity.x = 320.0
	elif _time >= BOARD_AT and _time < SECOND_AT:
		if _phase != "board":
			_phase = "board"
			_float_y = edge.global_position.y
		# Walk to the middle of the floating crate and stand there.
		if pusher.global_position.x < edge.global_position.x - 6.0:
			pusher.velocity.x = 200.0
	elif _time >= SECOND_AT and _time < SWIM[0]:
		if _phase != "second":
			_phase = "second"
			pusher.global_position = Vector2(middle.global_position.x + middle.push_contact_offset(1, RADIUS).x, -2.0)
			pusher.velocity = Vector2.ZERO
		_push(middle, delta)
	elif _time >= SWIM[0] and _time < SWIM[1]:
		if _phase != "swim":
			_phase = "swim"
			pusher.global_position = Vector2(-1120, -2)
			pusher.velocity = Vector2.ZERO
		# Swim-pushes, spaced so the two crates arrive one after the other.
		edge.push(1, delta)
		if middle.global_position.x < edge.global_position.x - 200.0:
			middle.push(1, delta)
	if _phase != "opened" and _phase != "refilled" and _time >= OPEN_AT:
		_phase = "opened"
		river.open_hole()
	if _phase != "refilled" and _time >= REFILL_AT:
		_phase = "refilled"
		river.refill()
	pusher.move_and_slide()
	if _tick % 30 == 0:
		print("CRATE t=%.2f edge=(%.0f, %.0f) %s middle=(%.0f, %.0f) %s pusher=(%.0f, %.0f) floor=%s sink=%+.0f" % [
			_time, edge.global_position.x, edge.global_position.y, "G" if edge.is_grounded() else "D",
			middle.global_position.x, middle.global_position.y, "G" if middle.is_grounded() else "D",
			pusher.global_position.x, pusher.global_position.y, pusher.is_on_floor(),
			edge.global_position.y - _float_y if _phase == "board" else 0.0])
	if _dir.is_empty():
		return
	while not _shots.is_empty() and _time >= _shots[0][0] - 0.001:
		var s: Array = _shots.pop_front()
		camera.position = s[2]
		camera.zoom = Vector2.ONE * s[3]
		_shot(s[1])
	if _shots.is_empty() and not _done:
		_done = true
		_try_quit()


# What the player layer does: push while grounded, walk with the crate, feet at the contact offset.
func _push(crate: PushCrate, delta: float) -> void:
	if not crate.is_grounded():
		return
	if crate.push(1, delta):
		pusher.global_position.x = (crate.global_position + crate.push_contact_offset(1, RADIUS)).x
	elif _target != crate:
		_target = crate
		print("CRATE push blocked at x=%.0f" % crate.global_position.x)


func _make_pusher() -> CharacterBody2D:
	var a := 6
	var body := CharacterBody2D.new()
	body.name = "Pusher"
	body.floor_snap_length = 12.0
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	shape.shape = cap
	shape.position = Vector2(0, -HEIGHT * 0.5)
	body.add_child(shape)
	var w := int(RADIUS * 2.0 / a)
	var h := int(HEIGHT / a)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	img.fill_rect(Rect2i(0, 4, w, h - 8), Color("#ff3cc8"))
	img.fill_rect(Rect2i(3, 0, w - 6, h), Color("#ff3cc8"))
	img.fill_rect(Rect2i(6, 3, w - 12, 9), Color("#ffd0f0"))
	var s := Sprite2D.new()
	s.texture = ImageTexture.create_from_image(img)
	s.centered = false
	s.scale = Vector2(a, a)
	s.position = Vector2(-RADIUS, -HEIGHT)
	s.z_index = 1
	body.add_child(s)
	return body


func _shot(shot_name: String) -> void:
	_busy += 1
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("CAPTURE %s edge=(%.0f, %.0f) middle=(%.0f, %.0f) fps=%d" % [path, edge.global_position.x, edge.global_position.y,
		middle.global_position.x, middle.global_position.y, Engine.get_frames_per_second()])
	_busy -= 1
	_try_quit()


func _try_quit() -> void:
	if _done and _busy == 0:
		get_tree().quit()
