class_name QuestState
extends RefCounted
## Normalises quest save data. Used when loading, so a damaged or hand-edited save can never crash
## the game: wrong types, oversized lists and unknown shapes are dropped.

const MAX_QUESTS: int = 32
const MAX_ENTRIES: int = 64
const MAX_ID_LENGTH: int = 64


## Returns {} when there is nothing usable (callers then treat the save as having no quest data).
static func sanitize(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var data: Dictionary = raw
	if data.is_empty():
		return {}
	var active := {}
	var active_raw: Variant = data.get("active", {})
	if active_raw is Dictionary:
		for key in (active_raw as Dictionary).keys():
			if active.size() >= MAX_QUESTS:
				break
			var id := _id(key)
			var entry: Variant = (active_raw as Dictionary)[key]
			if id.is_empty() or not entry is Dictionary:
				continue
			active[id] = {
				"progress": _int_list(entry.get("progress", [])),
				"seen": _string_lists(entry.get("seen", [])),
				"done": _bool_list(entry.get("done", [])),
			}
	var world: Dictionary = {}
	var world_raw: Variant = data.get("world", {})
	if world_raw is Dictionary:
		world = (world_raw as Dictionary).duplicate(true)
	return {
		"active": active,
		"completed": _string_list(data.get("completed", [])),
		"rewarded": _string_list(data.get("rewarded", [])),
		"pending_rewards": _string_list(data.get("pending_rewards", [])),
		"history": _string_list(data.get("history", [])),
		"intro_done": typeof(data.get("intro_done", false)) == TYPE_BOOL and data.get("intro_done", false),
		"world": world,
	}


static func _id(value: Variant) -> String:
	if not (value is String or value is StringName):
		return ""
	var text := String(value)
	return text if text.length() <= MAX_ID_LENGTH else ""


static func _string_list(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			var text := _id(item)
			if not text.is_empty() and not result.has(text) and result.size() < MAX_ENTRIES:
				result.append(text)
	return result


static func _string_lists(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			if result.size() >= MAX_ENTRIES:
				break
			result.append(_string_list(item))
	return result


static func _int_list(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			if result.size() >= MAX_ENTRIES:
				break
			result.append(clampi(int(item) if (item is int or item is float) else 0, 0, 100000))
	return result


static func _bool_list(value: Variant) -> Array:
	var result: Array = []
	if value is Array:
		for item in value:
			if result.size() >= MAX_ENTRIES:
				break
			result.append(item is bool and item)
	return result
