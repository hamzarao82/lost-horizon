extends SceneTree
## Writes the Milestone 6 item, recipe, loot-table and merchant resources (existing items are untouched).
##   godot --headless --path . -s tools/gen_items.gd
## Re-running overwrites only the files this script owns.

const ITEMS: String = "res://resources/items/"
const LOOT: String = "res://resources/loot/"
const RECIPES: String = "res://resources/recipes/"
const MERCHANTS: String = "res://resources/merchants/"
const K := ItemData.Kind
const R := ItemData.Rarity


func _initialize() -> void:
	for dir in [RECIPES, MERCHANTS]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_items()
	_recipes()
	_loot()
	_merchant()
	quit()


func _item(id: String, name: String, kind: int, rarity: int, desc: String, props: Dictionary = {}) -> void:
	var item := ItemData.new()
	item.item_id = StringName(id)
	item.display_name = name
	item.kind = kind as ItemData.Kind
	item.rarity = rarity as ItemData.Rarity
	item.description = desc
	for key in props.keys():
		item.set(key, props[key])
	var err := ResourceSaver.save(item, ITEMS + id + ".tres")
	if err != OK:
		push_error("could not save item " + id)


func _items() -> void:
	# Crafting and upgrade materials.
	_item("scrap_metal", "Scrap Metal", K.MATERIAL, R.COMMON, "Twisted plating and spent casings.", {"value": 3, "max_stack": 99})
	_item("cloth_scrap", "Cloth Scrap", K.MATERIAL, R.COMMON, "Clean enough to wrap a wound.", {"value": 2, "max_stack": 99})
	_item("antiseptic", "Antiseptic", K.MATERIAL, R.UNCOMMON, "Sealed field-medic vials.", {"value": 6, "max_stack": 50})
	_item("electronics", "Salvaged Electronics", K.MATERIAL, R.UNCOMMON, "Boards and wiring pulled from dead consoles.", {"value": 10, "max_stack": 50})
	_item("upgrade_kit_weapon", "Weapon Upgrade Kit", K.UPGRADE_COMPONENT, R.UNCOMMON, "Whetstones, grip tape and spare fittings.", {"value": 40, "max_stack": 20})
	_item("upgrade_kit_armor", "Armor Upgrade Kit", K.UPGRADE_COMPONENT, R.UNCOMMON, "Plate liners, straps and rivets.", {"value": 40, "max_stack": 20})
	# Consumables (the classic medkit stays health_potion and is counted in Inventory.potions).
	_item("bandage", "Field Bandage", K.CONSUMABLE, R.COMMON, "Restores 25 health.", {"value": 12, "max_stack": 20, "effect": "heal", "effect_amount": 25.0, "cooldown": 1.5})
	_item("armor_patch", "Armor Patch", K.CONSUMABLE, R.UNCOMMON, "Restores 30 armor points.", {"value": 18, "max_stack": 10, "effect": "armor_restore", "effect_amount": 30.0, "cooldown": 1.5})
	_item("sharpening_oil", "Sharpening Oil", K.CONSUMABLE, R.UNCOMMON, "+10% weapon damage for 60 seconds.", {"value": 20, "max_stack": 10, "effect": "buff", "effect_amount": 0.10, "buff_stat": "damage_mult", "buff_seconds": 60.0, "cooldown": 5.0})
	_item("teleport_cell", "Teleport Cell", K.CONSUMABLE, R.RARE, "Restores one teleport charge.", {"value": 60, "max_stack": 3, "effect": "teleport_charge", "effect_amount": 1.0, "cooldown": 3.0})
	# Currency pickups and collectibles.
	_item("credits_small", "Credits (20)", K.COLLECTIBLE, R.COMMON, "Outpost script, good at any trader.", {"currency_amount": 20})
	_item("credits_medium", "Credits (60)", K.COLLECTIBLE, R.UNCOMMON, "A bundle of outpost script.", {"currency_amount": 60})
	_item("dog_tag", "Dog Tag", K.COLLECTIBLE, R.COMMON, "Someone from Outpost 17 never came home.", {"value": 8, "max_stack": 99})
	_item("intel_drive", "Intel Drive", K.QUEST, R.RARE, "Encrypted. The signal is not the only thing on it.", {"quest_item": true, "unique": true, "max_stack": 1})
	# Wearable gear for the new slots. Bonuses stay small: no single piece adds more than 8% to anything.
	_item("combat_helmet", "Combat Helmet", K.ARMOR, R.UNCOMMON, "Dented, but it still turns a blow.", {"slot": ItemData.Slot.HEAD, "value": 45, "base_stats": {"max_health": 6.0, "damage_reduction": 0.02}})
	_item("tactical_gloves", "Tactical Gloves", K.ARMOR, R.UNCOMMON, "A firmer grip on every swing.", {"slot": ItemData.Slot.GLOVES, "value": 40, "base_stats": {"damage_mult": 1.03}})
	_item("field_boots", "Field Boots", K.ARMOR, R.UNCOMMON, "Broken in by someone who walked far.", {"slot": ItemData.Slot.LEGS, "value": 40, "base_stats": {"move_speed_mult": 1.04}})
	_item("signal_charm", "Signal Charm", K.ARMOR, R.RARE, "A radio crystal on a cord. It hums near the mast.", {"slot": ItemData.Slot.ACCESSORY, "value": 90, "base_stats": {"damage_reduction": 0.03, "max_health": 4.0}})


func _recipe(id: String, name: String, desc: String, inputs: Dictionary, output: String, count: int, credits: int) -> void:
	var recipe := Recipe.new()
	recipe.recipe_id = StringName(id)
	recipe.display_name = name
	recipe.description = desc
	var ids := PackedStringArray()
	var counts := PackedInt32Array()
	for key in inputs.keys():
		ids.append(String(key))
		counts.append(int(inputs[key]))
	recipe.input_ids = ids
	recipe.input_counts = counts
	recipe.output_id = output
	recipe.output_count = count
	recipe.currency_cost = credits
	ResourceSaver.save(recipe, RECIPES + id + ".tres")


func _recipes() -> void:
	_recipe("bandage", "Field Bandage", "Wrap a wound in clean cloth.", {"cloth_scrap": 2}, "bandage", 1, 0)
	_recipe("medkit_supply", "Medkit Supply", "Assemble a full medkit.", {"cloth_scrap": 3, "antiseptic": 1}, "health_potion", 1, 0)
	_recipe("armor_patch", "Armor Patch", "Quick plating for the armor bar.", {"scrap_metal": 3, "cloth_scrap": 1}, "armor_patch", 1, 0)
	_recipe("sharpening_oil", "Sharpening Oil", "Weapon maintenance in a bottle.", {"antiseptic": 1, "scrap_metal": 1}, "sharpening_oil", 1, 0)
	_recipe("upgrade_kit_weapon", "Weapon Upgrade Kit", "Everything needed to improve a blade.", {"scrap_metal": 4, "electronics": 1}, "upgrade_kit_weapon", 1, 20)
	_recipe("upgrade_kit_armor", "Armor Upgrade Kit", "Everything needed to improve armor.", {"scrap_metal": 3, "cloth_scrap": 2}, "upgrade_kit_armor", 1, 20)


func _table(id: String, source: int, region: String, chance: float, rolls: int, entries: Array, guaranteed: Array = [], rarity_weights: Array = []) -> void:
	var table := LootTable.new()
	table.source = source as LootTable.Source
	table.region = region
	table.drop_chance = chance
	table.rolls = rolls
	var paths := PackedStringArray()
	var weights := PackedFloat32Array()
	var maxes := PackedInt32Array()
	for entry in entries:
		paths.append(ITEMS + String(entry[0]) + ".tres")
		weights.append(float(entry[1]))
		maxes.append(int(entry[2]) if entry.size() > 2 else 1)
	table.item_paths = paths
	table.weights = weights
	table.max_counts = maxes
	var fixed := PackedStringArray()
	for item_id in guaranteed:
		fixed.append(ITEMS + String(item_id) + ".tres")
	table.guaranteed_paths = fixed
	if not rarity_weights.is_empty():
		table.rarity_weights = PackedFloat32Array(rarity_weights)
	ResourceSaver.save(table, LOOT + id + ".tres")


func _loot() -> void:
	var L := LootTable.Source
	_table("enemy_regular", L.REGULAR, "outpost17", 0.35, 1,
			[["scrap_metal", 40, 2], ["cloth_scrap", 30, 2], ["credits_small", 20], ["bandage", 10]])
	_table("enemy_elite", L.ELITE, "outpost17", 0.6, 2,
			[["scrap_metal", 30, 3], ["credits_small", 20, 2], ["armor_patch", 12], ["antiseptic", 12],
			["field_boots", 3], ["tactical_gloves", 3], ["upgrade_kit_weapon", 4]])
	_table("enemy_miniboss", L.MINIBOSS, "outpost17", 1.0, 2,
			[["scrap_metal", 30, 4], ["electronics", 18, 2], ["armor_patch", 12], ["combat_helmet", 6],
			["credits_medium", 20]], ["upgrade_kit_armor"], [1.0, 1.0, 1.5, 2.0, 2.0])
	_table("crate_common", L.CRATE, "outpost17", 1.0, 2,
			[["scrap_metal", 30, 3], ["cloth_scrap", 30, 3], ["bandage", 15, 2], ["credits_small", 15],
			["antiseptic", 8], ["armor_patch", 8], ["dog_tag", 4]])
	_table("crate_hidden", L.HIDDEN, "outpost17", 1.0, 2,
			[["electronics", 20, 2], ["credits_medium", 20], ["combat_helmet", 3], ["tactical_gloves", 3],
			["signal_charm", 2], ["teleport_cell", 4], ["sharpening_oil", 8]], ["dog_tag"], [1.0, 1.0, 1.2, 1.5, 1.5])
	_table("reward_first_signal", L.REWARD, "outpost17", 1.0, 0, [],
			["credits_medium", "upgrade_kit_weapon", "intel_drive"])


func _merchant() -> void:
	var merchant := MerchantData.new()
	merchant.merchant_id = &"outpost_quartermaster"
	merchant.display_name = "Quartermaster Vale"
	merchant.region = "outpost17"
	var stock := [
		["bandage", 25, -1], ["armor_patch", 40, -1], ["cloth_scrap", 5, -1], ["scrap_metal", 7, -1],
		["antiseptic", 14, 10], ["health_potion", 70, 2], ["sharpening_oil", 45, 5],
		["upgrade_kit_weapon", 95, 3], ["upgrade_kit_armor", 95, 3], ["teleport_cell", 150, 2],
		["combat_helmet", 120, 1], ["field_boots", 105, 1],
	]
	var ids := PackedStringArray()
	var prices := PackedInt32Array()
	var counts := PackedInt32Array()
	for entry in stock:
		ids.append(entry[0])
		prices.append(entry[1])
		counts.append(entry[2])
	merchant.stock_ids = ids
	merchant.stock_prices = prices
	merchant.stock_counts = counts
	merchant.sell_multiplier = 0.5
	ResourceSaver.save(merchant, MERCHANTS + "outpost_quartermaster.tres")
