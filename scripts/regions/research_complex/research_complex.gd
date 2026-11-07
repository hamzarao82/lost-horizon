class_name ResearchComplex
extends Node3D
## The Research Complex: the fourth region. A self-contained content builder (like DeadCoast and
## Blackwood): build() assembles six areas from modular sub-builders; the region framework reads
## `entry_points`, `exit_points`, `capture_state()` / `restore_state()`. It starts its own quest chain.
## Every saved id is underscore-only and at most 48 characters (WorldState drops anything else on load).

const Z = preload("res://scripts/regions/research_complex/research_complex_zones.gd")
const REGION_ID: StringName = &"research_complex"
const FIRST_QUEST: StringName = &"rc_restricted_zone"
const LAST_QUEST: StringName = &"rc_project_black_site"
const COMPLETE_FLAG: StringName = &"research_complex_region_complete"
const PERIMETER_PASS: StringName = &"research_complex_perimeter_pass"
const COMMANDER_CLAIM: StringName = &"commander_cleared"
const SEALED_TEXT: String = "Access to the Iron Fortress road is sealed. For now."
const AMBUSH_WARNING: String = "Something is moving behind the glass."
const WARNING_SECONDS: float = 1.5
const COMMANDER_CONFIG: String = "res://resources/enemies/facility_commander.tres"
const COMMANDER_POS: Vector3 = Vector3(0.0, 0.0, -146.0)

## world flag -> spawn ids that must all be cleared (the commander counts as `commander_cleared`).
const GROUPS: Dictionary = {
	&"research_complex_perimeter_clear": ["rc_guard_1", "rc_guard_2", "rc_guard_3"],
	&"research_complex_ambush_cleared": ["rc_subject_med_1", "rc_subject_med_2"],
	&"research_complex_subjects_cleared": ["rc_subject_cell_1", "rc_subject_cell_2", "rc_subject_cell_3"],
	&"research_complex_elite_down": ["rc_elite_subject"],
	&"research_complex_lab_security_cleared": ["rc_lab_heavy_1", "rc_lab_heavy_2", "commander_cleared"],
}

var entry_points: Dictionary = {}
var exit_points: Dictionary = {}
var parts: ResearchComplexParts
var kits: Dictionary = {}
var commander: Enemy
var ambush_released: bool = false

var _built: bool = false


func _ready() -> void:
	set_meta(&"region_id", REGION_ID)
	set_meta(&"ambience_name", "research_complex")
	set_meta(&"environment_preset", "research_complex")
	if not _built:
		build()


func region_id() -> StringName:
	return REGION_ID


func build() -> void:
	if _built:
		return
	_built = true
	parts = ResearchComplexParts.new(self)
	kits["perimeter"] = ResearchComplexOuter.perimeter(self, parts)
	kits["admin"] = ResearchComplexOuter.admin_wing(self, parts)
	kits["medical"] = ResearchComplexOuter.medical_wing(self, parts)
	kits["containment"] = ResearchComplexInner.containment(self, parts)
	kits["laboratory"] = ResearchComplexInner.laboratory(self, parts)
	kits["underground"] = ResearchComplexInner.underground(self, parts)
	_build_area_triggers()
	_build_entries_and_exits()
	_wire()
	_refresh_groups.call_deferred()


func location_at(pos: Vector3) -> String:
	return Z.location_at(pos)


## The walkable main route (door by door, with the gates opened) from the arrival to the sealed exit.
static func main_path() -> Array[Vector3]:
	# The gate chicane (two concrete barriers) and the reception desk are solid: the route weaves around them.
	var pts: Array[Vector3] = [Vector3(0.0, 0.1, 47.0), Vector3(2.0, 0.1, 46.0), Vector3(2.0, 0.1, 44.0),
			Vector3(-1.5, 0.1, 44.0), Vector3(-2.0, 0.1, 41.5)]
	var z := 38.0
	while z >= -12.0:
		pts.append(Vector3(0.0, 0.1, z))
		z -= 5.0
	pts.append_array([Vector3(5.0, 0.1, -15.0), Vector3(5.0, 0.1, -21.0), Vector3(0.0, 0.1, -23.0)])
	z = -28.0
	while z >= -168.0:
		pts.append(Vector3(0.0, 0.1, z))
		z -= 5.0
	pts.append(Vector3(0.0, 0.1, -170.0))
	var hatch := Z.HATCH_X
	pts.append(Vector3(hatch, 0.1, -170.0))
	pts.append(Vector3(hatch, 0.1, -172.5))
	for i in 8:
		pts.append(Vector3(hatch, -0.5 * float(i + 1) + 0.1, -173.5 - float(i)))
	pts.append(Vector3(hatch, Z.UNDER_Y + 0.1, -183.0))
	var zz := -188.0
	while zz >= -200.0:
		pts.append(Vector3(hatch, Z.UNDER_Y + 0.1, zz))
		zz -= 5.0
	return pts


func _build_area_triggers() -> void:
	for area in Z.AREAS:
		var rect := Z.area_rect(area)
		var y := float(area["y"])
		parts.area_trigger(String(area["id"]), Vector3(0.0, y, float(area["z"])), Vector3(rect.size.x, 16.0 if y > 0.0 else 8.0, rect.size.y))


func _build_entries_and_exits() -> void:
	entry_points = {
		"from_blackwood": Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 47.0)),                 # faces north (-z)
		"from_underground": Transform3D(Basis.IDENTITY, Vector3(Z.HATCH_X, Z.UNDER_Y + 0.1, -190.0)),
	}
	exit_points = {
		"to_blackwood": {"position": Vector3(0.0, 0.0, 54.0), "region": "blackwood", "entry": "from_underground",
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
	for id: String in parts.spawns:
		(parts.spawns[id] as FacilityEnemySpawn).cleared.connect(_refresh_groups)
	(parts.triggers["rc_checkpoint_reach"] as MissionTrigger).fired.connect(func(_event: StringName) -> void: _set_flag(PERIMETER_PASS))
	(parts.triggers["rc_medical_ambush"] as MissionTrigger).fired.connect(func(_event: StringName) -> void: begin_ambush())
	(parts.triggers["rc_elite_chamber"] as AreaTrigger).entered.connect(func(_id: StringName) -> void: release_elite())
	(parts.triggers["rc_lab"] as AreaTrigger).entered.connect(func(_id: StringName) -> void: release_commander())
	(parts.triggers["rc_sealed_exit"] as AreaTrigger).entered.connect(func(_id: StringName) -> void: Outpost17.say(self, SEALED_TEXT, 5.0))
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null and quests.has_signal("quest_completed"):
		quests.quest_completed.connect(_on_quest_completed)


func _on_quest_completed(quest_id: StringName) -> void:
	if quest_id == LAST_QUEST:
		_set_flag(COMPLETE_FLAG)  # saved with the world flags; the map and the campaign read it


func _set_flag(flag: StringName) -> void:
	var state := get_node_or_null("/root/WorldState")
	if state != null:
		state.set_flag(flag, true)


## Marks every group flag whose members are all cleared (cleared state lives in PersistentIds, so it survives saves).
func _refresh_groups() -> void:
	for flag: StringName in GROUPS:
		var all_cleared := true
		for member: String in GROUPS[flag]:
			if member == String(COMMANDER_CLAIM):
				all_cleared = all_cleared and PersistentIds.is_claimed(REGION_ID, COMMANDER_CLAIM)
			else:
				var spawn := parts.spawns.get(member) as FacilityEnemySpawn
				all_cleared = all_cleared and spawn != null and spawn.is_cleared()
		if all_cleared:
			_set_flag(flag)
			if flag == &"research_complex_perimeter_clear":
				_set_flag(PERIMETER_PASS)  # defeating the guards counts as dealing with them


## The medical ambush: a fair 1.5 s warning (caption and a creak) before two subjects are released.
func begin_ambush() -> void:
	if ambush_released or _spawn_cleared("rc_subject_med_1") and _spawn_cleared("rc_subject_med_2"):
		return
	ambush_released = true
	Outpost17.say(self, AMBUSH_WARNING, 2.5)
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.call("play", &"metal_creak")
	get_tree().create_timer(WARNING_SECONDS).timeout.connect(release_ambush)


func release_ambush() -> void:
	for id in ["rc_subject_med_1", "rc_subject_med_2"]:
		var spawn := parts.spawns[id] as FacilityEnemySpawn
		if spawn.can_spawn():
			var enemy := spawn.trigger()
			if enemy != null:
				enemy.aggro()


## Releases Subject Zero when the player steps into the chamber. The HUD boss bar shows the group "boss".
func release_elite() -> Enemy:
	var spawn := parts.spawns["rc_elite_subject"] as FacilityEnemySpawn
	if not spawn.can_spawn():
		return null
	var elite := spawn.trigger()
	if elite != null:
		elite.add_to_group("boss")  # the existing HUD boss bar and name read this group
		Outpost17.say(self, "Subject Zero is awake.", 3.0)
	return elite


## The Facility Commander holds the laboratory (ranged, uses the cover points). Spawns once per save.
func release_commander() -> Enemy:
	if commander != null and is_instance_valid(commander):
		return commander
	if PersistentIds.is_claimed(REGION_ID, COMMANDER_CLAIM):
		return null
	var config := load(COMMANDER_CONFIG) as EnemyConfig
	if config == null:
		return null
	commander = config.spawn(self, COMMANDER_POS)
	commander.defeated.connect(func() -> void:
		PersistentIds.claim(REGION_ID, COMMANDER_CLAIM)
		_refresh_groups())
	return commander


func _spawn_cleared(id: String) -> bool:
	var spawn := parts.spawns.get(id) as FacilityEnemySpawn
	return spawn != null and spawn.is_cleared()


# --- quests and persistence -------------------------------------------------------------

## Called by the region framework (or a test) when the player arrives. Starts the chain once.
func enter(entry_id: String = "from_blackwood") -> Transform3D:
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null and quests.has_method("start_quest"):
		if not quests.is_active(FIRST_QUEST) and not quests.is_completed(FIRST_QUEST):
			quests.start_quest(FIRST_QUEST)
	return entry_points.get(entry_id, entry_points["from_blackwood"])


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
