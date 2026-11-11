extends RefCounted

# Fists: jab, jab, cross, uppercut. Each X inside the punch's combo_window (or shortly after the
# punch ends) advances the combo; otherwise it restarts at the jab. Hits land on the rig's `hit`
# event with circle queries along the striking glove's reach (REACH), plus the rig's wind.

const Feedback := preload("res://game/feedback.gd")
const Hitbox := preload("res://game/combat/hitbox.gd")
const FogHooks := preload("res://game/fog_hooks.gd")

const PUNCHES: Array[StringName] = [&"punch_1", &"punch_2", &"punch_3", &"punch_4"]
# Striking glove per punch (the lead hand is the back arm) and its damage.
const GLOVES: Array[StringName] = [&"gloveB", &"gloveB", &"gloveF", &"gloveB"]
const DAMAGE: Array[float] = [8.0, 8.0, 14.0, 18.0]
# Reach of each punch from the striking glove along its direction; circles of hit_radius cover it.
const REACH: Array[float] = [120.0, 120.0, 150.0, 100.0]

var reset_after := 0.3
var hit_radius := 64.0
var hit_samples := 3
var hitstop := 0.05
var shake := 8.0

var player
var index := -1
var window_open := false
var hit_count := 0
var swings := 0
var _since_end := INF


func _init(owner_player) -> void:
	player = owner_player


func step(delta: float) -> void:
	if not _playing():
		_since_end += delta


func _playing() -> bool:
	return player.current_action in PUNCHES


# X on the ground. Returns true when a punch started.
func attack() -> bool:
	var next := 0
	if _playing():
		if not window_open:
			return false
		next = (index + 1) % PUNCHES.size()
	elif index >= 0 and _since_end <= reset_after and index < PUNCHES.size() - 1:
		next = index + 1
	if not player.start_combat_action(PUNCHES[next]):
		return false
	index = next
	window_open = false
	_since_end = 0.0
	return true


func on_event(id: StringName, event_name: StringName) -> void:
	if id not in PUNCHES:
		return
	match event_name:
		&"combo_window":
			window_open = true
		&"hit":
			_land(PUNCHES.find(id))


func on_finished(id: StringName) -> void:
	if id in PUNCHES:
		window_open = false
		_since_end = 0.0


func _land(i: int) -> void:
	var f: int = player.facing
	var rig = player.rig
	var from: Vector2 = player.global_position + Vector2(f * 150.0, -260.0)
	if rig.has_method(&"get_anchor"):
		from = rig.get_anchor(GLOVES[i])
	var direction := Vector2(f, -1.2 if i == 3 else -0.1).normalized()
	var targets: Array[Node] = []
	var points: Array[Vector2] = []
	var steps := maxi(hit_samples - 1, 1)
	for k in maxi(hit_samples, 1):
		var c := from + direction * REACH[i] * float(k) / float(steps)
		for t in Hitbox.query(player.get_world_2d(), c, hit_radius, [player.get_rid()]):
			if t not in targets:
				targets.append(t)
				points.append(c)
	swings += 1
	FogHooks.push(from + direction * REACH[i] * 0.5, direction * 1500.0, 170.0, 1.0)
	for j in targets.size():
		if is_instance_valid(targets[j]):
			targets[j].take_hit(points[j], direction, DAMAGE[i], &"punch")
	var hit := not targets.is_empty()
	var to: Vector2 = points[0] if hit else from + direction * (REACH[i] + hit_radius)
	if rig.has_method(&"punch_reach"):
		rig.punch_reach(from, to, hit)
	if not hit:
		Feedback.sfx(&"punch_swing", to)
		return
	hit_count += 1
	var strength := 1.0 if i >= 2 else 0.7
	Feedback.sfx(&"punch_hit", to, strength)
	Feedback.haptic(&"punch_hit", strength)
	player.hitstop(hitstop * (1.5 if i >= 2 else 1.0))
	player.camera_shake(shake * strength, 0.15)
