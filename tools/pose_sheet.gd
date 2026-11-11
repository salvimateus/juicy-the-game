extends Node2D
## Pose sheet: renders the Adventurer at given phases into one PNG grid per spec, at 1 world unit
## per pixel, framed like the JS panels (520x520, origin at 268,452).
##
## godot --path <project> res://tools/pose_sheet.tscn -- --pose-sheet <spec>[+<spec>...]
##     --phases 0,0.25,0.5 --out <dir> [--cols N] [--no-root-motion] [--no-juice]
## Specs: idle | walk | run | sprint | locomotion@<speed> | air@<vy> | land@<vy> | hanging |
##   wall_slide@<speed> | dodge_cancel | any action id (skid_turn, roll, roll_back, dodge, jump,
##   ledge_grab, ledge_climb, ledge_descend, ledge_drop, ledge_leap, wall_grab, wall_jump).
## Phases are normalized over the clip or action (hanging: 4 s, wall_slide: 2 s, land: landing;
## an action's `sheet_duration` overrides its duration). --weapon <id> calls set_weapon first; an
## action's `sheet_setup(adv)` prepares extra state. Air-only actions start airborne.

const SCENE := preload("res://rig/adventurer.tscn")
const STEP := 1.0 / 120.0
const SKY := Color("#20202c")
const GROUND := Color("#4f6b3a")
const DIRT := Color("#5a4030")
const STONE := Color("#6e5c5c")
const CELL := Vector2i(520, 520)
const ORIGIN := Vector2(268, 452)

var _specs: PackedStringArray
var _phases := PackedFloat32Array()
var _out := "res://captures/pose_sheets"
var _cols := 0
var _root_motion := true
var _juice := true
var _weapon := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--pose-sheet")
	if i < 0:
		_specs = PackedStringArray(["walk"])
	else:
		_specs = args[i + 1].split("+")
	var p := args.find("--phases")
	var phase_list := args[p + 1] if p >= 0 else "0,0.125,0.25,0.375,0.5,0.625,0.75,0.875"
	for s in phase_list.split(","):
		_phases.append(float(s))
	var o := args.find("--out")
	if o >= 0:
		_out = args[o + 1]
	var c := args.find("--cols")
	if c >= 0:
		_cols = int(args[c + 1])
	_root_motion = args.find("--no-root-motion") < 0
	_juice = args.find("--no-juice") < 0
	var wi := args.find("--weapon")
	if wi >= 0:
		_weapon = args[wi + 1]
	DirAccess.make_dir_recursive_absolute(_out)
	for spec in _specs:
		await _render_sheet(spec)
	get_tree().quit()


func _cell_frame(spec: String) -> Dictionary:
	# Cell size, adventurer origin and scenery for the spec.
	var name := spec.split("@")[0]
	if name in ["ledge_grab", "ledge_climb", "ledge_descend", "ledge_drop", "ledge_leap", "hanging"]:
		var corner := Vector2(300, 300)
		var origin := corner - Adventurer.HANG_GRIP_OFFSET
		if name == "ledge_descend":
			origin = corner + Adventurer.LEDGE_TOP_OFFSET
		return {"size": Vector2i(560, 700), "origin": origin, "ledge": corner}
	if name in ["wall_grab", "wall_slide", "wall_jump", "wall_kick"]:
		var o := Vector2(220, 500)
		return {"size": Vector2i(520, 560), "origin": o, "wall": o.x + Adventurer.WALL_CONTACT_OFFSET.x}
	if name in ["roll", "roll_back", "dodge", "dodge_cancel"]:
		var x := 192.0 if name == "roll" else 360.0
		return {"size": Vector2i(560, 520), "origin": Vector2(x, ORIGIN.y), "ground": ORIGIN.y}
	if name == "step_up":
		return {"size": CELL, "origin": Vector2(160, ORIGIN.y), "ground": ORIGIN.y, "step": float(spec.split("@")[1])}
	if name == "push":
		var o := Vector2(220, ORIGIN.y)
		return {"size": CELL, "origin": o, "ground": ORIGIN.y, "wall": o.x + Adventurer.PUSH_CONTACT_OFFSET.x}
	if name in ["air", "jump", "double_jump"]:
		return {"size": CELL, "origin": ORIGIN, "ground": ORIGIN.y + (0.0 if name == "jump" else 60.0)}
	return {"size": CELL, "origin": ORIGIN, "ground": ORIGIN.y}


func _render_sheet(spec: String) -> void:
	var frame := _cell_frame(spec)
	var cell: Vector2i = frame.size
	var cols := _cols if _cols > 0 else mini(_phases.size(), 4)
	var rows := ceili(float(_phases.size()) / cols)
	var vp := SubViewport.new()
	vp.size = Vector2i(cell.x * cols, cell.y * rows)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.snap_2d_transforms_to_pixel = true
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = SKY
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	for k in _phases.size():
		var cell_pos := Vector2((k % cols) * cell.x, (k / cols) * cell.y)
		var holder := Node2D.new()
		holder.position = cell_pos
		vp.add_child(holder)
		_draw_scenery(holder, frame, cell)
		var adv: Adventurer = SCENE.instantiate()
		adv.juice = _juice
		adv.position = frame.origin
		holder.add_child(adv)
		var label := Label.new()
		label.text = "%s  u=%.3f" % [spec, _phases[k]]
		label.position = Vector2(8, 4)
		label.add_theme_font_size_override("font_size", 14)
		holder.add_child(label)
		var info := _simulate(adv, spec, _phases[k])
		if not info.is_empty():
			label.text += "  " + info
		adv._render()
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := _out.path_join("%s.png" % spec.replace("@", "_at_"))
	var err := img.save_png(path)
	print("POSE_SHEET ", path, " size=", img.get_size(), " err=", err)
	vp.queue_free()


func _draw_scenery(holder: Node2D, frame: Dictionary, cell: Vector2i) -> void:
	if frame.has("ground"):
		var g := ColorRect.new()
		g.color = DIRT
		g.position = Vector2(0, frame.ground)
		g.size = Vector2(cell.x, cell.y - frame.ground)
		holder.add_child(g)
		var top := ColorRect.new()
		top.color = GROUND
		top.position = Vector2(0, frame.ground)
		top.size = Vector2(cell.x, 12)
		holder.add_child(top)
	if frame.has("step"):
		var st := ColorRect.new()
		st.color = Color("#6e5c5c")
		var edge: float = frame.origin.x + 60.0
		st.position = Vector2(edge, frame.ground - frame.step)
		st.size = Vector2(cell.x - edge, frame.step)
		holder.add_child(st)
	if frame.has("ledge"):
		var corner: Vector2 = frame.ledge
		var tex := load("res://assets/pecas_extra/ledge.png") as Texture2D
		var y := corner.y - 6.0
		while y < cell.y:
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.position = Vector2(corner.x - 6.0, y)
			if y > corner.y:
				s.region_enabled = true
				s.region_rect = Rect2(0, 96, 264, 72)
			holder.add_child(s)
			y += 180.0 if y < corner.y else 72.0
		var marker := ColorRect.new()
		marker.color = Color(1, 0.3, 0.4, 0.9)
		marker.position = corner - Vector2(2, 2)
		marker.size = Vector2(4, 4)
		holder.add_child(marker)
	if frame.has("wall"):
		var w := ColorRect.new()
		w.color = STONE
		w.position = Vector2(frame.wall, 0)
		w.size = Vector2(cell.x - frame.wall, cell.y)
		holder.add_child(w)


func _step(adv: Adventurer, speed: float, airborne: bool, vy: float, dt := STEP, wall := false, wall_speed := 0.0) -> void:
	adv.set_locomotion(speed, dt)
	adv.set_airborne(airborne, vy)
	adv.set_wall_slide(wall, wall_speed)
	var m := adv.take_root_motion()
	if _root_motion:
		adv.position += m


func _run(adv: Adventurer, seconds: float, speed: float, airborne := false, vy := 0.0, wall := false, wall_speed := 0.0, travel := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		var dt := minf(STEP, seconds - t)
		_step(adv, speed, airborne, vy, dt, wall, wall_speed)
		if travel:
			adv.position.x += speed * dt * adv.facing
		t += dt


func _crouch_run(adv: Adventurer, seconds: float, speed: float, travel := false) -> void:
	var t := 0.0
	while t < seconds - 1e-6:
		var dt := minf(STEP, seconds - t)
		adv.set_locomotion(0.0, dt)
		adv.set_crouch(true, speed, dt)
		adv.set_airborne(false, 0.0)
		if travel:
			adv.position.x += speed * dt * adv.facing
		t += dt
	adv.set_locomotion(0.0, 0.0)


func _simulate(adv: Adventurer, spec: String, u: float) -> String:
	var parts := spec.split("@")
	var name := parts[0]
	var arg := float(parts[1]) if parts.size() > 1 else 0.0
	match name:
		"idle":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.set("_idle_u", u)
			adv.debug_skip_blend()
			return ""
		"walk", "run", "sprint", "locomotion":
			var speed: float = {"walk": Adventurer.WALK_SPEED, "run": Adventurer.RUN_SPEED, "sprint": Adventurer.SPRINT_SPEED}.get(name, arg)
			# Run one second into the phase so step FX from earlier footfalls are alive.
			var cycle: float = adv.get("_gait").cycle_length() if speed > 0.0 else 1.0
			adv.debug_set_locomotion(speed, RigMath.frac(u - speed / cycle), 0.0)
			cycle = adv.get("_gait").cycle_length()
			adv.debug_set_locomotion(speed, RigMath.frac(u - speed / cycle), 0.0)
			adv.debug_skip_blend()
			var start: Vector2 = adv.position
			adv.position -= Vector2(speed, 0.0)
			_run(adv, 1.0, speed, false, 0.0, false, 0.0, true)
			adv.position = start
			return "%.0f u/s ph=%.3f" % [speed, adv.get("_phase")]
		"air":
			adv.debug_set_air(true, arg, 0.4)
			adv.debug_skip_blend()
			return "vy=%.0f" % arg
		"land":
			adv.debug_set_air(true, arg, 0.5)
			adv.debug_skip_blend()
			_step(adv, 0.0, false, 0.0)
			_run(adv, u * RigAir.landing_duration(RigAir.landing_strength(arg)), 0.0)
			return "vy=%.0f" % arg
		"push":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.debug_set_push(1.0, u * 2.0)
			adv.debug_skip_blend()
			return "t=%.2f" % (u * 2.0)
		"step_up":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.debug_skip_blend()
			if not adv.play_step_up(arg):
				return "play_step_up failed"
			var action: RigAction = adv.get("_actions")[&"step_up"]
			var st := u * action.duration
			_run(adv, st, 0.0)
			return "h=%.0f t=%.3f/%.2f" % [arg, st, action.duration]
		"crouch":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.debug_set_crouch(1.0, 0.0, 0.0)
			adv.debug_skip_blend()
			_crouch_run(adv, u * 4.0, 0.0)
			return "h=%.0f" % adv.debug_silhouette_height()
		"crawl":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			var cyc: float = adv.crawl.cycle_length()
			var speed := 120.0
			adv.debug_set_crouch(1.0, 1.0, RigMath.frac(u - speed * 1.0 / cyc))
			adv.debug_skip_blend()
			var start: Vector2 = adv.position
			adv.position.x -= speed
			_crouch_run(adv, 1.0, speed, true)
			adv.position = start
			return "h=%.0f" % adv.debug_silhouette_height()
		"stand_to_crouch":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.debug_skip_blend()
			_crouch_run(adv, u * 0.2, 0.0)
			return "t=%.2f" % (u * 0.2)
		"crouch_to_crawl":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.debug_set_crouch(1.0, 0.0, 0.0)
			adv.debug_skip_blend()
			_crouch_run(adv, u * 0.3, 120.0, true)
			return "t=%.2f" % (u * 0.3)
		"hanging":
			adv.debug_set_hanging(u * 4.0)
			adv.debug_skip_blend()
			return ""
		"wall_slide":
			adv.debug_set_wall(arg, u * 2.0)
			adv.debug_skip_blend()
			_run(adv, u * 2.0, 0.0, true, arg, true, arg)
			return "%.0f u/s" % arg
		"dodge_cancel":
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
			adv.debug_skip_blend()
			adv.play_action(&"dodge")
			var total := 1.2
			var t := u * total
			var first := minf(t, 0.5)
			_run(adv, first, 0.0)
			if t > 0.5:
				var ok := adv.play_action(&"dodge")
				_run(adv, t - 0.5, 0.0)
				return "t=%.2f recancel=%s" % [t, ok]
			return "t=%.2f" % t
	return _simulate_action(adv, StringName(name), u)


func _simulate_action(adv: Adventurer, id: StringName, u: float) -> String:
	var speed := 0.0
	var airborne := false
	var vy := 0.0
	var wall := false
	match id:
		&"skid_turn":
			speed = Adventurer.RUN_SPEED
			adv.debug_set_locomotion(speed, 0.0, 0.0)
		&"ledge_climb", &"ledge_drop", &"ledge_leap":
			adv.debug_set_hanging(2.0)
		&"ledge_grab":
			adv.debug_set_air(true, 700.0, 0.4)
			airborne = true
			vy = 700.0
		&"wall_grab":
			adv.debug_set_air(true, 300.0, 0.4)
			airborne = true
			vy = 300.0
		&"double_jump":
			adv.debug_set_air(true, -200.0, 0.4)
			airborne = true
			vy = -200.0
		&"wall_jump", &"wall_kick":
			adv.debug_set_air(true, 250.0, 0.4)
			adv.debug_set_wall(250.0, 0.5)
			airborne = true
			vy = 250.0
			wall = true
		_:
			adv.debug_set_locomotion(0.0, 0.0, 1.0)
	var action: RigAction = adv.get("_actions").get(id)
	if action == null:
		return "unknown action"
	if not _weapon.is_empty():
		adv.set_weapon(StringName(_weapon))
	if action.requires == "air" and not airborne:
		adv.debug_set_air(true, -100.0, 0.4)
		airborne = true
		vy = -100.0
	# Actions can prepare their own sheet state (hold a guard, aim, ...).
	if action.has_method("sheet_setup"):
		action.sheet_setup(adv)
	adv.debug_skip_blend()
	if not adv.play_action(id):
		return "play_action failed"
	var span: float = action.get("sheet_duration") if action.get("sheet_duration") != null else action.duration
	var t := u * span
	_run(adv, t, speed if id == &"skid_turn" else 0.0, airborne, vy, wall, vy)
	return "t=%.3f/%.2f" % [t, action.duration]
