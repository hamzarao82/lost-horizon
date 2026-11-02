class_name PatrolRoute
extends Node3D
## An ordered list of waypoints a patrolling enemy walks. Points are local to this node.

## true: A, B, C, A, B, C ...   false (ping-pong): A, B, C, B, A, B ...
@export var loop: bool = false
## Seconds an enemy stands at each waypoint before walking on.
@export var wait_seconds: float = 1.2

var _points: PackedVector3Array = PackedVector3Array()


func set_points(points: PackedVector3Array) -> void:
	_points = points


func point_count() -> int:
	return _points.size()


## World position of waypoint `index` (wraps, so a bad index never crashes).
func global_point(index: int) -> Vector3:
	if _points.is_empty():
		return global_position
	return to_global(_points[posmod(index, _points.size())])


## Index of the waypoint nearest to a world position.
func nearest_index(world_position: Vector3) -> int:
	var best := 0
	var best_dist := INF
	for i in _points.size():
		var d := global_point(i).distance_to(world_position)
		if d < best_dist:
			best_dist = d
			best = i
	return best


## The waypoint after `index`; `step` (+1 or -1) carries the ping-pong direction.
## Returns [next_index, next_step].
func advance(index: int, step: int) -> Array:
	var count := _points.size()
	if count <= 1:
		return [0, step]
	if loop:
		return [(index + 1) % count, 1]
	var next := index + step
	if next >= count or next < 0:
		step = -step
		next = index + step
	return [next, step]
