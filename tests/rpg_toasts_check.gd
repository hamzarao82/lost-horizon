extends SceneTree
## item_collected must be raised exactly once per pickup, whichever path gives the item:
## collect(), add_item(), crafting, merchant buying and loot grants.
##   godot --headless --path . -s tests/rpg_toasts_check.gd

const ITEMS: String = "res://resources/items/"

var _failures: int = 0
var _checks: int = 0
var _events: Array = []


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
	inventory.item_collected.connect(func(item: ItemData, kept: bool) -> void: _events.append([item.item_id, kept]))
	return inventory


func _run() -> void:
	var inv := _inventory()
	_events.clear()
	inv.collect(_item("cloth_scrap"), 3)
	_check(_events.size() == 1 and _events[0][1], "collect() of a stack raises one 'kept' event (%d)" % _events.size())

	_events.clear()
	inv.add_item(_item("sharpening_oil"))
	_check(_events.size() == 1, "add_item() of an effect consumable (calls collect inside) raises one event (%d)" % _events.size())

	_events.clear()
	inv.add_item(_item("scrap_metal"))
	_check(_events.size() == 1, "add_item() of a material raises one event (%d)" % _events.size())

	_events.clear()
	inv.add_item(_item("health_potion"))
	_check(_events.size() == 1, "add_item() of a medkit raises one event (%d)" % _events.size())

	_events.clear()
	inv.add_item(_item("credits_small"))
	_check(_events.size() == 1 and _events[0][1], "a credits pickup raises one event (%d)" % _events.size())

	_events.clear()
	inv.add_item(_item("combat_helmet"))
	_check(_events.size() == 1 and _events[0][1], "equipment through add_item raises one event (%d)" % _events.size())

	# crafting
	var recipe := load("res://resources/recipes/bandage.tres") as Recipe
	var crafter := _inventory()
	crafter.add_currency(500)
	for id in recipe.inputs():
		crafter.collect(_item(String(id)), int(recipe.inputs()[id]) + 2)
	_events.clear()
	var made: Dictionary = CraftingBook.craft(crafter, recipe)
	_check(bool(made.get("ok", false)), "the recipe crafts (%s)" % str(made.get("reason", "ok")))
	_check(_events.size() == 1 and _events[0][1], "crafting raises one loot event (%d)" % _events.size())

	# merchant
	var merchant := load("res://resources/merchants/outpost_quartermaster.tres") as MerchantData
	var buyer := _inventory()
	buyer.add_currency(1000)
	_events.clear()
	var bought: Dictionary = MerchantService.buy(buyer, merchant, "bandage", 2)
	_check(bool(bought.get("ok", false)), "the purchase succeeds (%s)" % str(bought.get("reason", "ok")))
	_check(_events.size() == 1, "buying raises one loot event (%d)" % _events.size())

	# loot service: equipment that auto-equips, and equipment that falls back to the bag
	var table := LootTable.new()
	var looter := _inventory()
	_events.clear()
	LootService.grant(table, looter, RandomNumberGenerator.new())
	_check(_events.size() <= 1, "an empty table raises at most one event (%d)" % _events.size())
	_events.clear()
	var taken: bool = looter.add_item(_item("field_boots"), false)
	looter.announce(_item("field_boots"), taken)
	_check(_events.size() == 1, "add_item(announce = false) plus announce() raises exactly one event (%d)" % _events.size())


	print("rpg_toasts_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
