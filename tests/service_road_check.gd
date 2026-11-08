extends SceneTree
## The way out behind the Warden room: a service road to the Dead Coast, so nobody walks the whole map back.
## godot --headless --path . -s tests/service_road_check.gd   (uses SaveManager's per-process test file)

const OBJ := ObjectiveData.Type
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
	_qm.tracker_first = &""
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	var player := main.get_node("Player") as Player
	var north := main.get_node_or_null("Exit_to_dead_coast_north") as RegionExit
	var south := main.get_node_or_null("Exit_to_dead_coast") as RegionExit
	_check(north != null and south != null, "Outpost 17 has both exits")
	if north == null or south == null:
		quit(1)
		return
	_check(north.position.z < -85.0 and north.position.z > -92.0, "the north exit sits inside Area D's north wall (z %.1f)" % north.position.z)
	_check(not main.has_node("ServiceRoadDoor"), "no service door before the mission is done")

	player.global_position = north.global_position
	await _frames(20)
	_check(_rm.current_region_id == &"outpost_17", "walking into the north exit is refused before the mission ends")
	player.global_position = Vector3(0.0, 0.1, -60.0)
	await _frames(2)

	_complete_first_signal()
	await _frames(30)
	_check(main.has_node("ServiceRoadDoor"), "the service door appears when the road opens")
	_check(not main.has_node("CampaignGate"), "and the south barricade is gone")

	var pointers := main.find_children("*", "ObjectivePointer", true, false)
	if pointers.size() == 1:
		var pointer := pointers[0] as ObjectivePointer
		player.global_position = Vector3(0.0, 0.1, -80.0)
		pointer._resolve_target()
		_check(pointer.label == "Service road", "near the Warden room the arrow says Service road (%s)" % pointer.label)
		player.global_position = Vector3(0.0, 0.1, 60.0)
		pointer._resolve_target()
		_check(pointer.label == "Road south", "near the beach the arrow says Road south (%s)" % pointer.label)
	else:
		_check(false, "the HUD has one objective pointer")

	player.global_position = north.global_position
	var guard := 0
	while _rm.current_region_id != &"dead_coast" and guard < 160:
		await physics_frame
		guard += 1
	await _frames(3)
	_check(_rm.current_region_id == &"dead_coast", "walking into the north exit travels to Dead Coast")

	_sm.reset_runtime_state()
	_sm.delete_save()
	print("service_road_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
