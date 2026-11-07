extends SceneTree
## Writes the three Blackwood quests: godot --headless --path . -s tools/gen_blackwood_quests.gd
## Objective ids and event targets must match scripts/regions/blackwood/blackwood.gd.

const OUT_DIR: String = "res://resources/quests/blackwood/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_into_the_blackwood())
	_save(_ghost_frequency())
	_save(_experimental_site())
	quit()


func _obj(id: String, text: String, type: ObjectiveData.Type, targets: Array, count: int = 0, optional: bool = false, label: String = "") -> ObjectiveData:
	var o := ObjectiveData.new()
	o.id = StringName(id)
	o.text = text
	o.type = type
	o.targets = PackedStringArray(targets)
	o.count = count
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


func _into_the_blackwood() -> QuestData:
	var q := _quest("into_the_blackwood", "Into the Blackwood",
			"The coast trail ends at a wall of jungle. A military track leads in. Follow it and find out what happened to the patrol that took it.",
			[
				_obj("enter_blackwood", "Enter the Blackwood", ObjectiveData.Type.ENTER_AREA, ["blackwood_jungle_entrance"]),
				_obj("follow_trail", "Follow the military trail", ObjectiveData.Type.ENTER_AREA, ["blackwood_trail"]),
				_obj("check_patrol_gear", "Investigate the abandoned patrol equipment", ObjectiveData.Type.INTERACT, ["bw_patrol_gear"]),
				_obj("survive_ambush", "Survive the ambush", ObjectiveData.Type.FLAG, ["blackwood_ambush_cleared"]),
				_obj("find_camp", "Find the abandoned patrol camp", ObjectiveData.Type.ENTER_AREA, ["blackwood_patrol_camp"]),
				_obj("camp_logs", "Read the patrol logs", ObjectiveData.Type.FLAG,
						["doc_bw_log_patrol_1_found", "doc_bw_log_patrol_2_found"], 0, true, "Logs"),
			])
	q.location_hint = "Blackwood"
	q.next_quest = &"ghost_frequency"
	q.start_captions = PackedStringArray(["The trail goes in. The patrol never came out."])
	q.complete_captions = PackedStringArray(["A hand-drawn map in the camp marks a signal tower deeper in."])
	q.rewards = PackedStringArray(["credits_medium", "bandage", "bandage"])
	q.reward_text = "Credits and field dressings."
	return q


func _ghost_frequency() -> QuestData:
	var q := _quest("ghost_frequency", "Ghost Frequency",
			"A transmitter is still sending from somewhere in the trees. Tune the hidden station and listen.",
			[
				_obj("find_station", "Locate the hidden communications station", ObjectiveData.Type.ENTER_AREA, ["blackwood_comms_station"]),
				_obj("read_frequency", "Read the technician's frequency log", ObjectiveData.Type.INTERACT, ["bw_log_frequency"]),
				_obj("restore_station", "Restore the station: tune the three dials", ObjectiveData.Type.FLAG, ["blackwood_comms_power"]),
				_obj("read_transmissions", "Investigate the encrypted transmissions", ObjectiveData.Type.FLAG, ["blackwood_transmissions_read"]),
				_obj("recover_data", "Recover the research data", ObjectiveData.Type.INTERACT, ["bw_data_recorder"]),
				_obj("black_site_link", "Find the connection to Project Black Site", ObjectiveData.Type.FLAG, ["blackwood_black_site_link"]),
				_obj("tech_notes", "Read the technician's notes", ObjectiveData.Type.FLAG, ["doc_bw_log_tech_notes_found"], 0, true),
			])
	q.location_hint = "Hidden station"
	q.next_quest = &"experimental_site"
	q.start_captions = PackedStringArray(["Static, then a voice counting numbers. Find where it comes from."])
	q.complete_captions = PackedStringArray(["Black Site. The same name as the file in Outpost 17."])
	q.rewards = PackedStringArray(["credits_medium", "armor_plate", "electronics"])
	q.reward_text = "Credits, an armor plate and electronics."
	return q


func _experimental_site() -> QuestData:
	var q := _quest("experimental_site", "The Experimental Site",
			"The recovered data points to a testing site behind the research perimeter. Get in, find out what they did there and open the way on.",
			[
				_obj("reach_perimeter", "Reach the research perimeter", ObjectiveData.Type.ENTER_AREA, ["blackwood_research_perimeter"]),
				_obj("open_gate", "Open the concealed gate", ObjectiveData.Type.INTERACT, ["bw_gate_panel"]),
				_obj("find_site", "Find the experimental testing site", ObjectiveData.Type.ENTER_AREA, ["blackwood_testing_site"]),
				_obj("examine_equipment", "Investigate the experimental equipment", ObjectiveData.Type.INTERACT,
						["bw_test_equipment_1", "bw_test_equipment_2"], 0, false, "Equipment"),
				_obj("find_evidence", "Find evidence of human experimentation", ObjectiveData.Type.INTERACT, ["bw_log_experiment_1"]),
				_obj("defeat_defenders", "Defeat the site defenders", ObjectiveData.Type.FLAG, ["blackwood_site_defenders_cleared"]),
				_obj("unlock_access", "Unlock the way to the Research Complex", ObjectiveData.Type.FLAG, ["blackwood_research_complex_access"]),
				_obj("find_hatch", "Find the concealed underground hatch", ObjectiveData.Type.INTERACT, ["bw_hatch"], 0, true),
				_obj("subject_list", "Read the subject list", ObjectiveData.Type.FLAG, ["doc_bw_log_subject_list_found"], 0, true),
			])
	q.location_hint = "Experimental site"
	q.start_captions = PackedStringArray(["Fresh tire tracks. Somebody still drives to the testing site."])
	q.complete_captions = PackedStringArray(["The research facility is open. Whatever they did here, it started below."])
	q.rewards = PackedStringArray(["credits_medium", "credits_medium", "upgrade_kit_weapon", "blackwood_ghost_charm"])
	q.reward_text = "Credits, a weapon upgrade kit and the Ghost Charm."
	q.show_mission_banner = false
	return q


func _save(q: QuestData) -> void:
	var errors := q.validate()
	if not errors.is_empty():
		push_error("%s invalid: %s" % [q.id, "; ".join(errors)])
	var path := OUT_DIR + String(q.id) + ".tres"
	var err := ResourceSaver.save(q, path)
	print("%s -> %s (%d)" % [q.id, path, err])
