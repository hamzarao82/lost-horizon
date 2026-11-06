extends SceneTree
## Bag: collecting, stacking limits, overflow, removal, sorting, filtering, consumables, protection,
## save round trip and old-format loading.
##   godot --headless --path . -s tests/items_inventory_check.gd

const ITEMS: String = "res://resources/items/"

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


func _inventory() -> Inventory:
	var inventory := Inventory.new()
	inventory.weapon = _item("improvised_blade")
	return inventory


func _health(current: float = 100.0, maximum: float = 100.0) -> HealthComponent:
	var health := HealthComponent.new()
	health.max_health = maximum
	health.health = current
	return health


func _run() -> void:
	_test_collect_and_stack()
	_test_capacity()
	_test_remove_drop_protect()
	_test_sort_filter()
	_test_consumables()
	_test_currency()
	_test_persistence()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_collect_and_stack() -> void:
	print("Collect and stack")
	var inventory := _inventory()
	var scrap := _item("scrap_metal")
	var result := inventory.collect(scrap, 5)
	_check(result["added"] == 5 and result["overflow"] == 0, "collecting 5 scrap adds 5")
	_check(inventory.count_of("scrap_metal") == 5 and inventory.stack_count() == 1, "they form one stack")
	inventory.collect(scrap, 94)
	_check(inventory.count_of("scrap_metal") == 99 and inventory.stack_count() == 1, "stacks fill to the maximum of 99")
	inventory.collect(scrap, 3)
	_check(inventory.count_of("scrap_metal") == 102 and inventory.stack_count() == 2, "extra scrap starts a second stack")
	var medkit := _item("health_potion")
	inventory.collect(medkit, 2)
	_check(inventory.potions == 2 and inventory.count_of("health_potion") == 2, "medkits go to the existing medkit pool")
	var credits := inventory.collect(_item("credits_medium"), 2)
	_check(inventory.currency == 120 and credits["added"] == 2, "credit pickups add currency, not bag stacks")
	_check(inventory.add_item(_item("bandage")) and inventory.count_of("bandage") == 1, "add_item routes a consumable to the bag")
	_check(not inventory.add_item(_item("improvised_blade")), "add_item keeps the old rule: a worse weapon is not taken")
	_check(inventory.collect(_item("katana"), 1)["added"] == 1 and inventory.count_of("katana") == 1, "collect() can store a spare weapon in the bag")
	_check(inventory.collect(_item("katana"), 1)["added"] == 0, "a second copy of the same equipment is refused")
	inventory.free()


func _test_capacity() -> void:
	print("Capacity")
	var inventory := _inventory()
	var filler: Array[String] = ["scrap_metal", "cloth_scrap", "antiseptic", "electronics", "upgrade_kit_weapon",
			"upgrade_kit_armor", "bandage", "armor_patch", "sharpening_oil", "teleport_cell", "dog_tag"]
	var stacks := 0
	for id in filler:
		inventory.collect(_item(id), 1)
		stacks += 1
	_check(inventory.stack_count() == stacks, "each distinct item takes one stack")
	# Fill the remaining stacks with full stacks of scrap to hit the capacity limit.
	var scrap := _item("scrap_metal")
	var guard := 0
	while inventory.stack_count() < Inventory.BAG_CAPACITY and guard < 200:
		inventory.collect(scrap, 99)
		guard += 1
	_check(inventory.stack_count() == Inventory.BAG_CAPACITY, "the bag stops at its capacity of %d stacks" % Inventory.BAG_CAPACITY)
	_check(not inventory.can_fit(scrap, 99) or inventory.count_of("scrap_metal") % 99 != 0, "can_fit agrees with a full bag")
	var before := inventory.count_of("scrap_metal")
	var overflow := inventory.collect(scrap, 200)
	_check(overflow["overflow"] > 0 and inventory.count_of("scrap_metal") <= before + 200, "overflow is reported, not silently lost")
	_check(overflow["added"] + overflow["overflow"] == 200, "added plus overflow equals the request")
	inventory.free()


func _test_remove_drop_protect() -> void:
	print("Remove, drop, protection")
	var inventory := _inventory()
	inventory.collect(_item("scrap_metal"), 10)
	_check(not inventory.remove("scrap_metal", 11) and inventory.count_of("scrap_metal") == 10, "removing more than owned changes nothing")
	_check(inventory.remove("scrap_metal", 4) and inventory.count_of("scrap_metal") == 6, "removing some leaves the rest")
	_check(not inventory.remove("scrap_metal", 0) and not inventory.remove("scrap_metal", -3), "zero and negative removals are refused")
	_check(inventory.remove("scrap_metal", 6) and inventory.count_of("scrap_metal") == 0 and inventory.stack_count() == 0, "emptying a stack frees its slot")
	inventory.collect(_item("dog_tag"), 3)
	var dropped := inventory.drop("dog_tag", 2)
	_check(dropped["ok"] and inventory.count_of("dog_tag") == 1, "an ordinary item can be dropped")
	inventory.collect(_item("intel_drive"), 1)
	var refused := inventory.drop("intel_drive", 1)
	_check(not refused["ok"] and refused["reason"] == "protected" and inventory.count_of("intel_drive") == 1, "quest items cannot be dropped")
	_check(not inventory.drop("bandage", 1)["ok"], "dropping something not owned fails")
	var quest := ItemData.new()
	quest.item_id = &"test_quest_note"
	quest.kind = ItemData.Kind.QUEST
	quest.quest_item = true
	quest.max_stack = 1
	inventory.collect(quest, 1)
	_check(not inventory.drop("test_quest_note", 1)["ok"], "an item flagged quest_item is protected")
	inventory.free()


func _test_sort_filter() -> void:
	print("Sort and filter")
	var inventory := _inventory()
	for id in ["scrap_metal", "bandage", "dog_tag", "upgrade_kit_weapon", "electronics", "teleport_cell"]:
		inventory.collect(_item(id), 1)
	var weapons := inventory.stacks(ItemData.Category.CONSUMABLE)
	_check(weapons.size() == 2, "filtering by category returns only that category (2 consumables)")
	_check(inventory.stacks(ItemData.Category.MATERIAL).size() == 2, "filtering materials returns 2")
	_check(inventory.stacks().size() == 6, "no filter returns everything")
	var count_before := inventory.stacks().size()
	inventory.sort_bag()
	var sorted := inventory.stacks()
	var ordered := true
	for i in range(1, sorted.size()):
		var a := sorted[i - 1]["item"] as ItemData
		var b := sorted[i]["item"] as ItemData
		if a.category() > b.category() or (a.category() == b.category() and a.rarity < b.rarity):
			ordered = false
	_check(ordered and sorted.size() == count_before, "sorting orders by category then rarity and loses nothing")
	inventory.free()


func _test_consumables() -> void:
	print("Consumables")
	var inventory := _inventory()
	inventory.collect(_item("bandage"), 2)
	inventory.collect(_item("armor_patch"), 1)
	inventory.collect(_item("sharpening_oil"), 1)
	var health := _health(60.0)
	var used := inventory.use_item("bandage", health)
	_check(used["ok"] and is_equal_approx(health.health, 85.0) and inventory.count_of("bandage") == 1, "a bandage heals 25 and is consumed")
	var again := inventory.use_item("bandage", health)
	_check(not again["ok"] and again["reason"] == "cooldown" and inventory.count_of("bandage") == 1, "the cooldown blocks an immediate second use")
	inventory.tick(2.0)
	health.health = 100.0
	var full := inventory.use_item("bandage", health)
	_check(not full["ok"] and full["reason"] == "full_health" and inventory.count_of("bandage") == 1, "healing at full health is refused and wastes nothing")
	var dead := _health(0.0)
	_check(not inventory.use_item("bandage", dead)["ok"], "consumables cannot be used while dead")
	health.health = 50.0
	health.set_armor(40.0, 10.0)
	var armored := inventory.use_item("armor_patch", health)
	_check(armored["ok"] and is_equal_approx(health.armor, 40.0), "an armor patch restores the armor bar (capped at max)")
	health.set_armor(40.0, 40.0)
	inventory.collect(_item("armor_patch"), 1)
	inventory.tick(2.0)
	_check(inventory.use_item("armor_patch", health)["reason"] == "armor_full", "a patch is not wasted on a full bar")
	var before := inventory.stat_totals()["damage_mult"] as float
	_check(inventory.use_item("sharpening_oil", health)["ok"], "sharpening oil can be used")
	var buffed := inventory.stat_totals()["damage_mult"] as float
	_check(is_equal_approx(buffed, before * 1.10), "the buff multiplies damage by 1.10")
	inventory.collect(_item("sharpening_oil"), 1)
	inventory.tick(6.0)
	inventory.use_item("sharpening_oil", health)
	_check(is_equal_approx(inventory.stat_totals()["damage_mult"], before * 1.10), "re-using a buff refreshes it and never stacks")
	inventory.tick(61.0)
	_check(is_equal_approx(inventory.stat_totals()["damage_mult"], before), "the buff expires after its duration")
	_check(not inventory.use_item("scrap_metal", health)["ok"], "materials cannot be used")
	inventory.potions = 1
	health.health = 30.0
	var medkit := inventory.use_item("health_potion", health)
	_check(medkit["ok"] and inventory.potions == 0 and health.health == 70.0, "the medkit still works through use_item and the old healing path")
	health.free()
	dead.free()
	inventory.free()


func _test_currency() -> void:
	print("Currency")
	var inventory := _inventory()
	inventory.add_currency(100)
	_check(inventory.currency == 100, "currency is added")
	_check(not inventory.spend_currency(101) and inventory.currency == 100, "overspending is refused and changes nothing")
	_check(inventory.spend_currency(40) and inventory.currency == 60, "spending reduces the balance")
	inventory.add_currency(-5)
	_check(inventory.currency == 60, "negative additions are ignored")
	inventory.add_currency(Inventory.MAX_CURRENCY * 2)
	_check(inventory.currency == Inventory.MAX_CURRENCY, "currency is capped")
	inventory.free()


func _test_persistence() -> void:
	print("Persistence")
	var inventory := _inventory()
	inventory.collect(_item("scrap_metal"), 120)
	inventory.collect(_item("bandage"), 3)
	inventory.collect(_item("katana"), 1)
	inventory.add_currency(250)
	inventory.potions = 2
	inventory.upgrades["katana"] = 2
	inventory.unique_claimed["intel_drive"] = true
	inventory.merchant_stock["outpost_quartermaster"] = {"teleport_cell": 1}
	var data := inventory.to_dict()
	var restored := _inventory()
	restored.from_dict(data)
	_check(restored.count_of("scrap_metal") == 120 and restored.count_of("bandage") == 3, "bag contents round trip")
	_check(restored.count_of("katana") == 1 and restored.level_of(_item("katana")) == 2, "gear and its upgrade level round trip")
	_check(restored.currency == 250 and restored.potions == 2, "currency and medkits round trip")
	_check(restored.is_unique_claimed("intel_drive"), "claimed unique rewards round trip")
	_check(restored.merchant_stock["outpost_quartermaster"]["teleport_cell"] == 1, "merchant stock state round trips")
	_check(restored.invalid_ids_dropped == 0, "a clean save drops nothing")
	# Old format: only the original four keys.
	var old := _inventory()
	old.from_dict({"weapon": "katana", "armor": "reinforced_armor", "armor_points": 10.0, "potions": 3})
	_check(old.weapon.item_id == &"katana" and old.armor.item_id == &"reinforced_armor" and old.potions == 3, "an old-format save keeps weapon, armor and medkits")
	_check(old.currency == 0 and old.stack_count() == 0 and old.unique_claimed.is_empty(), "an old-format save gets empty defaults for everything new")
	# Invalid data.
	var hostile := _inventory()
	hostile.from_dict({
		"weapon": "../../project", "armor": "katana", "potions": 9999, "currency": -50,
		"bag": [{"id": "nope_item", "count": 5}, {"id": "scrap_metal", "count": 99999}, "junk", {"id": "BAD ID", "count": 1}],
		"slots": {"head": "scrap_metal", "legs": "combat_helmet", "wat": "field_boots"},
		"upgrades": {"katana": 99, "missing_item": 3, "scrap_metal": 2},
		"unique_claimed": ["intel_drive", "x y", "Bad Id"],
		"merchant_stock": {"outpost_quartermaster": {"bandage": -4, "bad id": 1}, "bad merchant": {}},
	})
	_check(hostile.weapon != null, "an invalid weapon id leaves a valid weapon")
	_check(hostile.armor == null, "a weapon id in the armor field is rejected")
	_check(hostile.potions == Inventory.MAX_POTIONS and hostile.currency == 0, "out-of-range numbers are clamped")
	_check(hostile.count_of("scrap_metal") == 99 and hostile.count_of("nope_item") == 0, "bag counts are clamped and unknown ids dropped")
	_check(hostile.equipped(ItemData.Slot.HEAD) == null and hostile.equipped(ItemData.Slot.LEGS) == null, "items in the wrong slot are rejected")
	_check(hostile.level_of(_item("katana")) == _item("katana").max_upgrade, "upgrade levels are clamped to the maximum")
	_check(not hostile.upgrades.has("scrap_metal") and not hostile.upgrades.has("missing_item"), "upgrades for non-equipment or unknown ids are dropped")
	_check(hostile.unique_claimed.size() == 1 and hostile.unique_claimed.has("intel_drive"), "only valid unique ids survive")
	_check(hostile.merchant_stock["outpost_quartermaster"]["bandage"] == 0 and not hostile.merchant_stock.has("bad merchant"), "merchant stock is clamped and bad ids dropped")
	_check(hostile.invalid_ids_dropped > 0, "dropped ids are counted")
	var clean := Inventory.sanitize({"currency": 5.9, "bag": [{"id": "dog_tag", "count": 500}, {"id": "X"}], "unique_claimed": ["intel_drive", "Bad"]})
	_check(clean["currency"] == 5 and clean["bag"].size() == 1 and clean["bag"][0]["count"] == 99, "sanitize() clamps counts and drops bad ids")
	_check(clean["unique_claimed"] == ["intel_drive"], "sanitize() keeps only well-formed ids")
	restored.free()
	old.free()
	hostile.free()
	inventory.free()
