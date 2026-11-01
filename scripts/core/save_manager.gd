extends Node
## Versioned local save (autoload "SaveManager"). JSON in user://, written atomically, stable item ids only.
## Also carries the in-memory "resume" state that survives a scene reload (manual Load, death restart).
## Behaviour is documented in docs/SAVE.md.

signal saved(reason: String)

const CURRENT_VERSION: int = 1
const MAX_POTIONS: int = 99

## 1-based wave to start on, and whether a Load is queued for the next scene start.
var pending_load: bool = false
var pending_data: Dictionary = {}
## In-memory snapshot taken at every wave start; used when the scene restarts after a death.
var checkpoint: Dictionary = {}
var defeated_bosses: Array[String] = []
var slot: int = 1
## Headless runs (tests) use a separate file so they never touch the real save.
var test_mode: bool = DisplayServer.get_name() == "headless"
var last_error: String = ""

var _notice: String = ""


# --- paths -----------------------------------------------------------------

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
	return {
		"version": CURRENT_VERSION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"next_wave": next_wave,
		"completed": completed,
		"inventory": player.inventory.to_dict(),
		"player": {"health": player.health.health, "max_health": player.health.max_health},
		"defeated_bosses": defeated_bosses.duplicate(),
	}


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
	defeated_bosses.clear()
	for boss in data["defeated_bosses"]:
		defeated_bosses.append(boss)
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
	return {
		"version": CURRENT_VERSION,
		"saved_at": int(data.get("saved_at", 0)),
		"next_wave": clampi(int(data.get("next_wave", 1)), 1, WaveManager.WAVES.size()),
		"completed": bool(data.get("completed", false)),
		"inventory": {
			"weapon": str(inventory.get("weapon", "")),
			"armor": str(inventory.get("armor", "")),
			"potions": clampi(int(inventory.get("potions", 0)), 0, MAX_POTIONS),
		},
		"player": clean_player,
		"defeated_bosses": bosses,
	}


# --- resuming into a fresh scene -------------------------------------------

## What the new Player/Inventory should restore: a queued Load first, else the death checkpoint.
func peek_restore() -> Dictionary:
	if pending_load and not pending_data.is_empty():
		return pending_data
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
	_notice = ""


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
