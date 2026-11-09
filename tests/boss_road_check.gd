extends SceneTree
## The way on opens when a stage's bosses are down, with no need to finish its missions, on every stage.
## godot --headless --path . -s tests/boss_road_check.gd   (uses SaveManager's per-process test file)

const STAGES: Array = [
	{"region": &"dead_coast", "bosses": [&"dead_coast_boss_1_defeated", &"dead_coast_boss_2_defeated"],
			"next": &"blackwood", "road": &"dc_road_to_blackwood"},
	{"region": &"blackwood", "bosses": [&"blackwood_boss_1_defeated", &"blackwood_boss_2_defeated"],
			"next": &"research_complex", "road": &"bw_road_to_research_complex"},
	{"region": &"research_complex", "bosses": [&"research_complex_elite_down", &"research_complex_boss_2_defeated"],
			"next": &"iron_fortress", "road": &"rc_road_to_iron_fortress"},
]
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
	var pointer := main.find_children("*", "ObjectivePointer", true, false)[0] as ObjectivePointer

	# Outpost 17: the Warden's fall opens the road south, with the first mission still unfinished.
	_check(not _world.has_flag(&"dead_coast_unlocked"), "Outpost 17: the road is shut at the start")
	_check(not _qm.is_completed(&"first_signal"), "Outpost 17: the first mission is NOT complete")
	_world.set_flag(&"boss_warden_defeated", true)
	await _frames(40)
	_check(_world.has_flag(&"dead_coast_unlocked"), "Outpost 17: the Warden's fall unlocks Dead Coast")
	_check(_qm.is_active(&"leave_outpost"), "Outpost 17: the road quest starts")
	_check(_qm.tracker_title() == "The Road South", "Outpost 17: the tracker leads to the road (%s)" % _qm.tracker_title())
	_check(main.has_node("ServiceRoadDoor") and not main.has_node("CampaignGate"), "Outpost 17: the service door shows and the barricade is gone")

	for stage: Dictionary in STAGES:
		var region: StringName = stage["region"]
		_rm.unlock(region)
		var data := RegionStore.load_data(region)
		var entry: StringName = data.entry_points.keys()[0] if data != null and not data.entry_points.is_empty() else &""
		var ok: bool = await _rm.travel(region, entry, null, true)
		await _frames(30)
		_check(ok and _rm.current_region_id == region, "%s: reached by real travel" % region)
		var next: StringName = stage["next"]
		var bosses: Array = stage["bosses"]
		_check(not _world.has_flag(CampaignFlow.unlock_flag(next)), "%s: %s is locked at first" % [region, next])
		_world.set_flag(bosses[0], true)
		await _frames(20)
		_check(not _world.has_flag(CampaignFlow.unlock_flag(next)), "%s: ONE boss down is not enough" % region)
		_world.set_flag(bosses[1], true)
		await _frames(30)
		_check(_world.has_flag(CampaignFlow.unlock_flag(next)), "%s: both bosses down unlock %s" % [region, next])
		_check(not _qm.is_completed(&"dc_lost_cargo") and not _world.has_flag(&"%s_mission_3_complete" % region),
				"%s: with the missions NOT finished" % region)
		_check(_qm.is_active(stage["road"]), "%s: the road step starts" % region)
		_check(_qm.tracker_first == stage["road"], "%s: and is pinned at the top of the tracker" % region)
		var road_quest: QuestData = _qm.get_quest(stage["road"])
		pointer._resolve_for(road_quest.objectives[0])
		_check(pointer.label.begins_with("Road to"), "%s: the arrow leads to the road (%s)" % [region, pointer.label])
		var gates := root.find_children("*", "RegionGate", true, false)
		var open_gate := false
		for gate in gates:
			if (gate as RegionGate).next_region == next and (gate as RegionGate).is_open():
				open_gate = true
		if region == &"research_complex":
			open_gate = _rm.is_unlocked(next)  # this stage keeps its own underground exit instead of a RegionGate
		_check(open_gate, "%s: the way to %s is open" % [region, next])

	_sm.reset_runtime_state()
	_sm.delete_save()
	print("boss_road_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
