class_name IronFortressParts
extends ResearchComplexParts
## The Research Complex factory, pointed at the Iron Fortress: story text from IronFortressStory, enemies from
## FortressEnemies, loot tables from resources/loot/iron_fortress_*. Door, panel, terminal and puzzle claims
## still land in the shared facility namespace (FacilityIds.REGION); every fortress id starts with `if_` so
## it can never collide with a Research Complex id.

const FORTRESS_CACHE: String = "res://resources/loot/iron_fortress_cache.tres"
const FORTRESS: StringName = &"iron_fortress"

var fspawns: Dictionary = {}


func doc(id: String, pos: Vector3, why: String, extra: String = "", lift: float = 0.0) -> LoreDocument:
	var item := LoreDocument.new()
	item.name = id
	item.title = IronFortressStory.title(id)
	item.body_text = IronFortressStory.body(id) + extra
	item.interaction_id = StringName(id)
	_register(item, id, pos + Vector3(0.0, lift, 0.0), why)
	document_ids.append(id)
	return item


func terminal(id: String, pos: Vector3, why: String, finish_flag: String = "", requires: String = "", credential: String = "", screen: bool = true) -> ResearchTerminal:
	var item := ResearchTerminal.new()
	item.name = id
	item.terminal_title = IronFortressStory.title(id)
	item.pages = PackedStringArray(IronFortressStory.pages(id))
	item.finish_flag = StringName(finish_flag)
	item.requires_flag = StringName(requires)
	item.credential = StringName(credential)
	item.interaction_id = StringName(id)
	item.show_model = screen
	_register(item, id, pos, why, 2.4, screen)
	terminal_ids.append(id)
	return item


func crate(id: String, loot: Array, pos: Vector3, why: String, table: String = FORTRESS_CACHE) -> SupplyCrate:
	return super.crate(id, loot, pos, why, table)


## A fortress enemy spawn (FortressSpawn). `config_name` is a FortressEnemies name.
func fspawn(id: String, config_name: String, pos: Vector3, radius: float = 0.0, route: Array = []) -> FortressSpawn:
	var item := FortressSpawn.new()
	item.name = "Spawn_" + id
	item.spawn_id = StringName(id)
	item.config_name = config_name
	item.trigger_radius = radius
	var points := PackedVector3Array()
	for p in route:
		points.append(p as Vector3)
	item.route_points = points
	item.position = pos
	root.add_child(item)
	fspawns[id] = item
	return item
