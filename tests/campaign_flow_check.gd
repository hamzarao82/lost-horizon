extends SceneTree
## Campaign flow between regions (headless): godot --headless --path . -s tests/campaign_flow_check.gd
## Uses the stub regions and the real QuestManager, WorldState, RegionManager and Progression.

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
var _captions: Array[String] = []


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


func _fresh() -> void:
	_sm.reset_runtime_state()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	_qm.tracker_first = &""
	_captions.clear()


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)  # CampaignFlow syncs 2 and 40 frames after Main appears
	return main


func _free_main(main: Node) -> void:
	main.queue_free()
	await _frames(4)
	_rm.reset()


## The whole First Signal through events, exactly like tests/mission_check.gd.
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


func _gates(main: Node) -> int:
	var count := 0
	for child in main.get_children():
		if child.name == &"CampaignGate" or String(child.name).begins_with("CampaignGate"):
			count += 1
	return count


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_rm = root.get_node("RegionManager")
	_prog = root.get_node("Progression")
	_qm.caption_requested.connect(func(text: String, _seconds: float) -> void: _captions.append(text))
	await _frames(3)
	_test_contract()
	_test_flag_persistence()
	await _test_locked_state()
	await _test_unlock_and_bridge()
	await _test_travel_rewards_and_returns()
	await _test_gate_not_duplicated()
	_test_chain()
	await _test_no_softlock()
	_fresh()
	_qm.mission_autosave = true
	_sm.reset_runtime_state()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_contract() -> void:
	print("Flag contract and data")
	_check(CampaignFlow.mission_flag(&"dead_coast", 3) == &"dead_coast_mission_3_complete", "mission flag name: dead_coast_mission_3_complete")
	_check(CampaignFlow.mission_flag(&"blackwood", 3) == &"blackwood_mission_3_complete", "mission flag name: blackwood_mission_3_complete")
	_check(CampaignFlow.unlock_flag(&"research_complex") == &"research_complex_unlocked", "unlock flag name: research_complex_unlocked")
	for id in [&"dead_coast", &"blackwood", &"research_complex"]:
		var data := RegionStore.load_data(id)
		_check(data != null and data.unlock_flag == CampaignFlow.unlock_flag(id), "%s unlocks through %s" % [id, CampaignFlow.unlock_flag(id)])
	var dead_coast := RegionStore.load_data(&"dead_coast")
	_check(dead_coast.entry_points.has(&"beach_arrival"), "Dead Coast has the beach_arrival entry the gate travels to")
	var bridge := _qm.get_quest(BRIDGE) as QuestData
	_check(bridge != null and bridge.validate().is_empty(), "the bridge quest is registered from resources/quests/campaign/ and validates")
	_check(bridge != null and bridge.prerequisites.has("first_signal"), "the bridge quest requires The First Signal")
	_check(bridge != null and bridge.objectives[0].text == "Follow the signal to the Dead Coast", "the objective text")
	var files: PackedStringArray = _qm.quest_files_in("res://resources/quests/campaign/")
	_check(files.has("res://resources/quests/campaign/leave_outpost.tres"), "the folder scan finds the bridge quest")
	_check(_qm.quest_files_in("res://resources/quests/no_such_region/").is_empty(), "a missing region folder gives an empty list, no error")
	_check(CampaignFlow.refusal_text(&"dead_coast") == "The road is blocked.", "the locked Dead Coast text is 'The road is blocked.'")
	_check(CampaignFlow.refusal_text(&"somewhere") == "", "unknown regions fall back to the generic refusal")


func _test_flag_persistence() -> void:
	print("Every flag the campaign uses survives WorldState.to_dict / from_dict")
	_fresh()
	var regions: Array[StringName] = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex"]
	var ids: Array[StringName] = [&"mission_first_signal_complete", &"dead_coast_arrived"]
	for region in regions:
		ids.append(CampaignFlow.unlock_flag(region))
		for n in [1, 2, 3]:
			ids.append(CampaignFlow.mission_flag(region, n))
		ids.append(StringName("%s_region_complete" % region))
		ids.append(StringName(CampaignFlow.SAID_PREFIX + String(region)))
	var longest := 0
	var all_plain := true
	for id in ids:
		longest = maxi(longest, String(id).length())
		for i in String(id).length():
			var c := String(id).unicode_at(i)
			if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
				all_plain = false
	_check(all_plain, "all %d campaign flag ids use only a-z, 0-9 and underscore" % ids.size())
	_check(longest <= 48, "the longest id is %d characters (limit 48)" % longest)
	for id in ids:
		_world.set_flag(id, true)
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_check(not _world.has_flag(&"dead_coast_unlocked"), "reset clears them")
	_world.from_dict(saved)
	var lost: Array[String] = []
	for id in ids:
		if not _world.has_flag(id):
			lost.append(String(id))
	_check(lost.is_empty(), "none is lost through the real round trip %s" % str(lost))
	_fresh()


func _test_locked_state() -> void:
	print("Before the first mission ends")
	_fresh()
	var main := await _spawn_main()
	_check(not _rm.is_unlocked(&"dead_coast"), "Dead Coast is locked")
	_check(_gates(main) == 1, "the road gate stands on the beach (%d)" % _gates(main))
	var gate := main.get_node_or_null("CampaignGate") as Node3D
	_check(gate != null and gate.global_position.z > 79.0 and absf(gate.global_position.x) < 1.0, "it sits beyond the exit trigger at the south end of the beach")
	_captions.clear()
	_check(not await _rm.travel(&"dead_coast", &"beach_arrival"), "travel is refused")
	_check(_captions.has("The road is blocked."), "the player is told 'The road is blocked.' (%s)" % str(_captions))
	_check(_rm.current_region_id == &"outpost_17", "the player stays in Outpost 17")
	_check(not _qm.is_active(BRIDGE) and _qm.tracker_first == &"", "the bridge quest has not started")
	await _free_main(main)


func _test_unlock_and_bridge() -> void:
	print("Unlock and bridge quest")
	_fresh()
	var main := await _spawn_main()
	var started: Array = []
	_qm.quest_started.connect(func(id: StringName) -> void: started.append(id))
	_complete_first_signal()
	await _frames(3)
	_check(_qm.is_completed(FIRST), "The First Signal completed through events")
	_check(_world.has_flag(&"dead_coast_unlocked"), "that sets dead_coast_unlocked")
	_check(_rm.is_unlocked(&"dead_coast"), "Dead Coast is unlocked")
	_check(_qm.is_active(BRIDGE) and started.count(BRIDGE) == 1, "the bridge quest started exactly once")
	_check(_qm.is_active(&"restore_power"), "the older chained quest is also active (restore_power)")
	_check(_qm.tracker_title() == "The Road South", "the tracker shows the bridge quest first (%s)" % _qm.tracker_title())
	_check(_qm.tracker_objective() == "Follow the signal to the Dead Coast", "the tracker objective is 'Follow the signal to the Dead Coast'")
	await _frames(2)
	_check(_gates(main) == 0, "the road gate is removed once the road is open")
	await get_create_timer_wait(6.5)
	var unlock_lines := _captions.filter(func(t: String) -> bool: return t.contains("The road is open"))
	_check(unlock_lines.size() == 1, "the hand-off line is said once (%d: %s)" % [unlock_lines.size(), str(unlock_lines)])
	_complete_first_signal()
	_world.set_flag(&"mission_first_signal_complete", true)
	await _frames(3)
	_check(started.count(BRIDGE) == 1, "repeating the events does not restart the bridge quest")
	await _free_main(main)


func get_create_timer_wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _test_travel_rewards_and_returns() -> void:
	print("Travel, reward once, return")
	_fresh()
	var main := await _spawn_main()
	_complete_first_signal()
	await _frames(3)
	var xp_events: Array = []
	var on_xp := func(amount: int, source: String) -> void: xp_events.append([amount, source])
	_prog.xp_gained.connect(on_xp)
	_captions.clear()
	_check(await _rm.travel(&"dead_coast", &"beach_arrival"), "travel to Dead Coast works through the beach_arrival entry")
	await _frames(3)
	_check(_world.has_flag(&"dead_coast_arrived"), "arriving sets dead_coast_arrived")
	_check(_qm.is_completed(BRIDGE), "the bridge quest completes")
	var quest_xp: int = 0
	for event in xp_events:
		if event[1] == "quest":
			quest_xp += int(event[0])
	_check(quest_xp == 60, "it pays its small XP once (%d)" % quest_xp)
	_check(_qm.tracker_first == &"", "the tracker pin is released")
	var arrival_lines := _captions.filter(func(t: String) -> bool: return t.contains("Wreckage everywhere"))
	_check(arrival_lines.size() == 1, "the Dead Coast arrival line is said once")
	_check(await _rm.travel(&"outpost_17", &"from_south"), "the way back to Outpost 17 is open")
	_check(await _rm.travel(&"dead_coast", &"beach_arrival"), "and Dead Coast can be revisited")
	await _frames(3)
	var again := 0
	for event in xp_events:
		if event[1] == "quest":
			again += int(event[0])
	_check(again == 60, "a revisit pays no more XP (%d)" % again)
	arrival_lines = _captions.filter(func(t: String) -> bool: return t.contains("Wreckage everywhere"))
	_check(arrival_lines.size() == 1, "the arrival line is not repeated on a revisit")
	_prog.xp_gained.disconnect(on_xp)
	_check(await _rm.travel(&"outpost_17", &"from_south"), "back in Outpost 17")
	_check(_qm.is_completed(FIRST) and _qm.is_completed(BRIDGE), "completed quests stay completed on return")
	_check(_world.has_flag(&"boss_warden_defeated") and get_nodes_in_group("boss").filter(func(n: Node) -> bool: return not (n as Enemy).is_dead()).is_empty(), "no living Warden after the return")
	await _free_main(main)


func _test_gate_not_duplicated() -> void:
	print("The gate is built once")
	_fresh()
	var main := await _spawn_main()
	_check(_gates(main) == 1, "one gate at the start")
	_rm.unlock(&"dead_coast")  # allowed through the manager only: the flag-driven gate stays
	_check(await _rm.travel(&"dead_coast", &"beach_arrival"), "travelled out")
	await _frames(3)
	var stray := 0
	for child in main.get_children():
		if String(child.name).begins_with("CampaignGate"):
			stray += 1
	_check(stray == 0, "no gate is built inside the other region (%d)" % stray)
	_check(await _rm.travel(&"outpost_17", &"from_south"), "travelled back")
	await _frames(3)
	_check(_gates(main) == 1, "still exactly one gate after a round trip (%d)" % _gates(main))
	await _free_main(main)


func _test_chain() -> void:
	print("Unlock chain")
	_fresh()
	_check(not _world.has_flag(&"blackwood_unlocked"), "Blackwood starts locked")
	_check(CampaignFlow.mark_mission_complete(&"dead_coast", 1), "mission 1 of Dead Coast marks once")
	_check(not CampaignFlow.mark_mission_complete(&"dead_coast", 1), "marking it again returns false")
	CampaignFlow.mark_mission_complete(&"dead_coast", 2)
	_check(not _world.has_flag(&"blackwood_unlocked"), "missions 1 and 2 do not unlock Blackwood")
	_check(CampaignFlow.mark_mission_complete(&"dead_coast", 3), "mission 3 of Dead Coast marks")
	_check(_world.has_flag(&"blackwood_unlocked") and _rm.is_unlocked(&"blackwood"), "mission 3 unlocks Blackwood")
	_check(not _world.has_flag(&"research_complex_unlocked"), "the Research Complex stays locked")
	_check(CampaignFlow.mark_mission_complete(&"blackwood", 3), "mission 3 of Blackwood marks")
	_check(_world.has_flag(&"research_complex_unlocked") and _rm.is_unlocked(&"research_complex"), "it unlocks the Research Complex")
	_check(not CampaignFlow.mark_mission_complete(&"blackwood", 0), "mission numbers below 1 are ignored")
	_fresh()
	_world.set_flag(&"dead_coast_region_complete", true)
	_check(_world.has_flag(&"blackwood_unlocked"), "the region_complete alias also unlocks the next region")


func _test_no_softlock() -> void:
	print("No softlock across regions")
	_fresh()
	_world.set_flag(&"dead_coast_arrived", true)  # visited before the quest existed (an older save)
	var main := await _spawn_main()
	_complete_first_signal()
	await _frames(3)
	_check(_qm.is_completed(BRIDGE), "a player who already stood in Dead Coast does not have to go back (history replay)")
	await _free_main(main)
	_fresh()
	main = await _spawn_main()
	_rm.unlock(&"dead_coast")
	_qm.notify(OBJ.ENTER_AREA, &"area_a_perimeter")
	_check(await _rm.travel(&"dead_coast", &"beach_arrival"), "leave mid-mission")
	_qm.notify(OBJ.INTERACT, &"checkpoint_desk")  # an event arrives while away
	_check(await _rm.travel(&"outpost_17", &"from_south"), "come back")
	var done: Array = _qm.active[FIRST]["done"]
	_check(done[0] and done[1], "objectives completed before and during the absence both count")
	_check(_qm.is_active(FIRST), "the mission is still open")
	await _free_main(main)
