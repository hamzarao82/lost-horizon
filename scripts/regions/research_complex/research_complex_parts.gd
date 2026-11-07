class_name ResearchComplexParts
extends RefCounted
## Factory and registry for everything interactive in the Research Complex: documents, terminals, panels,
## doors, crates, checkpoints, enemy spawns, puzzles and triggers. Area builders call these; the region
## script and the tests read the registries. All ids are underscore-only and at most 48 characters.

const CACHE_TABLE: String = "res://resources/loot/research_complex_cache.tres"

var root: Node3D
var nodes: Dictionary = {}
var spawns: Dictionary = {}
var puzzles: Dictionary = {}
var doors: Dictionary = {}
var triggers: Dictionary = {}
var crate_ids: Array[String] = []
var document_ids: Array[String] = []
var terminal_ids: Array[String] = []
## {name, pos, radius, why, solid}: what the keep-clear tests read.
var placed: Array[Dictionary] = []

var _configs: Dictionary = {}


func _init(parent: Node3D) -> void:
	root = parent


func config(config_name: String) -> FacilityEnemyConfig:
	if not _configs.has(config_name):
		_configs[config_name] = load("res://resources/enemies/facility_%s.tres" % config_name) as FacilityEnemyConfig
	return _configs[config_name]


func _register(item: Node3D, id: String, pos: Vector3, why: String, radius: float = 2.2, solid: bool = false) -> void:
	item.position = pos
	root.add_child(item)
	nodes[id] = item
	placed.append({"kind": "interactable", "name": id, "pos": pos, "radius": radius, "why": why, "solid": solid})


func doc(id: String, pos: Vector3, why: String, extra: String = "", lift: float = 0.0) -> LoreDocument:
	var item := LoreDocument.new()
	item.name = id
	item.title = ResearchComplexStory.title(id)
	item.body_text = ResearchComplexStory.body(id) + extra
	item.interaction_id = StringName(id)
	_register(item, id, pos + Vector3(0.0, lift, 0.0), why)
	document_ids.append(id)
	return item


func terminal(id: String, pos: Vector3, why: String, finish_flag: String = "", requires: String = "", credential: String = "", screen: bool = true) -> ResearchTerminal:
	var item := ResearchTerminal.new()
	item.name = id
	item.terminal_title = ResearchComplexStory.title(id)
	item.pages = PackedStringArray(ResearchComplexStory.pages(id))
	item.finish_flag = StringName(finish_flag)
	item.requires_flag = StringName(requires)
	item.credential = StringName(credential)
	item.interaction_id = StringName(id)
	item.show_model = screen
	_register(item, id, pos, why, 2.4, screen)
	terminal_ids.append(id)
	return item


func panel(id: String, pos: Vector3, grants: String, why: String, requires: String = "") -> AccessPanel:
	var item := AccessPanel.new()
	item.name = id
	item.interaction_id = StringName(id)
	item.grants = StringName(grants)
	item.requires_flag = StringName(requires)
	_register(item, id, pos, why, 2.4, true)
	return item


func door(id: String, pos: Vector3, credential: String, width: float = 4.0) -> SecurityDoor:
	var item := SecurityDoor.new()
	item.name = "Door_" + id
	item.door_id = StringName(id)
	item.credential = StringName(credential)
	item.width = width
	item.position = pos
	root.add_child(item)
	doors[id] = item
	placed.append({"kind": "door", "name": id, "pos": pos, "radius": width * 0.5, "why": "a wall opening closed by a security door", "solid": true})
	return item


## A door opened by any world flag (puzzle result, a defeated enemy) rather than a credential.
func flag_door(id: String, pos: Vector3, flag: String, reason: String, width: float = 4.0) -> Door:
	var item := Door.new()
	item.name = "Door_" + id
	item.door_id = StringName(id)
	item.width = width
	item.locked_by_flag = StringName(flag)
	item.lock_reason = reason
	item.position = pos
	root.add_child(item)
	doors[id] = item
	placed.append({"kind": "door", "name": id, "pos": pos, "radius": width * 0.5, "why": "a wall opening closed by a flag door", "solid": true})
	return item


func crate(id: String, loot: Array, pos: Vector3, why: String, table: String = CACHE_TABLE) -> SupplyCrate:
	var item := SupplyCrate.new()
	item.name = id
	item.crate_id = StringName(id)
	var paths := PackedStringArray()
	for entry in loot:
		paths.append("res://resources/items/%s.tres" % entry)
	item.loot_paths = paths
	item.bonus_table_path = table
	_register(item, id, pos, why, 2.0)
	crate_ids.append(id)
	return item


func checkpoint(id: String, pos: Vector3) -> Checkpoint:
	var item := Checkpoint.new()
	item.name = id
	item.interaction_id = StringName(id)
	_register(item, id, pos + Vector3(0.0, 0.8, 0.0), "rest point with a save: %s" % id)
	return item


func spawn(id: String, config_name: String, pos: Vector3, radius: float = 0.0, route: Array = []) -> FacilityEnemySpawn:
	var item := FacilityEnemySpawn.new()
	item.name = "Spawn_" + id
	item.spawn_id = StringName(id)
	item.config = config(config_name)
	item.trigger_radius = radius
	var points := PackedVector3Array()
	for p in route:
		points.append(p as Vector3)
	item.route_points = points
	item.position = pos
	root.add_child(item)
	spawns[id] = item
	return item


func area_trigger(id: String, center: Vector3, size: Vector3) -> AreaTrigger:
	var trigger := AreaTrigger.new()
	trigger.name = "Trigger_" + id
	trigger.area_id = StringName(id)
	trigger.size = size
	trigger.position = center
	root.add_child(trigger)
	triggers[id] = trigger
	return trigger


func mission_trigger(id: String, event: String, center: Vector3, size: Vector3) -> MissionTrigger:
	var trigger := MissionTrigger.new()
	trigger.name = "Mission_" + id
	trigger.trigger_id = StringName(id)
	trigger.event_id = StringName(event)
	trigger.size = size
	trigger.position = center
	root.add_child(trigger)
	triggers[id] = trigger
	return trigger


func switch(id: String, pos: Vector3, puzzle: Node, switch_id: String, prompt: String, why: String) -> PuzzleSwitch:
	var item := PuzzleSwitch.new()
	item.name = id
	item.interaction_id = StringName(id)
	item.puzzle = puzzle
	item.switch_id = StringName(switch_id)
	item.prompt_text = prompt
	_register(item, id, pos, why, 2.2, true)
	FacilityProps.add_console(item, Color(0.95, 0.35, 0.25))
	return item


func cover(pos: Vector3) -> CoverPoint:
	var marker := CoverPoint.new()
	marker.position = pos
	marker.add_to_group(CoverPoint.GROUP)
	root.add_child(marker)
	return marker
