extends SceneTree
## The "Enemies left" counter of the four later regions.
## godot --headless --path . -s tests/stage_enemies_check.gd   (uses SaveManager's per-process test file)

const REGIONS: Array = [&"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
var _checks: int = 0
var _failures: int = 0
var _rm: Node
var _world: Node
var _sm: Node
var _qm: Node


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


func _left() -> int:
	return int(StageEnemies.count(root.get_tree())["left"])


## What the region should contain, counted independently from the real node lists.
func _expected_total() -> int:
	var total := 0
	for node in root.get_tree().get_nodes_in_group("stage_enemy_sources"):
		if node is PatrolGroup:
			total += (node as PatrolGroup).scene_paths.size()
		elif node is BlackwoodEncounter:
			total += (node as BlackwoodEncounter).scene_paths.size()
	total += root.get_tree().get_nodes_in_group("facility_spawns").size()
	total += root.get_tree().get_nodes_in_group("fortress_spawns").size()
	total += root.get_tree().get_nodes_in_group("stage_boss_spawns").size()
	return total


func _wave_members() -> Dictionary:
	var out := {}
	for stage in root.get_tree().get_nodes_in_group("stage_waves"):
		for enemy in stage.get("_enemies"):
			if is_instance_valid(enemy):
				out[enemy] = true
	return out


func _alive_enemy() -> Enemy:
	var waves := _wave_members()
	for node in root.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dead() and not waves.has(enemy):
			return enemy
	return null


func _kill(enemy: Enemy) -> void:
	var attack := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 60:
		if not is_instance_valid(enemy) or enemy.is_dead():
			break
		enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame
	await _frames(3)


func _travel(region: StringName) -> bool:
	_rm.unlock(region)
	var data := RegionStore.load_data(region)
	var entry: StringName = data.entry_points.keys()[0]
	var ok: bool = await _rm.travel(region, entry, null, true)
	await _frames(40)
	return ok and _rm.current_region_id == region


func _run() -> void:
	_rm = root.get_node("RegionManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_qm = root.get_node("QuestManager")
	await _frames(3)
	_sm.reset_runtime_state()
	_sm.delete_save()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)

	# --- label wording (pure) ---
	_check(StageEnemies.label_for({"left": 7, "has_sources": true}) == "Enemies left: 7", "N > 0 reads 'Enemies left: N'")
	_check(StageEnemies.label_for({"left": 0, "has_sources": true}) == "Area clear", "N == 0 with enemies in the stage reads 'Area clear'")
	_check(StageEnemies.label_for({"left": 0, "has_sources": false}) == "", "a region without any enemies shows nothing")
	_check(StageEnemies.applies(&"dead_coast") and not StageEnemies.applies(&"outpost_17"), "it applies to the later regions, not Outpost 17")

	# --- every region: total equals the real members ---
	for region: StringName in REGIONS:
		_check(await _travel(region), "%s: reached by real travel" % region)
		var numbers := StageEnemies.count(root.get_tree())
		var expected := _expected_total()
		_check(int(numbers["left"]) > 0, "%s: enemies left > 0 on arrival (%d)" % [region, int(numbers["left"])])
		_check(int(numbers["left"]) == expected, "%s: equals the sum of the real members (%d vs %d)" % [region, int(numbers["left"]), expected])
		_check(int(numbers["left"]) == int(numbers["alive"]) + int(numbers["pending"]), "%s: alive + not yet spawned = left" % region)

	# --- Dead Coast in detail ---
	_check(await _travel(&"dead_coast"), "back in Dead Coast")
	var start := _left()
	var boss_spawns := root.get_tree().get_nodes_in_group("stage_boss_spawns").size()
	_check(boss_spawns == 2 and start >= boss_spawns, "two bosses, each counted once (spawn points %d, total %d)" % [boss_spawns, start])

	# a lazy squad streaming in does not change the number
	var lazy: PatrolGroup = null
	for node in root.get_tree().get_nodes_in_group("stage_enemy_sources"):
		if node is PatrolGroup and not (node as PatrolGroup).spawned:
			lazy = node as PatrolGroup
			break
	_check(lazy != null, "there is a squad that has not spawned yet")
	if lazy != null:
		var before_lazy := _left()
		var appeared := lazy.spawn()
		await _frames(3)
		_check(appeared > 0 and _left() == before_lazy, "a squad streaming in does not move the number (%d -> %d, %d appeared)" % [before_lazy, _left(), appeared])

	# kills lower it by exactly one each
	for i in 3:
		var target := _alive_enemy()
		if target == null:
			_check(false, "an enemy is alive to kill (round %d)" % i)
			break
		var before_kill := _left()
		await _kill(target)
		_check(_left() == before_kill - 1, "killing one lowers it by exactly one (%d -> %d)" % [before_kill, _left()])

	# a half-cleared region: flags survive a real WorldState round trip and a rebuild by real travel
	var beach: PatrolGroup = null
	for node in root.get_tree().get_nodes_in_group("stage_enemy_sources"):
		if node is PatrolGroup and (node as PatrolGroup).spawned and not (node as PatrolGroup).enemies.is_empty():
			beach = node as PatrolGroup
			break
	_check(beach != null, "a spawned squad exists to clear")
	if beach != null:
		for enemy in beach.enemies.duplicate():
			if is_instance_valid(enemy) and not enemy.is_dead():
				await _kill(enemy)
		await _frames(4)
		_check(_world.has_flag(beach.cleared_flag()), "clearing a squad sets its flag")
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_world.from_dict(saved)
	_check(beach == null or _world.has_flag(beach.cleared_flag()), "the squad's flag survives a real WorldState round trip")
	_rm.unlock(&"blackwood")
	await _rm.travel(&"blackwood", &"from_dead_coast", null, true)
	await _frames(20)
	_check(await _travel(&"dead_coast"), "Dead Coast rebuilt by real travel")
	var after := _left()
	var cleared_members := 0
	for node in root.get_tree().get_nodes_in_group("stage_enemy_sources"):
		if node is PatrolGroup and _world.has_flag((node as PatrolGroup).cleared_flag()):
			cleared_members += (node as PatrolGroup).scene_paths.size()
	_check(cleared_members > 0, "cleared squads stay cleared after the rebuild (%d members)" % cleared_members)
	_check(after == _expected_total() - cleared_members, "the number after the rebuild is the real members minus the cleared ones (%d)" % after)

	# wave enemies do not leak into the number
	var stage := root.get_tree().get_first_node_in_group("stage_waves")
	if stage != null:
		var before_wave := _left()
		stage.start()
		await _frames(120)
		var waves := _wave_members()
		_check(waves.size() > 0, "the wave encounter has spawned enemies (%d)" % waves.size())
		_check(_left() == before_wave, "wave enemies are not part of the stage number (%d -> %d)" % [before_wave, _left()])
		var in_group := 0
		for node in root.get_tree().get_nodes_in_group("enemies"):
			if waves.has(node):
				in_group += 1
		_check(in_group == waves.size(), "they are in the enemies group, so the exclusion is real (%d)" % in_group)

	# the HUD uses it
	var huds: Array[Node] = main.find_children("*", "Hud", true, false)
	_check(huds.size() == 1, "Main has one HUD")
	if huds.size() == 1:
		var hud := huds[0] as Hud
		var label: Label = hud.get("_wave_label")
		await _frames(20)
		hud.call("_refresh_wave_label")
		if hud.call("_active_stage") == null:
			_check(label.text == StageEnemies.label_text(root.get_tree()), "the HUD shows the stage counter outside a fight (%s)" % label.text)
		else:
			_check(label.text.begins_with("Wave"), "during a wave fight the HUD keeps its own counter (%s)" % label.text)

	# Outpost 17 is unchanged
	await _rm.travel(&"outpost_17", &"from_south", null, true)
	await _frames(40)
	_check(_rm.current_region_id == &"outpost_17", "back in Outpost 17")
	if huds.size() == 1:
		(huds[0] as Hud).call("_refresh_wave_label")
		var outpost_label: Label = (huds[0] as Hud).get("_wave_label")
		_check(outpost_label.text.begins_with("Wave"), "Outpost 17 keeps the arena label (%s)" % outpost_label.text)

	_sm.reset_runtime_state()
	_sm.delete_save()
	print("stage_enemies_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
