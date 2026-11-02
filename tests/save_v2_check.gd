extends SceneTree
## Save version 2 and checkpoint checks (headless): godot --headless --path . -s tests/save_v2_check.gd
## Uses SaveManager's per-process test file, never the real save.

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
	_clean()
	_test_migration_and_sanitising()
	await _test_checkpoint_and_respawn()
	_test_load_restores_checkpoint()
	await _test_real_reload_respawn()
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


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _test_migration_and_sanitising() -> void:
	print("Version 1 -> 2")
	_write_raw('{"version": 1, "next_wave": 2, "completed": false, "inventory": {"weapon": "combat_knife", "armor": "", "potions": 3}, "player": {"health": 80, "max_health": 100}, "defeated_bosses": []}')
	_check(_sm.load_game(), "a real version 1 save still loads")
	var data: Dictionary = _sm.pending_data
	_check(int(data["version"]) == 2 and data["world"]["checkpoint_id"] == "" and data["world"]["position"] == null,
			"it is upgraded to version 2 with an empty world section")
	_check(data["inventory"]["weapon"] == "combat_knife" and int(data["inventory"]["potions"]) == 3 and int(data["next_wave"]) == 2,
			"its inventory and wave are untouched")
	_check(_sm.consume_spawn_position() == null, "no checkpoint means the default spawn")
	_clean()

	var clean: Dictionary = _sm._sanitize_world({"checkpoint_id": "x".repeat(200), "position": [1, 2, 3]})
	_check(String(clean["checkpoint_id"]).length() == 64, "an over-long checkpoint id is cut to 64 characters")
	clean = _sm._sanitize_world({"checkpoint_id": "cp", "position": [99999, -99999, 5]})
	_check(is_equal_approx(float(clean["position"][0]), 1000.0) and is_equal_approx(float(clean["position"][1]), -1000.0),
			"a huge position is clamped to the world limit")
	clean = _sm._sanitize_world({"checkpoint_id": "cp", "position": ["a", 2, 3]})
	_check(clean["position"] == null and clean["checkpoint_id"] == "", "a malformed position means no checkpoint")
	clean = _sm._sanitize_world({"checkpoint_id": "cp"})
	_check(clean["position"] == null, "an id without a position means no checkpoint")
	_check(_sm._sanitize_world("not a dictionary")["position"] == null, "a non-dictionary world section is ignored")


func _test_checkpoint_and_respawn() -> void:
	print("Checkpoint and respawn")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	player.global_position = Vector3(3.0, 0.1, -40.0)
	player.health.take_damage(23.0)
	player.inventory.add_item(load("res://resources/items/military_machete.tres") as ItemData)
	await _frames(2)

	_check(_sm.activate_checkpoint("checkpoint_c"), "activating a checkpoint writes the save")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(parsed is Dictionary and int(parsed["version"]) == 2, "the file is version 2")
	var world: Dictionary = parsed["world"]
	_check(world["checkpoint_id"] == "checkpoint_c", "it records the checkpoint id")
	_check(absf(float(world["position"][0]) - 3.0) < 0.2 and absf(float(world["position"][2]) + 40.0) < 0.2,
			"it records where the player stood")
	_check(_sm.world_checkpoint["inventory"]["weapon"] == "military_machete", "the checkpoint remembers the equipped weapon")
	_check(is_equal_approx(float(_sm.world_checkpoint["player"]["health"]), 77.0), "and the health at that moment")
	var tmp: String = _sm.save_path() + ".tmp"
	_check(not FileAccess.file_exists(tmp), "no half-written temp file is left behind")

	# Dying outside the arena waves queues a respawn at the checkpoint
	player.health.take_damage(1000.0)
	_check(_sm._respawn_pending, "dying outside the arena waves queues a checkpoint respawn")
	var restore: Dictionary = _sm.peek_restore()
	_check(restore.get("inventory", {}).get("weapon", "") == "military_machete", "the new Player will get the checkpoint inventory")
	var spawn: Variant = _sm._spawn_position
	_check(spawn is Vector3 and (spawn as Vector3).distance_to(Vector3(3.0, 0.1, -40.0)) < 0.3, "and spawn at the checkpoint position")
	main.queue_free()
	await _frames(3)
	_sm.reset_runtime_state()
	_check(_sm.world_checkpoint.is_empty() and _sm.checkpoint_id == "" and not _sm._respawn_pending,
			"a deliberate restart forgets the checkpoint")

	# Dying while the arena waves are running keeps the existing wave-checkpoint behaviour
	main = await _spawn_main()
	player = main.get_node("Player") as Player
	_sm.activate_checkpoint("checkpoint_b")
	var waves := main.get_node("WaveManager") as WaveManager
	waves.start_delay = 0.0
	waves.start()
	var guard := 0
	while not waves.has_started() and guard < 200:
		await physics_frame
		guard += 1
	player.health.take_damage(1000.0)
	_check(not _sm._respawn_pending, "dying during the arena waves does not use the world checkpoint")
	main.queue_free()
	await _frames(3)
	_clean()


func _test_load_restores_checkpoint() -> void:
	print("Loading a checkpoint save")
	_write_raw('{"version": 2, "next_wave": 1, "completed": false, "inventory": {"weapon": "iron_sword", "armor": "", "potions": 1}, "player": {"health": 60, "max_health": 100}, "defeated_bosses": [], "world": {"checkpoint_id": "checkpoint_c", "position": [5, 0.1, -45]}}')
	_check(_sm.load_game(), "a version 2 save with a checkpoint loads")
	_check(_sm.checkpoint_id == "checkpoint_c", "the checkpoint id is restored")
	var spawn: Variant = _sm.consume_spawn_position()
	_check(spawn is Vector3 and (spawn as Vector3).distance_to(Vector3(5.0, 0.1, -45.0)) < 0.01, "Load resumes at the checkpoint position")
	_check(_sm.consume_spawn_position() == null, "the spawn position applies exactly once")
	_check(_sm.world_checkpoint["inventory"]["weapon"] == "iron_sword", "later deaths respawn with that inventory")
	_clean()


func _test_real_reload_respawn() -> void:
	print("Real death and scene reload")
	# Earlier tests killed players: their 2 s reload timers are still pending and would reload THIS scene.
	await create_timer(2.6).timeout
	_clean()
	var main := await _spawn_main()
	current_scene = main  # so Player._die's reload_current_scene() has a scene to reload
	var player := main.get_node("Player") as Player
	player.global_position = Vector3(6.0, 0.1, -41.0)
	player.inventory.add_item(load("res://resources/items/military_machete.tres") as ItemData)
	player.health.take_damage(10.0)
	await _frames(2)
	_sm.activate_checkpoint("checkpoint_e2e")
	player.global_position = Vector3(0.0, 0.1, 5.0)  # walk away from the checkpoint
	player.health.take_damage(1000.0)  # die outside the arena waves
	var guard := 0
	while (current_scene == main or not is_instance_valid(current_scene)) and guard < 600:
		await physics_frame
		guard += 1
	_check(current_scene != null and current_scene != main, "the scene reloads after death")
	await _frames(20)
	var reloaded := current_scene
	var new_player := reloaded.get_node("Player") as Player if reloaded else null
	_check(new_player != null and not new_player.is_dead(), "a fresh player is alive")
	if new_player != null:
		_check(new_player.global_position.distance_to(Vector3(6.0, 0.1, -41.0)) < 0.6, "it stands at the checkpoint")
		_check(new_player.inventory.weapon != null and new_player.inventory.weapon.item_id == &"military_machete",
				"it carries what it had at the checkpoint")
		_check(is_equal_approx(new_player.health.health, 90.0), "and the health it had then (not full, not zero)")
	if reloaded:
		reloaded.queue_free()
	await _frames(3)
	_clean()
