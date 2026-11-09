extends SceneTree
## Blackwood persistence (headless): godot --headless --path . -s tests/blackwood_persistence_check.gd
## WorldState keeps only [a-z0-9_] ids of at most 48 characters. This scans every Blackwood id and flag,
## plays the region for real, then proves claims, cleared encounters, puzzle and mission flags survive a
## real WorldState.to_dict()/from_dict() (through JSON) and a real SaveManager save and load. Quests that were
## active in the save come back, for Blackwood and for Dead Coast.
## Uses SaveManager's per-process test file, never the real save.

const HEAVY: String = "res://resources/attacks/heavy_1.tres"
const BW_QUESTS: Array[String] = ["into_the_blackwood", "ghost_frequency", "experimental_site"]
const DC_QUESTS: Array[String] = ["dc_wreckage", "dc_silent_checkpoint", "dc_lost_cargo"]

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _sm: Node
var _rm: Node
var _region: Blackwood
var _player: Player
var _expected: Array[String] = []


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


static func _is_plain(text: String) -> bool:
	for i in text.length():
		var c: int = text.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return text.length() > 0 and text.length() <= 48


func _clean() -> void:
	_sm.reset_runtime_state()
	_sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = _sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_world.reset()
	_rm.from_dict({})
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()


func _build() -> void:
	if _region != null and is_instance_valid(_region):
		_region.queue_free()
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	await _frames(2)
	_player = load("res://scenes/player/Player.tscn").instantiate() as Player
	_player.position = Vector3(2000.0, 5.0, 2000.0)
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
	_rm = root.get_node("RegionManager")
	await _frames(3)
	_clean()
	await _build()
	_test_registration()
	_test_every_id_is_plain()
	_test_dotted_control()
	await _play_region()
	_test_json_round_trip()
	await _test_real_save_and_load()
	_clean()
	_qm.mission_autosave = true
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_registration() -> void:
	print("Registration in QUEST_PATHS")
	var paths: Array = _qm.get_script().get_script_constant_map()["QUEST_PATHS"]
	var all_listed := true
	for id in BW_QUESTS:
		all_listed = all_listed and paths.has("res://resources/quests/blackwood/%s.tres" % id)
	_check(all_listed, "the three Blackwood quests are listed in QUEST_PATHS")
	var dc_listed := true
	for id in DC_QUESTS:
		dc_listed = dc_listed and _qm.get_quest(StringName(id)) != null
	_check(dc_listed, "the Dead Coast quests are still loaded")
	_qm._load_quests()  # what a fresh start does: only QUEST_PATHS, no region has registered anything
	var bw_loaded := true
	for id in BW_QUESTS:
		bw_loaded = bw_loaded and _qm.get_quest(StringName(id)) != null
	_check(bw_loaded, "a fresh QuestManager knows all three Blackwood quests without the region")


## Every id and flag the region can create.
func _all_names() -> Array[String]:
	var names: Array[String] = []
	for id in BW_QUESTS:
		var quest := _qm.get_quest(StringName(id)) as QuestData
		names.append(String(quest.id))
		for objective in quest.objectives:
			names.append(String(objective.id))
			if objective.type == ObjectiveData.Type.FLAG or objective.type == ObjectiveData.Type.INTERACT \
					or objective.type == ObjectiveData.Type.ENTER_AREA:
				for target in objective.targets:
					names.append(String(target))
	for node in _region.find_children("*", "Interactable", true, false):
		var it := node as Interactable
		names.append(String(it.interaction_id))
		if it is LoreDocument:
			names.append(String((it as LoreDocument).found_flag()))
		if it is SupplyCrate:
			names.append(String((it as SupplyCrate).crate_id) + "_taken")
		if it is Terminal:
			names.append(String((it as Terminal).requires_flag))
			names.append(String((it as Terminal).finish_flag))
	for id in _region.encounters:
		names.append(String((_region.encounters[id] as BlackwoodEncounter).cleared_flag()))
		names.append(String((_region.encounters[id] as BlackwoodEncounter).claim_id()))
	for trigger in _region.find_children("Trigger_*", "AreaTrigger", true, false):
		names.append(String((trigger as AreaTrigger).area_id))
		names.append("discovered_" + String((trigger as AreaTrigger).area_id))
	names.append(String(FrequencyPuzzle.SOLVED_FLAG))
	names.append("blackwood_gate_open")
	names.append(String(Blackwood.ACCESS_FLAG))
	names.erase("")
	return names


func _test_every_id_is_plain() -> void:
	print("Every id is plain")
	var names := _all_names()
	var bad: Array[String] = []
	for n in names:
		if not _is_plain(n):
			bad.append(n)
	_check(names.size() > 60, "the scan covers the region (%d ids and flags)" % names.size())
	_check(bad.is_empty(), "every Blackwood id and flag is [a-z0-9_] and at most 48 characters (bad: %s)" % str(bad))
	_check(RegionFlags.key(&"blackwood", &"ambush_cleared") == &"blackwood_ambush_cleared", "RegionFlags builds the cleared-flag names the quests use")
	_check((_region.encounters[&"ambush"] as BlackwoodEncounter).cleared_flag() == &"blackwood_ambush_cleared", "the encounter uses RegionFlags")


## Control: a dotted flag is lost by a real round trip, so the scan above would catch the old naming.
func _test_dotted_control() -> void:
	print("Control: dotted ids are lost")
	_check(not _is_plain("blackwood.ambush_cleared"), "the scan rejects a dotted id")
	_world.set_flag(&"blackwood.ambush_cleared", true)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_world.to_dict()))
	_world.from_dict(data)
	_check(not _world.has_flag(&"blackwood.ambush_cleared"), "WorldState drops a dotted flag on a real round trip")
	_world.reset()


## Plays the region for real so the flags, claims and quest progress are produced by the game itself.
func _play_region() -> void:
	print("Playing the region")
	_world.emit_area_entered(&"blackwood_jungle_entrance")
	await _frames(2)
	_world.emit_area_entered(&"blackwood_trail")
	var gear: Interactable = null
	for n in _region.find_children("*", "Interactable", true, false):
		if (n as Interactable).interaction_id == &"bw_patrol_gear":
			gear = n
	gear.interact(_player)
	var ambush: BlackwoodEncounter = _region.encounters[&"ambush"]
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(1.8)
	_kill(ambush)
	await _frames(4)
	_check(_world.has_flag(&"blackwood_ambush_cleared"), "the ambush is cleared (flag)")
	_check(PersistentIds.is_claimed(&"blackwood", &"encounter_ambush"), "the ambush is claimed as a one-time id")
	_world.emit_area_entered(&"blackwood_patrol_camp")
	_world.set_flag(&"blackwood_boss_1_defeated")  # the patrol chief step (stage_bosses_check plays the real fight)
	await _frames(3)
	_check(_qm.is_completed(&"into_the_blackwood"), "mission one is complete")
	_world.emit_area_entered(&"blackwood_comms_station")
	var p := _region.puzzle
	p.turn(2)
	_check(not p.transmit() and not _world.has_flag(&"blackwood_comms_power"), "a wrong channel sets no flag")
	for dial in 3:
		while p.dials[dial] != FrequencyPuzzle.CODE[dial]:
			p.turn(dial)
	p.transmit()
	await _frames(2)
	_terminal(&"bw_transmissions").interact(_player)
	await _frames(2)
	_check(_world.has_flag(&"blackwood_comms_power") and _world.has_flag(&"blackwood_transmissions_read"), "the puzzle step flags are set")
	_terminal(&"bw_data_recorder").interact(_player)
	_terminal(&"bw_gate_panel").interact(_player)
	for n in _region.find_children("*", "LoreDocument", true, false):
		if (n as LoreDocument).interaction_id == &"bw_log_patrol_1":
			(n as LoreDocument).interact(_player)
	await _frames(3)
	# Leave the second mission half done on purpose: it must come back active after the load.
	_check(_qm.is_active(&"ghost_frequency"), "Ghost Frequency is active and unfinished (the save will carry it)")
	# Dead Coast quest active too, to prove nothing about Blackwood broke theirs.
	_qm.start_quest(&"dc_wreckage")
	_check(_qm.is_active(&"dc_wreckage"), "a Dead Coast quest is active as well")
	_expected.clear()
	for flag in ["blackwood_ambush_cleared", "blackwood_comms_power", "blackwood_transmissions_read", "blackwood_black_site_link",
			"blackwood_gate_open", "doc_bw_log_patrol_1_found"]:
		if _world.has_flag(StringName(flag)):
			_expected.append(flag)
	_check(_expected.size() == 6, "the play-through produced the flags to track (%d)" % _expected.size())


func _test_json_round_trip() -> void:
	print("Real WorldState round trip (through JSON, like the save file)")
	var data: Dictionary = JSON.parse_string(JSON.stringify(_world.to_dict()))
	_world.reset()
	_check(not _world.has_flag(&"blackwood_ambush_cleared"), "reset cleared the world")
	_world.from_dict(data)
	var lost: Array[String] = []
	for flag in _expected:
		if not _world.has_flag(StringName(flag)):
			lost.append(flag)
	_check(lost.is_empty(), "every Blackwood flag survives to_dict() and from_dict() (lost: %s)" % str(lost))


func _test_real_save_and_load() -> void:
	print("Real SaveManager save and load")
	var active_before: Dictionary = (_qm.active[&"ghost_frequency"] as Dictionary).duplicate(true)
	var claimed_before: bool = PersistentIds.is_claimed(&"blackwood", &"encounter_ambush")
	_check(claimed_before, "the claim exists before saving")
	_check(_sm.save_game("test"), "the game saves")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(parsed is Dictionary and (parsed as Dictionary).has("quests") and (parsed as Dictionary).has("regions"), "the file has quests and regions")
	if parsed is Dictionary:
		var q: Dictionary = (parsed as Dictionary)["quests"]
		_check((q["active"] as Dictionary).has("ghost_frequency") and (q["active"] as Dictionary).has("dc_wreckage"), "both active quests are in the file")
		var in_file := 0
		for flag in ((q.get("world", {}) as Dictionary).get("flags", []) as Array):
			if _expected.has(String(flag)):
				in_file += 1
		_check(in_file == _expected.size(), "all tracked flags are in the file (%d of %d)" % [in_file, _expected.size()])
	# Wipe everything the way a new process starts: nothing registered by any region.
	_world.reset()
	_rm.from_dict({})
	_qm.reset()
	_qm._load_quests()
	_check(not _qm.is_active(&"ghost_frequency") and not PersistentIds.is_claimed(&"blackwood", &"encounter_ambush"), "the wipe removed quests, flags and claims")
	_check(_sm.load_game(), "the game loads")
	await _frames(2)
	var lost: Array[String] = []
	for flag in _expected:
		if not _world.has_flag(StringName(flag)):
			lost.append(flag)
	_check(lost.is_empty(), "every tracked flag is back after a real load (lost: %s)" % str(lost))
	_check(PersistentIds.is_claimed(&"blackwood", &"encounter_ambush"), "the claimed encounter id is back")
	_check(_qm.is_completed(&"into_the_blackwood"), "the completed Blackwood mission stays completed")
	_check(_qm.is_active(&"ghost_frequency"), "the active Ghost Frequency quest is restored")
	if _qm.is_active(&"ghost_frequency"):
		_check((_qm.active[&"ghost_frequency"] as Dictionary)["done"] == active_before["done"], "its objective progress is identical")
	_check(_qm.is_active(&"dc_wreckage"), "the active Dead Coast quest is restored too")
	var charm_before := _player.inventory.count_of("blackwood_ghost_charm")
	_check(charm_before == 0, "no reward appeared out of nowhere on load")
	# A cleared ambush stays cleared when the region is rebuilt from the loaded state.
	await _build()
	var again: BlackwoodEncounter = _region.encounters[&"ambush"]
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(1.8)
	_check(again.is_cleared and again.enemies.is_empty(), "a rebuilt region does not respawn the cleared ambush")
	_check(not _region.puzzle.is_solved or _world.has_flag(&"blackwood_comms_power"), "the puzzle state agrees with its flag")
	_check(_region.puzzle.is_solved, "the solved puzzle is still solved after the load")
