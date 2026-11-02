class_name QuestData
extends Resource
## A quest definition. Pure data: prerequisites, objectives, rewards and the story lines to show.

const ITEM_DIR: String = "res://resources/items/"

enum Category { MAIN, SIDE, EXPLORATION }

@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var prerequisites: PackedStringArray
@export var objectives: Array[ObjectiveData] = []
## Item ids from resources/items (repeat an id for a count). Granted exactly once on completion.
@export var rewards: PackedStringArray
@export var reward_text: String
## Started automatically when this quest completes (if its own prerequisites are met).
@export var next_quest: StringName
@export var start_captions: PackedStringArray
@export var complete_captions: PackedStringArray
@export var caption_seconds: float = 4.0
@export var category: Category = Category.MAIN
## Short pointer for the player ("Outer Perimeter"), shown by the HUD when the quest starts.
@export var location_hint: String
## Completing this quest shows the MISSION COMPLETE banner instead of QUEST COMPLETE.
@export var show_mission_banner: bool = false


## Objectives that have to be done for the quest to complete (optional ones are excluded).
func required_indices() -> Array[int]:
	var result: Array[int] = []
	for index in objectives.size():
		if objectives[index] != null and not objectives[index].optional:
			result.append(index)
	return result


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("quest has no id")
	if title.strip_edges().is_empty():
		errors.append("%s: no title" % id)
	if objectives.is_empty():
		errors.append("%s: no objectives" % id)
	elif required_indices().is_empty():
		errors.append("%s: every objective is optional" % id)
	var seen_ids: Array[StringName] = []
	for objective in objectives:
		if objective == null:
			errors.append("%s: null objective" % id)
			continue
		errors.append_array(objective.validate())
		if seen_ids.has(objective.id):
			errors.append("%s: duplicate objective id %s" % [id, objective.id])
		seen_ids.append(objective.id)
	for prerequisite in prerequisites:
		if prerequisite == String(id):
			errors.append("%s: a quest cannot require itself" % id)
	for item_id in rewards:
		if not ResourceLoader.exists(ITEM_DIR + item_id + ".tres"):
			errors.append("%s: reward item '%s' does not exist" % [id, item_id])
	return errors
