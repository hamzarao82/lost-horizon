extends Node
## Autoload "WorldState": story/puzzle flags and world events. It lives outside the scene, so
## the power puzzle, opened gate and taken crates survive a death restart (scene reload).
## Flags are plain booleans keyed by stable ids; nothing here references live nodes.

signal flag_changed(id: StringName, value: bool)
signal interacted(id: StringName)
signal area_entered(id: StringName)

var _flags: Dictionary = {}  # StringName -> bool


func set_flag(id: StringName, value: bool = true) -> void:
	var old: bool = _flags.get(id, false)
	if value:
		_flags[id] = true
	else:
		_flags.erase(id)
	if old != value:
		flag_changed.emit(id, value)


func has_flag(id: StringName) -> bool:
	return _flags.get(id, false)


func emit_interacted(id: StringName) -> void:
	interacted.emit(id)


func emit_area_entered(id: StringName) -> void:
	area_entered.emit(id)


## Only the ids of flags that are set; safe to put straight into a save file.
func to_dict() -> Dictionary:
	var ids: Array = []
	for id in _flags:
		ids.append(String(id))
	ids.sort()
	return {"flags": ids}


## Unknown shapes are ignored; ids are sanitized so a hostile save cannot inject odd keys.
func from_dict(data: Dictionary) -> void:
	_flags.clear()
	var ids: Variant = data.get("flags", [])
	if ids is Array:
		for id in ids as Array:
			var s := str(id)
			if s.length() > 0 and s.length() <= 48 and _is_plain(s):
				_flags[StringName(s)] = true
	flag_changed.emit(&"*", true)


func reset() -> void:
	_flags.clear()
	flag_changed.emit(&"*", false)


func _is_plain(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true
