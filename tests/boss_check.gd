extends SceneTree
## Headless Warden check (merge into run_tests.gd if wanted):
##   godot --headless --path . -s tests/boss_check.gd

var _failures: int = 0
var _checks: int = 0


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


func _hp(boss: Enemy) -> float:
	return (boss.get_node("HealthComponent") as HealthComponent).health


func _spawn(player_hp: float = 100000.0) -> Array:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(3)
	var player := main.get_node("Player") as Player
	player.health.max_health = player_hp
	player.health.health = player_hp
	var boss := (load("res://scenes/enemies/Warden.tscn") as PackedScene).instantiate() as Warden
	boss.position = Vector3(0, 0.1, -12)
	main.add_child(boss)
	await _frames(2)
	return [main, player, boss]


func _run() -> void:
	print("Warden")
	var set1 := await _spawn()
	var main := set1[0] as Node
	var player := set1[1] as Player
	var boss := set1[2] as Warden

	_check(boss.display_name == "The Warden" and _hp(boss) == 420.0, "boss has 420 HP and its name")
	_check(boss.is_in_group("boss") and boss.is_in_group("enemies"), "boss is in the boss and enemies groups")

	# Super armor: light hits do not interrupt, the heavy finisher does.
	boss.set_physics_process(false)
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	boss.state = Enemy.State.CHASE
	boss.receive_hit(light, player.global_position)
	_check(boss.state == Enemy.State.CHASE and _hp(boss) == 410.0, "a light hit damages but does not interrupt")
	boss.receive_hit(heavy, player.global_position)
	_check(boss.state == Enemy.State.STAGGER, "a heavy hit staggers the boss briefly")
	_check(boss._stagger_time < 0.2, "stagger is short (%.2fs)" % boss._stagger_time)
	boss.set_physics_process(true)
	boss.state = Enemy.State.CHASE

	# Signals for audio
	var seen := {"hit": 0, "swing": 0, "defeated": 0}
	boss.was_hit.connect(func(_dodged: bool) -> void: seen["hit"] += 1)
	boss.swing_started.connect(func() -> void: seen["swing"] += 1)
	boss.defeated.connect(func() -> void: seen["defeated"] += 1)
	boss.receive_hit(light, player.global_position)
	_check(seen["hit"] == 1, "was_hit is emitted")

	# Slam telegraph and damage: stand next to the boss and wait for the first swing
	player.global_position = boss.global_position + Vector3(0, 0, 2.2)
	boss._cooldown = 0.0
	boss.state = Enemy.State.CHASE
	var hp_before := player.health.health
	var swung := false
	for i in 120:
		await physics_frame
		if boss.state == Enemy.State.ATTACK:
			swung = true
		player.global_position = boss.global_position + Vector3(0, 0, 2.2)
		if swung and player.health.health < hp_before:
			break
	_check(swung and seen["swing"] >= 1, "boss starts a slam and swing_started fires")
	_check(player.health.health <= hp_before - 22.0 + 0.01, "slam hits for 22 (player lost %.1f)" % (hp_before - player.health.health))

	# Shockwave: grounded player is hit, airborne player is not
	await _frames(120)
	boss._cooldown = 9999.0
	boss.state = Enemy.State.CHASE
	player.global_position = boss.global_position + Vector3(0, 0.05, 3.0)
	await _frames(3)
	hp_before = player.health.health
	boss._spawn_shockwave()
	await _frames(45)
	_check(is_equal_approx(hp_before - player.health.health, 14.0), "shockwave deals 14 to a grounded player (%.1f)" % (hp_before - player.health.health))
	await _frames(40)
	boss._cooldown = 9999.0
	player.global_position = boss.global_position + Vector3(0, 6.0, 3.0)
	player.velocity = Vector3.ZERO
	hp_before = player.health.health
	boss._spawn_shockwave()
	await _frames(20)
	_check(player.health.health == hp_before, "shockwave misses an airborne player")
	main.queue_free()
	await _frames(3)

	# Phase 2
	var set2 := await _spawn()
	main = set2[0]
	player = set2[1]
	boss = set2[2]
	boss.set_physics_process(false)
	var soldiers_before := root.get_tree().get_nodes_in_group("enemies").size()
	var speed_before := boss.move_speed
	var guard := 0
	while not boss.phase2 and guard < 40:
		boss.receive_hit(heavy, player.global_position)
		guard += 1
	_check(boss.phase2 and boss._roaring, "dropping to 40% health (Milestone 4 threshold, was 50%) triggers the roar (hp %.0f)" % _hp(boss))
	var hp_roar := _hp(boss)
	_check(not boss.receive_hit(heavy, player.global_position) and _hp(boss) == hp_roar, "boss is invulnerable while roaring")
	boss.set_physics_process(true)
	await _frames(10)
	_check(root.get_tree().get_nodes_in_group("enemies").size() == soldiers_before + 2, "two soldiers are summoned once")
	await _frames(170)
	_check(not boss._roaring, "the roar ends after 2.5s")
	_check(is_equal_approx(boss.move_speed, speed_before * 1.35), "phase 2 is 35% faster")
	_check(boss.cooldown_max < 2.4, "phase 2 shortens cooldowns")
	boss.forced_attack = &"slam"
	boss._slam_count = 1
	boss._start_attack()
	_check(boss._chain_flurry and boss._shock_pending, "phase 2: flurry follows the slam and shockwave every 2nd attack")

	# Defeat and reward
	boss.set_physics_process(false)
	boss.state = Enemy.State.CHASE
	(boss.get_node("HealthComponent") as HealthComponent).take_damage(100000.0)
	await _frames(4)
	var ids: Array[StringName] = []
	for child in main.get_children():
		if child is Pickup:
			ids.append((child as Pickup).item.item_id)
	_check(seen["defeated"] == 0 and boss.is_dead(), "boss dies")
	_check(ids.has(&"warden_blade") and ids.has(&"warden_plate"), "guaranteed drops: cleaver and plate")
	_check(ids.count(&"health_potion") == 2, "two medkits drop (%d)" % ids.count(&"health_potion"))

	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
