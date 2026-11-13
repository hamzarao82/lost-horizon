extends SceneTree
## Acts 4-6 of "The First Signal" (docs/STORY_AND_MISSION_FLOW.md):
##   godot --headless --path . -s tests/mission_check.gd
## Events go through QuestManager.notify / WorldState like in play; the d_guards squad is spawned for real.

const OBJ := ObjectiveData.Type
const FIRST: StringName = &"first_signal"
const HEAVY: String = "res://resources/attacks/heavy_1.tres"

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _sm: Node


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


func _index(id: StringName) -> int:
	var quest := _qm.get_quest(FIRST) as QuestData
	for i in quest.objectives.size():
		if quest.objectives[i].id == id:
			return i
	return -1


func _done(id: StringName) -> bool:
	if _qm.is_completed(FIRST):
		return true
	return bool(_qm.active[FIRST]["done"][_index(id)])


## Acts 1-3 through events, leaving Acts 4-6 open.
func _acts_1_to_3() -> void:
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


func _fresh() -> void:
	_sm.reset_runtime_state()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	await _frames(3)  # QuestManager binds WorldState on a deferred call
	_test_data()
	await _test_objectives()
	await _test_completion_once()
	await _test_out_of_order_and_optional()
	await _test_old_save()
	await _test_guards()
	_qm.mission_autosave = true
	_sm.reset_runtime_state()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("Quest data")
	var quest := _qm.get_quest(FIRST) as QuestData
	_check(quest != null and quest.validate().is_empty(), "first_signal validates")
	for id in [&"enter_command_center", &"defeat_command_guards", &"read_black_site_file", &"defeat_warden", &"take_warden_reward", &"contact_outside"]:
		_check(_index(id) >= 10, "objective %s exists after the Acts 1-3 chain" % id)
		_check(not quest.objectives[_index(id)].optional, "%s is required" % id)
	_check(quest.objectives[9].optional and quest.objectives[9].id == &"find_security_log", "the optional log keeps index 9")
	var reward := quest.objectives[_index(&"take_warden_reward")]
	_check(reward.targets.has("warden_blade") and reward.targets.has("warden_plate") and reward.required() == 1, "the reward objective accepts the blade or the plate")


func _test_objectives() -> void:
	print("Acts 4-6 objectives")
	_fresh()
	_acts_1_to_3()
	_check(_qm.is_active(FIRST), "Acts 1-3 alone do not finish the mission")
	_check(_qm.tracker_objective() == "Enter the command center", "the tracker moves on to Act 4")
	_qm.notify(OBJ.ENTER_AREA, &"area_d_command")
	_check(_done(&"enter_command_center") and _qm.tracker_objective() == "Defeat the command guards", "entering Area D -> guards")
	_world.set_flag(&"patrol_d_guards_cleared", true)
	_check(_done(&"defeat_command_guards"), "the cleared flag completes the guards objective")
	_world.emit_interacted(&"log_project_black_site")
	_check(_done(&"read_black_site_file") and _qm.tracker_objective() == "Defeat the Warden", "reading the file -> Warden")
	_world.set_flag(&"boss_warden_defeated", true)
	# The Warden falling also opens the road to Dead Coast (CampaignFlow): the tracker pins that step
	# above first_signal's own from here on, even though first_signal is still open and tracked underneath.
	_check(_done(&"defeat_warden") and _qm.tracker_objective() == "Follow the signal to the Dead Coast", "the Warden flag -> reward objective still completes; the pinned road quest is what the tracker shows")
	_qm.notify(OBJ.ITEM_COLLECTED, &"health_potion")
	_check(not _done(&"take_warden_reward"), "an unrelated pickup does not count")
	_qm.notify(OBJ.ITEM_COLLECTED, &"warden_plate")
	_check(_done(&"take_warden_reward") and _qm.is_active(FIRST), "the plate counts as the reward; the mission is still open")
	_qm.tracker_first = &""  # drop the pin to see first_signal's own remaining step underneath it
	_check(_qm.tracker_objective() == "Contact the outside from the command terminal", "the last objective is the command terminal")


func _test_completion_once() -> void:
	print("Completion")
	_fresh()
	var counts := {"mission": 0, "quest": 0, "id": &""}
	var on_mission := func(id: StringName) -> void:
		counts["mission"] += 1
		counts["id"] = id
	var on_quest := func(id: StringName) -> void:
		if id == FIRST:
			counts["quest"] += 1
	_qm.mission_completed.connect(on_mission)
	_qm.quest_completed.connect(on_quest)
	_acts_1_to_3()
	_qm.notify(OBJ.ENTER_AREA, &"area_d_command")
	_world.set_flag(&"patrol_d_guards_cleared", true)
	_world.emit_interacted(&"log_project_black_site")
	_world.set_flag(&"boss_warden_defeated", true)
	_qm.notify(OBJ.ITEM_COLLECTED, &"warden_blade")
	_check(counts["mission"] == 0, "no mission_completed before the terminal")
	_world.emit_interacted(&"command_terminal_d")
	_check(_qm.is_completed(FIRST) and counts["quest"] == 1, "the terminal completes The First Signal")
	_check(counts["mission"] == 1 and counts["id"] == FIRST, "mission_completed(first_signal) is emitted once")
	_check(_world.has_flag(&"mission_first_signal_complete"), "the completion flag is set")
	_check(_qm._rewarded.count(FIRST) == 1, "the reward is queued once")
	_world.emit_interacted(&"command_terminal_d")
	_qm.notify(OBJ.ENTER_AREA, &"area_d_command")
	_qm.notify(OBJ.INTERACT, &"command_terminal_d")
	_check(counts["mission"] == 1 and counts["quest"] == 1 and _qm._rewarded.count(FIRST) == 1, "repeated events do not repeat the completion, signal or reward")
	_qm.mission_completed.disconnect(on_mission)
	_qm.quest_completed.disconnect(on_quest)
	# The autosave: attempted (deferred) on completion when enabled. With no player in the scene the save
	# itself is refused, so the signal is observed through the manager's own hook instead of a file.
	_fresh()
	_qm.mission_autosave = true
	var attempts := {"n": 0}
	var on_saved := func(_reason: String) -> void:
		if _reason == "mission":
			attempts["n"] += 1
	_sm.saved.connect(on_saved)
	var host := Node3D.new()
	root.add_child(host)
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Player
	host.add_child(player)
	await _frames(3)
	_acts_1_to_3()
	for id in [&"area_d_command"]:
		_qm.notify(OBJ.ENTER_AREA, id)
	_world.set_flag(&"patrol_d_guards_cleared", true)
	_world.emit_interacted(&"log_project_black_site")
	_world.set_flag(&"boss_warden_defeated", true)
	_qm.notify(OBJ.ITEM_COLLECTED, &"warden_blade")
	_world.emit_interacted(&"command_terminal_d")
	await _frames(3)
	# >= 1: the results screen (another component) also saves with reason "mission" when it is in the scene.
	_check(attempts["n"] >= 1, "completing the mission writes an autosave with reason mission (%d)" % attempts["n"])
	_sm.saved.disconnect(on_saved)
	_sm.delete_save()
	_qm.mission_autosave = false
	host.queue_free()
	await _frames(2)


func _test_out_of_order_and_optional() -> void:
	print("Out of order and optional")
	_fresh()
	_qm.notify(OBJ.ENTER_AREA, &"area_d_command")
	_world.set_flag(&"boss_warden_defeated", true)
	_qm.notify(OBJ.ITEM_COLLECTED, &"warden_blade")
	_world.emit_interacted(&"log_project_black_site")
	_world.emit_interacted(&"command_terminal_d")
	_check(_qm.is_active(FIRST), "early Act 4-6 events do not finish the mission by themselves")
	_world.set_flag(&"patrol_d_guards_cleared", true)
	_acts_1_to_3()
	_check(_qm.is_completed(FIRST), "once the missing steps arrive, the remembered events complete it")
	_fresh()
	_world.emit_interacted(&"log_missing_security")
	_check(_qm.is_active(FIRST) and _qm.tracker_optional() == "", "the optional log alone changes nothing else")
	_fresh()
	_acts_1_to_3()
	_qm.notify(OBJ.ENTER_AREA, &"area_d_command")
	_world.set_flag(&"patrol_d_guards_cleared", true)
	_world.emit_interacted(&"log_project_black_site")
	_world.set_flag(&"boss_warden_defeated", true)
	_qm.notify(OBJ.ITEM_COLLECTED, &"warden_blade")
	_world.emit_interacted(&"command_terminal_d")
	_check(_qm.is_completed(FIRST), "the mission completes without the optional log")


func _test_old_save() -> void:
	print("Old saves")
	_fresh()
	var old := {
		"active": {"first_signal": {
			"progress": [1, 1, 1, 4, 1, 1, 1, 1, 1, 0],
			"seen": [[], [], [], [], [], [], [], [], [], []],
			"done": [true, true, true, true, true, true, true, true, true, false]}},
		"completed": [], "history": ["0:checkpoint_desk"], "intro_done": true}
	_qm.from_dict(old)
	_check(_qm.is_active(FIRST), "a save from before Acts 4-6 loads and the mission is active")
	var quest := _qm.get_quest(FIRST) as QuestData
	_check(_qm.active[FIRST]["done"].size() == quest.objectives.size(), "its progress is resized to the new objective list")
	_acts_1_to_3()
	_qm.notify(OBJ.ENTER_AREA, &"area_d_command")
	_check(_done(&"enter_command_center"), "the new objectives work after loading an old save")
	_qm.from_dict({"completed": ["first_signal"], "rewarded": ["first_signal"], "intro_done": true})
	_check(_qm.is_completed(FIRST), "a save that already finished the mission keeps it finished")


func _test_guards() -> void:
	print("Area D guards")
	_fresh()
	var host := Node3D.new()
	root.add_child(host)
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Player
	host.add_child(player)
	var outpost := Outpost17.new()
	host.add_child(outpost)
	await _frames(4)
	var group := outpost.get_node_or_null("PatrolD") as PatrolGroup
	_check(group != null and group.group_id == &"d_guards" and group.area_id == &"area_c_research", "PatrolD exists: group d_guards, woken by the research wing")
	if group == null:
		return
	_check(group.route_points.size() >= 2, "it has a route")
	for point in group.route_points:
		var p: Vector3 = group.to_global(point)
		_check(absf(p.x) > 14.5 and p.z < -62.0 and p.z > -92.0, "route point (%.0f, %.0f) is in the east yard, clear of the boss zone" % [p.x, p.z])
	_check(group.enemies.is_empty(), "nobody spawned before the player reaches the research wing")
	_world.emit_area_entered(&"area_c_research")
	await _frames(4)
	_check(group.enemies.size() == 2, "entering the research wing wakes two command guards (%d)" % group.enemies.size())
	var names := group.enemies.map(func(e: Enemy) -> String: return e.display_name)
	_check(names.size() == 2 and names[0] != names[1], "one elite and one soldier (%s)" % ", ".join(names))
	_check(not _world.has_flag(&"patrol_d_guards_cleared"), "the cleared flag is not set while they live")
	var heavy := load(HEAVY) as AttackData
	for enemy in group.enemies.duplicate():
		for i in 30:
			if enemy.is_dead():
				break
			enemy.receive_hit(heavy, player.global_position)
			await physics_frame
	await _frames(4)
	_check(_world.has_flag(&"patrol_d_guards_cleared"), "killing both sets patrol_d_guards_cleared")
	_check(_done(&"defeat_command_guards"), "and completes the guards objective")
	host.queue_free()
	await _frames(3)
