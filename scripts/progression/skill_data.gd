class_name SkillData
extends Resource
## One skill. Each rank grants `effects` once (value per rank); ranks cost `cost` skill points each.

enum Category { COMBAT, SURVIVAL, MOBILITY, SPECIAL }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var category: Category = Category.COMBAT
@export var max_rank: int = 3
@export var cost: int = 1
@export var min_level: int = 2
@export var prerequisites: PackedStringArray
## Effect key -> value per rank (see StatsResolver.EFFECTS).
@export var effects: Dictionary = {}
## Screen position inside the tree view (column, row).
@export var tree_position: Vector2i = Vector2i.ZERO


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"" or display_name == "" or description == "":
		errors.append("%s: id, name and description are required" % id)
	if max_rank < 1 or cost < 1 or min_level < 1:
		errors.append("%s: bad rank, cost or level" % id)
	if effects.is_empty():
		errors.append("%s: no effect" % id)
	for key in effects:
		if not StatsResolver.EFFECTS.has(key):
			errors.append("%s: unknown effect '%s'" % [id, key])
	return errors
