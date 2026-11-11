extends Node

# Projectiles stuck in the player's body: each rides the rig bone it hit (tip and shaft in that
# bone's frame) and blinks out after stick_time, still riding until it leaves the tree.

var stick_time := 4.0
var max_stuck := 3
var hit_count := 0
var player
var _items: Array[Dictionary] = []


func setup(owner_player) -> void:
	player = owner_player
	process_physics_priority = 1


func attach(projectile: Node2D, tip: Vector2, angle: float) -> bool:
	if player == null or not is_instance_valid(projectile):
		return false
	_prune()
	# Over the cap the oldest one still riding blinks out (fading ones already left the count).
	var riding := 0
	for it in _items:
		if not it.gone:
			riding += 1
	if riding >= max_stuck:
		for it in _items:
			if not it.gone:
				it.gone = true
				it.node.vanish()
				break
	var bone: int = player.rig.bone_at(tip) if player.rig.has_method(&"bone_at") else -1
	var inv := _frame(bone).affine_inverse()
	_items.append({"node": projectile, "bone": bone, "tip": inv * tip, "dir": inv.basis_xform(Vector2.from_angle(angle)), "t": 0.0, "gone": false})
	projectile.tree_exiting.connect(_on_gone.bind(projectile), CONNECT_ONE_SHOT)
	hit_count += 1
	return true


func count() -> int:
	return _items.size()


func _physics_process(delta: float) -> void:
	if _items.is_empty() or player == null:
		return
	_prune()
	for it in _items:
		var xf := _frame(it.bone)
		it.node.set_carried_pose(xf * it.tip, xf.basis_xform(it.dir).angle())
		it.t += delta
		if not it.gone and it.t >= stick_time:
			it.gone = true
			it.node.vanish()


func _frame(bone: int) -> Transform2D:
	if bone >= 0 and player.rig.has_method(&"bone_transform"):
		return player.rig.bone_transform(bone)
	return Transform2D(0.0, Vector2(player.facing, 1.0), 0.0, player.global_position)


func _prune() -> void:
	_items = _items.filter(func(it): return is_instance_valid(it.node) and it.node.is_inside_tree())


func _on_gone(n: Node) -> void:
	_items = _items.filter(func(it): return is_instance_valid(it.node) and it.node != n)
