extends SceneTree
## Headless checks for the quest and story layer:
##   godot --headless --path . -s tests/quest_check.gd

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
	_test_state_sanitize()
	_test_intro_rules()
	await _test_flow()
	await _test_history_replay()
	await _test_kill_objective()
	await _test_save_round_trip()
	await _test_resilience()
	await _test_world_and_wave_wiring()
	await _test_save_manager()
	await _test_hud_layout()
	await _test_story_scenes()
	for qm in _managers:
		if is_instance_valid(qm):
			qm.queue_free()
	await _frames(2)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- helpers ---------------------------------------------------------------

## A private QuestManager that is not tied to the real WorldState, so tests drive it with notify().
func _make_manager() -> Node:
	var qm := (load(QM_SCRIPT) as GDScript).new() as Node
	qm.name = "QuestManagerTest%d" % _managers.size()
	root.add_child(qm)
	_managers.append(qm)
	await process_frame  # its deferred WorldState bind runs now
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


func _complete_first_two(qm: Node) -> void:
	qm.notify(OBJ.INTERACT, &"radio")
	for id in [&"switch_1", &"switch_2", &"switch_3"]:
		qm.notify(OBJ.INTERACT, id)
	qm.notify(OBJ.FLAG, &"power_on")


# --- data ------------------------------------------------------------------

func _test_data() -> void:
	print("Quest data")
	var ids: Array[StringName] = []
	var all_valid := true
	var chain_ok := true
	for path in ["first_signal", "restore_power", "broken_perimeter", "final_transmission"]:
		var quest := load("res://resources/quests/%s.tres" % path) as QuestData
		var errors := quest.validate() if quest else PackedStringArray(["failed to load"])
		if not errors.is_empty():
			print("       ", path, ": ", errors)
		all_valid = all_valid and errors.is_empty()
		if quest:
			ids.append(quest.id)
	for path in ["first_signal", "restore_power", "broken_perimeter", "final_transmission"]:
		var quest := load("res://resources/quests/%s.tres" % path) as QuestData
		for prerequisite in quest.prerequisites:
			chain_ok = chain_ok and ids.has(StringName(prerequisite))
		chain_ok = chain_ok and (quest.next_quest == &"" or ids.has(quest.next_quest))
	_check(ids.size() == 4 and all_valid, "all four quests load and validate")
	_check(chain_ok, "prerequisites and next_quest only reference real quests")

	var bad := QuestData.new()
	_check(not bad.validate().is_empty(), "an empty quest is rejected")
	bad.id = &"x"
	bad.title = "X"
	var objective := ObjectiveData.new()
	objective.id = &"o"
	objective.text = "Do it"
	objective.type = OBJ.INTERACT
	bad.objectives.append(objective)
	_check(not bad.validate().is_empty(), "an INTERACT objective without targets is rejected")
	objective.targets = PackedStringArray(["a"])
	_check(bad.validate().is_empty(), "adding a target makes it valid")
	bad.rewards = PackedStringArray(["no_such_item"])
	_check(not bad.validate().is_empty(), "an unknown reward item is rejected")
	var kills := ObjectiveData.new()
	kills.id = &"k"
	kills.text = "Kill"
	kills.type = OBJ.KILL_COUNT
	_check(not kills.validate().is_empty(), "KILL_COUNT needs a count")
	var switches := load("res://resources/quests/restore_power.tres") as QuestData
	_check(switches.objectives[0].required() == 3, "three switches need three distinct targets")


func _test_state_sanitize() -> void:
	print("Quest save sanitising")
	_check(QuestState.sanitize("junk").is_empty() and QuestState.sanitize({}).is_empty(), "non-dictionaries and empty data give {}")
	var messy := QuestState.sanitize({
		"active": {"first_signal": {"progress": [1, "x", 5.7], "seen": [["a", 3, "a"]], "done": [true, 1]}, 7: {}},
		"completed": [1, "a", "a", {"k": 1}],
		"history": 5,
		"intro_done": "yes",
		"world": "nope",
	})
	_check(messy["completed"] == ["a"], "completed keeps only unique strings")
	_check(messy["active"].has("first_signal") and not messy["active"].has("7"), "non-string quest ids are dropped")
	_check(messy["active"]["first_signal"]["progress"] == [1, 0, 5], "progress is coerced to ints")
	_check(messy["active"]["first_signal"]["seen"] == [["a"]], "seen lists keep unique strings")
	_check(messy["active"]["first_signal"]["done"] == [true, false], "done flags must be real booleans")
	_check(messy["history"].is_empty() and messy["world"] == {} and messy["intro_done"] == false, "wrong types fall back to defaults")
	var many: Array = []
	for i in 500:
		many.append("id%d" % i)
	_check(QuestState.sanitize({"completed": many})["completed"].size() <= QuestState.MAX_ENTRIES, "oversized lists are clipped")


func _test_intro_rules() -> void:
	print("Intro rules")
	var qm_script := load(QM_SCRIPT) as GDScript
	var holder := qm_script.new() as Node
	_check(holder.should_play_intro(false, false, false, false, false), "a fresh game on a real display plays the intro")
	_check(not holder.should_play_intro(true, false, false, false, false), "headless never plays it")
	_check(not holder.should_play_intro(false, true, false, false, false), "loading a save skips it")
	_check(not holder.should_play_intro(false, false, true, false, false), "a death restart (checkpoint) skips it")
	_check(not holder.should_play_intro(false, false, false, true, false), "a game with quest progress skips it")
	_check(not holder.should_play_intro(false, false, false, false, true), "it plays only once")
	holder.free()


# --- flow ------------------------------------------------------------------

func _test_flow() -> void:
	print("Quest flow")
	var qm := await _make_manager()
	var player := await _make_player()
	var captions: Array[String] = []
	var events: Array[String] = []
	qm.caption_requested.connect(func(text: String, _s: float) -> void: captions.append(text))
	qm.quest_started.connect(func(id: StringName) -> void: events.append("start:%s" % id))
	qm.quest_completed.connect(func(id: StringName) -> void: events.append("done:%s" % id))
	qm.reset()
	events.clear()

	_check(qm.is_active(&"first_signal") and qm.completed.is_empty(), "a fresh run starts The First Signal")
	_check(qm.tracker_title() == "The First Signal" and qm.tracker_objective().contains("radio"), "the tracker shows quest and objective")
	_check(not qm.start_quest(&"restore_power"), "a quest cannot start before its prerequisite is done")
	_check(not qm.start_quest(&"first_signal"), "an active quest cannot be started twice")

	qm.notify(OBJ.INTERACT, &"not_the_radio")
	_check(qm.is_active(&"first_signal"), "an unrelated interaction does nothing")
	var knife_before: StringName = player.inventory.weapon.item_id
	qm.notify(OBJ.INTERACT, &"radio")
	_check(qm.is_completed(&"first_signal") and qm.is_active(&"restore_power"), "using the radio completes quest 1 and starts quest 2")
	_check(player.inventory.weapon.item_id == &"combat_knife" and knife_before == &"improvised_blade", "the quest 1 reward (combat knife) is granted")
	_check(captions.size() == 3 and captions[0].contains("not alone"), "the radio lines are queued as captions (%d)" % captions.size())
	qm.notify(OBJ.INTERACT, &"radio")
	_check(qm.completed.size() == 1 and events.count("done:first_signal") == 1, "repeating the event does not complete it again")

	_check(qm.tracker_objective().contains("Switches 0/3"), "the switch objective shows 0/3")
	qm.notify(OBJ.INTERACT, &"switch_1")
	qm.notify(OBJ.INTERACT, &"switch_1")
	_check(qm.objective_progress(&"restore_power", 0) == 1, "the same switch twice counts once")
	qm.notify(OBJ.INTERACT, &"switch_2")
	qm.notify(OBJ.INTERACT, &"switch_3")
	_check(qm.objective_progress(&"restore_power", 0) == 3 and qm.is_active(&"restore_power"), "three switches finish objective 1 only")
	_check(qm.tracker_objective().contains("Restore power"), "the tracker moves on to the power objective")
	var armor_before: ItemData = player.inventory.armor
	qm.notify(OBJ.FLAG, &"power_on")
	_check(qm.is_completed(&"restore_power") and qm.is_active(&"broken_perimeter"), "power_on completes quest 2 and starts quest 3")
	_check(armor_before == null and player.inventory.armor != null, "the quest 2 reward (armor) is granted")

	qm.notify(OBJ.ENTER_AREA, &"courtyard")
	qm.notify(OBJ.WAVE_CLEARED, &"", 3)
	_check(qm.objective_progress(&"broken_perimeter", 1) == 3, "wave progress follows the highest cleared wave")
	qm.notify(OBJ.WAVE_CLEARED, &"", 2)
	_check(qm.objective_progress(&"broken_perimeter", 1) == 3, "an older wave never lowers progress")
	var potions_before: int = player.inventory.potions
	qm.notify(OBJ.WAVE_CLEARED, &"", 5)
	_check(qm.is_completed(&"broken_perimeter") and qm.is_active(&"final_transmission"), "clearing wave 5 completes quest 3 and starts quest 4")
	_check(player.inventory.potions == potions_before + 2, "the quest 3 reward is two medkits")
	qm.notify(OBJ.WAVE_CLEARED, &"", 5)
	_check(player.inventory.potions == potions_before + 2, "a repeated all-cleared event pays nothing again")

	var ending := [0]
	qm.ending_started.connect(func() -> void: ending[0] += 1)
	qm.notify(OBJ.BOSS_DEFEATED, &"warden")
	qm.notify(OBJ.FLAG, &"has_keycard")
	_check(qm.is_active(&"final_transmission") and ending[0] == 0, "the keycard alone does not finish the last quest")
	qm.notify(OBJ.INTERACT, &"command_terminal")
	_check(qm.is_completed(&"final_transmission") and qm.active.is_empty(), "the command terminal completes the last quest")
	_check(ending[0] == 1, "the ending starts exactly once")
	_check(qm.tracker_title() == "" and qm.tracker_objective() == "", "nothing is tracked once everything is done")
	_check(player.inventory.potions == potions_before + 3, "the final reward (a medkit) is granted once")
	_check(events == ["done:first_signal", "start:restore_power", "done:restore_power", "start:broken_perimeter",
			"done:broken_perimeter", "start:final_transmission", "done:final_transmission"],
			"quests start and finish in order: %s" % [events])

	qm.reset()
	_check(qm.completed.is_empty() and qm.is_active(&"first_signal"), "reset returns to the first quest")
	await _drop(player)


func _test_history_replay() -> void:
	print("Doing things early")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	qm.notify(OBJ.INTERACT, &"switch_1")  # before the radio: quest 2 is not even active yet
	qm.notify(OBJ.INTERACT, &"switch_2")
	qm.notify(OBJ.INTERACT, &"switch_3")
	qm.notify(OBJ.INTERACT, &"radio")
	_check(qm.is_active(&"restore_power") and qm.objective_progress(&"restore_power", 0) == 3, "switches thrown before the quest began still count")
	qm.notify(OBJ.FLAG, &"power_on")
	_check(qm.is_completed(&"restore_power"), "the quest then finishes on power_on")
	await _drop(player)


func _test_kill_objective() -> void:
	print("Kill objective")
	var qm := await _make_manager()
	var quest := QuestData.new()
	quest.id = &"test_hunt"
	quest.title = "Hunt"
	var objective := ObjectiveData.new()
	objective.id = &"kills"
	objective.text = "Defeat three Hunters"
	objective.type = OBJ.KILL_COUNT
	objective.targets = PackedStringArray(["Hunter"])
	objective.count = 3
	objective.progress_label = "Hunters"
	quest.objectives.append(objective)
	_check(quest.validate().is_empty(), "the synthetic quest is valid")
	qm.quests[quest.id] = quest
	_check(qm.start_quest(&"test_hunt"), "it starts")
	qm.active.erase(&"first_signal")  # the tracker follows the first active quest
	qm.notify(OBJ.KILL_COUNT, &"Soldier", 1, 11)
	_check(qm.objective_progress(&"test_hunt", 0) == 0, "other enemy types do not count")
	qm.notify(OBJ.KILL_COUNT, &"Hunter", 1, 21)
	qm.notify(OBJ.KILL_COUNT, &"Hunter", 1, 21)
	_check(qm.objective_progress(&"test_hunt", 0) == 1, "the same enemy never counts twice")
	_check(qm.tracker_objective().contains("Hunters 1/3"), "the tracker shows kill progress")
	qm.notify(OBJ.KILL_COUNT, &"Hunter", 1, 22)
	qm.notify(OBJ.KILL_COUNT, &"Hunter", 1, 23)
	_check(qm.is_completed(&"test_hunt"), "three different Hunters complete it")


# --- persistence -----------------------------------------------------------

func _test_save_round_trip() -> void:
	print("Quest persistence")
	var qm := await _make_manager()
	var player := await _make_player()
	qm.reset()
	qm.notify(OBJ.INTERACT, &"radio")
	qm.notify(OBJ.INTERACT, &"switch_1")
	qm.notify(OBJ.INTERACT, &"switch_3")
	var through_file: Variant = JSON.parse_string(JSON.stringify(qm.to_dict()))  # what a save file does to numbers
	_check(through_file is Dictionary and not str(through_file).contains("res://"), "the saved data holds ids only, no paths")

	var other := await _make_manager()
	var player2 := await _make_player()
	other.from_dict(through_file)
	_check(other.is_completed(&"first_signal") and other.is_active(&"restore_power"), "completed and active quests are restored")
	_check(other.objective_progress(&"restore_power", 0) == 2, "objective progress is restored (2/3 switches)")
	other.notify(OBJ.INTERACT, &"switch_1")
	_check(other.objective_progress(&"restore_power", 0) == 2, "a restored switch still counts only once")
	other.notify(OBJ.INTERACT, &"switch_2")
	_check(other.objective_progress(&"restore_power", 0) == 3, "the missing switch finishes it")
	_check(player2.inventory.weapon.item_id == &"improvised_blade", "restoring a save does not pay the quest 1 reward again")

	# Pending rewards survive a save while no player exists
	await _drop(player)
	var third := await _make_manager()
	third.from_dict({"completed": ["first_signal"], "rewarded": ["first_signal"], "pending_rewards": ["combat_knife"], "intro_done": true})
	_check(player2.inventory.weapon.item_id == &"combat_knife", "a queued reward is delivered when a player exists")
	_check(third.to_dict()["pending_rewards"].is_empty(), "and leaves the queue")
	await _drop(player2)


func _test_resilience() -> void:
	print("Bad data and missing systems")
	var qm := await _make_manager()
	qm.from_dict({"active": "junk", "completed": [1, 2, {"a": 1}], "history": 5, "world": [1]})
	_check(qm.is_active(&"first_signal") and qm.completed.is_empty(), "junk save data falls back to a fresh quest line")
	qm.from_dict(null)
	_check(qm.is_active(&"first_signal"), "null save data is fine")
	qm.from_dict({"completed": ["no_such_quest", "first_signal"], "intro_done": true})
	_check(qm.completed == [&"first_signal"] and qm.is_active(&"restore_power"), "unknown quest ids are dropped, known ones continue")
	qm.from_dict({"active": {"restore_power": {"progress": [1], "seen": [["switch_1"]], "done": [false]}}, "completed": ["first_signal"]})
	_check(qm.is_active(&"restore_power") and qm.objective_progress(&"restore_power", 0) == 0, "a quest whose objective list changed restarts cleanly")

	qm._world = null
	qm.reset()
	qm.notify(OBJ.BOSS_DEFEATED, &"warden")  # the keycard path must cope with no WorldState
	qm.notify(OBJ.INTERACT, &"radio")
	_check(qm.is_completed(&"first_signal"), "events work with no WorldState and no WaveManager in the scene")
	_check(qm.get_quest(&"nope") == null and not qm.start_quest(&"nope"), "an unknown quest id is harmless")
	_check(qm.boss_id_for("The Warden") == &"warden", "boss ids derive from display names")


func _test_world_and_wave_wiring() -> void:
	print("WorldState and WaveManager wiring (real autoloads)")
	var world := root.get_node_or_null("WorldState")
	var am := root.get_node("QuestManager")
	var player := await _make_player()
	am.reset()
	_check(world != null, "the WorldState autoload exists")
	if world == null:
		await _drop(player)
		return
	world.emit_interacted(&"radio")
	_check(am.is_completed(&"first_signal"), "WorldState.interacted advances the quest")
	for id in [&"switch_1", &"switch_2", &"switch_3"]:
		world.emit_interacted(id)
	world.set_flag(&"power_on", true)
	_check(am.is_completed(&"restore_power"), "WorldState.set_flag completes the power quest")
	var waves := WaveManager.new()
	waves.autostart = false
	root.add_child(waves)
	await _frames(2)
	world.emit_area_entered(&"courtyard")
	waves.wave_cleared.emit(4)
	_check(am.objective_progress(&"broken_perimeter", 1) == 4, "WaveManager.wave_cleared advances the quest (found via node_added)")
	waves.all_cleared.emit()
	_check(am.is_completed(&"broken_perimeter") and am.is_active(&"final_transmission"), "WaveManager.all_cleared finishes the perimeter quest")
	waves.queue_free()

	# Enemy defeat: a Warden death sets the keycard flag and counts as the boss kill
	var warden := (load("res://scenes/enemies/Warden.tscn") as PackedScene).instantiate() as Enemy
	warden.position = Vector3(-20, 0.1, -20)
	root.add_child(warden)
	await _frames(2)
	warden.set_physics_process(false)
	warden.defeated.emit()
	_check(world.has_flag(&"has_keycard"), "defeating the Warden sets the keycard flag")
	world.emit_interacted(&"command_terminal")
	_check(am.is_completed(&"final_transmission"), "the terminal then finishes the story")
	warden.queue_free()
	am.reset()
	_check(not world.has_flag(&"power_on") and am.is_active(&"first_signal"), "reset also clears the world flags")
	await _drop(player)


func _test_save_manager() -> void:
	print("SaveManager integration")
	var am := root.get_node("QuestManager")
	var player := await _make_player()
	_sm.reset_runtime_state()
	_sm.delete_save()
	am.reset()
	am.notify(OBJ.INTERACT, &"radio")
	am.notify(OBJ.INTERACT, &"switch_2")
	_check(_sm.save_game("test"), "the game saves with quest data present")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	_check(parsed is Dictionary and parsed.has("quests") and int(parsed["version"]) == 1, "the save has a quests field and is still version 1")
	_check(not str(parsed).contains("res://"), "the save still contains no paths")

	am.reset()
	_check(am.completed.is_empty(), "the quest line was reset")
	_check(_sm.load_game(), "the save loads")
	_check(am.is_completed(&"first_signal") and am.objective_progress(&"restore_power", 0) == 1, "loading restores the quest state (radio done, 1/3 switches)")
	_check(am.intro_done, "a loaded game never replays the intro")
	var sanitized: Dictionary = _sm._sanitize(parsed)
	_check(sanitized.has("quests") and sanitized["quests"]["completed"] == ["first_signal"], "the sanitised save keeps the quest field")

	# An old save (no quests field) still loads and restarts the quest line
	var legacy: Dictionary = parsed.duplicate(true)
	legacy.erase("quests")
	_check(_sm.write_data(legacy, "legacy") and _sm.load_game(), "a save without quest data still loads")
	_check(am.is_active(&"first_signal") and am.completed.is_empty() and am.intro_done, "and starts the quest line fresh without the intro")
	_check(not _sm.pending_data.has("quests"), "the queued data has no quests field")

	_sm.reset_runtime_state()
	_check(am.completed.is_empty() and am.is_active(&"first_signal"), "a deliberate restart resets the quests")
	_sm.delete_save()
	am.reset()
	await _drop(player)


# --- HUD -------------------------------------------------------------------

func _test_hud_layout() -> void:
	print("HUD tracker and subtitles")
	var hud := Hud.new()
	root.add_child(hud)
	await _frames(2)
	hud._tracker_title.text = "Restore Power"
	hud._tracker_objective.text = "Activate the generator switches (Switches 1/3)"
	hud._subtitle.text = "The generator is running. The courtyard gate is open, but they will know someone is inside."

	# With stretch canvas_items + expand the logical size is never smaller than 1280x720 (a 800x360 window
	# or a 20:9 phone is 1600x720), so those are the real cases; 800x360 exercises the short-screen fallback.
	var sizes := [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 1700), Vector2(800, 360)]
	for size: Vector2 in sizes:
		var vx := size.x
		var vy := size.y
		var rects := hud.layout_story(size)
		var tracker: Rect2 = rects["tracker"]
		var subtitle: Rect2 = rects["subtitle"]
		var bars := Rect2(16, 90, 240, 44)
		var teleport_plain := Rect2(16, 146, 260, 30)
		var teleport_touch := Rect2(84, 146, 260, 30)
		var pause_button := Rect2(16, 140, 56, 56)
		var wave_label := Rect2(vx * 0.5 - 110, 12, 220, 30)
		var boss := Rect2(vx * 0.5 - 260, 40, 520, 46)
		var toast := Rect2(vx * 0.5 - 250, vy - 110, 500, 30)
		var equipment := Rect2(vx - 16 - 360, 12, 360, 100)
		var label := "%dx%d" % [size.x, size.y]
		_check(not tracker.intersects(bars) and not tracker.intersects(teleport_plain) and not tracker.intersects(teleport_touch)
				and not tracker.intersects(pause_button) and not tracker.intersects(wave_label),
				"%s: tracker clears the bars, teleport label, pause button and wave label" % label)
		_check(tracker.position.x >= 0 and tracker.end.x <= vx and tracker.end.y <= vy, "%s: tracker is on screen" % label)
		_check(not subtitle.intersects(toast), "%s: subtitle clears the toast" % label)
		_check(subtitle.position.x >= 0 and subtitle.end.x <= vx and subtitle.end.y <= vy, "%s: subtitle is on screen" % label)
		if vy >= 480:
			_check(not tracker.intersects(equipment) and not subtitle.intersects(equipment), "%s: story widgets clear the equipment panel" % label)
			_check(not tracker.intersects(boss) and not subtitle.intersects(boss), "%s: story widgets clear the boss bar" % label)
		else:
			_check(not subtitle.intersects(boss) and not subtitle.intersects(wave_label) and not subtitle.intersects(equipment),
					"%s: short fallback: the subtitle sits below the boss bar, wave label and equipment panel" % label)

	# Short screens hide the tracker while the boss bar owns the top centre
	hud._boss_bar.visible = true
	hud._update_story(Vector2(800, 360), 0.0)
	_check(not hud._tracker_title.visible, "short screen: the tracker hides during a boss fight")
	hud._update_story(Vector2(1280, 720), 0.0)
	_check(hud._tracker_title.visible, "tall screen: the tracker stays during a boss fight")
	hud._boss_bar.visible = false

	for i in 12:
		hud.show_caption("line %d" % i, 2.0)
	_check(hud._caption_queue.size() <= Hud.MAX_QUEUED_CAPTIONS and hud._caption_queue[-1]["text"] == "line 11", "the caption queue is capped and keeps the newest lines")
	hud._caption_queue.clear()
	hud._subtitle_time = 0.0
	hud.show_caption("first", 1.5)
	hud.show_caption("second", 1.5)
	hud._update_story(Vector2(1280, 720), 0.016)
	_check(hud._subtitle.text == "first" and hud._subtitle.visible, "captions show one at a time, in order")
	hud._update_story(Vector2(1280, 720), 1.6)
	hud._update_story(Vector2(1280, 720), 0.016)
	_check(hud._subtitle.text == "second", "the next caption follows when the first runs out")
	await _drop(hud)


# --- scenes ----------------------------------------------------------------

func _test_story_scenes() -> void:
	print("Intro and ending scenes")
	var am := root.get_node("QuestManager")
	var player := await _make_player()
	_check(am._intro == null and not root.get_children().any(func(n: Node) -> bool: return n is StoryIntro), "the intro does not appear under the headless driver")

	var intro := (load("res://scenes/story/Intro.tscn") as PackedScene).instantiate() as StoryIntro
	var finished := [false]
	intro.finished.connect(func() -> void: finished[0] = true)
	root.add_child(intro)
	await process_frame
	_check(paused, "the game is paused while the intro plays")
	intro.skip()
	await _frames(2)
	_check(not paused and finished[0] and not is_instance_valid(intro), "skipping ends the intro, unpauses and frees it")

	var ending := (load("res://scenes/story/Ending.tscn") as PackedScene).instantiate() as StoryEnding
	root.add_child(ending)
	await process_frame
	var buttons: Array[String] = []
	for node in ending.find_children("*", "Button", true, false):
		buttons.append((node as Button).text)
	_check(paused and buttons.has("Play Again"), "the ending pauses the game and offers Play Again (%s)" % [buttons])
	ending.queue_free()
	await _frames(2)
	_check(not paused, "closing the ending unpauses the game")
	await _drop(player)
