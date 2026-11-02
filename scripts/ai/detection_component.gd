class_name DetectionComponent
extends RefCounted
## Sight test for patrolling enemies: range, field-of-view cone and a line-of-sight ray against the
## world layer (walls, doors, props block it; characters do not). Pure functions, no state.

const WORLD_MASK: int = 1


## True when `target` is within `sight_range` (flat distance), inside the cone of `fov_deg` around
## `facing`, and nothing on the world layer is between the two eye points.
static func can_see(eye_node: Node3D, target: Node3D, facing: Vector3, sight_range: float,
		fov_deg: float, mask: int = WORLD_MASK) -> bool:
	if eye_node == null or target == null or not eye_node.is_inside_tree() or not target.is_inside_tree():
		return false
	var from := eye_node.global_position + Vector3(0.0, 1.5, 0.0)
	var to_pos := target.global_position + Vector3(0.0, 1.0, 0.0)
	var flat := Vector3(to_pos.x - from.x, 0.0, to_pos.z - from.z)
	var dist := flat.length()
	if dist > sight_range:
		return false
	if dist > 0.01 and facing.length_squared() > 0.0001:
		var flat_facing := Vector3(facing.x, 0.0, facing.z).normalized()
		if flat_facing.dot(flat / dist) < cos(deg_to_rad(fov_deg * 0.5)):
			return false
	var space := eye_node.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to_pos, mask)
	return space.intersect_ray(query).is_empty()
