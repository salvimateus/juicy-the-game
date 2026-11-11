extends Node

# Bridge from gameplay to the Fog autoload (res://game/fog/fog.gd): every call is a no-op while the
# autoload is missing or disabled. Also follows things that live outside the player each frame:
# arrows in flight (group of Arrow) and turret bullets (connected through the turret's `fired`).

const ARROW_GROUP := &"arrow"

var _arrows := {}
var _bullets := {}


static func fog() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var f: Node = tree.root.get_node_or_null("Fog") if tree else null
	return f if f and f.enabled else null


static func push(p: Vector2, v: Vector2, r: float, s := 1.0) -> void:
	var f := fog()
	if f: f.push(p, v, r, s)


static func burst(p: Vector2, r: float, s := 1.0) -> void:
	var f := fog()
	if f: f.burst(p, r, s)


static func line(a: Vector2, b: Vector2, w: float, s := 1.0) -> void:
	var f := fog()
	if f: f.line(a, b, w, s)


static func sweep(a: Vector2, b: Vector2, r: float, s := 1.0) -> void:
	var f := fog()
	if f: f.sweep(a, b, r, s)


static func swirl(p: Vector2, r: float, s := 1.0) -> void:
	var f := fog()
	if f: f.swirl(p, r, s)


static func add_density(p: Vector2, r: float, amount: float) -> void:
	var f := fog()
	if f: f.add_density(p, r, amount)


static func set_body(id: int, p: Vector2, v: Vector2, r: float) -> void:
	var f := fog()
	if f: f.set_body(id, p, v, r)


func track_bullet(bullet: Node) -> void:
	if bullet is Node2D:
		_bullets[bullet.get_instance_id()] = [bullet, (bullet as Node2D).global_position]


func _physics_process(_delta: float) -> void:
	if fog() == null:
		return
	var seen := {}
	for arrow in get_tree().get_nodes_in_group(ARROW_GROUP):
		var id := arrow.get_instance_id()
		seen[id] = true
		var pos: Vector2 = arrow.global_position
		if _arrows.has(id) and _arrows[id].distance_to(pos) > 1.0:
			line(_arrows[id], pos, 10.0, 0.7)
		_arrows[id] = pos
	for id in _arrows.keys():
		if not seen.has(id):
			_arrows.erase(id)
	for id in _bullets.keys():
		var b = _bullets[id][0]
		if not is_instance_valid(b) or not b.is_inside_tree():
			_bullets.erase(id)
			continue
		var pos: Vector2 = b.global_position
		line(_bullets[id][1], pos, 10.0, 0.7)
		_bullets[id][1] = pos
