extends SceneTree
## The three Blackwood missions through real events: godot --headless --path . -s tests/blackwood_missions_check.gd
## Real areas, interactables, puzzle, ambush and defenders; rewards and XP exactly once; out-of-order play.

const HEAVY: String = "res://resources/attacks/heavy_1.tres"
const Q1: StringName = &"into_the_blackwood"
const Q2: StringName = &"ghost_frequency"
const Q3: StringName = &"experimental_site"

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _sm: Node
var _prog: Node
var _region: Blackwood
var _player: Player


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


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _fresh() -> void:
	if _region != null and is_instance_valid(_region):
		_region.queue_free()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	await _frames(2)
	_sm.reset_runtime_state()
	_world.reset()
	root.get_node("RegionManager").from_dict({})  # claimed ids are saved state too
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	_player = load("res://scenes/player/Player.tscn").instantiate() as Player
	_player.position = Vector3(2000.0, 5.0, 2000.0)  # far from every trigger: areas are entered by events below
	root.add_child(_player)
	await _frames(3)
	_region = load("res://scenes/regions/Blackwood_content.tscn").instantiate() as Blackwood
	root.add_child(_region)
	await _frames(3)


func _terminal(id: StringName) -> Terminal:
	for t in _region.find_children("*", "Terminal", true, false):
		if (t as Terminal).interaction_id == id:
			return t
	return null


func _interactable(id: StringName) -> Interactable:
	for t in _region.find_children("*", "Interactable", true, false):
		if (t as Interactable).interaction_id == id:
			return t
	return null


func _use(id: StringName) -> bool:
	var node := _interactable(id)
	return node != null and node.interact(_player)


func _owned(item_id: String) -> int:
	var n: int = _player.inventory.count_of(item_id)
	for slot in [ItemData.Slot.HEAD, ItemData.Slot.GLOVES, ItemData.Slot.LEGS, ItemData.Slot.ACCESSORY]:
		var worn := _player.inventory.equipped(slot) as ItemData
		if worn != null and String(worn.item_id) == item_id:
			n += 1
	return n


func _count(item_id: String) -> int:
	return _player.inventory.count_of(item_id)


func _done(quest: StringName, objective: StringName) -> bool:
	if _qm.is_completed(quest):
		return true
	if not _qm.is_active(quest):
		return false
	var data := _qm.get_quest(quest) as QuestData
	for i in data.objectives.size():
		if data.objectives[i].id == objective:
			return bool(_qm.active[quest]["done"][i])
	return false


func _kill(encounter: BlackwoodEncounter) -> void:
	var kill := load(HEAVY) as AttackData
	for e in encounter.enemies:
		for i in 30:
			if is_instance_valid(e) and not e.is_dead():
				e.receive_hit(kill, e.global_position + Vector3(0.0, 0.0, 2.0))


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_prog = root.get_node("Progression")
	await _frames(3)
	await _test_full_chain()
	await _test_out_of_order()
	await _test_reload_no_repeat()
	_qm.mission_autosave = true
	_sm.reset_runtime_state()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_full_chain() -> void:
	print("Full chain, in order")
	await _fresh()
	_check(not _qm.is_active(Q1), "the chain does not start before the player enters Blackwood")
	var xp_start: int = _prog.progress.xp
	_world.emit_area_entered(&"blackwood_jungle_entrance")
	await _frames(2)
	_check(_qm.is_active(Q1), "entering the jungle starts Into the Blackwood")
	_check(_done(Q1, &"enter_blackwood"), "'Enter the Blackwood' is done")
	_world.emit_area_entered(&"blackwood_trail")
	_check(_done(Q1, &"follow_trail"), "following the trail counts")
	_check(_use(&"bw_patrol_gear"), "the abandoned patrol gear can be searched")
	_check(_done(Q1, &"check_patrol_gear"), "'Investigate the abandoned patrol equipment' is done")
	_check(not _qm.is_completed(Q1), "the mission is open before the ambush")
	# Real ambush.
	var ambush: BlackwoodEncounter = _region.encounters[&"ambush"]
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(1.8)
	_check(ambush.enemies.size() == 3, "the ambush attackers arrived")
	_kill(ambush)
	await _frames(4)
	_check(_done(Q1, &"survive_ambush"), "'Survive the ambush' is done after the attackers fall")
	_world.emit_area_entered(&"blackwood_patrol_camp")
	await _frames(3)
	_check(_qm.is_completed(Q1), "Into the Blackwood completes without the optional logs")
	_check(_count("bandage") == 2, "its reward paid two bandages (%d)" % _count("bandage"))
	_check(_qm.is_active(Q2), "Ghost Frequency starts next")
	_check(_prog.progress.xp - xp_start >= 260, "quest XP was awarded (%d)" % (_prog.progress.xp - xp_start))
	# Ghost Frequency.
	_world.set_flag(&"blackwood_waves_cleared")  # the stage's wave step (stage_waves_check plays the real fight)
	_world.emit_area_entered(&"blackwood_comms_station")
	_check(_done(Q2, &"find_station"), "the hidden station is found")
	var receiver := _terminal(&"bw_transmissions")
	_check(receiver != null and receiver.locked and not receiver.interact(_player), "the receiver is locked before the station has power")
	_check(not _done(Q2, &"restore_station"), "nothing advanced from touching the locked receiver")
	_check(_use(&"bw_log_frequency"), "the frequency log can be read")
	_check(_done(Q2, &"read_frequency"), "'Read the technician's frequency log' is done")
	var p := _region.puzzle
	p.turn(0)
	p.transmit()
	_check(not _done(Q2, &"restore_station") and p.dials == [0, 0, 0], "a wrong channel changes nothing but the dials")
	for dial in 3:
		while p.dials[dial] != FrequencyPuzzle.CODE[dial]:
			p.turn(dial)
	_check(p.transmit(), "the right channel restores the station")
	await _frames(2)
	_check(_done(Q2, &"restore_station"), "'Restore the station' is done")
	_check(receiver.locked == false and receiver.interact(_player), "the receiver works now")
	await _frames(2)
	_check(_done(Q2, &"read_transmissions"), "'Investigate the encrypted transmissions' is done")
	_check(not _qm.is_completed(Q2), "the mission is still open before the data is recovered")
	_check(_terminal(&"bw_data_recorder").interact(_player), "the data recorder can be read")
	await _frames(3)
	_check(_done(Q2, &"recover_data") and _done(Q2, &"black_site_link"), "the research data and the Black Site link are done")
	_check(_qm.is_completed(Q2), "Ghost Frequency completes without the optional notes")
	_check(_qm.is_active(Q3), "The Experimental Site starts next")
	# The Experimental Site.
	_world.emit_area_entered(&"blackwood_research_perimeter")
	_check(_done(Q3, &"reach_perimeter"), "the perimeter is reached")
	var gate_panel := _terminal(&"bw_gate_panel")
	_check(gate_panel != null and not gate_panel.locked, "the gate panel is usable after the transmissions")
	_check(gate_panel.interact(_player), "the gate panel can be used")
	await _frames(3)
	_check(_done(Q3, &"open_gate") and _world.has_flag(&"blackwood_gate_open"), "the concealed gate opens")
	_world.emit_area_entered(&"blackwood_testing_site")
	_check(_done(Q3, &"find_site"), "the testing site is found")
	_check(_use(&"bw_test_equipment_1") and not _done(Q3, &"examine_equipment"), "one console is not enough")
	_check(_use(&"bw_test_equipment_2") and _done(Q3, &"examine_equipment"), "both consoles done")
	_check(_use(&"bw_log_experiment_1") and _done(Q3, &"find_evidence"), "the evidence of experimentation is found")
	var site_terminal := _terminal(&"bw_site_terminal")
	_check(site_terminal.locked and not site_terminal.interact(_player), "the site terminal is locked while the site is guarded")
	var defenders: BlackwoodEncounter = _region.encounters[&"site_defenders"]
	_check(defenders.enemies.size() == 4, "four defenders guard the site (%d)" % defenders.enemies.size())
	_kill(defenders)
	await _frames(4)
	_check(_done(Q3, &"defeat_defenders"), "'Defeat the site defenders' is done")
	_check(not _qm.is_completed(Q3), "the mission is open before the access is unlocked")
	_check(site_terminal.interact(_player), "the site terminal unlocks once the defenders are down")
	await _frames(3)
	_check(_qm.is_completed(Q3), "The Experimental Site completes without the optional hatch or list")
	_check(not _region.exit_locked(&"to_research_complex"), "the Research Complex exit is open")
	_check(_owned("blackwood_ghost_charm") == 1 and _player.inventory.unique_claimed.has("blackwood_ghost_charm"), "the unique Ghost Charm arrived once and is claimed (%d)" % _owned("blackwood_ghost_charm"))
	_check(_count("upgrade_kit_weapon") == 1, "the weapon upgrade kit arrived once")
	var xp_total: int = _prog.progress.xp - xp_start
	_check(xp_total >= 260 + 320 + 420, "all three quests paid their XP (%d)" % xp_total)


func _test_out_of_order() -> void:
	print("Out of order and optional")
	await _fresh()
	_world.set_flag(&"blackwood_waves_cleared")  # the stage's wave step (stage_waves_check plays the real fight)
	# Do things from later missions before the chain even starts: they are remembered.
	_world.emit_area_entered(&"blackwood_research_perimeter")
	_world.emit_area_entered(&"blackwood_testing_site")
	_world.emit_area_entered(&"blackwood_comms_station")
	_world.emit_area_entered(&"blackwood_patrol_camp")
	_world.emit_area_entered(&"blackwood_jungle_entrance")
	await _frames(3)
	_check(_qm.is_active(Q1) and _done(Q1, &"find_camp"), "visiting the camp first still counts once the quest begins")
	_check(_use(&"bw_log_patrol_1") and _use(&"bw_log_patrol_2"), "the optional patrol logs are readable")
	await _frames(2)
	var data := _qm.get_quest(Q1) as QuestData
	var optional_done := bool(_qm.active[Q1]["done"][data.objectives.size() - 1])
	_check(optional_done, "the optional objective completes when both logs are read")
	_check(not _qm.is_completed(Q1), "optional objectives alone never complete a mission")
	_world.emit_area_entered(&"blackwood_trail")
	_check(_use(&"bw_patrol_gear"), "gear searched")
	var ambush: BlackwoodEncounter = _region.encounters[&"ambush"]
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(1.8)
	_kill(ambush)
	await _frames(4)
	_check(_qm.is_completed(Q1), "Into the Blackwood completes in a different order")
	_check(_qm.is_active(Q2) and _done(Q2, &"find_station"), "the early station visit was remembered by the next mission")
	_check(_qm.is_active(Q2) == true and not _terminal(&"bw_data_recorder").interact(_player), "the data recorder stays locked until power is restored")
	var p := _region.puzzle
	for dial in 3:
		while p.dials[dial] != FrequencyPuzzle.CODE[dial]:
			p.turn(dial)
	p.transmit()
	await _frames(2)
	_check(_use(&"bw_log_frequency"), "the frequency log is read")
	# Recorder before receiver (the other way round).
	_check(_terminal(&"bw_data_recorder").interact(_player), "the recorder works first this time")
	_check(_terminal(&"bw_transmissions").interact(_player), "then the receiver")
	await _frames(3)
	_check(_qm.is_completed(Q2), "Ghost Frequency completes with the terminals read the other way round")
	_check(_qm.is_active(Q3) and _done(Q3, &"reach_perimeter") and _done(Q3, &"find_site"), "perimeter and site visited early were remembered")


func _test_reload_no_repeat() -> void:
	print("Reload and no repeats")
	await _fresh()
	_world.emit_area_entered(&"blackwood_jungle_entrance")
	await _frames(2)
	var ambush: BlackwoodEncounter = _region.encounters[&"ambush"]
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(1.8)
	_kill(ambush)
	await _frames(3)
	_world.emit_area_entered(&"blackwood_trail")
	_use(&"bw_patrol_gear")
	_world.emit_area_entered(&"blackwood_patrol_camp")
	await _frames(3)
	var bandages := _count("bandage")
	_check(_qm.is_completed(Q1) and bandages == 2, "quest one is done and paid (%d bandages)" % bandages)
	var quest_save: Dictionary = _qm.to_dict()
	var world_save: Dictionary = _world.to_dict()
	# The player returns later: same quests and flags, a rebuilt region.
	_region.queue_free()
	await _frames(2)
	_qm.from_dict(quest_save)
	_world.from_dict(world_save)
	var again := load("res://scenes/regions/Blackwood_content.tscn").instantiate() as Blackwood
	root.add_child(again)
	_region = again
	await _frames(3)
	_world.emit_area_entered(&"blackwood_jungle_entrance")
	_world.emit_area_entered(&"blackwood_patrol_camp")
	_use(&"bw_patrol_gear")
	await _frames(3)
	_check(_qm.is_completed(Q1) and not _qm.is_active(Q1), "the finished mission stays finished after a reload")
	_check(_count("bandage") == bandages, "reloading and revisiting pays nothing again (%d)" % _count("bandage"))
	var again_ambush: BlackwoodEncounter = again.encounters[&"ambush"]
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(1.8)
	_check(again_ambush.enemies.is_empty(), "the cleared ambush does not return")
