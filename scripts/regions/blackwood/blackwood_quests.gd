class_name BlackwoodQuests
extends RefCounted
## Registers the three Blackwood quests with QuestManager at runtime (QuestManager only loads its own
## fixed list, and this region must not edit it) and starts the chain once the player enters.

const PATHS: Array[String] = [
	"res://resources/quests/blackwood/into_the_blackwood.tres",
	"res://resources/quests/blackwood/ghost_frequency.tres",
	"res://resources/quests/blackwood/experimental_site.tres",
]
const FIRST: StringName = &"into_the_blackwood"
## Quest XP a step above the 200 default (Progression reads this table; first_signal pays 400).
const QUEST_XP: Dictionary = {&"into_the_blackwood": 260, &"ghost_frequency": 320, &"experimental_site": 420}


## Adds the quests to `manager` (the QuestManager node). Returns how many are registered.
static func register(manager: Node, progression: Node = null) -> int:
	if manager == null:
		return 0
	var count := 0
	for path in PATHS:
		var quest := load(path) as QuestData
		if quest == null or not quest.validate().is_empty():
			push_warning("BlackwoodQuests: %s is missing or invalid" % path)
			continue
		manager.quests[quest.id] = quest
		count += 1
	if progression != null and progression.get("config") != null:
		for id: StringName in QUEST_XP:
			progression.config.quest_xp[id] = QUEST_XP[id]
	return count


## Starts the first quest if nothing of the chain is active or done (safe to call on every entry).
static func start_chain(manager: Node) -> bool:
	if manager == null or manager.is_active(FIRST) or manager.is_completed(FIRST):
		return false
	return manager.start_quest(FIRST)
