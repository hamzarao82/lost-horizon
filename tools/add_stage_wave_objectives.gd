extends SceneTree
## One-off: adds a required FLAG objective `<region>_waves_cleared` to the middle mission of each later stage.
## godot --headless --path . -s tools/add_stage_wave_objectives.gd
## Safe to re-run: a quest that already has the objective is left alone.

const PLAN: Array = [
	["res://resources/quests/dead_coast/dc_silent_checkpoint.tres", &"dead_coast", "Hold the line against the coastal patrols", 2],
	["res://resources/quests/blackwood/ghost_frequency.tres", &"blackwood", "Hold the trail against the jungle patrol", 2],
	["res://resources/quests/research_complex/rc_silent_records.tres", &"research_complex", "Hold the wing against facility security", 2],
	["res://resources/quests/iron_fortress/if_inside_the_walls.tres", &"iron_fortress", "Hold the barracks against the garrison", 2],
]


func _initialize() -> void:
	for entry in PLAN:
		var quest := load(String(entry[0])) as QuestData
		var region: StringName = entry[1]
		var flag := "%s_waves_cleared" % String(region)
		var have := false
		for objective in quest.objectives:
			if objective.id == StringName(flag):
				have = true
		if have:
			print("SKIP ", entry[0], " (already has ", flag, ")")
			continue
		var objective := ObjectiveData.new()
		objective.id = StringName(flag)
		objective.text = String(entry[2])
		objective.type = ObjectiveData.Type.FLAG
		objective.targets = PackedStringArray([flag])
		quest.objectives.insert(mini(int(entry[3]), quest.objectives.size()), objective)
		var errors := quest.validate()
		if not errors.is_empty():
			print("INVALID ", entry[0], ": ", errors)
			continue
		var saved := ResourceSaver.save(quest, String(entry[0]))
		print("ADDED ", flag, " to ", entry[0], " save=", saved)
	quit()
