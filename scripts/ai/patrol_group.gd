class_name PatrolGroup
extends Node3D
## A squad that starts walking a route when the player enters an area. Spawns once; when every member
## is dead it sets the flag `patrol_<id>_cleared` (saved with the world flags), so they stay dead.

const MAX_ACTIVE_PATROLLERS: int = 4

@export var group_id: StringName
## WorldState.area_entered id that wakes the squad.
@export var area_id: StringName
@export var scene_paths: PackedStringArray
## Waypoints, local to this node.
@export var route_points: PackedVector3Array
@export var loop: bool = false
@export var wait_seconds: float = 1.2

var route: PatrolRoute
var enemies: Array[Enemy] = []
var spawned: bool = false


func cleared_flag() -> StringName:
	return StringName("patrol_%s_cleared" % group_id)


func _ready() -> void:
	var state := get_node_or_null("/root/WorldState")
	if state == null:
		return
	if state.has_flag(cleared_flag()):
		spawned = true  # already wiped out in an earlier life of this world: stay dead
		return
	state.area_entered.connect(_on_area_entered)


func _on_area_entered(id: StringName) -> void:
	if id == area_id:
		spawn()


## Spawns the squad. Returns how many enemies appeared (0 if already spawned, cleared or over the cap).
func spawn() -> int:
	if spawned or scene_paths.is_empty() or route_points.is_empty():
		return 0
	if Enemy.active_patrollers + scene_paths.size() > MAX_ACTIVE_PATROLLERS:
		return 0  # try again on the next entry rather than flooding the level
	spawned = true
	route = PatrolRoute.new()
	route.name = "Route"
	route.loop = loop
	route.wait_seconds = wait_seconds
	route.set_points(route_points)
	add_child(route)
	var parent := get_parent()
	for i in scene_paths.size():
		var scene := load(scene_paths[i]) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate() as Enemy
		if enemy == null:
			continue
		enemy.patrol_route = route
		enemy.patrol_index = i % route.point_count()
		# Position before entering the tree so the enemy never overlaps the player for a frame.
		enemy.position = parent.to_local(route.global_point(enemy.patrol_index))
		parent.add_child(enemy)
		enemy.defeated.connect(_on_member_defeated)
		enemies.append(enemy)
	return enemies.size()


func _on_member_defeated() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and not enemy.is_dead():
			return
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(cleared_flag(), true)
