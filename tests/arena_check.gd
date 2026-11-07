extends SceneTree
## Five-wave arena: data, state machine, clear detection, rewards, failure and restart.
## godot --headless --path . -s tests/arena_check.gd

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"

var _failures: int = 0
var _checks: int = 0
var _heavy: AttackData
var _main: Node
var _wm: WaveManager
var _world: Node
var _sm: Node
var _player: Player


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


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * 60.0))


## A fresh Main with the arena stopped; the test drives the manager itself.
func _fresh(fast: bool = true) -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
		await _frames(3)
	_world.reset()
	_sm.reset_runtime_state()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(3)
	_wm = _main.get_node("WaveManager")
	_player = _main.get_node("Player")
	_player.health.max_health = 100000.0
	_player.health.health = 100000.0
	if fast:
		_wm.start_delay = 0.05
		_wm.between_waves_delay = 0.15
		_wm._wave_set = null  # rest windows from the data are three seconds: the test uses short ones


func _kill_arena(max_frames: int = 1500) -> void:
	for i in max_frames:
		var alive := false
		for enemy in _wm._arena_enemies.duplicate():
			if is_instance_valid(enemy) and not enemy.is_dead():
				alive = true
				enemy.receive_hit(_heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		if not alive:
			return
		await physics_frame


func _run() -> void:
	_heavy = load("res://resources/attacks/heavy_1.tres") as AttackData
	_world = root.get_node_or_null("WorldState")
	_sm = root.get_node_or_null("SaveManager")
	_check(_world != null and _sm != null, "WorldState and SaveManager exist")
	if _world == null or _sm == null:
		quit(1)
		return
	_test_data()
	await _test_full_run()
	await _test_world_enemies_do_not_hold_a_wave()
	await _test_watchdog_and_fallen_enemy()
	await _test_failure_and_restart()
	await _test_claim_and_reload()
	print("arena_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _weight(path: String) -> int:
	if path.ends_with("PatrolSoldier.tscn"):
		return 1
	if path.ends_with("HunterElite.tscn"):
		return 2
	if path.ends_with("HeavySoldier.tscn"):
		return 3
	return 8  # the Warden


func _test_data() -> void:
	var set := load(WaveManager.WAVE_DATA_PATH) as ArenaWaveSet
	_check(set != null and set.wave_count() == 5 and WaveManager.WAVES.size() == 5, "the wave data resource loads with five waves")
	if set == null:
		return
	var same := true
	for i in 5:
		if set.enemies_of(i) != WaveManager.WAVES[i]:
			same = false
	_check(same, "the data resource and WaveManager.WAVES list the same enemies (no drift)")
	var previous := 0
	var rising := true
	for i in 5:
		var total := 0
		for path in set.enemies_of(i):
			total += _weight(path)
		if total <= previous:
			rising = false
		previous = total
	_check(rising, "each wave is harder than the one before by its enemy mix")
	_check(set.enemies_of(4).size() == 1 and String(set.enemies_of(4)[0]).ends_with("Warden.tscn"), "wave 5 is the Warden")
	_check(set.spacing_of(0, 9.0) == 0.12 and set.rest_of(0, 9.0) == 3.0, "spacing and rest windows come from the data (0.12 s, 3.0 s)")
	_check(set.enemies_of(9).is_empty() and set.rest_of(9, 7.0) == 7.0, "an out-of-range wave falls back safely")


func _test_full_run() -> void:
	await _fresh()
	var started: Array[int] = []
	var cleared: Array[int] = []
	var finished: Array[bool] = []
	var rewards: Array[Vector2i] = []
	var states: Array[int] = []
	_wm.wave_started.connect(func(i: int, _t: int) -> void: started.append(i))
	_wm.wave_cleared.connect(func(i: int) -> void: cleared.append(i))
	_wm.all_cleared.connect(func() -> void: finished.append(true))
	_wm.reward_granted.connect(func(xp: int, c: int) -> void: rewards.append(Vector2i(xp, c)))
	_wm.state_changed.connect(func(s: int) -> void: states.append(s))
	_check(_wm.state == WaveManager.State.IDLE and not _wm.has_started(), "the arena is IDLE before it starts")
	var xp_before: int = _main.get_node("/root/Progression").progress.xp
	var credits_before: int = _player.inventory.currency
	_wm.start_wave_at(1)
	_check(_wm.state == WaveManager.State.TRANSITION, "starting enters TRANSITION (waiting for the first spawn)")
	await _seconds(0.4)
	_check(_wm.state == WaveManager.State.ACTIVE and _wm.current_wave == 1, "wave 1 is ACTIVE after its spawn (%s)" % _wm.state_name())
	_check(_wm.active_enemy_count() == 2, "wave 1 has exactly two active enemies (%d)" % _wm.active_enemy_count())
	await _seconds(1.5)
	_check(started == [1] and _wm.current_wave == 1, "wave 2 does not start while wave 1 is alive")
	var timings: Array[String] = []
	for wave in 5:
		var t0 := Time.get_ticks_msec()
		if wave > 0:
			for i in 600:
				if _wm.state == WaveManager.State.ACTIVE and _wm.current_wave == wave + 1:
					break
				await physics_frame
		_check(_wm.state == WaveManager.State.ACTIVE and _wm.current_wave == wave + 1, "wave %d is ACTIVE" % (wave + 1))
		if wave == 0:
			var one: Node = _wm._arena_enemies[0]
			for i in 40:
				if one.is_dead():
					break
				one.receive_hit(_heavy, one.global_position + Vector3(0.0, 0.0, 2.0))
				await physics_frame
			await _frames(60)
			_check(_wm.active_enemy_count() <= 1 and _wm.state == WaveManager.State.ACTIVE, "a dead enemy is no longer counted, the wave stays ACTIVE")
		await _kill_arena()
		await _seconds(1.0 if wave < 4 else 1.5)
		timings.append("w%d %.1fs" % [wave + 1, (Time.get_ticks_msec() - t0) / 1000.0])
	_check(cleared == [1, 2, 3, 4, 5], "wave_cleared fired once per wave in order (%s)" % str(cleared))
	_check(started == [1, 2, 3, 4, 5], "wave_started fired once per wave in order (%s)" % str(started))
	_check(finished.size() == 1 and _wm.is_finished() and _wm.state == WaveManager.State.COMPLETE, "all_cleared fired once and the arena is COMPLETE")
	_check(rewards.size() == 1 and rewards[0] == Vector2i(WaveManager.REWARD_XP, WaveManager.REWARD_CREDITS), "the completion reward was granted once")
	_check(_main.get_node("/root/Progression").progress.xp - xp_before >= WaveManager.REWARD_XP, "the XP arrived")
	_check(_player.inventory.currency - credits_before >= WaveManager.REWARD_CREDITS, "the credits arrived")
	_check(_world.has_flag(&"arena_complete") and _world.has_flag(&"arena_reward_claimed"), "the completion and claim flags are set")
	_wm._grant_completion_reward()
	_check(rewards.size() == 1, "a second grant pays nothing")
	_check(states.has(int(WaveManager.State.SPAWNING)) and states.has(int(WaveManager.State.CLEARED)), "SPAWNING and CLEARED states were visited")
	print("  arena timing for a bot: ", ", ".join(timings))


func _test_world_enemies_do_not_hold_a_wave() -> void:
	await _fresh()
	var stray := (load(SOLDIER) as PackedScene).instantiate() as Node3D
	stray.position = Vector3(40.0, 0.1, 40.0)
	_main.add_child(stray)
	stray.set_physics_process(false)
	_wm.start_wave_at(1)
	await _seconds(0.4)
	await _kill_arena()
	await _seconds(1.5)
	_check(_wm.current_wave == 2 and _wm.state == WaveManager.State.ACTIVE, "a patrolling guard outside the arena does not hold wave 1 open (wave %d, %s)" % [_wm.current_wave, _wm.state_name()])


func _test_watchdog_and_fallen_enemy() -> void:
	await _fresh()
	var cleared: Array[int] = []
	_wm.wave_cleared.connect(func(i: int) -> void: cleared.append(i))
	_wm.start_wave_at(1)
	await _seconds(0.4)
	var first: Node3D = _wm._arena_enemies[0]
	first.global_position = Vector3(first.global_position.x, -80.0, first.global_position.z)
	await _seconds(0.7)
	_check(not is_instance_valid(first) or first.is_queued_for_deletion(), "an enemy that fell out of the world is removed")
	_check(_wm.active_enemy_count() == 1, "and it no longer counts")
	for enemy in _wm._arena_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()  # removed without dying: no defeated signal at all
	var t0 := Time.get_ticks_msec()
	for i in 240:
		if cleared.size() > 0:
			break
		await physics_frame
	_check(cleared == [1] and (Time.get_ticks_msec() - t0) < 2000, "the watchdog clears a wave whose enemies vanished within 2 s (%d ms)" % (Time.get_ticks_msec() - t0))
	await _seconds(0.6)
	_check(_wm.current_wave == 2 and cleared.size() == 1, "and the next wave starts exactly once")


func _test_failure_and_restart() -> void:
	await _fresh()
	var failures: Array[bool] = []
	_wm.arena_failed.connect(func() -> void: failures.append(true))
	_check(_player.health.died.is_connected(_wm._on_player_died), "the arena listens for the player's death")
	_wm.start_wave_at(1)
	await _seconds(0.4)
	await _kill_arena()
	await _seconds(0.6)
	_check(_wm.current_wave == 2 and _wm.state in [WaveManager.State.ACTIVE, WaveManager.State.SPAWNING], "wave 2 is under way")
	_check(_sm.checkpoint.get("next_wave", 0) == 2, "the checkpoint remembers wave 2")
	_wm._on_player_died()
	await _seconds(0.1)
	var wave := _wm.current_wave
	await _seconds(2.0)
	_check(_wm.state == WaveManager.State.FAILED and failures.size() == 1, "death moves the arena to FAILED once")
	_check(_wm.current_wave == wave, "FAILED spawns nothing more")
	for enemy in _wm._arena_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.queue_free()
	await _seconds(1.5)
	_check(_wm.state == WaveManager.State.FAILED and not _world.has_flag(&"arena_reward_claimed"), "a failed arena cannot clear or pay a reward")
	# The scene reload that follows death builds a new arena: it resumes at the checkpoint with nothing left over.
	var checkpoint_wave: int = _sm.checkpoint.get("next_wave", 1)
	_main.queue_free()
	await _frames(3)
	var fresh := (load(MAIN_SCENE) as PackedScene).instantiate()
	fresh.get_node("WaveManager").autostart = false
	root.add_child(fresh)
	await _frames(3)
	var wm2: WaveManager = fresh.get_node("WaveManager")
	wm2.start()
	_check(wm2.current_wave == checkpoint_wave - 1 and wm2.state == WaveManager.State.TRANSITION, "the restarted arena resumes at wave %d (current_wave %d)" % [checkpoint_wave, wm2.current_wave])
	_check(wm2.active_enemy_count() == 0, "with no leftover enemies")
	_main = fresh


func _test_claim_and_reload() -> void:
	await _fresh()
	_world.set_flag(&"arena_complete")
	_world.set_flag(&"arena_reward_claimed")
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_world.from_dict(saved)
	_check(_world.has_flag(&"arena_complete") and _world.has_flag(&"arena_reward_claimed"), "the flags survive a WorldState save and load")
	_check(_sm.save_game("manual"), "a real save is written")
	_world.reset()
	_check(not _world.has_flag(&"arena_complete"), "the flags are gone after a reset")
	_check(_sm.load_game(), "the real save loads")
	await _frames(2)
	_check(_world.has_flag(&"arena_complete") and _world.has_flag(&"arena_reward_claimed"), "the flags come back from the real save")
	# A completed arena stays completed: no waves spawn and no second reward is possible.
	var wm := WaveManager.new()
	var enemies_before := get_nodes_in_group("enemies").size()
	var paid: Array[bool] = []
	wm.reward_granted.connect(func(_x: int, _c: int) -> void: paid.append(true))
	_main.add_child(wm)
	await _seconds(2.5)
	_check(wm.state == WaveManager.State.COMPLETE and wm.is_finished(), "a completed arena starts COMPLETE")
	_check(get_nodes_in_group("enemies").size() == enemies_before, "and spawns no enemies, not even the wave 5 boss")
	wm._grant_completion_reward()
	_check(paid.is_empty(), "and cannot pay the reward again")
	wm.replay()
	_check(not wm.is_finished() and wm.state == WaveManager.State.TRANSITION, "replay() deliberately restarts at wave 1")
	wm.queue_free()
