extends SceneTree
## Crafting, upgrading and merchants: validation, atomicity, preview == result, money conservation,
## and the unique-weapon upgrade curve.
##   godot --headless --path . -s tests/items_economy_check.gd

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


func _recipe(id: String) -> Recipe:
	return load("res://resources/recipes/" + id + ".tres") as Recipe


func _run() -> void:
	_test_recipes()
	_test_crafting()
	_test_upgrades()
	_test_merchant()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_recipes() -> void:
	print("Recipes")
	var recipes := CraftingBook.load_recipes()
	_check(recipes.size() == 6, "six recipes load and validate (%d)" % recipes.size())
	var outputs_exist := true
	for recipe in recipes:
		outputs_exist = outputs_exist and CraftingBook.output_item(recipe) != null
		for id in recipe.input_ids:
			outputs_exist = outputs_exist and FileAccess.file_exists(ITEMS + id + ".tres")
	_check(outputs_exist, "every recipe input and output is a real item")
	var medkit := _recipe("medkit_supply")
	_check(medkit.output_id == "health_potion", "one recipe builds the existing medkit")
	var broken := Recipe.new()
	_check(not broken.is_valid() and not CraftingBook.check(_inventory(), broken)["ok"], "an empty recipe is invalid and cannot be crafted")


func _test_crafting() -> void:
	print("Crafting")
	var inventory := _inventory()
	var bandage := _recipe("bandage")
	var short := CraftingBook.craft(inventory, bandage)
	_check(not short["ok"] and short["reason"] == "missing_materials" and short["missing"]["cloth_scrap"] == 2, "crafting without materials fails and names what is missing")
	inventory.collect(_item("cloth_scrap"), 3)
	var made := CraftingBook.craft(inventory, bandage)
	_check(made["ok"] and inventory.count_of("bandage") == 1 and inventory.count_of("cloth_scrap") == 1, "a bandage consumes exactly 2 cloth and yields 1 bandage")
	# Atomicity: not enough of the second input leaves everything untouched.
	var medkit := _recipe("medkit_supply")
	inventory.collect(_item("cloth_scrap"), 5)
	var before := inventory.to_dict()
	var failed := CraftingBook.craft(inventory, medkit)
	_check(not failed["ok"] and inventory.to_dict() == before, "a failed craft changes nothing (atomic)")
	inventory.collect(_item("antiseptic"), 1)
	var potions_before := inventory.potions
	var kit := CraftingBook.craft(inventory, medkit)
	_check(kit["ok"] and inventory.potions == potions_before + 1 and inventory.count_of("antiseptic") == 0, "the medkit recipe feeds the single medkit pool")
	# Currency cost
	var weapon_kit := _recipe("upgrade_kit_weapon")
	inventory.collect(_item("scrap_metal"), 8)
	inventory.collect(_item("electronics"), 1)
	var poor := CraftingBook.craft(inventory, weapon_kit)
	_check(not poor["ok"] and poor["reason"] == "not_enough_currency" and inventory.count_of("scrap_metal") == 8, "currency cost is enforced and nothing is consumed")
	inventory.add_currency(25)
	var rich := CraftingBook.craft(inventory, weapon_kit)
	_check(rich["ok"] and inventory.currency == 5 and inventory.count_of("upgrade_kit_weapon") == 1 and inventory.count_of("scrap_metal") == 4, "the kit costs 20 credits plus its materials")
	# Maximum stack: output that cannot fit does not eat inputs.
	var full := _inventory()
	full.potions = Inventory.MAX_POTIONS
	full.collect(_item("cloth_scrap"), 3)
	full.collect(_item("antiseptic"), 1)
	var blocked := CraftingBook.craft(full, medkit)
	_check(not blocked["ok"] and blocked["reason"] == "no_room" and full.count_of("cloth_scrap") == 3, "output with no room fails before anything is consumed")
	inventory.free()
	full.free()


func _test_upgrades() -> void:
	print("Upgrades")
	var inventory := _inventory()
	var katana := _item("katana")
	var not_owned := UpgradeService.preview(katana, inventory)
	_check(not not_owned["ok"] and not_owned["reason"] == "not_owned", "an item that is not owned cannot be upgraded")
	inventory.add_item(katana)
	var plan := UpgradeService.preview(katana, inventory)
	_check(not plan["ok"] and plan["reason"] == "missing_materials" and plan["missing"].has("upgrade_kit_weapon"), "the preview lists the missing kit")
	_check(plan["from"] == 0 and plan["to"] == 1 and plan["after"]["damage_mult"] > plan["before"]["damage_mult"], "the preview shows before and after stats")
	inventory.collect(_item("upgrade_kit_weapon"), 1)
	var price := int(plan["currency"])
	var poor := UpgradeService.preview(katana, inventory)
	_check(poor["reason"] == "not_enough_currency", "materials alone are not enough: it also costs %d credits" % price)
	inventory.add_currency(price + 7)
	var predicted_damage: float = (UpgradeService.preview(katana, inventory)["after"] as Dictionary)["damage_mult"]
	var done := UpgradeService.upgrade(katana, inventory)
	_check(done["ok"] and inventory.level_of(katana) == 1, "the upgrade is applied")
	_check(inventory.count_of("upgrade_kit_weapon") == 0 and inventory.currency == 7, "exactly the previewed materials and credits are spent")
	_check(is_equal_approx(inventory.item_stats(katana)["damage_mult"], predicted_damage), "the applied stats equal the previewed stats")
	_check(is_equal_approx(inventory.damage_multiplier(), predicted_damage), "the equipped weapon's damage uses the upgrade immediately")
	var refused := UpgradeService.upgrade(katana, inventory)
	_check(not refused["ok"] and inventory.level_of(katana) == 1 and inventory.currency == 7, "a refused upgrade spends nothing")
	# Level cap
	inventory.upgrades["katana"] = katana.max_upgrade
	_check(UpgradeService.preview(katana, inventory)["reason"] == "max_level", "the level cap is enforced")
	# Cost growth
	var c0 := int(UpgradeService.cost(katana, 0)["currency"])
	var c3 := int(UpgradeService.cost(katana, 3)["currency"])
	_check(c3 > c0 and int(UpgradeService.cost(katana, 3)["materials"]["upgrade_kit_weapon"]) == 4, "costs grow with the level")
	# Armor
	inventory.add_item(_item("reinforced_armor"))
	var armor := _item("reinforced_armor")
	var armor_before := float(inventory.item_stats(armor)["armor_points"])
	inventory.collect(_item("upgrade_kit_armor"), 1)
	inventory.add_currency(500)
	_check(UpgradeService.upgrade(armor, inventory)["ok"], "armor upgrades with the armor kit")
	_check(float(inventory.item_stats(armor)["armor_points"]) > armor_before, "an upgraded armor has more armor points")
	# Unique weapon identity
	var cleaver := _item("warden_blade")
	var curve_costs := UpgradeService.cost(cleaver, 0)["materials"] as Dictionary
	_check(curve_costs.has("electronics") and curve_costs.has("upgrade_kit_weapon"), "the Cleaver needs salvaged electronics as well as a kit")
	var s1 := UpgradeService.stats_at(cleaver, 2)
	_check(s1["attack_speed"] > cleaver.attack_speed, "at level 2 the Cleaver swings faster, which no ordinary weapon gets")
	_check(UpgradeService.stats_at(katana, 5)["attack_speed"] == katana.attack_speed, "ordinary weapons only gain damage")
	# Save round trip
	var restored := _inventory()
	restored.from_dict(inventory.to_dict())
	_check(restored.level_of(armor) == 1 and restored.level_of(katana) == katana.max_upgrade, "upgrade levels persist")
	restored.free()
	inventory.free()


func _test_merchant() -> void:
	print("Merchant")
	var merchant := load("res://resources/merchants/outpost_quartermaster.tres") as MerchantData
	_check(merchant != null and merchant.is_valid(), "the quartermaster loads and is valid")
	var arbitrage := 0
	for id in merchant.stock_ids:
		var item := MerchantService.item_for(id)
		if item == null:
			arbitrage += 100
			continue
		if MerchantService.sell_price(merchant, item) >= MerchantService.buy_price(merchant, id):
			arbitrage += 1
	_check(arbitrage == 0, "every stock item exists and sells for more than the vendor pays back")
	var inventory := _inventory()
	var poor := MerchantService.buy(inventory, merchant, "bandage", 1)
	_check(not poor["ok"] and poor["reason"] == "not_enough_currency", "buying without money fails")
	inventory.add_currency(200)
	var bought := MerchantService.buy(inventory, merchant, "bandage", 2)
	_check(bought["ok"] and inventory.currency == 150 and inventory.count_of("bandage") == 2, "buying 2 bandages costs 2 x 25")
	_check(not MerchantService.buy(inventory, merchant, "scrap_helmet", 1)["ok"], "items the vendor does not sell cannot be bought")
	_check(not MerchantService.buy(inventory, merchant, "bandage", 0)["ok"] and not MerchantService.buy(inventory, merchant, "bandage", -2)["ok"], "zero and negative quantities are refused")
	# Limited stock
	inventory.add_currency(1000)
	var first := MerchantService.buy(inventory, merchant, "teleport_cell", 1)
	var second := MerchantService.buy(inventory, merchant, "teleport_cell", 1)
	var third := MerchantService.buy(inventory, merchant, "teleport_cell", 1)
	_check(first["ok"] and second["ok"] and not third["ok"] and third["reason"] == "sold_out", "limited stock sells out after 2 purchases")
	_check(MerchantService.stock_left(inventory, merchant, "teleport_cell") == 0 and MerchantService.stock_left(inventory, merchant, "bandage") == -1, "stock levels are tracked; unlimited stock stays unlimited")
	var restored := _inventory()
	restored.from_dict(inventory.to_dict())
	_check(MerchantService.stock_left(restored, merchant, "teleport_cell") == 0, "sold-out stock stays sold out after a reload")
	# Selling
	var credits := inventory.currency
	var sold := MerchantService.sell(inventory, merchant, "bandage", 1)
	_check(sold["ok"] and sold["price"] == 2 and inventory.currency == credits + 2 and inventory.count_of("bandage") == 1, "selling a bandage (value 12, common) pays 12 x 0.5 x 0.4 = 2")
	_check(not MerchantService.sell(inventory, merchant, "bandage", 5)["ok"], "selling more than owned is refused")
	inventory.collect(_item("intel_drive"), 1)
	_check(not MerchantService.sell(inventory, merchant, "intel_drive", 1)["ok"] and inventory.has_item("intel_drive"), "quest items cannot be sold")
	inventory.collect(_item("credits_small"), 1)
	_check(not MerchantService.sell(inventory, merchant, "credits_small", 1)["ok"], "currency pickups are not bag items to sell")
	inventory.collect(_item("katana"), 1)
	var katana_price := MerchantService.sell_price(merchant, _item("katana"))
	_check(katana_price == roundi(150 * 0.5 * RarityTable.sell_multiplier(_item("katana").rarity)), "equipment sells at value x vendor x rarity multiplier")
	inventory.equip(_item("katana"))
	_check(not MerchantService.sell(inventory, merchant, "katana", 1)["ok"], "a worn item cannot be sold")
	# Money conservation: buy everything possible then sell it all back: never ends richer.
	var trader := _inventory()
	trader.add_currency(1000)
	var start := trader.currency
	for id in ["bandage", "armor_patch", "cloth_scrap", "scrap_metal", "antiseptic", "sharpening_oil"]:
		MerchantService.buy(trader, merchant, id, 2)
	for id in ["bandage", "armor_patch", "cloth_scrap", "scrap_metal", "antiseptic", "sharpening_oil"]:
		MerchantService.sell(trader, merchant, id, 2)
	_check(trader.currency < start and trader.currency > 0, "buying and re-selling always loses money (%d of %d left)" % [trader.currency, start])
	var full := _inventory()
	full.add_currency(500)
	full.potions = Inventory.MAX_POTIONS
	var no_room := MerchantService.buy(full, merchant, "health_potion", 1)
	_check(not no_room["ok"] and no_room["reason"] == "no_room" and full.currency == 500, "a purchase with no room is refused and refunds nothing because nothing was charged")
	var gear := _inventory()
	gear.add_currency(500)
	_check(MerchantService.buy(gear, merchant, "combat_helmet", 1)["ok"] and gear.count_of("combat_helmet") == 1, "gear can be bought into the bag")
	_check(not MerchantService.buy(gear, merchant, "combat_helmet", 1)["ok"], "the vendor's single helmet cannot be bought twice")
	trader.free()
	full.free()
	gear.free()
	restored.free()
	inventory.free()
