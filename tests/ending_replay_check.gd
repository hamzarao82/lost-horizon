extends SceneTree
## Headless check for "Replay Ending" on the main menu:
##   godot --headless --path . -s tests/ending_replay_check.gd
## The replay must show the ending from a finished save without changing flags, saves, progression or stats.

var _failures: int = 0
var _checks: int = 0
var _saves: Node


func _initialize() -> void:
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
		await process_frame


func _path(slot_number: int) -> String:
	return "user://save_test_%d_slot_%d.json" % [OS.get_process_id(), slot_number]


func _save_dict(complete: bool) -> Dictionary:
	var flags: Array = ["mission_first_signal_complete", "dead_coast_mission_3_complete", "campaign_complete"] if complete else ["mission_first_signal_complete"]
	return {
		"version": 4, "saved_at": 1760000000, "next_wave": 1, "completed": false,
		"inventory": {"weapon": "", "armor": "", "potions": 0}, "player": {"health": 100.0, "max_health": 100.0},
		"defeated_bosses": [], "world": {"checkpoint_id": "", "position": null}, "regions": {"current": "iron_fortress"},
		"stats": {"seconds": 7384.0, "kills": 211},
		"quests": {"active": {}, "completed": ["first_signal", "the_last_stronghold", "black_site"], "rewarded": [],
				"pending_rewards": [], "history": [], "world": {"flags": flags}},
	}


## Everything a replay must leave alone, as one comparable value.
func _fingerprint() -> String:
	var parts: Array[String] = []
	var world := root.get_node_or_null("WorldState")
	parts.append(JSON.stringify(world.to_dict()) if world != null else "no world")
	var progression := root.get_node_or_null("Progression")
	parts.append(JSON.stringify(progression.to_dict()) if progression != null else "no progression")
	var stats := root.get_node_or_null("RunStats")
	parts.append(JSON.stringify(stats.to_dict()) if stats != null else "no stats")
	parts.append(FileAccess.get_file_as_string(_path(1)) if FileAccess.file_exists(_path(1)) else "no file")
	parts.append(str(_saves.pending_load) + str(_saves.slot) + str(_saves.defeated_bosses))
	return "\n".join(parts)


func _run() -> void:
	_saves = root.get_node_or_null("SaveManager")
	if _saves == null:
		print("FAIL no SaveManager")
		quit(1)
		return
	for suffix in [".json", ".json.bak"]:
		if FileAccess.file_exists(_path(1) + suffix.trim_prefix(".json")):
			DirAccess.remove_absolute(_path(1) + suffix.trim_prefix(".json"))
	_saves.slot = 1

	# --- who gets the button ------------------------------------------------------------------
	var menu := MainMenu.new()
	root.add_child(menu)
	await _frames(2)
	_check(not menu.button("replay_ending").visible and menu.replay_ending() == null, "no save: no button and replay_ending() does nothing")
	_saves.write_data(_save_dict(false))
	menu.refresh()
	_check(not menu.button("replay_ending").visible and menu.replay_ending() == null, "unfinished campaign: the button stays hidden")
	var file := FileAccess.open(_path(1), FileAccess.WRITE)
	file.store_string("{ not json")
	file = null
	menu.refresh()
	_check(not menu.button("replay_ending").visible, "a damaged save never offers a replay")
	_saves.write_data(_save_dict(true))
	menu.refresh()
	_check(menu.button("replay_ending").visible and not menu.button("replay_ending").disabled, "a finished campaign shows Replay Ending")
	_check(menu.button("load_game").visible, "...next to Load Game")

	# --- stats come from the save only -----------------------------------------------------------
	var stats := CampaignEnding.stats_from_save(_save_dict(true))
	_check(is_equal_approx(float(stats["time_played"]), 7384.0) and int(stats["enemies"]) == 211, "replay stats: time and kills come from the save")
	var campaign: Dictionary = stats["campaign"]
	_check(int(campaign["missions_completed"]) == 3 and bool(campaign["campaign_complete"]), "replay stats: missions and completion come from the save")
	_check(int(campaign["regions_completed"]) == 3 and (stats["optional"] as Dictionary).is_empty(), "replay stats: regions counted from flags, no optional counters")
	var hostile := CampaignEnding.stats_from_save({"stats": {"seconds": "lots", "kills": [1]}, "quests": {"world": {"flags": 5}, "completed": "x"}})
	_check(float(hostile["time_played"]) == 0.0 and int(hostile["enemies"]) == 0 and int(hostile["campaign"]["missions_completed"]) == 0,
			"hostile stats and quest sections become zeros, not crashes")
	_check(not CampaignEnding.stats_from_save({})["campaign"]["campaign_complete"], "an empty save is not a finished campaign")

	# --- the replay itself ----------------------------------------------------------------------------
	var before := _fingerprint()
	var done := [0, &""]
	var ending: CampaignEnding = menu.replay_ending()
	_check(ending != null and ending.replay, "replay_ending() starts the ending in replay mode")
	if ending == null:
		quit(1)
		return
	ending.finished.connect(func(choice: StringName) -> void:
		done[0] += 1
		done[1] = choice)
	await _frames(2)
	_check(ending.layer > menu.layer and paused, "the ending runs above the menu with the tree paused")
	_check(not menu._root.visible, "the menu is hidden while the ending plays")
	_check(root.get_node_or_null("WorldState") == null or not root.get_node("WorldState").has_flag(&"ending_seen"), "starting the replay does not set ending_seen")
	ending._show_stats()
	_check(ending._body.text.contains("Time played: 2:03:04") and ending._body.text.contains("Enemies defeated: 211") and ending._body.text.contains("Missions completed: 3"),
			"the statistics page shows the saved run")
	_check(not ending._body.text.contains("Optional discoveries"), "the replay leaves out discovery counters it cannot know")
	ending._show_credits()
	ending._show_choice()
	await _frames(2)
	_check(ending._buttons.get_child_count() == 1 and (ending._buttons.get_child(0) as Button).text == "Close", "a replay offers only Close (no Main Menu / Continue Exploring)")
	ending._choose(&"explore")
	ending._choose(&"explore")
	await _frames(3)
	_check(done[0] == 1 and done[1] == &"explore", "finished fires exactly once")
	_check(not paused, "the tree is unpaused again")
	_check(menu._root.visible and not menu._ending_playing, "the menu is back and the button is usable again")
	_check(_fingerprint() == before, "flags, progression, stats, the save file and runtime state are all unchanged")
	_check(root.get_node_or_null("CampaignEnding") == null, "the ending node is gone")

	# --- again: nothing accumulates --------------------------------------------------------------------
	var second: CampaignEnding = menu.replay_ending()
	_check(second != null and menu.replay_ending() == null, "a second replay works, and cannot be started twice at once")
	var second_done := [0]
	second.finished.connect(func(_c: StringName) -> void: second_done[0] += 1)
	second._show_choice()
	second._choose(&"explore")
	await _frames(3)
	_check(_fingerprint() == before, "after two replays everything is still unchanged (nothing granted twice)")
	_check(second_done[0] == 1, "the second replay finished once")

	# --- the real ending is untouched ---------------------------------------------------------------------
	var world := root.get_node_or_null("WorldState")
	var real := CampaignEnding.start(root.get_tree())
	_check(real != null and not real.replay and real.layer == 170, "a normal ending still runs at layer 170 and is not a replay")
	await _frames(2)
	_check(world == null or world.has_flag(&"ending_seen"), "a normal ending still marks ending_seen")
	real._choose(&"explore")
	await _frames(3)
	if world != null:
		world.reset()
	menu.queue_free()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(_path(1) + suffix):
			DirAccess.remove_absolute(_path(1) + suffix)
	await _frames(2)
	print("ending_replay_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
