extends RefCounted

# Shared hit query: damageable nodes (group `damageable`, take_hit(point, direction, damage, kind))
# overlapping a circle. A collider counts when it, or one of its ancestors, is in the group.


static func query(world: World2D, center: Vector2, radius: float, exclude: Array[RID] = []) -> Array[Node]:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape
	params.transform = Transform2D(0.0, center)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	# Combat hitbox layer (7): damageable areas live there.
	params.collision_mask = 1 << 6
	params.exclude = exclude
	var out: Array[Node] = []
	for hit in world.direct_space_state.intersect_shape(params, 16):
		var node := hit.collider as Node
		while node and not node.is_in_group(&"damageable"):
			node = node.get_parent()
		if node and node not in out and node.has_method(&"take_hit"):
			out.append(node)
	return out
