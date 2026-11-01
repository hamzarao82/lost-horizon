class_name WaveManager
extends Node
## Spawns enemy waves around the player; advances when the arena is clear.

signal wave_started(index: int, total: int)
signal all_cleared

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"
const WAVES: Array[Array] = [
	[SOLDIER, SOLDIER],
	[SOLDIER, SOLDIER, HUNTER],
	[HEAVY, HUNTER, SOLDIER],
	[HEAVY, HUNTER, HUNTER],
]
const OBSTACLES: Array[Vector2] = [Vector2(8.0, -6.0), Vector2(-8.0, -4.0)]
const OBSTACLE_CLEARANCE: float = 4.5
const ARENA_LIMIT: float = 26.0
const SPAWN_MIN: float = 12.0
const SPAWN_MAX: float = 16.0
const POLL_SECONDS: float = 0.5

@export var autostart: bool = true
@export var start_delay: float = 1.5
@export var between_waves_delay: float = 3.0

var current_wave: int = 0

var _finished: bool = false
var _running: bool = false
var _wave_spawned: bool = false
var _poll_time: float = 0.0
var _next_wave_in: float = -1.0


func _ready() -> void:
	add_to_group("wave_manager")
	if autostart:
		start()


func start() -> void:
	current_wave = 0
	_finished = false
	_running = true
	_wave_spawned = false
	_next_wave_in = start_delay


func is_finished() -> bool:
	return _finished


func total_waves() -> int:
	return WAVES.size()


func _process(delta: float) -> void:
	if not _running or _finished:
		return
	if _next_wave_in >= 0.0:
		_next_wave_in -= delta
		if _next_wave_in < 0.0:
			_spawn_wave()
		return
	_poll_time += delta
	if _poll_time < POLL_SECONDS:
		return
	_poll_time = 0.0
	if _wave_spawned and get_tree().get_nodes_in_group("enemies").is_empty():
		_wave_spawned = false
		if current_wave >= WAVES.size():
			_finished = true
			_running = false
			all_cleared.emit()
		else:
			_next_wave_in = between_waves_delay


func _spawn_wave() -> void:
	_next_wave_in = -1.0
	_poll_time = 0.0
	current_wave += 1
	var parent := get_parent()
	for path in WAVES[current_wave - 1]:
		var scene := load(path) as PackedScene
		if scene == null:
			push_warning("WaveManager: missing enemy scene %s" % path)
			continue
		var enemy := scene.instantiate() as Node3D
		# Position before entering the tree: an enemy that briefly overlaps the player at the
		# origin would push them on top of it and carry them along when it is moved.
		enemy.position = _pick_spawn_point()
		parent.add_child(enemy)
		if enemy.has_method("aggro"):
			enemy.call("aggro")
	_wave_spawned = true
	wave_started.emit(current_wave, WAVES.size())


func _pick_spawn_point() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var center := Vector2.ZERO
	if player:
		center = Vector2(player.global_position.x, player.global_position.z)
	var point := Vector2.ZERO
	for attempt in 12:
		var angle := randf() * TAU
		var dist := randf_range(SPAWN_MIN, SPAWN_MAX)
		point = center + Vector2(cos(angle), sin(angle)) * dist
		point = point.clamp(Vector2(-ARENA_LIMIT, -ARENA_LIMIT), Vector2(ARENA_LIMIT, ARENA_LIMIT))
		if _clear_of_obstacles(point):
			break
	return Vector3(point.x, 0.1, point.y)


func _clear_of_obstacles(point: Vector2) -> bool:
	for obstacle in OBSTACLES:
		if point.distance_to(obstacle) < OBSTACLE_CLEARANCE:
			return false
	return true
