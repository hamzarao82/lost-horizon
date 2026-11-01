extends SceneTree
## Headless test runner:
##   godot --headless --path . -s tests/run_tests.gd
## Exits non-zero if any check fails.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"
const ITEMS: String = "res://resources/items/"

var _failures: int = 0
var _checks: int = 0


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


func _run() -> void:
	_test_attack_data()
	_test_health()
	_test_inventory()
	_test_loot_table()
	await _test_combat()
	await _test_equipment_in_combat()
	await _test_enemy_ai()
	await _test_variants_and_drops()
	await _test_waves()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _item(id: String) -> ItemData:
	return load(ITEMS + id + ".tres") as ItemData


func _test_attack_data() -> void:
	print("AttackData")
	for id in ["light_1", "light_2", "heavy_1", "enemy_swing", "heavy_swing", "hunter_slash"]:
		var data := load("res://resources/attacks/%s.tres" % id) as AttackData
		_check(data != null and data.validate().is_empty(), "%s loads and validates" % id)
	var bad := AttackData.new()
	bad.damage = 0.0
	_check(not bad.validate().is_empty(), "invalid attack data is rejected")


func _test_health() -> void:
	print("HealthComponent")
	var health := HealthComponent.new()
	health.max_health = 50.0
	health._ready()
	var died := [false]
	health.died.connect(func() -> void: died[0] = true)
	health.take_damage(20.0)
	_check(is_equal_approx(health.health, 30.0), "damage reduces health")
	health.heal(100.0)
	_check(is_equal_approx(health.health, 50.0), "heal clamps at max health")
	health.take_damage(100.0)
	_check(health.is_dead() and died[0], "overkill kills once and clamps at 0")
	health.heal(20.0)
	_check(health.is_dead(), "dead target cannot be healed")
	health.free()


func _test_inventory() -> void:
	print("Inventory")
	var inv := Inventory.new()
	inv._ready()
	_check(inv.weapon != null and inv.damage_multiplier() == 1.0, "starts with the improvised blade")
	_check(inv.add_item(_item("combat_knife")) and inv.weapon.item_id == &"combat_knife", "better weapon is equipped")
	_check(not inv.add_item(_item("improvised_blade")) and inv.weapon.item_id == &"combat_knife", "worse weapon is rejected")
	_check(inv.add_item(_item("tactical_sword")) and is_equal_approx(inv.damage_multiplier(), 1.9), "sword replaces knife")
	_check(inv.armor == null and inv.damage_reduction() == 0.0, "starts with no armor, and armor is no longer a percentage")
	_check(inv.add_item(_item("reinforced_armor")) and is_equal_approx(inv.armor.armor_points, 60.0), "armor is equipped")
	_check(not inv.add_item(_item("light_tactical_armor")), "weaker armor is rejected")
	_check(inv.add_item(_item("heavy_combat_armor")) and is_equal_approx(inv.armor.armor_points, 100.0), "stronger armor replaces it")

	var health := HealthComponent.new()
	health.max_health = 100.0
	health._ready()
	_check(not inv.use_potion(health), "cannot use a medkit you do not have")
	inv.add_item(_item("health_potion"))
	_check(inv.potions == 1, "medkit is collected")
	_check(not inv.use_potion(health), "medkit is not wasted at full health")
	health.take_damage(70.0)
	_check(inv.use_potion(health) and is_equal_approx(health.health, 70.0) and inv.potions == 0, "medkit heals 40 and is consumed")
	health.free()
	inv.free()


func _test_loot_table() -> void:
	print("LootTable")
	var table := load("res://resources/loot/soldier_loot.tres") as LootTable
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var drops := 0
	var potions := 0
	var rolls := 10000
	for i in rolls:
		var item := table.roll(rng)
		if item:
			drops += 1
			if item.item_id == &"health_potion":
				potions += 1
	var rate := float(drops) / rolls
	_check(absf(rate - table.drop_chance) < 0.03, "drop rate matches table (%.3f vs %.2f)" % [rate, table.drop_chance])
	var potion_share := float(potions) / maxf(drops, 1)
	var weight_total := 0.0
	for w in table.weights:
		weight_total += w
	var expected_share := table.weights[0] / weight_total  # the potion is the first entry
	_check(absf(potion_share - expected_share) < 0.04, "weights respected (potion share %.3f vs %.3f)" % [potion_share, expected_share])
	var guaranteed := load("res://resources/loot/heavy_loot.tres") as LootTable
	var all_drop := true
	for i in 200:
		all_drop = all_drop and guaranteed.roll(rng) != null
	_check(all_drop, "heavy loot always drops")


func _spawn_main(with_waves: bool = false) -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	if not with_waves:
		var wm := main.get_node_or_null("WaveManager")
		if wm:
			wm.autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _spawn_enemy(main: Node, path: String, pos: Vector3, frozen: bool = false) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	enemy.position = pos  # before add_child, so it never overlaps the player at the origin
	main.add_child(enemy)
	if frozen:
		enemy.set_physics_process(false)
	return enemy


func _hp(enemy: Enemy) -> float:
	return (enemy.get_node("HealthComponent") as HealthComponent).health


func _press(action: String, hold_frames: int = 2) -> void:
	Input.action_press(action)
	await _frames(hold_frames)
	Input.action_release(action)


func _test_combat() -> void:
	print("Combat")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _spawn_enemy(main, SOLDIER, player.global_position + Vector3(0, 0, -1.5), true)
	await _frames(2)
	var start_hp := _hp(enemy)

	await _press("attack_light")
	_check(player.state == Player.State.ATTACK, "light attack starts on input")
	_check(_hp(enemy) == start_hp, "no damage during startup frames")
	await _frames(14)
	var dealt := start_hp - _hp(enemy)
	_check(is_equal_approx(dealt, 10.0), "light_1 deals exactly 10 once per swing (got %s)" % dealt)
	await _frames(30)
	_check(player.state == Player.State.FREE, "player returns to FREE after recovery")

	enemy.global_position = player.global_position + Vector3(0, 0, -1.5)
	await _frames(2)
	var before_combo := _hp(enemy)
	await _press("attack_light")
	await _frames(12)
	await _press("attack_light")
	await _frames(20)
	var combo_damage := before_combo - _hp(enemy)
	_check(is_equal_approx(combo_damage, 22.0), "light, light chain deals 10 + 12 (got %s)" % combo_damage)
	await _frames(40)

	var stamina_before := player.stamina
	await _press("dodge")
	_check(player.state == Player.State.DODGE, "dodge starts on input")
	_check(player.stamina < stamina_before, "dodge spends stamina")
	_check(player.is_invulnerable(), "invulnerable during i-frames")
	var swing := load("res://resources/attacks/enemy_swing.tres") as AttackData
	var player_hp := player.health.health
	_check(not player.receive_hit(swing, player.global_position + Vector3(0, 0, -1)), "hit during i-frames is ignored")
	await _frames(20)
	_check(not player.is_invulnerable(), "i-frames expire")
	await _frames(20)
	_check(player.state == Player.State.FREE, "dodge ends")
	_check(player.receive_hit(swing, player.global_position + Vector3(0, 0, -1)), "hit after i-frames lands")
	_check(is_equal_approx(player.health.health, player_hp - swing.damage), "damage applied to player")

	await _frames(40)
	player.health.take_damage(1000.0)
	_check(player.is_dead(), "player dies at 0 health")
	main.queue_free()
	await _frames(3)


func _test_equipment_in_combat() -> void:
	print("Equipment in combat")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _spawn_enemy(main, SOLDIER, player.global_position + Vector3(0, 0, -1.5), true)
	player.inventory.add_item(_item("military_machete"))
	player.inventory.add_item(_item("reinforced_armor"))
	await _frames(2)
	var start_hp := _hp(enemy)
	await _press("attack_light")
	await _frames(14)
	var dealt := start_hp - _hp(enemy)
	_check(is_equal_approx(dealt, 15.0), "machete scales light_1 to 15 damage (got %s)" % dealt)

	await _frames(40)
	var swing := load("res://resources/attacks/enemy_swing.tres") as AttackData
	var hp := player.health.health
	_check(is_equal_approx(player.health.armor, 60.0), "equipping reinforced armor fills a 60 point armor bar")
	player.receive_hit(swing, player.global_position + Vector3(0, 0, -1))
	_check(is_equal_approx(player.health.health, hp) and is_equal_approx(player.health.armor, 60.0 - swing.damage),
			"armor absorbs damage before health")

	await _frames(40)
	player.health.take_damage(player.health.armor + 30.0)  # strip the armor, then hurt the player
	var hurt_hp := player.health.health
	player.inventory.add_item(_item("health_potion"))
	await _press("use_item")
	_check(player.inventory.potions == 0 and player.health.health > hurt_hp, "use_item key consumes a medkit and heals")

	# A heal tapped mid-attack is buffered and used as soon as the attack ends
	await _frames(40)
	player.health.take_damage(30.0)
	player.inventory.add_item(_item("health_potion"))
	var hurt := player.health.health
	await _press("attack_light")
	await _press("use_item", 1)
	_check(player.state == Player.State.ATTACK and player.inventory.potions == 1, "heal is not used mid-attack")
	await _frames(60)
	_check(player.inventory.potions == 0 and player.health.health > hurt, "buffered heal is used after the attack")
	main.queue_free()
	await _frames(3)


func _test_enemy_ai() -> void:
	print("Enemy AI")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy1 := _spawn_enemy(main, SOLDIER, player.global_position + Vector3(0, 0, -20))
	var enemy2 := _spawn_enemy(main, SOLDIER, player.global_position + Vector3(6, 0, -22))
	await _frames(10)
	_check(enemy1.state == Enemy.State.IDLE, "enemy outside detection range stays idle")
	enemy1.global_position = player.global_position + Vector3(0, 0, -8)
	enemy2.global_position = player.global_position + Vector3(6, 0, -8)
	await _frames(30)
	_check(enemy1.state != Enemy.State.IDLE, "enemy detects player and leaves idle")

	var d0 := enemy1.global_position.distance_to(player.global_position)
	await _frames(60)
	var d1 := enemy1.global_position.distance_to(player.global_position)
	_check(d1 < d0 or enemy1.state == Enemy.State.ATTACK, "enemy closes distance")

	var max_attackers := 0
	var player_start_hp := player.health.health
	for i in 600:
		await physics_frame
		var attackers := 0
		for e in [enemy1, enemy2]:
			if (e as Enemy).state == Enemy.State.ATTACK:
				attackers += 1
		max_attackers = maxi(max_attackers, attackers)
	_check(max_attackers <= 1, "never more than one of two enemies attacking at once (max %d)" % max_attackers)
	_check(player.health.health < player_start_hp, "idle player eventually gets hit by enemies")

	var swing := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 3:
		enemy1.receive_hit(swing, player.global_position)
	_check(enemy1.is_dead(), "enemy dies when health reaches 0")
	_check(not enemy1.is_in_group("enemies"), "dead enemy leaves the enemies group")
	main.queue_free()
	await _frames(3)


func _test_variants_and_drops() -> void:
	print("Enemy variants and drops")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	player.global_position = Vector3(0, 0.1, 20)
	var soldier := _spawn_enemy(main, SOLDIER, Vector3(-20, 0.1, -20), true)
	var heavy := _spawn_enemy(main, HEAVY, Vector3(-15, 0.1, -20), true)
	var hunter := _spawn_enemy(main, HUNTER, Vector3(-10, 0.1, -20), true)
	await _frames(2)
	_check(_hp(heavy) == 140.0 and _hp(hunter) == 45.0 and _hp(soldier) == 60.0, "variants have their own hit points")
	_check(heavy.move_speed < soldier.move_speed and hunter.move_speed > soldier.move_speed, "heavy is slower, hunter is faster")

	var stagger_probe := load("res://resources/attacks/light_1.tres") as AttackData
	heavy.receive_hit(stagger_probe, player.global_position)
	soldier.receive_hit(stagger_probe, player.global_position)
	_check(heavy._stagger_time < soldier._stagger_time, "heavy resists stagger")

	hunter.set_physics_process(true)
	hunter.dodge_chance = 1.0
	hunter.state = Enemy.State.CHASE
	var hunter_start := hunter.global_position
	_check(not hunter.receive_hit(stagger_probe, hunter.global_position + Vector3(0, 0, 2)), "a dodged hit deals no damage")
	await _frames(14)
	_check(_hp(hunter) == 45.0 and hunter.global_position.distance_to(hunter_start) > 1.0, "hunter sidestep actually moves it")
	hunter.set_physics_process(false)

	var table := load(soldier.loot_table_path) as LootTable
	var original_chance := table.drop_chance
	table.drop_chance = 1.0
	var kill := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 3:
		soldier.receive_hit(kill, player.global_position)
	table.drop_chance = original_chance
	await _frames(3)
	var pickups: Array[Pickup] = []
	for child in main.get_children():
		if child is Pickup:
			pickups.append(child)
	_check(soldier.is_dead() and pickups.size() == 1, "dead enemy drops a pickup (found %d)" % pickups.size())

	# Collection is tested with a medkit we control: a random drop can be an armor plate, which is
	# deliberately left on the ground when no armor is worn.
	for stray in pickups:
		stray.queue_free()
	var medkit := Pickup.spawn(main, _item("health_potion"), player.global_position)
	await _frames(8)
	_check(not is_instance_valid(medkit) or medkit.is_queued_for_deletion(), "walking into a pickup collects it")

	var worse := Pickup.spawn(main, _item("improvised_blade"), player.global_position)
	player.inventory.add_item(_item("military_machete"))
	await _frames(4)
	_check(is_instance_valid(worse) and not worse.is_queued_for_deletion(), "a non-upgrade stays on the ground")
	main.queue_free()
	await _frames(3)


func _test_waves() -> void:
	print("Waves")
	var main := await _spawn_main(true)
	var wm := main.get_node("WaveManager") as WaveManager
	wm.start()  # Main no longer autostarts waves; the courtyard trigger (or a test) starts them
	var player := main.get_node("Player") as Player
	player.health.max_health = 100000.0
	player.health.health = 100000.0
	var waited := 0
	while wm.current_wave < 1 and waited < 400:
		await physics_frame
		waited += 1
	_check(wm.current_wave == 1, "wave 1 starts automatically")
	_check(get_nodes_in_group("enemies").size() == 2, "wave 1 has two soldiers")

	var kill := load("res://resources/attacks/heavy_1.tres") as AttackData
	for round in 3:
		var expected_wave := round + 2
		for enemy in get_nodes_in_group("enemies"):
			for i in 12:
				(enemy as Enemy).receive_hit(kill, player.global_position)
		waited = 0
		while wm.current_wave < expected_wave and waited < 500:
			await physics_frame
			waited += 1
		_check(wm.current_wave == expected_wave, "wave %d starts after the previous is cleared" % expected_wave)
	_check(get_nodes_in_group("enemies").size() == 3, "wave 4 has a heavy and two hunters")
	_check(not wm.is_finished(), "arena is not finished while wave 4 is alive")
	for enemy in get_nodes_in_group("enemies"):
		for i in 12:
			(enemy as Enemy).receive_hit(kill, player.global_position)
	waited = 0
	while wm.current_wave < 5 and waited < 500:
		await physics_frame
		waited += 1
	_check(wm.current_wave == 5, "wave 5 starts after wave 4 is cleared")
	_check(get_nodes_in_group("boss").size() == 1, "wave 5 is the Warden")
	_check(not wm.is_finished(), "arena is not finished while the Warden is alive")
	# The boss has an invulnerable roar and summons soldiers, so keep hitting until all are down.
	var rounds := 0
	while not wm.is_finished() and rounds < 40:
		for enemy in get_nodes_in_group("enemies"):
			for i in 12:
				(enemy as Enemy).receive_hit(kill, player.global_position)
		await _frames(30)
		rounds += 1
	_check(wm.is_finished(), "arena is finished after the Warden and his summons fall")
	main.queue_free()
	await _frames(3)
