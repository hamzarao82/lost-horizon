class_name MerchantData
extends Resource
## A vendor definition. stock_* are parallel arrays: item id, price in credits, units for sale (-1 = unlimited).
## Buying prices are always above the price the same vendor pays for that item (no buy-sell loops).

@export var merchant_id: StringName
@export var display_name: String
@export var region: String = ""
@export var stock_ids: PackedStringArray
@export var stock_prices: PackedInt32Array
@export var stock_counts: PackedInt32Array
## What fraction of an item's value this vendor pays when buying, before the rarity multiplier.
@export_range(0.1, 1.0) var sell_multiplier: float = 0.5
## ItemData.Category values this vendor buys; empty = everything that is not protected.
@export var buys_categories: PackedInt32Array


func entry_index(item_id: String) -> int:
	return stock_ids.find(item_id)


func is_valid() -> bool:
	return merchant_id != &"" and stock_ids.size() == stock_prices.size() and stock_ids.size() == stock_counts.size()
