extends SceneTree
## Research Complex mission checks (headless): godot --headless --path . -s tests/research_complex_missions_check.gd
## Plays the four missions through real interactions and real kills: once in order (guards defeated),
## once with a different order (guards slipped past, steps shuffled). Rewards arrive once; optional
## objectives stay optional; the elite shows the boss bar group; wrong puzzle input never blocks.

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const HIT: String = "res://resources/attacks/heavy_1.tres"

var _failures: int = 0
var _checks: int = 0
var _rc: ResearchComplex
var _player: Player
var _world: Node
var _qm: Node
var _dummy: Node3D


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
	_world = root.get_node_or_null("WorldState")
	_qm = root.get_node_or_null("QuestManager")
	await _scenario_in_order()
	await _scenario_other_order()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _fresh() -> void:
	for node in [_rc, _player, _dummy]:
		if is_instance_valid(node):
			(node as Node).free()
	_world.from_dict({})
	var manager := root.get_node_or_null("RegionManager")
	if manager != null:
		manager.call("reset")  # forgets every claimed id from the previous scenario
	_qm.call("reset", false)
	_qm.set("intro_done", true)
	_qm.set("mission_autosave", false)
	_qm.active.clear()
	if not _qm.completed.has(&"first_signal"):
		_qm.completed.append(&"first_signal")
	Enemy.active_patrollers = 0
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_dummy = Node3D.new()
	root.add_child(_dummy)
	_rc = ResearchComplex.new()
	root.add_child(_rc)
	await _frames(4)


func _use(id: String) -> bool:
	return (_rc.parts.nodes[id] as Interactable).interact(_dummy)


func _door(id: String) -> bool:
	return (_rc.parts.doors[id] as Interactable).interact(_dummy)


func _enter(area: String) -> void:
	(_rc.parts.triggers[area] as AreaTrigger).report_entered()


func _fire(id: String) -> void:
	(_rc.parts.triggers[id] as MissionTrigger).fire()


func _has(flag: String) -> bool:
	return _world.has_flag(StringName(flag))


func _done(quest_id: StringName, objective_id: String) -> bool:
	var quest: QuestData = _qm.get_quest(quest_id)
	for i in quest.objectives.size():
		if String(quest.objectives[i].id) == objective_id:
			return bool(_qm.active[quest_id]["done"][i]) if _qm.active.has(quest_id) else _qm.is_completed(quest_id)
	return false


func _count(item_id: String) -> int:
	return _player.inventory.count_of(item_id)


## Brings a spawned enemy down through real hits.
func _kill(enemy: Enemy, limit: int = 600) -> void:
	var attack := load(HIT) as AttackData
	for i in limit:
		if not is_instance_valid(enemy) or enemy.is_dead():
			break
		enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame
	await _frames(4)


func _kill_spawn(id: String) -> void:
	var spawn := _rc.parts.spawns[id] as FacilityEnemySpawn
	var enemy := spawn.enemy
	if enemy == null:
		enemy = spawn.trigger()
	await _frames(3)
	if enemy != null:
		await _kill(enemy)


func _lab_pattern() -> void:
	var puzzle := _rc.parts.puzzles["lab_power"] as LabPowerPuzzle
	for i in puzzle.pattern.size():
		if puzzle.pattern[i]:
			puzzle.input(StringName("breaker_%d" % i))
	puzzle.input(&"lever")


# --- scenarios -------------------------------------------------------------------------

func _scenario_in_order() -> void:
	print("-- in order (the guards are defeated)")
	await _fresh()
	_rc.enter()
	_check(_qm.is_active(&"rc_restricted_zone") and not _qm.is_active(&"rc_silent_records"), "entering starts The Restricted Zone only")
	# The tracker only shows the stage the player is in; this test enters the region directly, so say so.
	root.get_node("RegionManager").current_region_id = &"research_complex"
	_check(_qm.tracker_title() == "The Restricted Zone", "the HUD tracker shows the mission title (%s)" % _qm.tracker_title())

	# Mission 1: The Restricted Zone
	_fire("rc_entrance")
	_check(_done(&"rc_restricted_zone", "find_entrance"), "reaching the entrance completes the first objective")
	var panel := _rc.parts.nodes["rc_checkpoint_panel"] as Interactable
	_check(not panel.interact(_dummy), "the keycard rack is dead until the logbook is read")
	_check(not _door("rc_admin_door"), "the admin door is locked without a credential")
	await _kill_spawn("rc_guard_1")
	await _kill_spawn("rc_guard_2")
	_check(not _done(&"rc_restricted_zone", "perimeter_guards"), "two of three guards down is not enough")
	await _kill_spawn("rc_guard_3")
	_check(_has("research_complex_perimeter_clear") and _done(&"rc_restricted_zone", "perimeter_guards"), "defeating all three guards counts as dealing with them")
	_check(_use("rc_checkpoint_log") and _done(&"rc_restricted_zone", "search_checkpoint"), "the checkpoint logbook can be searched")
	_check(panel.interact(_dummy) and _has("credential_admin"), "the keycard rack then grants the admin credential")
	_check(_done(&"rc_restricted_zone", "get_credential") and not _qm.is_completed(&"rc_restricted_zone"), "the credential completes its objective, the mission is still open")
	_check(_door("rc_admin_door") and _has("door_rc_admin_door_open"), "the admin door opens")
	_check(not _has("rc_cache_perimeter_taken"), "the optional cache has not been taken, yet the mission can finish")
	_check(_qm.is_completed(&"rc_restricted_zone"), "The Restricted Zone completes without the optional cache")
	_check(_qm.is_active(&"rc_silent_records"), "Silent Records follows")
	_use("rc_cache_perimeter")
	_check(_has("rc_cache_perimeter_taken"), "the optional cache can still be opened afterwards")

	# Mission 2: Silent Records
	_enter("rc_archive")
	_check(_done(&"rc_silent_records", "find_archive"), "entering the archive completes its objective")
	_check(not _use("rc_archive_breaker"), "the archive breaker is dead while security is offline")
	_check(not _use("rc_medical_panel"), "the medical panel is dead while security is offline")
	_check(_use("rc_security_console") and _has("research_complex_security_online"), "the security console restores the network")
	_check(_use("rc_archive_breaker") and _has("research_complex_archive_power"), "the archive breaker then works")
	_check(not _qm.is_completed(&"rc_silent_records"), "the mission is still open")
	_check(_use("rc_archive_terminal") and _has("research_complex_records_retrieved"), "the powered archive terminal gives up its records")
	_check(_use("rc_medical_panel") and _has("credential_medical"), "the medical panel grants the medical credential")
	_check(_door("rc_medical_door"), "the medical door opens")
	_enter("rc_medical_wing")
	_check(_use("rc_medical_evidence"), "the trial notes can be read")
	_rc.begin_ambush()
	_check(_rc.ambush_released and not (_rc.parts.spawns["rc_subject_med_1"] as FacilityEnemySpawn).enemy, "the ambush gives a warning before anyone is released")
	await create_timer(ResearchComplex.WARNING_SECONDS + 0.3).timeout
	var subject := (_rc.parts.spawns["rc_subject_med_1"] as FacilityEnemySpawn).enemy
	_check(subject != null, "after the warning the first subject is released")
	await _kill_spawn("rc_subject_med_1")
	await _kill_spawn("rc_subject_med_2")
	_check(_has("research_complex_ambush_cleared"), "clearing both subjects sets the optional flag")
	_check(_qm.is_completed(&"rc_silent_records"), "Silent Records completes")

	# Mission 3: Containment Breach
	_check(_qm.is_active(&"rc_containment_breach"), "Containment Breach follows")
	_enter("rc_containment")
	_check(not _door("rc_elite_door"), "the elite's door is sealed before the override")
	var puzzle := _rc.parts.puzzles["containment"] as ContainmentOverride
	_use("rc_override_lever")
	_check(not puzzle.is_completed() and not _has("research_complex_containment_done"), "a premature lever pull only complains and finishes nothing")
	_check(_use("rc_override_a") and _use("rc_override_b") and _use("rc_override_c"), "the three override terminals can be activated")
	_check(_use("rc_override_lever") and _has("research_complex_containment_done"), "the lever releases the override")
	_check(_door("rc_elite_door"), "the elite's door opens after the override")
	_check(not _qm.is_completed(&"rc_containment_breach"), "the mission is still open")
	for id in ["rc_subject_cell_1", "rc_subject_cell_2", "rc_subject_cell_3"]:
		await _kill_spawn(id)
	_check(_has("research_complex_subjects_cleared") and _done(&"rc_containment_breach", "survive_subjects"), "the cell subjects are cleared")
	var lab_panel := _rc.parts.nodes["rc_lab_panel"] as Interactable
	_check(not lab_panel.interact(_dummy), "the laboratory panel is dead while the elite lives")
	_enter("rc_elite_chamber")
	var elite := (_rc.parts.spawns["rc_elite_subject"] as FacilityEnemySpawn).enemy
	_check(elite != null and elite.is_in_group("boss"), "entering the chamber releases Subject Zero and puts him on the boss bar")
	await _kill(elite, 900)
	_check(elite.is_dead(), "Subject Zero can be defeated through real hits")
	_check(_has("research_complex_elite_down") and _done(&"rc_containment_breach", "defeat_elite"), "his defeat sets the flag")
	_check(_use("rc_incident_report"), "the incident report can be recovered")
	_check(_qm.is_completed(&"rc_containment_breach"), "Containment Breach completes")
	_check(_count("upgrade_kit_armor") == 1, "its reward arrives once (%d)" % _count("upgrade_kit_armor"))

	# Mission 4: Project Black Site
	_check(_qm.is_active(&"rc_project_black_site"), "Project Black Site follows")
	_check(not _door("rc_lab_door"), "the laboratory door is locked without the lab credential")
	_check(lab_panel.interact(_dummy) and _has("credential_lab"), "with the elite down the panel grants the lab credential")
	_check(_door("rc_lab_door"), "the laboratory door opens")
	_enter("rc_lab")
	_check(_done(&"rc_project_black_site", "access_lab"), "entering the laboratory completes its objective")
	_check(_rc.commander != null and is_instance_valid(_rc.commander), "the Facility Commander is released in the laboratory")
	var lab := _rc.parts.puzzles["lab_power"] as LabPowerPuzzle
	lab.input(&"breaker_1")
	lab.input(&"lever")
	_check(not lab.is_completed(), "a wrong pattern with the lever does not complete the puzzle")
	_check(lab.breakers.all(func(b: bool) -> bool: return not b), "and trips the breakers off without losing anything")
	_lab_pattern()
	_check(lab.is_completed() and _has("research_complex_lab_power_done"), "the right pattern and the lever restore laboratory power")
	_check(_door("rc_final_door"), "the final chamber door opens with power")
	await _kill_spawn("rc_lab_heavy_1")
	await _kill_spawn("rc_lab_heavy_2")
	_check(not _has("research_complex_lab_security_cleared"), "the Commander still counts as laboratory security")
	await _kill(_rc.commander, 600)
	_check(_rc.commander.is_dead() and _has("research_complex_lab_security_cleared"), "defeating the Commander clears the laboratory")
	_enter("rc_final_chamber")
	_check(not _door("rc_service_hatch"), "the service hatch stays sealed before the data is retrieved")
	_check(_use("rc_black_site_data") and _has("research_complex_next_lead"), "the Project Black Site data can be retrieved")
	_check(_door("rc_service_hatch") and _has("door_rc_service_hatch_open"), "the service hatch then opens")
	_check(not _qm.is_completed(&"rc_project_black_site"), "the mission is still open until the way out is reached")
	_enter("rc_sealed_exit")
	_check(_qm.is_completed(&"rc_project_black_site"), "reaching the sealed exit completes Project Black Site")
	_check(_has("research_complex_region_complete"), "completing the last mission sets the region complete flag")
	_check(_count("upgrade_kit_weapon") == 1, "its reward arrives once (%d)" % _count("upgrade_kit_weapon"))
	var done_count: int = _qm.completed.size()
	_enter("rc_sealed_exit")
	await _frames(2)
	_check(_qm.completed.size() == done_count and _count("upgrade_kit_weapon") == 1, "entering the exit again changes nothing")


func _scenario_other_order() -> void:
	print("-- other order (the guards are slipped past, steps shuffled)")
	await _fresh()
	_rc.enter()
	# credentials and doors reached through their panels and terminals, but guards avoided
	_fire("rc_entrance")  # strict stage order: the entrance is the first step, so it comes first
	_fire("rc_checkpoint_reach")
	_check(_has("research_complex_perimeter_pass") and _done(&"rc_restricted_zone", "perimeter_guards"), "reaching the checkpoint counts as slipping past the guards")
	_check(_use("rc_checkpoint_log"), "searching works")
	_check((_rc.parts.nodes["rc_checkpoint_panel"] as Interactable).interact(_dummy), "the rack grants the credential")
	_check(_door("rc_admin_door"), "the door opens")
	_fire("rc_entrance")
	_check(_qm.is_completed(&"rc_restricted_zone"), "Mission 1 completes with the objectives done in a different order")
	# Mission 2 shuffled: evidence and medical wing before the archive
	_enter("rc_medical_wing")
	_check(_use("rc_security_console") and _use("rc_medical_panel"), "medical access is reachable first")
	_check(_use("rc_medical_evidence"), "the evidence can be read before the archive")
	_enter("rc_archive")
	_check(_use("rc_archive_breaker") and _use("rc_archive_terminal"), "the archive follows")
	_check(_qm.is_completed(&"rc_silent_records"), "Mission 2 completes in a different order")
	_check(not _has("research_complex_ambush_cleared") and _qm.is_completed(&"rc_silent_records"), "the optional ambush objective was never required")
	# a premature visit to the sealed exit changes nothing
	_enter("rc_sealed_exit")
	_check(not _qm.is_completed(&"rc_project_black_site") and not _has("research_complex_region_complete"), "reaching the exit early does not finish the campaign")
