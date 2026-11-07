extends SceneTree
## Dialogue sequences: order, speaker prefix, played-once through a real WorldState round trip, skip,
## and that other captions are never touched. godot --headless --path . -s tests/dialogue_check.gd

var _failures: int = 0
var _checks: int = 0
var _captions: Array[String] = []


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _initialize() -> void:
	_run.call_deferred()


func _record(text: String, _seconds: float) -> void:
	_captions.append(text)


func _run() -> void:
	var world := root.get_node("WorldState")
	var quests := root.get_node("QuestManager")
	quests.caption_requested.connect(_record)
	world.reset()
	var ids: Array[StringName] = [&"radio_dead_coast_handoff", &"terminal_command_post", &"optional_supply_chatter"]
	for id in ids:
		var seq := DialoguePlayer.load_sequence(id)
		_check(seq != null and seq.lines.size() >= 2, "%s loads with lines" % id)
		_check(String(DialoguePlayer.flag_for(id)).length() <= 48, "%s played flag fits the 48 character limit" % id)
		var flag := String(DialoguePlayer.flag_for(id))
		var plain := true
		for c in flag:
			if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
				plain = false
		_check(plain, "%s played flag uses only a-z, 0-9 and underscore" % id)
	_check(DialoguePlayer.load_sequence(&"nope") == null and DialoguePlayer.play(&"nope") == null, "an unknown sequence is refused")

	# other captions are not touched
	quests.say("Unrelated caption", 2.0)
	var player := DialoguePlayer.play(&"radio_dead_coast_handoff")
	_check(player != null and player.is_running(), "a sequence starts")
	_check(_captions.size() == 2 and _captions[0] == "Unrelated caption", "the first line is queued after, not instead of, an existing caption")
	_check(_captions[1] == "Radio: The signal keeps repeating from the south, past the beach gate.", "the first line has the speaker prefix (%s)" % _captions[1])
	player._wait = 0.0
	await process_frame
	await process_frame
	player._wait = 0.0
	await process_frame
	await process_frame
	_check(player.lines_emitted.size() == 3, "all three lines were emitted in order (%d)" % player.lines_emitted.size())
	_check(player.lines_emitted[1].begins_with("You: ") and player.lines_emitted[2].begins_with("Radio: "), "speakers follow the script")
	player._wait = 0.0
	await process_frame
	await process_frame
	_check(not is_instance_valid(player) or not player.is_running(), "the sequence finishes after the last line")
	_check(_captions.size() == 4, "exactly one caption per line and nothing else (%d)" % _captions.size())

	# played once, through a real WorldState round trip
	_check(DialoguePlayer.has_played(&"radio_dead_coast_handoff"), "the played flag is set")
	var saved: Dictionary = world.to_dict()
	world.reset()
	_check(not DialoguePlayer.has_played(&"radio_dead_coast_handoff"), "a reset clears it")
	world.from_dict(saved)
	_check(DialoguePlayer.has_played(&"radio_dead_coast_handoff"), "the played flag survives a real WorldState save and load")
	var before := _captions.size()
	_check(DialoguePlayer.play(&"radio_dead_coast_handoff") == null and _captions.size() == before, "a played sequence does not play again")

	# skip stops the rest, with the input action too
	var skipper := DialoguePlayer.play(&"terminal_command_post")
	_check(skipper != null and skipper.lines_emitted.size() == 1, "a second sequence starts with its first line")
	var ev := InputEventAction.new()
	ev.action = &"interact"
	ev.pressed = true
	var captions_before_skip := _captions.size()
	skipper._unhandled_input(ev)
	_check(not is_instance_valid(skipper) or not skipper.is_running(), "pressing interact stops the rest of the sequence")
	await process_frame
	await process_frame
	_check(_captions.size() == captions_before_skip, "no further caption is emitted after the skip")
	var direct := DialoguePlayer.play(&"optional_supply_chatter")
	direct.skip()
	_check(not is_instance_valid(direct) or not direct.is_running(), "skip() also stops a sequence")
	world.reset()
	print("dialogue_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
