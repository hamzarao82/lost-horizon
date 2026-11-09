class_name StageEnemies
extends RefCounted
## "Enemies left" for the four later regions. N = living enemies now + members of lazy sources that have not
## spawned yet and are not cleared. Everything that is spawned shows up once in the first part, everything that
## is still waiting once in the second, so the number does not jump when a squad streams in, and it is right
## after a reload because cleared sources stay cleared (flags and PersistentIds) and the rest respawn in full.
## Enemies of the stage's wave encounter are NOT counted: the encounter has its own "Wave n/N" counter.

const REGIONS: Array[StringName] = [&"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
## Groups of the nodes that can still spawn enemies. PatrolGroup and BlackwoodEncounter join this group themselves.
const SOURCE_GROUP: StringName = &"stage_enemy_sources"


static func applies(region_id: StringName) -> bool:
	return REGIONS.has(region_id)


## {"left": int, "alive": int, "pending": int, "has_sources": bool}
static func count(tree: SceneTree) -> Dictionary:
	var alive := 0
	var pending := 0
	var sources := 0
	var wave_enemies := {}
	for stage in tree.get_nodes_in_group("stage_waves"):
		var own: Variant = stage.get("_enemies")
		if own is Array:
			for enemy in own:
				if is_instance_valid(enemy):
					wave_enemies[enemy] = true
	for node in tree.get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or wave_enemies.has(node):
			continue
		if node.has_method("is_dead") and node.is_dead():
			continue
		alive += 1
	for node in tree.get_nodes_in_group(SOURCE_GROUP):
		sources += 1
		if node is PatrolGroup:
			if not (node as PatrolGroup).spawned:
				pending += (node as PatrolGroup).scene_paths.size()
		elif node is BlackwoodEncounter:
			var encounter := node as BlackwoodEncounter
			if not encounter.spawned and not encounter.is_cleared:
				pending += encounter.scene_paths.size()
	for node in tree.get_nodes_in_group("facility_spawns"):
		sources += 1
		if node is FacilityEnemySpawn and (node as FacilityEnemySpawn).enemy == null and not (node as FacilityEnemySpawn).is_cleared():
			pending += 1
	for node in tree.get_nodes_in_group("fortress_spawns"):
		sources += 1
		if node is FortressSpawn and (node as FortressSpawn).enemy == null and not (node as FortressSpawn).is_cleared():
			pending += 1
	for node in tree.get_nodes_in_group("stage_boss_spawns"):
		sources += 1
		if node is StageBoss and (node as StageBoss).boss == null and not (node as StageBoss).is_defeated():
			pending += 1
	return {"left": alive + pending, "alive": alive, "pending": pending, "has_sources": sources > 0 or alive > 0}


## The HUD text: "Enemies left: N", "Area clear" once nothing is left, or "" in a region with no enemies at all.
static func label_text(tree: SceneTree) -> String:
	return label_for(count(tree))


static func label_for(numbers: Dictionary) -> String:
	if int(numbers.get("left", 0)) > 0:
		return "Enemies left: %d" % int(numbers["left"])
	return "Area clear" if bool(numbers.get("has_sources", false)) else ""
