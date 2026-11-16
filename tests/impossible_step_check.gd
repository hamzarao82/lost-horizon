extends SceneTree
## Impossible required steps after a load (docs/MISSION_RULES.md rule 6), headless:
##   godot --headless --path . -s tests/impossible_step_check.gd
## Seeded saved states: a step is credited ONLY when persistent state proves it done; every other step is left alone.

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _objective(id: StringName, type: ObjectiveData.Type, targets: Array, count: int = 0) -> ObjectiveData:
	var o := ObjectiveData.new()
	o.id = id
	o.text = "step %s" % id
	o.type = type
	o.targets = PackedStringArray(targets)
	o.count = count
	return o


func _quest(id: StringName, objectives: Array[ObjectiveData], strict: bool = false) -> void:
	var q := QuestData.new()
	q.id = id
	q.title = "Test %s" % id
	q.objectives = objectives
	q.strict_order = strict
	_qm.quests[id] = q


func _fresh() -> void:
	_qm.reset()
	_world.reset()


func _done(quest_id: StringName, index: int) -> bool:
	return bool(_qm.active[quest_id]["done"][index])


func _run() -> void:
	_qm = root.get_node_or_null("QuestManager")
	_world = root.get_node_or_null("WorldState")
	await process_frame
	await process_frame
	_check(_qm != null and _world != null, "QuestManager and WorldState exist")
	if _qm == null or _world == null:
		quit(1)
		return

	_quest(&"i_item", [
		_objective(&"stick", ObjectiveData.Type.ITEM_COLLECTED, ["wooden_stick"]),
		_objective(&"gone", ObjectiveData.Type.ITEM_COLLECTED, ["no_such_item_zzz"]),
	])
	_quest(&"i_kill", [
		_objective(&"warden", ObjectiveData.Type.KILL_COUNT, ["The Warden"], 1),
		_objective(&"guard", ObjectiveData.Type.KILL_COUNT, ["Ghost Guard"], 1),
	])
	_quest(&"i_kill2", [
		_objective(&"warden_twice", ObjectiveData.Type.KILL_COUNT, ["The Warden"], 2),
	])
	_quest(&"i_strict", [
		_objective(&"first", ObjectiveData.Type.FLAG, ["i_strict_flag"]),
		_objective(&"later", ObjectiveData.Type.ITEM_COLLECTED, ["wooden_stick"]),
	], true)

	var item_key := "%d:wooden_stick" % int(ObjectiveData.Type.ITEM_COLLECTED)

	# --- items: credited only when the saved history records the item as collected ---
	_fresh()
	_qm.start_quest(&"i_item", true)
	_qm._history[item_key] = true
	var credited: int = _qm.reconcile_impossible()
	_check(_done(&"i_item", 0), "a proven-collected item step is credited")
	_check(not _done(&"i_item", 1), "an item step with no record and no item resource is left alone")
	_check(credited >= 1, "the call reports what it credited (%d)" % credited)

	_fresh()
	_qm.start_quest(&"i_item", true)
	credited = _qm.reconcile_impossible()
	_check(not _done(&"i_item", 0) and not _done(&"i_item", 1), "with no saved proof nothing is credited")
	_check(credited == 0, "and the call reports zero (%d)" % credited)

	# --- kills: credited only when the saved world marks every named boss defeated ---
	_fresh()
	_qm.start_quest(&"i_kill", true)
	_world.set_flag(&"boss_warden_defeated", true)
	_qm.reconcile_impossible()
	_check(_done(&"i_kill", 0), "a boss kill the saved world marks defeated is credited")
	_check(not _done(&"i_kill", 1), "a plain enemy with no saved record is left alone")

	_fresh()
	_qm.start_quest(&"i_kill", true)
	_qm.reconcile_impossible()
	_check(not _done(&"i_kill", 0) and not _done(&"i_kill", 1), "with no saved kill record no kill step is credited")

	_fresh()
	_qm.start_quest(&"i_kill2", true)
	_world.set_flag(&"boss_warden_defeated", true)
	_qm.reconcile_impossible()
	_check(not _done(&"i_kill2", 0), "a count of 2 is not credited by one proven kill")

	# --- strict order: a locked step is never judged ---
	_fresh()
	_qm.start_quest(&"i_strict", true)
	_qm._history[item_key] = true
	_qm.reconcile_impossible()
	_check(not _done(&"i_strict", 1), "a strict step that is still locked is not credited")

	# --- a reload: the proof survives a save/load round trip ---
	_fresh()
	_qm.start_quest(&"i_item", true)
	_qm._history[item_key] = true
	var saved: Dictionary = _qm.to_dict()
	_qm.reset()
	_qm.from_dict(saved)
	_qm.reconcile_impossible()
	_check(_qm.is_active(&"i_item") and _done(&"i_item", 0), "after a save and load the proven step is still credited")

	print("impossible_step_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
