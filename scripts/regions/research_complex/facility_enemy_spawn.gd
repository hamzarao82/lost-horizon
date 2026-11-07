class_name FacilityEnemySpawn
extends Node3D
## A placed spawn point for one Research Complex enemy. trigger() (or the optional proximity radius)
## instantiates the config's scene, applies its stats before the enemy enters the tree, and watches it.
## A defeated enemy writes a PersistentIds claim (`<spawn_id>_cleared`), so it never comes back after a
## reload. A cleared elite whose unique reward was never picked up gets the reward put back.
## A patrolling config with a route respects the global patroller cap (like PatrolGroup).

signal spawned(enemy: Enemy)
signal cleared

@export var spawn_id: StringName = &"spawn"
@export var config: FacilityEnemyConfig
@export var region_id: StringName = FacilityIds.REGION
## 0 = manual (trigger() from a MissionTrigger or encounter); > 0 = wakes when the player gets this close.
@export var trigger_radius: float = 0.0
## Optional patrol waypoints (local to this node) for configs that patrol.
@export var route_points: PackedVector3Array

var enemy: Enemy

var _triggered: bool = false
var _route: PatrolRoute


func _ready() -> void:
	add_to_group("facility_spawns")
	set_physics_process(trigger_radius > 0.0 and not is_cleared())
	if is_cleared():
		_triggered = true
		restore_pending_reward.call_deferred()


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
	if config == null or _triggered or is_cleared():
		return false
	if config.patrols and not route_points.is_empty():
		return Enemy.active_patrollers < PatrolGroup.MAX_ACTIVE_PATROLLERS
	return true


## Spawns the enemy once. Returns it, or null when it already spawned, is cleared, or the cap blocks it.
func trigger() -> Enemy:
	if not can_spawn() or not is_inside_tree():
		return null
	var scene := load(config.base_scene_path) as PackedScene
	if scene == null:
		return null
	var made := scene.instantiate() as Enemy
	if made == null:
		return null
	_triggered = true
	config.apply(made)
	var parent := get_parent()
	if config.patrols and not route_points.is_empty():
		_route = PatrolRoute.new()
		_route.name = "Route_%s" % String(spawn_id)
		_route.set_points(route_points)
		add_child(_route)
		made.patrol_route = _route
	# Position before entering the tree so it never overlaps the player for a frame.
	made.position = parent.to_local(global_position)
	parent.add_child(made)
	made.defeated.connect(_on_defeated)
	enemy = made
	spawned.emit(made)
	return made


func _on_defeated() -> void:
	PersistentIds.claim(region_id, cleared_id())
	cleared.emit()


## A cleared enemy with a unique reward that this save does not own yet: the reward waits where it stood.
func restore_pending_reward() -> bool:
	if config == null or config.reward_item_path == "" or not is_inside_tree():
		return false
	var item := load(config.reward_item_path) as ItemData
	var player := get_tree().get_first_node_in_group("player")
	if item == null or player == null or EliteExperimentalSubject.reward_owned(player, item):
		return false
	Pickup.spawn(get_parent(), item, Vector3(global_position.x, 0.0, global_position.z))
	return true
