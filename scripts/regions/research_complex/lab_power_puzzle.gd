class_name LabPowerPuzzle
extends MultiStepPuzzle
## Puzzle B (central laboratory): four breakers must be set to the pattern shown on the wall display, then
## the main lever is pulled. Steps: `pattern` then `engage`. Once the pattern is right it is locked in. A wrong
## lever pull (before the pattern matches) only switches the breakers back off: nothing finished is lost.
## The rule is written in a facility document (hint_text), so it can be solved without guessing.

signal breakers_changed

@export var pattern: Array[bool] = [true, false, true, true]

var breakers: Array[bool] = [false, false, false, false]


func _init() -> void:
	puzzle_id = &"lab_power"
	steps = [&"pattern", &"engage"]
	ordered = true


func input(id: StringName) -> void:
	var s := String(id)
	if s.begins_with("breaker_"):
		toggle(int(s.substr(8)))
	elif id == &"lever":
		engage()


func toggle(index: int) -> bool:
	if is_step_done(&"pattern") or index < 0 or index >= breakers.size():
		return false  # locked in once correct
	breakers[index] = not breakers[index]
	breakers_changed.emit()
	if breakers == pattern:
		complete_step(&"pattern")
	return true


func engage() -> bool:
	if is_completed():
		return false
	if not is_step_done(&"pattern"):
		fail(&"engage", "pattern_mismatch")
		return false
	return complete_step(&"engage")


func reset_breakers() -> void:
	for i in breakers.size():
		breakers[i] = false
	breakers_changed.emit()


func _reset_current(_step: StringName) -> void:
	if not is_step_done(&"pattern"):
		reset_breakers()


func _after_restore() -> void:
	if is_step_done(&"pattern"):
		breakers = pattern.duplicate()
		breakers_changed.emit()


func display_text() -> String:
	var parts: PackedStringArray = []
	for i in pattern.size():
		parts.append("%d:%s" % [i + 1, "ON" if pattern[i] else "OFF"])
	return "LAB POWER  " + "  ".join(parts)


func hint_text() -> String:
	return "Maintenance note: the lab breakers must match the pattern on the wall display, then pull the main lever. A wrong pull trips them all off, nothing is lost."
