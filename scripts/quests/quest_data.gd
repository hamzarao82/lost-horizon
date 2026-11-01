class_name QuestData
extends Resource
## A quest definition. Pure data: prerequisites, objectives, rewards and the story lines to show.

const ITEM_DIR: String = "res://resources/items/"

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


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("quest has no id")
	if title.strip_edges().is_empty():
		errors.append("%s: no title" % id)
	if objectives.is_empty():
		errors.append("%s: no objectives" % id)
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
