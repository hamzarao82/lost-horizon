class_name DialoguePlayer
extends Node
## Plays a DialogueSequence line by line through the EXISTING caption path (QuestManager.say), with the
## speaker name as a prefix. It never clears other captions. Pressing "interact" while a sequence runs
## stops the REST of it (the line on screen finishes by itself). Played-once state is the WorldState
## flag `dlg_<id>` (underscore only, at most 48 characters).

signal line_started(speaker: String, text: String)
signal finished(skipped: bool)

const DIR: String = "res://resources/story/dialogue/"
const FLAG_PREFIX: String = "dlg_"
const GAP: float = 0.35
const SKIP_ACTION: StringName = &"interact"

var sequence: DialogueSequence
var lines_emitted: Array[String] = []
var _index: int = 0
var _wait: float = 0.0
var _running: bool = false


static func flag_for(sequence_id: StringName) -> StringName:
	return StringName(FLAG_PREFIX + String(sequence_id))


static func has_played(sequence_id: StringName) -> bool:
	var world := _node("WorldState")
	return world != null and world.has_flag(flag_for(sequence_id))


static func load_sequence(sequence_id: StringName) -> DialogueSequence:
	var path := DIR + String(sequence_id) + ".tres"
	return load(path) as DialogueSequence if ResourceLoader.exists(path) else null


## Starts a sequence by id. Returns the player node, or null when it does not exist or was already played.
static func play(sequence_id: StringName) -> DialoguePlayer:
	var loop := Engine.get_main_loop() as SceneTree
	var seq := load_sequence(sequence_id)
	if loop == null or seq == null or seq.lines.is_empty():
		return null
	if seq.once and has_played(sequence_id):
		return null
	var world := _node("WorldState")
	if seq.once and world != null:
		world.set_flag(flag_for(sequence_id), true)
	var player := DialoguePlayer.new()
	loop.root.add_child(player)
	player.start(seq)
	return player


func start(seq: DialogueSequence) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	sequence = seq
	_index = 0
	_running = true
	_emit_next()


func is_running() -> bool:
	return _running


## Stops the rest of the sequence.
func skip() -> void:
	if _running:
		_finish(true)


func _process(delta: float) -> void:
	if not _running:
		return
	_wait -= delta
	if _wait <= 0.0:
		_emit_next()


func _unhandled_input(event: InputEvent) -> void:
	if _running and InputMap.has_action(SKIP_ACTION) and event.is_action_pressed(SKIP_ACTION) and not event.is_echo():
		skip()


func _emit_next() -> void:
	if sequence == null or _index >= sequence.lines.size():
		_finish(false)
		return
	var line := sequence.lines[_index]
	_index += 1
	var text := ("%s: %s" % [line.speaker, line.text]) if line.speaker != "" else line.text
	lines_emitted.append(text)
	var quests := _node("QuestManager")
	if quests != null and quests.has_method("say"):
		quests.say(text, line.seconds)
	if line.cue != &"":
		var audio := _node("AudioManager")
		if audio != null and audio.has_method("play"):
			audio.play(line.cue)
	line_started.emit(line.speaker, line.text)
	_wait = maxf(line.seconds, 0.5) + GAP


func _finish(skipped: bool) -> void:
	_running = false
	finished.emit(skipped)
	queue_free()


static func _node(name: String) -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null(name) if loop else null
