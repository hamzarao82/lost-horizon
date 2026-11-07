extends SceneTree
## The REAL Dead Coast and Blackwood reached through the real RegionManager (headless):
## godot --headless --path . -s tests/region_wiring_check.gd

var _failures: int = 0
var _checks: int = 0
var _rm: Node
var _world: Node
var _sm: Node
var _qm: Node


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


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(6)
	return main


func _region(main: Node) -> Region:
	for child in main.get_children():
		if child is DeadCoastRegion or child is BlackwoodRegion:
			return child as Region
	return null


func _hop(region_id: StringName, entry_id: StringName) -> bool:
	var ok: bool = await _rm.travel(region_id, entry_id, null, true)
	await _frames(3)
	return ok


func _run() -> void:
	_rm = root.get_node("RegionManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_qm = root.get_node("QuestManager")
	_clean()
	await _test_travel_and_exits()
	await _test_save_mid_region()
	await _test_no_leaks()
	_clean()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_travel_and_exits() -> void:
	print("Real travel, entry placement and exits")
	for id in [&"dead_coast", &"blackwood"]:
		var data := RegionStore.load_data(id)
		_check((data.scene_path != "" and not data.scene_path.ends_with("StubRegion.tscn")), "%s uses its real region scene (%s)" % [id, data.scene_path])
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	_check(not await _rm.travel(&"dead_coast", &"beach_arrival", null, true), "Dead Coast is locked at the start")
	_world.set_flag(&"mission_first_signal_complete")
	_check(await _hop(&"dead_coast", &"beach_arrival"), "travel to the real Dead Coast works")
	var coast := _region(main)
	_check(coast is DeadCoastRegion and coast.content != null, "the Dead Coast adapter holds the builder content")
	var arrival: Transform3D = coast.content.entry_points["beach_arrival"]
	_check(player.global_position.distance_to(arrival.origin) < 0.5, "the player stands at the builder's beach arrival point (%s)" % str(player.global_position))
	_check(main.get_node_or_null("DeadCoastRegion") != null and main.get_node_or_null("Outpost17") == null, "Outpost 17 is out of the tree while in Dead Coast")
	_check(main.get_node_or_null("Exit_to_outpost_17") is RegionExit, "Dead Coast has a real exit back to Outpost 17")
	var north := main.get_node_or_null("Exit_to_blackwood") as RegionExit
	_check(north != null and north.target_region == &"blackwood" and north.target_entry == &"from_dead_coast", "Dead Coast has an exit to Blackwood with the right entry id")
	_check(not _rm.is_unlocked(&"blackwood"), "the Blackwood exit is locked before Dead Coast mission 3")
	_check(not await _rm.travel(&"blackwood", &"from_dead_coast", null, true), "travel to Blackwood is refused while locked")
	_check(_qm.is_active(DeadCoast.FIRST_QUEST) or _qm.is_completed(DeadCoast.FIRST_QUEST), "entering Dead Coast started its first quest")
	CampaignFlow.mark_mission_complete(&"dead_coast", 3)
	_check(_rm.is_unlocked(&"blackwood"), "mission 3 unlocks Blackwood")
	_check(await _hop(&"blackwood", &"from_dead_coast"), "travel to the real Blackwood works")
	var wood := _region(main)
	_check(wood is BlackwoodRegion and wood.content != null and wood.content.is_built, "the Blackwood adapter holds the built content")
	var wood_arrival: Transform3D = wood.content.entry_points[&"from_dead_coast"]
	_check(player.global_position.distance_to(wood_arrival.origin) < 0.5, "the player stands at Blackwood's entry point (%s)" % str(player.global_position))
	_check(main.get_node_or_null("DeadCoastRegion") == null, "Dead Coast was freed on leaving")
	var back := main.get_node_or_null("Exit_to_dead_coast") as RegionExit
	_check(back != null and back.target_region == &"dead_coast" and back.target_entry == &"from_blackwood", "Blackwood has an exit back to Dead Coast")
	var forward := main.get_node_or_null("Exit_to_research_complex") as RegionExit
	_check(forward != null and not _rm.is_unlocked(&"research_complex"), "the Research Complex exit exists and is locked before Blackwood mission 3")
	CampaignFlow.mark_mission_complete(&"blackwood", 3)
	_check(_rm.is_unlocked(&"research_complex"), "Blackwood mission 3 unlocks the Research Complex")
	_check(await _hop(&"dead_coast", &"from_blackwood"), "the way back to Dead Coast works")
	var coast2 := _region(main)
	var from_wood: Transform3D = coast2.content.entry_points["from_blackwood"]
	_check(player.global_position.distance_to(from_wood.origin) < 0.5, "coming back from Blackwood lands at the north end of Dead Coast")
	_check(await _hop(&"outpost_17", &"from_south"), "and back to Outpost 17")
	_check(main.get_node_or_null("Outpost17") != null and main.get_node_or_null("DeadCoastRegion") == null, "Outpost 17 is back and Dead Coast is gone")
	main.queue_free()
	await _frames(4)
	_clean()


func _test_save_mid_region() -> void:
	print("A real save and load inside the real Blackwood")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	_world.set_flag(&"mission_first_signal_complete")
	CampaignFlow.mark_mission_complete(&"dead_coast", 3)
	await _hop(&"dead_coast", &"beach_arrival")
	_check(PersistentIds.claim(&"dead_coast", &"wiring_probe_cache"), "a Dead Coast claim is recorded")
	_world.set_flag(&"dead_coast_wiring_probe")
	await _hop(&"blackwood", &"from_dead_coast")
	var probe_pos := Vector3(-3.0, 0.1, -20.0)
	player.global_position = probe_pos
	await _frames(3)
	_check(_sm.save_game("manual"), "saving inside Blackwood works")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(raw is Dictionary and raw["regions"]["current"] == "blackwood", "the file records Blackwood as the current region")
	_check(raw["regions"]["states"].has("dead_coast"), "Dead Coast's state was saved when the player left it")
	main.queue_free()
	await _frames(4)
	_rm.reset()
	_world.reset()
	_check(_sm.load_game(), "loading the save succeeds")
	var main2 := await _spawn_main()
	await _frames(14)
	_check(_rm.current_region_id == &"blackwood" and _region(main2) is BlackwoodRegion, "the game restarts inside the real Blackwood")
	var player2 := main2.get_node("Player") as Player
	_check(player2.global_position.distance_to(probe_pos) < 1.0, "the player is where they saved (%s)" % str(player2.global_position))
	_check(_rm.is_unlocked(&"blackwood") and _world.has_flag(&"dead_coast_wiring_probe"), "unlocks and world flags came back")
	_check(PersistentIds.is_claimed(&"dead_coast", &"wiring_probe_cache"), "the Dead Coast claim came back (no repeat reward)")
	_check(not PersistentIds.claim(&"dead_coast", &"wiring_probe_cache"), "claiming it again is refused")
	_check(await _hop(&"dead_coast", &"from_blackwood"), "Dead Coast is reachable after loading")
	_check(_qm.is_active(DeadCoast.FIRST_QUEST) or _qm.is_completed(DeadCoast.FIRST_QUEST), "its quest data was registered after the load")
	main2.queue_free()
	await _frames(4)
	_clean()


func _test_no_leaks() -> void:
	print("Five round trips: leaks and travel time")
	var main := await _spawn_main()
	_world.set_flag(&"mission_first_signal_complete")
	CampaignFlow.mark_mission_complete(&"dead_coast", 3)
	var route: Array = [[&"dead_coast", &"beach_arrival"], [&"blackwood", &"from_dead_coast"],
			[&"dead_coast", &"from_blackwood"], [&"outpost_17", &"from_south"]]
	for hop in route:  # one warm-up cycle so caches are filled before the baseline
		await _hop(hop[0], hop[1])
	await _frames(10)
	var base_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var base_mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var worst_ms := 0
	var times: Dictionary = {}
	for round in 5:
		for hop in route:
			var t0 := Time.get_ticks_msec()
			var ok: bool = await _hop(hop[0], hop[1])
			var dt := Time.get_ticks_msec() - t0
			times[String(hop[0])] = maxi(int(times.get(String(hop[0]), 0)), dt)
			worst_ms = maxi(worst_ms, dt)
			if not ok:
				_check(false, "round %d hop to %s worked" % [round, hop[0]])
	await _frames(20)
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	_check(_rm.current_region_id == &"outpost_17", "five cycles end back in Outpost 17")
	_check(abs(nodes - base_nodes) <= 40, "node count returns to baseline (%d now, %d before)" % [nodes, base_nodes])
	_check(mem - base_mem < 40.0, "static memory does not climb (%.1f MB now, %.1f MB before)" % [mem, base_mem])
	print("  info slowest hop per region (ms, includes the first-frame builds): ", times)
	var draw := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("  info draw calls this frame (headless renders none): ", draw)
	main.queue_free()
	await _frames(4)
	_clean()
