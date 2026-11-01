class_name Targeting
extends RefCounted
## Lock-on target selection. Pure logic: callers pass the origin, the camera's forward direction,
## the enemy list and (optionally) the physics space used for line-of-sight rays.

const ACQUIRE_RANGE: float = 14.0
const DROP_RANGE: float = 18.0
const LOS_GRACE: float = 1.5
const CONE_HALF_ANGLE: float = 75.0  # degrees either side of the camera's forward direction
const WORLD_MASK: int = 1

var target: Node3D

var _los_lost: float = 0.0


static func is_valid_target(node: Node) -> bool:
	if node == null or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if not node is Node3D:
		return false
	return not (node.has_method("is_dead") and node.call("is_dead"))


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Angle from `forward` to `to` on the ground plane. Positive = to the right on screen.
static func signed_angle(forward: Vector3, to: Vector3) -> float:
	var f := flat(forward).normalized()
	var t := flat(to).normalized()
	return atan2(-f.cross(t).y, f.dot(t))


static func has_line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, node: Node3D) -> bool:
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
			from + Vector3.UP * 1.2, node.global_position + Vector3.UP * 1.0, WORLD_MASK)
	return space.intersect_ray(query).is_empty()


## Valid enemies in range and inside the view cone, best first (closest to screen centre).
static func candidates(origin: Vector3, forward: Vector3, enemies: Array, max_range: float = ACQUIRE_RANGE) -> Array[Node3D]:
	var scored: Array[Dictionary] = []
	var half_angle := deg_to_rad(CONE_HALF_ANGLE)
	for node in enemies:
		if not is_valid_target(node):
			continue
		var enemy := node as Node3D
		var to := flat(enemy.global_position - origin)
		var dist := to.length()
		if dist > max_range:
			continue
		var angle := 0.0 if dist < 0.01 else signed_angle(forward, to)
		if absf(angle) > half_angle:
			continue
		scored.append({"node": enemy, "angle": angle, "score": absf(angle) + dist * 0.02})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["score"] < b["score"])
	var result: Array[Node3D] = []
	for entry in scored:
		result.append(entry["node"])
	return result


func acquire(origin: Vector3, forward: Vector3, enemies: Array, space: PhysicsDirectSpaceState3D = null) -> Node3D:
	for candidate in candidates(origin, forward, enemies):
		if has_line_of_sight(space, origin, candidate):
			_set_target(candidate)
			return candidate
	_set_target(null)
	return null


## Switch to the next target to the right (+1) or left (-1) by screen position. Wraps around.
func cycle(direction: int, origin: Vector3, forward: Vector3, enemies: Array, space: PhysicsDirectSpaceState3D = null) -> Node3D:
	if target == null:
		return acquire(origin, forward, enemies, space)
	var visible: Array[Dictionary] = []
	for candidate in candidates(origin, forward, enemies):
		if candidate == target or has_line_of_sight(space, origin, candidate):
			visible.append({"node": candidate, "angle": signed_angle(forward, flat(candidate.global_position - origin))})
	if visible.size() <= 1:
		return target
	visible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["angle"] < b["angle"])
	var index := -1
	for i in visible.size():
		if visible[i]["node"] == target:
			index = i
	if index < 0:
		return acquire(origin, forward, enemies, space)
	var next := wrapi(index + (1 if direction >= 0 else -1), 0, visible.size())
	_set_target(visible[next]["node"])
	return target


## Per-frame validity check. Returns false (and clears the target) when the lock should drop.
func update(delta: float, origin: Vector3, space: PhysicsDirectSpaceState3D = null) -> bool:
	if target == null:
		return false
	if not is_valid_target(target):
		_set_target(null)
		return false
	if flat(target.global_position - origin).length() > DROP_RANGE:
		_set_target(null)
		return false
	if has_line_of_sight(space, origin, target):
		_los_lost = 0.0
	else:
		_los_lost += delta
		if _los_lost > LOS_GRACE:
			_set_target(null)
			return false
	return true


func clear() -> void:
	_set_target(null)


func _set_target(new_target: Node3D) -> void:
	target = new_target
	_los_lost = 0.0
