extends SceneTree
## Save-system checks (headless): godot --headless --path . -s tests/save_check.gd
## Uses SaveManager's per-process test file, never the real save.

const ITEMS: String = "res://resources/items/"

var _failures: int = 0
var _checks: int = 0
var _sm: Node


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	_sm = root.get_node("SaveManager")
	_check(_sm.test_mode and _sm.save_path().contains("_test"), "headless run uses the test save file")
	_clean()
	await _test_round_trip_and_restore()
	_test_failure_modes()
	_test_item_ids()
	await _test_checkpoint_resume()
	await _test_autosave_and_boss()
	_clean()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _clean() -> void:
	_sm.reset_runtime_state()
	_sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = _sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_sm.defeated_bosses.clear()


func _write_raw(text: String) -> void:
	var file := FileAccess.open(_sm.save_path(), FileAccess.WRITE)
	file.store_string(text)
	file = null


func _item(id: String) -> ItemData:
	return load(ITEMS + id + ".tres") as ItemData


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _kill_all(player: Player) -> void:
	var kill := load("res://resources/attacks/heavy_1.tres") as AttackData
	for enemy in get_nodes_in_group("enemies"):
		for i in 12:
			(enemy as Enemy).receive_hit(kill, player.global_position)


func _test_round_trip_and_restore() -> void:
	print("Round trip and restore")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var waves := main.get_node("WaveManager") as WaveManager
	player.inventory.add_item(_item("military_machete"))
	player.inventory.add_item(_item("heavy_combat_armor"))
	player.inventory.add_item(_item("health_potion"))
	player.inventory.add_item(_item("health_potion"))
	player.health.health = 55.0
	waves.start_wave_at(3)

	_check(_sm.save_game("test"), "save_game succeeds")
	_check(_sm.has_save(), "save file exists")
	_check(not FileAccess.file_exists(_sm.save_path() + ".tmp"), "atomic write leaves no .tmp file")
	_check(_sm.save_game("test"), "saving again over an existing file works")
	_check(not FileAccess.file_exists(_sm.save_path() + ".tmp"), "still no .tmp after overwrite")

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(parsed is Dictionary and int(parsed["version"]) == 1, "file is JSON with version 1")
	_check(parsed["inventory"]["weapon"] == "military_machete" and parsed["inventory"]["potions"] == 2,
			"inventory is stored as ids and counts")
	_check(int(parsed["next_wave"]) == 3, "next_wave is the wave to resume on")
	_check(not str(parsed).contains("Resource") and not str(parsed).contains("res://"), "no objects or paths in the save")

	_check(_sm.load_game() and _sm.pending_load, "load_game queues the save")
	main.queue_free()
	await _frames(3)

	var restored_main := await _spawn_main()
	var restored := restored_main.get_node("Player") as Player
	_check(restored.inventory.weapon.item_id == &"military_machete", "weapon restored by id")
	_check(restored.inventory.armor.item_id == &"heavy_combat_armor", "armor restored by id")
	_check(restored.inventory.potions == 2, "medkits restored")
	_check(is_equal_approx(restored.health.health, 55.0) and is_equal_approx(restored.health.max_health, 100.0),
			"player health restored")
	_check(_sm.pending_load, "load stays queued until the wave manager starts")

	var restored_waves := restored_main.get_node("WaveManager") as WaveManager
	restored_waves.start_delay = 0.0
	restored_waves.start()
	_check(not _sm.pending_load and _sm.pending_data.is_empty(), "queued load is consumed exactly once")
	_check(restored_waves.resume_index() == 3, "wave manager resumes on the saved wave")
	var spawn_wait := 0
	while restored_waves.current_wave < 3 and spawn_wait < 120:
		await physics_frame
		spawn_wait += 1
	_check(restored_waves.current_wave == 3 and get_nodes_in_group("enemies").size() == 3, "wave 3 spawns (heavy, hunter, soldier)")
	restored_main.queue_free()
	await _frames(3)
	_clean()


func _test_failure_modes() -> void:
	print("Failure modes")
	_write_raw("{ this is not json")
	_check(not _sm.load_game(), "corrupt file: load_game returns false")
	_check(FileAccess.file_exists(_sm.save_path() + ".bak"), "corrupt file is kept as .bak")
	_check(not _sm.has_save() and not _sm.pending_load, "corrupt file is no longer offered for loading")
	_clean()

	_write_raw("[1, 2, 3]")
	_check(not _sm.load_game(), "valid JSON of the wrong shape is rejected")
	_clean()

	_write_raw('{"version": 99, "next_wave": 2}')
	_check(not _sm.load_game(), "newer save version is rejected")
	_check(_sm.has_save() and str(_sm.last_error).contains("newer"), "newer save is left untouched")
	_clean()

	_write_raw('{"version": "x"}')
	_check(not _sm.load_game(), "non-numeric version is rejected")
	_clean()

	_check(not _sm.load_game() and not _sm.pending_load, "missing file: load_game returns false")

	_write_raw('{"wave": 4, "weapon": "combat_knife", "armor": "reinforced_armor", "potions": 3, "hp": 40.0, "max_hp": 100.0}')
	_check(_sm.load_game(), "version 0 save loads")
	var data: Dictionary = _sm.pending_data
	_check(int(data["version"]) == 1, "version 0 is migrated to the current version")
	_check(int(data["next_wave"]) == 4 and data["inventory"]["weapon"] == "combat_knife" and data["inventory"]["potions"] == 3,
			"migrated fields are mapped")
	_check(is_equal_approx(data["player"]["health"], 40.0), "migrated health is mapped")
	_sm.reset_runtime_state()
	_clean()

	_write_raw('{"version": 1, "next_wave": 99, "inventory": {"potions": 5000}, "player": {"health": 9999, "max_health": 100}}')
	_check(_sm.load_game(), "out-of-range values still load")
	_check(int(_sm.pending_data["next_wave"]) == WaveManager.WAVES.size(), "next_wave is clamped to the last wave")
	_check(int(_sm.pending_data["inventory"]["potions"]) == 99, "potion count is clamped")
	_check(is_equal_approx(_sm.pending_data["player"]["health"], 100.0), "health is clamped to max")
	_sm.reset_runtime_state()
	_clean()


func _test_item_ids() -> void:
	print("Item ids")
	var inventory := Inventory.new()
	inventory._ready()
	inventory.from_dict({"weapon": "no_such_weapon", "armor": "../../project", "potions": -4})
	_check(inventory.weapon.item_id == &"improvised_blade", "unknown weapon id keeps the starting weapon")
	_check(inventory.armor == null, "unknown or hostile armor id is ignored")
	_check(inventory.potions == 0, "negative potion count is clamped")
	inventory.from_dict({"weapon": "light_tactical_armor", "armor": "combat_knife"})
	_check(inventory.weapon.item_id == &"improvised_blade" and inventory.armor == null, "an item in the wrong slot is ignored")
	inventory.from_dict({"weapon": "warden_blade", "armor": "warden_plate", "potions": 2})
	_check(inventory.weapon.item_id == &"warden_blade" and inventory.armor.item_id == &"warden_plate", "boss rewards restore by id")
	var round_trip := inventory.to_dict()
	_check(round_trip["weapon"] == "warden_blade" and round_trip["armor"] == "warden_plate" and round_trip["potions"] == 2,
			"to_dict mirrors from_dict")
	inventory.free()


func _test_checkpoint_resume() -> void:
	print("Death checkpoint")
	_clean()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var waves := main.get_node("WaveManager") as WaveManager
	player.inventory.add_item(_item("military_machete"))
	player.inventory.add_item(_item("health_potion"))
	waves.start_delay = 0.0
	waves.start_wave_at(3)
	var cp_wait := 0
	while waves.current_wave < 3 and cp_wait < 120:
		await physics_frame
		cp_wait += 1
	_check(waves.current_wave == 3, "wave 3 started")
	_check(int(_sm.checkpoint.get("next_wave", 0)) == 3, "wave start records a checkpoint")
	_check(_sm.checkpoint["inventory"]["weapon"] == "military_machete", "checkpoint holds the inventory at wave start")

	# What a death does: the scene is replaced; the autoload keeps the checkpoint.
	player.health.take_damage(1000.0)
	main.queue_free()
	await _frames(3)
	_check(not _sm.checkpoint.is_empty(), "checkpoint survives the scene being freed")

	var again := await _spawn_main()
	var reborn := again.get_node("Player") as Player
	_check(reborn.inventory.weapon.item_id == &"military_machete" and reborn.inventory.potions == 1, "inventory restored after a death restart")
	_check(is_equal_approx(reborn.health.health, reborn.health.max_health), "death restart gives full health")
	var waves_again := again.get_node("WaveManager") as WaveManager
	waves_again.start_delay = 0.0
	waves_again.start()
	_check(waves_again.resume_index() == 3, "death restart resumes on the wave the player died on")
	_check(_sm.checkpoint.is_empty(), "checkpoint is consumed once")
	_check(str(_sm.consume_notice()).contains("wave 3"), "HUD notice names the wave")
	await _frames(5)
	again.queue_free()
	await _frames(3)

	# A deliberate restart is a fresh run.
	_sm.set_checkpoint(4)
	_sm.reset_runtime_state()
	var fresh := await _spawn_main()
	var fresh_waves := fresh.get_node("WaveManager") as WaveManager
	fresh_waves.start()
	_check(fresh_waves.resume_index() == 1, "after reset_runtime_state a run starts from wave 1")
	_check((fresh.get_node("Player") as Player).inventory.potions == 0, "and with a fresh inventory")
	fresh.queue_free()
	await _frames(3)
	_clean()


func _test_autosave_and_boss() -> void:
	print("Autosave")
	_clean()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var waves := main.get_node("WaveManager") as WaveManager
	player.health.max_health = 100000.0
	player.health.health = 100000.0
	var signal_hits := [0]
	_sm.saved.connect(func(_reason: String) -> void: signal_hits[0] += 1)
	waves.start_delay = 0.0
	waves.between_waves_delay = 0.2
	waves.start_wave_at(1)
	var waited := 0
	while waves.current_wave < 1 and waited < 200:
		await physics_frame
		waited += 1
	_kill_all(player)
	waited = 0
	while waves.current_wave < 2 and waited < 400:
		await physics_frame
		waited += 1
	_check(waves.current_wave == 2, "wave 2 followed wave 1")
	_check(signal_hits[0] >= 1 and _sm.has_save(), "clearing a wave autosaves and emits saved")
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(saved is Dictionary and int(saved["next_wave"]) == 2, "autosave points at the next wave")
	_check(saved["defeated_bosses"].is_empty(), "no boss defeated yet")

	# Fight through to the Warden.
	waves.between_waves_delay = 0.2
	var guard := 0
	while waves.current_wave < 5 and guard < 40:
		_kill_all(player)
		await _frames(30)
		guard += 1
	_check(waves.current_wave == 5, "reached the Warden wave")
	guard = 0
	while not waves.is_finished() and guard < 60:
		_kill_all(player)
		await _frames(30)
		guard += 1
	_check(waves.is_finished(), "the Warden wave is cleared")
	var final: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(final is Dictionary and final["completed"] == true, "completion is saved")
	_check(final["defeated_bosses"].has("warden"), "defeated boss is recorded")
	_check(int(final["next_wave"]) == 1, "a completed run resumes from wave 1")
	_check(_sm.checkpoint.is_empty(), "no stale death checkpoint after completion")
	main.queue_free()
	await _frames(3)
	_clean()
