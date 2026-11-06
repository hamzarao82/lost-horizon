extends SceneTree
## Equipment slots: equip / unequip / replace, comparison, stat totals, no duplicate state, upgrades
## and rarity bounds.
##   godot --headless --path . -s tests/items_equipment_check.gd

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


func _run() -> void:
	_test_slots()
	_test_replace_and_unequip()
	_test_totals_and_compare()
	_test_upgrade_levels()
	_test_data_rules()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_slots() -> void:
	print("Slots")
	var inventory := _inventory()
	_check(_item("combat_helmet").equip_slot() == ItemData.Slot.HEAD, "the helmet goes in the head slot")
	_check(_item("tactical_gloves").equip_slot() == ItemData.Slot.GLOVES and _item("field_boots").equip_slot() == ItemData.Slot.LEGS, "gloves and boots use their own slots")
	_check(_item("signal_charm").equip_slot() == ItemData.Slot.ACCESSORY, "the charm is an accessory")
	_check(_item("katana").equip_slot() == ItemData.Slot.PRIMARY_WEAPON and _item("reinforced_armor").equip_slot() == ItemData.Slot.BODY, "weapons and old armor derive their slots")
	_check(inventory.add_item(_item("combat_helmet")) and inventory.equipped(ItemData.Slot.HEAD) == _item("combat_helmet"), "picking up a helmet auto-equips it into the empty head slot")
	_check(inventory.armor == null and inventory.weapon.item_id == &"improvised_blade", "a helmet does not touch the body armor or weapon")
	inventory.collect(_item("katana"), 1)
	var result := inventory.equip(_item("katana"))
	_check(result["ok"] and inventory.weapon.item_id == &"katana", "equip() puts a bagged weapon in hand")
	_check(inventory.count_of("katana") == 0 and inventory.count_of("improvised_blade") == 1, "the replaced weapon returns to the bag and the equipped one leaves it")
	_check(not inventory.equip(_item("katana"))["ok"], "equipping something already worn is refused")
	_check(not inventory.equip(_item("claymore"))["ok"], "equipping something not in the bag is refused")
	_check(not inventory.equip(_item("scrap_metal"))["ok"], "materials cannot be equipped")
	inventory.free()


func _test_replace_and_unequip() -> void:
	print("Replace and unequip")
	var inventory := _inventory()
	inventory.collect(_item("field_boots"), 1)
	inventory.equip(_item("field_boots"))
	_check(inventory.equipped(ItemData.Slot.LEGS) == _item("field_boots"), "boots equipped")
	var off := inventory.unequip(ItemData.Slot.LEGS)
	_check(off["ok"] and inventory.equipped(ItemData.Slot.LEGS) == null and inventory.count_of("field_boots") == 1, "unequip moves the boots back to the bag")
	_check(not inventory.unequip(ItemData.Slot.LEGS)["ok"], "unequipping an empty slot fails")
	_check(not inventory.unequip(ItemData.Slot.PRIMARY_WEAPON)["ok"] and inventory.weapon != null, "the primary weapon cannot be taken off")
	# Body armor
	inventory.collect(_item("light_tactical_armor"), 1)
	inventory.collect(_item("reinforced_armor"), 1)
	inventory.equip(_item("light_tactical_armor"))
	var replaced := inventory.equip(_item("reinforced_armor"))
	_check(replaced["ok"] and replaced["replaced"] == _item("light_tactical_armor") and inventory.armor == _item("reinforced_armor"), "body armor replace reports the old piece")
	_check(inventory.count_of("light_tactical_armor") == 1 and inventory.count_of("reinforced_armor") == 0, "no piece is both worn and in the bag")
	_check(inventory.unequip(ItemData.Slot.BODY)["ok"] and inventory.armor == null, "body armor can be taken off")
	# Duplicate-state sweep: nothing equipped may also sit in the bag.
	var duplicates := 0
	for slot in [ItemData.Slot.PRIMARY_WEAPON, ItemData.Slot.BODY, ItemData.Slot.HEAD, ItemData.Slot.GLOVES, ItemData.Slot.LEGS, ItemData.Slot.ACCESSORY]:
		var worn := inventory.equipped(slot)
		if worn and inventory.count_of(String(worn.item_id)) > 0:
			duplicates += 1
	_check(duplicates == 0, "no equipped item also appears in the bag")
	_check(inventory.collect(_item("improvised_blade"), 1)["added"] == 0 or inventory.weapon.item_id != &"improvised_blade", "a worn piece cannot be collected a second time")
	# Round trip of worn gear
	inventory.collect(_item("signal_charm"), 1)
	inventory.equip(_item("signal_charm"))
	var restored := _inventory()
	restored.from_dict(inventory.to_dict())
	_check(restored.equipped(ItemData.Slot.ACCESSORY) == _item("signal_charm"), "worn accessories survive the save round trip")
	_check(restored.count_of("signal_charm") == 0, "and are not duplicated into the bag on load")
	restored.free()
	inventory.free()


func _test_totals_and_compare() -> void:
	print("Totals and comparison")
	var inventory := _inventory()
	var base := inventory.stat_totals()
	_check(base.keys().size() == 4 and base.has("damage_mult") and base.has("damage_reduction") and base.has("max_health_bonus") and base.has("move_speed_mult"), "stat_totals() has exactly the four agreed keys")
	_check(is_equal_approx(base["damage_mult"], 1.0) and is_equal_approx(inventory.damage_multiplier(), 1.0), "the starting blade is x1.00 and damage_multiplier() agrees")
	inventory.add_item(_item("katana"))
	_check(is_equal_approx(inventory.stat_totals()["damage_mult"], _item("katana").damage_multiplier), "a better weapon raises damage_mult to its multiplier")
	inventory.add_item(_item("tactical_gloves"))
	_check(is_equal_approx(inventory.stat_totals()["damage_mult"], _item("katana").damage_multiplier * 1.03), "gloves multiply on top (x1.03)")
	inventory.add_item(_item("combat_helmet"))
	inventory.add_item(_item("signal_charm"))
	var totals := inventory.stat_totals()
	_check(is_equal_approx(totals["damage_reduction"], 0.05) and is_equal_approx(totals["max_health_bonus"], 10.0), "helmet + charm: 5% reduction and +10 max health")
	inventory.add_item(_item("field_boots"))
	_check(is_equal_approx(inventory.stat_totals()["move_speed_mult"], 1.04), "boots give +4% movement speed")
	# Immediate update on unequip
	inventory.unequip(ItemData.Slot.GLOVES)
	_check(is_equal_approx(inventory.stat_totals()["damage_mult"], _item("katana").damage_multiplier), "taking gloves off updates the totals immediately")
	# Clamps
	var stacked := _inventory()
	var heavy := ItemData.new()
	heavy.item_id = &"test_heavy_charm"
	heavy.kind = ItemData.Kind.ARMOR
	heavy.slot = ItemData.Slot.ACCESSORY
	heavy.base_stats = {"damage_reduction": 0.9, "move_speed_mult": 2.0}
	stacked._slots[ItemData.Slot.ACCESSORY] = heavy
	var capped := stacked.stat_totals()
	_check(capped["damage_reduction"] <= Inventory.MAX_DAMAGE_REDUCTION and capped["move_speed_mult"] <= Inventory.MOVE_SPEED_MAX, "damage reduction and speed bonuses are capped")
	# Compare
	var delta := inventory.compare(_item("improvised_blade"), _item("katana"))
	_check(delta["damage_mult"] > 0.0 and is_equal_approx(delta["damage_mult"], _item("katana").damage_multiplier - _item("improvised_blade").damage_multiplier), "compare() reports the damage difference")
	var armor_delta := inventory.compare(_item("light_tactical_armor"), _item("heavy_combat_armor"))
	_check(armor_delta["armor_points"] > 0.0, "compare() shows armor points gained")
	var from_nothing := inventory.compare(null, _item("combat_helmet"))
	_check(is_equal_approx(from_nothing["max_health"], 6.0), "comparing against an empty slot gives the item's own bonus")
	var worse := inventory.compare(_item("katana"), _item("improvised_blade"))
	_check(worse["damage_mult"] < 0.0, "a weaker item shows a negative delta")
	stacked.free()
	inventory.free()


func _test_upgrade_levels() -> void:
	print("Upgrade levels in stats")
	var inventory := _inventory()
	var katana := _item("katana")
	var base := inventory.item_stats(katana)["damage_mult"] as float
	inventory.upgrades["katana"] = 5
	var maxed := inventory.item_stats(katana)["damage_mult"] as float
	_check(is_equal_approx(maxed, base * 1.20), "five generic levels add 20% damage")
	var warden := _item("warden_blade")
	var warden_base := UpgradeService.stats_at(warden, 0)
	var warden_max := UpgradeService.stats_at(warden, 5)
	_check(warden_max["damage_mult"] < warden_base["damage_mult"] * 1.20, "the Warden's Cleaver gains less raw damage than the generic curve")
	_check(warden_max["attack_speed"] > warden_base["attack_speed"] and warden_max["damage_reduction"] > 0.0, "and gains distinct bonuses (speed, resistance)")
	_check(UpgradeService.stats_at(katana, 99)["damage_mult"] == maxed, "levels above the cap are clamped")
	inventory.weapon = katana
	_check(is_equal_approx(inventory.damage_multiplier(), maxed), "damage_multiplier() uses the upgraded value, once")
	inventory.free()


func _test_data_rules() -> void:
	print("Item data rules")
	var bad_rarity := 0
	var bad_icon := 0
	var bad_stats := 0
	var files := DirAccess.get_files_at(ITEMS)
	var count := 0
	for file in files:
		if not file.ends_with(".tres"):
			continue
		var item := load(ITEMS + file) as ItemData
		if item == null:
			continue
		count += 1
		if item.icon() == null:
			bad_icon += 1
		var multiplier: float = item.base_stats.get("damage_mult", 1.0)
		if item.kind == ItemData.Kind.ARMOR and item.slot != ItemData.Slot.NONE and item.slot != ItemData.Slot.BODY:
			if multiplier > 1.08 or float(item.base_stats.get("damage_reduction", 0.0)) > 0.08 \
					or float(item.base_stats.get("move_speed_mult", 1.0)) > 1.08 or float(item.base_stats.get("max_health", 0.0)) > 12.0:
				bad_stats += 1
		if item.rarity == ItemData.Rarity.LEGENDARY and not item.unique:
			bad_rarity += 1
	_check(count >= 30, "at least 30 item definitions load (%d)" % count)
	_check(bad_icon == 0, "every item has an icon texture")
	_check(bad_stats == 0, "no wearable piece exceeds the per-item bonus caps")
	_check(bad_rarity == 0, "legendary items are unique boss rewards")
	_check(RarityTable.stat_range(ItemData.Rarity.LEGENDARY).y <= 1.2001 and RarityTable.stat_range(ItemData.Rarity.COMMON).x == 1.0, "rarity stat ranges stay within +20%")
	_check(_item("warden_blade").unique and _item("warden_plate").unique, "the Warden's rewards are unique")
	var sellables := 0
	for id in ["scrap_metal", "katana", "combat_helmet"]:
		if _item(id).value > 0:
			sellables += 1
	_check(sellables == 3, "ordinary items have a currency value")
