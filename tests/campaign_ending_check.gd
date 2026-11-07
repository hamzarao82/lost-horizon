extends SceneTree
## The campaign ending: starts once from `campaign_complete`, never from the arena chain or a loaded save,
## shows statistics (campaign and optional separately), and leaves the world playable.
## godot --headless --path . -s tests/campaign_ending_check.gd

var _failures: int = 0
var _checks: int = 0
var _sm: Node
var _qm: Node
var _world: Node
var _run_stats: Node


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


func _clean() -> void:
	_sm.reset_runtime_state()
	_sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = _sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_sm.defeated_bosses.clear()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	_world.reset()
	paused = false
	var old := root.get_node_or_null("CampaignEnding")
	if old != null:
		old.free()


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	return main


func _run() -> void:
	_sm = root.get_node_or_null("SaveManager")
	_qm = root.get_node_or_null("QuestManager")
	_world = root.get_node_or_null("WorldState")
	_run_stats = root.get_node_or_null("RunStats")
	if _sm == null or _qm == null or _world == null or _run_stats == null:
		print("FAIL autoloads missing")
		quit(1)
		return
	await _test_rules()
	await _test_triggers()
	await _test_arena_chain()
	await _test_stats()
	await _test_sequence_and_choices()
	await _test_persistence_and_new_game()
	_test_ids()
	_clean()
	_qm.mission_autosave = true
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_rules() -> void:
	print("The start rule")
	_clean()
	_check(CampaignEnding.should_start(_world, &"campaign_complete", true), "the completion flag turning on starts the ending")
	_check(not CampaignEnding.should_start(_world, &"campaign_complete", false), "the flag turning off does not")
	_check(not CampaignEnding.should_start(_world, &"iron_fortress_director_defeated", true), "the Director's defeat flag alone does not")
	_check(not CampaignEnding.should_start(_world, &"*", true), "the wildcard a loaded save emits does not")
	_world.set_flag(&"ending_seen", true)
	_check(not CampaignEnding.should_start(_world, &"campaign_complete", true), "an ending that was already seen does not start again")
	_clean()


func _test_triggers() -> void:
	print("Triggering through the real WorldState")
	_clean()
	_world.set_flag(&"iron_fortress_director_defeated", true)
	await _frames(2)
	_check(root.get_node_or_null("CampaignEnding") == null, "nothing starts before campaign_complete")
	_world.set_flag(&"campaign_complete", true)
	await _frames(2)
	var ending := root.get_node_or_null("CampaignEnding") as CampaignEnding
	_check(ending != null, "campaign_complete starts the ending")
	_check(paused, "the game is paused while it plays")
	_check(_world.has_flag(&"ending_seen"), "ending_seen is set when it starts")
	ending.go_to_menu_scene = false
	var count := 0
	for child in root.get_children():
		if child is CampaignEnding:
			count += 1
	_check(count == 1, "exactly one ending exists")
	ending.free()
	paused = false
	_world.set_flag(&"campaign_complete", false)
	_world.set_flag(&"campaign_complete", true)
	await _frames(2)
	_check(root.get_node_or_null("CampaignEnding") == null, "turning the flag on again does not replay the ending")

	_clean()
	_world.from_dict({"flags": ["campaign_complete"]})
	await _frames(2)
	_check(root.get_node_or_null("CampaignEnding") == null, "loading a save that already has campaign_complete does not start it")
	_clean()


func _test_arena_chain() -> void:
	print("The old arena ending")
	_clean()
	var started := [0]
	_qm.ending_started.connect(func() -> void: started[0] += 1)
	_qm.call("_begin_ending", null)
	await _frames(3)
	_check(started[0] == 1, "completing the arena chain still raises the legacy signal once")
	_check(root.get_node_or_null("CampaignEnding") == null and not _qm.ending_shown, "but it starts no ending and shows no 'Thanks for playing' screen")
	_check(not paused, "and does not pause the game")
	var source := FileAccess.get_file_as_string("res://scripts/quests/quest_manager.gd")
	_check(not source.contains("load(ENDING_SCENE)"), "the quest manager no longer loads the old ending scene (source check: headless runs returned early before)")
	_clean()


func _test_stats() -> void:
	print("Statistics")
	_clean()
	_run_stats.seconds_played = 3725.0
	_run_stats.enemies_defeated = 42
	for flag in [&"mission_first_signal_complete", &"dead_coast_mission_3_complete"]:
		_world.set_flag(flag, true)
	var stats := CampaignEnding.collect_stats(self)
	_check(is_equal_approx(float(stats["time_played"]), 3725.0) and int(stats["enemies"]) == 42, "time and kills come from RunStats")
	_check(int(stats["campaign"]["regions_completed"]) == 2, "two regions are complete after two unlock flags (%s)" % str(stats["campaign"]["regions_completed"]))
	_check(not bool(stats["campaign"]["campaign_complete"]), "the campaign is not complete yet")
	_check(stats["optional"].has("secrets_found") and stats["optional"].has("documents") and not stats["campaign"].has("secrets_found"),
			"optional discoveries are reported separately from campaign progress")
	for flag in [&"blackwood_mission_3_complete", &"research_complex_mission_4_complete", &"campaign_complete"]:
		_world.set_flag(flag, true)
	stats = CampaignEnding.collect_stats(self)
	_check(int(stats["campaign"]["regions_completed"]) == 5 and bool(stats["campaign"]["campaign_complete"]), "all five regions complete with the campaign flag")
	_check(CampaignEnding.format_time(3725.0) == "1:02:05", "time formats as h:mm:ss")
	_run_stats.reset()
	_clean()


func _skip_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.pressed = true
	return event


func _test_sequence_and_choices() -> void:
	print("The sequence, the HUD and the choices")
	_clean()
	var main := await _spawn_main()
	var hud := main.find_children("*", "Hud", true, false)
	_check(hud.size() == 1 and (hud[0] as CanvasLayer).visible, "the HUD is visible before the ending")
	for flag in [&"mission_first_signal_complete", &"dead_coast_mission_3_complete", &"blackwood_mission_3_complete", &"research_complex_mission_4_complete"]:
		_world.set_flag(flag, true)
	_world.set_flag(&"campaign_complete", true)
	await _frames(2)
	var ending := root.get_node_or_null("CampaignEnding") as CampaignEnding
	_check(ending != null, "the ending started in a real world")
	if ending == null:
		main.queue_free()
		return
	ending.go_to_menu_scene = false
	_check(not (hud[0] as CanvasLayer).visible, "the HUD is hidden during the ending")
	_check(ending.stage == CampaignEnding.Stage.FADE, "it begins with the fade")
	ending._input(_skip_event(KEY_SPACE))
	await _frames(2)
	_check(ending.stage == CampaignEnding.Stage.BEATS and ending.beat_index == 0, "skipping the fade shows the first beat")
	ending._input(_skip_event(KEY_ENTER))
	_check(ending.beat_index == 1, "Enter skips one beat")
	ending._input(_skip_event(KEY_ESCAPE))
	_check(ending.beat_index == 2, "Esc skips one beat")
	var tail := ""
	for beat in CampaignEnding.BEATS:
		tail += String(beat["text"]) + " "
	_check(CampaignEnding.BEATS.size() >= 6 and CampaignEnding.BEATS.size() <= 8, "there are 6 to 8 closing beats (%d)" % CampaignEnding.BEATS.size())
	_check(tail.contains("counter is still running"), "one thread is left open for optional future content")
	while ending.stage == CampaignEnding.Stage.BEATS:
		ending._input(_skip_event(KEY_SPACE))
	_check(ending.stage == CampaignEnding.Stage.STATS, "after the last beat the statistics screen shows")
	_check(_button_texts(ending) == ["Continue"], "the statistics screen has a Continue button")
	ending._show_credits()
	_check(ending.stage == CampaignEnding.Stage.CREDITS, "then the credits")
	ending._show_choice()
	await process_frame
	var labels := _button_texts(ending)
	_check(labels.has("Continue Exploring") and labels.has("Main Menu"), "the choice offers Continue Exploring and Main Menu (%s)" % str(labels))
	var choice := [&""]
	ending.finished.connect(func(c: StringName) -> void: choice[0] = c)
	ending._choose(CampaignEnding.CHOICE_EXPLORE)
	await _frames(3)
	_check(choice[0] == CampaignEnding.CHOICE_EXPLORE and root.get_node_or_null("CampaignEnding") == null, "Continue Exploring closes the ending")
	_check(not paused, "the game is unpaused")
	_check((hud[0] as CanvasLayer).visible, "the HUD is back")
	var player := main.get_node("Player") as Player
	_check(player.is_physics_processing() and player.state != Player.State.DEAD, "the player is alive and processing")
	var regions := root.get_node_or_null("RegionManager")
	var open := regions != null
	if regions != null:
		for region in [&"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]:
			open = open and regions.is_unlocked(region)
	_check(open, "every region stays open after the ending")
	_qm.active.clear()  # the story is finished: nothing is left to track
	_check(_qm.tracker_title() == "After the signal" and _qm.tracker_objective() == "Explore freely: every region is open",
			"the tracker shows a post-campaign line instead of nothing")
	main.queue_free()
	await _frames(2)

	_clean()
	var replay := CampaignEnding.start(self, true)
	await _frames(2)
	_check(replay != null and replay.replay and not _world.has_flag(&"ending_seen"), "a replay does not touch the saved flags")
	replay.free()
	paused = false
	_clean()


func _button_texts(node: Node) -> Array[String]:
	var out: Array[String] = []
	for child in node.find_children("*", "Button", true, false):
		if not (child as Button).is_queued_for_deletion():
			out.append((child as Button).text)
	return out


func _test_persistence_and_new_game() -> void:
	print("Saving, loading and a new game")
	_clean()
	var main := await _spawn_main()
	for flag in [&"campaign_complete", &"ending_seen"]:
		_world.set_flag(flag, true)
	var existing := root.get_node_or_null("CampaignEnding")
	if existing != null:
		existing.free()
		paused = false
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_world.from_dict(saved)
	_check(_world.has_flag(&"campaign_complete") and _world.has_flag(&"ending_seen"), "both flags survive a WorldState round trip")
	_check(_sm.save_game("manual"), "saved")
	main.queue_free()
	await _frames(2)
	_world.reset()
	_check(_sm.load_game(), "the save loads")
	var main2 := await _spawn_main()
	_check(_world.has_flag(&"campaign_complete") and _world.has_flag(&"ending_seen"), "both flags survive a real save and load")
	_check(root.get_node_or_null("CampaignEnding") == null, "loading that save does not replay the ending")
	_qm.active.clear()
	_check(_qm.tracker_title() == "After the signal", "the post-campaign tracker line is back after the reload")
	var ending := CampaignEnding.start(self)
	ending.go_to_menu_scene = false
	await _frames(2)
	var finished_with := [&""]
	ending.finished.connect(func(c: StringName) -> void: finished_with[0] = c)
	ending._choose(CampaignEnding.CHOICE_MENU)
	await _frames(2)
	_check(finished_with[0] == CampaignEnding.CHOICE_MENU, "Main Menu reports the menu choice")
	_check(not _world.has_flag(&"campaign_complete") and not _world.has_flag(&"ending_seen"), "a new game after the menu starts without the campaign flags")
	_check(not paused, "the game is not left paused")
	main2.queue_free()
	await _frames(2)
	_clean()


func _test_ids() -> void:
	print("Flag names")
	for flag in ["campaign_complete", "ending_seen"]:
		var ok: bool = flag.length() <= 48
		for i in flag.length():
			var c: int = flag.unicode_at(i)
			ok = ok and ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95)
		_check(ok, "%s is a valid saved flag id" % flag)
