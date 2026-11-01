class_name WaveManager
extends Node
## Spawns enemy waves around the player; advances when the arena is clear.

signal wave_started(index: int, total: int)
signal wave_cleared(index: int)
signal all_cleared

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"
const WARDEN: String = "res://scenes/enemies/Warden.tscn"
const WAVES: Array[Array] = [
	[SOLDIER, SOLDIER],
	[SOLDIER, SOLDIER, HUNTER],
	[HEAVY, HUNTER, SOLDIER],
	[HEAVY, HUNTER, HUNTER],
	[WARDEN],
]
const OBSTACLES: Array[Vector2] = [Vector2(8.0, -6.0), Vector2(-8.0, -4.0)]
const OBSTACLE_CLEARANCE: float = 4.5
const SAFE_SPAWNS: Array[Vector2] = [Vector2(22, 22), Vector2(-22, 22), Vector2(22, -22), Vector2(-22, -22)]
## Loaded once up front so the first kill / first spawn of a type does not hitch (web, Android).
const WARM_UP: PackedStringArray = [
	"res://scenes/loot/Pickup.tscn",
	"res://resources/loot/soldier_loot.tres",
	"res://resources/loot/hunter_loot.tres",
	"res://resources/loot/heavy_loot.tres",
	"res://resources/loot/warden_loot.tres",
]
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
	_warm_up()
	if autostart:
		start()


func _warm_up() -> void:
	for path in WARM_UP:
		var res := load(path)
		if res is LootTable:
			for item_path in (res as LootTable).item_paths:
				load(item_path)
	for wave in WAVES:
		for path in wave:
			load(path)


## Begin at the wave a queued Load / death checkpoint asks for, otherwise wave 1.
func start() -> void:
	var save_manager := _save_manager()
	start_wave_at(save_manager.consume_start_wave(WAVES.size()) if save_manager else 1)


## Begin with a specific 1-based wave (after start_delay), ignoring any queued save state.
func start_wave_at(index: int) -> void:
	current_wave = clampi(index, 1, WAVES.size()) - 1
	_finished = false
	_running = true
	_wave_spawned = false
	_next_wave_in = start_delay


func is_finished() -> bool:
	return _finished


## The wave a save made right now should resume on: the current wave while its enemies are alive,
## the next one between waves, and wave 1 again once the arena has been cleared.
func resume_index() -> int:
	if _finished:
		return 1
	if _wave_spawned:
		return current_wave
	return mini(current_wave + 1, WAVES.size())


func _save_manager() -> Node:
	return get_node_or_null("/root/SaveManager")


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
		var save_manager := _save_manager()
		if save_manager and WAVES[current_wave - 1].has(WARDEN):
			save_manager.mark_boss_defeated("warden")
		wave_cleared.emit(current_wave)
		if current_wave >= WAVES.size():
			_finished = true
			_running = false
			if save_manager:
				save_manager.autosave("complete")
				save_manager.clear_checkpoint()
			all_cleared.emit()
		else:
			_next_wave_in = between_waves_delay
			if save_manager:
				save_manager.autosave("wave")


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
	var save_manager := _save_manager()
	if save_manager:
		save_manager.set_checkpoint(current_wave)  # where a death restart resumes
	wave_started.emit(current_wave, WAVES.size())


func _pick_spawn_point() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var center := Vector2.ZERO
	if player:
		center = Vector2(player.global_position.x, player.global_position.z)
	var best := Vector2.INF
	var best_dist := -1.0
	for attempt in 12:
		var angle := randf() * TAU
		var dist := randf_range(SPAWN_MIN, SPAWN_MAX)
		var point := center + Vector2(cos(angle), sin(angle)) * dist
		point = point.clamp(Vector2(-ARENA_LIMIT, -ARENA_LIMIT), Vector2(ARENA_LIMIT, ARENA_LIMIT))
		var actual := point.distance_to(center)  # clamping can pull the point back toward the player
		if _clear_of_obstacles(point) and actual > best_dist:
			best = point
			best_dist = actual
		if best_dist >= SPAWN_MIN * 0.75:
			break
	if best_dist < SPAWN_MIN * 0.5:
		# Player is hugging a wall/corner or every try hit an obstacle: use the farthest fixed corner.
		for corner in SAFE_SPAWNS:
			if corner.distance_to(center) > best_dist:
				best = corner
				best_dist = corner.distance_to(center)
	return Vector3(best.x, 0.1, best.y)


func _clear_of_obstacles(point: Vector2) -> bool:
	for obstacle in OBSTACLES:
		if point.distance_to(obstacle) < OBSTACLE_CLEARANCE:
			return false
	return true
