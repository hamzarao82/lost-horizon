extends SceneTree
## Wave encounters in the four later stages. godot --headless --path . -s tests/stage_waves_check.gd
## Uses SaveManager's per-process test file, never the real save.

const EXPECTED: Dictionary = {&"dead_coast": 3, &"blackwood": 3, &"research_complex": 3, &"iron_fortress": 4}
var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _sm: Node
var _rm: Node
var _prog: Node
var _main: Node
var _kill: AttackData


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


func _stage() -> StageWaves:
	var found := root.find_children("*", "StageWaves", true, false)
	return found[0] as StageWaves if found.size() > 0 else null


func _player() -> Player:
	return get_first_node_in_group("player") as Player


func _go(region: StringName, entry: StringName) -> bool:
	_rm.unlock(region)
	var ok: bool = await _rm.travel(region, entry, null, true)
	await _frames(25)
	var player := _player()
	if player != null:
		player.health.max_health = 100000.0
		player.health.health = 100000.0
	return ok and _rm.current_region_id == region


func _total_xp() -> int:
	return int(_prog.progress.xp) + 1000000 * int(_prog.progress.level())


## Kills everything the encounter has alive through the real hit path.
func _clear_enemies(stage: StageWaves) -> void:
	var guard := 0
	while stage.active_enemy_count() > 0 and guard < 400:
		for enemy in stage._enemies.duplicate():
			if is_instance_valid(enemy) and enemy.has_method("receive_hit") and not enemy.is_dead():
				enemy.receive_hit(_kill, enemy.global_position + Vector3(0.0, 0.0, 2.0), 60.0)
		await physics_frame
		guard += 1


## Walks the encounter through every wave, returning the largest live enemy count seen.
func _play_through(stage: StageWaves) -> int:
	var peak := 0
	var guard := 0
	while not stage.is_complete() and guard < 3000:
		peak = maxi(peak, stage.active_enemy_count())
		if stage.state == StageWaves.State.ACTIVE:
			await _clear_enemies(stage)
		if stage.state == StageWaves.State.TRANSITION:
			stage._next_in = minf(stage._next_in, 0.05)  # skip the rest window
		await physics_frame
		guard += 1
	return peak


func _wait_active(stage: StageWaves) -> void:
	var guard := 0
	while stage.state != StageWaves.State.ACTIVE and guard < 400:
		await physics_frame
		guard += 1


func _legal_flag(flag: String) -> bool:
	var plain := flag.length() > 0 and flag.length() <= 48
	for i in flag.length():
		var c := flag.unicode_at(i)
		plain = plain and ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95)
	return plain


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_rm = root.get_node("RegionManager")
	_prog = root.get_node("Progression")
	_kill = load("res://resources/attacks/heavy_1.tres") as AttackData
	await _frames(3)
	_sm.reset_runtime_state()
	_sm.delete_save()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(46)

	print("Tables")
	for region: StringName in EXPECTED:
		var table := load("res://resources/arena/stage_%s.tres" % String(region)) as ArenaWaveSet
		_check(table != null and table.wave_count() == int(EXPECTED[region]), "%s: %d waves" % [region, EXPECTED[region]])
		if table == null:
			continue
		var first_kinds := {}
		var last_kinds := {}
		var capped := true
		var loadable := true
		for index in table.wave_count():
			var entries := table.enemies_of(index)
			capped = capped and entries.size() <= StageWaves.ENEMY_CAP and entries.size() > 0
			for entry in entries:
				loadable = loadable and load(String(entry)) != null
				if index == 0:
					first_kinds[entry] = true
				if index == table.wave_count() - 1:
					last_kinds[entry] = true
		var new_kind := false
		for kind in last_kinds:
			new_kind = new_kind or not first_kinds.has(kind)
		_check(capped, "%s: every wave has 1 to %d enemies" % [region, StageWaves.ENEMY_CAP])
		_check(loadable, "%s: every enemy entry loads" % region)
		_check(new_kind, "%s: the last wave brings a kind of enemy the first did not (the mix rises)" % region)
		var amounts: Array = StageWaves.REWARDS.get(region, [])
		_check(amounts.size() == 2 and int(amounts[0]) > 100 and int(amounts[1]) > 120, "%s: the reward is above the arena's 100 XP and 120 credits" % region)

	print("Dead Coast: a full run")
	_check(await _go(&"dead_coast", &"from_outpost"), "reached Dead Coast")
	var stage := _stage()
	_check(stage != null and stage.state == StageWaves.State.IDLE, "an idle encounter waits in the stage")
	var hud_found := _main.find_children("*", "Hud", true, false)
	var hud: Hud = hud_found[0] if hud_found.size() > 0 else null
	var label: Label = hud.get("_wave_label") if hud != null else null
	hud._refresh_wave_label()
	_check(label.text == "", "no wave counter while the encounter is idle")
	var stage_xp: Array[int] = []
	_prog.xp_gained.connect(func(amount: int, source: Variant) -> void:
		if String(source) == "stage_waves":
			stage_xp.append(amount))
	var credits_before := int(_player().inventory.currency)
	_player().global_position = stage.global_position + Vector3(0.0, 0.5, 0.0)
	await _wait_active(stage)
	_check(stage.state == StageWaves.State.ACTIVE and stage.current_wave == 1, "walking into the hold area starts wave 1")
	hud._refresh_wave_label()
	_check(label.text.begins_with("Wave 1/3  Enemies: ") and stage.active_enemy_count() > 0, "the counter shows it (%s)" % label.text)
	_check(not stage.start(), "it cannot be started twice")
	var peak := await _play_through(stage)
	_check(stage.is_complete() and _world.has_flag(&"dead_coast_waves_cleared"), "the stage flag dead_coast_waves_cleared is set")
	_check(peak <= StageWaves.ENEMY_CAP, "never more than %d enemies at once (%d)" % [StageWaves.ENEMY_CAP, peak])
	_check(stage_xp == [140], "140 XP was paid, once (%s)" % str(stage_xp))
	_check(int(_player().inventory.currency) - credits_before == 160, "160 credits were paid")
	hud._refresh_wave_label()
	_check(label.text == "", "the counter goes away when the stage is secure")

	print("Reload and persistence")
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_world.from_dict(saved)
	_check(_world.has_flag(&"dead_coast_waves_cleared") and _world.has_flag(&"dead_coast_waves_reward"), "both flags survive a WorldState round trip")
	_check(_sm.save_game("manual"), "saved")
	var xp_saved := _total_xp()
	_check(await _go(&"outpost_17", &"from_south"), "left for Outpost 17")
	_check(_sm.load_game(), "loaded")
	await _frames(40)
	await _go(&"dead_coast", &"from_outpost")
	var again := _stage()
	_check(again != null and again.is_complete() and again.active_enemy_count() == 0, "after a reload the stage is still complete and spawns nothing")
	again._grant_reward()
	_check(_total_xp() == xp_saved, "a second grant pays nothing")

	print("Death mid-wave, in Blackwood")
	_world.reset()
	_check(await _go(&"blackwood", &"from_dead_coast"), "reached Blackwood")
	var bw := _stage()
	_player().global_position = bw.global_position + Vector3(0.0, 0.5, 0.0)
	await _wait_active(bw)
	_check(bw.state == StageWaves.State.ACTIVE and bw.active_enemy_count() > 0, "wave 1 is running")
	var xp_bw := _total_xp()
	bw._on_player_died()
	await _frames(3)
	_check(bw.state == StageWaves.State.FAILED, "the player dying fails the encounter")
	_check(bw.active_enemy_count() == 0, "and the survivors are gone")
	_check(not _world.has_flag(&"blackwood_waves_cleared") and _total_xp() == xp_bw, "no flag and no reward")
	bw._rearm = 0.01
	await _frames(5)
	_check(bw.state == StageWaves.State.IDLE and bw.current_wave == 0, "after the respawn it can be tried again")

	print("Leaving mid-wave leaks nothing")
	_world.reset()
	await _go(&"outpost_17", &"from_south")
	await _frames(20)
	var base_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for round_trip in 5:
		await _go(&"dead_coast", &"from_outpost")
		var s := _stage()
		_player().global_position = s.global_position + Vector3(0.0, 0.5, 0.0)
		await _frames(120)
		await _go(&"outpost_17", &"from_south")
		await _frames(10)
	var after_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check(absi(after_nodes - base_nodes) < 30, "node count is stable after five round trips (%d to %d)" % [base_nodes, after_nodes])
	_check(_stage() == null, "no stage encounter is left behind in Outpost 17")

	print("Flag names")
	for region: StringName in EXPECTED:
		_check(_legal_flag(String(RegionFlags.key(region, &"waves_cleared"))), "%s is a legal saved flag" % RegionFlags.key(region, &"waves_cleared"))
		_check(_legal_flag(String(RegionFlags.key(region, &"waves_reward"))), "%s is a legal saved flag" % RegionFlags.key(region, &"waves_reward"))

	_sm.reset_runtime_state()
	_sm.delete_save()
	print("\nstage_waves_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
