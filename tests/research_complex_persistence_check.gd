extends SceneTree
## Research Complex persistence checks (headless): godot --headless --path . -s tests/research_complex_persistence_check.gd
## Real Main, real RegionManager travel, real SaveManager save and load (the per-process test file), in
## the middle of a mission and of both puzzles. Nothing repeats after a reload: claimed crates, cleared
## enemies, the elite's reward. Puzzles can still be finished. Travelling back and forth does not leak.

const PLAYER_HIT: String = "res://resources/attacks/heavy_1.tres"

var _failures: int = 0
var _checks: int = 0
var _rm: Node
var _world: Node
var _sm: Node
var _qm: Node
var _dummy: Node3D


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
	_rm.reset()
	_qm.intro_done = true
	_qm.mission_autosave = false
	Enemy.active_patrollers = 0


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(6)
	return main


func _hop(region_id: StringName, entry_id: StringName) -> bool:
	var ok: bool = await _rm.travel(region_id, entry_id, null, true)
	await _frames(3)
	return ok


func _content(main: Node) -> ResearchComplex:
	for child in main.get_children():
		if child is ResearchComplexRegion:
			return (child as ResearchComplexRegion).content
	return null


func _use(rc: ResearchComplex, id: String) -> bool:
	return (rc.parts.nodes[id] as Interactable).interact(_dummy)


func _kill(enemy: Enemy, limit: int = 600) -> void:
	var attack := load(PLAYER_HIT) as AttackData
	for i in limit:
		if not is_instance_valid(enemy) or enemy.is_dead():
			break
		enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame
	await _frames(4)


func _pickups(item_id: String) -> int:
	var found := 0
	for node in root.find_children("*", "Pickup", true, false):
		var pickup := node as Pickup
		if pickup != null and not pickup.is_queued_for_deletion() and pickup.item != null and String(pickup.item.item_id) == item_id:
			found += 1
	return found


func _run() -> void:
	_rm = root.get_node("RegionManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_qm = root.get_node("QuestManager")
	_dummy = Node3D.new()
	root.add_child(_dummy)
	_clean()
	_test_dotted_control()
	await _test_save_mid_mission()
	await _test_no_leaks()
	_clean()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_dotted_control() -> void:
	print("-- control: a dotted flag does not survive a save, an underscore flag does")
	_world.set_flag(&"research_complex.bad_flag")
	_world.set_flag(&"research_complex_good_flag")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.to_dict()))
	_world.reset()
	_world.from_dict(saved)
	_check(not _world.has_flag(&"research_complex.bad_flag"), "the dotted flag is lost (this is why every id is underscore-only)")
	_check(_world.has_flag(&"research_complex_good_flag"), "the underscore flag survives")
	_world.reset()


func _test_save_mid_mission() -> void:
	print("-- a real save and load in the middle of the missions")
	var main := await _spawn_main()
	_world.set_flag(&"mission_first_signal_complete")
	_rm.unlock(&"blackwood")
	_rm.unlock(&"research_complex")
	_check(await _hop(&"research_complex", &"from_blackwood"), "travel into the real Research Complex works")
	var rc := _content(main)
	_check(rc != null and _rm.current_region_id == &"research_complex", "the region is the real Research Complex")
	_check(_qm.is_active(&"rc_restricted_zone"), "its first mission started")
	var player := main.get_node("Player") as Player
	var arrival: Vector3 = (rc.entry_points["from_blackwood"] as Transform3D).origin
	_check(player.global_position.distance_to(arrival) < 1.0, "the player stands at the arrival (%s)" % str(player.global_position))

	# state in the middle of Mission 1 and of both puzzles
	_check(_use(rc, "rc_checkpoint_log") and (rc.parts.nodes["rc_checkpoint_panel"] as Interactable).interact(_dummy), "the logbook is searched and the admin credential taken")
	_check((rc.parts.doors["rc_admin_door"] as Interactable).interact(_dummy), "the admin door is opened")
	_check(_use(rc, "rc_cache_perimeter"), "the perimeter cache is taken")
	var guard_spawn := rc.parts.spawns["rc_guard_1"] as FacilityEnemySpawn
	var guard := guard_spawn.enemy if guard_spawn.enemy != null else guard_spawn.trigger()  # arriving within its radius may already have woken it
	await _frames(3)
	await _kill(guard)
	_check((rc.parts.spawns["rc_guard_1"] as FacilityEnemySpawn).is_cleared(), "guard 1 is cleared")
	var containment := rc.parts.puzzles["containment"] as ContainmentOverride
	_use(rc, "rc_override_a")
	_use(rc, "rc_override_b")
	_check(containment.active.size() == 2 and not containment.is_completed(), "two override terminals are on, the puzzle is unfinished")
	var lab := rc.parts.puzzles["lab_power"] as LabPowerPuzzle
	for i in lab.pattern.size():
		if lab.pattern[i]:
			lab.input(StringName("breaker_%d" % i))
	_check(lab.is_step_done(&"pattern") and not lab.is_completed(), "the lab breakers match, the main lever is not pulled yet")
	var elite := rc.release_elite()
	await _frames(3)
	await _kill(elite, 900)
	_check(elite != null and elite.is_dead(), "Subject Zero is defeated")
	_check(_pickups("containment_sigil") == 1, "his unique reward lies on the floor (%d)" % _pickups("containment_sigil"))
	var items_before := (player.inventory.count_of("bandage") + player.inventory.count_of("armor_patch") + player.inventory.count_of("credits_small"))
	player.global_position = Vector3(2.0, 0.1, -30.0)
	await _frames(2)
	_check(_sm.save_game("manual"), "the game saves inside the Research Complex")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(raw is Dictionary and raw["regions"]["current"] == "research_complex", "the file records the Research Complex as the current region")
	var flags_in_file: Array = ((raw["quests"]["world"] as Dictionary)["flags"]) if raw is Dictionary and raw.has("quests") else []
	_check(flags_in_file.has("credential_admin") and flags_in_file.has("door_rc_admin_door_open") and flags_in_file.has("rc_cache_perimeter_taken"),
			"the credential, the open door and the taken cache are in the file")
	_check(flags_in_file.has("research_complex_lab_power_pattern"), "the lab puzzle's first step is in the file")

	# a new process: nothing in memory
	main.queue_free()
	await _frames(4)
	_rm.reset()
	_world.reset()
	_qm.reset()
	_qm._load_quests()
	_check(_sm.load_game(), "loading the save succeeds")
	var main2 := await _spawn_main()
	await _frames(14)
	var rc2 := _content(main2)
	_check(_rm.current_region_id == &"research_complex" and rc2 != null, "the game restarts inside the real Research Complex")
	if rc2 == null:
		return
	var player2 := main2.get_node("Player") as Player
	_check(player2.global_position.distance_to(Vector3(2.0, 0.1, -30.0)) < 1.5, "the player is where they saved (%s)" % str(player2.global_position))
	_check(_world.has_flag(&"credential_admin"), "the admin credential is still held")
	_check((rc2.parts.doors["rc_admin_door"] as Door).is_open, "the admin door is still open")
	_check(_qm.is_active(&"rc_restricted_zone") or _qm.is_completed(&"rc_restricted_zone"), "the mission state came back")
	var stock_after := (player2.inventory.count_of("bandage") + player2.inventory.count_of("armor_patch") + player2.inventory.count_of("credits_small"))
	_check(not _use(rc2, "rc_cache_perimeter") and (player2.inventory.count_of("bandage") + player2.inventory.count_of("armor_patch") + player2.inventory.count_of("credits_small")) == stock_after,
			"the taken cache cannot be taken again")
	_check(stock_after >= items_before - 0, "nothing was lost from the bag (%d, was %d)" % [stock_after, items_before])
	var spawn1 := rc2.parts.spawns["rc_guard_1"] as FacilityEnemySpawn
	_check(spawn1.is_cleared() and spawn1.trigger() == null, "the cleared guard does not come back")
	_check(not (rc2.parts.spawns["rc_guard_2"] as FacilityEnemySpawn).is_cleared(), "the guards that were not defeated are still to deal with")
	var elite_spawn := rc2.parts.spawns["rc_elite_subject"] as FacilityEnemySpawn
	_check(elite_spawn.is_cleared() and rc2.release_elite() == null, "Subject Zero does not come back")
	await _frames(6)
	_check(_pickups("containment_sigil") == 1, "his reward is put back exactly once, not duplicated (%d)" % _pickups("containment_sigil"))
	# puzzles are never soft-locked by the reload
	var c2 := rc2.parts.puzzles["containment"] as ContainmentOverride
	_check(not c2.is_completed(), "the override is still open after the reload")
	_use(rc2, "rc_override_a")
	_use(rc2, "rc_override_b")
	_use(rc2, "rc_override_c")
	_check(c2.is_step_done(&"terminals"), "all three override terminals can be activated again")
	_use(rc2, "rc_override_lever")
	_check(c2.is_completed() and _world.has_flag(&"research_complex_containment_done"), "and the override completes")
	var l2 := rc2.parts.puzzles["lab_power"] as LabPowerPuzzle
	_check(l2.is_step_done(&"pattern"), "the lab puzzle's first step survived the reload")
	l2.input(&"lever")
	_check(l2.is_completed() and _world.has_flag(&"research_complex_lab_power_done"), "the lab puzzle finishes with one lever pull")
	main2.queue_free()
	await _frames(4)
	_clean()


func _test_no_leaks() -> void:
	print("-- five round trips between Blackwood and the Research Complex")
	var main := await _spawn_main()
	_world.set_flag(&"mission_first_signal_complete")
	_rm.unlock(&"blackwood")
	_rm.unlock(&"research_complex")
	var route: Array = [[&"research_complex", &"from_blackwood"], [&"blackwood", &"from_underground"]]
	await _hop(&"blackwood", &"from_dead_coast")
	for hop in route:  # one warm-up cycle so caches are filled before the baseline
		await _hop(hop[0], hop[1])
	await _frames(10)
	var base_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var worst_ms := 0
	var all_ok := true
	for round in 5:
		for hop in route:
			var t0 := Time.get_ticks_msec()
			var ok: bool = await _hop(hop[0], hop[1])
			all_ok = all_ok and ok
			worst_ms = maxi(worst_ms, Time.get_ticks_msec() - t0)
	await _frames(20)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check(all_ok, "every hop in five cycles worked")
	_check(abs(nodes - base_nodes) <= 40, "node count returns to baseline (%d now, %d before)" % [nodes, base_nodes])
	print("  info slowest hop (ms, includes first-frame builds): ", worst_ms)
	_check(_rm.current_region_id == &"blackwood", "the cycles end in Blackwood")
	main.queue_free()
	await _frames(4)
	_clean()
