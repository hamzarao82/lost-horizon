class_name StageWaves
extends Node3D
## One wave encounter inside a campaign stage (Dead Coast, Blackwood, Research Complex, Iron Fortress),
## like the five-wave arena of Outpost 17 but small and data driven. The player walks into the hold area,
## the waves come, and when the last one falls the stage flag `<region>_waves_cleared` is set (a normal
## FLAG objective of the stage's mission) and a reward is paid once. Waves keep the arena's signals and its
## counter methods (`current_wave`, `total_waves()`, `active_enemy_count()`), so the HUD shows
## "Wave n/N  Enemies: m" for whichever encounter is active.
##
## Enemy entries in the table are scene paths (.tscn) or enemy config resources (EnemyConfig and
## FacilityEnemyConfig). All flags are underscore-only: WorldState drops anything else when it loads a save.

signal wave_started(index: int, total: int)
signal wave_cleared(index: int)
signal all_cleared
signal state_changed(new_state: int)
signal reward_granted(xp: int, credits: int)
signal failed

enum State { IDLE, SPAWNING, ACTIVE, TRANSITION, COMPLETE, FAILED }

const TABLE_PATH: String = "res://resources/arena/stage_%s.tres"
## Centre of the hold area per stage: a middle section of the stage (the map's area centres).
const HOLD_POINTS: Dictionary = {
	&"dead_coast": Vector3(6.6, 0.0, -72.0),
	&"blackwood": Vector3(-30.0, 0.0, -100.0),
	&"research_complex": Vector3(0.0, 0.0, -65.0),
	&"iron_fortress": Vector3(0.0, 0.0, -67.0),
}
## XP and credits, one step above the arena's 100 XP and 120 credits, rising with the stage.
const REWARDS: Dictionary = {
	&"dead_coast": [140, 160],
	&"blackwood": [160, 180],
	&"research_complex": [180, 200],
	&"iron_fortress": [220, 240],
}
const HOLD_SIZE: Vector3 = Vector3(18.0, 6.0, 18.0)
const ENEMY_CAP: int = 6
const FALL_LIMIT: float = -60.0
const POLL_SECONDS: float = 0.5
const START_DELAY: float = 1.5
const REARM_SECONDS: float = 3.0
const SPAWN_ATTEMPTS: int = 16

@export var region_id: StringName = &""

var current_wave: int = 0
var state: State = State.IDLE
var hold_position: Vector3 = Vector3.ZERO

var _table: ArenaWaveSet
var _enemies: Array = []
var _trigger: Area3D
var _next_in: float = -1.0
var _poll: float = 0.0
var _wave_spawned: bool = false
var _rearm: float = -1.0
var _player_bound: bool = false


## Builds the encounter for a region under its adapter node. The position is set before the node enters the
## tree, so nothing ever overlaps the player at the origin.
static func attach(parent: Node, region: StringName) -> StageWaves:
	var stage := StageWaves.new()
	stage.name = "StageWaves"
	stage.region_id = region
	stage.position = HOLD_POINTS.get(region, Vector3.ZERO)
	parent.add_child(stage)
	return stage


func _ready() -> void:
	add_to_group("stage_waves")
	hold_position = global_position
	_table = load(TABLE_PATH % String(region_id)) as ArenaWaveSet
	if _flag(cleared_flag()):
		state = State.COMPLETE
		current_wave = total_waves()
		return
	_build_trigger()


func cleared_flag() -> StringName:
	return RegionFlags.key(region_id, &"waves_cleared")


func reward_flag() -> StringName:
	return RegionFlags.key(region_id, &"waves_reward")


func total_waves() -> int:
	return _table.wave_count() if _table != null else 0


func is_active() -> bool:
	return state == State.SPAWNING or state == State.ACTIVE or state == State.TRANSITION


func is_complete() -> bool:
	return state == State.COMPLETE


func state_name() -> String:
	return State.keys()[state]


## Enemies of this encounter that are still a threat: spawned here, alive, in the world.
func active_enemy_count() -> int:
	var count := 0
	for enemy in _enemies.duplicate():
		if not is_instance_valid(enemy) or (enemy as Node).is_queued_for_deletion():
			_enemies.erase(enemy)
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		if enemy is Node3D and (enemy as Node3D).global_position.y < FALL_LIMIT:
			(enemy as Node).queue_free()
			_enemies.erase(enemy)
			continue
		count += 1
	return count


# --- running the waves ---------------------------------------------------------------

## Starts the encounter once. A cleared stage never starts again; a failed one waits to re-arm.
func start() -> bool:
	if state != State.IDLE or _table == null or total_waves() == 0:
		return false
	current_wave = 0
	_wave_spawned = false
	_next_in = START_DELAY
	_set_state(State.TRANSITION)
	_say("Hold the line: wave 1 of %d" % total_waves())
	return true


func _process(delta: float) -> void:
	_bind_player()
	if state == State.FAILED:
		if _rearm >= 0.0:
			_rearm -= delta
			if _rearm < 0.0:
				_reset_after_failure()
		return
	if not is_active():
		return
	if _next_in >= 0.0:
		_next_in -= delta
		if _next_in < 0.0:
			_spawn_wave()
		return
	_poll += delta
	if _poll < POLL_SECONDS:
		return
	_poll = 0.0
	if _wave_spawned and state == State.ACTIVE and active_enemy_count() == 0:
		_clear_wave()


func _clear_wave() -> void:
	_wave_spawned = false
	_enemies.clear()
	wave_cleared.emit(current_wave)
	if current_wave >= total_waves():
		_complete()
		return
	_next_in = _table.rest_of(current_wave - 1, 3.0)
	_set_state(State.TRANSITION)
	_say("Wave %d cleared. Wave %d of %d is coming." % [current_wave, current_wave + 1, total_waves()])


func _complete() -> void:
	_set_flag(cleared_flag())
	_grant_reward()
	_set_state(State.COMPLETE)
	_say("The stage is secure.")
	var saves := get_node_or_null("/root/SaveManager")
	if saves != null and saves.has_method("autosave"):
		saves.autosave("stage_waves")
	all_cleared.emit()


## Once per playthrough: the claim flag is saved with the world, so a reload pays nothing twice.
func _grant_reward() -> void:
	if _flag(reward_flag()):
		return
	_set_flag(reward_flag())
	var amounts: Array = REWARDS.get(region_id, [140, 160])
	var progression := get_node_or_null("/root/Progression")
	if progression != null:
		progression.award_xp(int(amounts[0]), "stage_waves")
		progression.add_currency(int(amounts[1]), false)
	reward_granted.emit(int(amounts[0]), int(amounts[1]))


func _spawn_wave() -> void:
	_next_in = -1.0
	_poll = 0.0
	var wave_number := current_wave + 1
	_wave_spawned = false
	_set_state(State.SPAWNING)
	var spacing := _table.spacing_of(wave_number - 1, 0.25)
	var first := true
	for entry in _table.enemies_of(wave_number - 1):
		if _enemies.size() >= ENEMY_CAP:
			break
		if not first:
			await get_tree().create_timer(spacing).timeout
			if not is_inside_tree() or state != State.SPAWNING:
				return
		first = false
		var enemy := _make_enemy(String(entry))
		if enemy != null:
			_enemies.append(enemy)
			if enemy.has_method("aggro"):
				enemy.call("aggro")
	if state != State.SPAWNING:
		return
	current_wave = wave_number
	_wave_spawned = true
	_set_state(State.ACTIVE)
	wave_started.emit(current_wave, total_waves())
	if wave_number > 1:
		_say("Hold the line: wave %d of %d" % [wave_number, total_waves()])


## One enemy at a ground point near the player. Position is set before the node enters the tree.
func _make_enemy(entry: String) -> Node3D:
	var parent := get_parent()
	if parent == null:
		return null
	var local_pos: Vector3 = (parent as Node3D).to_local(_pick_spawn_point()) if parent is Node3D else _pick_spawn_point()
	if entry.ends_with(".tscn"):
		var scene := load(entry) as PackedScene
		if scene == null:
			push_warning("StageWaves: missing enemy scene %s" % entry)
			return null
		var enemy := scene.instantiate() as Node3D
		enemy.position = local_pos
		parent.add_child(enemy)
		return enemy
	var res := load(entry)
	if res is EnemyConfig:
		return (res as EnemyConfig).spawn(parent, local_pos)
	if res is FacilityEnemyConfig:
		var cfg := res as FacilityEnemyConfig
		var base := load(cfg.base_scene_path) as PackedScene
		if base == null:
			return null
		var made := base.instantiate() as Enemy
		if made == null:
			return null
		cfg.apply(made)
		made.position = local_pos
		parent.add_child(made)
		return made
	push_warning("StageWaves: unusable enemy entry %s" % entry)
	return null


## A ground point 8 to 14 m from the player with a clear line to them (no wall or prop between), found by
## ray casts. Falls back to closer rings and finally to a spot just beside the player.
func _pick_spawn_point() -> Vector3:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var center := player.global_position if player != null else global_position
	var space := get_world_3d().direct_space_state
	for ring in [[8.0, 14.0], [5.0, 8.0], [3.0, 5.0]]:
		for attempt in SPAWN_ATTEMPTS:
			var angle := randf() * TAU
			var distance := randf_range(float(ring[0]), float(ring[1]))
			var probe := center + Vector3(cos(angle), 0.0, sin(angle)) * distance
			var down := PhysicsRayQueryParameters3D.create(probe + Vector3.UP * 30.0, probe + Vector3.DOWN * 60.0, 1)
			var hit := space.intersect_ray(down)
			if hit.is_empty():
				continue
			var ground: Vector3 = hit["position"]
			if absf(ground.y - center.y) > 6.0:
				continue
			var sight := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 1.2, ground + Vector3.UP * 1.2, 1)
			if not space.intersect_ray(sight).is_empty():
				continue
			return ground + Vector3.UP * 0.3
	return center + Vector3(2.5, 0.3, 2.5)


# --- failure ---------------------------------------------------------------------------

func _bind_player() -> void:
	if _player_bound:
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.health == null:
		return
	_player_bound = true
	player.health.died.connect(_on_player_died)


## The player dying stops the encounter: no new spawns, no clear, no reward, and the survivors go away.
func _on_player_died() -> void:
	if not is_active():
		return
	_next_in = -1.0
	_wave_spawned = false
	_set_state(State.FAILED)
	_free_enemies()
	_rearm = REARM_SECONDS
	failed.emit()


func _reset_after_failure() -> void:
	_free_enemies()
	current_wave = 0
	_rearm = -1.0
	_set_state(State.IDLE)
	if _trigger != null and is_instance_valid(_trigger):
		_trigger.monitoring = true


func _free_enemies() -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			(enemy as Node).queue_free()
	_enemies.clear()


# --- the hold area -------------------------------------------------------------------------

func _build_trigger() -> void:
	_trigger = Area3D.new()
	_trigger.name = "HoldArea"
	_trigger.collision_layer = 0
	_trigger.collision_mask = 2  # the player's layer
	_trigger.monitoring = true
	_trigger.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = HOLD_SIZE
	shape.shape = box
	shape.position = Vector3(0.0, HOLD_SIZE.y * 0.5, 0.0)
	_trigger.add_child(shape)
	_trigger.body_entered.connect(_on_body_entered)
	add_child(_trigger)


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		start()


# --- helpers -------------------------------------------------------------------------

func _set_state(value: State) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(int(value))


func _say(text: String) -> void:
	Outpost17.say(self, text, 3.5)


func _flag(flag: StringName) -> bool:
	var world := get_node_or_null("/root/WorldState")
	return world != null and world.has_flag(flag)


func _set_flag(flag: StringName) -> void:
	var world := get_node_or_null("/root/WorldState")
	if world != null:
		world.set_flag(flag)
