class_name MerchantService
extends RefCounted
## Buying and selling rules. Every call validates first and changes the inventory only on success.
## Stock levels that have changed are stored in Inventory.merchant_stock (saved with the inventory).

const ITEM_DIR: String = "res://resources/items/"


static func item_for(item_id: String) -> ItemData:
	var path := ITEM_DIR + item_id + ".tres"
	return load(path) as ItemData if Inventory._valid_id(item_id) and ResourceLoader.exists(path) else null


## Units still for sale (-1 = unlimited, 0 = sold out, -2 = vendor does not sell it).
static func stock_left(inventory: Inventory, merchant: MerchantData, item_id: String) -> int:
	var index := merchant.entry_index(item_id)
	if index < 0:
		return -2
	var base := merchant.stock_counts[index]
	if base < 0:
		return -1
	var changed: Dictionary = inventory.merchant_stock.get(String(merchant.merchant_id), {})
	return int(changed.get(item_id, base))


static func buy_price(merchant: MerchantData, item_id: String) -> int:
	var index := merchant.entry_index(item_id)
	return merchant.stock_prices[index] if index >= 0 else -1


## What the vendor pays for one unit; 0 means it does not buy the item.
static func sell_price(merchant: MerchantData, item: ItemData) -> int:
	if item.value <= 0 or item.is_protected():
		return 0
	if not merchant.buys_categories.is_empty() and not merchant.buys_categories.has(int(item.category())):
		return 0
	return maxi(1, roundi(item.value * merchant.sell_multiplier * RarityTable.sell_multiplier(item.rarity)))


static func buy(inventory: Inventory, merchant: MerchantData, item_id: String, quantity: int = 1) -> Dictionary:
	if quantity <= 0 or merchant == null or not merchant.is_valid():
		return {"ok": false, "reason": "invalid"}
	var left := stock_left(inventory, merchant, item_id)
	if left == -2:
		return {"ok": false, "reason": "not_sold"}
	if left != -1 and left < quantity:
		return {"ok": false, "reason": "sold_out" if left == 0 else "not_enough_stock"}
	var item := item_for(item_id)
	if item == null:
		return {"ok": false, "reason": "unknown_item"}
	if item.unique and inventory.is_unique_claimed(item_id):
		return {"ok": false, "reason": "already_claimed"}
	if item.is_equipment() and quantity > 1:
		return {"ok": false, "reason": "single_only"}
	var total := buy_price(merchant, item_id) * quantity
	if inventory.currency < total:
		return {"ok": false, "reason": "not_enough_currency", "price": total}
	if not inventory.can_fit(item, quantity) or (item.is_equipment() and inventory.count_of(item_id) + (1 if inventory.is_equipped(item) else 0) > 0):
		return {"ok": false, "reason": "no_room"}
	inventory.spend_currency(total)
	var result := inventory.collect(item, quantity)
	if int(result["added"]) < quantity:
		inventory.add_currency(total)  # refund; collect() could not take everything
		if int(result["added"]) > 0:
			inventory.remove(item_id, int(result["added"]))
		return {"ok": false, "reason": "no_room"}
	if left != -1:
		var key := String(merchant.merchant_id)
		var entry: Dictionary = inventory.merchant_stock.get(key, {})
		entry[item_id] = left - quantity
		inventory.merchant_stock[key] = entry
	return {"ok": true, "reason": "", "price": total, "item": item}


static func sell(inventory: Inventory, merchant: MerchantData, item_id: String, quantity: int = 1) -> Dictionary:
	if quantity <= 0 or merchant == null or not merchant.is_valid():
		return {"ok": false, "reason": "invalid"}
	var item := inventory.bag_item(item_id)
	if item == null:
		return {"ok": false, "reason": "not_in_bag"}
	if item.is_protected():
		return {"ok": false, "reason": "protected"}
	var each := sell_price(merchant, item)
	if each <= 0:
		return {"ok": false, "reason": "not_wanted"}
	if inventory.count_of(item_id) < quantity:
		return {"ok": false, "reason": "not_enough"}
	inventory.remove(item_id, quantity)
	inventory.add_currency(each * quantity)
	return {"ok": true, "reason": "", "price": each * quantity, "item": item}
