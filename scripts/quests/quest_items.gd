class_name QuestItems
extends RefCounted
## Quest items are NOT inventory items: equipping, replacing or dropping gear can never remove them.
## Stable ids only (e.g. "access_card"); each id is granted once.

const MAX_ITEMS: int = 64
const MAX_ID_LENGTH: int = 48

## id -> display name for toasts. Unknown ids fall back to a readable form of the id.
const NAMES: Dictionary = {
	"access_card": "Security Access Card",
}

var _ids: Array[StringName] = []


## Returns true if the item was new.
func add(id: StringName) -> bool:
	if id == &"" or _ids.has(id) or _ids.size() >= MAX_ITEMS:
		return false
	_ids.append(id)
	return true


func has(id: StringName) -> bool:
	return _ids.has(id)


func all() -> Array[StringName]:
	return _ids.duplicate()


func clear() -> void:
	_ids.clear()


func to_dict() -> Array:
	return _ids.map(func(id: StringName) -> String: return String(id))


## Wrong types, oversized lists and odd ids are dropped.
func from_dict(raw: Variant) -> void:
	_ids.clear()
	if not raw is Array:
		return
	for entry in raw as Array:
		if _ids.size() >= MAX_ITEMS:
			break
		if entry is String or entry is StringName:
			var text := String(entry)
			if text.length() > 0 and text.length() <= MAX_ID_LENGTH and not _ids.has(StringName(text)):
				_ids.append(StringName(text))


static func display_name(id: StringName) -> String:
	return String(NAMES.get(String(id), String(id).replace("_", " ").capitalize()))
