class_name IronFortress
extends Node3D
## The Iron Fortress: the fifth and last region. A self-contained content builder (like the Research Complex):
## build() assembles six areas from modular sub-builders; the region framework reads `entry_points`,
## `exit_points`, `capture_state()` / `restore_state()`. It starts its own quest chain and ends the campaign:
## `campaign_complete` is set once, only after the Director is down and the last mission is finished.
## Every saved id is underscore-only and at most 48 characters (WorldState drops anything else on load).

const Z = preload("res://scripts/regions/iron_fortress/iron_fortress_zones.gd")
const REGION_ID: StringName = &"iron_fortress"
const FIRST_QUEST: StringName = &"if_last_stronghold"
const LAST_QUEST: StringName = &"if_black_site"
const COMPLETE_FLAG: StringName = &"iron_fortress_region_complete"
const CAMPAIGN_FLAG: StringName = &"campaign_complete"
const APPROACH_PASS: StringName = &"iron_fortress_approach_pass"
const CAPTAIN_DOWN: StringName = &"iron_fortress_captain_down"
const DIRECTOR_DOWN: StringName = &"iron_fortress_director_defeated"
const LOCKDOWN_DONE: StringName = &"iron_fortress_lockdown_done"
const CONTROL_OPEN: StringName = &"iron_fortress_control_open"
const CAPTAIN_REWARD: String = "res://resources/items/captain_insignia.tres"
const DIRECTOR_REWARD: String = "res://resources/items/director_signet.tres"
const COMPLETE_CAPTION: String = "The island answers to no one now. Campaign complete."

## world flag -> spawn ids that must all be cleared.
const GROUPS: Dictionary = {
	&"iron_fortress_approach_clear": ["if_app_1", "if_app_2", "if_app_3"],
	&"iron_fortress_perimeter_clear": ["if_per_1", "if_per_2", "if_per_elite"],
	&"iron_fortress_barracks_cleared": ["if_bar_elite_1", "if_bar_elite_2", "if_bar_heavy_1"],
	&"iron_fortress_command_cleared": ["if_cmd_elite", "if_cmd_commander"],
	&"iron_fortress_inner_cleared": ["if_inn_heavy_1", "if_inn_heavy_2", "if_inn_elite_1", "if_inn_elite_2"],
	&"iron_fortress_depot_cleared": ["if_depot_elite_1", "if_depot_elite_2"],
	&"iron_fortress_captain_down": ["if_captain"],
	&"iron_fortress_director_defeated": ["if_director"],
}
## spawn id -> unique reward the cleared enemy owes the player until it is picked up.
const REWARDS: Dictionary = {"if_captain": CAPTAIN_REWARD, "if_director": DIRECTOR_REWARD}

var entry_points: Dictionary = {}
var exit_points: Dictionary = {}
var parts: IronFortressParts
var kits: Dictionary = {}

var _built: bool = false
var _reward_given: Dictionary = {}


func _ready() -> void:
	set_meta(&"region_id", REGION_ID)
	set_meta(&"ambience_name", "research_complex")
	set_meta(&"environment_preset", "iron_fortress")
	if not _built:
		build()


func region_id() -> StringName:
	return REGION_ID


func build() -> void:
	if _built:
		return
	_built = true
	parts = IronFortressParts.new(self)
	kits["approach"] = IronFortressOuter.approach(self, parts)
	kits["perimeter"] = IronFortressOuter.perimeter(self, parts)
	kits["barracks"] = IronFortressOuter.barracks(self, parts)
	kits["command"] = IronFortressInner.command_center(self, parts)
	kits["inner"] = IronFortressInner.inner_fortress(self, parts)
	kits["control"] = IronFortressInner.control_facility(self, parts)
	_build_area_triggers()
	_build_entries_and_exits()
	_wire()
	_refresh_groups.call_deferred()


func location_at(pos: Vector3) -> String:
	return Z.location_at(pos)


## The walkable main route (door by door, with the gates opened) from the arrival to the transmission console.
static func main_path() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var z := 52.0
	while z >= -208.0:
		pts.append(Vector3(0.0, 0.1, z))
		z -= 5.0
	return pts


func _build_area_triggers() -> void:
	for area in Z.AREAS:
		var rect := Z.area_rect(area)
		parts.area_trigger(String(area["id"]), Vector3(0.0, 3.0, float(area["z"])), Vector3(rect.size.x, 16.0, rect.size.y))


func _build_entries_and_exits() -> void:
	entry_points = {
		"from_research_complex": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 51.0)),   # faces north (-z)
		"from_underground": Transform3D(Basis.IDENTITY, Vector3(3.0, 0.1, 50.0)),
	}
	exit_points = {
		"to_research_complex": {"position": Vector3(0.0, 0.0, 58.0), "region": "research_complex", "entry": "from_iron_fortress",
			"locked_flag": "", "locked_text": ""},
	}
	var exits := Node3D.new()
	exits.name = "Exits"
	add_child(exits)
	for id: String in exit_points:
		var marker := Marker3D.new()
		marker.name = id
		marker.position = (exit_points[id] as Dictionary)["position"]
		for key: String in ["region", "entry", "locked_flag", "locked_text"]:
			marker.set_meta(StringName(key), (exit_points[id] as Dictionary)[key])
		exits.add_child(marker)


# --- wiring -------------------------------------------------------------------------

func _wire() -> void:
	for id: String in parts.fspawns:
		(parts.fspawns[id] as FortressSpawn).cleared.connect(_refresh_groups)
	(parts.triggers["if_checkpoint_reach"] as MissionTrigger).fired.connect(func(_event: StringName) -> void: _set_flag(APPROACH_PASS))
	(parts.triggers["if_captain_hall"] as AreaTrigger).entered.connect(func(_id: StringName) -> void: release_captain())
	(parts.triggers["if_arena"] as AreaTrigger).entered.connect(func(_id: StringName) -> void: release_director())
	for puzzle_id: String in parts.puzzles:
		(parts.puzzles[puzzle_id] as MultiStepPuzzle).completed.connect(_refresh_groups)
	var world := get_node_or_null("/root/WorldState")
	if world != null and world.has_signal("flag_changed"):
		world.flag_changed.connect(func(_id: StringName, _value: bool) -> void: _refresh_groups())
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null and quests.has_signal("quest_completed"):
		quests.quest_completed.connect(_on_quest_completed)


func _on_quest_completed(quest_id: StringName) -> void:
	if quest_id != LAST_QUEST:
		return
	_set_flag(COMPLETE_FLAG)
	if _has_flag(DIRECTOR_DOWN):
		_set_flag(CAMPAIGN_FLAG)  # the campaign ends here, once, only after the Director is down
		Outpost17.say(self, COMPLETE_CAPTION, 6.0)


func _set_flag(flag: StringName) -> void:
	var state := get_node_or_null("/root/WorldState")
	if state != null and not state.has_flag(flag):
		state.set_flag(flag, true)


func _has_flag(flag: StringName) -> bool:
	var state := get_node_or_null("/root/WorldState")
	return state != null and state.has_flag(flag)


## Marks every group flag whose members are all cleared (cleared state lives in PersistentIds, so it survives
## saves), lifts the control door when the lockdown is off and the Captain is down, and re-offers unclaimed
## unique rewards.
func _refresh_groups() -> void:
	if parts == null:
		return
	for flag: StringName in GROUPS:
		var all_cleared := true
		for member: String in GROUPS[flag]:
			var spawn := parts.fspawns.get(member) as FortressSpawn
			all_cleared = all_cleared and spawn != null and spawn.is_cleared()
		if all_cleared:
			_set_flag(flag)
			if flag == &"iron_fortress_approach_clear":
				_set_flag(APPROACH_PASS)  # defeating the guards counts as dealing with them
	if _has_flag(LOCKDOWN_DONE) and _has_flag(CAPTAIN_DOWN):
		_set_flag(CONTROL_OPEN)
	_restore_rewards()


## The Fortress Captain holds the inner hall. Spawns once per save; the HUD boss bar shows the group "boss".
func release_captain() -> Enemy:
	var spawn := parts.fspawns["if_captain"] as FortressSpawn
	if not spawn.can_spawn():
		return null
	var captain := spawn.trigger()
	if captain != null:
		captain.add_to_group("boss")
		_offer_reward_on_defeat("if_captain", captain, CAPTAIN_REWARD)
		Outpost17.say(self, "The Fortress Captain steps out of the shadow of the control door.", 3.0)
	return captain


## The Director waits in the arena. Spawns once per save.
func release_director() -> Enemy:
	var spawn := parts.fspawns["if_director"] as FortressSpawn
	if not spawn.can_spawn():
		return null
	var director := spawn.trigger()
	if director != null:
		director.add_to_group("boss")
		_offer_reward_on_defeat("if_director", director, DIRECTOR_REWARD)
		Outpost17.say(self, "The Director has been waiting for someone to follow the evidence this far.", 4.0)
	return director


func _offer_reward_on_defeat(spawn_id: String, enemy: Enemy, item_path: String) -> void:
	enemy.defeated.connect(func() -> void:
		_give_reward(spawn_id, item_path, enemy.global_position))


## Puts a unique reward on the floor once, unless this save already owns it.
func _give_reward(spawn_id: String, item_path: String, at: Vector3) -> bool:
	if _reward_given.has(spawn_id) or not is_inside_tree():
		return false
	var item := load(item_path) as ItemData
	var player := get_tree().get_first_node_in_group("player")
	if item == null or player == null or EliteExperimentalSubject.reward_owned(player, item):
		return false
	_reward_given[spawn_id] = true
	Pickup.spawn(self, item, Vector3(at.x, 0.0, at.z))
	return true


## A cleared boss whose unique reward was never picked up (a reload in between): the reward waits where it stood.
func _restore_rewards() -> void:
	for spawn_id: String in REWARDS:
		var spawn := parts.fspawns.get(spawn_id) as FortressSpawn
		if spawn != null and spawn.is_cleared() and spawn.enemy == null:
			_give_reward(spawn_id, REWARDS[spawn_id], spawn.global_position)


# --- quests and persistence -------------------------------------------------------------

## Called by the region framework (or a test) when the player arrives. Starts the chain once.
func enter(entry_id: String = "from_research_complex") -> Transform3D:
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null and quests.has_method("start_quest"):
		if not quests.is_active(FIRST_QUEST) and not quests.is_completed(FIRST_QUEST):
			quests.start_quest(FIRST_QUEST)
	return entry_points.get(entry_id, entry_points["from_research_complex"])


## What this region keeps besides the world flags and PersistentIds: puzzle progress (restore is idempotent).
func capture_state() -> Dictionary:
	var puzzles: Dictionary = {}
	for id: String in parts.puzzles:
		puzzles[id] = (parts.puzzles[id] as MultiStepPuzzle).capture_state()
	return {"version": 1, "puzzles": puzzles}


func restore_state(raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	var saved: Variant = (raw as Dictionary).get("puzzles")
	if saved is Dictionary:
		for id: String in parts.puzzles:
			var data: Variant = (saved as Dictionary).get(id)
			if data is Dictionary:
				(parts.puzzles[id] as MultiStepPuzzle).restore_state(data)
	_refresh_groups()
