class_name Adventurer
extends Node2D
## The adventurer rig: locomotion by speed, one-shot actions, air, ledge and wall states, with
## root motion for the game body. Origin on the ground under the hip, y down, 1 unit = 1 source px.
##
## The game drives it every physics frame: set_locomotion (the tick), set_airborne and
## set_wall_slide, then take_root_motion. Rendering happens in _process from the last tick.

signal action_finished(id: StringName)
signal action_event(id: StringName, name: StringName)
signal footstep(foot: StringName, strength: float)
signal landed(strength: float)
## One per swim stroke (sound, bubbles, surface ripple).
signal swim_stroke(strength: float)

const WALK_SPEED: float = WalkTuning.T.stride / (WalkTuning.T.duty * WalkTuning.T.duration)
const RUN_SPEED: float = RunTuning.T.stride / (RunTuning.T.duty * RunTuning.T.duration)
const SPRINT_SPEED: float = SprintTuning.OVERRIDES.stride / (SprintTuning.OVERRIDES.duty * SprintTuning.OVERRIDES.duration)
## Origin to the ledge corner the hands hook over while hanging, facing 1:
## origin = corner - HANG_GRIP_OFFSET (x mirrored by facing).
const HANG_GRIP_OFFSET := Vector2(90, -367)
## Origin relative to the corner when standing on the top after ledge_climb, and where
## ledge_descend must start, facing 1 (the character faces away from the drop).
const LEDGE_TOP_OFFSET := Vector2(70, 0)
## Silhouette heights (ground to the top of the art) of the crouch idle and the crawl.
const CROUCH_HEIGHT := 270.0
const CRAWL_HEIGHT := 244.0
## Highest step play_step_up takes (knee height) and its forward root motion.
const STEP_MAX_HEIGHT: float = StepTuning.T.maxHeight
const STEP_FORWARD: float = StepTuning.T.forward
## Origin to the wall plane while pushing (set_push), facing 1.
const PUSH_CONTACT_OFFSET := Vector2(198, 0)
## Origin to the wall plane while wall sliding, facing 1 (facing the wall).
const WALL_CONTACT_OFFSET := Vector2(112, 0)

const B := preload("res://rig/rig_bone.gd")
## Action providers (scripts with `static func create(rig: RigData) -> Dictionary` id -> RigAction,
## optional `static func apply_guard(rig, pose, weight, time)`), loaded when present.
## A provider may also define `static func attach(host)` to add its own child nodes (e.g. the bow
## string), called once after the rig nodes exist.
const ACTION_PROVIDERS := [
	"res://rig/clips/boxing_actions.gd",
	"res://rig/clips/kick_actions.gd",
	"res://rig/clips/gun_actions.gd",
	"res://rig/clips/bow_ninja_actions.gd",
	"res://rig/clips/reaction_actions.gd",
	"res://rig/clips/interaction_actions.gd",
	"res://rig/clips/swim_actions.gd",
	"res://rig/clips/landing_actions.gd",
	"res://rig/clips/ride_actions.gd",
]
## Props shown in hand per weapon (fists wear the boxing gloves).
const WEAPON_PROPS := {&"none": [], &"fists": ["glove_front", "glove_back"], &"revolver": ["revolver"], &"rifle": ["ak47"], &"bow": ["bow"], &"kunai": ["kunai"]}
const LT := preload("res://rig/clips/locomotion_tuning.gd")
const HISTORY := 128
const WORLD_FLOATS := 28 * 6
const PART_SHADER := preload("res://rig/rig_part.gdshader")
const FX_SHADER := preload("res://rig/fx/rig_fx.gdshader")
const DRAW_ORDER_RULES := [
	[],
	# Hanging: the back arm goes over the head reaching up; the front arm stays behind the head
	# (its forearm would otherwise cross the face).
	[["foreArmB", "after", "head"], ["handB", "after", "foreArmB"], ["upperArmB", "after", "handB"]],
	# Climbing: the same plus the near leg over the body while it steps onto the top.
	[["foreArmB", "after", "head"], ["handB", "after", "foreArmB"], ["upperArmB", "after", "handB"], ["thighF", "after", "body"], ["footF", "after", "thighF"], ["shaftF", "after", "footF"], ["kneeF", "after", "shaftF"]],
	# Default with the back arm raised: its forearm, fist and held prop go in front of the head (and
	# the mouth); the upper arm stays behind the torso. Built in _build_orders.
	[],
]
const ORDER_RAISED_B := 3
## Actions whose pose may mirror right away when the game flips the facing (aim loops and what
## plays inside them): the pose blends over FLIP_BLEND without restarting the action.
const FLIP_OK_ACTIONS: Array[StringName] = [&"bow_aim", &"revolver_aim", &"rifle_aim", &"revolver_cock", &"revolver_recock", &"revolver_fire"]
const FLIP_BLEND := 0.05
## Actions that hide the weapon prop in hand while they play.
const EVADES: Array[StringName] = [&"dodge", &"roll", &"roll_back"]
# Actions that keep the weapon carry overlay on top of their own pose.
const CARRY_ACTIONS: Array[StringName] = [&"jump", &"hero_landing"]
const HIDE_WEAPON_ACTIONS: Array[StringName] = [&"flying_kick", &"flying_kick_impact"]
## Back arm raise hysteresis around the neck joint (rig units, y down).
const RAISE_ON := 4.0
const RAISE_OFF := 14.0

@export var facing: int = 1:
	set(value):
		_set_facing(1 if value >= 0 else -1)
	get:
		return _facing
@export var juice := true

var rig: RigData
var fx: RigFx
var ledge: RigLedge
var pose: RigPose
var hang_catch_age := 10.0
var catch_k := 1.0
var wall_speed := 0.0

var _facing := 1
var crawl: RigCrawl
var step_height := 60.0
## Current weapon id (set_weapon) and its prop mask.
var weapon: StringName = &"none"
var weapon_mask := 0
var guard := false
var _guard_w := 0.0
var _guard_provider: Script
## Weapon carry overlay (static func apply_carry(rig, pose, weapon, time)), applied on the ground
## pose while no action plays.
var _carry_provider: Script
var _attachers: Array[Script] = []
## Swim state: an object from a provider's create_swimmer(rig) with
## `tick(host, mode: StringName, velocity: Vector2, delta: float) -> float` (stroke strength, 0 when
## no stroke this tick) and `sample(host, pose: RigPose, juice: bool)`.
var _swimmer: Object
var _swim_mode: StringName = &""
var _swim_frame := -10
## Game-driven parameters read by actions (rifle_firing, bow_aim, hit_direction, ...).
var action_params := {&"rifle_firing": false, &"bow_aim": 0.0, &"bow_power": 1.0, &"hit_direction": Vector2.LEFT, &"rest_height": 90.0, &"gun_aim": 0.0}
var _push := false
var _push_w := 0.0
var _push_time := 0.0
var _push_step := 0.0
var _push_sampler: RigPush
var _push_pose: RigPose
var _wall_sampler: RigWall
var _crouch := false
var _crouch_w := 0.0
var _crawl_w := 0.0
var _crawl_speed := 0.0
var _crawl_phase := 0.0
var _crouch_time := 0.0
var _crouch_pose: RigPose
# Held look (set_look): weight 0..1 and direction (1 down, -1 up) of the last non-zero request.
var _look_w := 0.0
var _look_dir := 1
var _crawl_pose: RigPose
var _pending_facing := 0
var _time := 0.0
var _target: RigPose
var _snap: RigPose
var _scratch: RigPose
var _air_pose: RigPose
var _takeoff_pose: RigPose
var _world := PackedFloat32Array()
var _gaits: Array[RigGait] = []
var _gait: RigGait
var _gait_fx: Array = []
var _speed := 0.0
var _speed_smooth := 0.0
var _phase := 0.0
var _idle_u := 0.0
var _idle_w := 1.0
var _actions := {}
var _action: RigAction
var _action_t := 0.0
var _event_i := 0
var _iframes := false
var _rm_prev := Vector2.ZERO
var _root := Vector2.ZERO
var _hanging := false
var _wall := false
var _wall_age := 0.0
var _wall_fx_t := 0.0
var _airborne := false
var _air_time := 0.0
var _vy := 0.0
var _last_air_vy := 0.0
var _inherit := 0.0
var _jump_hold := -1.0
var _land_t := -1.0
var _land_s := 0.0
var _source := ""
var _blend_t := 1.0
var _blend_dur := 0.0
var _draw_order := -1
var _b_raised := false
var _tick_dt := 0.0
var _orders := {}  # preset id -> PackedInt32Array
var _flash_state := Vector2(-1, -1)

# Nodes.
var _parts_node: Node2D
var _sprites: Array[Sprite2D] = []
var _ghost_groups: Array[CanvasGroup] = []
var _ghost_sprites: Array = []
var _fx_back: MultiMeshInstance2D
var _fx_front: MultiMeshInstance2D
var _material: ShaderMaterial

# History of rendered frames for afterimages.
var _hist_world := PackedFloat32Array()
var _hist_time := PackedFloat64Array()
var _hist_pos := PackedVector2Array()
var _hist_props := PackedInt32Array()
var _hist_head := 0
var _hist_count := 0


func _ready() -> void:
	rig = RigData.shared()
	fx = RigFx.new(rig)
	ledge = RigLedge.new(rig)
	pose = RigPose.new(rig)
	_target = RigPose.new(rig)
	_snap = RigPose.new(rig)
	_scratch = RigPose.new(rig)
	_air_pose = RigPose.new(rig)
	_takeoff_pose = RigPose.new(rig)
	_world = RigMath.create_world(rig)
	crawl = RigCrawl.new(rig)
	_push_sampler = RigPush.new(rig)
	_push_pose = RigPose.new(rig)
	_crouch_pose = RigPose.new(rig)
	_crawl_pose = RigPose.new(rig)
	for t in [WalkTuning.T, RunTuning.T, SprintTuning.data()]:
		var g := RigGait.from_tuning(rig, t)
		_gaits.append(g)
		_gait_fx.append(_step_fx_params(g))
	_gait = RigGait.new()
	_gait.copy_from(_gaits[0])
	var wall := RigWall.new(rig)
	_actions = {
		&"skid_turn": SkidTurnAction.new(rig, _gaits[1]),
		&"roll": RollAction.new(rig, false),
		&"roll_back": RollAction.new(rig, true),
		&"dodge": DodgeAction.new(rig),
		&"jump": JumpAction.new(rig),
		&"step_up": StepUpAction.new(rig),
		&"double_jump": AirActions.DoubleJump.new(rig),
		&"wall_kick": AirActions.WallKick.new(rig, wall),
		&"wall_grab": WallActions.Grab.new(rig, wall),
		&"wall_jump": WallActions.Jump.new(rig, wall),
	}
	_actions.merge(LedgeActions.create(rig, ledge))
	for path in _provider_paths():
		if ResourceLoader.exists(path):
			var provider: Script = load(path)
			_actions.merge(provider.create(rig))
			if provider.has_method("apply_guard"):
				_guard_provider = provider
			if provider.has_method("apply_carry"):
				_carry_provider = provider
			if provider.has_method("attach"):
				_attachers.append(provider)
			if provider.has_method("create_swimmer"):
				_swimmer = provider.create_swimmer(rig)
	_wall_sampler = wall
	_check_hang_offset()
	_build_nodes()
	_build_orders()
	for provider in _attachers:
		provider.attach(self)
	_hist_world.resize(HISTORY * WORLD_FLOATS)
	_hist_time.resize(HISTORY)
	_hist_pos.resize(HISTORY)
	_hist_props.resize(HISTORY)
	_compose()
	_render()


## Provider list, with work-in-progress overrides for development runs only: the environment
## variable RIG_PROVIDER_OVERRIDES="<stable path>=<wip path>;..." swaps or adds providers, so a
## half-finished group never has to be referenced by the shipping list.
static func _provider_paths() -> Array:
	var paths: Array = ACTION_PROVIDERS.duplicate()
	var env := OS.get_environment("RIG_PROVIDER_OVERRIDES")
	if env.is_empty():
		return paths
	for pair in env.split(";", false):
		var kv := pair.split("=")
		if kv.size() != 2:
			continue
		var at := paths.find(kv[0])
		if at >= 0:
			paths[at] = kv[1]
		else:
			paths.append(kv[1])
	return paths


static var _instances := 0


func _enter_tree() -> void:
	_instances += 1


func _exit_tree() -> void:
	_instances -= 1
	if _instances <= 0:
		# Drop the shared rig data (atlas texture, images, parts) once no adventurer uses it.
		RigData.release_shared()


func _check_hang_offset() -> void:
	var expected := -ledge.hang_origin
	if not expected.is_equal_approx(HANG_GRIP_OFFSET) and expected.distance_to(HANG_GRIP_OFFSET) > 1.0:
		push_warning("HANG_GRIP_OFFSET %s differs from the solved hang %s" % [HANG_GRIP_OFFSET, expected])
	if ledge.top_origin.distance_to(LEDGE_TOP_OFFSET) > 0.5:
		push_warning("LEDGE_TOP_OFFSET %s differs from %s" % [LEDGE_TOP_OFFSET, ledge.top_origin])


func _step_fx_params(g: RigGait) -> Dictionary:
	var dust := {"count": int(g.dust_count), "life": g.dust_life, "speed": g.dust_speed, "rise": g.dust_rise, "spread": g.dust_spread, "dir": -1}
	var debris := {"sprite": "debris", "count": int(g.debris_count), "life": g.debris_life, "speed": g.debris_speed, "up": g.debris_up, "gravity": g.debris_gravity, "angle": PI * 1.1, "cone": 0.7, "floor": 0.0, "restitution": 0.3, "layer": "back"}
	return {"dust": dust, "debris": debris, "has_debris": g.debris > 0.5}


func _build_nodes() -> void:
	_material = ShaderMaterial.new()
	_material.shader = PART_SHADER
	var ghosts := Node2D.new()
	ghosts.name = "Ghosts"
	add_child(ghosts)
	for i in RigFx.MAX_GHOSTS:
		var group := CanvasGroup.new()
		group.visible = false
		ghosts.add_child(group)
		_ghost_groups.append(group)
		_ghost_sprites.append(_make_sprites(group, null))
	var fx_mat := ShaderMaterial.new()
	fx_mat.shader = FX_SHADER
	_fx_back = MultiMeshInstance2D.new()
	_fx_back.name = "FxBack"
	_fx_back.multimesh = RigFx.create_multimesh()
	_fx_back.texture = rig.atlas
	_fx_back.material = fx_mat
	add_child(_fx_back)
	_parts_node = Node2D.new()
	_parts_node.name = "Parts"
	_parts_node.material = _material
	add_child(_parts_node)
	_sprites.assign(_make_sprites(_parts_node, _material))
	_fx_front = MultiMeshInstance2D.new()
	_fx_front.name = "FxFront"
	_fx_front.multimesh = RigFx.create_multimesh()
	_fx_front.texture = rig.atlas
	_fx_front.material = fx_mat
	add_child(_fx_front)


func _make_sprites(parent: Node, mat: Material) -> Array[Sprite2D]:
	var list: Array[Sprite2D] = []
	for part in rig.parts:
		var s := Sprite2D.new()
		s.name = part.name
		s.texture = rig.atlas
		s.centered = false
		s.region_enabled = true
		s.region_rect = part.region
		s.offset = Vector2(part.src.position) - part.pivot
		s.use_parent_material = mat != null
		parent.add_child(s)
		list.append(s)
	return list


# Port of the JS drawOrder rules: a part moves with its followers right after or before a target.
func _build_orders() -> void:
	var followers := []
	for p in rig.parts:
		var f := PackedInt32Array()
		for j in rig.parts.size():
			if rig.parts[j].follows == p.name:
				f.append(j)
		followers.append(f)
	var raised: Array = [["foreArmB", "after", "head"]]
	var prev := "foreArmB"
	for p in rig.parts:
		if p.follows.is_empty() and p.name != "handB" and rig.part_index.has("handB") and p.bone in [RigBone.GRIP_B, RigBone.GLOVE_B, RigBone.HAND_B]:
			raised.append([p.name, "after", prev])
			prev = p.name
	raised.append(["handB", "after", prev])
	var sets := {}
	for i in ORDER_RAISED_B:
		sets[i] = DRAW_ORDER_RULES[i]
	sets[ORDER_RAISED_B] = raised
	# Providers add presets (ids from 10 up) as {id: [[part, "after"|"before", target], ...]}.
	for path in _provider_paths():
		if ResourceLoader.exists(path):
			var provider: Script = load(path)
			if provider.has_method("draw_orders"):
				sets.merge(provider.draw_orders())
	for id in sets:
		var order := PackedInt32Array(range(rig.parts.size()))
		for rule: Array in sets[id]:
			if not rig.part_index.has(rule[0]) or not rig.part_index.has(rule[2]):
				continue
			var lead: int = rig.part_index[rule[0]]
			var target: int = rig.part_index[rule[2]]
			var group := PackedInt32Array()
			var rest := PackedInt32Array()
			for idx in order:
				if idx == lead or (followers[lead] as PackedInt32Array).has(idx):
					group.append(idx)
				else:
					rest.append(idx)
			var at := rest.find(target)
			if rule[1] == "after":
				at += 1
				while at < rest.size() and (followers[target] as PackedInt32Array).has(rest[at]):
					at += 1
			else:
				while at > 0 and (followers[target] as PackedInt32Array).has(rest[at - 1]):
					at -= 1
			order = rest.slice(0, at) + group + rest.slice(at)
		_orders[id] = order


# ---------------------------------------------------------------------------------------------
# Public API

## Tick: the game calls it every frame with the absolute horizontal speed (units/s).
func set_locomotion(speed: float, delta: float) -> void:
	_tick_dt = delta
	_time += delta
	_speed = maxf(0.0, speed)
	_advance_locomotion(delta)
	if _jump_hold >= 0.0:
		_jump_hold += delta
		if _airborne or _jump_hold > JumpTuning.T.holdMax:
			_jump_hold = -1.0
	if _airborne:
		_air_time += delta
	if _land_t >= 0.0:
		_land_t += delta
		if _land_t > RigAir.landing_duration(_land_s):
			_land_t = -1.0
	hang_catch_age += delta
	if _wall:
		_wall_age += delta
	_blend_t += delta
	var prev_t := _action_t
	if _action:
		_action_t = minf(_action_t + delta, _action.duration)
		var rm := _action.root_motion(_action_t)
		var d := rm - _rm_prev
		_rm_prev = rm
		_root += Vector2(d.x * _action.start_facing, d.y)
	_guard_w = move_toward(_guard_w, 1.0 if guard else 0.0, delta / 0.12)
	_compose()
	RigMath.compute_world(rig, pose, _world)
	if _action and _action.tick(self, delta):
		_action_t = _action.duration
	if _action:
		_run_events(prev_t, _action_t)
		if _action and _action_t >= _action.duration:
			_finish_action()
	elif _source == "ground":
		_ground_steps(delta)
	if _wall:
		_wall_slide_fx(delta)
	_record_history()


## Air state and vertical speed (down positive); called every frame.
func set_airborne(airborne: bool, vy: float) -> void:
	if airborne:
		_last_air_vy = vy
	if airborne and not _airborne:
		_air_time = 0.0
	if not airborne and _airborne and _action and _action.ends_on_landing:
		_action_t = _action.duration
		_finish_action()
	if not airborne and _airborne and _free() and _air_time > 0.04 and not is_swimming():
		_start_landing(_last_air_vy)
	_airborne = airborne
	_vy = vy


## Crouch state and the crawl speed (absolute, units/s); called every frame. While crouching it
## takes precedence over set_locomotion: standing still crouches, moving crawls.
func set_crouch(crouching: bool, crawl_speed: float, delta: float) -> void:
	var CT: Dictionary = CrawlTuning.T
	_crouch = crouching
	_crawl_speed = maxf(0.0, crawl_speed) if crouching else 0.0
	_crouch_w = move_toward(_crouch_w, 1.0 if crouching else 0.0, delta / CT.crouchTime)
	var moving: bool = crouching and _crawl_speed > CT.crawlMinSpeed
	_crawl_w = move_toward(_crawl_w, 1.0 if moving else 0.0, delta / CT.crawlTime)
	_crouch_time += delta
	var prev := _crawl_phase
	_crawl_phase = RigMath.frac(_crawl_phase + _crawl_speed * delta / crawl.cycle_length())
	if _crawl_w > 0.5 and _crouch_w > 0.5 and _crawl_speed > 0.0 and _free() and not _airborne:
		for side in ["front", "back"]:
			if SkidTurnAction._crossed(crawl.knee_phase(side, prev), crawl.knee_phase(side, _crawl_phase), 0.0):
				footstep.emit(StringName(side), CT.juice.stepStrength)
				_spawn_point_fx("dust", CT.juice.dust, crawl.knee_contact_x(side), 0.0)
			if SkidTurnAction._crossed(crawl.hand_phase(side, prev), crawl.hand_phase(side, _crawl_phase), 0.0):
				footstep.emit(StringName(side), CT.juice.stepStrength)
				_spawn_point_fx("dust", CT.juice.dust, crawl.hand_contact_x(side), 0.0)


## Steps up onto a ledge of the given height (STEP_MAX_HEIGHT at most); root motion is
## (STEP_FORWARD, -height). Lower than about 30 units the game should just snap to the floor.
func play_step_up(height: float) -> bool:
	if height < 0.0 or height > STEP_MAX_HEIGHT + 0.5:
		return false
	step_height = height
	return play_action(&"step_up")


## Push against a wall at PUSH_CONTACT_OFFSET; called every frame (blends in and out).
func set_push(active: bool, delta: float) -> void:
	var P: Dictionary = StepTuning.T.push
	_push = active
	_push_w = move_toward(_push_w, 1.0 if active else 0.0, delta / P.blend)
	if _push_w <= 0.0:
		return
	_push_time += delta
	if active and _free() and not _airborne:
		_push_step += delta * P.scrapeHz
		if _push_step >= 1.0:
			_push_step -= 1.0
			footstep.emit(&"back", P.stepStrength)
			var p := anchor_world("toeB")
			if juice:
				fx.spawn("dust", P.dust, p.x, global_position.y, 0.0, _facing, global_position.y, _time)


func is_pushing() -> bool:
	return _push_w > 0.5


## Shows the weapon's prop in hand: &"fists" (boxing gloves), &"revolver", &"rifle", &"bow",
## &"kunai" or &"none".
func set_weapon(id: StringName) -> void:
	weapon = id
	weapon_mask = 0
	for key in WEAPON_PROPS.get(id, []):
		if rig.props.has(key):
			weapon_mask |= rig.props[key].bit


## Guard stance on top of idle and locomotion (blends in and out).
func set_guard(on: bool) -> void:
	guard = on


## Seat or mattress height above the ground (units) for sit_down / lie_down and their loops.
func set_rest_height(height: float) -> void:
	action_params[&"rest_height"] = height


## Upward aim limits (degrees, negative up) the rig clamps set_gun_aim to, per weapon.
const REVOLVER_AIM_MIN_DEG: float = GunTuning.T.revolver.aimMin
const RIFLE_AIM_MIN_DEG: float = GunTuning.T.rifle.aimMin


## Gun aim angle in world radians relative to the facing (about -75 deg up to +60 deg down),
## called every frame while aiming the revolver or the rifle.
func set_gun_aim(angle: float) -> void:
	action_params[&"gun_aim"] = angle


## Muzzle of the weapon in hand: {"point": world Vector2, "direction": world unit Vector2}, or
## empty when no firearm shows.
func get_muzzle() -> Dictionary:
	if _action and _action.has_method("muzzle"):
		return _action.muzzle(self)
	for key in ["ak47", "revolver"]:
		if rig.props.has(key) and (pose.props & rig.props[key].bit) != 0:
			var name := "%s.muzzle" % key
			return {"point": anchor_world(name), "direction": get_anchor_direction(name)}
	return {}


## Rifle burst loop on or off (while the rifle is raised).
func set_rifle_firing(firing: bool) -> void:
	action_params[&"rifle_firing"] = firing


## Bow aim, called every frame while aiming: arrow angle in world radians from facing-forward
## (about -80 deg up to +45 deg down) and draw power 0..1 (string pull).
func set_bow_aim(angle: float, power: float = 1.0) -> void:
	action_params[&"bow_aim"] = angle
	action_params[&"bow_power"] = clampf(power, 0.0, 1.0)


## World direction the hit or the bullet travels, read by hurt and shot_hit when they start.
func set_hit_direction(direction: Vector2) -> void:
	action_params[&"hit_direction"] = direction.normalized() if direction.length() > 0.0 else Vector2.LEFT


## Id of the playing action, or &"" when none.
func current_action() -> StringName:
	return _action.id if _action else &""


## World position of a rig anchor (e.g. &"toeF", &"revolver.muzzle").
func get_anchor(name: StringName) -> Vector2:
	return anchor_world(name)


## World direction of the bone that carries an anchor (+x of the bone, facing applied).
func get_anchor_direction(name: StringName) -> Vector2:
	var a := rig.anchor(name)
	return Vector2.from_angle(RigMath.bone_angle(_world, int(a.x)))


## The action object registered under id (for action-specific queries), or null.
func get_action(id: StringName) -> RigAction:
	return _actions.get(id)


## Flying kick contact: world point of the sole and the kick direction (hip to ankle), for the
## breakable wall. Empty when no kick is playing.
func get_kick_contact() -> Dictionary:
	if _action and _action.has_method("contact_point"):
		return {"point": _action.contact_point(self), "direction": _action.kick_direction(self)}
	return {}


## Arrow point and direction (world) for the playing bow_aim or bow_release; empty otherwise.
## Read it in the &"release" handler.
func get_arrow_release() -> Dictionary:
	if _action and _action.has_method("arrow_release"):
		return _action.arrow_release(self)
	return {}


## Contact callback for open-ended attacks (flying kick): forwards to the playing action.
func kick_impact() -> void:
	if _action and _action.has_method("impact"):
		_action.impact(self)


## Punch reach feedback (whiff trail or hit spark) from the playing action, when it draws one.
func punch_reach(from: Vector2, to: Vector2, hit: bool) -> void:
	if juice and _action and _action.has_method("reach_fx"):
		_action.reach_fx(self, from, to, hit)


## Held look while still: dir 1 tilts the head down, -1 looks up (neck and a bit of torso), 0 eases
## back. Call every physics frame; the offset rides on the ground pose.
## amount (0..1) scales the pose, so the game can ease the look in while the stick is held.
func set_look(dir: int, delta: float, amount := 1.0) -> void:
	var k: Dictionary = LT.T.look
	if dir != 0:
		_look_dir = dir
	var goal := clampf(amount, 0.0, 1.0) if dir != 0 else 0.0
	var blend: float = k.blendIn if goal > _look_w else k.blendOut
	_look_w = move_toward(_look_w, goal, delta / maxf(blend, 0.001))


## World transform of a bone for this frame's pose (facing and root applied).
func bone_transform(bone: int) -> Transform2D:
	var o := bone * 6
	return Transform2D(Vector2(_world[o], _world[o + 1]), Vector2(_world[o + 2], _world[o + 3]), global_position + Vector2(_world[o + 4], _world[o + 5]))


## Body bone under a world point: the visible body part whose box is nearest (props, hair and
## scarf skipped); -1 when there is none.
func bone_at(point: Vector2) -> int:
	var best := -1
	var best_d := INF
	for part in rig.parts:
		if not part.has_box or part.prop_bit != 0 or RigMath.SETTLE_IGNORE.has(part.name):
			continue
		if part.hide_bit != 0 and (pose.props & part.hide_bit) != 0:
			continue
		var q := bone_transform(part.bone).affine_inverse() * point
		var c := q.clamp(part.box.position, part.box.end)
		var d := c.distance_squared_to(q)
		if d < best_d:
			best_d = d
			best = part.bone
	return best


## Ends the playing action now (as finished).
func stop_action() -> void:
	if _action:
		_action_t = _action.duration
		_finish_action()


## Swimming, called every frame while in the water; takes precedence over locomotion and air.
## mode: &"tread", &"surface", &"under" or &"under_idle"; velocity in world units/s.
func set_swim(mode: StringName, velocity: Vector2, delta: float) -> void:
	if _swimmer == null:
		return
	_swim_mode = mode
	_swim_frame = Engine.get_physics_frames() if Engine.is_in_physics_frame() else Engine.get_process_frames()
	var stroke: float = _swimmer.tick(self, mode, velocity, delta)
	if stroke > 0.0 and _action == null:
		swim_stroke.emit(stroke)


func is_swimming() -> bool:
	if _swim_mode == &"":
		return false
	var now_frame := Engine.get_physics_frames() if Engine.is_in_physics_frame() else Engine.get_process_frames()
	return now_frame - _swim_frame <= 1


## True when a facing change applies right away (no action, or an aim loop that mirrors in place).
func can_flip_now() -> bool:
	return _action == null or _action.id in FLIP_OK_ACTIONS


func is_crouching() -> bool:
	return _crouch_w > 0.5


## Wall slide state and the slide speed (down positive); called every frame.
func set_wall_slide(active: bool, slide_speed: float) -> void:
	wall_speed = maxf(0.0, slide_speed)
	if active and not _wall and _free():
		_enter_wall()
	elif not active and _wall:
		_wall = false
		action_event.emit(&"wall_slide", &"slide_stop")


func play_action(id: StringName) -> bool:
	if _hanging and id == &"jump":
		id = &"ledge_leap"
	if _wall and id == &"jump":
		id = &"wall_jump"
	var next: RigAction = _actions.get(id)
	if next == null:
		return false
	if next.requires == "air" and not _airborne:
		return false
	if next.requires == "ground" and (_airborne or _hanging or _wall):
		return false
	var current := _action.id if _action else &""
	if _action and not (_can_cancel(id) or id in _action.cancel_by):
		return false
	match id:
		&"ledge_climb", &"ledge_drop", &"ledge_leap":
			if not _hanging:
				return false
		&"wall_jump", &"wall_kick":
			if not _wall and current != &"wall_grab":
				return false
		&"double_jump":
			if not _airborne:
				return false
		&"ledge_grab", &"wall_grab":
			pass
		&"hurt", &"shot_hit":
			# A hit knocks the body off the ledge too.
			pass
		_:
			if _hanging:
				return false
	if _action:
		_cancel_action()
	if _hanging:
		_hanging = false
	if _wall:
		_wall = false
		action_event.emit(&"wall_slide", &"slide_stop")
	_action = next
	_action_t = 0.0
	_event_i = 0
	_rm_prev = Vector2.ZERO
	_iframes = false
	_action.begin(self)
	_land_t = -1.0
	_jump_hold = -1.0
	return true


func is_action_playing() -> bool:
	return _action != null


func action_elapsed() -> float:
	return _action_t if _action else 0.0


func is_hanging() -> bool:
	return _hanging


func is_wall_sliding() -> bool:
	return _wall


func take_root_motion() -> Vector2:
	var r := _root
	_root = Vector2.ZERO
	return r


## Screen shake requested by the current pose (rig units), for the game camera.
func get_shake() -> Vector2:
	return Vector2(pose.shake_x, pose.shake_y)


# ---------------------------------------------------------------------------------------------
# Host API used by actions

func get_entry_speed() -> float:
	return _speed_smooth


func get_loco_phase() -> float:
	return _phase


func incoming_speed() -> float:
	return Vector2(_speed, _last_air_vy).length()


func now() -> float:
	return _time


func anchor_world(name: String) -> Vector2:
	return global_position + RigMath.anchor_point(rig, _world, name)


## Ground pose (locomotion plus landing) into p; dip lowers the hip before the legs are solved.
func sample_ground(p: RigPose, dip: float, use_juice: bool) -> void:
	var d := dip
	if _land_t >= 0.0:
		d += RigAir.landing_dip(_land_t, _land_s)
	if _idle_w >= 0.999:
		RigLocomotion.sample_idle(rig, p, _idle_u, use_juice, d)
	else:
		RigLocomotion.sample_gait(rig, p, _phase, _gait, use_juice, d)
		if _idle_w > 0.001:
			RigLocomotion.sample_idle(rig, _scratch, _idle_u, use_juice, d)
			p.blend_toward(_scratch, _idle_w)
	if _land_t >= 0.0:
		RigAir.apply_landing(p, _land_t, _land_s, use_juice)
	p.facing = _facing
	if _crouch_w > 0.001:
		var cw := RigMath.smooth01(_crawl_w)
		if cw < 0.999:
			crawl.sample_crouch(_crouch_pose, _crouch_time, use_juice, _facing)
		if cw > 0.001:
			crawl.sample_crawl(_crawl_pose, _crawl_phase, use_juice, _facing)
			if cw < 0.999:
				_crouch_pose.blend_toward(_crawl_pose, cw)
			else:
				_crouch_pose.copy_from(_crawl_pose)
		p.blend_toward(_crouch_pose, RigMath.smooth01(_crouch_w))
		p.facing = _facing
	if _carry_provider and _action == null:
		_carry_provider.apply_carry(rig, p, weapon, _time)
		p.facing = _facing
	if _guard_provider and _guard_w > 0.001:
		_guard_provider.apply_guard(rig, p, RigMath.smooth01(_guard_w), _time)
		p.facing = _facing
	if _push_w > 0.001:
		_push_sampler.sample(_push_pose, _push_time, use_juice, _facing)
		p.blend_toward(_push_pose, RigMath.smooth01(_push_w))
		p.facing = _facing
	if _look_w > 0.001:
		var lk: Dictionary = LT.T.look.up if _look_dir < 0 else LT.T.look.down
		var lw := RigMath.smooth01(_look_w)
		p.rot[RigBone.TORSO] += deg_to_rad(lk.torso) * lw
		p.rot[RigBone.NECK] += deg_to_rad(lk.neck) * lw


func spawn_fx_local(type: String, params: Dictionary, local: Vector2, on_ground := false) -> void:
	if not juice:
		return
	var w := global_position + local
	fx.spawn(type, params, w.x, w.y, 0.0, pose.facing, global_position.y if on_ground else w.y + 4000.0, _time)


func wall_contact_fx(burst: bool) -> void:
	if not juice:
		return
	var T: Dictionary = WallTuning.T
	# Contact points: each palm and the braced sole, on the wall plane.
	for a in ["fistF", "fistB", "soleF"]:
		var p := anchor_world(a)
		p.x = global_position.x + T.wallX * pose.facing
		fx.spawn("dust", T.fxDust.merged({"count": 4}) if burst else T.fxDust, p.x, p.y, 0.0, pose.facing, p.y + 4000.0, _time)
		if a == "soleF" or burst:
			fx.spawn("ledgeDebris", T.fxChips, p.x, p.y, 0.0, pose.facing, 0.0, _time)


# ---------------------------------------------------------------------------------------------
# Internals

func _set_facing(value: int) -> void:
	if value == _facing:
		_pending_facing = 0
		return
	if _action == null:
		_facing = value
		_pending_facing = 0
	elif _action.id in FLIP_OK_ACTIONS:
		_facing = value
		_action.start_facing = value
		_pending_facing = 0
		_start_blend(FLIP_BLEND)
	elif _action_t == 0.0 and _action.id in [&"ledge_grab", &"ledge_descend", &"wall_grab"]:
		# The game aligns these to the ledge or wall right after starting them.
		_facing = value
		_action.start_facing = value
	else:
		_pending_facing = value


func _weapon_stowed() -> bool:
	return _action != null and _action.id == &"hero_landing" and weapon == &"rifle"


func _free() -> bool:
	return _action == null and not _hanging and not _wall


func _can_cancel(id: StringName) -> bool:
	if _action.id == &"double_jump" and id in [&"ledge_grab", &"wall_grab"]:
		return true
	if _action.id in [&"jump", &"wall_grab"] and id in [&"wall_kick", &"double_jump", &"step_up"]:
		return true
	# Reactions interrupt any action.
	if id in [&"hurt", &"shot_hit"] and _action.id != id:
		return true
	# Evades chain into each other (the game gates the interval).
	return _action.id in EVADES and id in EVADES and _action_t >= DodgeTuning.T.cancelFrom


func _cancel_action() -> void:
	var id := _action.id
	if _iframes:
		action_event.emit(id, &"iframes_end")
		_iframes = false
	action_event.emit(id, &"cancelled")
	_action = null
	action_finished.emit(id)
	_start_blend(0.06)


func _advance_locomotion(delta: float) -> void:
	_speed_smooth = lerpf(_speed_smooth, _speed, 1.0 - exp(-delta / LT.T.gaitSmoothing))
	var s := _speed_smooth
	var target: RigGait
	if s <= WALK_SPEED:
		_gait.copy_from(_gaits[0])
	elif s <= RUN_SPEED:
		_gait.blend(_gaits[0], _gaits[1], RigMath.smooth01((s - WALK_SPEED) / (RUN_SPEED - WALK_SPEED)))
	elif s <= SPRINT_SPEED:
		_gait.blend(_gaits[1], _gaits[2], RigMath.smooth01((s - RUN_SPEED) / (SPRINT_SPEED - RUN_SPEED)))
	else:
		_gait.copy_from(_gaits[2])
	var idle_target := 1.0 - clampf(_speed / LT.T.idleSpeed, 0.0, 1.0)
	_idle_w = lerpf(_idle_w, idle_target, 1.0 - exp(-delta / LT.T.idleSmoothing))
	if absf(_idle_w - idle_target) < 0.002:
		_idle_w = idle_target
	_idle_u = fmod(_idle_u + delta / IdleTuning.T.duration, 1.0)
	_prev_phase = _phase
	_phase = RigMath.frac(_phase + _speed * delta / _gait.cycle_length())


var _prev_phase := 0.0


func _ground_steps(_delta: float) -> void:
	if 1.0 - _idle_w < LT.T.stepMinWeight or _speed <= 1.0:
		return
	var gi := 0 if _speed_smooth < (WALK_SPEED + RUN_SPEED) * 0.5 else (1 if _speed_smooth < (RUN_SPEED + SPRINT_SPEED) * 0.5 else 2)
	var params: Dictionary = _gait_fx[gi]
	var strength := clampf(remap(_speed_smooth, WALK_SPEED, SPRINT_SPEED, LT.T.stepStrengthWalk, LT.T.stepStrengthSprint), 0.2, 1.0)
	for k in 2:
		var edge := 0.5 * k
		if SkidTurnAction._crossed(_prev_phase, _phase, edge):
			footstep.emit(&"front" if k == 0 else &"back", strength)
			_spawn_point_fx("dust", params.dust, RigLocomotion.heel_contact_x(_gait), 0.0)
		if params.has_debris and SkidTurnAction._crossed(_prev_phase, _phase, RigMath.frac(edge + _gait.duty)):
			var x := RigLocomotion.toe_off_x(_gait)
			_spawn_point_fx("burst", params.debris, x, 0.0)
			_spawn_point_fx("dust", params.dust, x, 0.0)


func _spawn_point_fx(type: String, params: Dictionary, x: float, y: float) -> void:
	if not juice:
		return
	var w := global_position + Vector2(x * pose.facing + pose.root_x, y)
	fx.spawn(type, params, w.x, w.y, 0.0, pose.facing, global_position.y, _time)


func _start_landing(vy: float) -> void:
	_land_s = RigAir.landing_strength(vy)
	_land_t = 0.0
	_jump_hold = -1.0
	landed.emit(_land_s)
	footstep.emit(&"front", _land_s)
	if juice:
		var J: Dictionary = JumpTuning.T.juice
		var params: Dictionary = J.landDust.merged({"count": int(J.landDust.count + J.landDustStrong * _land_s), "dir": 0})
		for a in ["soleF", "soleB"]:
			var p := anchor_world(a)
			fx.spawn("dust", params, p.x, global_position.y, 0.0, _facing, global_position.y, _time)


func _enter_wall() -> void:
	_wall = true
	_wall_age = 0.0
	_wall_fx_t = 0.0
	action_event.emit(&"wall_slide", &"slide_start")


func _wall_slide_fx(delta: float) -> void:
	var T: Dictionary = WallTuning.T
	if wall_speed < T.fxMinSpeed:
		return
	_wall_fx_t += delta * wall_speed
	if _wall_fx_t >= T.fxSpacing:
		_wall_fx_t = fmod(_wall_fx_t, T.fxSpacing)
		wall_contact_fx(false)


func _source_id() -> String:
	if _action:
		return "action:" + _action.id
	if _hanging:
		return "hang"
	if _wall:
		return "wall"
	if is_swimming():
		return "swim"
	if _airborne or _jump_hold >= 0.0:
		return "air"
	return "ground"


func _start_blend(duration: float) -> void:
	_snap.copy_from(pose)
	_blend_t = 0.0
	_blend_dur = duration


func _compose() -> void:
	var src := _source_id()
	if src != _source:
		if not _source.is_empty():
			var dur: float = LT.T.exitBlend
			if src.begins_with("action:"):
				dur = LT.T.enterBlend
			elif src == "air":
				dur = JumpTuning.T.airBlend
			elif src == "ground" and _land_t >= 0.0:
				dur = 0.05
			if _blend_t >= _blend_dur or src.begins_with("action:"):
				_start_blend(dur)
			else:
				_start_blend(maxf(dur, 0.04))
		_source = src
	if _action:
		_action.sample(_action_t, _target, juice)
		# The weapon stays held through the jump's takeoff swing and the hero landing (which plants
		# the free front hand; the two-handed rifle is stowed instead, like on a climb).
		if _carry_provider and _action.id in CARRY_ACTIONS and not _weapon_stowed():
			_carry_provider.apply_carry(rig, _target, weapon, _time)
			_target.facing = _facing
	elif _hanging:
		ledge.sample(_target, 0.0, hang_catch_age, catch_k, ledge.hang_origin, _facing, juice, _time)
	elif src == "swim":
		_swimmer.sample(self, _target, juice)
	elif _wall:
		_wall_sampler.sample(_target, wall_speed, _wall_age, juice)
		_target.facing = _facing
	elif src == "air":
		if _jump_hold >= 0.0 and not _airborne:
			_target.copy_from(_takeoff_pose)
		else:
			RigAir.sample_air(rig, _target, _vy, _speed, juice, _air_time)
			_target.facing = _facing
			var w := _inherit * exp(-_air_time / JumpTuning.T.inheritDecay)
			if w > 0.01:
				_target.blend_toward(_takeoff_pose, w)
				_target.facing = _facing
		# Weapon carry in the air too (the frozen takeoff pose already holds it from the jump).
		if _carry_provider:
			_carry_provider.apply_carry(rig, _target, weapon, _time)
			_target.facing = _facing
	else:
		sample_ground(_target, 0.0, juice)
	if not (_action and _action.id in HIDE_WEAPON_ACTIONS) and not _weapon_stowed():
		_target.props |= weapon_mask
	if _action and _action.max_turn > 0.0 and _tick_dt > 0.0:
		var lim := deg_to_rad(_action.max_turn) * _tick_dt * 60.0
		for i in rig.bone_count:
			var d := wrapf(_target.rot[i] - pose.rot[i], -PI, PI)
			if absf(d) > lim:
				_target.rot[i] = pose.rot[i] + signf(d) * lim
	if _blend_t < _blend_dur:
		pose.copy_from(_snap)
		pose.blend_toward(_target, RigMath.smooth01(_blend_t / _blend_dur))
		pose.facing = _target.facing
		pose.draw_order = _target.draw_order
		pose.props = _target.props
	else:
		pose.copy_from(_target)


func _run_events(_t0: float, t1: float) -> void:
	var a := _action
	while _event_i < a.events.size() and float(a.events[_event_i].t) <= t1:
		var ev: Dictionary = a.events[_event_i]
		_event_i += 1
		if ev.has("signal"):
			if ev.signal == &"iframes_start":
				_iframes = true
			elif ev.signal == &"iframes_end":
				_iframes = false
			action_event.emit(a.id, ev.signal)
		elif ev.has("footstep"):
			footstep.emit(ev.footstep, ev.strength)
		elif ev.has("flip"):
			_facing = -_facing
		elif ev.has("fx"):
			_action_fx(ev)
		elif ev.has("custom"):
			a.custom_event(ev, self)
		if _action != a:
			return


func _action_fx(ev: Dictionary) -> void:
	if not juice:
		return
	var params: Dictionary = ev.params
	var ground := global_position.y
	if ev.has("anchor"):
		var an := rig.anchor(ev.anchor)
		var p := global_position + RigMath.point(_world, int(an.x), an.y, an.z)
		fx.spawn(ev.fx, params, p.x, minf(p.y, ground), RigMath.bone_angle(_world, int(an.x)), pose.facing, ground, _time)
	elif ev.has("x"):
		_spawn_point_fx(ev.fx, params, ev.x, ev.y)
	else:
		fx.spawn(ev.fx, params, global_position.x, ground, 0.0, pose.facing, ground, _time)


func _finish_action() -> void:
	var a := _action
	_action = null
	if _iframes:
		# Ended early (landing, stop_action): close the invulnerability window it opened.
		_iframes = false
		action_event.emit(a.id, &"iframes_end")
	if a.exit_phase >= 0.0:
		_phase = a.exit_phase
		_prev_phase = _phase
	if a.id == &"jump":
		_takeoff_pose.copy_from(pose)
		_inherit = JumpTuning.T.inherit * (1.0 - _idle_w)
		_jump_hold = 0.0
	if a.next_state.begins_with("action:"):
		var next_id := StringName(a.next_state.substr(7))
		_iframes = false
		action_finished.emit(a.id)
		play_action(next_id)
		return
	match a.next_state:
		"hanging":
			_hanging = true
			hang_catch_age = a.duration if a.id == &"ledge_grab" else LedgeTuning.T.descendCatchAge
		"wall":
			_enter_wall()
	if _pending_facing != 0:
		_facing = _pending_facing
		_pending_facing = 0
	_iframes = false
	action_finished.emit(a.id)


# ---------------------------------------------------------------------------------------------
# Rendering

func _process(_delta: float) -> void:
	_render()


func _record_history() -> void:
	_hist_head = (_hist_head + 1) % HISTORY
	_hist_count = mini(_hist_count + 1, HISTORY)
	var o := _hist_head * WORLD_FLOATS
	for i in WORLD_FLOATS:
		_hist_world[o + i] = _world[i]
	_hist_time[_hist_head] = _time
	_hist_pos[_hist_head] = global_position
	_hist_props[_hist_head] = pose.props


func _apply_sprites(sprites: Array, world: PackedFloat32Array, base: int, props: int, p: RigPose) -> void:
	for i in rig.parts.size():
		var part: RigData.Part = rig.parts[i]
		var s: Sprite2D = sprites[i]
		var show := true
		if part.prop_bit != 0 and (props & part.prop_bit) == 0:
			show = false
		elif part.hide_bit != 0 and (props & part.hide_bit) != 0:
			show = false
		elif part.frame_field >= 0:
			var f := roundi(p.face[part.frame_field]) if p else 0
			if f <= 0 or f > part.frame_count:
				show = false
			else:
				s.region_rect = Rect2(part.region.position + Vector2((f - 1) * part.frame_step), part.region.size)
		s.visible = show
		if not show:
			continue
		var o := base + part.bone * 6
		s.transform = Transform2D(Vector2(world[o], world[o + 1]), Vector2(world[o + 2], world[o + 3]), Vector2(roundf(world[o + 4]), roundf(world[o + 5])))


func _render() -> void:
	if rig == null:
		return
	_apply_sprites(_sprites, _world, 0, pose.props, pose)
	var preset := pose.draw_order
	if preset == 0:
		var neck_y := _world[RigBone.NECK * 6 + 5]
		var arm_y := minf(_world[RigBone.FORE_ARM_B * 6 + 5], _world[RigBone.HAND_B * 6 + 5])
		var hand_tip := RigMath.anchor_point(rig, _world, "fistB").y
		arm_y = minf(arm_y, hand_tip)
		if _b_raised and arm_y > neck_y + RAISE_OFF:
			_b_raised = false
		elif not _b_raised and arm_y < neck_y - RAISE_ON:
			_b_raised = true
		if _b_raised:
			preset = ORDER_RAISED_B
	else:
		_b_raised = false
	if preset != _draw_order:
		_draw_order = preset
		var order: PackedInt32Array = _orders.get(_draw_order, _orders[0])
		for k in order.size():
			_parts_node.move_child(_sprites[order[k]], k)
	var flash := Vector2(pose.flash, pose.tint)
	if flash != _flash_state:
		_flash_state = flash
		var amount := pose.flash if pose.flash > 0.0 else pose.tint
		_material.set_shader_parameter("fill_amount", amount)
		_material.set_shader_parameter("fill_color", Color.WHITE if pose.flash > 0.0 else pose.tint_color)
	fx.update(_time)
	fx.upload(_fx_back.multimesh, _fx_front.multimesh, global_position)
	_render_ghosts()


func _render_ghosts() -> void:
	for g in RigFx.MAX_GHOSTS:
		var group := _ghost_groups[g]
		if g >= fx.ghost_count or _hist_count < 2:
			group.visible = false
			continue
		var want := _time - fx.ghost_lag[g]
		var best := _hist_head
		for k in _hist_count:
			var idx := posmod(_hist_head - k, HISTORY)
			best = idx
			if _hist_time[idx] <= want:
				break
		group.visible = true
		group.self_modulate = Color(1, 1, 1, fx.ghost_alpha[g])
		group.position = _hist_pos[best] - global_position
		_apply_sprites(_ghost_sprites[g], _hist_world, best * WORLD_FLOATS, _hist_props[best], null)


# ---------------------------------------------------------------------------------------------
# Debug helpers for the pose sheet tool

## Sets the locomotion state directly (speed, gait phase, idle weight).
func debug_set_locomotion(speed: float, phase: float, idle_weight: float) -> void:
	_speed = speed
	_speed_smooth = speed
	_phase = phase
	_prev_phase = phase
	_idle_w = idle_weight
	_advance_locomotion(0.0)
	_idle_w = idle_weight


func debug_set_air(airborne: bool, vy: float, air_time: float) -> void:
	_airborne = airborne
	_vy = vy
	_last_air_vy = vy
	_air_time = air_time


func debug_set_hanging(catch_age: float) -> void:
	_hanging = true
	hang_catch_age = catch_age
	_source = ""


func debug_set_wall(speed: float, age: float) -> void:
	_wall = true
	wall_speed = speed
	_wall_age = age


func debug_set_push(weight: float, time: float) -> void:
	_push = weight > 0.5
	_push_w = weight
	_push_time = time


func debug_set_crouch(crouch_weight: float, crawl_weight: float, phase: float) -> void:
	_crouch = crouch_weight > 0.5
	_crouch_w = crouch_weight
	_crawl_w = crawl_weight
	_crawl_phase = phase


## Height of the current pose's silhouette (ground to the topmost opaque box corner).
func debug_silhouette_height() -> float:
	RigMath.compute_world(rig, pose, _world)
	var top := INF
	for part in rig.parts:
		if not part.has_box or (part.prop_bit != 0 and (pose.props & part.prop_bit) == 0) or part.frame_field >= 0:
			continue
		var o := part.bone * 6
		for k in 4:
			var px := part.box.end.x if k & 1 else part.box.position.x
			var py := part.box.end.y if k & 2 else part.box.position.y
			top = minf(top, _world[o + 1] * px + _world[o + 3] * py + _world[o + 5])
	return -top


func debug_skip_blend() -> void:
	_compose()
	_blend_t = 1.0
	_blend_dur = 0.0
	_compose()
	RigMath.compute_world(rig, pose, _world)
