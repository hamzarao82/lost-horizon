extends SceneTree
## Campaign bot (headless): godot --headless --path . -s tests/campaign_bot_check.gd
## Plays Outpost 17 -> Dead Coast -> Blackwood -> Research Complex gate with the stub regions: the First
## Signal through events, then real walking into the exit areas, a save in the middle and a reload.
## Uses SaveManager's per-process test file, never the real save.

const OBJ := ObjectiveData.Type
const FIRST: StringName = &"first_signal"
const BRIDGE: StringName = &"leave_outpost"

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _sm: Node
var _rm: Node
var _prog: Node


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
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	_qm.tracker_first = &""


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	return main


func _complete_first_signal() -> void:
	_qm.notify(OBJ.ENTER_AREA, &"area_a_perimeter")
	_qm.notify(OBJ.INTERACT, &"checkpoint_desk")
	_qm.notify(OBJ.INTERACT, &"radio")
	for i in 4:
		_qm.notify(OBJ.KILL_COUNT, &"Soldier", 1, 7000 + i)
	_qm.notify(OBJ.FLAG, &"has_access_card")
	_qm.notify(OBJ.FLAG, &"comms_power_on")
	_qm.notify(OBJ.INTERACT, &"military_terminal")
	_qm.notify(OBJ.ENTER_AREA, &"area_c_research")
	_qm.notify(OBJ.FLAG, &"next_location_unlocked")
	_qm.notify(OBJ.ENTER_AREA, &"area_d_command")
	_world.set_flag(&"patrol_d_guards_cleared", true)
	_world.emit_interacted(&"log_project_black_site")
	_world.set_flag(&"boss_warden_defeated", true)
	_qm.notify(OBJ.ITEM_COLLECTED, &"warden_blade")
	_world.emit_interacted(&"command_terminal_d")


## Walks the player into the named exit area of the current region and waits for the travel to finish.
func _walk_through(main: Node, exit_name: String, target: StringName) -> bool:
	var exit := main.get_node_or_null(exit_name) as RegionExit
	if exit == null:
		return false
	var player := main.get_node("Player") as Player
	player.global_position = exit.global_position
	var guard := 0
	while _rm.current_region_id != target and guard < 160:
		await physics_frame
		guard += 1
	await _frames(3)
	return _rm.current_region_id == target


func _total_xp() -> int:
	return int(_prog.progress.xp) + 1000000 * int(_prog.progress.level())


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_rm = root.get_node("RegionManager")
	_prog = root.get_node("Progression")
	await _frames(3)
	_clean()
	await _play_campaign()
	_clean()
	_qm.mission_autosave = true
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _play_campaign() -> void:
	print("Outpost 17: the road is shut until the mission ends")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var exit := main.get_node_or_null("Exit_to_dead_coast") as RegionExit
	_check(exit != null, "the south exit exists on the beach")
	player.global_position = exit.global_position if exit else Vector3(0.0, 0.1, 78.0)
	await _frames(20)
	_check(_rm.current_region_id == &"outpost_17", "walking into it before the mission ends keeps the player here")
	player.global_position = Vector3(0.0, 0.1, 40.0)
	await _frames(2)

	print("Finish The First Signal")
	_complete_first_signal()
	await _frames(3)
	_check(_qm.is_completed(FIRST) and _qm.is_active(BRIDGE), "the mission is done and the bridge quest is active")
	var xp_after_mission := _total_xp()

	print("Walk to Dead Coast")
	_check(await _walk_through(main, "Exit_to_dead_coast", &"dead_coast"), "walking into the beach exit travels to Dead Coast")
	_check(_qm.is_completed(BRIDGE), "arriving completes the bridge quest")
	var xp_in_coast := _total_xp()
	_check(xp_in_coast > xp_after_mission, "the bridge reward arrived")
	_check(CampaignFlow.mark_mission_complete(&"dead_coast", 1) and CampaignFlow.mark_mission_complete(&"dead_coast", 2), "Dead Coast missions 1 and 2 are marked")
	_check(not _rm.is_unlocked(&"blackwood"), "Blackwood is still locked after two missions")
	var exit_locked := main.get_node_or_null("Exit_to_blackwood") as RegionExit
	player = main.get_node("Player") as Player
	player.global_position = exit_locked.global_position if exit_locked else Vector3.ZERO
	await _frames(20)
	_check(_rm.current_region_id == &"dead_coast", "walking into the Blackwood exit is refused while it is locked")
	player.global_position = Vector3(0.0, 0.1, 0.0)
	await _frames(2)
	CampaignFlow.mark_mission_complete(&"dead_coast", 3)
	await _frames(2)
	_check(_rm.is_unlocked(&"blackwood"), "mission 3 unlocks Blackwood")

	print("Walk to Blackwood")
	_check(await _walk_through(main, "Exit_to_blackwood", &"blackwood"), "walking into the exit travels to Blackwood")
	_check(not _rm.is_unlocked(&"research_complex"), "the Research Complex is still locked")
	CampaignFlow.mark_mission_complete(&"blackwood", 3)
	await _frames(2)
	_check(_rm.is_unlocked(&"research_complex"), "Blackwood mission 3 makes the Research Complex accessible")

	print("Save in Blackwood and reload")
	player = main.get_node("Player") as Player
	player.global_position = Vector3(4.0, 0.1, 10.0)
	await _frames(3)
	var xp_before_save := _total_xp()
	var flags_before := {
		"dead_coast.unlocked": _world.has_flag(&"dead_coast.unlocked"),
		"blackwood.unlocked": _world.has_flag(&"blackwood.unlocked"),
		"research_complex.unlocked": _world.has_flag(&"research_complex.unlocked"),
		"dead_coast.arrived": _world.has_flag(&"dead_coast.arrived"),
	}
	_check(_sm.save_game("manual"), "saved in Blackwood")
	main.queue_free()
	await _frames(4)
	_rm.reset()
	_world.reset()
	_qm.reset()
	_check(_sm.load_game(), "the save loads")
	var main2 := await _spawn_main()
	await _frames(14)
	_check(_rm.current_region_id == &"blackwood", "the game restarts in Blackwood")
	var player2 := main2.get_node("Player") as Player
	_check(player2.global_position.distance_to(Vector3(4.0, 0.1, 10.0)) < 1.0, "at the saved position (%s)" % str(player2.global_position))
	for flag in flags_before:
		_check(_world.has_flag(StringName(flag)) == flags_before[flag] and flags_before[flag], "%s survived the reload" % flag)
	_check(_qm.is_completed(FIRST) and _qm.is_completed(BRIDGE), "both quests are still completed")
	_check(_total_xp() == xp_before_save, "XP is unchanged by the reload (%d)" % _total_xp())
	_check(_qm._rewarded.count(FIRST) == 1 and _qm._rewarded.count(BRIDGE) == 1, "rewards are recorded once")
	_check(_rm.is_unlocked(&"dead_coast") and _rm.is_unlocked(&"blackwood") and _rm.is_unlocked(&"research_complex"), "all three regions are open after the reload")

	print("Back through the chain after the reload")
	_check(await _rm.travel(&"dead_coast", &"from_blackwood"), "Dead Coast is reachable again")
	var xp_revisit := _total_xp()
	_check(await _rm.travel(&"outpost_17", &"from_south"), "and Outpost 17")
	_check(_total_xp() == xp_revisit, "revisiting pays nothing again")
	var living_wardens := get_nodes_in_group("boss").filter(func(n: Node) -> bool: return not (n as Enemy).is_dead())
	_check(living_wardens.is_empty(), "no Warden is alive in the rebuilt Outpost 17")
	main2.queue_free()
	await _frames(4)
	_rm.reset()
