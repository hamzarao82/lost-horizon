class_name CraftingBook
extends RefCounted
## Crafting rules. craft() validates everything first and then changes the inventory, so a failed
## craft never consumes anything.

const RECIPE_DIR: String = "res://resources/recipes/"
const ITEM_DIR: String = "res://resources/items/"


static func load_recipes() -> Array[Recipe]:
	var out: Array[Recipe] = []
	for file in DirAccess.get_files_at(RECIPE_DIR):
		if file.ends_with(".tres"):
			var recipe := load(RECIPE_DIR + file) as Recipe
			if recipe and recipe.is_valid():
				out.append(recipe)
	out.sort_custom(func(a: Recipe, b: Recipe) -> bool: return String(a.recipe_id) < String(b.recipe_id))
	return out


static func output_item(recipe: Recipe) -> ItemData:
	var path := ITEM_DIR + recipe.output_id + ".tres"
	return load(path) as ItemData if ResourceLoader.exists(path) else null


## {"ok": bool, "reason": String, "missing": {id: short_count}}.
static func check(inventory: Inventory, recipe: Recipe) -> Dictionary:
	if recipe == null or not recipe.is_valid():
		return {"ok": false, "reason": "invalid_recipe", "missing": {}}
	var output := output_item(recipe)
	if output == null:
		return {"ok": false, "reason": "unknown_output", "missing": {}}
	var missing: Dictionary = {}
	var needs := recipe.inputs()
	for id in needs.keys():
		var short: int = int(needs[id]) - inventory.count_of(String(id))
		if short > 0:
			missing[id] = short
	if not missing.is_empty():
		return {"ok": false, "reason": "missing_materials", "missing": missing}
	if inventory.currency < recipe.currency_cost:
		return {"ok": false, "reason": "not_enough_currency", "missing": {}}
	if output.unique and inventory.is_unique_claimed(recipe.output_id):
		return {"ok": false, "reason": "already_claimed", "missing": {}}
	# Room is checked after the inputs are taken away, because consuming a stack can free its slot.
	var probe := _room_after_consuming(inventory, needs, output, recipe.output_count)
	if not probe:
		return {"ok": false, "reason": "no_room", "missing": {}}
	return {"ok": true, "reason": "", "missing": {}}


static func craft(inventory: Inventory, recipe: Recipe) -> Dictionary:
	var verdict := check(inventory, recipe)
	if not verdict["ok"]:
		return verdict
	var needs := recipe.inputs()
	var output := output_item(recipe)
	var snapshot := inventory.to_dict()
	for id in needs.keys():
		inventory.remove(String(id), int(needs[id]))
	inventory.spend_currency(recipe.currency_cost)
	var result := inventory.collect(output, recipe.output_count)
	if int(result["added"]) < recipe.output_count:
		inventory.from_dict(snapshot)  # cannot happen after check(), but never lose materials
		return {"ok": false, "reason": "no_room", "missing": {}}
	return {"ok": true, "reason": "", "missing": {}, "output": output, "count": recipe.output_count}


static func _room_after_consuming(inventory: Inventory, needs: Dictionary, output: ItemData, count: int) -> bool:
	var copy := Inventory.new()
	copy.from_dict(inventory.to_dict())
	for id in needs.keys():
		copy.remove(String(id), int(needs[id]))
	var fits := copy.can_fit(output, count)
	copy.free()
	return fits
