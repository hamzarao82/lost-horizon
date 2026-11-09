extends SceneTree
## Every required objective of every region mission must be findable by the objective arrow.
## godot --headless --path . -s tests/pointer_regions_check.gd   (uses SaveManager's per-process test file)

const REGIONS: Array = [&"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _sm: Node
var _rm: Node


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


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_rm = root.get_node("RegionManager")
	await _frames(3)
	_sm.reset_runtime_state()
	_sm.delete_save()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	var pointers := main.find_children("*", "ObjectivePointer", true, false)
	_check(pointers.size() == 1, "the HUD has one objective pointer")
	if pointers.size() != 1:
		quit(1)
		return
	var pointer := pointers[0] as ObjectivePointer
	for region: StringName in REGIONS:
		_rm.unlock(region)
		var data := RegionStore.load_data(region)
		var entry: StringName = data.entry_points.keys()[0] if data != null and not data.entry_points.is_empty() else &""
		var ok: bool = await _rm.travel(region, entry, null, true)
		await _frames(30)
		_check(ok and _rm.current_region_id == region, "%s: reached by real travel" % region)
		var total := 0
		var waves_checked := 0
		var missing: Array[String] = []
		for quest_id: StringName in _qm.quests.keys():
			if _qm._quest_region.get(quest_id, &"outpost_17") != region:
				continue
			var quest: QuestData = _qm.get_quest(quest_id)
			for objective: ObjectiveData in quest.objectives:
				if objective.optional:
					continue
				total += 1
				pointer._resolve_for(objective)
				if pointer.target == null:
					missing.append("%s/%s" % [quest_id, objective.id])
				for flag in objective.targets:
					if String(flag).ends_with("_waves_cleared"):
						waves_checked += 1
						_check(pointer.label == "Hold point", "%s: the wave step '%s' aims at the hold point (%s)" % [region, objective.id, pointer.label])
		_check(total > 0, "%s: has required objectives (%d)" % [region, total])
		_check(waves_checked == 1, "%s: has exactly one wave step (%d)" % [region, waves_checked])
		_check(missing.is_empty(), "%s: the arrow finds every required objective (missing: %s)" % [region, ", ".join(missing)])
	_sm.reset_runtime_state()
	_sm.delete_save()
	print("pointer_regions_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
