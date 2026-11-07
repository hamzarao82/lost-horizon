extends SceneTree
## Research Complex components (Milestone 8): godot --headless --path . -s tests/facility_components_check.gd
## Doors, terminals, panels, the two multi-step puzzles, spawn points and mission triggers, each through
## a real WorldState and RegionManager save round trip ("reload").

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"

var _failures: int = 0
var _checks: int = 0
var _root3d: Node3D
var _world: Node
var _rm: Node
var _player: Player


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), message)
	if not condition:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


## Saves and restores exactly what a real save file keeps for these systems.
func _reload() -> void:
	var world_snap: Dictionary = _world.to_dict()
	var region_snap: Dictionary = _rm.to_dict()
	_world.reset()
	_rm.reset()
	_world.from_dict(JSON.parse_string(JSON.stringify(world_snap)))
	_rm.from_dict(JSON.parse_string(JSON.stringify(region_snap)))


func _fresh() -> void:
	_world.reset()
	_rm.reset()
	if is_instance_valid(_root3d):
		_root3d.free()
	_root3d = Node3D.new()
	root.add_child(_root3d)


func _run() -> void:
	_world = root.get_node_or_null("WorldState")
	_rm = root.get_node_or_null("RegionManager")
	_check(_world != null and _rm != null, "WorldState and RegionManager autoloads exist")
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(500.0, 0.1, 500.0)
	await _frames(3)
	await _test_ids()
	await _test_door()
	await _test_terminal()
	await _test_panel()
	await _test_base_puzzle()
	await _test_lab_puzzle()
	await _test_containment()
	await _test_spawns()
	await _test_trigger()
	await _test_configs()
	print("facility_components_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_ids() -> void:
	print("-- ids")
	var all_ids: Array[StringName] = []
	for level in FacilityIds.LEVELS:
		all_ids.append(FacilityIds.credential_flag(level))
	var lab := LabPowerPuzzle.new()
	var cont := ContainmentOverride.new()
	for puzzle in [lab, cont]:
		all_ids.append_array((puzzle as MultiStepPuzzle).all_flag_ids())
	var bad: PackedStringArray = []
	for id in all_ids:
		if not FacilityIds.is_saveable(String(id)):
			bad.append(String(id))
	_check(all_ids.size() >= 9 and bad.is_empty(), "every credential and puzzle flag is [a-z0-9_] and <= 48 chars (%d scanned) %s" % [all_ids.size(), str(bad)])
	_check(not FacilityIds.is_saveable("research_complex.lab_done"), "a dotted id is correctly rejected by the scan")
	_check(not FacilityIds.is_saveable("x".repeat(49)), "an over-long id is correctly rejected by the scan")
	lab.free()
	cont.free()
	await _frames(1)


func _test_door() -> void:
	print("-- security door")
	_fresh()
	var door := SecurityDoor.new()
	door.door_id = &"admin_gate"
	door.credential = &"admin"
	_root3d.add_child(door)
	await _frames(2)
	_check(door.locked and not door.can_interact(), "the door is locked without the credential")
	_check(door.current_prompt().contains("admin"), "the locked caption names the required credential (%s)" % door.current_prompt())
	_check(not door.interact(_player) and not door.is_open, "using a locked door does nothing")
	FacilityIds.set_flag(FacilityIds.credential_flag(&"admin"))
	await _frames(1)
	_check(not door.locked, "the credential unlocks it")
	_check(door.interact(_player) and door.is_open, "it opens once")
	_check(PersistentIds.is_claimed(FacilityIds.REGION, door.claim_id()), "opening is claimed in the region state")
	_reload()
	door.free()
	var again := SecurityDoor.new()
	again.door_id = &"admin_gate"
	again.credential = &"admin"
	_root3d.add_child(again)
	await _frames(2)
	_check(again.is_open, "after a save and reload the door is still open")
	# Prove the claim path on its own: drop the door's own world flag and reload again.
	_world.set_flag(again.open_flag(), false)
	_reload()
	again.free()
	var third := SecurityDoor.new()
	third.door_id = &"admin_gate"
	_root3d.add_child(third)
	await _frames(2)
	_check(third.is_open, "the PersistentIds claim alone keeps it open")
	var other := SecurityDoor.new()
	other.door_id = &"lab_gate"
	other.credential = &"lab"
	_root3d.add_child(other)
	await _frames(2)
	_check(not other.is_open and other.locked, "a different door and credential level stay shut")


func _test_terminal() -> void:
	print("-- research terminal")
	_fresh()
	var terminal := ResearchTerminal.new()
	terminal.interaction_id = &"archive_terminal"
	terminal.terminal_title = "Archive"
	terminal.requires_flag = &"archive_power"
	terminal.credential = &"medical"
	terminal.pages = PackedStringArray(["Subject records.", "Page two."])
	_root3d.add_child(terminal)
	await _frames(2)
	_check(terminal.get_node_or_null("ConsoleBody") != null and terminal.get_node_or_null("ConsoleScreen") != null, "the terminal has a visible console model")
	_check(terminal.locked and terminal.current_prompt().contains("no power"), "no power: %s" % terminal.current_prompt())
	_world.set_flag(&"archive_power")
	await _frames(1)
	_check(terminal.locked and terminal.current_prompt().contains("medical"), "powered but no credential: %s" % terminal.current_prompt())
	FacilityIds.set_flag(FacilityIds.credential_flag(&"medical"))
	await _frames(1)
	_check(not terminal.locked, "power and credential unlock it")
	var progression := root.get_node_or_null("Progression")
	var before: int = progression.progress.xp if progression else 0
	_check(terminal.interact(_player), "it can be read")
	var after_first: int = progression.progress.xp if progression else 0
	var expected: int = int(progression.config.discovery_xp) if progression else 0
	_check(after_first - before == expected and expected > 0, "the first read pays the existing discovery XP once (%d of %d)" % [after_first - before, expected])
	_check(FacilityIds.has_flag(terminal.found_flag()), "reading sets doc_<id>_found (%s)" % terminal.found_flag())
	terminal.interact(_player)
	var after_second: int = progression.progress.xp if progression else 0
	_check(after_second == after_first, "reading again pays nothing")
	_reload()
	terminal.free()
	var again := ResearchTerminal.new()
	again.interaction_id = &"archive_terminal"
	again.requires_flag = &"archive_power"
	_root3d.add_child(again)
	await _frames(2)
	var before_reload: int = progression.progress.xp if progression else 0
	again.interact(_player)
	var after_reload: int = progression.progress.xp if progression else 0
	_check(after_reload == before_reload and PersistentIds.is_claimed(FacilityIds.REGION, again.read_claim_id()), "after a reload the read is still claimed: no second XP payout")
	_check(FacilityIds.is_saveable(String(again.found_flag())), "the found flag is saveable")


func _test_panel() -> void:
	print("-- access panel")
	_fresh()
	var panel := AccessPanel.new()
	panel.interaction_id = &"lab_panel"
	panel.grants = &"lab"
	panel.requires_flag = &"keycard_found"
	_root3d.add_child(panel)
	await _frames(2)
	_check(panel.get_node_or_null("ConsoleBody") != null, "the access panel has a visible model")
	_check(panel.locked and not panel.interact(_player), "the panel is dead until its keycard is found")
	_world.set_flag(&"keycard_found")
	await _frames(1)
	_check(panel.interact(_player), "with the keycard the swipe works")
	_check(FacilityIds.has_flag(&"credential_lab"), "it grants credential_lab")
	_check(not panel.interact(_player), "it works only once")
	_reload()
	panel.free()
	var again := AccessPanel.new()
	again.interaction_id = &"lab_panel"
	again.grants = &"lab"
	_root3d.add_child(again)
	await _frames(2)
	_check(FacilityIds.has_flag(&"credential_lab") and again.is_used(), "after a reload the credential is kept and the panel is spent")


func _make_puzzle(ordered: bool) -> MultiStepPuzzle:
	var puzzle := MultiStepPuzzle.new()
	puzzle.puzzle_id = &"demo"
	puzzle.steps = [&"a", &"b", &"c"]
	puzzle.ordered = ordered
	_root3d.add_child(puzzle)
	return puzzle


func _test_base_puzzle() -> void:
	print("-- multi step puzzle base")
	_fresh()
	var puzzle := _make_puzzle(true)
	var fails: Array[String] = []
	var completions := [0]
	puzzle.step_failed.connect(func(_s: StringName, reason: String) -> void: fails.append(reason))
	puzzle.completed.connect(func() -> void: completions[0] += 1)
	await _frames(1)
	_check(not puzzle.complete_step(&"b") and fails == ["out_of_order"], "an ordered puzzle refuses a later step")
	_check(puzzle.complete_step(&"a") and puzzle.complete_step(&"b"), "steps complete in order")
	_check(not puzzle.complete_step(&"b") and not puzzle.complete_step(&"zzz"), "a repeated or unknown step is ignored")
	var state := puzzle.capture_state()
	_check(state["done"] == ["a", "b"] and not state["completed"], "capture lists exactly the finished steps")
	puzzle.fail(&"c", "test")
	_check(puzzle.is_step_done(&"a") and puzzle.is_step_done(&"b"), "a failure never undoes finished steps")
	_reload()
	puzzle.free()
	var restored := _make_puzzle(true)
	await _frames(1)
	_check(restored.is_step_done(&"a") and restored.is_step_done(&"b") and restored.current_step() == &"c", "a reload restores steps from saved flags")
	restored.completed.connect(func() -> void: completions[0] += 1)
	_check(restored.complete_step(&"c") and restored.is_completed(), "the last step completes the puzzle")
	_check(completions[0] == 1 and not restored.complete_step(&"c"), "completion fires once")
	_reload()
	restored.free()
	var done := _make_puzzle(true)
	await _frames(1)
	_check(done.is_completed(), "a completed puzzle stays completed after a reload")
	# A damaged save: only the last step flag exists. It must not strand the puzzle.
	_fresh()
	var probe := _make_puzzle(true)
	_world.set_flag(probe.step_flag(&"c"))
	probe.restore_state()
	_check(probe.is_completed(), "an ordered puzzle with only a late flag restores fully (no soft lock)")
	_fresh()
	var loose := _make_puzzle(false)
	await _frames(1)
	_check(loose.complete_step(&"c") and loose.complete_step(&"a") and not loose.is_completed(), "an any-order puzzle accepts steps in any order")
	_check(loose.complete_step(&"b") and loose.is_completed(), "and completes when all are done")


func _test_lab_puzzle() -> void:
	print("-- lab power puzzle (Puzzle B)")
	_fresh()
	var puzzle := LabPowerPuzzle.new()
	_root3d.add_child(puzzle)
	await _frames(1)
	var failures: Array[String] = []
	var completions := [0]
	puzzle.step_failed.connect(func(_s: StringName, reason: String) -> void: failures.append(reason))
	puzzle.completed.connect(func() -> void: completions[0] += 1)
	_check(puzzle.display_text().contains("1:ON") and puzzle.hint_text().length() > 20, "the wall display and the hint document exist")
	puzzle.input(&"breaker_1")  # a wrong breaker (target has it OFF)
	puzzle.input(&"lever")
	_check(failures == ["pattern_mismatch"] and not puzzle.breakers.has(true), "a wrong lever pull trips every breaker off")
	_check(not puzzle.is_step_done(&"pattern") and not puzzle.is_completed(), "and loses no progress (nothing was finished)")
	puzzle.input(&"breaker_0")
	puzzle.input(&"breaker_2")
	_check(not puzzle.is_step_done(&"pattern"), "a partial pattern is not accepted")
	puzzle.input(&"breaker_3")
	_check(puzzle.is_step_done(&"pattern") and puzzle.current_step() == &"engage", "the right pattern completes the first step")
	var locked_copy := puzzle.breakers.duplicate()
	puzzle.input(&"breaker_0")
	_check(puzzle.breakers == locked_copy, "a correct pattern is locked in: later presses change nothing")
	puzzle.input(&"lever")
	_check(puzzle.is_completed() and completions[0] == 1, "the lever completes the puzzle once")
	puzzle.input(&"lever")
	_check(completions[0] == 1, "another pull does not complete it again")
	# Capture and restore at every stage.
	for stage in 3:
		_fresh()
		var p := LabPowerPuzzle.new()
		_root3d.add_child(p)
		await _frames(1)
		if stage >= 1:
			for i in [0, 2, 3]:
				p.input(StringName("breaker_%d" % i))
		if stage >= 2:
			p.input(&"lever")
		var snapshot := p.capture_state()
		_reload()
		p.free()
		var q := LabPowerPuzzle.new()
		_root3d.add_child(q)
		await _frames(1)
		q.restore_state(snapshot)
		match stage:
			0:
				_check(not q.is_step_done(&"pattern") and q.current_step() == &"pattern", "restore at stage 0: still at the pattern step")
			1:
				_check(q.is_step_done(&"pattern") and q.breakers == q.pattern and q.current_step() == &"engage", "restore at stage 1: pattern kept and breakers shown correct")
				_check(q.engage() and q.is_completed(), "and the lever still finishes it")
			2:
				_check(q.is_completed(), "restore at stage 2: completed")


func _test_containment() -> void:
	print("-- containment override (Puzzle C)")
	_fresh()
	var puzzle := ContainmentOverride.new()
	_root3d.add_child(puzzle)
	await _frames(1)
	var control := ContainmentControl.new()
	_root3d.add_child(control)
	control.bind(puzzle)
	await _frames(1)
	_check(control.lamp_color == ContainmentControl.COLORS[0], "the lamp starts red (locked)")
	var reasons: Array[String] = []
	puzzle.step_failed.connect(func(_s: StringName, reason: String) -> void: reasons.append(reason))
	_check(puzzle.activate_terminal(&"b") and puzzle.activate_terminal(&"a"), "terminals switch on in any order")
	_check(control.lamp_color == ContainmentControl.COLORS[1] and puzzle.window_left > 44.0, "the first terminal opens the 45 s window (lamp amber)")
	puzzle.advance(46.0)
	_check(reasons == ["window_expired"] and puzzle.active.is_empty(), "when the window runs out the unfinished terminals switch off again")
	_check(not puzzle.is_step_done(&"terminals") and puzzle.current_step() == &"terminals", "and nothing completed was touched (nothing was)")
	_check(not puzzle.activate_terminal(&"x"), "an unknown terminal is ignored")
	puzzle.activate_terminal(&"c")
	puzzle.advance(20.0)
	puzzle.activate_terminal(&"a")
	puzzle.activate_terminal(&"b")
	_check(puzzle.is_step_done(&"terminals") and puzzle.status() == 2, "all three inside one window complete the terminals step")
	puzzle.advance(100.0)
	_check(puzzle.is_step_done(&"terminals"), "time passing never undoes a completed step")
	var released := [false]
	puzzle.completed.connect(func() -> void: released[0] = true)
	_check(puzzle.release() and puzzle.is_completed() and released[0], "the lockdown lever completes the puzzle")
	_check(control.lamp_color == ContainmentControl.COLORS[3], "the lamp turns green")
	# Pressing the lever too early only reports; it does not reset the window.
	_fresh()
	var early := ContainmentOverride.new()
	_root3d.add_child(early)
	await _frames(1)
	var early_reasons: Array[String] = []
	early.step_failed.connect(func(_s: StringName, reason: String) -> void: early_reasons.append(reason))
	early.activate_terminal(&"a")
	_check(not early.release() and early_reasons == ["terminals_offline"] and early.active.has(&"a"), "an early lever pull is refused without resetting the window")
	# Capture and restore mid-window and after each step.
	var snap_mid := early.capture_state()
	_reload()
	early.free()
	var mid := ContainmentOverride.new()
	_root3d.add_child(mid)
	await _frames(1)
	mid.restore_state(snap_mid)
	_check(mid.active.is_empty() and mid.window_left == 0.0 and mid.current_step() == &"terminals", "restore mid-window: the window starts fresh, no steps lost, not stuck")
	for t in [&"a", &"b", &"c"]:
		mid.activate_terminal(t)
	var snap_terminals := mid.capture_state()
	_reload()
	mid.free()
	var after_terminals := ContainmentOverride.new()
	_root3d.add_child(after_terminals)
	await _frames(1)
	after_terminals.restore_state(snap_terminals)
	_check(after_terminals.is_step_done(&"terminals") and after_terminals.current_step() == &"release" and after_terminals.active.size() == 3, "restore after the terminals: the lever is next")
	after_terminals.release()
	_reload()
	after_terminals.free()
	var finished := ContainmentOverride.new()
	_root3d.add_child(finished)
	await _frames(1)
	_check(finished.is_completed(), "restore after release: completed")
	var all_ids := finished.all_flag_ids()
	var bad := 0
	for id in all_ids:
		if not FacilityIds.is_saveable(String(id)):
			bad += 1
	_check(bad == 0, "all containment flags are saveable")


func _guard_config() -> FacilityEnemyConfig:
	return load("res://resources/enemies/facility_security_guard.tres") as FacilityEnemyConfig


func _test_spawns() -> void:
	print("-- facility enemy spawn")
	_fresh()
	var spawn := FacilityEnemySpawn.new()
	spawn.spawn_id = &"guard_a"
	spawn.config = _guard_config()
	spawn.position = Vector3(100.0, 0.1, 100.0)
	_root3d.add_child(spawn)
	await _frames(2)
	_check(spawn.can_spawn(), "a fresh spawn point can spawn")
	var enemy := spawn.trigger()
	await _frames(2)
	_check(enemy != null and enemy.is_inside_tree() and enemy.display_name == "Security Guard" and enemy.hit_points == 70.0, "the config's stats were applied before it entered the tree")
	_check(spawn.trigger() == null, "a second trigger spawns nothing")
	enemy._health.take_damage(99999.0)
	await _frames(3)
	_check(spawn.is_cleared() and PersistentIds.is_claimed(FacilityIds.REGION, spawn.cleared_id()), "defeating it writes the cleared claim")
	_reload()
	spawn.free()
	var again := FacilityEnemySpawn.new()
	again.spawn_id = &"guard_a"
	again.config = _guard_config()
	again.position = Vector3(100.0, 0.1, 100.0)
	_root3d.add_child(again)
	await _frames(2)
	_check(again.is_cleared() and again.trigger() == null, "after a reload the cleared enemy does not come back")
	# The global patroller cap.
	var saved_count: int = Enemy.active_patrollers
	Enemy.active_patrollers = PatrolGroup.MAX_ACTIVE_PATROLLERS
	var patrol := FacilityEnemySpawn.new()
	patrol.spawn_id = &"guard_patrol"
	patrol.config = _guard_config()
	patrol.route_points = PackedVector3Array([Vector3.ZERO, Vector3(4.0, 0.0, 0.0)])
	patrol.position = Vector3(120.0, 0.1, 120.0)
	_root3d.add_child(patrol)
	await _frames(1)
	_check(not patrol.can_spawn() and patrol.trigger() == null, "a patrolling spawn respects the global patroller cap")
	Enemy.active_patrollers = saved_count
	# The elite's pending reward.
	var elite_config := load("res://resources/enemies/facility_elite_subject.tres") as FacilityEnemyConfig
	var elite_spawn := FacilityEnemySpawn.new()
	elite_spawn.spawn_id = &"elite_zero"
	elite_spawn.config = elite_config
	elite_spawn.position = Vector3(140.0, 0.1, 140.0)
	_root3d.add_child(elite_spawn)
	await _frames(1)
	PersistentIds.claim(FacilityIds.REGION, elite_spawn.cleared_id())  # cleared in an earlier life, reward never taken
	var sigil := load("res://resources/items/containment_sigil.tres") as ItemData
	_check(elite_spawn.restore_pending_reward(), "a cleared elite whose reward was not taken puts it back")
	_check(not _find_pickups().is_empty(), "the reward pickup exists")
	_player.inventory.collect(sigil)
	_check(_player.inventory.is_unique_claimed(String(sigil.item_id)), "collecting it claims the unique item")
	_check(not elite_spawn.restore_pending_reward(), "once owned it is never put back again")


func _find_pickups() -> Array:
	return _root3d.find_children("*", "Pickup", true, false)


func _test_trigger() -> void:
	print("-- mission trigger")
	_fresh()
	var events: Array[StringName] = []
	_world.area_entered.connect(func(id: StringName) -> void: events.append(id))
	var trigger := MissionTrigger.new()
	trigger.trigger_id = &"enter_admin"
	trigger.event_id = &"area_admin_wing"
	_root3d.add_child(trigger)
	await _frames(1)
	_check(trigger.fire(), "the first fire succeeds")
	_check(not trigger.fire(), "the second fire does nothing")
	_check(events == [&"area_admin_wing"], "the quest event fired exactly once (%s)" % str(events))
	_reload()
	trigger.free()
	var again := MissionTrigger.new()
	again.trigger_id = &"enter_admin"
	again.event_id = &"area_admin_wing"
	_root3d.add_child(again)
	await _frames(1)
	_check(not again.fire() and events.size() == 1, "after a reload it does not fire again")


func _test_configs() -> void:
	print("-- configs")
	for name in ["security_guard", "heavy_guard", "experimental_subject", "elite_subject"]:
		var config := load("res://resources/enemies/facility_%s.tres" % name) as FacilityEnemyConfig
		_check(config != null and config.validate().is_empty(), "%s config loads and validates %s" % [name, str(config.validate() if config else "missing")])
		var scene := load(config.base_scene_path) as PackedScene
		var instance := scene.instantiate() as Enemy
		_check(instance != null, "%s base scene instantiates to an Enemy" % name)
		if instance != null:
			config.apply(instance)
			_check(instance.hit_points == config.hit_points and instance.swing_path == config.swing_path, "%s config applies hit points and attack" % name)
			instance.free()
	var guard := _guard_config()
	var heavy := load("res://resources/enemies/facility_heavy_guard.tres") as FacilityEnemyConfig
	_check(heavy.hit_points > guard.hit_points and heavy.move_speed < guard.move_speed, "the heavy guard is tougher and slower than the guard")
