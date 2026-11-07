extends SceneTree
## Writes the example dialogue sequences to resources/story/dialogue/. Original text, no new lore beyond
## what the existing documents already say. Run: godot --headless --path . -s tools/gen_dialogue.gd

const OUT: String = "res://resources/story/dialogue/"
const DATA: Dictionary = {
	"radio_dead_coast_handoff": [
		["Radio", "The signal keeps repeating from the south, past the beach gate.", 4.0, ""],
		["You", "Then that is where it starts. I am going.", 3.0, ""],
		["Radio", "Copy. Stay off the open road, and keep the channel clear.", 4.0, ""],
	],
	"terminal_command_post": [
		["Terminal", "Session restored. The last operator never closed the channel.", 4.0, ""],
		["You", "Whoever sat here left in a hurry.", 3.0, ""],
		["Radio", "Take what the screen gives you. Do not stay in one place.", 4.0, ""],
	],
	"optional_supply_chatter": [
		["Radio", "If you found anything useful out there, keep it close.", 3.5, ""],
		["You", "Understood.", 2.0, ""],
	],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for id in DATA:
		var seq := DialogueSequence.new()
		seq.id = StringName(id)
		seq.once = true
		for row in DATA[id]:
			var line := DialogueLine.new()
			line.speaker = row[0]
			line.text = row[1]
			line.seconds = row[2]
			line.cue = StringName(row[3])
			seq.lines.append(line)
		var err := ResourceSaver.save(seq, OUT + "%s.tres" % id)
		print("DIALOGUE %s -> %s" % [id, "ok" if err == OK else "FAILED %d" % err])
	quit()
