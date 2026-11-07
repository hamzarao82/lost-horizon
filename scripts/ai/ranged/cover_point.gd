class_name CoverPoint
extends Marker3D
## A spot a ranged enemy may reposition to. Level designers place these behind walls, crates and corners.

const GROUP: StringName = &"cover_points"
const WORLD_MASK: int = 1
const EYE: Vector3 = Vector3(0.0, 1.1, 0.0)


func _ready() -> void:
	add_to_group(GROUP)


## True when nothing in the world blocks a straight line between the two points (eye height).
static func has_line_of_sight(world: World3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from + EYE, to + EYE, WORLD_MASK)
	query.collide_with_areas = false
	return world.direct_space_state.intersect_ray(query).is_empty()


## The nearest cover point to `enemy_pos` that sees the player from between the two distances.
## Returns null when there is none.
static func best_for(tree: SceneTree, world: World3D, enemy_pos: Vector3, player_pos: Vector3,
		band_min: float, band_max: float) -> Variant:
	var best: Variant = null
	var best_dist := INF
	for node in tree.get_nodes_in_group(GROUP):
		var point := node as Node3D
		if point == null:
			continue
		var flat := Vector2(point.global_position.x - player_pos.x, point.global_position.z - player_pos.z).length()
		if flat < band_min or flat > band_max * 1.3:
			continue
		var d := point.global_position.distance_to(enemy_pos)
		if d < best_dist and has_line_of_sight(world, point.global_position, player_pos):
			best = point.global_position
			best_dist = d
	return best
