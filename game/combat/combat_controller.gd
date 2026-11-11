extends Node

# Combat layer of the player: current weapon (d-pad cycles), X routing per weapon and the rig
# events of the attacks. One handler per weapon; only the fists are ready so far.

signal weapon_changed(id: StringName)
# True while an interactable controls the player (weapon put away, HUD hidden).
signal holstered_changed(holstered: bool)

const Feedback := preload("res://game/feedback.gd")
const Weapons := preload("res://game/combat/weapons.gd")
const Fists := preload("res://game/combat/fists.gd")
const FlyingKick := preload("res://game/combat/flying_kick.gd")
const Bow := preload("res://game/combat/bow.gd")
const Guns := preload("res://game/combat/guns.gd")
const Kunai := preload("res://game/combat/kunai.gd")
const FIREARMS: Array[StringName] = [&"revolver", &"rifle"]
# Weapons whose X on the ground is the boxing combo (unarmed punches bare-handed).
const PUNCHERS: Array[StringName] = [&"fists", &"unarmed"]
# Rig actions that count as "in the aim" per weapon (the entry, the loop and its shots).
const AIM_LOOPS := {
	&"bow": [&"bow_draw", &"bow_aim", &"bow_release", &"bow_cancel"],
	&"revolver": [&"revolver_cock", &"revolver_aim", &"revolver_fire", &"revolver_recock", &"revolver_draw"],
	&"rifle": [&"rifle_raise", &"rifle_aim"],
}
# LT hysteresis on the raw trigger value: in at 0.35, out at 0.15.
const AIM_IN := 0.35
const AIM_OUT := 0.15

var player
var weapon: StringName = &"unarmed"
var fists
var kick
var bow
var guns
var kunai
var holstered := false
var _holster_reasons: Dictionary = {}
# LT state after hysteresis, read by the bow and the guns this frame.
var aim_down := false
# Debug: frames the game was aiming while the rig was outside the aim loop (after a 2-frame grace).
var aim_bad_frames := 0
var _aim_bad_streak := 0
var _orphan_streak := 0
# Rig loops that hold an aim pose; outside the game's aim they must not last.
const AIM_HOLDS: Array[StringName] = [&"bow_draw", &"bow_aim", &"revolver_aim", &"revolver_cock", &"revolver_recock", &"rifle_raise", &"rifle_aim"]
# Objects whose visibility suspends weapon cycling (the F1 HUD uses the d-pad while open).
var cycle_blockers: Array[Object] = []
# Glove prop mask each punch action shows by itself, kept to restore it when leaving &"unarmed".
var _punch_masks: Dictionary = {}


func setup(owner_player) -> void:
	player = owner_player
	fists = Fists.new(player)
	kick = FlyingKick.new(player)
	bow = Bow.new(player)
	guns = Guns.new(player)
	kunai = Kunai.new(player)
	_apply_weapon()
	player.rig.action_event.connect(_on_action_event)
	player.rig.action_finished.connect(_on_action_finished)


func _input(event: InputEvent) -> void:
	bow.aim.on_input(event)
	guns.aim.on_input(event)


# Called by the player every physics frame with its input gate already applied.
func step(delta: float, on_floor: bool, can_act: bool) -> void:
	fists.step(delta)
	_update_aim_trigger()
	if holstered:
		return
	if on_floor:
		kick.refill()
	# One place for weapon switching (also with LT held: cycle ends the aim first).
	if (can_act or player.crouching) and not _cycle_blocked():
		if player.just_pressed(&"weapon_prev"):
			cycle(-1)
		elif player.just_pressed(&"weapon_next"):
			cycle(1)
	if weapon == &"bow":
		bow.step(delta, can_act and on_floor)
		if bow.blocks_movement():
			_check_aim_invariant()
			return
	if weapon in FIREARMS or guns.aiming:
		# Firearms also aim crouched (inside the tunnel); the player passes that state on.
		guns.step(delta, weapon, (can_act or (player.crouching and not player.hurting)) and on_floor)
	_check_aim_invariant()
	if guns.aiming:
		return
	if not can_act:
		return
	if not player.just_pressed(&"attack"):
		return
	# X in the air: flying kick with any weapon, unless aiming (LT held). On the ground: the
	# weapon's own move (fists and unarmed punch; firearms and bow do nothing; kunai waits for the rig).
	if not on_floor:
		if player.current_action.is_empty() and not aim_down and not bow.blocks_movement() and not guns.aiming:
			if kick.attack():
				var rig = player.rig
				if rig.has_method(&"set_guard"):
					rig.set_guard(false)
	elif weapon in PUNCHERS:
		fists.attack()
	elif weapon == &"kunai" and player.current_action.is_empty():
		kunai.attack()


# Movement and jumping are held while the current weapon needs the player still (bow aim).
func blocks_movement() -> bool:
	return (weapon == &"bow" and bow.blocks_movement()) or guns.blocks_movement()


func cycle(step_dir: int) -> void:
	# Switching with LT held: the current aim ends; the new weapon raises next frame.
	if bow.aiming:
		bow._cancel()
	guns.end()
	var i := Weapons.ORDER.find(weapon)
	weapon = Weapons.ORDER[posmod(i + step_dir, Weapons.ORDER.size())]
	_apply_weapon()
	Feedback.sfx(&"weapon_switch", player.global_position)
	Feedback.haptic(&"weapon_switch")


func _apply_weapon() -> void:
	_apply_rig_weapon()
	weapon_changed.emit(weapon)


func _apply_rig_weapon() -> void:
	var rig = player.rig
	if rig.has_method(&"set_weapon"):
		rig.set_weapon(&"none" if holstered else weapon)
	if rig.has_method(&"set_guard"):
		rig.set_guard(weapon == &"fists" and not holstered)
	_apply_punch_props()


# The punch actions add the glove props on their own; bare-handed they must show the hands.
func _apply_punch_props() -> void:
	var rig = player.rig
	if not rig.has_method(&"get_action"):
		return
	for id in Fists.PUNCHES:
		var action: Object = rig.get_action(id)
		if action == null or not (&"mask" in action):
			continue
		if not _punch_masks.has(id):
			_punch_masks[id] = action.get(&"mask")
		action.set(&"mask", 0 if weapon == &"unarmed" else _punch_masks[id])


# Puts the weapon away and brings the same weapon back once every reason is gone; cycling is
# ignored meanwhile. &"control": an interactable drives the player (HUD hidden). &"climb": hanging
# or on a wall (HUD dimmed, silent).
func set_holstered(on: bool, reason: StringName = &"control") -> void:
	if on == _holster_reasons.has(reason):
		return
	if on:
		_holster_reasons[reason] = true
	else:
		_holster_reasons.erase(reason)
	var now := not _holster_reasons.is_empty()
	if now != holstered:
		holstered = now
		if now:
			if bow.aiming or bow.blocks_movement():
				bow._cancel()
			guns.end()
		_apply_rig_weapon()
		if reason == &"control":
			Feedback.sfx(&"weapon_switch", player.global_position, 0.3)
	holstered_changed.emit(holstered)


func is_holstered_for(reason: StringName) -> bool:
	return _holster_reasons.has(reason)


func _update_aim_trigger() -> void:
	var v := 0.0 if player._blocked else Input.get_action_raw_strength(&"aim")
	aim_down = v > AIM_OUT if aim_down else v >= AIM_IN


# True when the rig is in this weapon's aim (or has no way to tell, like the stub).
func rig_in_aim_loop(w: StringName) -> bool:
	var rig = player.rig
	if not rig.has_method(&"current_action"):
		return true
	return rig.current_action() in AIM_LOOPS.get(w, [])


func _check_aim_invariant() -> void:
	var aiming_w := &""
	if bow.aiming:
		aiming_w = &"bow"
	elif guns.aiming:
		aiming_w = guns.weapon
	if aiming_w != &"" and not rig_in_aim_loop(aiming_w):
		_aim_bad_streak += 1
		if _aim_bad_streak > 2:
			aim_bad_frames += 1
	else:
		_aim_bad_streak = 0
	# The other way round: the rig holding an aim the game no longer has (a refused lower).
	var rig = player.rig
	if aiming_w == &"" and not bow.releasing and rig.has_method(&"current_action") and rig.current_action() in AIM_HOLDS:
		_orphan_streak += 1
		if _orphan_streak > 3 and rig.has_method(&"stop_action"):
			rig.stop_action()
			_orphan_streak = 0
	else:
		_orphan_streak = 0


func _cycle_blocked() -> bool:
	for b in cycle_blockers:
		if is_instance_valid(b) and b.visible:
			return true
	return false


func _on_action_event(id: StringName, event_name: StringName) -> void:
	fists.on_event(id, event_name)
	kunai.on_event(id, event_name)
	if id == &"bow_release" and event_name == &"release":
		bow.on_release()
	if event_name == &"shot" and (String(id).begins_with("revolver") or String(id).begins_with("rifle")):
		guns.on_shot()
	elif event_name == &"click" and String(id).begins_with("revolver"):
		guns.on_click()


func _on_action_finished(id: StringName) -> void:
	fists.on_finished(id)
	if id == &"flying_kick":
		_apply_rig_weapon()
	bow.on_finished(id)
