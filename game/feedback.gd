extends RefCounted

# Guarded bridge to the Sfx (res://audio/sfx.gd) and Haptics (res://feedback/haptics.gd) autoloads:
# every call is a no-op while the autoload is missing.


static func _node(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree else null


static func sfx(id: StringName, at: Vector2 = Vector2.INF, strength: float = 1.0, surface: StringName = &"") -> void:
	var n := _node("Sfx")
	if n:
		n.play(id, at, strength, surface)


static func sfx_loop(id: StringName, at: Vector2 = Vector2.INF) -> int:
	var n := _node("Sfx")
	return n.start_loop(id, at) if n else -1


static func sfx_stop(handle: int, fade: float = 0.15) -> void:
	var n := _node("Sfx")
	if n and handle >= 0:
		n.stop_loop(handle, fade)


static func haptic(id: StringName, strength: float = 1.0) -> void:
	var n := _node("Haptics")
	if n:
		n.play(id, strength)


static func haptic_loop(id: StringName, strength: float = 1.0) -> int:
	var n := _node("Haptics")
	return n.start_loop(id, strength) if n else -1


static func haptic_stop(handle: int) -> void:
	var n := _node("Haptics")
	if n and handle >= 0:
		n.stop_loop(handle)


static func haptics() -> Node:
	return _node("Haptics")


static func sfx_loop_update(handle: int, strength: float, at: Vector2 = Vector2.INF) -> void:
	var n := _node("Sfx")
	if n == null or handle < 0:
		return
	if n.has_method(&"set_loop_strength"):
		n.set_loop_strength(handle, strength)
	if at != Vector2.INF and n.has_method(&"set_loop_position"):
		n.set_loop_position(handle, at)


static func haptic_loop_strength(handle: int, strength: float) -> void:
	var n := _node("Haptics")
	if n and handle >= 0 and n.has_method(&"set_loop_strength"):
		n.set_loop_strength(handle, strength)
