extends SceneTree
## Stage sequence: the later regions run step by step, and the tracker and arrow only speak about the
## current stage. godot --headless --path . -s tests/stage_sequence_check.gd

const OBJ := ObjectiveData.Type
const WRECK: StringName = &"dc_wreckage"
var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _rm: Node
var _sm: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _fresh(region: StringName) -> void:
	_sm.reset_runtime_state()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	_qm.active.clear()
	_qm.completed.clear()
	_qm.tracker_first = &""
	_rm.current_region_id = region


## Starts a quest the way start_quest does, without prerequisites (used to seed other regions' quests).
func _seed_active(quest_id: StringName) -> void:
	var quest: QuestData = _qm.get_quest(quest_id)
	var progress: Array = []
	var seen: Array = []
	var done: Array = []
	for objective in quest.objectives:
		progress.append(0)
		seen.append([])
		done.append(false)
	_qm.active[quest_id] = {"progress": progress, "seen": seen, "done": done}


func _index_of(quest_id: StringName, objective_id: StringName) -> int:
	var quest: QuestData = _qm.get_quest(quest_id)
	for index in quest.objectives.size():
		if quest.objectives[index].id == objective_id:
			return index
	return -1


func _done(quest_id: StringName, objective_id: StringName) -> bool:
	return _qm.active.has(quest_id) and bool(_qm.active[quest_id]["done"][_index_of(quest_id, objective_id)])


func _play_in_order() -> void:
	_qm.notify(OBJ.ENTER_AREA, &"dc_wreckage_beach")
	_qm.notify(OBJ.INTERACT, &"dead_coast_wreck_hull")
	_qm.notify(OBJ.INTERACT, &"dead_coast_radio_wreck")
	_qm.notify(OBJ.INTERACT, &"dead_coast_log_wreck_manifest")
	_qm.notify(OBJ.FLAG, &"patrol_dead_coast_beach_cleared")
	_qm.notify(OBJ.INTERACT, &"dead_coast_data_device")


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_rm = root.get_node("RegionManager")
	_sm = root.get_node("SaveManager")
	await physics_frame
	_sm.delete_save()

	print("strictness")
	_check(not _qm.is_strict(&"first_signal") and not _qm.is_strict(&"restore_power"), "Outpost 17 quests keep their free order")
	for quest_id in [&"dc_wreckage", &"into_the_blackwood", &"rc_restricted_zone", &"if_last_stronghold"]:
		_check(_qm.is_strict(quest_id), "%s is strict" % quest_id)

	print("one step at a time")
	_fresh(&"dead_coast")
	_check(_qm.start_quest(WRECK), "Dead Coast mission 1 starts")
	_check(_qm.tracker_title() == "Wreckage", "the tracker shows the stage's mission (%s)" % _qm.tracker_title())
	_check(_qm.tracker_objective() == "Enter the Dead Coast", "and only the first step (%s)" % _qm.tracker_objective())
	var line: String = _qm.tracker_stage_line()
	_check(line.begins_with("Dead Coast: step 1 of "), "the stage line says step 1 (%s)" % line)

	print("early events are remembered, not lost")
	_qm.notify(OBJ.INTERACT, &"dead_coast_radio_wreck")
	_check(not _done(WRECK, &"find_comm_equipment"), "an event before its turn does nothing visible")
	_check(_qm.tracker_objective() == "Enter the Dead Coast", "the current step is unchanged")
	_qm.notify(OBJ.ENTER_AREA, &"dc_wreckage_beach")
	_check(_done(WRECK, &"enter_dead_coast") and _qm.tracker_objective() == "Investigate the freighter wreckage", "step 1 done: step 2 is current")
	_check(not _done(WRECK, &"find_comm_equipment"), "the remembered radio event waits for its own turn")
	_qm.notify(OBJ.INTERACT, &"dead_coast_wreck_hull")
	_check(_done(WRECK, &"investigate_wreckage") and _done(WRECK, &"find_comm_equipment"), "after the hull, the remembered radio event is applied in order")
	_check(_qm.tracker_objective() == "Find evidence of a military shipment", "and the next step is current (%s)" % _qm.tracker_objective())
	_check(_qm.tracker_stage_line().begins_with("Dead Coast: step 4 of "), "the stage line follows (%s)" % _qm.tracker_stage_line())

	print("no soft lock: a whole mission in reverse order")
	_fresh(&"dead_coast")
	_qm.start_quest(WRECK)
	_qm.notify(OBJ.INTERACT, &"dead_coast_data_device")
	_qm.notify(OBJ.FLAG, &"patrol_dead_coast_beach_cleared")
	_qm.notify(OBJ.INTERACT, &"dead_coast_log_wreck_manifest")
	_qm.notify(OBJ.INTERACT, &"dead_coast_radio_wreck")
	_qm.notify(OBJ.INTERACT, &"dead_coast_wreck_hull")
	_check(not _qm.is_completed(WRECK), "nothing completes before the first step")
	_qm.notify(OBJ.ENTER_AREA, &"dc_wreckage_beach")
	_check(_qm.is_completed(WRECK), "the first step releases the whole remembered chain and the mission finishes")
	_check(_qm.is_active(&"dc_silent_checkpoint"), "the next mission starts")
	var after: String = _qm.tracker_stage_line()
	_check(after.begins_with("Dead Coast: step 7 of ") or after.begins_with("Dead Coast: step 6 of "), "after mission 1 the line moves on (%s)" % after)

	print("optional objectives never block")
	_fresh(&"dead_coast")
	_qm.start_quest(WRECK)
	_play_in_order()
	_check(_qm.is_completed(WRECK), "the required steps in order finish the mission without the optional cache")

	print("other stages never show")
	_fresh(&"dead_coast")
	_qm.start_quest(WRECK)
	for other in [&"first_signal", &"restore_power", &"broken_perimeter", &"final_transmission", &"leave_outpost"]:
		_seed_active(other)
	_qm.tracker_first = &"leave_outpost"
	_check(_qm.tracker_title() == "Wreckage", "in Dead Coast the tracker ignores Outpost 17 quests and the bridge (%s)" % _qm.tracker_title())
	var pointer := ObjectivePointer.new()
	root.add_child(pointer)
	var current: ObjectiveData = pointer.current_objective()
	_check(current != null and current.id == &"enter_dead_coast", "the arrow aims at the current Dead Coast step only")
	_rm.current_region_id = &"blackwood"
	_check(_qm.tracker_title() == "" and _qm.tracker_objective() == "", "in Blackwood, with no Blackwood quest active, the tracker is empty")
	_check(pointer.current_objective() == null, "and the arrow shows nothing instead of pointing at another stage")
	_rm.current_region_id = &"outpost_17"
	_check(_qm.tracker_title() == "The Road South", "back in Outpost 17 the pinned bridge quest shows first (%s)" % _qm.tracker_title())
	_check(_qm.tracker_stage_line() == "", "Outpost 17 has no stage line")
	pointer.queue_free()

	print("Outpost 17 keeps its free order")
	_fresh(&"outpost_17")
	_qm.start_quest(&"first_signal")
	_qm.notify(OBJ.INTERACT, &"radio")
	var radio_done := false
	var quest: QuestData = _qm.get_quest(&"first_signal")
	for index in quest.objectives.size():
		if quest.objectives[index].targets.has("radio") and _qm.active[&"first_signal"]["done"][index]:
			radio_done = true
	_check(radio_done, "the radio objective counts at once, before the earlier steps, in Outpost 17")

	print("labels")
	_check(ObjectivePointer.short_label(&"dead_coast_wreck_hull") == "Wreck Hull", "region prefix dropped (%s)" % ObjectivePointer.short_label(&"dead_coast_wreck_hull"))
	_check(ObjectivePointer.short_label(&"dead_coast_log_wreck_manifest") == "Wreck Manifest", "and a leading log (%s)" % ObjectivePointer.short_label(&"dead_coast_log_wreck_manifest"))
	_check(ObjectivePointer.short_label(&"rc_archive_terminal") == "Archive Terminal", "short prefixes too (%s)" % ObjectivePointer.short_label(&"rc_archive_terminal"))
	_check(ObjectivePointer.short_label(&"checkpoint_desk") == "Checkpoint Desk", "Outpost ids are unchanged")

	_fresh(&"outpost_17")
	_sm.delete_save()
	print("stage_sequence_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
