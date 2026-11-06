class_name LootTable
extends Resource
## Weighted drop table. item_paths and weights are parallel arrays.
##
## roll() is the original single-drop behaviour (enemies, waves). Milestone 6 adds roll_all(), which
## supports guaranteed entries, several rolls, rarity weighting, stack counts and unique-reward
## protection, and tags for the loot source and region.

enum Source { REGULAR, ELITE, MINIBOSS, BOSS, CRATE, HIDDEN, REWARD }

@export_range(0.0, 1.0) var drop_chance: float = 0.5
@export var item_paths: PackedStringArray
@export var weights: PackedFloat32Array

@export var source: Source = Source.REGULAR
@export var region: String = ""
## Items that always drop (skipped only when they are unique and already claimed).
@export var guaranteed_paths: PackedStringArray
## How many weighted rolls roll_all() makes; each is gated by drop_chance.
@export var rolls: int = 1
## Multipliers on each entry's weight by the item's rarity (common..legendary). Empty = no change.
@export var rarity_weights: PackedFloat32Array
## Optional parallel to item_paths: the largest stack that can drop (1 when missing).
@export var max_counts: PackedInt32Array


func roll(rng: RandomNumberGenerator = null) -> ItemData:
	if item_paths.is_empty() or item_paths.size() != weights.size():
		return null
	var generator := rng if rng else RandomNumberGenerator.new()
	if rng == null:
		generator.randomize()
	if generator.randf() > drop_chance:
		return null
	var total := 0.0
	for w in weights:
		total += w
	var pick := generator.randf() * total
	for i in item_paths.size():
		pick -= weights[i]
		if pick <= 0.0:
			return load(item_paths[i]) as ItemData
	return load(item_paths[item_paths.size() - 1]) as ItemData


## Everything this table drops once: [{"item": ItemData, "count": int}]. `claimed` is the set of unique
## item ids already received (Inventory.unique_claimed); those never drop again.
func roll_all(rng: RandomNumberGenerator, claimed: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in guaranteed_paths:
		var item := load(path) as ItemData
		if item and not (item.unique and claimed.has(String(item.item_id))):
			out.append({"item": item, "count": 1})
	if item_paths.is_empty() or item_paths.size() != weights.size():
		return out
	var items: Array[ItemData] = []
	var effective: Array[float] = []
	for i in item_paths.size():
		var item := load(item_paths[i]) as ItemData
		if item == null or (item.unique and claimed.has(String(item.item_id))):
			continue
		var weight := weights[i]
		if rarity_weights.size() == 5:
			weight *= rarity_weights[clampi(item.rarity, 0, 4)]
		if weight > 0.0:
			items.append(item)
			effective.append(weight)
	if items.is_empty():
		return out
	var total := 0.0
	for w in effective:
		total += w
	for roll_index in maxi(rolls, 0):
		if rng.randf() > drop_chance:
			continue
		var pick := rng.randf() * total
		var chosen := items.size() - 1
		for i in items.size():
			pick -= effective[i]
			if pick <= 0.0:
				chosen = i
				break
		var item := items[chosen]
		var most := 1
		var source_index := item_paths.find(String(item.resource_path))
		if source_index >= 0 and source_index < max_counts.size():
			most = maxi(max_counts[source_index], 1)
		var count := rng.randi_range(1, most)
		if item.unique:
			if claimed.has(String(item.item_id)) or _already_in(out, item):
				continue
			count = 1
		out.append({"item": item, "count": count})
	return out


func _already_in(entries: Array[Dictionary], item: ItemData) -> bool:
	for entry in entries:
		if entry["item"] == item:
			return true
	return false
