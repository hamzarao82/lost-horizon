extends SceneTree
## The opening ending: due only after the payment is recovered, plays once, can be skipped without leaving
## pause state behind, and is NOT the campaign ending.
##   godot --headless --path . -s tests/opening_ending_check.gd

var _checks: int = 0
var _failures: int = 0
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
	_world = root.get_node("WorldState")
	_world.reset()
	await _frames(2)

	# --- due only after the recovery, once ---------------------------------------------------------
	_check(not OpeningEnding.should_play(_world), "not due on a fresh game")
	_world.set_flag(&"payment_recovered", true)
	_check(OpeningEnding.should_play(_world), "due once the payment is recovered")
	_check(not OpeningEnding.should_play(null), "never due without a world")
	_check(OpeningEnding.trigger(self, _world) == null, "a headless run records the arc without playing (nobody to watch)")
	_check(_world.has_flag(&"opening_arc_complete"), "trigger() set the arc flag first")
	_check(not OpeningEnding.should_play(_world), "so it is never due again, not on Continue or a load either")
	_check(OpeningEnding.trigger(self, _world) == null, "and a second trigger does nothing")
	var campaign_flag := String(CampaignEnding.FLAG_COMPLETE)
	_check(not _world.has_flag(StringName(campaign_flag)), "the campaign ending's flag was not touched: this is not the campaign ending")

	# --- timeline -----------------------------------------------------------------------------------
	var total := OpeningEnding.total_duration()
	_check(total > 6.0 and total < 20.0, "it is short (%.1f s)" % total)
	_check(OpeningEnding.LINES.size() == 2 and OpeningEnding.LINES[0].find("he came for") > 0, "two plain lines, the first about what he came for")

	# --- full play: finished exactly once, not skipped ---------------------------------------------
	var record := [0, null]
	var ending := OpeningEnding.new()
	ending.finished.connect(func(skipped: bool) -> void:
		record[0] += 1
		record[1] = skipped)
	root.add_child(ending)
	await _frames(1)
	_check(paused, "the tree is paused while it plays")
	var seen_line := false
	var t := 0.0
	while t < total + 1.0 and not ending.is_done:
		ending.advance(0.25)
		t += 0.25
		if is_instance_valid(ending) and ending._label != null and ending._label.text != "":
			seen_line = true
	await _frames(2)
	_check(record[0] == 1 and record[1] == false, "finished fired exactly once, not skipped")
	_check(seen_line, "a line was shown on the way")
	_check(not paused, "the pause is restored")

	# --- skip, twice ---------------------------------------------------------------------------------
	var record2 := [0, null]
	var second := OpeningEnding.new()
	second.finished.connect(func(skipped: bool) -> void:
		record2[0] += 1
		record2[1] = skipped)
	root.add_child(second)
	await _frames(1)
	second.advance(1.0)
	second.skip()
	second.skip()
	await _frames(2)
	_check(record2[0] == 1 and record2[1] == true, "skip finishes once, flagged as skipped, even when pressed twice")
	_check(not paused, "skipping restores the pause")

	# --- freed early: the pause is still restored -------------------------------------------------
	var third := OpeningEnding.new()
	root.add_child(third)
	await _frames(1)
	_check(paused, "paused again for a third run")
	third.free()
	await _frames(1)
	_check(not paused, "freeing it early restores the pause")

	# --- a paused game stays paused ---------------------------------------------------------------
	paused = true
	var fourth := OpeningEnding.new()
	root.add_child(fourth)
	await _frames(1)
	fourth.skip()
	await _frames(2)
	_check(paused, "if the game was already paused it stays paused")
	paused = false

	_world.reset()
	print("opening_ending_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
