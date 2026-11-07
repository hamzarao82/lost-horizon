extends SceneTree
## Dead Coast persistence checks (headless): godot --headless --path . -s tests/dead_coast_persistence_check.gd
## WorldState silently drops saved flags that contain anything but a-z, 0-9 and underscore, or exceed 48
## characters. This proves every Dead Coast id and flag survives a real WorldState.to_dict()/from_dict()
## and a real SaveManager save and load, and shows that a dotted id would not.

const SCENE: String = "res://scenes/regions/DeadCoast_content.tscn"
const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const MAX_FLAG: int = 48

var _failures: int = 0
var _checks: int = 0
var _region: DeadCoast
var _player: Player
var _world: Node
var _qm: Node
var _sm: Node
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


static func _is_plain(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return text.length() > 0


func _run() -> void:
	_world = root.get_node_or_null("WorldState")
	_qm = root.get_node_or_null("QuestManager")
	_sm = root.get_node_or_null("SaveManager")
	_sm.delete_save()
	_world.from_dict({})
	_qm.call("reset", false)
	_qm.set("intro_done", true)
	_qm.set("mission_autosave", false)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_dummy = Node3D.new()
	root.add_child(_dummy)
	_region = (load(SCENE) as PackedScene).instantiate() as DeadCoast
	root.add_child(_region)
	await _frames(4)

	_test_every_id_is_plain()
	_test_dotted_ids_are_dropped_control()
	await _play_and_collect_flags()
	_test_world_state_round_trip()
	await _test_real_save_and_load()
	_sm.delete_save()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Every persistent id, every flag derived from it and every quest flag name: plain characters, 48 at most.
func _all_flag_names() -> Array[String]:
	var names: Array[String] = []
	for id in _region.content.crate_ids:
		names.append(id)
		names.append(id + "_taken")
	for id in _region.content.document_ids:
		names.append(id)
		names.append("doc_%s_found" % id)
	for id: String in _region.content.patrols:
		names.append(id)
		names.append("patrol_%s_cleared" % id)
	for area in DeadCoast.AREAS:
		names.append("discovered_%s" % area["id"])
	names.append("discovered_dc_camp")
	names.append(String(DeadCoast.ROUTE_FLAG))
	names.append(String(DeadCoast.COMPLETE_FLAG))
	names.append("door_dc_gate_open")
	for id in _region.content.nodes:
		if String(id).begins_with("checkpoint_"):
			names.append(String(id))
	for quest_id in [&"dc_wreckage", &"dc_silent_checkpoint", &"dc_lost_cargo"]:
		var quest: QuestData = _qm.get_quest(quest_id)
		names.append(String(quest.id))
		for objective in quest.objectives:
			names.append(String(objective.id))
			for target in objective.targets:
				names.append(String(target))
	return names


func _test_every_id_is_plain() -> void:
	print("-- every id and flag")
	var names := _all_flag_names()
	var bad: Array[String] = []
	var long: Array[String] = []
	for n in names:
		if not _is_plain(n):
			bad.append(n)
		if n.length() > MAX_FLAG:
			long.append(n)
	_check(names.size() > 100, "scanned %d ids and flag names" % names.size())
	_check(bad.is_empty(), "every id and flag uses only a-z, 0-9 and underscore (bad: %s)" % str(bad))
	_check(long.is_empty(), "every id and flag is at most %d characters (long: %s)" % [MAX_FLAG, str(long)])
	var longest := 0
	for n in names:
		longest = maxi(longest, n.length())
	_check(longest <= MAX_FLAG, "the longest is %d characters" % longest)
	_check(DeadCoast.ROUTE_FLAG == RegionFlags.key(&"dead_coast", &"route_pass"), "the route flag follows RegionFlags.key")
	_check(DeadCoast.COMPLETE_FLAG == RegionFlags.key(&"dead_coast", &"cargo_complete"), "the completion flag follows RegionFlags.key")


## The failure mode itself: a dotted flag is dropped by a real round trip, an underscore one survives.
func _test_dotted_ids_are_dropped_control() -> void:
	print("-- control: dotted ids vanish")
	_world.set_flag(&"dead_coast.cache_old_taken", true)
	_world.set_flag(&"dead_coast_cache_new_taken", true)
	var data: Dictionary = _world.to_dict()
	_world.from_dict(data)
	_check(not _world.has_flag(&"dead_coast.cache_old_taken"), "a dotted flag is lost by WorldState.to_dict()/from_dict() (the old ids would have repeated)")
	_check(_world.has_flag(&"dead_coast_cache_new_taken"), "the underscore flag survives")
	_check(not _is_plain("dead_coast.cache_old_taken") and _is_plain("dead_coast_cache_new_taken"), "the scanner flags the dotted id and accepts the underscore id")
	_world.from_dict({})


func _use(id: String) -> bool:
	return (_region.content.nodes[id] as Interactable).interact(_dummy)


var _expected: Array[String] = []


## Real play: open a cache, read documents, take the pass, kill the beach squad, finish all three missions.
func _play_and_collect_flags() -> void:
	print("-- play")
	_region.enter()
	(_region.triggers[&"dc_wreckage_beach"] as AreaTrigger).report_entered()
	for id in ["dead_coast_wreck_hull", "dead_coast_radio_wreck", "dead_coast_log_wreck_manifest", "dead_coast_data_device",
			"dead_coast_checkpoint_terminal", "dead_coast_guard_pass", "dead_coast_log_checkpoint_orders", "dead_coast_trail_markers",
			"dead_coast_cargo_a", "dead_coast_cargo_b", "dead_coast_cargo_c", "dead_coast_cargo_gear", "dead_coast_log_black_site_link",
			"dead_coast_cache_wreck", "dead_coast_depot_vault"]:
		_check(_use(id), "used %s" % id)
	# a real squad kill for the beach patrol, the other squads through their cleared flags
	var beach := _region.content.patrols["dead_coast_beach"] as PatrolGroup
	beach.spawn()
	await _frames(3)
	var attack := load("res://resources/attacks/heavy_1.tres") as AttackData
	for enemy in beach.enemies:
		for i in 14:
			if is_instance_valid(enemy) and not enemy.is_dead():
				enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, 2.0))
				await physics_frame
	await _frames(4)
	_world.set_flag(&"patrol_dead_coast_checkpoint_cleared", true)
	(_region.triggers[&"dc_checkpoint"] as AreaTrigger).report_entered()
	(_region.triggers[&"dc_cove"] as AreaTrigger).report_entered()
	await _frames(4)
	for quest_id in [&"dc_wreckage", &"dc_silent_checkpoint", &"dc_lost_cargo"]:
		_check(_qm.is_completed(quest_id), "mission complete: %s" % quest_id)
	_expected = [
		"dead_coast_cache_wreck_taken", "dead_coast_depot_vault_taken", "dead_coast_cargo_a_taken", "dead_coast_cargo_b_taken",
		"dead_coast_cargo_c_taken", "doc_dead_coast_log_wreck_manifest_found", "doc_dead_coast_log_black_site_link_found",
		"patrol_dead_coast_beach_cleared", "patrol_dead_coast_checkpoint_cleared", "dead_coast_route_pass", "dead_coast_cargo_complete",
		"discovered_dc_wreckage_beach", "discovered_dc_cove"]
	for flag in _expected:
		_check(_world.has_flag(StringName(flag)), "flag set in play: %s" % flag)


func _test_world_state_round_trip() -> void:
	print("-- real WorldState round trip")
	var data: Dictionary = _world.to_dict()
	_world.reset()
	for flag in _expected:
		_check(not _world.has_flag(StringName(flag)), "reset cleared %s" % flag)
		break
	_world.from_dict(data)
	var lost: Array[String] = []
	for flag in _expected:
		if not _world.has_flag(StringName(flag)):
			lost.append(flag)
	_check(lost.is_empty(), "every claimed cache, read log, cleared squad and mission flag survives (lost: %s)" % str(lost))
	var region_state: Dictionary = _region.capture_state()
	_check((region_state["claimed"] as Array).has("dead_coast_cache_wreck") and (region_state["cleared"] as Array).has("dead_coast_beach"),
		"capture_state reports the claimed cache and the cleared squad")
	_check((region_state["flags"] as Array).has("dead_coast_route_pass") and (region_state["flags"] as Array).has("dead_coast_cargo_complete"),
		"capture_state reports the mission flags")


## A real SaveManager.save_game() and load_game() with the world wiped in between.
func _test_real_save_and_load() -> void:
	print("-- real SaveManager save and load")
	_check(_sm.save_game("test"), "the game saves")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(parsed is Dictionary, "the file is JSON")
	var in_file := 0
	if parsed is Dictionary and (parsed as Dictionary).has("quests"):
		var world: Dictionary = (parsed["quests"] as Dictionary).get("world", {})
		for flag in (world.get("flags", []) as Array):
			if _expected.has(String(flag)):
				in_file += 1
	_check(in_file == _expected.size(), "all %d Dead Coast flags are written to the file (%d)" % [_expected.size(), in_file])
	_region.free()
	_player.free()
	await _frames(2)
	_world.reset()
	_qm.call("reset", false)
	_sm.reset_runtime_state()
	_check(not _world.has_flag(&"dead_coast_route_pass"), "wiped before loading")
	_check(_sm.load_game(), "the save loads")
	await _frames(3)
	var missing: Array[String] = []
	for flag in _expected:
		if not _world.has_flag(StringName(flag)):
			missing.append(flag)
	_check(missing.is_empty(), "after a real save and load every flag is back (missing: %s)" % str(missing))
	for quest_id in [&"dc_wreckage", &"dc_silent_checkpoint", &"dc_lost_cargo"]:
		_check(_qm.is_completed(quest_id), "mission still complete after loading: %s" % quest_id)
	# a rebuilt region honours the loaded flags: caches stay shut, the beach squad stays dead, nothing repeats
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_region = (load(SCENE) as PackedScene).instantiate() as DeadCoast
	root.add_child(_region)
	await _frames(4)
	var crate := _region.content.nodes["dead_coast_cache_wreck"] as SupplyCrate
	var pickups_before := root.find_children("*", "Pickup", true, false).size()
	_check(not crate.interact(_dummy), "the opened cache stays shut after the reload")
	await _frames(3)
	_check(root.find_children("*", "Pickup", true, false).size() == pickups_before, "nothing is handed out again")
	var beach := _region.content.patrols["dead_coast_beach"] as PatrolGroup
	_check(beach.spawned and beach.enemies.is_empty(), "the cleared beach squad does not respawn")
	var vault := _region.content.nodes["dead_coast_depot_vault"] as SupplyCrate
	_check(vault.is_used() and not vault.interact(_dummy), "the unique vault cannot be opened a second time")
	var gate := _region.content.nodes["dc_gate"] as Door
	_check(not gate.locked, "the barrier stays unlocked: the guard pass flag persisted")
