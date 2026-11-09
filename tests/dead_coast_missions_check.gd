extends SceneTree
## Dead Coast mission checks (headless): godot --headless --path . -s tests/dead_coast_missions_check.gd
## Plays the three missions through real interactions (and real kills), once in order and once with the
## later missions done first. Rewards once, optional objectives optional, state survives a save round trip.

const SCENE: String = "res://scenes/regions/DeadCoast_content.tscn"
const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"

var _failures: int = 0
var _checks: int = 0
var _region: DeadCoast
var _player: Player
var _world: Node
var _qm: Node
var _progression: Node
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
	_progression = root.get_node_or_null("Progression")
	await _scenario_in_order()
	await _scenario_out_of_order()
	await _scenario_save_round_trip()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Fresh world, fresh quests, a player, and a rebuilt region.
func _fresh() -> void:
	if is_instance_valid(_region):
		_region.free()
	if is_instance_valid(_player):
		_player.free()
	if is_instance_valid(_dummy):
		_dummy.free()
	_world.from_dict({})
	_qm.call("reset", false)
	_qm.set("intro_done", true)
	_qm.set("mission_autosave", false)
	# The Dead Coast is reached after Outpost 17: its mission is finished by then, so the tracker follows the coast.
	_qm.active.clear()
	if not _qm.completed.has(&"first_signal"):
		_qm.completed.append(&"first_signal")
	Enemy.active_patrollers = 0
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_dummy = Node3D.new()
	root.add_child(_dummy)
	_region = (load(SCENE) as PackedScene).instantiate() as DeadCoast
	root.add_child(_region)
	await _frames(4)


func _use(id: String) -> bool:
	var item := _region.content.nodes[id] as Interactable
	return item.interact(_dummy)


func _enter(area: StringName) -> void:
	(_region.triggers[area] as AreaTrigger).report_entered()


func _done(quest_id: StringName, objective_id: String) -> bool:
	var quest: QuestData = _qm.get_quest(quest_id)
	for i in quest.objectives.size():
		if String(quest.objectives[i].id) == objective_id:
			return bool(_qm.active[quest_id]["done"][i]) if _qm.active.has(quest_id) else _qm.is_completed(quest_id)
	return false


func _kill_group(id: String) -> void:
	var group := _region.content.patrols[id] as PatrolGroup
	var attack := load("res://resources/attacks/heavy_1.tres") as AttackData
	if not group.spawned:
		group.spawn()
	await _frames(3)
	for enemy in group.enemies:
		for i in 14:
			if is_instance_valid(enemy) and not enemy.is_dead():
				enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, 2.0))
				await physics_frame
	await _frames(4)


func _count(item_id: String) -> int:
	return _player.inventory.count_of(item_id)


func _scenario_in_order() -> void:
	print("-- in order")
	await _fresh()
	var xp_before: int = _progression.progress.xp if _progression != null else 0
	_region.enter()
	_check(_qm.is_active(&"dc_wreckage"), "entering the region starts Wreckage")
	_check(not _qm.is_active(&"dc_silent_checkpoint") and not _qm.is_active(&"dc_lost_cargo"), "only the first mission is active")
	_check(_qm.tracker_title() == "Wreckage", "the HUD tracker shows the mission title (%s)" % _qm.tracker_title())
	_check(_qm.tracker_objective().length() > 0, "the tracker shows the current objective (%s)" % _qm.tracker_objective())

	# Mission 1: Wreckage
	_enter(&"dc_wreckage_beach")
	_check(_done(&"dc_wreckage", "enter_dead_coast"), "entering the beach completes the first objective")
	_check(_use("dead_coast_wreck_hull"), "the hull can be inspected")
	_check(_use("dead_coast_radio_wreck"), "the ship radio can be used")
	_check(_use("dead_coast_log_wreck_manifest"), "the manifest can be read")
	_check(not _qm.is_completed(&"dc_wreckage"), "not complete while a patrol and the device remain")
	await _kill_group("dead_coast_beach")
	_check(_world.has_flag(&"patrol_dead_coast_beach_cleared"), "killing the beach squad sets its flag")
	_check(_done(&"dc_wreckage", "defeat_beach_patrols"), "that completes 'Defeat the hostile patrols'")
	_check(not _qm.is_completed(&"dc_wreckage"), "still open: the data device is missing")
	_check(_use("dead_coast_data_device"), "the data device can be recovered")
	await _frames(3)
	_check(_qm.is_completed(&"dc_wreckage"), "Wreckage completes with the optional cache untouched")
	_check(not _world.has_flag(&"dead_coast_cache_wreck_taken"), "the optional lifeboat cache is still closed")
	_check(_count("upgrade_kit_weapon") == 1, "the reward arrives once in the inventory (%d)" % _count("upgrade_kit_weapon"))
	_check(_qm.is_active(&"dc_silent_checkpoint"), "The Silent Checkpoint starts by itself")
	if _progression != null:
		_check(int(_progression.progress.xp) > xp_before or int(_progression.progress.level) > 1, "completing a mission awards XP")

	# Mission 2: The Silent Checkpoint, in a different order than the quest text
	_world.set_flag(&"dead_coast_waves_cleared")  # the stage's wave step (stage_waves_check plays the real fight)
	var gate := _region.content.nodes["dc_gate"] as Door
	_check(gate.locked, "the barrier is locked before the pass")
	_check(_use("dead_coast_checkpoint_terminal"), "the checkpoint terminal can be read")
	_check(_use("dead_coast_guard_pass"), "the guard pass can be taken")
	_check(_world.has_flag(&"dead_coast_route_pass"), "taking the pass sets dead_coast_route_pass")
	_check(not gate.locked, "the barrier unlocks with the pass")
	_check(gate.interact(_dummy) and gate.is_open, "and the barrier opens")
	_check(_use("dead_coast_log_checkpoint_orders"), "the posted orders can be read")
	_enter(&"dc_checkpoint")
	_check(not _qm.is_completed(&"dc_silent_checkpoint"), "not complete until the defenders are down")
	await _kill_group("dead_coast_checkpoint")
	await _frames(3)
	_check(_qm.is_completed(&"dc_silent_checkpoint"), "The Silent Checkpoint completes")
	_check(_count("armor_patch") >= 1, "its armor patch reward arrives (%d)" % _count("armor_patch"))
	_check(_qm.is_active(&"dc_lost_cargo"), "Lost Cargo starts by itself")

	# Mission 3: Lost Cargo
	var exit_locked: bool = not _world.has_flag(DeadCoast.COMPLETE_FLAG)
	_check(exit_locked, "the way to Blackwood is still sealed")
	_check(_use("dead_coast_trail_markers"), "the drag marks can be followed")
	_enter(&"dc_cove")
	_check(_use("dead_coast_cargo_a") and _use("dead_coast_cargo_b"), "two hidden containers opened")
	_check(not _done(&"dc_lost_cargo", "find_containers"), "two of three is not enough")
	_check(_use("dead_coast_cargo_c"), "the third container opened")
	_check(_done(&"dc_lost_cargo", "find_containers"), "three of three completes the container objective")
	_check(_use("dead_coast_cargo_gear"), "the sealed equipment case recovered")
	_check(not _qm.is_completed(&"dc_lost_cargo"), "not complete before the Black Site link is found")
	_check(_use("dead_coast_log_black_site_link"), "the consignment sheet read")
	await _frames(3)
	_check(_qm.is_completed(&"dc_lost_cargo"), "Lost Cargo completes (optional watchpoint, depot and camp untouched)")
	_check(_world.has_flag(DeadCoast.COMPLETE_FLAG), "completion unlocks the way to Blackwood")
	_check(_count("coastal_weapon_part") == 1, "the unique weapon part arrives once")
	# nothing pays twice
	_use("dead_coast_log_black_site_link")
	_use("dead_coast_guard_pass")
	_enter(&"dc_cove")
	await _frames(3)
	_check(_count("coastal_weapon_part") == 1 and _count("upgrade_kit_weapon") == 1, "repeating events pays nothing twice")
	_check(_qm.completed.count(&"dc_lost_cargo") == 1 and _qm.completed.count(&"dc_wreckage") == 1, "each quest completed exactly once")

	# Optional content still works after the mission, once.
	var vault_before: int = _count("tide_charm")
	_check(_use("dead_coast_depot_vault"), "the depot vault opens")
	await _frames(4)
	_check(_world.has_flag(&"dead_coast_depot_vault_taken"), "the vault is remembered as taken")
	_check(not _use("dead_coast_depot_vault"), "it cannot be opened twice")
	_check(vault_before == 0, "the unique charm was not in the bag before")


func _scenario_out_of_order() -> void:
	print("-- out of order")
	await _fresh()
	_region.enter()
	# Everything the later missions need happens first, as flags and interactions.
	_world.set_flag(&"dead_coast_waves_cleared")  # the stage's wave step (stage_waves_check plays the real fight)
	_use("dead_coast_guard_pass")
	_use("dead_coast_log_checkpoint_orders")
	_use("dead_coast_checkpoint_terminal")
	_enter(&"dc_checkpoint")
	_world.set_flag(&"patrol_dead_coast_checkpoint_cleared", true)
	_use("dead_coast_trail_markers")
	_enter(&"dc_cove")
	for id in ["dead_coast_cargo_a", "dead_coast_cargo_b", "dead_coast_cargo_c", "dead_coast_cargo_gear", "dead_coast_log_black_site_link"]:
		_use(id)
	_check(_qm.is_active(&"dc_wreckage") and not _qm.is_completed(&"dc_lost_cargo"), "later missions wait for their prerequisites")
	# Now Mission 1, last.
	_enter(&"dc_wreckage_beach")
	for id in ["dead_coast_wreck_hull", "dead_coast_radio_wreck", "dead_coast_log_wreck_manifest", "dead_coast_data_device"]:
		_use(id)
	_world.set_flag(&"patrol_dead_coast_beach_cleared", true)
	await _frames(4)
	_check(_qm.is_completed(&"dc_wreckage"), "Wreckage completes last")
	_check(_qm.is_completed(&"dc_silent_checkpoint"), "The Silent Checkpoint was already done and completes at once")
	_check(_qm.is_completed(&"dc_lost_cargo"), "Lost Cargo was already done and completes at once")
	_check(_world.has_flag(DeadCoast.COMPLETE_FLAG), "the Blackwood exit is unlocked")
	_check(_count("upgrade_kit_weapon") == 1 and _count("coastal_weapon_part") == 1, "every reward arrives exactly once")
	_check(_qm.completed.size() == 4 and _qm.completed.has(&"first_signal"), "exactly the three coast quests plus Outpost 17 completed (%d)" % _qm.completed.size())


func _scenario_save_round_trip() -> void:
	print("-- save round trip")
	await _fresh()
	_region.enter()
	_enter(&"dc_wreckage_beach")
	_use("dead_coast_wreck_hull")
	_use("dead_coast_log_wreck_manifest")
	var quest_state: Dictionary = _qm.to_dict()
	var world_state: Dictionary = _world.to_dict()
	var region_state: Dictionary = _region.capture_state()
	_check((region_state["read"] as Array).has("dead_coast_log_wreck_manifest"), "capture_state records the read manifest")
	# reload into a fresh world
	await _fresh()
	_world.from_dict(world_state)
	_qm.call("from_dict", quest_state)
	_region.restore_state(region_state)
	await _frames(3)
	_check(_qm.is_active(&"dc_wreckage"), "the mission is still active after a reload")
	_check(_done(&"dc_wreckage", "investigate_wreckage") and _done(&"dc_wreckage", "find_shipment_evidence"), "finished objectives are still finished")
	_check(not _done(&"dc_wreckage", "recover_data_device"), "unfinished objectives are still open")
	_check(_world.has_flag(&"doc_dead_coast_log_wreck_manifest_found"), "the read flag survived")
	# the region can be re-entered without restarting or resetting the mission
	_region.enter()
	_check(_qm.is_active(&"dc_wreckage") and _qm.completed.size() == 1, "re-entering does not restart or complete anything (%d completed)" % _qm.completed.size())
