extends SceneTree
## Loot tables: weights within statistical tolerance (seeded RNG), guaranteed entries, rarity weighting,
## unique-reward protection across save/load, source tables, and the existing enemy tables.
##   godot --headless --path . -s tests/items_loot_check.gd

const ITEMS: String = "res://resources/items/"
const LOOT: String = "res://resources/loot/"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _item(id: String) -> ItemData:
	return load(ITEMS + id + ".tres") as ItemData


func _table(id: String) -> LootTable:
	return load(LOOT + id + ".tres") as LootTable


func _inventory() -> Inventory:
	var inventory := Inventory.new()
	inventory.weapon = _item("improvised_blade")
	return inventory


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _run() -> void:
	_test_weights()
	_test_guaranteed_and_rarity()
	_test_unique()
	_test_sources()
	_test_service()
	_test_existing_tables()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_weights() -> void:
	print("Weights")
	var table := LootTable.new()
	table.drop_chance = 1.0
	table.rolls = 1
	table.item_paths = PackedStringArray([ITEMS + "scrap_metal.tres", ITEMS + "cloth_scrap.tres", ITEMS + "dog_tag.tres"])
	table.weights = PackedFloat32Array([70.0, 20.0, 10.0])
	var rng := _rng(12345)
	var counts := {"scrap_metal": 0, "cloth_scrap": 0, "dog_tag": 0}
	var trials := 4000
	for i in trials:
		for entry in table.roll_all(rng):
			counts[String((entry["item"] as ItemData).item_id)] += 1
	_check(absf(counts["scrap_metal"] / float(trials) - 0.7) < 0.03, "a 70-weight entry drops about 70%% of the time (%.3f)" % (counts["scrap_metal"] / float(trials)))
	_check(absf(counts["cloth_scrap"] / float(trials) - 0.2) < 0.03, "a 20-weight entry drops about 20%% (%.3f)" % (counts["cloth_scrap"] / float(trials)))
	_check(absf(counts["dog_tag"] / float(trials) - 0.1) < 0.03, "a 10-weight entry drops about 10%% (%.3f)" % (counts["dog_tag"] / float(trials)))
	var repeat_a := table.roll_all(_rng(7))
	var repeat_b := table.roll_all(_rng(7))
	_check(repeat_a.size() == repeat_b.size() and repeat_a[0]["item"] == repeat_b[0]["item"], "the same seed gives the same drop")
	table.drop_chance = 0.0
	var none := 0
	for i in 200:
		none += table.roll_all(rng).size()
	_check(none == 0, "drop_chance 0 never drops")
	table.drop_chance = 1.0
	table.rolls = 3
	_check(table.roll_all(rng).size() == 3, "rolls = 3 gives three drops")
	var broken := LootTable.new()
	broken.item_paths = PackedStringArray([ITEMS + "scrap_metal.tres"])
	_check(broken.roll_all(rng).is_empty(), "a table with mismatched weights drops nothing instead of crashing")
	var counts_table := LootTable.new()
	counts_table.drop_chance = 1.0
	counts_table.item_paths = PackedStringArray([ITEMS + "scrap_metal.tres"])
	counts_table.weights = PackedFloat32Array([1.0])
	counts_table.max_counts = PackedInt32Array([4])
	var seen_max := 0
	var seen_over := false
	for i in 300:
		var count: int = counts_table.roll_all(rng)[0]["count"]
		seen_max = maxi(seen_max, count)
		seen_over = seen_over or count > 4 or count < 1
	_check(seen_max == 4 and not seen_over, "stack counts stay within 1..max_counts")


func _test_guaranteed_and_rarity() -> void:
	print("Guaranteed entries and rarity weighting")
	var table := LootTable.new()
	table.drop_chance = 0.0
	table.guaranteed_paths = PackedStringArray([ITEMS + "upgrade_kit_armor.tres"])
	var drops := table.roll_all(_rng(1))
	_check(drops.size() == 1 and (drops[0]["item"] as ItemData).item_id == &"upgrade_kit_armor", "guaranteed entries drop even at drop_chance 0")
	var table2 := LootTable.new()
	table2.drop_chance = 1.0
	table2.item_paths = PackedStringArray([ITEMS + "scrap_metal.tres", ITEMS + "signal_charm.tres"])
	table2.weights = PackedFloat32Array([50.0, 50.0])
	var rng := _rng(99)
	var rare_plain := 0
	for i in 3000:
		if (table2.roll_all(rng)[0]["item"] as ItemData).item_id == &"signal_charm":
			rare_plain += 1
	table2.rarity_weights = PackedFloat32Array([1.0, 1.0, 0.1, 0.1, 0.1])
	var rare_weighted := 0
	for i in 3000:
		if (table2.roll_all(rng)[0]["item"] as ItemData).item_id == &"signal_charm":
			rare_weighted += 1
	_check(rare_weighted < rare_plain * 0.3, "rarity weights make the rare item far less common (%d vs %d of 3000)" % [rare_weighted, rare_plain])


func _test_unique() -> void:
	print("Unique rewards")
	var inventory := _inventory()
	var reward := _table("reward_first_signal")
	var first := LootService.grant(reward, inventory, _rng(5))
	_check(inventory.has_item("intel_drive") and inventory.is_unique_claimed("intel_drive"), "the mission reward gives the unique intel drive and claims it")
	var credits_before := inventory.currency
	var kits_before := inventory.count_of("upgrade_kit_weapon")
	var second := LootService.grant(reward, inventory, _rng(5))
	_check(inventory.count_of("intel_drive") == 1, "granting the reward again gives no second intel drive")
	_check(inventory.currency > credits_before and inventory.count_of("upgrade_kit_weapon") == kits_before + 1, "the non-unique parts of the reward are still given")
	# Reload: claimed set persists, so a reloaded save cannot be farmed.
	var data := inventory.to_dict()
	var reloaded := _inventory()
	reloaded.from_dict(data)
	reloaded.remove("intel_drive", 1)  # simulate the player having handed it in
	LootService.grant(reward, reloaded, _rng(5))
	_check(not reloaded.has_item("intel_drive"), "after a reload the claimed unique reward is not given again")
	_check(not reloaded.add_item(_item("intel_drive")), "picking the unique item up again is refused")
	# Boss rewards from the existing Warden table.
	var fresh := _inventory()
	_check(fresh.add_item(_item("warden_blade")) and fresh.weapon.item_id == &"warden_blade" and fresh.is_unique_claimed("warden_blade"), "the Warden's Cleaver is received once and claimed")
	var other := _inventory()
	other.from_dict(fresh.to_dict())
	other.weapon = _item("improvised_blade")
	_check(not other.add_item(_item("warden_blade")), "a loaded save cannot pick up a second Cleaver")
	_check(first["granted"].size() >= 3 and second["granted"].size() >= 2, "grant() reports what was granted")
	inventory.free()
	reloaded.free()
	fresh.free()
	other.free()


func _test_sources() -> void:
	print("Source tables")
	var expected := {
		"enemy_regular": LootTable.Source.REGULAR, "enemy_elite": LootTable.Source.ELITE,
		"enemy_miniboss": LootTable.Source.MINIBOSS, "crate_common": LootTable.Source.CRATE,
		"crate_hidden": LootTable.Source.HIDDEN, "reward_first_signal": LootTable.Source.REWARD,
	}
	for id in expected.keys():
		var table := _table(id)
		_check(table != null and table.source == expected[id] and table.region == "outpost17", "%s loads with its source and region tag" % id)
	var everything_valid := true
	for file in DirAccess.get_files_at(LOOT):
		if not file.ends_with(".tres"):
			continue
		var table := load(LOOT + file) as LootTable
		if table == null:
			everything_valid = false
			continue
		for path in table.item_paths:
			everything_valid = everything_valid and load(path) is ItemData
		for path in table.guaranteed_paths:
			everything_valid = everything_valid and load(path) is ItemData
		if table.item_paths.size() != table.weights.size():
			everything_valid = false
	_check(everything_valid, "every loot table points at real items with matching weights")
	# Anti-inflation: the regular enemy table should drop little and the elite table more but bounded.
	var rng := _rng(2024)
	var regular_drops := 0
	var elite_drops := 0
	for i in 1000:
		regular_drops += _table("enemy_regular").roll_all(rng).size()
		elite_drops += _table("enemy_elite").roll_all(rng).size()
	_check(regular_drops < 500, "regular enemies drop on average under half an item (%d per 1000)" % regular_drops)
	_check(elite_drops > regular_drops and elite_drops < 1500, "elites drop more but stay bounded (%d per 1000)" % elite_drops)
	var gear_from_regular := 0
	for i in 2000:
		for entry in _table("enemy_regular").roll_all(rng):
			if (entry["item"] as ItemData).is_equipment():
				gear_from_regular += 1
	_check(gear_from_regular == 0, "regular enemies never drop equipment")


func _test_service() -> void:
	print("Grant into a full bag")
	var inventory := _inventory()
	for i in Inventory.BAG_CAPACITY:
		var filler := ItemData.new()
		filler.item_id = StringName("filler_%d" % i)
		filler.kind = ItemData.Kind.MATERIAL
		filler.max_stack = 1
		inventory.collect(filler, 1)
	_check(inventory.stack_count() == Inventory.BAG_CAPACITY, "bag filled with single-stack fillers")
	var table := LootTable.new()
	table.drop_chance = 1.0
	table.rolls = 0
	table.guaranteed_paths = PackedStringArray([ITEMS + "upgrade_kit_weapon.tres", ITEMS + "credits_medium.tres"])
	var result := LootService.grant(table, inventory, _rng(3))
	_check(result["overflow"].size() == 1 and (result["overflow"][0]["item"] as ItemData).item_id == &"upgrade_kit_weapon", "an item that does not fit is returned as overflow for the caller to drop")
	_check(inventory.currency == 60, "credits still arrive when the bag is full")
	inventory.free()


func _test_existing_tables() -> void:
	print("Existing enemy tables")
	var rng := _rng(77)
	for id in ["soldier_loot", "hunter_loot", "heavy_loot"]:
		var table := _table(id)
		var drops := 0
		for i in 400:
			if table.roll(rng) != null:
				drops += 1
		_check(drops > 0 and drops < 400 or table.drop_chance >= 1.0, "%s still drops through the original roll()" % id)
	var warden := _table("warden_loot")
	var guaranteed := warden.roll(rng)
	_check(guaranteed != null and warden.drop_chance == 1.0, "the Warden table still always drops something through roll()")
