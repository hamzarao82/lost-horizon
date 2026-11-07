class_name FortressEnemies
extends RefCounted
## Resolves a fortress enemy config name to a resource and spawns it. The real configs
## (resources/enemies/fortress_infantry.tres, elite_security_soldier.tres, heavy_assault_unit.tres,
## tactical_commander.tres, fortress_captain.tres, director.tres) come from the combat work; until a file
## exists the placement falls back to the closest Research Complex configuration, so the region always
## plays. `missing()` lists the names that are still on a fallback.

const DIR: String = "res://resources/enemies/"
const FALLBACKS: Dictionary = {
	"fortress_infantry": "facility_security_guard",
	"elite_security_soldier": "facility_heavy_guard",
	"heavy_assault_unit": "facility_heavy_guard",
	"tactical_commander": "facility_commander",
	"fortress_captain": "facility_elite_subject",
	"director": "facility_elite_subject",
}


static func path_for(config_name: String) -> String:
	var own := "%s%s.tres" % [DIR, config_name]
	if ResourceLoader.exists(own):
		return own
	return "%s%s.tres" % [DIR, String(FALLBACKS.get(config_name, "facility_security_guard"))]


static func is_fallback(config_name: String) -> bool:
	return path_for(config_name) != "%s%s.tres" % [DIR, config_name]


static func missing() -> Array[String]:
	var out: Array[String] = []
	for config_name: String in FALLBACKS:
		if is_fallback(config_name):
			out.append(config_name)
	return out


static func resource(config_name: String) -> Resource:
	return load(path_for(config_name))


## Instantiates the enemy under `parent` at `local_pos` (position is set before the node enters the tree).
static func make(config_name: String, parent: Node, local_pos: Vector3, spawn: FortressSpawn, route_points: PackedVector3Array) -> Enemy:
	var res := resource(config_name)
	if res is FacilityEnemyConfig:
		var cfg := res as FacilityEnemyConfig
		var scene := load(cfg.base_scene_path) as PackedScene
		if scene == null:
			return null
		var made := scene.instantiate() as Enemy
		if made == null:
			return null
		cfg.apply(made)
		if cfg.patrols and not route_points.is_empty() and spawn != null:
			made.patrol_route = spawn.attach_route(route_points)
		made.position = local_pos
		parent.add_child(made)
		return made
	if res is EnemyConfig:
		return (res as EnemyConfig).spawn(parent, local_pos)
	return null
