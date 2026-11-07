class_name FortressSpawn
extends Node3D
## A placed spawn point for one Iron Fortress enemy. Same contract as FacilityEnemySpawn (trigger(), cleared
## signal, PersistentIds claim `<spawn_id>_cleared`) but the config may be a FacilityEnemyConfig (melee scene
## stats) or an EnemyConfig (ranged and boss configs): both come from FortressEnemies.

signal spawned(enemy: Enemy)
signal cleared

@export var spawn_id: StringName = &"spawn"
@export var region_id: StringName = &"iron_fortress"
## 0 = manual (trigger() from an encounter); > 0 = wakes when the player gets this close.
@export var trigger_radius: float = 0.0
@export var config_name: String = "fortress_infantry"
@export var route_points: PackedVector3Array

var enemy: Enemy

var _triggered: bool = false
var _route: PatrolRoute


func _ready() -> void:
	add_to_group("fortress_spawns")
	set_physics_process(trigger_radius > 0.0 and not is_cleared())
	if is_cleared():
		_triggered = true


func cleared_id() -> StringName:
	return StringName("%s_cleared" % String(spawn_id))


func is_cleared() -> bool:
	return PersistentIds.is_claimed(region_id, cleared_id())


func _physics_process(_delta: float) -> void:
	if _triggered or trigger_radius <= 0.0:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player != null and player.global_position.distance_to(global_position) <= trigger_radius:
		trigger()


func can_spawn() -> bool:
	if _triggered or is_cleared():
		return false
	if not route_points.is_empty():
		return Enemy.active_patrollers < PatrolGroup.MAX_ACTIVE_PATROLLERS
	return true


## Spawns the enemy once. Returns it, or null when it already spawned, is cleared, or the cap blocks it.
func trigger() -> Enemy:
	if not can_spawn() or not is_inside_tree():
		return null
	var made := FortressEnemies.make(config_name, get_parent(), get_parent().to_local(global_position), self, route_points)
	if made == null:
		return null
	_triggered = true
	enemy = made
	made.defeated.connect(_on_defeated)
	spawned.emit(made)
	return made


func _on_defeated() -> void:
	PersistentIds.claim(region_id, cleared_id())
	cleared.emit()


func attach_route(points: PackedVector3Array) -> PatrolRoute:
	_route = PatrolRoute.new()
	_route.name = "Route_%s" % String(spawn_id)
	_route.set_points(points)
	add_child(_route)
	return _route
