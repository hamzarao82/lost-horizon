class_name LootService
extends RefCounted
## Rolls a LootTable and puts the result into an Inventory. Equipment goes through add_item (the
## "equip only when better" rule), everything else through collect (stacking, credits, medkits).
## Anything that does not fit is returned in "overflow" so the caller can spawn Pickups for it.


static func grant(table: LootTable, inventory: Inventory, rng: RandomNumberGenerator = null) -> Dictionary:
	var generator := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		generator.randomize()
	var granted: Array[Dictionary] = []
	var overflow: Array[Dictionary] = []
	for entry in table.roll_all(generator, inventory.unique_claimed):
		var item: ItemData = entry["item"]
		var count: int = entry["count"]
		if item.is_equipment():
			var taken := inventory.add_item(item, false)
			if not taken:
				inventory._quiet += 1
				taken = int(inventory.collect(item, 1)["added"]) > 0  # keep it in the bag for selling
				inventory._quiet -= 1
			inventory.announce(item, taken)
			(granted if taken else overflow).append({"item": item, "count": 1})
		else:
			var result := inventory.collect(item, count)
			if int(result["added"]) > 0:
				granted.append({"item": item, "count": int(result["added"])})
			if int(result["overflow"]) > 0:
				overflow.append({"item": item, "count": int(result["overflow"])})
	return {"granted": granted, "overflow": overflow}
