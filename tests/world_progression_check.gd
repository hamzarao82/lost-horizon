extends SceneTree
## World wiring of the Milestone 6 systems (headless): godot --headless --path . -s tests/world_progression_check.gd
## Loot tiers on real enemies, crates and hidden caches, the quartermaster, the mission reward and the
## Field Medic medkit hook, with a save/load of a purchase.

var _failures: int = 0
var _checks: int = 0
var _sm: Node
var _prog: Node


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


func _clean() -> void:
	_sm.reset_runtime_state()
	_sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = _sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_sm.defeated_bosses.clear()


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _item(id: String) -> ItemData:
	return load("res://resources/items/%s.tres" % id) as ItemData


func _run() -> void:
	_sm = root.get_node("SaveManager")
	_prog = root.get_node("Progression")
	_clean()
	_test_table_distribution()
	await _test_enemy_drops_and_xp()
	await _test_crates_and_caches()
	await _test_merchant_and_purchase_persistence()
	await _test_mission_reward_once()
	await _test_field_medic()
	_clean()
	print("\nworld_progression_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## Seeded rolls: the drop chance and the weights are what the tables say, and bonus tables never hand out gear.
func _test_table_distribution() -> void:
	print("Loot tables with a seeded RNG")
	var regular := load("res://resources/loot/enemy_regular.tres") as LootTable
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var drops := 0
	var scrap := 0
	var trials := 4000
	for i in trials:
		var item := regular.roll(rng)
		if item != null:
			drops += 1
			if item.item_id == &"scrap_metal":
				scrap += 1
	var rate := float(drops) / trials
	_check(absf(rate - regular.drop_chance) < 0.04, "regular enemies drop at the table's chance (%.3f vs %.2f)" % [rate, regular.drop_chance])
	_check(absf(float(scrap) / maxf(drops, 1) - 0.4) < 0.06, "scrap metal is about 40%% of drops (%.3f)" % (float(scrap) / maxf(drops, 1)))
	var regular_gear := false
	for item_path in regular.item_paths:
		if (load(item_path) as ItemData).is_equipment():
			regular_gear = true
	_check(not regular_gear, "the regular bonus table is materials and credits only")
	# The elite and heavy bonus table does contain two wearable pieces: elites gain a small extra chance
	# at gloves and boots on top of their own table. Measure that share instead of hiding it.
	var elite := load("res://resources/loot/enemy_elite.tres") as LootTable
	var gear_weight := 0.0
	var total_weight := 0.0
	for i in elite.item_paths.size():
		total_weight += elite.weights[i]
		if (load(elite.item_paths[i]) as ItemData).is_equipment():
			gear_weight += elite.weights[i]
	var elite_gear_chance: float = elite.drop_chance * gear_weight / maxf(total_weight, 0.001)
	_check(elite_gear_chance > 0.0 and elite_gear_chance < 0.15,
			"elite bonus drops add a small gear chance (%.3f per kill)" % elite_gear_chance)
	var same_a := load("res://resources/loot/enemy_elite.tres") as LootTable
	rng.seed = 99
	var first: Array = []
	for i in 20:
		var item := same_a.roll(rng)
		first.append(String(item.item_id) if item else "")
	rng.seed = 99
	var second: Array = []
	for i in 20:
		var item := same_a.roll(rng)
		second.append(String(item.item_id) if item else "")
	_check(first == second, "the same seed gives the same drops")


func _test_enemy_drops_and_xp() -> void:
	print("Enemy drops by tier and XP")
	_prog.reset()
	var main := await _spawn_main()
	var arena := Node3D.new()
	root.add_child(arena)
	var bonus_ids := {}
	for path in Enemy.BONUS_TABLES.values():
		for item_path in (load(path) as LootTable).item_paths:
			bonus_ids[String((load(item_path) as ItemData).item_id)] = true
	var xp_before: int = _prog.progress.xp
	var kills := 60
	for i in kills:
		var enemy := (load("res://scenes/enemies/PatrolSoldier.tscn") as PackedScene).instantiate() as Enemy
		enemy.position = Vector3(800.0 + i * 3.0, 0.0, 800.0)
		arena.add_child(enemy)
		await physics_frame
		enemy._health.take_damage(100000.0)
		await physics_frame
	await _frames(4)
	var gear := 0
	var bonus := 0
	for child in arena.get_children():
		if child is Pickup:
			if bonus_ids.has(String((child as Pickup).item.item_id)):
				bonus += 1
			else:
				gear += 1
	var gear_rate := float(gear) / kills
	_check(bonus >= 1, "kills also drop materials or credits (%d of %d kills)" % [bonus, kills])
	_check(gear_rate > 0.4 and gear_rate < 0.95, "gear drops stay near the table's 70%% (%.2f)" % gear_rate)
	_check(_prog.progress.xp > xp_before, "the kills awarded XP (%d)" % (_prog.progress.xp - xp_before))
	arena.queue_free()
	main.queue_free()
	await _frames(2)
	_prog.reset()


func _test_crates_and_caches() -> void:
	print("Crates and hidden caches")
	var main := await _spawn_main()
	var crates: Array[SupplyCrate] = []
	for node in main.find_children("*", "SupplyCrate", true, false):
		crates.append(node as SupplyCrate)
	var common_ok := true
	var hidden_ok := true
	var hidden_count := 0
	for crate in crates:
		if String(crate.crate_id).begins_with("cache"):
			hidden_count += 1
			if not crate.bonus_table_path.ends_with("crate_hidden.tres"):
				hidden_ok = false
		elif not crate.bonus_table_path.ends_with("crate_common.tres"):
			common_ok = false
	_check(crates.size() > 0 and common_ok, "supply crates use the crate table (%d crates)" % crates.size())
	_check(hidden_count > 0 and hidden_ok, "hidden caches use the hidden table (%d caches)" % hidden_count)

	var table := LootTable.new()
	table.drop_chance = 1.0
	table.guaranteed_paths = PackedStringArray(["res://resources/items/scrap_metal.tres"])
	table.source = LootTable.Source.CRATE
	ResourceSaver.save(table, "user://test_crate_table.tres")
	var holder := Node3D.new()
	root.add_child(holder)
	var crate := SupplyCrate.new()
	crate.crate_id = &"test_crate_world_prog"
	crate.bonus_table_path = "user://test_crate_table.tres"
	holder.add_child(crate)
	await physics_frame
	var player := main.get_node("Player") as Player
	_check(crate.interact(player), "the crate opens")
	await _frames(2)
	var pickups := 0
	for child in holder.get_children():
		if child is Pickup:
			pickups += 1
	_check(pickups == 1, "its bonus table drops exactly the guaranteed item (%d)" % pickups)
	_check(not crate.interact(player), "a second interaction does nothing")
	await _frames(2)
	var after := 0
	for child in holder.get_children():
		if child is Pickup:
			after += 1
	_check(after == 1, "so the loot cannot be rolled twice (%d pickups)" % after)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_crate_table.tres"))
	holder.queue_free()
	main.queue_free()
	await _frames(2)
	_clean()


func _test_merchant_and_purchase_persistence() -> void:
	print("Quartermaster and a purchase across save/load")
	var main := await _spawn_main()
	var vendor: MerchantNpc = null
	var merchant_data: MerchantData = null
	for node in main.find_children("*", "MerchantNpc", true, false):
		vendor = node as MerchantNpc
	_check(vendor != null and vendor.data != null and vendor.data.merchant_id == &"outpost_quartermaster",
			"the quartermaster stands in the world")
	var player := main.get_node("Player") as Player
	var inv: Inventory = player.inventory
	if vendor != null:
		var heard := [0]
		vendor.open_requested.connect(func(_data: MerchantData) -> void: heard[0] += 1)
		vendor.interact(player)
		_check(heard[0] == 1, "interacting emits open_requested once for the trading screen")
		merchant_data = vendor.data
		var spot: Vector3 = vendor.global_position
		_check(spot.z > 15.0 and spot.z < 30.0, "he is at the compound gate in Area B (z %.1f)" % spot.z)
		inv.add_currency(1000)
		var stock_before := MerchantService.stock_left(inv, merchant_data, "antiseptic")
		var price := MerchantService.buy_price(merchant_data, "antiseptic")
		var result := MerchantService.buy(inv, merchant_data, "antiseptic", 2)
		_check(bool(result.get("ok", false)), "buying two antiseptics works")
		var cash := inv.currency
		_check(cash == 1000 - 2 * price, "the price was paid (%d)" % cash)
		_check(_sm.save_game("test"), "the purchase is saved")
		main.queue_free()
		await _frames(2)
		_sm.reset_runtime_state()
		_check(_sm.load_game(), "and loaded")
		var main2 := await _spawn_main()
		var inv2: Inventory = (main2.get_node("Player") as Player).inventory
		_check(inv2.currency == cash, "money after the purchase persists")
		_check(inv2.count_of("antiseptic") == 2, "the purchased items persist")
		_check(MerchantService.stock_left(inv2, merchant_data, "antiseptic") == stock_before - 2,
				"the vendor's remaining stock persists")
		main2.queue_free()
	else:
		main.queue_free()
	await _frames(2)
	_clean()


func _test_mission_reward_once() -> void:
	print("Mission reward once")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var inv: Inventory = player.inventory
	var quests := root.get_node("QuestManager")
	var world := root.get_node("WorldState")
	world.set_flag(&"mission_reward_granted", false)
	var money_before := inv.currency
	quests._grant_mission_reward()
	var gained := inv.currency - money_before
	_check(gained == 60, "completing the mission pays credits (%d)" % gained)
	_check(inv.count_of("intel_drive") == 1 and inv.count_of("upgrade_kit_weapon") == 1, "and hands over its items")
	_check(world.has_flag(&"mission_reward_granted"), "the reward is recorded in a saved world flag")
	quests._grant_mission_reward()
	_check(inv.currency - money_before == gained and inv.count_of("intel_drive") == 1, "a second completion pays nothing")
	world.set_flag(&"mission_reward_granted", false)
	main.queue_free()
	await _frames(2)
	_clean()


func _test_field_medic() -> void:
	print("Field Medic medkit hook")
	_prog.reset()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var inv: Inventory = player.inventory
	player.health.max_health = 200.0
	player.health.health = 50.0
	inv.potions = 3
	_check(inv.use_potion(player.health), "a medkit is used")
	_check(is_equal_approx(player.health.health, 50.0 + inv.potion_heal), "without the skill it heals the base amount (%.1f)" % player.health.health)
	_prog.progress.skills[&"field_medic"] = 1
	player.health.health = 50.0
	_check(inv.use_potion(player.health), "a medkit is used with the skill")
	var healed := player.health.health - 50.0
	_check(healed > inv.potion_heal + 0.5, "Field Medic heals more (%.1f vs %.1f)" % [healed, inv.potion_heal])
	_prog.reset()
	main.queue_free()
	await _frames(2)
	_clean()
