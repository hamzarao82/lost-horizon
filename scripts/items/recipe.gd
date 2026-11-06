class_name Recipe
extends Resource
## A crafting recipe. input_ids and input_counts are parallel arrays; ids are item file names under
## resources/items/ ("health_potion" is the medkit).

@export var recipe_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var input_ids: PackedStringArray
@export var input_counts: PackedInt32Array
@export var output_id: String
@export var output_count: int = 1
@export var currency_cost: int = 0


func inputs() -> Dictionary:
	var out: Dictionary = {}
	for i in mini(input_ids.size(), input_counts.size()):
		out[input_ids[i]] = input_counts[i]
	return out


func is_valid() -> bool:
	return input_ids.size() == input_counts.size() and not input_ids.is_empty() \
			and output_id != "" and output_count > 0 and currency_cost >= 0
