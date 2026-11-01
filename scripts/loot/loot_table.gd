class_name LootTable
extends Resource
## Weighted drop table. item_paths and weights are parallel arrays.

@export_range(0.0, 1.0) var drop_chance: float = 0.5
@export var item_paths: PackedStringArray
@export var weights: PackedFloat32Array


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
