extends Node
## Versioned local save (autoload "SaveManager"). JSON in user://, written atomically, stable item ids only.
## Also carries the in-memory "resume" state that survives a scene reload (manual Load, death restart).
## Behaviour is documented in docs/SAVE.md.

signal saved(reason: String)

const CURRENT_VERSION: int = 2
const MAX_POTIONS: int = 99
const MAX_WORLD_IDS: int = 256
const POSITION_LIMIT: float = 1000.0

## 1-based wave to start on, and whether a Load is queued for the next scene start.
var pending_load: bool = false
var pending_data: Dictionary = {}
## In-memory snapshot taken at every wave start; used when the scene restarts after a death.
var checkpoint: Dictionary = {}
var defeated_bosses: Array[String] = []
var slot: int = 1

## Last activated world checkpoint (kept in memory across scene reloads): where a death outside the
## arena waves respawns. {id, position [x,y,z], inventory, player{health,max_health}}.
var world_checkpoint: Dictionary = {}
var checkpoint_id: String = ""

var _respawn_pending: bool = false  # the player died outside the arena: next scene starts at the checkpoint
var _spawn_position: Variant = null  # Vector3 queued for the next Player (null = default spawn)
## Headless runs (tests) use a separate file so they never touch the real save.
var test_mode: bool = DisplayServer.get_name() == "headless"
var last_error: String = ""

var _notice: String = ""


# --- paths -----------------------------------------------------------------

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


## A Player's HealthComponent is created per scene, so hook each new Player once it is ready.
func _on_node_added(node: Node) -> void:
	var player := node as Player
	if player != null:
		player.ready.connect(_on_player_ready.bind(player), CONNECT_ONE_SHOT)


func _on_player_ready(player: Player) -> void:
	if player.health != null:
		player.health.died.connect(_on_player_died)
	_place_player_after_setup(player)


## Death outside the arena waves respawns at the last checkpoint; inside the waves the existing
## wave checkpoint keeps its behaviour (WaveManager.consume_start_wave).
func _on_player_died() -> void:
	var waves := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	var in_arena := waves != null and waves.has_started() and not waves.is_finished()
	_respawn_pending = not in_arena and not world_checkpoint.is_empty()
	if _respawn_pending:
		_spawn_position = _position_from(world_checkpoint.get("position", null))


## Moves the new Player to a queued spawn position after every _ready (WorldFlow places the
## player at the beach start in its own _ready, which would otherwise win).
func _place_player_after_setup(player: Player) -> void:
	_respawn_pending = false  # Player._ready has already taken what it needed from the checkpoint
	if _spawn_position == null:
		return
	await get_tree().process_frame
	var target: Variant = consume_spawn_position()
	if target != null and is_instance_valid(player):
		player.global_position = target
		player.velocity = Vector3.ZERO


## One-shot: the position a fresh Player should start at (a loaded checkpoint or a respawn).
func consume_spawn_position() -> Variant:
	var pos: Variant = _spawn_position
	_spawn_position = null
	return pos


static func _position_from(raw: Variant) -> Variant:
	if raw is Vector3:
		return raw
	if raw is Array and (raw as Array).size() == 3:
		var a: Array = raw
		for v in a:
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				return null
		return Vector3(clampf(float(a[0]), -POSITION_LIMIT, POSITION_LIMIT),
				clampf(float(a[1]), -POSITION_LIMIT, POSITION_LIMIT),
				clampf(float(a[2]), -POSITION_LIMIT, POSITION_LIMIT))
	return null


func save_path() -> String:
	if test_mode:  # one file per test process: parallel test runs must not share a save
		return "user://save_test_%d_slot_%d.json" % [OS.get_process_id(), slot]
	return "user://save_slot_%d.json" % slot


func has_save() -> bool:
	return FileAccess.file_exists(save_path())


func delete_save() -> void:
	for path in [save_path(), save_path() + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- saving ----------------------------------------------------------------

## Snapshot of the running game, or {} when there is nothing sensible to save (no player, or dead).
func build_save() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.is_dead():
		return {}
	var next_wave := 1
	var completed := false
	var waves := get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if waves:
		next_wave = waves.resume_index()
		completed = waves.is_finished()
	var data := {
		"version": CURRENT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"next_wave": next_wave,
		"completed": completed,
		"inventory": player.inventory.to_dict(),
		"player": {"health": player.health.health, "max_health": player.health.max_health},
		"defeated_bosses": defeated_bosses.duplicate(),
	}
	var quest_manager := get_node_or_null("/root/QuestManager")
	if quest_manager:
		data["quests"] = quest_manager.to_dict()  # optional field: older saves simply do not have it
	var run_stats := get_node_or_null("/root/RunStats")
	if run_stats:
		data["stats"] = run_stats.to_dict()  # optional too
	var world := {"checkpoint_id": "", "position": null}
	if not world_checkpoint.is_empty():
		var p: Variant = _position_from(world_checkpoint.get("position", null))
		if p != null:
			var v: Vector3 = p
			world = {"checkpoint_id": checkpoint_id, "position": [v.x, v.y, v.z]}
	data["world"] = world
	return data


## Activating a checkpoint: remember where the player stands and what they carry, then write the whole
## game to disk. Death outside the arena waves respawns here. Returns true if the file was written.
func activate_checkpoint(id: String) -> bool:
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.is_dead():
		return false
	checkpoint_id = id
	world_checkpoint = {
		"position": [player.global_position.x, player.global_position.y, player.global_position.z],
		"inventory": player.inventory.to_dict(),
		"player": {"health": player.health.health, "max_health": player.health.max_health},
	}
	return save_game("checkpoint")


func save_game(reason: String = "manual") -> bool:
	var data := build_save()
	if data.is_empty():
		last_error = "nothing to save"
		return false
	return write_data(data, reason)


func autosave(reason: String = "auto") -> bool:
	return save_game(reason)


## Atomic write: full contents go to <file>.tmp first, then it replaces the real file.
func write_data(data: Dictionary, reason: String = "manual") -> bool:
	var path := save_path()
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		last_error = "cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()]
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file = null  # closes the file
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		last_error = "cannot replace %s (error %d)" % [path, err]
		DirAccess.remove_absolute(tmp)
		return false
	last_error = ""
	saved.emit(reason)
	return true


# --- loading ---------------------------------------------------------------

## Reads and validates the save. On success the data is queued (pending_load) so the next scene
## start restores it; the caller reloads the scene. Never throws; failures return false.
func load_game() -> bool:
	last_error = ""
	var path := save_path()
	if not FileAccess.file_exists(path):
		last_error = "no save"
		return false
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return _reject_corrupt(path, "corrupt save")
	var data: Dictionary = json.data
	var raw_version: Variant = data.get("version", 0)
	if typeof(raw_version) != TYPE_INT and typeof(raw_version) != TYPE_FLOAT:
		return _reject_corrupt(path, "bad version")
	if int(raw_version) > CURRENT_VERSION:
		last_error = "save is from a newer version (%d)" % int(raw_version)
		return false  # leave the file alone: a newer build can still read it
	data = _sanitize(_migrate(data))
	if data.is_empty():
		return _reject_corrupt(path, "invalid save contents")
	pending_data = data
	pending_load = true
	# A save made at a checkpoint resumes there, and later deaths outside the arena respawn there too.
	var world: Dictionary = data.get("world", {})
	var spawn: Variant = _position_from(world.get("position", null))
	if spawn != null:
		_spawn_position = spawn
		checkpoint_id = str(world.get("checkpoint_id", ""))
		world_checkpoint = {"position": world["position"], "inventory": data["inventory"], "player": data["player"]}
	defeated_bosses.clear()
	for boss in data["defeated_bosses"]:
		defeated_bosses.append(boss)
	var quest_manager := get_node_or_null("/root/QuestManager")
	if quest_manager:
		quest_manager.on_game_loaded(data.get("quests", {}))  # a pre-quest save restarts the quest line
	var run_stats := get_node_or_null("/root/RunStats")
	if run_stats:
		run_stats.reset()
		run_stats.from_dict(data.get("stats", {}))
	return true


func _reject_corrupt(path: String, message: String) -> bool:
	last_error = message
	if DirAccess.copy_absolute(path, path + ".bak") == OK:
		DirAccess.remove_absolute(path)  # keep the evidence, stop offering a broken Load
	return false


## Upgrades old save layouts one version at a time.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 0))
	while version < CURRENT_VERSION:
		match version:
			0:
				data = _migrate_0_to_1(data)
			1:
				data = _migrate_1_to_2(data)
		version += 1
		data["version"] = version
	return data


## v0 was a flat prototype layout: wave / weapon / armor / potions / hp.
func _migrate_0_to_1(old: Dictionary) -> Dictionary:
	return {
		"version": 1,
		"saved_at": int(old.get("saved_at", 0)),
		"next_wave": int(old.get("wave", 1)),
		"completed": bool(old.get("completed", false)),
		"inventory": {
			"weapon": str(old.get("weapon", "")),
			"armor": str(old.get("armor", "")),
			"potions": int(old.get("potions", 0)),
		},
		"player": {"health": float(old.get("hp", 0.0)), "max_health": float(old.get("max_hp", 0.0))},
		"defeated_bosses": old.get("defeated_bosses", []),
	}


## v1 had no world section: it simply gains an empty one (no checkpoint, default spawn).
func _migrate_1_to_2(old: Dictionary) -> Dictionary:
	var upgraded := old.duplicate(true)
	if not upgraded.has("world"):
		upgraded["world"] = {"checkpoint_id": "", "position": null}
	return upgraded


## Normalises types and ranges. Unknown keys are dropped. Returns {} if the shape is unusable.
func _sanitize(data: Dictionary) -> Dictionary:
	var inv_raw: Variant = data.get("inventory", {})
	var player_raw: Variant = data.get("player", {})
	if not inv_raw is Dictionary or not player_raw is Dictionary:
		return {}
	var inventory: Dictionary = inv_raw
	var player: Dictionary = player_raw
	var bosses: Array[String] = []
	var bosses_raw: Variant = data.get("defeated_bosses", [])
	if bosses_raw is Array:
		for boss in bosses_raw:
			if boss is String and not bosses.has(boss):
				bosses.append(boss)
	var clean_player := {}
	var max_health := float(player.get("max_health", 0.0))
	if max_health > 0.0:
		clean_player = {
			"health": clampf(float(player.get("health", max_health)), 1.0, max_health),
			"max_health": max_health,
		}
	var result := {
		"version": CURRENT_VERSION,
		"saved_at": int(data.get("saved_at", 0)),
		"next_wave": clampi(int(data.get("next_wave", 1)), 1, WaveManager.WAVES.size()),
		"completed": bool(data.get("completed", false)),
		"inventory": {
			"weapon": str(inventory.get("weapon", "")),
			"armor": str(inventory.get("armor", "")),
			# Optional (added after v1 shipped): current armor bar; -1 or missing means full.
			"armor_points": maxf(float(inventory.get("armor_points", -1.0)), -1.0),
			"potions": clampi(int(inventory.get("potions", 0)), 0, MAX_POTIONS),
		},
		"player": clean_player,
		"defeated_bosses": bosses,
	}
	var quests := QuestState.sanitize(data.get("quests", {}))
	if not quests.is_empty():
		result["quests"] = quests
	result["world"] = _sanitize_world(data.get("world", {}))
	var run_stats := get_node_or_null("/root/RunStats")
	if run_stats:
		var stats: Dictionary = run_stats.sanitize(data.get("stats", {}))
		if not stats.is_empty():
			result["stats"] = stats
	return result


## World section: the last checkpoint id and where it was. Anything malformed becomes "no checkpoint".
func _sanitize_world(raw: Variant) -> Dictionary:
	var clean := {"checkpoint_id": "", "position": null}
	if not raw is Dictionary:
		return clean
	var world: Dictionary = raw
	var id := str(world.get("checkpoint_id", "")).substr(0, 64)
	var pos: Variant = _position_from(world.get("position", null))
	if id != "" and pos != null:
		var v: Vector3 = pos
		clean = {"checkpoint_id": id, "position": [v.x, v.y, v.z]}
	return clean


# --- resuming into a fresh scene -------------------------------------------

## What the new Player/Inventory should restore: a queued Load first, else the death checkpoint.
func peek_restore() -> Dictionary:
	if pending_load and not pending_data.is_empty():
		return pending_data
	if _respawn_pending and not world_checkpoint.is_empty():
		return world_checkpoint  # died outside the arena: carry what the player had at the checkpoint
	return checkpoint


## Called once by WaveManager at scene start. Returns the 1-based wave to begin with and clears the
## queued resume state so it applies exactly once.
func consume_start_wave(total_waves: int) -> int:
	var wave := 1
	if pending_load and not pending_data.is_empty():
		wave = 1 if bool(pending_data.get("completed", false)) else int(pending_data.get("next_wave", 1))
		_notice = "Save loaded - wave %d" % clampi(wave, 1, total_waves)
	elif not checkpoint.is_empty():
		wave = int(checkpoint.get("next_wave", 1))
		_notice = "Back to wave %d" % clampi(wave, 1, total_waves)
	pending_load = false
	pending_data = {}
	checkpoint = {}
	return clampi(wave, 1, total_waves)


func set_checkpoint(wave: int) -> void:
	checkpoint = {"next_wave": wave}
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.inventory:
		checkpoint["inventory"] = player.inventory.to_dict()


func clear_checkpoint() -> void:
	checkpoint = {}


## A deliberate restart / new run: forget everything queued.
func reset_runtime_state() -> void:
	pending_load = false
	pending_data = {}
	checkpoint = {}
	world_checkpoint = {}
	checkpoint_id = ""
	_respawn_pending = false
	_spawn_position = null
	_notice = ""
	var quest_manager := get_node_or_null("/root/QuestManager")
	if quest_manager:
		quest_manager.reset()  # a fresh run starts the quest line (and the world flags) again
	var run_stats := get_node_or_null("/root/RunStats")
	if run_stats:
		run_stats.reset()


func mark_boss_defeated(boss_id: String) -> void:
	if not defeated_bosses.has(boss_id):
		defeated_bosses.append(boss_id)


## One-shot message for the HUD ("Save loaded - wave 3").
func consume_notice() -> String:
	var notice := _notice
	_notice = ""
	return notice


# --- web / mobile lifecycle ------------------------------------------------

func _notification(what: int) -> void:
	if test_mode:
		return
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Cheap, and only when a run is actually in progress (save_game refuses a dead/absent player).
			var waves := get_tree().get_first_node_in_group("wave_manager") as WaveManager
			if waves and not waves.is_finished():
				save_game("lifecycle")


func _exit_tree() -> void:
	if test_mode:
		for suffix in ["", ".tmp", ".bak"]:
			var path: String = save_path() + suffix
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
