class_name FacilityIds
extends RefCounted
## Shared names for the Research Complex components. Every saved id is lowercase letters, digits and
## underscore and at most 48 characters, because WorldState drops anything else when it loads.

const REGION: StringName = &"research_complex"
const LEVELS: Array[StringName] = [&"admin", &"medical", &"lab"]


static func credential_flag(level: StringName) -> StringName:
	return StringName("credential_%s" % String(level))


static func world() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("WorldState") if loop else null


static func has_flag(id: StringName) -> bool:
	var state := world()
	return state != null and state.has_flag(id)


static func set_flag(id: StringName, value: bool = true) -> void:
	var state := world()
	if state != null:
		state.set_flag(id, value)


## True for an id WorldState would keep through a save: [a-z0-9_] and 1..48 characters.
static func is_saveable(id: String) -> bool:
	if id.length() == 0 or id.length() > 48:
		return false
	for i in id.length():
		var c := id.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true
