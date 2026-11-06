class_name AttributeData
extends Resource
## One character attribute. `effects` maps an effect key to its value per spent point (see StatsResolver.EFFECTS).

@export var id: StringName
@export var display_name: String
@export_multiline var purpose: String
@export var base: int = 0
@export var max_points: int = 10
@export var effects: Dictionary = {}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"" or display_name == "" or purpose == "":
		errors.append("%s: id, display_name and purpose are required" % id)
	if effects.is_empty():
		errors.append("%s: an attribute without an effect has no gameplay purpose" % id)
	for key in effects:
		if not StatsResolver.EFFECTS.has(key):
			errors.append("%s: unknown effect '%s'" % [id, key])
	if max_points < 1 or base < 0 or base > max_points:
		errors.append("%s: bad base/max" % id)
	return errors
