extends SceneTree
## Mission failure and recovery rules (docs/MISSION_RULES.md), headless:
##   godot --headless --path . -s tests/mission_failure_check.gd

var _failures: int = 0
var _checks: int = 0
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


func _objective(id: StringName, type: ObjectiveData.Type, targets: Array, optional: bool = false) -> ObjectiveData:
	var o := ObjectiveData.new()
	o.id = id
	o.text = "step %s" % id
	o.type = type
	o.targets = PackedStringArray(targets)
	o.optional = optional
	return o


func _quest(id: StringName, objectives: Array[ObjectiveData], strict: bool = false) -> QuestData:
	var q := QuestData.new()
	q.id = id
	q.title = "Test %s" % id
	q.objectives = objectives
	q.strict_order = strict
	_qm.quests[id] = q
	return q


func _fresh() -> void:
	_qm.reset()
	_world.reset()
	for id in [&"t_boss", &"t_flag", &"t_strict", &"t_opt"]:
		_qm.active.erase(id)
		_qm.completed.erase(id)
		_qm._rewarded.erase(id)


func _run() -> void:
	_qm = root.get_node_or_null("QuestManager")
	_world = root.get_node_or_null("WorldState")
	await process_frame
	await process_frame
	_check(_qm != null and _world != null, "QuestManager and WorldState exist")
	if _qm == null or _world == null:
		quit(1)
		return

	var boss_q := _quest(&"t_boss", [
		_objective(&"find", ObjectiveData.Type.FLAG, ["t_marker_one"]),
		_objective(&"boss", ObjectiveData.Type.BOSS_DEFEATED, ["t_boss_one"]),
	])
	_quest(&"t_flag", [
		_objective(&"doc", ObjectiveData.Type.DISCOVER, ["t_doc_one"]),
		_objective(&"nice", ObjectiveData.Type.FLAG, ["t_never_set"], true),
	])
	_quest(&"t_strict", [
		_objective(&"a", ObjectiveData.Type.FLAG, ["t_strict_a"]),
		_objective(&"b", ObjectiveData.Type.BOSS_DEFEATED, ["t_boss_two"]),
		_objective(&"c", ObjectiveData.Type.FLAG, ["t_strict_c"]),
	], true)
	_quest(&"t_opt", [
		_objective(&"only_optional", ObjectiveData.Type.FLAG, ["t_never_set"], true),
	])

	print("-- rule 2: reconcile credits what saved state already proves")
	_fresh()
	_world.set_flag(&"boss_t_boss_one_defeated", true)
	_qm.start_quest(&"t_boss", true)
	_check(_qm.objective_progress(&"t_boss", 1) == 0, "start_quest alone does not read boss flags (existing behaviour kept)")
	var n: int = _qm.reconcile_active()
	_check(n >= 1 and _qm.objective_progress(&"t_boss", 1) == 1, "reconcile credits a boss defeated before the quest was active (%d)" % n)
	_check(_qm.is_active(&"t_boss"), "the quest is still waiting for its flag step")
	_world.set_flag(&"t_marker_one", true)
	_qm.reconcile_active()
	_check(_qm.is_completed(&"t_boss"), "once every proof exists the quest completes")
	_check(_qm.reconcile_active() == 0, "reconcile is idempotent when nothing is left to credit")

	_fresh()
	_world.set_flag(&"doc_t_doc_one_found", true)
	_qm.start_quest(&"t_flag", true)
	_qm.reconcile_active()
	_check(_qm.is_completed(&"t_flag"), "a document found earlier completes its step, and an optional step never blocks")
	_check(not _qm.is_completed(&"t_opt") and not _qm.is_active(&"t_opt"), "an unrelated quest is untouched")

	print("-- rule 2: strict order is respected")
	_fresh()
	_world.set_flag(&"boss_t_boss_two_defeated", true)
	_world.set_flag(&"t_strict_c", true)
	_qm.start_quest(&"t_strict", true)
	_qm.reconcile_active()
	_check(_qm.objective_progress(&"t_strict", 1) == 0 and _qm.objective_progress(&"t_strict", 2) == 0,
		"later steps are not credited while step 1 is open")
	_world.set_flag(&"t_strict_a", true)
	_qm.reconcile_active()
	_check(_qm.is_completed(&"t_strict"), "when the first step is proven the waiting proofs apply in turn and it completes")

	print("-- rule 3: restart an active quest safely")
	_fresh()
	_qm.start_quest(&"t_boss", true)
	_world.set_flag(&"t_marker_one", true)
	_qm.notify(ObjectiveData.Type.FLAG, &"t_marker_one")
	_check(_qm.objective_progress(&"t_boss", 0) == 1, "step one is done before the restart")
	_check(_qm.restart_quest(&"t_boss"), "an active quest can be restarted")
	_check(_qm.is_active(&"t_boss") and _qm.objective_progress(&"t_boss", 0) == 1,
		"the restart replays what history and saved state still prove (step one is not lost)")
	_check(not _qm.restart_quest(&"does_not_exist"), "an unknown quest cannot be restarted")
	_qm.notify(ObjectiveData.Type.BOSS_DEFEATED, &"t_boss_one")
	_check(_qm.is_completed(&"t_boss"), "finishing the quest after a restart works")
	var rewarded_before: int = _qm._rewarded.size()
	_check(not _qm.restart_quest(&"t_boss"), "a completed quest cannot be restarted")
	_check(_qm._rewarded.size() == rewarded_before, "no reward is paid again")

	print("-- rule 1: death costs no mission progress; saved state survives a reload")
	_fresh()
	_qm.start_quest(&"t_boss", true)
	_world.set_flag(&"boss_t_boss_one_defeated", true)
	_qm.reconcile_active()
	var saved: Dictionary = _qm.to_dict()
	_fresh()
	_world.reset()
	_qm.on_game_loaded(saved)
	_check(_qm.is_active(&"t_boss") and _qm.objective_progress(&"t_boss", 1) == 1,
		"a reload keeps the credited step (death reloads from the checkpoint save)")
	_world.set_flag(&"t_marker_one", true)
	_qm.on_game_loaded(_qm.to_dict())
	_check(_qm.is_completed(&"t_boss") or _qm.objective_progress(&"t_boss", 0) == 1,
		"a load reconciles: a flag set in the restored world counts")

	print("-- no soft lock from an optional-only quest")
	_fresh()
	_qm.start_quest(&"t_opt", true)
	_check(_qm.is_completed(&"t_opt"), "a quest with only optional steps completes immediately instead of waiting forever")

	_fresh()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
