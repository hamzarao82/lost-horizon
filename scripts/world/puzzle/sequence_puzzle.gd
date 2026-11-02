class_name SequencePuzzle
extends Node
## Ordered-switch puzzle (Restore Outpost Power). Power switches call try_press(id).
## Correct next press advances; a wrong press resets the sequence (never an error); pressing a switch
## that is already correctly set is ignored. Progress lives in WorldState flags, so it survives a death
## restart and is saved with the rest of the world state. See docs/QUESTS.md.

signal step_advanced(step: int, total: int)
signal wrong_order
signal solved
## The panel has not been inspected yet (or the puzzle is otherwise not ready): hint text for the HUD.
signal hint(text: String)

const DEFAULT_DATA: String = "res://resources/puzzles/power_sequence.tres"

@export var data: SequenceData

var _fallback_flags: Dictionary = {}  # used only if the WorldState autoload is missing (tests, tools)


## Finds the puzzle in the scene tree (group "sequence_puzzle") or creates one under `parent`.
static func ensure(parent: Node) -> SequencePuzzle:
	var tree := parent.get_tree()
	var existing := tree.get_first_node_in_group("sequence_puzzle") as SequencePuzzle
	if existing != null:
		return existing
	var puzzle := SequencePuzzle.new()
	puzzle.name = "SequencePuzzle"
	parent.add_child(puzzle)
	return puzzle


func _ready() -> void:
	add_to_group("sequence_puzzle")
	if data == null:
		data = load(DEFAULT_DATA) as SequenceData


## Number of correct presses so far.
func current_step() -> int:
	if data == null:
		return 0
	var count := 0
	for i in data.order.size():
		if _flag(_step_flag(i + 1)):
			count += 1
		else:
			break
	return count


func is_solved() -> bool:
	return data != null and data.solved_flag != &"" and _flag(data.solved_flag)


func total_steps() -> int:
	return data.order.size() if data else 0


## Returns true only when the press was the correct next switch.
func try_press(id: StringName) -> bool:
	if data == null or data.order.is_empty() or is_solved():
		return false
	if data.requires_flag != &"" and not _flag(data.requires_flag):
		hint.emit(data.hint_not_ready)
		return false
	var step := current_step()
	if String(id) == data.order[step]:
		_set_flag(_step_flag(step + 1), true)
		step += 1
		step_advanced.emit(step, data.order.size())
		_sfx(&"equip")
		if step >= data.order.size():
			if data.solved_flag != &"":
				_set_flag(data.solved_flag, true)
			solved.emit()
			_sfx(&"wave_start")
		return true
	# A switch that was already set correctly earlier in the sequence is not a mistake.
	var earlier := data.order.find(String(id))
	if earlier != -1 and earlier < step:
		return false
	# Anything else (wrong switch, unknown id) resets the sequence, without errors.
	reset_progress()
	wrong_order.emit()
	_sfx(&"hurt")
	return false


func reset_progress() -> void:
	if data == null:
		return
	for i in data.order.size():
		_set_flag(_step_flag(i + 1), false)


func _step_flag(number: int) -> StringName:
	return StringName("%s%d" % [data.step_flag_prefix, number])


func _world() -> Node:
	return get_node_or_null("/root/WorldState")


func _flag(id: StringName) -> bool:
	var world := _world()
	if world != null and world.has_method("has_flag"):
		return world.has_flag(id)
	return _fallback_flags.get(id, false)


func _set_flag(id: StringName, value: bool) -> void:
	var world := _world()
	if world != null and world.has_method("set_flag"):
		world.set_flag(id, value)
	else:
		_fallback_flags[id] = value


func _sfx(sfx_name: StringName) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.call("play", sfx_name)
