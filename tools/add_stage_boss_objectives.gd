extends SceneTree
## One-off, re-runnable: adds the stage boss steps to the missions and one short "road" quest per stage.
## godot --headless --path . -s tools/add_stage_boss_objectives.gd
## Why a separate road quest and not a last step of mission 3: finishing mission 3 is what unlocks the next
## region, and arriving there needs the unlock, so the arrival step cannot be inside mission 3.

## quest path, objective id (= flag), text, insert index
const BOSS_STEPS: Array = [
	["res://resources/quests/dead_coast/dc_silent_checkpoint.tres", "dead_coast_boss_1_defeated", "Defeat the Harbor Commander", 6],
	["res://resources/quests/dead_coast/dc_lost_cargo.tres", "dead_coast_boss_2_defeated", "Defeat the Cove Boss who guards the cargo", 4],
	["res://resources/quests/blackwood/into_the_blackwood.tres", "blackwood_boss_1_defeated", "Defeat the Patrol Chief at the abandoned camp", 5],
	["res://resources/quests/blackwood/experimental_site.tres", "blackwood_boss_2_defeated", "Defeat the Site Overseer", 6],
	["res://resources/quests/research_complex/rc_project_black_site.tres", "research_complex_boss_2_defeated", "Defeat the Facility Commander", 3],
]

## new quest path, id, title, description, prerequisite quest path, arrival flag, objective text, caption
const ROAD_QUESTS: Array = [
	["res://resources/quests/dead_coast/dc_road_to_blackwood.tres", "dc_road_to_blackwood", "The Road to Blackwood",
		"The shipment's trail runs inland. The gate at the end of the coast road is open.",
		"res://resources/quests/dead_coast/dc_lost_cargo.tres", "blackwood_arrived", "Take the road to Blackwood",
		"The road to Blackwood is open."],
	["res://resources/quests/blackwood/bw_road_to_research_complex.tres", "bw_road_to_research_complex", "The Road to the Research Complex",
		"The testing site's access code opens the facility road.",
		"res://resources/quests/blackwood/experimental_site.tres", "research_complex_arrived", "Take the road to the Research Complex",
		"The road to the Research Complex is open."],
	["res://resources/quests/research_complex/rc_road_to_iron_fortress.tres", "rc_road_to_iron_fortress", "The Road to the Iron Fortress",
		"The recovered data ends at one place. The underground road leads there.",
		"res://resources/quests/research_complex/rc_project_black_site.tres", "iron_fortress_arrived", "Take the underground road to the Iron Fortress",
		"The underground road is open."],
]


func _flag_objective(flag: String, text: String) -> ObjectiveData:
	var objective := ObjectiveData.new()
	objective.id = StringName(flag)
	objective.text = text
	objective.type = ObjectiveData.Type.FLAG
	objective.targets = PackedStringArray([flag])
	return objective


func _initialize() -> void:
	for entry in BOSS_STEPS:
		var path := String(entry[0])
		var quest := load(path) as QuestData
		var flag := String(entry[1])
		var have := false
		for objective in quest.objectives:
			if objective.id == StringName(flag):
				have = true
		if have:
			print("SKIP ", path, " (already has ", flag, ")")
			continue
		quest.objectives.insert(mini(int(entry[3]), quest.objectives.size()), _flag_objective(flag, String(entry[2])))
		var errors := quest.validate()
		if not errors.is_empty():
			print("INVALID ", path, ": ", errors)
			continue
		print("ADDED ", flag, " to ", path, " save=", ResourceSaver.save(quest, path))
	for entry in ROAD_QUESTS:
		var path := String(entry[0])
		var previous_path := String(entry[4])
		var previous := load(previous_path) as QuestData
		var quest := QuestData.new()
		if ResourceLoader.exists(path):
			quest = load(path) as QuestData
		quest.id = StringName(entry[1])
		quest.title = String(entry[2])
		quest.description = String(entry[3])
		quest.prerequisites = PackedStringArray([String(previous.id)])
		quest.objectives = [_flag_objective(String(entry[5]), String(entry[6]))]
		quest.start_captions = PackedStringArray([String(entry[7])])
		quest.caption_seconds = 4.0
		var errors := quest.validate()
		if not errors.is_empty():
			print("INVALID ", path, ": ", errors)
			continue
		print("ROAD ", quest.id, " save=", ResourceSaver.save(quest, path))
		if previous.next_quest != quest.id:
			previous.next_quest = quest.id
			print("LINKED ", previous.id, " -> ", quest.id, " save=", ResourceSaver.save(previous, previous_path))
	quit()
