extends SceneTree
## Iron Fortress mission checks (headless): godot --headless --path . -s tests/iron_fortress_missions_check.gd
## Plays the five missions through real interactions and real kills: once in order, once with a different
## order (guards slipped past, puzzles tried wrongly first). Rewards arrive once; optional objectives stay
## optional; both bosses show the boss bar group; `campaign_complete` is set once, and only after the Director.

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const HIT: String = "res://resources/attacks/heavy_1.tres"

var _failures: int = 0
var _checks: int = 0
var _f: IronFortress
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
	for node in [_f, _player, _dummy]:
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
	_f = IronFortress.new()
	root.add_child(_f)
	await _frames(4)


func _use(id: String) -> bool:
	return (_f.parts.nodes[id] as Interactable).interact(_dummy)


func _door(id: String) -> bool:
	return (_f.parts.doors[id] as Interactable).interact(_dummy)


func _enter(area: String) -> void:
	(_f.parts.triggers[area] as AreaTrigger).report_entered()


func _fire(id: String) -> void:
	(_f.parts.triggers[id] as MissionTrigger).fire()


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


func _pickups(item_id: String) -> int:
	var found := 0
	for node in root.find_children("*", "Pickup", true, false):
		var pickup := node as Pickup
		if pickup != null and not pickup.is_queued_for_deletion() and pickup.item != null and String(pickup.item.item_id) == item_id:
			found += 1
	return found


## Brings a spawned enemy down through real hits.
func _kill(enemy: Enemy, limit: int = 700) -> void:
	var attack := load(HIT) as AttackData
	for i in limit:
		if not is_instance_valid(enemy) or enemy.is_dead():
			break
		enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame
	await _frames(4)


func _kill_spawn(id: String) -> void:
	var spawn := _f.parts.fspawns[id] as FortressSpawn
	var enemy := spawn.enemy
	if enemy == null:
		enemy = spawn.trigger()
	await _frames(3)
	if enemy != null:
		await _kill(enemy, 900)


func _comms_pattern() -> void:
	var puzzle := _f.parts.puzzles["comms"] as LabPowerPuzzle
	for i in puzzle.pattern.size():
		if puzzle.pattern[i]:
			puzzle.input(StringName("breaker_%d" % i))
	puzzle.input(&"lever")


# --- scenarios -------------------------------------------------------------------------

func _scenario_in_order() -> void:
	print("-- in order (the guards are defeated)")
	await _fresh()
	_f.enter()
	_check(_qm.is_active(&"if_last_stronghold") and not _qm.is_active(&"if_inside_the_walls"), "entering starts The Last Stronghold only")
	_check(_qm.tracker_title() == "The Last Stronghold", "the HUD tracker shows the mission title (%s)" % _qm.tracker_title())

	# Mission 1: The Last Stronghold
	_fire("if_approach_reach")
	_check(_done(&"if_last_stronghold", "reach_approach"), "reaching the approach completes the first objective")
	var gate_panel := _f.parts.nodes["if_gate_panel"] as Interactable
	_check(not gate_panel.interact(_dummy), "the credential panel is dead until the logbook is read")
	_check(not _door("if_gate_door"), "the main gate is locked without a credential")
	_fire("if_checkpoint_reach")
	_check(_done(&"if_last_stronghold", "investigate_perimeter") and _has("iron_fortress_approach_pass"), "reaching the booth counts as investigating, and the guards can be slipped past")
	await _kill_spawn("if_app_1")
	await _kill_spawn("if_app_2")
	await _kill_spawn("if_app_3")
	_check(_has("iron_fortress_approach_clear"), "defeating all three guards also clears the group")
	_check(_use("if_checkpoint_log") and _done(&"if_last_stronghold", "search_checkpoint"), "the checkpoint log can be searched")
	_check(gate_panel.interact(_dummy) and _has("credential_fortress_gate"), "the panel then grants the gate credential")
	_check(not _qm.is_completed(&"if_last_stronghold"), "the mission is still open before the gate")
	_check(_door("if_gate_door") and _has("door_if_gate_door_open"), "the main gate opens")
	_check(not _has("if_cache_approach_taken") and _qm.is_completed(&"if_last_stronghold"), "The Last Stronghold completes without the optional cache")
	_check(_qm.is_active(&"if_inside_the_walls"), "Inside the Walls follows")
	_use("if_cache_approach")
	_check(_has("if_cache_approach_taken"), "the optional cache can still be opened afterwards")

	# Mission 2: Inside the Walls
	_world.set_flag(&"iron_fortress_waves_cleared")  # the stage's wave step (stage_waves_check plays the real fight)
	var command_panel := _f.parts.nodes["if_command_panel"] as Interactable
	_check(not _door("if_barracks_door"), "the barracks gate is locked before the gate sequence")
	_check(not (_f.parts.nodes["if_barracks_panel"] as Interactable).interact(_dummy), "the barracks panel is dead before the gate sequence")
	_check(_use("if_security_control") and _has("iron_fortress_gate_activated"), "the security console runs the gate activation")
	_check((_f.parts.nodes["if_barracks_panel"] as Interactable).interact(_dummy) and _has("credential_barracks"), "the barracks panel then grants its credential")
	_check(_door("if_barracks_door"), "the barracks gate opens")
	_enter("if_barracks")
	_check(_done(&"if_inside_the_walls", "enter_barracks"), "entering the barracks completes its objective")
	_check(_use("if_armory_terminal") and _use("if_lockdown_relay") and _has("iron_fortress_lockdown_step_a"), "the armory is investigated and the first lockdown stage is released")
	_check(not command_panel.interact(_dummy), "the command key cabinet is locked while the defenders live")
	await _kill_spawn("if_bar_elite_1")
	await _kill_spawn("if_bar_elite_2")
	_check(not _has("iron_fortress_barracks_cleared"), "two of three defenders down is not enough")
	await _kill_spawn("if_bar_heavy_1")
	_check(_has("iron_fortress_barracks_cleared"), "all defenders down")
	_check(command_panel.interact(_dummy) and _has("credential_command_key"), "the cabinet gives up the command key")
	_check(_door("if_command_door"), "the command center door opens")
	_check(_qm.is_completed(&"if_inside_the_walls") and _qm._rewarded.count(&"if_inside_the_walls") == 1, "Inside the Walls completes and pays its reward exactly once")
	_use("if_cache_armory")
	_use("if_patrol_log_1")
	_use("if_patrol_log_2")
	_check(_has("if_cache_armory_taken"), "the optional armory cache can be taken afterwards")

	# Mission 3: Chain of Command
	_check(_qm.is_active(&"if_chain_of_command"), "Chain of Command follows")
	_enter("if_command")
	_fire("if_archive_reach")
	_check(_done(&"if_chain_of_command", "find_archive"), "reaching the archive completes its objective")
	_check(not _use("if_ops_files"), "the operations files are dead until the network is back")
	var comms := _f.parts.puzzles["comms"] as LabPowerPuzzle
	comms.input(&"lever")
	_check(not comms.is_completed() and not _has("iron_fortress_comms_done"), "a premature switch only trips the racks: nothing finishes")
	_comms_pattern()
	_check(comms.is_completed() and _has("iron_fortress_comms_done"), "the right rack pattern and the main switch restore the network")
	_check(not _use("if_director_dossier"), "the Director's file stays locked behind the operational files")
	_check(_use("if_ops_files") and _has("iron_fortress_files_retrieved"), "the operational files can be retrieved")
	_check(_use("if_director_dossier") and _has("iron_fortress_director_known"), "the Director's file reveals the antagonist")
	_check(not _door("if_inner_door"), "the inner door is locked without the inner credential")
	_check((_f.parts.nodes["if_inner_panel"] as Interactable).interact(_dummy) and _has("credential_inner_access"), "the inner panel grants the credential")
	_check(not _qm.is_completed(&"if_chain_of_command"), "the mission is still open while the command guards live")
	await _kill_spawn("if_cmd_elite")
	await _kill_spawn("if_cmd_commander")
	_check(_has("iron_fortress_command_cleared"), "the guard and the commander are down")
	_check(_door("if_inner_door") and _qm.is_completed(&"if_chain_of_command"), "the inner door opens and Chain of Command completes")
	_use("if_orders_1")
	_use("if_orders_2")
	_use("if_orders_3")

	# Mission 4: The Final Lockdown
	_check(_qm.is_active(&"if_final_lockdown"), "The Final Lockdown follows")
	_enter("if_inner")
	_check(not _door("if_control_door"), "the control door is sealed by the lockdown")
	var lockdown := _f.parts.puzzles["lockdown"] as ContainmentOverride
	_use("if_lock_lever")
	_check(not lockdown.is_completed() and not _has("iron_fortress_lockdown_done"), "a premature release pull only complains and finishes nothing")
	_check(_use("if_lock_a") and _use("if_lock_b") and _use("if_lock_c"), "the three lockdown points can be disabled")
	_check(_use("if_lock_lever") and _has("iron_fortress_lockdown_done"), "the release lever lifts the lockdown")
	_check(not _has("iron_fortress_control_open"), "the control door stays sealed while the Captain holds the hall")
	for id in ["if_inn_heavy_1", "if_inn_heavy_2", "if_inn_elite_1", "if_inn_elite_2"]:
		await _kill_spawn(id)
	_check(_has("iron_fortress_inner_cleared"), "the elite defenses are down")
	_enter("if_captain_hall")
	var captain := (_f.parts.fspawns["if_captain"] as FortressSpawn).enemy
	_check(captain != null and captain.is_in_group("boss"), "entering the hall releases the Fortress Captain and puts him on the boss bar")
	await _kill(captain, 1200)
	_check(captain.is_dead(), "the Captain can be defeated through real hits")
	_check(_has("iron_fortress_captain_down") and _has("iron_fortress_control_open"), "his defeat and the lifted lockdown open the control door")
	_check(_pickups("captain_insignia") == 1, "his unique reward lies on the floor once (%d)" % _pickups("captain_insignia"))
	_check(_door("if_control_door"), "the control door opens")
	_check(not _qm.is_completed(&"if_final_lockdown"), "the mission waits for the player to walk in")
	_enter("if_control")
	_check(_qm.is_completed(&"if_final_lockdown"), "entering the control facility completes The Final Lockdown")

	# Mission 5: Black Site
	_check(_qm.is_active(&"if_black_site"), "Black Site follows")
	_check(not _has("campaign_complete"), "the campaign is not complete yet")
	_fire("if_control_reach")
	_check(_use("if_control_records") and _done(&"if_black_site", "read_records"), "the final records can be read")
	_check(not _use("if_end_console"), "the transmission console is dead while the Director lives")
	_enter("if_arena")
	var director := (_f.parts.fspawns["if_director"] as FortressSpawn).enemy
	_check(director != null and director.is_in_group("boss"), "entering the arena releases the Director and puts him on the boss bar")
	_check(_done(&"if_black_site", "confront_director") and not _has("campaign_complete"), "confronting him completes one objective, not the campaign")
	await _kill(director, 1500)
	_check(director.is_dead(), "the Director can be defeated through real hits")
	_check(_has("iron_fortress_director_defeated") and not _has("campaign_complete"), "his defeat sets the flag but the final transmission is still to send")
	_check(_pickups("director_signet") == 1, "his unique reward lies on the floor once (%d)" % _pickups("director_signet"))
	_check(not _qm.is_completed(&"if_black_site"), "Black Site stays open until the report is sent")
	_check(_use("if_end_console") and _has("iron_fortress_ending_read"), "the console sends the final transmission")
	_check(_qm.is_completed(&"if_black_site"), "Black Site completes")
	_check(_has("iron_fortress_region_complete") and _has("campaign_complete"), "the region and the campaign are complete")
	_check(_qm._rewarded.count(&"if_black_site") == 1, "its reward is recorded exactly once")
	_use("if_project_archive")
	_f._on_quest_completed(&"if_black_site")
	_check(_world.to_dict()["flags"].count("campaign_complete") == 1, "completing again changes nothing: the flag exists once")
	_check(_pickups("director_signet") == 1 and _pickups("captain_insignia") == 1, "no unique reward was duplicated")


func _scenario_other_order() -> void:
	print("-- other order (guards slipped past, puzzles tried the wrong way first)")
	await _fresh()
	# the arena-era first mission is still open: the tracker must show the region's own mission first
	_qm.completed.erase(&"first_signal")
	_qm.start_quest(&"first_signal")
	var regions := root.get_node("RegionManager")
	regions.current_region_id = &"iron_fortress"
	_f.enter()
	_check(_qm.is_active(&"first_signal") and _qm.tracker_title() == "The Last Stronghold", "an older open mission does not outrank the fortress mission in the tracker (%s)" % _qm.tracker_title())
	regions.current_region_id = &"outpost_17"
	_fire("if_checkpoint_reach")
	_check(_has("iron_fortress_approach_pass") and not (_f.parts.fspawns["if_app_1"] as FortressSpawn).is_cleared(), "the guards are slipped past, none is defeated")
	_use("if_checkpoint_log")
	(_f.parts.nodes["if_gate_panel"] as Interactable).interact(_dummy)
	_fire("if_approach_reach")
	_door("if_gate_door")
	_check(_qm.is_completed(&"if_last_stronghold"), "The Last Stronghold completes without a single kill, in a different order")
	# puzzles can be tried before their missions: wrong input never blocks
	var comms := _f.parts.puzzles["comms"] as LabPowerPuzzle
	comms.input(&"breaker_0")
	comms.input(&"lever")
	_check(not comms.is_completed(), "a wrong rack setting and a pull finish nothing")
	_comms_pattern()
	_check(comms.is_completed(), "the pattern can still be set right afterwards")
	_check(_use("if_ops_files") and _use("if_director_dossier"), "the files and the dossier open once the network is back")
	var lockdown := _f.parts.puzzles["lockdown"] as ContainmentOverride
	_use("if_lock_a")
	_use("if_lock_lever")
	_check(not lockdown.is_completed(), "a pull with one point disabled is refused")
	_use("if_lock_b")
	_use("if_lock_c")
	_use("if_lock_lever")
	_check(lockdown.is_completed() and _has("iron_fortress_lockdown_done"), "the lockdown still comes off")
	_check(not _has("iron_fortress_control_open"), "the control door needs the Captain as well")
	_check(not _has("campaign_complete"), "nothing here ends the campaign early")
