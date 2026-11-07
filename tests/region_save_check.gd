extends SceneTree
## Save version 4 and region persistence (headless): godot --headless --path . -s tests/region_save_check.gd
## Uses SaveManager's per-process test file, never the real save.

var _failures: int = 0
var _checks: int = 0
var _sm: Node
var _rm: Node
var _world: Node


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


func _clean() -> void:
	_sm.reset_runtime_state()
	_sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = _sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_sm.defeated_bosses.clear()
	_world.reset()


func _write_raw(text: String) -> void:
	var file := FileAccess.open(_sm.save_path(), FileAccess.WRITE)
	file.store_string(text)
	file = null


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(6)
	return main


func _run() -> void:
	_sm = root.get_node("SaveManager")
	_rm = root.get_node("RegionManager")
	_world = root.get_node("WorldState")
	# This suite tests saving with the generic stub region (it counts visits); the real Research Complex has its own suites.
	RegionStore.load_data(&"research_complex").scene_path = "res://scenes/regions/StubRegion.tscn"
	_clean()
	_test_migration_and_hostile_data()
	await _test_save_in_region_and_reload()
	await _test_claims_survive_reload()
	await _test_checkpoint_in_region()
	_clean()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_migration_and_hostile_data() -> void:
	print("Version 3 -> 4 and hostile data")
	_check(_sm.CURRENT_VERSION == 4, "the save format is version 4")
	var v3 := '{"version": 3, "next_wave": 2, "completed": false, "inventory": {"weapon": "combat_knife", "armor": "", "potions": 2}, "player": {"health": 70, "max_health": 100}, "defeated_bosses": ["warden"], "progression": {}}'
	_write_raw(v3)
	_check(_sm.load_game(), "a real version 3 save still loads")
	var data: Dictionary = _sm.pending_data
	_check(int(data["version"]) == 4 and data["regions"]["current"] == "outpost_17", "it is upgraded and placed in Outpost 17")
	_check(data["regions"]["unlocked"] == ["outpost_17"] and (data["regions"]["states"] as Dictionary).is_empty(), "nothing else unlocked, no region state")
	_check(data["inventory"]["weapon"] == "combat_knife" and int(data["inventory"]["potions"]) == 2 and data["defeated_bosses"] == ["warden"],
			"its weapon, medkits and boss list are intact")
	_check(_rm.pending_restore.is_empty() and _rm.current_region_id == &"outpost_17", "no region switch is queued")
	_clean()

	var clean := RegionStore.sanitize({"current": "atlantis", "unlocked": ["atlantis", 7, "dead_coast", "dead_coast"],
			"states": {"atlantis": {"ids": {"x": true}}, "dead_coast": "garbage", "blackwood": {"ids": {"a": true, "": true}, "custom": {"k": 1}}}})
	_check(clean["current"] == "outpost_17", "an unknown current region falls back to Outpost 17")
	_check(clean["unlocked"] == ["outpost_17", "dead_coast"], "unknown and duplicate unlocks are dropped (%s)" % str(clean["unlocked"]))
	_check(not (clean["states"] as Dictionary).has("atlantis") and not (clean["states"] as Dictionary).has("dead_coast"), "unknown regions and non-dictionary states are dropped")
	_check((clean["states"]["blackwood"]["ids"] as Dictionary).has("a") and not (clean["states"]["blackwood"]["ids"] as Dictionary).has(""), "empty claimed ids are dropped, good ones kept")
	_check(RegionStore.sanitize("not a dictionary") == RegionStore.default_section(), "a non-dictionary section becomes the default")
	_check(RegionStore.sanitize({"current": "blackwood", "unlocked": ["dead_coast"]})["current"] == "outpost_17",
			"being saved in a region that is not unlocked starts in Outpost 17")
	var far := RegionStore.sanitize({"current": "dead_coast", "unlocked": ["dead_coast"], "position": [1e12, "x", 0]})
	_check(not far.has("position"), "a malformed position is dropped")
	var clamped := RegionStore.sanitize({"current": "dead_coast", "unlocked": ["dead_coast"], "position": [1e12, 2, -1e12]})
	_check(clamped.has("position") and absf(float(clamped["position"][0])) <= 2000.0, "an absurd position is clamped")
	var big_custom := {"blob": "x".repeat(30000)}
	var big := RegionStore.sanitize({"states": {"blackwood": {"ids": {}, "custom": big_custom}}})
	_check((big["states"]["blackwood"]["custom"] as Dictionary).is_empty(), "an oversized custom state is dropped")
	var many := {}
	for i in 800:
		many["id_%d" % i] = true
	var capped := RegionStore.sanitize({"states": {"blackwood": {"ids": many}}})
	_check((capped["states"]["blackwood"]["ids"] as Dictionary).size() == RegionStore.MAX_CLAIMED, "claimed ids are capped at %d" % RegionStore.MAX_CLAIMED)
	_write_raw('{"version": 4, "regions": {"current": 5, "unlocked": "no", "states": []}, "inventory": {"weapon": "", "armor": "", "potions": 0}, "player": {"health": 50, "max_health": 100}}')
	_check(_sm.load_game() and _sm.pending_data["regions"]["current"] == "outpost_17", "a hostile regions section loads with safe defaults")
	_clean()


func _test_save_in_region_and_reload() -> void:
	print("Saving inside the Research Complex and loading")
	_clean()
	_rm.reset()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	_world.set_flag(&"mission_first_signal_complete")
	_rm.unlock(&"research_complex")  # the real Dead Coast has no `visits`; this save test needs the stub region
	_check(await _rm.travel(&"research_complex", &"from_blackwood"), "travelled to the Research Complex")
	var stub := _stub_of(main)
	stub.visits = 7
	player.global_position = Vector3(5.0, 0.1, 12.0)
	await _frames(3)
	_check(_sm.save_game("manual"), "saving inside the Research Complex works")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(raw is Dictionary and raw["regions"]["current"] == "research_complex", "the file records the current region")
	_check(raw["regions"]["states"]["research_complex"]["custom"]["visits"] == 7, "the file records the region's own state")
	_check(raw["regions"]["unlocked"].has("research_complex") and raw.has("version") and int(raw["version"]) == 4, "it records the unlock and version 4")
	var saved_pos: Array = raw["regions"]["position"]
	main.queue_free()
	await _frames(4)
	_rm.reset()
	_world.reset()
	_check(_sm.load_game(), "loading the saved game succeeds")
	_check(_rm.pending_restore.get("current", "") == "research_complex", "a switch to the Research Complex is queued")
	var main2 := await _spawn_main()
	await _frames(14)
	_check(_rm.current_region_id == &"research_complex", "the new game starts in the Research Complex")
	var player2 := main2.get_node("Player") as Player
	_check(player2.global_position.distance_to(Vector3(float(saved_pos[0]), float(saved_pos[1]), float(saved_pos[2]))) < 1.0,
			"the player is where they saved (%s)" % str(player2.global_position))
	var stub2 := _stub_of(main2)
	_check(stub2 != null and stub2.visits == 8, "the region state came back (visits 7 plus this entry: %s)" % str(stub2.visits if stub2 else null))
	_check(main2.get_node_or_null("Outpost17") == null, "Outpost 17 is not in the tree while in the Research Complex")
	_check(await _rm.travel(&"outpost_17", &"from_south"), "travelling back to Outpost 17 works after loading")
	_check(main2.get_node_or_null("Outpost17") != null, "Outpost 17 is built and present")
	main2.queue_free()
	await _frames(4)
	_clean()
	_rm.reset()


func _test_claims_survive_reload() -> void:
	print("Claimed rewards do not repeat after a reload")
	_clean()
	_rm.reset()
	var main := await _spawn_main()
	_check(PersistentIds.claim(&"dead_coast", &"cache_wreck_01"), "the cache reward is granted once")
	_check(PersistentIds.claim(&"blackwood", &"log_01"), "another region's id is separate")
	_check(_sm.save_game("manual"), "saved")
	main.queue_free()
	await _frames(4)
	_rm.reset()
	_check(not PersistentIds.is_claimed(&"dead_coast", &"cache_wreck_01"), "reset forgets claims (a new game)")
	_check(_sm.load_game(), "loaded")
	var main2 := await _spawn_main()
	await _frames(3)
	_check(PersistentIds.is_claimed(&"dead_coast", &"cache_wreck_01") and PersistentIds.is_claimed(&"blackwood", &"log_01"), "claims survived the reload")
	_check(not PersistentIds.claim(&"dead_coast", &"cache_wreck_01"), "the same reward cannot be claimed again after loading")
	_check(PersistentIds.claim(&"dead_coast", &"cache_wreck_02"), "a new id is still claimable")
	main2.queue_free()
	await _frames(4)
	_clean()
	_rm.reset()


func _test_checkpoint_in_region() -> void:
	print("Checkpoints remember their region")
	_clean()
	_rm.reset()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	_world.set_flag(&"mission_first_signal_complete")
	await _rm.travel(&"dead_coast", &"from_outpost")
	player.global_position = Vector3(-4.0, 0.1, 6.0)
	await _frames(3)
	_check(_sm.activate_checkpoint("coast_cp"), "a checkpoint can be activated in Dead Coast")
	_check(str(_sm.world_checkpoint.get("region", "")) == "dead_coast", "the checkpoint records its region")
	player.health.take_damage(10000.0)  # the real death path: respawn data is queued before the 2 s reload
	await _frames(2)
	_check(_rm.pending_restore.get("current", "") == "dead_coast", "dying queues a respawn in the checkpoint's region")
	_check(_sm.world_checkpoint.get("region", "") == "dead_coast", "the checkpoint is still in place")
	main.queue_free()
	await create_timer(2.6).timeout  # drain the pending reload timer of the dead player
	_clean()
	_rm.reset()


func _stub_of(main: Node) -> StubRegion:
	for child in main.get_children():
		if child is StubRegion:
			return child
	return null
