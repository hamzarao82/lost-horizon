extends SceneTree
## Ordered power puzzle (Restore Outpost Power):
##   godot --headless --path . -s tests/puzzle_check.gd

var _failures: int = 0
var _checks: int = 0
var _world: Node


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	_world = root.get_node_or_null("WorldState")
	_check(_world != null, "the WorldState autoload exists")
	if _world == null:
		quit(1)
		return
	_test_data()
	await _test_correct_order()
	await _test_wrong_order()
	await _test_repeats()
	await _test_requires_inspection()
	await _test_persistence()
	await _test_ensure_and_resilience()
	_world.reset()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _make_puzzle() -> SequencePuzzle:
	_world.reset()
	var puzzle := SequencePuzzle.new()
	root.add_child(puzzle)
	await _frames(1)
	return puzzle


func _test_data() -> void:
	print("Sequence data")
	var data := load("res://resources/puzzles/power_sequence.tres") as SequenceData
	_check(data != null and data.order.size() == 3, "the power sequence has three switches")
	_check(data.order == PackedStringArray(["power_switch_b", "power_switch_a", "power_switch_c"]), "the order is B, A, C")
	_check(data.requires_flag == &"panel_inspected" and data.solved_flag == &"comms_power_on", "it needs the inspected panel and sets comms_power_on")


func _test_correct_order() -> void:
	print("Correct order")
	var puzzle := await _make_puzzle()
	_world.set_flag(&"panel_inspected", true)
	var steps: Array[int] = []
	var solved := [0]
	puzzle.step_advanced.connect(func(step: int, _total: int) -> void: steps.append(step))
	puzzle.solved.connect(func() -> void: solved[0] += 1)
	_check(puzzle.try_press(&"power_switch_b") and puzzle.current_step() == 1, "the first correct switch advances to step 1")
	_check(puzzle.try_press(&"power_switch_a") and puzzle.current_step() == 2, "the second correct switch advances to step 2")
	_check(not _world.has_flag(&"comms_power_on"), "power is not on before the last switch")
	_check(puzzle.try_press(&"power_switch_c") and puzzle.is_solved(), "the third correct switch solves it")
	_check(_world.has_flag(&"comms_power_on") and solved[0] == 1, "comms_power_on is set and solved is emitted once")
	_check(steps == [1, 2, 3], "step_advanced reported 1, 2, 3")
	_check(not puzzle.try_press(&"power_switch_b") and solved[0] == 1, "a solved puzzle ignores further presses")
	puzzle.queue_free()


func _test_wrong_order() -> void:
	print("Wrong order")
	var puzzle := await _make_puzzle()
	_world.set_flag(&"panel_inspected", true)
	var wrong := [0]
	puzzle.wrong_order.connect(func() -> void: wrong[0] += 1)
	puzzle.try_press(&"power_switch_b")
	_check(not puzzle.try_press(&"power_switch_c"), "pressing C before A is rejected")
	_check(puzzle.current_step() == 0 and wrong[0] == 1, "a wrong press resets progress and emits wrong_order")
	_check(not puzzle.try_press(&"not_a_switch") and wrong[0] == 2, "an unknown id is a wrong press, never an error")
	_check(puzzle.try_press(&"power_switch_b") and puzzle.try_press(&"power_switch_a") and puzzle.try_press(&"power_switch_c"), "the puzzle can be solved after mistakes")
	_check(_world.has_flag(&"comms_power_on"), "and it still sets power on")
	puzzle.queue_free()


func _test_repeats() -> void:
	print("Repeated presses")
	var puzzle := await _make_puzzle()
	_world.set_flag(&"panel_inspected", true)
	var wrong := [0]
	puzzle.wrong_order.connect(func() -> void: wrong[0] += 1)
	puzzle.try_press(&"power_switch_b")
	puzzle.try_press(&"power_switch_a")
	_check(not puzzle.try_press(&"power_switch_b") and puzzle.current_step() == 2 and wrong[0] == 0, "pressing a switch that is already set is ignored, not a mistake")
	_check(not puzzle.try_press(&"power_switch_a") and puzzle.current_step() == 2, "repeating the latest switch is ignored too")
	puzzle.queue_free()


func _test_requires_inspection() -> void:
	print("Needs the inspected panel")
	var puzzle := await _make_puzzle()
	var hints: Array[String] = []
	puzzle.hint.connect(func(text: String) -> void: hints.append(text))
	_check(not puzzle.try_press(&"power_switch_b") and puzzle.current_step() == 0, "presses do nothing before the panel is inspected")
	_check(hints.size() == 1 and hints[0].contains("panel"), "a hint explains why")
	_world.set_flag(&"panel_inspected", true)
	_check(puzzle.try_press(&"power_switch_b") and puzzle.current_step() == 1, "after the inspection the same press counts")
	puzzle.queue_free()


func _test_persistence() -> void:
	print("Persistence")
	var puzzle := await _make_puzzle()
	_world.set_flag(&"panel_inspected", true)
	puzzle.try_press(&"power_switch_b")
	puzzle.try_press(&"power_switch_a")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.to_dict()))  # what a save file does
	puzzle.queue_free()
	await _frames(2)
	# Simulated scene reload: a brand-new puzzle node, the world state restored from the save.
	_world.reset()
	_world.from_dict(saved)
	var again := SequencePuzzle.new()
	root.add_child(again)
	await _frames(1)
	_check(again.current_step() == 2, "progress survives a reload (step 2 of 3)")
	_check(again.try_press(&"power_switch_c") and again.is_solved() and _world.has_flag(&"comms_power_on"), "the last switch then finishes the puzzle")
	var solved_saved: Dictionary = JSON.parse_string(JSON.stringify(_world.to_dict()))
	_world.reset()
	_world.from_dict(solved_saved)
	_check(again.is_solved(), "a solved puzzle stays solved after a save and load")
	again.queue_free()


func _test_ensure_and_resilience() -> void:
	print("ensure() and resilience")
	_world.reset()
	await _frames(2)  # puzzles queued for deletion by earlier tests must be gone before the group lookup
	var host := Node.new()
	root.add_child(host)
	var first := SequencePuzzle.ensure(host)
	await _frames(1)
	var second := SequencePuzzle.ensure(host)
	_check(first != null and first == second and first.is_in_group("sequence_puzzle"), "ensure() creates the puzzle once and finds it again")
	var empty := SequencePuzzle.new()
	empty.data = null
	root.add_child(empty)
	_check(not empty.try_press(&"power_switch_b") and empty.current_step() == 0 and not empty.is_solved(), "a puzzle with no data is harmless")
	var short := SequenceData.new()
	short.order = PackedStringArray([])
	var odd := SequencePuzzle.new()
	odd.data = short
	root.add_child(odd)
	_check(not odd.try_press(&"anything"), "an empty sequence never solves or crashes")
	host.queue_free()
	empty.queue_free()
	odd.queue_free()
	await _frames(2)
