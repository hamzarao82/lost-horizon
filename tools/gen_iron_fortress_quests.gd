extends SceneTree
## Writes the five Iron Fortress quests: godot --headless --path . -s tools/gen_iron_fortress_quests.gd
## Objective ids and event targets must match scripts/regions/iron_fortress/*.gd (the tests check this).
## Flag and interaction ids are underscore-only: WorldState drops anything else when a save is loaded.

const OUT_DIR: String = "res://resources/quests/iron_fortress/"
const T = ObjectiveData.Type


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_last_stronghold())
	_save(_inside_the_walls())
	_save(_chain_of_command())
	_save(_final_lockdown())
	_save(_black_site())
	quit()


func _obj(id: String, text: String, type: ObjectiveData.Type, targets: Array, optional: bool = false, label: String = "") -> ObjectiveData:
	var o := ObjectiveData.new()
	o.id = StringName(id)
	o.text = text
	o.type = type
	o.targets = PackedStringArray(targets)
	o.optional = optional
	o.progress_label = label
	return o


func _quest(id: String, title: String, description: String, objectives: Array[ObjectiveData]) -> QuestData:
	var q := QuestData.new()
	q.id = StringName(id)
	q.title = title
	q.description = description
	q.objectives = objectives
	q.category = QuestData.Category.MAIN
	return q


func _last_stronghold() -> QuestData:
	var q := _quest("if_last_stronghold", "The Last Stronghold",
			"The route table ends at one place: a walled command inland, behind an iron gate. Get to the checkpoint, find a way past the guards and open the main gate.",
			[
				_obj("reach_approach", "Reach the fortress approach", T.ENTER_AREA, ["if_approach_reach"]),
				_obj("investigate_perimeter", "Investigate the checkpoint booth", T.ENTER_AREA, ["if_checkpoint_reach"]),
				_obj("outer_guards", "Deal with the outer guards: defeat them or slip past", T.FLAG, ["iron_fortress_approach_pass"]),
				_obj("search_checkpoint", "Search the checkpoint log", T.INTERACT, ["if_checkpoint_log"]),
				_obj("get_credential", "Take the fortress gate credentials", T.FLAG, ["credential_fortress_gate"]),
				_obj("open_gate", "Open the main gate", T.FLAG, ["door_if_gate_door_open"]),
				_obj("approach_cache", "Find the supply depot cache beside the road", T.FLAG, ["if_cache_approach_taken"], true),
			])
	q.location_hint = "Fortress approach"
	q.next_quest = &"if_inside_the_walls"
	q.start_captions = PackedStringArray(["Walls, towers and one iron gate. Everything on this island was ordered from here."])
	q.complete_captions = PackedStringArray(["The main gate grinds open. Nobody inside has been expecting a visitor."])
	q.rewards = PackedStringArray(["credits_medium", "bandage", "armor_patch"])
	q.reward_text = "Credits, a bandage and an armor patch."
	return q


func _inside_the_walls() -> QuestData:
	var q := _quest("if_inside_the_walls", "Inside the Walls",
			"Break through the outer perimeter: start the gate sequence, win a pass for the barracks, and take the command key from the defenders.",
			[
				_obj("activate_gate", "Run the gate activation at the security control room", T.FLAG, ["iron_fortress_gate_activated"]),
				_obj("barracks_pass", "Take the barracks credentials", T.FLAG, ["credential_barracks"]),
				_obj("enter_barracks", "Enter the military barracks", T.ENTER_AREA, ["if_barracks"]),
				_obj("investigate_armory", "Investigate the armory", T.INTERACT, ["if_armory_terminal"]),
				_obj("disable_lockdown", "Disable the first stage of the inner lockdown", T.FLAG, ["iron_fortress_lockdown_step_a"]),
				_obj("defeat_defenders", "Defeat the security forces in the barracks", T.FLAG, ["iron_fortress_barracks_cleared"]),
				_obj("command_key", "Retrieve the command access key", T.FLAG, ["credential_command_key"]),
				_obj("unlock_command", "Unlock the command center", T.FLAG, ["door_if_command_door_open"]),
				_obj("armory_cache", "Armory recovery: open the armory cache", T.FLAG, ["if_cache_armory_taken"], true),
				_obj("missing_patrol", "Missing patrol: read both Team Ash logs", T.INTERACT, ["if_patrol_log_1", "if_patrol_log_2"], true, "Logs"),
			])
	q.location_hint = "Perimeter and barracks"
	q.next_quest = &"if_chain_of_command"
	q.start_captions = PackedStringArray(["Past the gate: guard posts, a barracks and a lockdown written to cascade inward."])
	q.complete_captions = PackedStringArray(["The command center door is open. The barracks behind you are quiet."])
	q.rewards = PackedStringArray(["credits_medium", "armor_plate"])
	q.reward_text = "Credits and an armor plate."
	return q


func _chain_of_command() -> QuestData:
	var q := _quest("if_chain_of_command", "Chain of Command",
			"Take the command center. Bring the communications network back, read the files and learn who gave the orders.",
			[
				_obj("enter_command", "Enter the command center", T.ENTER_AREA, ["if_command"]),
				_obj("find_archive", "Find the intelligence archive", T.ENTER_AREA, ["if_archive_reach"]),
				_obj("restore_comms", "Restore the communications network", T.FLAG, ["iron_fortress_comms_done"]),
				_obj("retrieve_files", "Retrieve the classified operational files", T.FLAG, ["iron_fortress_files_retrieved"]),
				_obj("learn_director", "Read the Director's file", T.FLAG, ["iron_fortress_director_known"]),
				_obj("command_guards", "Defeat the command center's guard and its commander", T.FLAG, ["iron_fortress_command_cleared"]),
				_obj("unlock_inner", "Unlock the inner fortress", T.FLAG, ["door_if_inner_door_open"]),
				_obj("classified_orders", "Classified orders: find all three orders", T.INTERACT, ["if_orders_1", "if_orders_2", "if_orders_3"], true, "Orders"),
			])
	q.location_hint = "Command center"
	q.next_quest = &"if_final_lockdown"
	q.start_captions = PackedStringArray(["Screens, maps and a long table. The people who ran the island worked here."])
	q.complete_captions = PackedStringArray(["Now there is a name on the other end of every order. The inner fortress is open."])
	q.rewards = PackedStringArray(["credits_medium", "antiseptic", "bandage"])
	q.reward_text = "Credits, antiseptic and a bandage."
	return q


func _final_lockdown() -> QuestData:
	var q := _quest("if_final_lockdown", "The Final Lockdown",
			"The inner fortress holds the way to Control. Break its defenders, lift the lockdown at all three points and bring down the Captain.",
			[
				_obj("enter_inner", "Enter the inner fortress", T.ENTER_AREA, ["if_inner"]),
				_obj("survive_defenses", "Defeat the elite defenses", T.FLAG, ["iron_fortress_inner_cleared"]),
				_obj("disable_lockdown", "Disable the fortress lockdown", T.FLAG, ["iron_fortress_lockdown_done"]),
				_obj("defeat_captain", "Defeat the Fortress Captain", T.FLAG, ["iron_fortress_captain_down"]),
				_obj("access_control", "Enter the control facility", T.ENTER_AREA, ["if_control"]),
				_obj("supply_depot", "Supply depot: clear the guards and open the depot cache", T.FLAG, ["if_cache_depot_taken"], true),
			])
	q.location_hint = "Inner fortress"
	q.next_quest = &"if_black_site"
	q.start_captions = PackedStringArray(["Red lamps, narrow halls and a door that does not open from this side."])
	q.complete_captions = PackedStringArray(["The control door is open. Whatever the Director built, it is down there."])
	q.rewards = PackedStringArray(["credits_medium", "armor_plate", "health_potion"])
	q.reward_text = "Credits, an armor plate and a medkit."
	return q


func _black_site() -> QuestData:
	var q := _quest("if_black_site", "Black Site",
			"Read the final records, face the Director and end the operation.",
			[
				_obj("enter_control", "Enter the Project Black Site control facility", T.ENTER_AREA, ["if_control_reach"]),
				_obj("read_records", "Read the final Project Black Site records", T.INTERACT, ["if_control_records"]),
				_obj("confront_director", "Confront the Director in the arena", T.ENTER_AREA, ["if_arena"]),
				_obj("defeat_director", "Defeat the Director", T.FLAG, ["iron_fortress_director_defeated"]),
				_obj("send_report", "Send the final transmission", T.INTERACT, ["if_end_console"]),
				_obj("project_archive", "Read the sealed project archive", T.INTERACT, ["if_project_archive"], true),
			])
	q.location_hint = "Control facility"
	q.start_captions = PackedStringArray(["Clean floors, quiet screens. The place where every order ended."])
	q.complete_captions = PackedStringArray(["The operation is over. The island is quiet."])
	q.rewards = PackedStringArray(["credits_medium", "health_potion"])
	q.reward_text = "Credits and a medkit. The campaign is complete."
	return q


func _save(q: QuestData) -> void:
	var errors := q.validate()
	if not errors.is_empty():
		push_error("%s: %s" % [q.id, "; ".join(errors)])
	var path := "%s%s.tres" % [OUT_DIR, q.id]
	var result := ResourceSaver.save(q, path)
	print("wrote ", path, " (", q.objectives.size(), " objectives) result=", result)
