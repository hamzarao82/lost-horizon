extends SceneTree
## Region framework checks (headless): godot --headless --path . -s tests/region_check.gd

var _failures: int = 0
var _checks: int = 0
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


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(6)
	return main


func _run() -> void:
	_rm = root.get_node_or_null("RegionManager")
	_world = root.get_node_or_null("WorldState")
	_check(_rm != null, "RegionManager autoload exists")
	# This suite tests the framework with the generic stub region; the real Research Complex has its own suites.
	RegionStore.load_data(&"research_complex").scene_path = "res://scenes/regions/StubRegion.tscn"
	_rm.reset()
	_test_data()
	var main := await _spawn_main()
	await _test_exits_and_locking(main)
	await _test_travel(main)
	await _test_walk_into_exit(main)
	await _test_no_leaks(main)
	await _test_persistent_ids()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("Region data")
	for id in RegionStore.IDS:
		var data := RegionStore.load_data(id)
		_check(data != null and data.id == id, "%s loads and carries its own id" % id)
		_check(data != null and data.display_name != "" and data.entry_points.size() >= 1, "%s has a name and an entry point" % id)
		if data != null and data.scene_path != "":
			_check(load(data.scene_path) is PackedScene, "%s scene path loads" % id)
		if data != null:
			for exit_id in data.exit_points:
				var target := StringName(str(data.exit_points[exit_id].get("target_region", "")))
				_check(RegionStore.is_known(target), "%s exit %s targets a known region" % [id, exit_id])
	_check(RegionStore.load_data(&"nowhere") == null, "an unknown region id returns null")
	_check(RegionData.new().entry_transform(&"x").origin.y > 0.0, "an empty region still has a safe entry transform")


func _test_exits_and_locking(main: Node) -> void:
	print("Outpost exits and locking")
	_check(_rm.current_region_id == &"outpost_17", "a fresh Main is region outpost_17")
	_check(main.get_node_or_null("Exit_to_dead_coast") is RegionExit, "Outpost 17 gets its exit to Dead Coast from region data")
	_check(not _rm.is_unlocked(&"dead_coast"), "Dead Coast starts locked")
	_check(not await _rm.travel(&"dead_coast", &"from_outpost"), "travel to a locked region is refused")
	_check(_rm.current_region_id == &"outpost_17", "refusal leaves the player where they were")
	_check(not await _rm.travel(&"nowhere"), "travel to an unknown region is refused")
	_check(not await _rm.travel(&"outpost_17"), "travel to the current region does nothing")
	_world.set_flag(&"mission_first_signal_complete")
	_check(_rm.is_unlocked(&"dead_coast"), "finishing the first mission unlocks Dead Coast through its flag")
	_check(not _rm.is_unlocked(&"blackwood"), "Blackwood stays locked")


func _test_travel(main: Node) -> void:
	print("Travel and state per region")
	var player := main.get_node("Player") as Player
	var seen: Array = []
	_rm.region_changed.connect(func(old: StringName, new: StringName) -> void: seen.append([old, new]))
	var outpost_node := main.get_node_or_null("Outpost17")
	_check(outpost_node != null, "Outpost17 node exists before leaving")
	_rm.unlock(&"research_complex")  # Dead Coast and Blackwood are real scenes now; the Research Complex is still the stub region
	_check(await _rm.travel(&"research_complex", &"from_blackwood"), "travel to the unlocked Research Complex succeeds")
	_check(_rm.current_region_id == &"research_complex", "current region is research_complex")
	_check(seen.size() == 1 and seen[0][0] == &"outpost_17" and seen[0][1] == &"research_complex", "region_changed fired once with old and new ids")
	_check(main.get_node_or_null("Outpost17") == null and not outpost_node.is_inside_tree(), "Outpost 17 is out of the tree while away")
	_check(main.get_node_or_null("Player") == player and is_instance_valid(main.get_node_or_null("Hud")), "player and HUD stay in Main")
	var entry := RegionStore.load_data(&"research_complex").entry_transform(&"from_blackwood").origin
	_check(player.global_position.distance_to(entry) < 0.5, "player stands at the arrival entry (%s)" % str(player.global_position))
	_check(main.get_node_or_null("Exit_to_blackwood") is RegionExit and main.get_node_or_null("Exit_to_dead_coast") == null,
			"the exits of the old region are replaced by the new region's")
	var stub := _find_stub(main)
	_check(stub != null and stub.visits == 1, "the stub region was entered once")
	_check(not await _rm.travel(&"blackwood"), "Blackwood is still locked from the Research Complex")
	_check(await _rm.travel(&"outpost_17", &"from_south"), "travel back to Outpost 17 succeeds")
	_check(main.get_node_or_null("Outpost17") == outpost_node and outpost_node.is_inside_tree(), "the same Outpost 17 nodes are back")
	_check(_find_stub(main) == null, "the stub region was freed on leaving")
	_check(await _rm.travel(&"research_complex", &"from_blackwood"), "second visit to the Research Complex")
	stub = _find_stub(main)
	_check(stub != null and stub.visits == 2, "its saved state came back: visit count 2 (got %s)" % str(stub.visits if stub else null))
	_check(await _rm.travel(&"outpost_17", &"start"), "back to Outpost 17 at the start entry")
	_check(not _rm.busy, "the manager is idle after travelling")
	_rm.reset()
	_world.reset()


func _test_walk_into_exit(main: Node) -> void:
	print("Walking into an exit")
	_rm.unlock(&"dead_coast")
	var player := main.get_node("Player") as Player
	var exit := main.get_node_or_null("Exit_to_dead_coast") as RegionExit
	_check(exit != null, "the exit exists")
	if exit == null:
		return
	player.global_position = exit.global_position
	var guard := 0
	while _rm.current_region_id != &"dead_coast" and guard < 120:
		await physics_frame
		guard += 1
	_check(_rm.current_region_id == &"dead_coast", "stepping into the exit area travels (%d frames)" % guard)
	var back := main.get_node_or_null("Exit_to_outpost_17") as RegionExit
	_check(back != null, "the real Dead Coast has a return exit")
	if back != null:
		player.global_position = back.global_position
		guard = 0
		while _rm.current_region_id != &"outpost_17" and guard < 120:
			await physics_frame
			guard += 1
		_check(_rm.current_region_id == &"outpost_17", "the return exit works (%d frames)" % guard)
	_rm.reset()


func _test_no_leaks(main: Node) -> void:
	print("No leaks across repeated travel")
	_rm.unlock(&"dead_coast")
	await _rm.travel(&"dead_coast", &"from_outpost")
	await _rm.travel(&"outpost_17", &"start")
	await _frames(4)
	var before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for i in 5:
		await _rm.travel(&"dead_coast", &"from_outpost")
		await _rm.travel(&"outpost_17", &"start")
		await _frames(2)
	await _frames(4)
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check(after == before, "node count is stable over 5 round trips (%d -> %d)" % [before, after])
	var children := main.get_children().size()
	await _rm.travel(&"dead_coast", &"from_outpost")
	await _rm.travel(&"outpost_17", &"start")
	await _frames(3)
	_check(main.get_children().size() == children, "Main has the same children after another round trip")
	_rm.reset()


func _test_persistent_ids() -> void:
	print("Persistent ids")
	_check(PersistentIds.claim(&"dead_coast", &"cache_01"), "first claim succeeds")
	_check(not PersistentIds.claim(&"dead_coast", &"cache_01"), "second claim is refused")
	_check(PersistentIds.claim(&"blackwood", &"cache_01"), "the same id in another region is separate")
	_check(PersistentIds.is_claimed(&"dead_coast", &"cache_01") and PersistentIds.count(&"dead_coast") == 1, "claimed state and count")
	_check(not PersistentIds.claim(&"nowhere", &"x"), "an unknown region cannot claim")
	_check(not PersistentIds.claim(&"dead_coast", &""), "an empty id cannot be claimed")
	RegionFlags.set_flag(&"dead_coast", &"checkpoint_found")
	_check(RegionFlags.has_flag(&"dead_coast", &"checkpoint_found") and not RegionFlags.has_flag(&"blackwood", &"checkpoint_found"),
			"region flags are namespaced")
	_check(_world.has_flag(&"dead_coast_checkpoint_found"), "the namespaced flag is a normal WorldState flag")
	# WorldState only keeps saved flags made of a-z, 0-9 and underscore (max 48): a dotted key would vanish on load.
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_world.from_dict(saved)
	_check(RegionFlags.has_flag(&"dead_coast", &"checkpoint_found"), "a region flag survives a WorldState save and load")
	_check(String(RegionFlags.key(&"research_complex", &"archive_terminal_unlocked")).length() <= 48, "long region flag keys stay within the 48 character limit")
	_rm.reset()
	_world.reset()


func _find_stub(main: Node) -> StubRegion:
	for child in main.get_children():
		if child is StubRegion:
			return child
	return null
