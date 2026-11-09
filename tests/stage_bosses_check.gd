extends SceneTree
## Two bosses per stage: spawned through StageBoss, fair by data, killed with real hits, one reward each, flags
## and defeats that survive a real save and load, no respawn after a reload, no leaks when leaving mid-fight.
## godot --headless --path . -s tests/stage_bosses_check.gd   (uses SaveManager's per-process test file)

const FPS: float = 60.0
const BOSSES: Array = [
	[&"dead_coast", 1, "res://resources/enemies/dc_harbor_commander.tres", "dc_harbor_cap"],
	[&"dead_coast", 2, "res://resources/enemies/dc_cove_boss.tres", "dc_cove_gloves"],
	[&"blackwood", 1, "res://resources/enemies/bw_patrol_chief.tres", "bw_chief_boots"],
	[&"blackwood", 2, "res://resources/enemies/bw_site_overseer.tres", "bw_overseer_badge"],
]

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _sm: Node
var _rm: Node


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


func _fresh_main() -> Node:
	_sm.reset_runtime_state()
	_sm.delete_save()
	_rm.reset()
	_world.reset()
	_qm.intro_done = true
	_qm.mission_autosave = false
	_qm.reset()
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	var player := main.get_node("Player") as Player
	player.health.max_health = 100000.0
	player.health.health = 100000.0
	return main


func _go(region: StringName) -> void:
	_rm.unlock(region)
	var data := RegionStore.load_data(region)
	var entry: StringName = data.entry_points.keys()[0] if data != null and not data.entry_points.is_empty() else &""
	await _rm.travel(region, entry, null, true)
	await _frames(30)


func _boss_node(region: StringName, index: int) -> StageBoss:
	for node in root.find_children("*", "StageBoss", true, false):
		var stage := node as StageBoss
		if stage != null and stage.region_id == region and stage.index == index:
			return stage
	return null


func _kill(enemy: Enemy) -> bool:
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 2500:
		if not is_instance_valid(enemy) or enemy.is_dead():
			return true
		enemy.receive_hit(heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame
	return not is_instance_valid(enemy) or enemy.is_dead()


func _pickups_of(parent: Node, item_id: String) -> int:
	var count := 0
	for node in parent.get_children():
		var pickup := node as Pickup
		if pickup != null and pickup.item != null and String(pickup.item.item_id) == item_id:
			count += 1
	return count


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_rm = root.get_node("RegionManager")
	await _frames(3)

	print("Fairness and the attack mix come from data")
	var claw := load("res://resources/attacks/experimental_claw.tres") as AttackData
	var ring := load("res://resources/attacks/experimental_ring.tres") as AttackData
	var charge := load("res://resources/attacks/experimental_charge.tres") as AttackData
	for pair in [["claw", claw], ["ring", ring]]:
		var a := pair[1] as AttackData
		_check(a.startup_frames >= 36 and a.recovery_frames >= 30, "%s: telegraph %.2f s, punish window %.2f s (>= 0.6 / 0.5)" % [pair[0], a.startup_frames / FPS, a.recovery_frames / FPS])
	_check(charge.startup_frames >= 48 and charge.recovery_frames >= 30, "charge: telegraph %.2f s, punish window %.2f s (>= 0.8 / 0.5)" % [charge.startup_frames / FPS, charge.recovery_frames / FPS])
	var mixes: Array = []
	for spec in BOSSES:
		var config := load(String(spec[2])) as EnemyConfig
		_check(config != null and config.scene_path == "res://scenes/enemies/StageBoss.tscn", "%s%d: a config on the stage boss scene" % [spec[0], spec[1]])
		var hp: float = config.hit_points
		if int(spec[1]) == 1:
			_check(hp >= 330.0 and hp <= 420.0, "%s boss 1: %.0f health between Subject Zero and the Warden" % [spec[0], hp])
		else:
			_check(hp >= 380.0 and hp <= 460.0, "%s boss 2: %.0f health (380-460)" % [spec[0], hp])
		_check(float(config.extras.get("claw_weight", 0.0)) + float(config.extras.get("ring_weight", 0.0)) + float(config.extras.get("charge_weight", 0.0)) > 0.0, "%s%d: at least one attack is enabled" % [spec[0], spec[1]])
		mixes.append(config.extras)
		var item := load("res://resources/items/%s.tres" % spec[3]) as ItemData
		_check(item != null and item.unique and ResourceLoader.exists("res://assets/icons/%s.png" % spec[3]), "%s: a unique reward with an icon" % spec[3])
		_check(String(spec[3]).length() <= 48, "%s: id within 48 characters" % spec[3])
	_check(mixes[0] != mixes[1] and mixes[2] != mixes[3], "the two bosses of a stage use different attack mixes")
	var commander_base := load("res://resources/enemies/facility_commander.tres") as EnemyConfig
	var commander := load("res://resources/enemies/rc_facility_commander_boss.tres") as EnemyConfig
	_check(commander.hit_points >= 380.0 and commander.hit_points <= 460.0 and commander.ranged != null, "the Facility Commander boss: %.0f health, still a ranged fighter" % commander.hit_points)
	_check(commander.ranged.burst_shots == commander_base.ranged.burst_shots and is_equal_approx(commander.ranged.shot_spacing, commander_base.ranged.shot_spacing), "its burst is the tested commander burst")
	_check(commander.unique_drop_path == "", "the helper, not the config, owns its reward")

	print("Dead Coast and Blackwood bosses: spawn, group, kill, flag, one reward")
	var main := await _fresh_main()
	var player := main.get_node("Player") as Player
	for region: StringName in [&"dead_coast", &"blackwood"]:
		await _go(region)
		for index in [1, 2]:
			var stage := _boss_node(region, index)
			_check(stage != null, "%s boss %d: the helper exists" % [region, index])
			if stage == null:
				continue
			var spawn_flag := StageBoss.flag_for(region, index)
			_check(String(spawn_flag).length() <= 48 and String(spawn_flag) == "%s_boss_%d_defeated" % [region, index], "flag name %s" % spawn_flag)
			_check(stage.boss != null and is_instance_valid(stage.boss), "%s boss %d: spawned through the helper" % [region, index])
			if stage.boss == null or not is_instance_valid(stage.boss):
				continue
			_check(not stage.boss.is_in_group("boss"), "no health bar for a boss the player is nowhere near")
			player.global_position = stage.boss.global_position + Vector3(0.0, 0.5, 12.0)
			await _frames(8)
			_check(stage.boss.is_in_group("boss"), "the health bar group is joined when the player comes near")
			_check(stage.is_in_group("stage_boss_spawns"), "and marked for the arrow")
			# Room to fight: solid ground under the spawn and no wall or prop within a dodge radius of it.
			var space := stage.get_world_3d().direct_space_state
			var ray := PhysicsRayQueryParameters3D.create(stage.global_position + Vector3(0.0, 6.0, 0.0), stage.global_position + Vector3(0.0, -6.0, 0.0), 1)
			var ground := space.intersect_ray(ray)
			_check(not ground.is_empty() and absf(ground["position"].y - stage.global_position.y) < 1.2, "%s boss %d: solid ground under the spawn" % [region, index])
			var probe := SphereShape3D.new()
			probe.radius = 2.4
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = probe
			query.transform = Transform3D(Basis.IDENTITY, stage.global_position + Vector3(0.0, 2.6, 0.0))
			query.collision_mask = 1
			var blockers := 0
			for hit in space.intersect_shape(query, 8):
				if not String((hit["collider"] as Node).name) in ["TerrainBody", "GroundBody"]:  # the ground itself is not a blocker
					blockers += 1
			_check(blockers == 0, "%s boss %d: nothing solid within 2.4 m of the spawn (%d)" % [region, index, blockers])
			var boss := stage.boss
			_check(boss.hit_points > 300.0, "%s boss %d: %s with %.0f health" % [region, index, boss.display_name, boss.hit_points])
			var mix_ok: bool = boss is StageBossEnemy
			_check(mix_ok, "it is a StageBossEnemy")
			if mix_ok:
				var config: EnemyConfig = load(String(BOSSES[(0 if region == &"dead_coast" else 2) + index - 1][2]))
				_check(is_equal_approx((boss as StageBossEnemy).charge_weight, float(config.extras["charge_weight"])), "its attack mix comes from the config")
			var reward_id: String = BOSSES[(0 if region == &"dead_coast" else 2) + index - 1][3]
			player.health.health = player.health.max_health
			var down := await _kill(boss)
			_check(down, "%s boss %d: killed with real hits" % [region, index])
			await _frames(8)
			_check(_world.has_flag(spawn_flag), "the defeat flag is set")
			_check(PersistentIds.is_claimed(region, StageBoss.claim_for(index)), "the defeat is claimed")
			var parent := stage.get_parent()
			_check(_pickups_of(parent, reward_id) == 1, "exactly one reward lies on the floor (%d)" % _pickups_of(parent, reward_id))

	print("A real save and load: the boss stays down and an unclaimed reward waits")
	await _go(&"dead_coast")
	var parent_dc := _boss_node(&"dead_coast", 1).get_parent()
	_check(_sm.save_game("manual"), "saved in Dead Coast")
	main.queue_free()
	await _frames(4)
	_rm.reset()
	_world.reset()
	_qm.reset()
	_check(_sm.load_game(), "the save loads")
	var main2: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main2.get_node("WaveManager").autostart = false
	root.add_child(main2)
	await _frames(70)
	_check(_rm.current_region_id == &"dead_coast", "the game restarts in Dead Coast")
	var stage1 := _boss_node(&"dead_coast", 1)
	var stage2 := _boss_node(&"dead_coast", 2)
	_check(stage1 != null and stage2 != null, "both helpers exist after the load")
	if stage1 != null and stage2 != null:
		_check(stage1.boss == null and stage2.boss == null, "no defeated boss respawns")
		_check(_world.has_flag(StageBoss.flag_for(&"dead_coast", 1)) and _world.has_flag(StageBoss.flag_for(&"dead_coast", 2)), "both defeat flags survived")
		var parent2 := stage1.get_parent()
		_check(_pickups_of(parent2, "dc_harbor_cap") == 1 and _pickups_of(parent2, "dc_cove_gloves") == 1, "both never-picked-up rewards wait at their spawns (%d, %d)" % [_pickups_of(parent2, "dc_harbor_cap"), _pickups_of(parent2, "dc_cove_gloves")])
		var player2 := main2.get_node("Player") as Player
		var cap := load("res://resources/items/dc_harbor_cap.tres") as ItemData
		player2.inventory.collect(cap)
		_check(player2.inventory.is_unique_claimed("dc_harbor_cap"), "picking the reward up claims it")
		_check(_sm.save_game("manual"), "saved again")
		main2.queue_free()
		await _frames(4)
		_rm.reset()
		_world.reset()
		_qm.reset()
		_check(_sm.load_game(), "the second save loads")
		var main3: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
		main3.get_node("WaveManager").autostart = false
		root.add_child(main3)
		await _frames(70)
		var s1 := _boss_node(&"dead_coast", 1)
		if s1 != null:
			var parent3 := s1.get_parent()
			_check(_pickups_of(parent3, "dc_harbor_cap") == 0, "a claimed reward is never put back")
			_check(_pickups_of(parent3, "dc_cove_gloves") == 1, "the other, still unclaimed, reward is still waiting")
		main3.queue_free()
		await _frames(4)

	print("No leaks when leaving mid-fight")
	_rm.reset()
	_world.reset()
	_qm.reset()
	_sm.reset_runtime_state()
	_sm.delete_save()
	var main4: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main4.get_node("WaveManager").autostart = false
	root.add_child(main4)
	await _frames(46)
	await _go(&"dead_coast")
	var before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for round in 5:
		await _rm.travel(&"outpost_17", &"from_south", null, true)
		await _frames(10)
		await _go(&"dead_coast")
	var after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check(abs(after - before) <= 40, "five round trips leave the node count flat (%d -> %d)" % [before, after])
	var live := 0
	for node in root.find_children("*", "StageBoss", true, false):
		if (node as StageBoss).boss != null and is_instance_valid((node as StageBoss).boss):
			live += 1
	_check(live <= 2, "at most the stage's two bosses exist (%d)" % live)

	main4.queue_free()
	await _frames(4)
	_sm.reset_runtime_state()
	_sm.delete_save()
	print("stage_bosses_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
