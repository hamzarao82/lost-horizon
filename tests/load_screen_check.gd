extends SceneTree
## Headless check for the Load Game list (LoadScreen + SaveManager.list_saves) and its main-menu entry:
##   godot --headless --path . -s tests/load_screen_check.gd
## Writes only this process's own test save files (user://save_test_<pid>_slot_N.json) and removes them at the end.

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


func _path(slot_number: int, suffix: String = ".json") -> String:
	return "user://save_test_%d_slot_%d%s" % [OS.get_process_id(), slot_number, suffix]


func _write_raw(slot_number: int, text: String, suffix: String = ".json") -> void:
	var file := FileAccess.open(_path(slot_number, suffix), FileAccess.WRITE)
	file.store_string(text)
	file = null


func _valid_save(extra: Dictionary = {}) -> Dictionary:
	var data := {
		"version": 4, "saved_at": 1760000000, "next_wave": 1, "completed": false,
		"inventory": {"weapon": "", "armor": "", "potions": 0}, "player": {"health": 100.0, "max_health": 100.0},
		"defeated_bosses": [], "world": {"checkpoint_id": "", "position": null},
		"regions": {"current": "dead_coast"}, "stats": {"seconds": 2530.0, "kills": 12},
	}
	data.merge(extra, true)
	return data


func _cleanup() -> void:
	for slot_number in range(1, 8):
		for suffix in [".json", ".json.tmp", ".json.bak"]:
			if FileAccess.file_exists(_path(slot_number, suffix)):
				DirAccess.remove_absolute(_path(slot_number, suffix))


func _run() -> void:
	_saves = root.get_node_or_null("SaveManager")
	_check(_saves != null and _saves.test_mode, "SaveManager is present and in test mode (own file names)")
	if _saves == null:
		quit(1)
		return
	_cleanup()
	_saves.slot = 1

	# --- no saves at all -----------------------------------------------------------
	_check(_saves.list_saves().is_empty(), "no files: the list is empty")
	var menu := MainMenu.new()
	root.add_child(menu)
	await _frames(2)
	_check(not menu.button("load_game").visible, "no saves: the main menu hides Load Game")
	_check(not menu.button("replay_ending").visible, "no saves: the main menu hides Replay Ending")
	var screen := LoadScreen.new()
	root.add_child(screen)
	await _frames(2)
	_check(screen.rows().is_empty() and screen.empty_text_visible(), "empty list shows 'No saved games.' and no rows")
	_check(screen.back_button() != null, "the empty screen still has a Back button")
	var closed_count := [0]
	screen.closed.connect(func() -> void: closed_count[0] += 1)
	screen.back_button().pressed.emit()
	await _frames(2)
	_check(closed_count[0] == 1 and not is_instance_valid(screen), "Back closes the screen once and frees it")

	# --- one good save --------------------------------------------------------------
	_saves.slot = 1
	_check(_saves.write_data(_valid_save()), "a valid slot-1 save is written")
	var listed: Array[Dictionary] = _saves.list_saves()
	_check(listed.size() == 1 and listed[0]["slot"] == 1 and listed[0]["usable"], "one usable entry for slot 1")
	_check(listed[0]["region"] == "Dead Coast", "the entry names the region from the save (%s)" % listed[0]["region"])
	_check(is_equal_approx(float(listed[0]["seconds"]), 2530.0), "play time is read from the save")
	_check(not listed[0]["campaign_complete"], "an unfinished campaign is not marked complete")
	var text := LoadScreen.describe(listed[0])
	_check(text.begins_with("Slot 1 - Dead Coast") and text.contains("Play time 0:42:10") and text.contains("Saved 20"),
			"row text shows slot, region, saved-at and play time: %s" % text.replace("\n", " / "))
	menu.refresh()
	_check(menu.button("load_game").visible and not menu.button("load_game").disabled, "a save exists: Load Game shows")
	_check(not menu.button("replay_ending").visible, "an unfinished save does not offer Replay Ending")

	# --- hostile files --------------------------------------------------------------
	_write_raw(2, "this is not json {{{")
	_write_raw(3, JSON.stringify(_valid_save({"version": 99})))
	_write_raw(4, "[1, 2, 3]")
	_write_raw(5, JSON.stringify({"version": "four", "inventory": {}, "player": {}}))
	_write_raw(6, JSON.stringify({"version": 4, "inventory": [], "player": 5}))
	_write_raw(7, "", ".json.bak")
	var before_files := _count_files()
	listed = _saves.list_saves()
	_check(listed.size() == 7, "all seven files are listed (got %d)" % listed.size())
	var by_slot := {}
	for entry in listed:
		by_slot[int(entry["slot"])] = entry
	_check(by_slot[1]["usable"] and not by_slot[2]["usable"] and not by_slot[3]["usable"], "good usable, garbage and too-new unusable")
	_check(by_slot[2]["note"] == "damaged save" and by_slot[3]["note"] == "from a newer version", "unusable entries say why")
	_check(not by_slot[4]["usable"] and not by_slot[5]["usable"] and not by_slot[6]["usable"], "wrong shapes (array, string version, bad sections) are unusable, not crashes")
	_check(not by_slot[7]["usable"] and by_slot[7]["note"] == "damaged save set aside", "an orphan .bak is listed as a set-aside damaged save")
	_check(_count_files() == before_files and FileAccess.file_exists(_path(2)) and not FileAccess.file_exists(_path(2, ".json.bak")),
			"listing is read-only: no file renamed, created or deleted")
	_check(LoadScreen.describe(by_slot[2]).begins_with("Slot 2 - unusable"), "unusable row text says unusable")
	_write_raw(1, "", ".json.bak")
	_check(_saves.list_saves().size() == 7, "a .bak next to a live slot file is not listed twice")
	DirAccess.remove_absolute(_path(1, ".json.bak"))

	# --- the screen with rows -----------------------------------------------------------
	screen = LoadScreen.new()
	root.add_child(screen)
	await _frames(2)
	_check(screen.rows().size() == 7 and not screen.empty_text_visible(), "the screen builds one row per listed file")
	_check(not screen.rows()[0].disabled and screen.rows()[1].disabled and screen.rows()[2].disabled, "unusable rows are disabled")
	var chosen := [0, -1]
	screen.slot_chosen.connect(func(s: int) -> void:
		chosen[0] += 1
		chosen[1] = s)
	screen.rows()[0].pressed.emit()
	_check(chosen[0] == 1 and chosen[1] == 1, "choosing a row reports its slot once")
	for size in [Vector2(1280, 720), Vector2(1600, 720), Vector2(1280, 2844)]:
		var need: Vector2 = screen.content_minimum_size()
		_check(need.x <= size.x and need.y <= size.y, "%dx%d: the list needs %dx%d and fits" % [size.x, size.y, need.x, need.y])
	screen.queue_free()
	await _frames(2)

	# --- main menu entry and loading a slot ---------------------------------------------
	menu.refresh()
	var continues := [0]
	menu.continue_pressed.connect(func() -> void: continues[0] += 1)
	_saves.slot = 3
	var opened: LoadScreen = menu.open_load_screen()
	await _frames(2)
	_check(opened != null and menu.open_load_screen() == opened, "Load Game opens one screen (a second press reuses it)")
	opened.rows()[0].pressed.emit()
	await _frames(2)
	_check(_saves.slot == 1 and continues[0] == 1, "choosing slot 1 makes it the active slot and continues once")
	var need_menu: Vector2 = menu._main_page.get_combined_minimum_size()
	menu.button("replay_ending").visible = true
	need_menu = menu._main_page.get_combined_minimum_size()
	_check(need_menu.y <= 720.0 and need_menu.x <= 1280.0, "the main page with every button on still fits 1280x720 (%dx%d)" % [need_menu.x, need_menu.y])
	menu.begin_loading()
	_check(menu.button("load_game").disabled and menu.button("replay_ending").disabled, "while the world loads, Load Game and Replay Ending are off")
	menu.queue_free()
	await _frames(2)

	# --- load_slot ---------------------------------------------------------------------------
	_saves.slot = 1
	_check(_saves.load_slot(1) and _saves.slot == 1, "load_slot loads a good file")
	_saves.pending_load = false
	_saves.pending_data = {}
	_saves.slot = 1
	_check(not _saves.load_slot(2) and _saves.slot == 1, "a damaged file fails to load and the active slot is restored")
	_check(not _saves.load_slot(3) and _saves.slot == 1 and FileAccess.file_exists(_path(3)), "a newer-version file is refused and left alone")
	_check(not _saves.load_slot(99) and _saves.slot == 1 and _saves.last_error == "no save", "a missing slot is refused")
	_saves.reset_runtime_state()

	_cleanup()
	print("load_screen_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _count_files() -> int:
	var dir := DirAccess.open("user://")
	var prefix := "save_test_%d_" % OS.get_process_id()
	var count := 0
	for file_name in dir.get_files():
		if file_name.begins_with(prefix):
			count += 1
	return count
