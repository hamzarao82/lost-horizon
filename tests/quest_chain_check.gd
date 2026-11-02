extends SceneTree
## Milestone 3 main quest "The First Signal" (nine objectives + one optional) and quest items:
##   godot --headless --path . -s tests/quest_chain_check.gd

const QM_SCRIPT: String = "res://scripts/quests/quest_manager.gd"
const OBJ := ObjectiveData.Type

var _failures: int = 0
var _checks: int = 0
var _managers: Array[Node] = []
var _sm: Node


func _initialize() -> void:
	HitStop.enabled = false
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
	_sm = root.get_node("SaveManager")
	_test_data()
	_test_quest_items_class()
	await _test_chain_in_order()
	await _test_chain_out_of_order()
	await _test_optional_objective()
	await _test_quest_items_in_manager()
	await _test_save_round_trip()
	await _test_flag_wiring()
	for qm in _managers:
		if is_instance_valid(qm):
			qm.queue_free()
	await _frames(2)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_manager() -> Node:
	var qm := (load(QM_SCRIPT) as GDScript).new() as Node
	qm.name = "QuestManagerChain%d" % _managers.size()
	root.add_child(qm)
	_managers.append(qm)
	await process_frame
	qm._world = null
	return qm


func _make_player() -> Player:
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(2)
	return player


func _drop(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	await _frames(2)


func _kills(qm: Node, count: int, base: int) -> void:
	for i in count:
		qm.notify(OBJ.KILL_COUNT, &"Soldier", 1, base + i)


# --- data ------------------------------------------------------------------

func _test_data() -> void:
	print("Quest data")
	var quest := load("res://resources/quests/first_signal.tres") as QuestData
	_check(quest != null and quest.validate().is_empty(), "first_signal loads and validates")
	_check(quest.objectives.size() == 10, "nine objectives plus one optional (found %d)" % quest.objectives.size())
	_check(quest.required_indices().size() == 9, "nine objectives are required")
	_check(quest.category == QuestData.Category.MAIN and quest.show_mission_banner, "it is a MAIN quest with the mission banner")
	var optional := 0
	for objective in quest.objectives:
		if objective.optional:
			optional += 1
	_check(optional == 1 and quest.objectives[9].optional and quest.objectives[9].targets.has("log_missing_security"), "the missing security log is the optional objective")
	var all_optional := QuestData.new()
	all_optional.id = &"x"
	all_optional.title = "x"
	var only := ObjectiveData.new()
	only.id = &"o"
	only.text = "o"
	only.targets = PackedStringArray(["a"])
	only.optional = true
	all_optional.objectives = [only]
	_check(not all_optional.validate().is_empty(), "a quest with only optional objectives is invalid")
	_check(ObjectiveData.Type.DISCOVER == 7, "DISCOVER is appended last so saved resources keep their numbers")


func _test_quest_items_class() -> void:
	print("QuestItems")
	var items := QuestItems.new()
	_check(items.add(&"access_card") and not items.add(&"access_card"), "an item is granted once")
	_check(items.has(&"access_card") and not items.has(&"other"), "has() reports what was granted")
	var copy := QuestItems.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(items.to_dict())))
	_check(copy.has(&"access_card") and copy.all().size() == 1, "round trip through JSON")
	copy.from_dict([5, {"a": 1}, "", "x".repeat(100), "ok_item", "ok_item"])
	_check(copy.all() == [&"ok_item"], "wrong types, empty and oversized ids are dropped, duplicates merged")
	copy.from_dict("not an array")
	_check(copy.all().is_empty(), "a damaged field clears safely")
	_check(QuestItems.display_name(&"access_card") == "Security Access Card" and QuestItems.display_name(&"odd_thing") == "Odd Thing", "display names")


# --- the chain --------------------------------------------------------------

func _test_chain_in_order() -> void:
	print("The First Signal, in order")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	_check(qm.is_active(&"first_signal") and qm.tracker_objective() == "Reach the outer perimeter", "the chain starts at the outer perimeter")
	qm.notify(OBJ.ENTER_AREA, &"area_a_perimeter")
	_check(qm.tracker_objective() == "Investigate the abandoned checkpoint", "objective 1 -> 2")
	qm.notify(OBJ.INTERACT, &"checkpoint_desk")
	_check(qm.tracker_objective() == "Find the source of the transmission", "objective 2 -> 3")
	qm.notify(OBJ.INTERACT, &"radio")
	_check(qm.tracker_objective().begins_with("Eliminate the hostile soldiers") and qm.tracker_objective().contains("Soldiers 0/4"), "objective 3 -> 4 with a 0/4 counter")
	_kills(qm, 2, 100)
	_check(qm.tracker_objective().contains("Soldiers 2/4"), "kills advance the counter (2/4)")
	_kills(qm, 2, 100)
	_check(qm.tracker_objective().contains("Soldiers 2/4"), "the same enemies never count twice")
	_kills(qm, 2, 200)
	_check(qm.tracker_objective() == "Locate the security access card", "objective 4 -> 5 after four kills")
	qm.notify(OBJ.FLAG, &"has_access_card")
	_check(qm.tracker_objective() == "Restore power to the communications facility", "objective 5 -> 6")
	qm.notify(OBJ.FLAG, &"comms_power_on")
	_check(qm.tracker_objective() == "Access the military terminal", "objective 6 -> 7")
	qm.notify(OBJ.INTERACT, &"military_terminal")
	_check(qm.tracker_objective() == "Discover the restricted research facility", "objective 7 -> 8")
	qm.notify(OBJ.ENTER_AREA, &"area_c_research")
	_check(qm.is_active(&"first_signal") and qm.tracker_objective() == "Unlock the next mission location", "objective 8 -> 9, the quest is still open")
	qm.notify(OBJ.FLAG, &"next_location_unlocked")
	_check(qm.is_completed(&"first_signal"), "objective 9 completes the quest (the optional one is not needed)")
	_check(player.inventory.weapon.item_id == &"combat_knife", "the reward (combat knife) is granted")
	qm.notify(OBJ.FLAG, &"next_location_unlocked")
	_check(qm.completed.count(&"first_signal") == 1, "a repeated event does not complete it twice")
	await _drop(player)


func _test_chain_out_of_order() -> void:
	print("The First Signal, out of order")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	# The player explores freely: research wing and terminal events arrive before the squad is dead.
	qm.notify(OBJ.ENTER_AREA, &"area_c_research")
	qm.notify(OBJ.INTERACT, &"radio")
	qm.notify(OBJ.FLAG, &"comms_power_on")
	qm.notify(OBJ.INTERACT, &"military_terminal")
	qm.notify(OBJ.FLAG, &"next_location_unlocked")
	_check(qm.is_active(&"first_signal"), "the quest stays open until every required objective is done")
	_check(qm.tracker_objective() == "Reach the outer perimeter", "the tracker shows the first unfinished objective")
	qm.notify(OBJ.ENTER_AREA, &"area_a_perimeter")
	qm.notify(OBJ.INTERACT, &"checkpoint_desk")
	_kills(qm, 4, 300)
	qm.notify(OBJ.FLAG, &"has_access_card")
	_check(qm.is_completed(&"first_signal"), "earlier events counted, so the last missing step finishes it")
	await _drop(player)


func _test_optional_objective() -> void:
	print("Optional objective")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	_check(qm.tracker_optional() == "Optional: find the missing security log", "the optional line is available from the start")
	_check(not qm.tracker_objective().contains("security log"), "it never appears as the main objective")
	qm.notify(OBJ.INTERACT, &"log_missing_security")
	_check(qm.tracker_optional() == "", "finding the log clears the optional line")
	_check(qm.is_active(&"first_signal"), "the optional objective alone does not finish the quest")
	# A hidden_until optional objective stays off the HUD until its flag is set.
	var quest := (load("res://resources/quests/first_signal.tres") as QuestData).duplicate(true) as QuestData
	quest.objectives[9].hidden_until = &"flag_that_is_not_set"
	qm.quests[&"first_signal"] = quest
	qm.reset()
	_check(qm.tracker_optional() == "", "an optional objective with an unset hidden_until is not shown")
	await _drop(player)


func _test_quest_items_in_manager() -> void:
	print("Quest items in the manager")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	var granted: Array[StringName] = []
	qm.quest_item_added.connect(func(id: StringName) -> void: granted.append(id))
	_check(not qm.has_quest_item(&"access_card"), "no access card at the start")
	qm._on_flag_changed(&"has_access_card", true)
	_check(qm.has_quest_item(&"access_card") and granted == [&"access_card"], "the access-card flag grants the quest item once")
	qm._on_flag_changed(&"has_access_card", true)
	_check(granted.size() == 1, "a repeated flag does not grant it again")
	# Gear changes never touch quest items.
	player.inventory.add_item(load("res://resources/items/combat_knife.tres") as ItemData)
	player.inventory.add_item(load("res://resources/items/military_machete.tres") as ItemData)
	player.inventory.add_item(load("res://resources/items/reinforced_armor.tres") as ItemData)
	_check(qm.has_quest_item(&"access_card"), "equipping and replacing gear does not remove the access card")
	qm.reset()
	_check(not qm.has_quest_item(&"access_card"), "a fresh run clears quest items")
	await _drop(player)


func _test_save_round_trip() -> void:
	print("Save round trip")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	qm.add_quest_item(&"access_card")
	qm.notify(OBJ.INTERACT, &"radio")
	var through_file: Variant = JSON.parse_string(JSON.stringify(qm.to_dict()))
	var sanitized := QuestState.sanitize(through_file)
	_check(sanitized.has("quest_items") and sanitized["quest_items"] == ["access_card"], "the sanitised save keeps the quest items")
	qm.reset()
	qm.from_dict(through_file)
	_check(qm.has_quest_item(&"access_card"), "loading restores the access card")
	_check(qm.objective_progress(&"first_signal", 2) == 1, "loading restores objective progress (radio found)")
	# An old save without the new field still loads.
	var old: Dictionary = through_file.duplicate(true)
	old.erase("quest_items")
	qm.reset()
	qm.from_dict(old)
	_check(not qm.has_quest_item(&"access_card") and qm.is_active(&"first_signal"), "an old save without quest_items loads with none")
	# Damaged data cannot crash it.
	qm.from_dict({"quest_items": 12, "active": 5, "completed": "x"})
	_check(qm.is_active(&"first_signal"), "damaged quest data falls back to a fresh quest line")
	await _drop(player)


func _test_flag_wiring() -> void:
	print("Flags and documents")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	qm.notify(OBJ.FLAG, &"x")  # unknown flag: nothing happens
	_check(qm.is_active(&"first_signal"), "an unknown flag does nothing")
	qm._on_flag_changed(&"doc_log_missing_security_found", true)
	_check(qm.tracker_optional() == "", "the document flag counts as finding the log")
	# The terminal sets next_location_unlocked itself (real WorldState).
	var world := root.get_node_or_null("WorldState")
	if world != null:
		world.reset()
		qm._world = world
		qm.reset()
		qm._on_interacted(&"military_terminal")
		_check(world.has_flag(&"next_location_unlocked"), "using the terminal unlocks the next location")
		qm._world = null
		world.reset()
	await _drop(player)
