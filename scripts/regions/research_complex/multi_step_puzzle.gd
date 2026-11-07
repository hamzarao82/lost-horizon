class_name MultiStepPuzzle
extends Node3D
## Base for facility puzzles made of named steps (ordered or any order).
##
## Rules that make it impossible to soft-lock:
##  - a completed step is saved as a flag (`<region>_<puzzle>_<step>`) and is never undone;
##  - a wrong input only resets the CURRENT step's loose progress (`_reset_current`), never a finished step;
##  - restore_state() rebuilds everything from the saved flags (and an optional captured dictionary), and in
##    an ordered puzzle a finished later step implies the earlier ones, so a damaged save cannot strand it.

signal step_completed(step: StringName)
signal step_failed(step: StringName, reason: String)
signal completed

@export var puzzle_id: StringName = &"puzzle"
@export var region_id: StringName = FacilityIds.REGION
@export var steps: Array[StringName] = []
@export var ordered: bool = true

var _done: Dictionary = {}
var _completed: bool = false


func _ready() -> void:
	restore_state()


func step_flag(step: StringName) -> StringName:
	return RegionFlags.key(region_id, StringName("%s_%s" % [String(puzzle_id), String(step)]))


func done_flag() -> StringName:
	return RegionFlags.key(region_id, StringName("%s_done" % String(puzzle_id)))


## Every flag this puzzle writes (tests check they are all saveable).
func all_flag_ids() -> Array[StringName]:
	var out: Array[StringName] = [done_flag()]
	for step in steps:
		out.append(step_flag(step))
	return out


func is_step_done(step: StringName) -> bool:
	return _done.has(step)


func is_completed() -> bool:
	return _completed


## First unfinished step in order, or &"" when everything is done.
func current_step() -> StringName:
	for step in steps:
		if not _done.has(step):
			return step
	return &""


func complete_step(step: StringName) -> bool:
	if _completed or not steps.has(step) or _done.has(step):
		return false
	if ordered and step != current_step():
		fail(step, "out_of_order")
		return false
	_done[step] = true
	FacilityIds.set_flag(step_flag(step))
	step_completed.emit(step)
	if _done.size() == steps.size():
		_finish()
	return true


## A wrong input: resets only the loose progress of the current step and reports why.
func fail(step: StringName, reason: String) -> void:
	if not _completed and not _done.has(step):
		_reset_current(step)
	step_failed.emit(step, reason)


func _finish() -> void:
	_completed = true
	FacilityIds.set_flag(done_flag())
	completed.emit()


func capture_state() -> Dictionary:
	var done: Array = []
	for step in steps:
		if _done.has(step):
			done.append(String(step))
	return {"done": done, "completed": _completed}


## Rebuilds from saved flags; `state` (from capture_state) is optional extra evidence.
func restore_state(state: Dictionary = {}) -> void:
	_done.clear()
	var raw: Variant = state.get("done", [])
	var listed: Array = raw if raw is Array else []
	var all_done := FacilityIds.has_flag(done_flag()) or bool(state.get("completed", false))
	var last := -1
	for i in steps.size():
		var step := steps[i]
		if all_done or FacilityIds.has_flag(step_flag(step)) or listed.has(String(step)):
			last = i
	for i in steps.size():
		var step := steps[i]
		var marked := all_done or FacilityIds.has_flag(step_flag(step)) or listed.has(String(step))
		if marked or (ordered and i <= last):
			_done[step] = true
	_completed = not steps.is_empty() and _done.size() == steps.size()
	if _completed:
		FacilityIds.set_flag(done_flag())
	_after_restore()


## Loose progress of one unfinished step goes back to its start (override).
func _reset_current(_step: StringName) -> void:
	pass


func _after_restore() -> void:
	pass
