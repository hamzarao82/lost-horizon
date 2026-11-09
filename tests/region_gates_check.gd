extends SceneTree
## The gate to the next stage: closed until the next region unlocks, a refusal at the trigger, a lit door when
## it opens, travel through it, an arrow that leads there, and a reload that keeps it open.
## godot --headless --path . -s tests/region_gates_check.gd   (uses SaveManager's per-process test file)

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


func _main() -> Node:
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	var player := main.get_node("Player") as Player
	player.health.max_health = 100000.0
	player.health.health = 100000.0
	return main


func _go(region: StringName) -> void:
	_rm.unlock(region)
	var data := RegionStore.load_data(region)
	var entry: StringName = data.entry_points.keys()[0] if data != null and not data.entry_points.is_empty() else &""
	await _rm.travel(region, entry, null, true)
	await _frames(30)


func _gate(next: StringName) -> RegionGate:
	return root.find_child("RegionGate_%s" % String(next), true, false) as RegionGate


func _exit_to(next: StringName) -> RegionExit:
	for node in root.find_children("*", "RegionExit", true, false):
		var road := node as RegionExit
		if road != null and road.target_region == next:
			return road
	return null


func _walk_in(main: Node, road: RegionExit, target: StringName) -> bool:
	var player := main.get_node("Player") as Player
	player.global_position = road.global_position
	var guard := 0
	while _rm.current_region_id != target and guard < 160:
		await physics_frame
		guard += 1
	await _frames(3)
	return _rm.current_region_id == target


func _stage(from_region: StringName, next: StringName, label: String, road_quest: StringName, main: Node) -> Node:
	print("%s -> %s" % [from_region, next])
	var gate := _gate(next)
	_check(gate != null, "%s: the gate to %s exists" % [from_region, next])
	if gate == null:
		return main
	_check(not gate.is_open() and gate.has_node("Barricade") and not gate.has_node("OpenRoad"), "closed: a barricade and no open door")
	var road := _exit_to(next)
	_check(road != null, "the exit trigger toward %s exists" % next)
	if road == null:
		return main
	_check(road.global_position.distance_to(gate.global_position) < 4.0, "the gate sits just beyond the trigger (%.1f m)" % road.global_position.distance_to(gate.global_position))
	var refused := not await _walk_in(main, road, next)
	_check(refused and _rm.current_region_id == from_region, "walking into the closed exit is refused")
	var player := main.get_node("Player") as Player
	player.global_position = road.global_position + Vector3(0.0, 0.0, 12.0)
	await _frames(4)

	CampaignFlow.mark_mission_complete(from_region, 3)
	await _frames(14)
	_check(_world.has_flag(CampaignFlow.unlock_flag(next)), "mission 3 unlocks %s" % next)
	_check(gate.is_open() and not gate.has_node("Barricade") and gate.has_node("OpenRoad"), "the gate opens: no barricade, a lit door")
	var door_label := gate.get_node("OpenRoad").get_child(1) as Label3D
	_check(door_label != null and door_label.text == "ROAD TO %s" % label.to_upper(), "the door says ROAD TO %s" % label.to_upper())

	var quest := _qm.get_quest(road_quest) as QuestData
	_check(quest != null and quest.objectives.size() == 1 and quest.objectives[0].targets[0] == "%s_arrived" % next, "the road quest ends in %s_arrived" % next)
	var pointers := main.find_children("*", "ObjectivePointer", true, false)
	if pointers.size() == 1 and quest != null:
		var pointer := pointers[0] as ObjectivePointer
		pointer._resolve_for(quest.objectives[0])
		_check(pointer.label == "Road to %s" % label and pointer.target is Vector3 and Vector2(pointer.target.x - road.global_position.x, pointer.target.z - road.global_position.z).length() < 1.5, "the arrow aims at the road (%s)" % pointer.label)
	return main


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_rm = root.get_node("RegionManager")
	await _frames(3)
	_sm.reset_runtime_state()
	_sm.delete_save()
	_rm.reset()
	_world.reset()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()

	print("The quests that end in the gates")
	for pair in [["dc_lost_cargo", "dc_road_to_blackwood"], ["experimental_site", "bw_road_to_research_complex"], ["rc_project_black_site", "rc_road_to_iron_fortress"]]:
		var previous := _qm.get_quest(StringName(pair[0])) as QuestData
		_check(previous != null and previous.next_quest == StringName(pair[1]), "%s hands over to %s" % [pair[0], pair[1]])

	var main := await _main()
	await _go(&"dead_coast")
	main = await _stage(&"dead_coast", &"blackwood", "Blackwood", &"dc_road_to_blackwood", main)

	print("A reload keeps the gate open")
	_check(_sm.save_game("manual"), "saved in Dead Coast with the road open")
	main.queue_free()
	await _frames(4)
	_rm.reset()
	_world.reset()
	_qm.reset()
	_check(_sm.load_game(), "the save loads")
	var main2 := await _main()
	await _frames(24)
	var gate2 := _gate(&"blackwood")
	_check(_rm.current_region_id == &"dead_coast" and gate2 != null and gate2.is_open() and gate2.has_node("OpenRoad") and not gate2.has_node("Barricade"), "after the reload the road is still open")

	print("Travel through the open gate")
	var road := _exit_to(&"blackwood")
	var arrived := road != null and await _walk_in(main2, road, &"blackwood")
	_check(arrived, "walking into the open exit travels to Blackwood")
	_check(_world.has_flag(&"blackwood_arrived"), "the arrival flag blackwood_arrived is set")
	main2 = await _stage(&"blackwood", &"research_complex", "Research Complex", &"bw_road_to_research_complex", main2)
	var road2 := _exit_to(&"research_complex")
	var arrived2 := road2 != null and await _walk_in(main2, road2, &"research_complex")
	_check(arrived2 and _world.has_flag(&"research_complex_arrived"), "and on into the Research Complex, which sets research_complex_arrived")

	main2.queue_free()
	await _frames(4)
	_sm.reset_runtime_state()
	_sm.delete_save()
	print("region_gates_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
