extends SceneTree
## Writes the four Research Complex quests: godot --headless --path . -s tools/gen_research_complex_quests.gd
## Objective ids and event targets must match scripts/regions/research_complex/*.gd (the tests check this).
## Flag and interaction ids are underscore-only: WorldState drops anything else when a save is loaded.

const OUT_DIR: String = "res://resources/quests/research_complex/"
const T = ObjectiveData.Type


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_restricted_zone())
	_save(_silent_records())
	_save(_containment_breach())
	_save(_project_black_site())
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


func _restricted_zone() -> QuestData:
	var q := _quest("rc_restricted_zone", "The Restricted Zone",
			"The route table from the experimental site ends at a fenced facility in the north of the Blackwood. Get through its perimeter and into the administration wing.",
			[
				_obj("find_entrance", "Find the facility entrance", T.ENTER_AREA, ["rc_entrance"]),
				_obj("perimeter_guards", "Deal with the perimeter guards: defeat them or slip past", T.FLAG, ["research_complex_perimeter_pass"]),
				_obj("search_checkpoint", "Search the security checkpoint", T.INTERACT, ["rc_checkpoint_log"]),
				_obj("get_credential", "Take an administration keycard", T.FLAG, ["credential_admin"]),
				_obj("unlock_admin", "Unlock the administration wing", T.FLAG, ["door_rc_admin_door_open"]),
				_obj("perimeter_cache", "Find the supply cache off the road", T.FLAG, ["rc_cache_perimeter_taken"], true),
			])
	q.location_hint = "Research perimeter"
	q.next_quest = &"rc_silent_records"
	q.start_captions = PackedStringArray(["A fence, a hut and a door that has not been opened in weeks."])
	q.complete_captions = PackedStringArray(["The administration wing is open. It smells of old paper and dust."])
	q.rewards = PackedStringArray(["credits_medium", "bandage", "armor_patch"])
	q.reward_text = "Credits, a bandage and an armor patch."
	return q


func _silent_records() -> QuestData:
	var q := _quest("rc_silent_records", "Silent Records",
			"Someone kept careful records here. Bring the security network back up, open the archive and follow the paper trail into the medical wing.",
			[
				_obj("find_archive", "Find the research archive", T.ENTER_AREA, ["rc_archive"]),
				_obj("restore_security", "Restore the security network", T.FLAG, ["research_complex_security_online"]),
				_obj("restore_archive_power", "Restore power to the archive terminal", T.FLAG, ["research_complex_archive_power"]),
				_obj("retrieve_records", "Retrieve the classified records", T.FLAG, ["research_complex_records_retrieved"]),
				_obj("medical_access", "Get a medical access credential", T.FLAG, ["credential_medical"]),
				_obj("enter_medical", "Investigate the medical wing", T.ENTER_AREA, ["rc_medical_wing"]),
				_obj("find_evidence", "Find evidence of human experimentation", T.INTERACT, ["rc_medical_evidence"]),
				_obj("survive_ambush", "Survive what is in the ward", T.FLAG, ["research_complex_ambush_cleared"], true),
				_obj("admin_cache", "Find the cache in the conference room", T.FLAG, ["rc_cache_admin_taken"], true),
				_obj("optional_docs", "Read the staff and ward papers", T.FLAG,
						["doc_rc_staff_memo_found", "doc_rc_exam_note_found", "doc_rc_ward_notice_found"], true, "Papers"),
			])
	q.location_hint = "Administration and medical wings"
	q.next_quest = &"rc_containment_breach"
	q.start_captions = PackedStringArray(["The lights are dead. The records are not."])
	q.complete_captions = PackedStringArray(["Thirty-one subjects. None of them asked to be here."])
	q.rewards = PackedStringArray(["credits_medium", "antiseptic", "electronics"])
	q.reward_text = "Credits, antiseptic and electronics."
	return q


func _containment_breach() -> QuestData:
	var q := _quest("rc_containment_breach", "Containment Breach",
			"The cells below the medical wing were opened from inside the system, not broken. Find out who ordered it and what is still locked in.",
			[
				_obj("enter_containment", "Enter the containment sector", T.ENTER_AREA, ["rc_containment"]),
				_obj("restore_emergency", "Restore emergency access: run the containment override", T.FLAG, ["research_complex_containment_done"]),
				_obj("survive_subjects", "Survive the experimental subjects", T.FLAG, ["research_complex_subjects_cleared"]),
				_obj("enter_chamber", "Investigate the damaged holding chamber", T.ENTER_AREA, ["rc_elite_chamber"]),
				_obj("defeat_elite", "Defeat Subject Zero", T.FLAG, ["research_complex_elite_down"]),
				_obj("incident_report", "Recover the containment incident report", T.INTERACT, ["rc_incident_report"]),
				_obj("override_notes", "Read the technician notes on the override", T.FLAG, ["doc_rc_override_notes_found"], true),
				_obj("medical_cache", "Find the cache in the medical storage", T.FLAG, ["rc_cache_medical_taken"], true),
			])
	q.location_hint = "Containment sector"
	q.next_quest = &"rc_project_black_site"
	q.start_captions = PackedStringArray(["The cells are open. Whatever was inside did not stay inside."])
	q.complete_captions = PackedStringArray(["Not an accident. An order, signed with a title."])
	q.rewards = PackedStringArray(["credits_medium", "credits_medium", "upgrade_kit_armor"])
	q.reward_text = "Credits and an armor upgrade kit."
	return q


func _project_black_site() -> QuestData:
	var q := _quest("rc_project_black_site", "Project Black Site",
			"The laboratory holds the data the whole operation was built around. Restore its power, reach the final chamber and get out with what you find.",
			[
				_obj("access_lab", "Reach the central laboratory", T.ENTER_AREA, ["rc_lab"]),
				_obj("restore_lab_power", "Restore laboratory power: match the breakers", T.FLAG, ["research_complex_lab_power_done"]),
				_obj("lab_security", "Defeat the laboratory security", T.FLAG, ["research_complex_lab_security_cleared"]),
				_obj("reach_final", "Reach the final research chamber", T.ENTER_AREA, ["rc_final_chamber"]),
				_obj("retrieve_data", "Retrieve the Project Black Site data", T.INTERACT, ["rc_black_site_data"]),
				_obj("learn_lead", "Learn where the data leads", T.FLAG, ["research_complex_next_lead"]),
				_obj("open_hatch", "Open the service hatch", T.FLAG, ["door_rc_service_hatch_open"]),
				_obj("reach_exit", "Escape through the underground exit", T.ENTER_AREA, ["rc_sealed_exit"]),
				_obj("lab_papers", "Read the laboratory papers", T.FLAG, ["doc_rc_lab_notes_found", "doc_rc_director_order_found"], true, "Papers"),
			])
	q.location_hint = "Central laboratory"
	q.start_captions = PackedStringArray(["The last door in the facility needs the power on."])
	q.complete_captions = PackedStringArray(["One destination in the route table. The command, behind the iron gate."])
	q.rewards = PackedStringArray(["credits_medium", "credits_medium", "upgrade_kit_weapon", "electronics"])
	q.reward_text = "Credits, a weapon upgrade kit and electronics."
	q.show_mission_banner = false
	return q


func _save(q: QuestData) -> void:
	var errors := q.validate()
	if not errors.is_empty():
		push_error("%s invalid: %s" % [q.id, "; ".join(errors)])
	var path := OUT_DIR + String(q.id) + ".tres"
	var err := ResourceSaver.save(q, path)
	print("%s -> %s (%d)" % [q.id, path, err])
