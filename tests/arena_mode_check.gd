extends SceneTree
## Arena Mode: records, isolation from the campaign save, no rewards, the run driver, the result card, the menu button.
##   godot --headless --path . -s tests/arena_mode_check.gd

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const RECORDS: String = "user://arena_mode_check_records.cfg"

var _failures: int = 0
var _checks: int = 0
var _heavy: AttackData
var _main: Node
var _wm: WaveManager
var _player: Player
var _world: Node
var _sm: Node
var _progression: Node


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


func _read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "<none>"
	return FileAccess.get_file_as_string(path)


func _fresh() -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		await _frames(3)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(3)
	_wm = _main.get_node("WaveManager")
	_wm.start_delay = 0.05
	_wm.between_waves_delay = 0.15
	_wm._wave_set = null
	_player = _main.get_node("Player")
	_player.health.max_health = 100000.0
	_player.health.health = 100000.0


func _kill_arena(max_frames: int = 2500) -> void:
	for i in max_frames:
		var alive := false
		for enemy in _wm._arena_enemies.duplicate():
			if is_instance_valid(enemy) and not enemy.is_dead():
				alive = true
				enemy.receive_hit(_heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		if not alive and (_wm.state == WaveManager.State.COMPLETE):
			return
		await physics_frame


func _run() -> void:
	_heavy = load("res://resources/attacks/heavy_1.tres") as AttackData
	_world = root.get_node_or_null("WorldState")
	_sm = root.get_node_or_null("SaveManager")
	_progression = root.get_node_or_null("Progression")
	_check(_world != null and _sm != null and _progression != null, "WorldState, SaveManager and Progression exist")
	if _world == null or _sm == null or _progression == null:
		quit(1)
		return
	ArenaMode.record_path = RECORDS
	DirAccess.remove_absolute(RECORDS)
	_test_state_and_records()
	_test_hostile_records()
	_test_save_guard()
	await _test_no_reward()
	await _test_full_run_and_isolation()
	await _test_play_again_and_failure()
	await _test_menu_button()
	DirAccess.remove_absolute(RECORDS)
	ArenaMode.end()
	print("arena_mode_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_state_and_records() -> void:
	print("-- state and records")
	_check(not ArenaMode.active, "Arena Mode is off by default")
	ArenaMode.begin()
	_check(ArenaMode.active, "begin() turns it on")
	ArenaMode.end()
	_check(not ArenaMode.active, "end() turns it off")
	_check(ArenaMode.best_time() == 0.0 and ArenaMode.best_wave() == 0 and ArenaMode.run_count() == 0, "no records yet")
	var first := ArenaMode.record_run(5, 200.0, true)
	_check(bool(first["new_best_time"]) and bool(first["new_best_wave"]), "a first clear sets both bests")
	_check(is_equal_approx(ArenaMode.best_time(), 200.0) and ArenaMode.best_wave() == 5 and ArenaMode.run_count() == 1, "the bests and the run count are stored")
	var slower := ArenaMode.record_run(5, 300.0, true)
	_check(not bool(slower["new_best_time"]) and is_equal_approx(ArenaMode.best_time(), 200.0), "a slower clear does not replace the best time")
	var faster := ArenaMode.record_run(5, 150.5, true)
	_check(bool(faster["new_best_time"]) and is_equal_approx(ArenaMode.best_time(), 150.5), "a faster clear does")
	var failed := ArenaMode.record_run(2, 40.0, false)
	_check(not bool(failed["new_best_time"]) and not bool(failed["new_best_wave"]), "a failed run beats nothing")
	_check(is_equal_approx(ArenaMode.best_time(), 150.5) and ArenaMode.best_wave() == 5 and ArenaMode.run_count() == 4, "a failed run only counts as a run")
	DirAccess.remove_absolute(RECORDS)
	ArenaMode.record_run(3, 99.0, false)
	_check(ArenaMode.best_wave() == 3 and ArenaMode.best_time() == 0.0, "a failed first run records the wave but no time")
	_check(ArenaMode.format_time(75.4) == "1:15" and ArenaMode.format_time(-5.0) == "0:00", "times format as m:ss and never go negative")
	_check(ArenaMode.SECTION.is_valid_identifier(), "the record section name is a plain identifier")


func _test_hostile_records() -> void:
	print("-- hostile record data")
	DirAccess.remove_absolute(RECORDS)
	var file := FileAccess.open(RECORDS, FileAccess.WRITE)
	file.store_string("this is [not a config\n" + char(1) + char(2) + " garbage")
	file = null
	_check(ArenaMode.best_time() == 0.0 and ArenaMode.best_wave() == 0, "a corrupt record file reads as empty")
	var out := ArenaMode.record_run(1, 10.0, false)
	_check(int(out["best_wave"]) == 1, "a run after a corrupt file still records cleanly")
	var nan_run := ArenaMode.record_run(5, NAN, true)
	_check(not bool(nan_run["new_best_time"]), "a NaN time is never stored as a best")
	var inf_run := ArenaMode.record_run(5, INF, true)
	_check(not bool(inf_run["new_best_time"]), "an infinite time is never stored as a best")
	var neg_run := ArenaMode.record_run(-4, -5.0, true)
	_check(not bool(neg_run["new_best_time"]) and ArenaMode.best_wave() == 5, "negative numbers are ignored")
	var typed := FileAccess.open(RECORDS, FileAccess.WRITE)
	typed.store_string("[arena]\nbest_time=\"fast\"\nbest_wave=[1,2]\nruns={}\n")
	typed = null
	var survived := true
	var value := ArenaMode.best_time()
	survived = survived and is_finite(value)
	_check(survived, "wrong-typed values in the file do not crash the readers")
	DirAccess.remove_absolute(RECORDS)


func _test_save_guard() -> void:
	print("-- no save is written while Arena Mode is active")
	var path: String = _sm.save_path()
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(path + suffix)
	var campaign := {"version": 4, "saved_at": 1760000000, "next_wave": 2, "completed": false,
		"inventory": {"weapon": "", "armor": "", "potions": 1}, "player": {"health": 90.0, "max_health": 100.0},
		"defeated_bosses": [], "world": {"checkpoint_id": "", "position": null}}
	_check(_sm.write_data(campaign, "test"), "control: a normal write works")
	var before := _read_file(path)
	_check(before != "<none>" and before.length() > 20, "the campaign save exists")
	ArenaMode.begin()
	var changed := campaign.duplicate(true)
	changed["next_wave"] = 5
	_check(not _sm.write_data(changed, "arena"), "write_data refuses while active")
	_check(_sm.last_error.contains("Arena"), "the refusal says why")
	_check(not _sm.autosave("arena"), "autosave refuses while active")
	_check(not _sm.save_game("manual"), "a manual save refuses while active")
	_check(_read_file(path) == before, "the save file is byte-identical after the refused writes")
	ArenaMode.end()
	_check(_sm.write_data(changed, "after"), "writes work again once Arena Mode ends")
	_check(_read_file(path) != before, "and the file changes again")
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(path + suffix)


func _test_no_reward() -> void:
	print("-- the arena reward")
	await _fresh()
	_world.reset()
	_progression.reset()
	var paid: Array = [0]
	ArenaMode.begin()
	_wm.reward_granted.connect(func(_xp: int, _credits: int) -> void: paid[0] += 1)
	_wm.start_wave_at(1)
	_wm.start_delay = 0.05
	await _kill_arena()
	_check(_wm.state == WaveManager.State.COMPLETE, "the arena can be cleared in Arena Mode")
	_check(not _world.has_flag(WaveManager.REWARD_FLAG), "the reward-claimed flag is not set")
	_check(paid[0] == 0, "the completion reward (100 XP, 120 credits) is never paid")
	ArenaMode.end()
	await _fresh()
	_world.reset()
	_progression.reset()
	var control_paid: Array = [0]
	_wm.reward_granted.connect(func(_xp: int, _credits: int) -> void: control_paid[0] += 1)
	_wm.start_wave_at(1)
	await _kill_arena()
	_check(control_paid[0] == 1, "control: the normal campaign arena pays its reward exactly once")
	_check(_world.has_flag(WaveManager.REWARD_FLAG), "control: the normal campaign arena still pays its one reward")


func _test_full_run_and_isolation() -> void:
	print("-- a full run through ArenaRun, and the campaign is untouched")
	await _fresh()
	_world.reset()
	_progression.reset()
	_world.set_flag(&"campaign_marker_flag", true)
	_progression.award_xp(40, "test")
	var path: String = _sm.save_path()
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(path + suffix)
	_check(_sm.save_game("manual"), "setup: a campaign save is written")
	var save_bytes := _read_file(path)
	var world_before: Dictionary = _world.to_dict().duplicate(true)
	var progression_before: Dictionary = _progression.to_dict().duplicate(true)
	DirAccess.remove_absolute(RECORDS)

	# What Boot does when Arena Mode is chosen: fresh runtime state, then the run.
	_sm.reset_runtime_state()
	ArenaMode.begin()
	await _fresh()
	var run := ArenaRun.attach(_main)
	run.main_menu_target = ""
	await _frames(3)
	_check(run.running and run.screen != null, "the run driver starts and has a result card")
	_check(_player.global_position.distance_to(ArenaRun.START_POSITION) < 3.0, "the player starts in the courtyard")
	_check(not _world.has_flag(&"campaign_marker_flag"), "the run starts from a fresh world, not the campaign one")
	_wm.start_delay = 0.05
	_wm.between_waves_delay = 0.15
	await _kill_arena()
	await _frames(3)
	_check(not run.running and bool(run.result.get("completed", false)), "clearing the arena finishes the run")
	_check(int(run.result["waves"]) == 5 and float(run.result["time"]) > 0.0, "five waves and a real time are reported")
	_check(run.screen.is_open() and run.screen.title_text() == "ARENA CLEARED", "the result card opens as ARENA CLEARED")
	_check(paused, "the game is paused behind the card")
	_check(ArenaMode.best_wave() == 5 and ArenaMode.best_time() > 0.0, "the time and wave were recorded")
	_check(run.screen.lines_text().contains("Waves cleared: 5 / 5"), "the card lists the waves cleared")
	_check(_read_file(path) == save_bytes, "the campaign save file is byte-identical after the whole run")
	run.screen.close()
	_check(not paused, "closing the card unpauses")
	ArenaMode.end()
	_world.reset()
	_progression.reset()
	_check(_sm.load_game(), "the untouched campaign save still loads")
	var data: Dictionary = _sm.pending_data
	_check(data.has("progression"), "and it still carries its progression section")
	_progression.from_dict(data["progression"])
	_world.from_dict((data.get("quests", {}) as Dictionary).get("world", {}) if data.has("quests") else {})
	_check(_progression.to_dict() == progression_before, "progression after Continue equals the campaign's before the run")
	_check(_world.to_dict() == world_before, "world flags after Continue equal the campaign's before the run")
	_sm.pending_load = false
	_sm.pending_data = {}
	for suffix in ["", ".tmp", ".bak"]:
		DirAccess.remove_absolute(path + suffix)


func _test_play_again_and_failure() -> void:
	print("-- play again, and failing a run")
	ArenaMode.begin()
	_sm.reset_runtime_state()
	await _fresh()
	var run := ArenaRun.attach(_main)
	run.main_menu_target = ""
	await _frames(3)
	var runs_before := ArenaMode.run_count()
	_wm.start_delay = 0.05
	_wm.between_waves_delay = 0.15
	await _kill_arena()
	await _frames(2)
	_check(run.screen.is_open(), "first clear: the card is open")
	var best_after_first := ArenaMode.best_time()
	run.screen.play_again_button().pressed.emit()
	await _frames(3)
	_check(not run.screen.is_open() and not paused, "Play again closes the card and unpauses")
	_check(run.running and run.elapsed < 1.0 and run.cleared_waves == 0, "the timer and counter restart")
	_check(_wm.current_wave <= 1 and not _wm.is_finished(), "the waves restart from wave 1")
	_check(ArenaMode.run_count() == runs_before + 1, "the finished run was counted once")
	_check(not _world.has_flag(WaveManager.REWARD_FLAG), "a replay claims no reward either")
	_wm.start_delay = 0.05
	_wm.between_waves_delay = 0.15
	await _kill_arena()
	await _frames(2)
	_check(ArenaMode.run_count() == runs_before + 2, "the second clear is a second run")
	_check(ArenaMode.best_time() <= best_after_first + 0.0001, "the best time never gets worse")
	run.screen.close()
	# Failure: the player dies in wave 2.
	run.play_again()
	await _frames(3)
	_player.health.max_health = 100.0
	_player.health.health = 100.0
	await _kill_arena_until_wave(2)
	var before_runs := ArenaMode.run_count()
	_player.health.take_damage(100000.0)
	await _frames(5)
	_check(not run.running and not bool(run.result.get("completed", true)), "dying ends the run as a failure")
	_check(run.screen.title_text() == "ARENA FAILED", "the card says ARENA FAILED")
	_check(not run.screen.play_again_button().visible, "a failed run has no Play again (the death reload follows)")
	_check(ArenaMode.run_count() == before_runs + 1, "a failed run is counted")
	ArenaMode.end()
	paused = false


func _kill_arena_until_wave(target: int, max_frames: int = 2500) -> void:
	for i in max_frames:
		if _wm.current_wave >= target and _wm.state == WaveManager.State.ACTIVE:
			return
		for enemy in _wm._arena_enemies.duplicate():
			if is_instance_valid(enemy) and not enemy.is_dead():
				enemy.receive_hit(_heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame


func _test_menu_button() -> void:
	print("-- the main menu button")
	var menu := MainMenu.new()
	root.add_child(menu)
	await _frames(2)
	var arena := menu.button("arena")
	_check(arena != null and arena.text == "Arena Mode", "the menu has an Arena Mode button")
	var pressed: Array = [0]
	menu.arena_mode_pressed.connect(func() -> void: pressed[0] += 1)
	menu.begin_loading()
	_check(arena.disabled, "it is off while the world loads")
	menu.set_ready()
	_check(not arena.disabled, "and on when the world is ready")
	arena.pressed.emit()
	_check(pressed[0] == 1, "pressing it emits arena_mode_pressed")
	_check(not menu.button("new_game").disabled and menu.button("continue") != null, "the other buttons are unaffected")
	var page := menu.get("_main_page") as Control
	for key in ["load_game", "replay_ending", "quit"]:
		if menu.button(key) != null:
			menu.button(key).visible = true
	var needed := page.get_combined_minimum_size().y
	_check(needed <= 700.0, "the main page with every button shown fits 1280x720 (needs %d px)" % int(needed))
	menu.queue_free()
	await _frames(2)
