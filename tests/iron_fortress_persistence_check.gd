extends SceneTree
## Iron Fortress persistence checks (headless): godot --headless --path . -s tests/iron_fortress_persistence_check.gd
## Real RegionManager travel, a real SaveManager save and load in the middle of the missions and of both
## puzzles, no duplicated rewards, a boss that stays down, and no leaks across five round trips.

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


func _content(main: Node) -> IronFortress:
	for child in main.get_children():
		if child is IronFortressRegion:
			return (child as IronFortressRegion).content
	return null


func _use(f: IronFortress, id: String) -> bool:
	return (f.parts.nodes[id] as Interactable).interact(_dummy)


func _kill(enemy: Enemy, limit: int = 1200) -> void:
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
	_world.set_flag(&"iron_fortress.bad_flag")
	_world.set_flag(&"iron_fortress_good_flag")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.to_dict()))
	_world.reset()
	_world.from_dict(saved)
	_check(not _world.has_flag(&"iron_fortress.bad_flag"), "the dotted flag is lost (this is why every id is underscore-only)")
	_check(_world.has_flag(&"iron_fortress_good_flag"), "the underscore flag survives")
	_world.reset()


func _test_save_mid_mission() -> void:
	print("-- a real save and load in the middle of the missions")
	var main := await _spawn_main()
	_world.set_flag(&"mission_first_signal_complete")
	for id in [&"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]:
		_rm.unlock(id)
	_check(_rm.is_unlocked(&"iron_fortress"), "the Iron Fortress is unlocked for the test")
	_check(await _hop(&"iron_fortress", &"from_research_complex"), "travel into the real Iron Fortress works")
	var f := _content(main)
	_check(f != null and _rm.current_region_id == &"iron_fortress", "the region is the real Iron Fortress")
	_check(_qm.is_active(&"if_last_stronghold"), "its first mission started")
	var player := main.get_node("Player") as Player
	var arrival: Vector3 = (f.entry_points["from_research_complex"] as Transform3D).origin
	_check(player.global_position.distance_to(arrival) < 1.0, "the player stands at the arrival (%s)" % str(player.global_position))
	_check(_rm.current_region_id == &"iron_fortress" and IronFortressZones.location_at(player.global_position) == "Fortress Approach", "the location name resolves to the Fortress Approach")

	# state in the middle of mission 1 and of both puzzles, plus a defeated boss
	_check(_use(f, "if_checkpoint_log") and (f.parts.nodes["if_gate_panel"] as Interactable).interact(_dummy), "the log is searched and the gate credential taken")
	_check((f.parts.doors["if_gate_door"] as Interactable).interact(_dummy), "the main gate is opened")
	_check(_use(f, "if_cache_approach"), "the approach cache is taken")
	var guard_spawn := f.parts.fspawns["if_app_1"] as FortressSpawn
	var guard := guard_spawn.enemy if guard_spawn.enemy != null else guard_spawn.trigger()
	await _frames(3)
	await _kill(guard)
	_check((f.parts.fspawns["if_app_1"] as FortressSpawn).is_cleared(), "guard 1 is cleared")
	var comms := f.parts.puzzles["comms"] as LabPowerPuzzle
	for i in comms.pattern.size():
		if comms.pattern[i]:
			comms.input(StringName("breaker_%d" % i))
	_check(comms.is_step_done(&"pattern") and not comms.is_completed(), "the comms racks match, the main switch is not thrown yet")
	var lockdown := f.parts.puzzles["lockdown"] as ContainmentOverride
	_use(f, "if_lock_a")
	_use(f, "if_lock_b")
	_check(lockdown.active.size() == 2 and not lockdown.is_completed(), "two lockdown points are off, the puzzle is unfinished")
	var captain := f.release_captain()
	await _frames(3)
	await _kill(captain, 1500)
	_check(captain != null and captain.is_dead(), "the Fortress Captain is defeated")
	_check(_pickups("captain_insignia") == 1, "his unique reward lies on the floor (%d)" % _pickups("captain_insignia"))
	var items_before := player.inventory.count_of("bandage") + player.inventory.count_of("armor_patch") + player.inventory.count_of("credits_small")
	player.global_position = Vector3(2.0, 0.1, -30.0)
	await _frames(2)
	_check(_sm.save_game("manual"), "the game saves inside the Iron Fortress")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(raw is Dictionary and raw["regions"]["current"] == "iron_fortress", "the file records the Iron Fortress as the current region")
	var flags_in_file: Array = ((raw["quests"]["world"] as Dictionary)["flags"]) if raw is Dictionary and raw.has("quests") else []
	_check(flags_in_file.has("credential_fortress_gate") and flags_in_file.has("door_if_gate_door_open") and flags_in_file.has("if_cache_approach_taken"),
			"the credential, the open door and the taken cache are in the file")
	_check(flags_in_file.has("iron_fortress_comms_pattern") and flags_in_file.has("iron_fortress_captain_down"), "the comms puzzle's first step and the Captain's defeat are in the file")

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
	var f2 := _content(main2)
	_check(_rm.current_region_id == &"iron_fortress" and f2 != null, "the game restarts inside the real Iron Fortress")
	if f2 == null:
		return
	var player2 := main2.get_node("Player") as Player
	_check(player2.global_position.distance_to(Vector3(2.0, 0.1, -30.0)) < 1.5, "the player is where they saved (%s)" % str(player2.global_position))
	_check(_world.has_flag(&"credential_fortress_gate"), "the gate credential is still held")
	_check((f2.parts.doors["if_gate_door"] as Door).is_open, "the main gate is still open")
	_check(_qm.is_active(&"if_last_stronghold") or _qm.is_completed(&"if_last_stronghold"), "the mission state came back")
	var stock_after := player2.inventory.count_of("bandage") + player2.inventory.count_of("armor_patch") + player2.inventory.count_of("credits_small")
	_check(not _use(f2, "if_cache_approach") and player2.inventory.count_of("bandage") + player2.inventory.count_of("armor_patch") + player2.inventory.count_of("credits_small") == stock_after,
			"the taken cache cannot be taken again")
	_check(stock_after >= items_before, "nothing was lost from the bag (%d, was %d)" % [stock_after, items_before])
	var spawn1 := f2.parts.fspawns["if_app_1"] as FortressSpawn
	_check(spawn1.is_cleared() and spawn1.trigger() == null, "the cleared guard does not come back")
	_check(not (f2.parts.fspawns["if_app_2"] as FortressSpawn).is_cleared(), "the guards that were not defeated are still to deal with")
	var captain_spawn := f2.parts.fspawns["if_captain"] as FortressSpawn
	_check(captain_spawn.is_cleared() and f2.release_captain() == null, "the Captain does not come back")
	await _frames(6)
	_check(_pickups("captain_insignia") == 1, "his reward is put back exactly once, not duplicated (%d)" % _pickups("captain_insignia"))
	# neither puzzle is soft-locked by the reload
	var c2 := f2.parts.puzzles["comms"] as LabPowerPuzzle
	_check(c2.is_step_done(&"pattern"), "the comms puzzle's first step survived the reload")
	c2.input(&"lever")
	_check(c2.is_completed() and _world.has_flag(&"iron_fortress_comms_done"), "the comms puzzle finishes with one switch")
	var l2 := f2.parts.puzzles["lockdown"] as ContainmentOverride
	_check(not l2.is_completed(), "the lockdown is still open after the reload")
	_use(f2, "if_lock_a")
	_use(f2, "if_lock_b")
	_use(f2, "if_lock_c")
	_check(l2.is_step_done(&"terminals"), "all three lockdown points can be disabled again")
	_use(f2, "if_lock_lever")
	_check(l2.is_completed() and _world.has_flag(&"iron_fortress_lockdown_done"), "and the lockdown comes off")
	_check(_world.has_flag(&"iron_fortress_control_open"), "with the Captain down, lifting the lockdown opens the control door")
	main2.queue_free()
	await _frames(4)
	_clean()


func _test_no_leaks() -> void:
	print("-- five round trips between the Research Complex and the Iron Fortress")
	var main := await _spawn_main()
	_world.set_flag(&"mission_first_signal_complete")
	for id in [&"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]:
		_rm.unlock(id)
	var route: Array = [[&"iron_fortress", &"from_research_complex"], [&"research_complex", &"from_iron_fortress"]]
	await _hop(&"research_complex", &"from_blackwood")
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
	_check(_rm.current_region_id == &"research_complex", "the cycles end in the Research Complex")
	main.queue_free()
	await _frames(4)
	_clean()
