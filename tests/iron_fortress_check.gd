extends SceneTree
## Iron Fortress checks (headless): godot --headless --path . -s tests/iron_fortress_check.gd
## The builder, quest-to-world consistency, a physics probe that really walks the route, keep-clear zones,
## the enemy config fallbacks, the region adapter, the map data and the draw-call budget.
## Mission flow is in iron_fortress_missions_check.gd, saving in iron_fortress_persistence_check.gd.

const Z = preload("res://scripts/regions/iron_fortress/iron_fortress_zones.gd")
const QUEST_DIR: String = "res://resources/quests/iron_fortress/"
const MESH_BUDGET: int = 150
const WALK_SPEED: float = 6.0

var _failures: int = 0
var _checks: int = 0
var _f: IronFortress
var _world: Node


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	_world = root.get_node_or_null("WorldState")
	_world.from_dict({})
	Enemy.active_patrollers = 0
	_f = IronFortress.new()
	root.add_child(_f)
	await _frames(4)
	_test_builder()
	_test_quest_consistency()
	_test_ids()
	await _test_connectivity()
	_test_keep_clear()
	_test_enemies()
	await _test_adapter()
	_test_map()
	_test_budget()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_builder() -> void:
	print("-- builder")
	_check(_f.kits.size() == 6, "six modular areas are built (%d)" % _f.kits.size())
	for area in Z.AREAS:
		_check(_f.parts.triggers.has(String(area["id"])), "area trigger %s exists" % String(area["id"]))
	_check(_f.parts.doors.size() == 5, "five doors: four credential gates and the lockdown door (%d)" % _f.parts.doors.size())
	_check(_f.parts.puzzles.size() == 2, "two puzzles are built here: comms and lockdown (%d)" % _f.parts.puzzles.size())
	_check(_f.parts.fspawns.size() == 19, "nineteen placed enemies (%d)" % _f.parts.fspawns.size())
	_check(_f.parts.document_ids.size() + _f.parts.terminal_ids.size() >= 14, "at least fourteen story entries are placed (%d)" % (_f.parts.document_ids.size() + _f.parts.terminal_ids.size()))
	_check(IronFortressStory.DOCS.size() >= 14 and IronFortressStory.DOCS.size() <= 18, "the story has 14 to 18 entries (%d)" % IronFortressStory.DOCS.size())
	for id: String in _f.parts.document_ids + _f.parts.terminal_ids:
		_check(IronFortressStory.DOCS.has(id), "%s has story text" % id)
	_check(_f.parts.crate_ids.size() == 4, "four optional caches (%d)" % _f.parts.crate_ids.size())
	_check(Z.location_at(Vector3(0.0, 0.0, 10.0)) == "Fortress Approach" and Z.location_at(Vector3(0.0, 0.0, -200.0)) == "Project Black Site Control Facility", "location names resolve")
	_check(IronFortress.main_path().size() > 40, "a main route is defined")


## Flags that the world really produces, taken from the built objects.
func _produced_flags() -> Dictionary:
	var out: Dictionary = {}
	for id: String in _f.parts.nodes:
		var node: Object = _f.parts.nodes[id]
		if node is ResearchTerminal and (node as ResearchTerminal).finish_flag != &"":
			out[String((node as ResearchTerminal).finish_flag)] = true
		if node is AccessPanel:
			out["credential_%s" % String((node as AccessPanel).grants)] = true
	for id: String in _f.parts.doors:
		out["door_%s_open" % id] = true
	for id in _f.parts.crate_ids:
		out["%s_taken" % id] = true
	for puzzle_id: String in _f.parts.puzzles:
		for flag in (_f.parts.puzzles[puzzle_id] as MultiStepPuzzle).all_flag_ids():
			out[String(flag)] = true
	for flag: StringName in IronFortress.GROUPS:
		out[String(flag)] = true
	for flag in [IronFortress.APPROACH_PASS, IronFortress.CONTROL_OPEN, IronFortress.COMPLETE_FLAG, IronFortress.CAMPAIGN_FLAG]:
		out[String(flag)] = true
	return out


func _test_quest_consistency() -> void:
	print("-- quest-to-world consistency")
	var flags := _produced_flags()
	var quest_count := 0
	for file in DirAccess.get_files_at(QUEST_DIR):
		if not file.ends_with(".tres"):
			continue
		quest_count += 1
		var quest := load(QUEST_DIR + file) as QuestData
		_check(quest != null and quest.validate().is_empty(), "%s loads and validates" % file)
		if quest == null:
			continue
		for objective in quest.objectives:
			for target in objective.targets:
				var ok := false
				match objective.type:
					ObjectiveData.Type.INTERACT:
						ok = _f.parts.nodes.has(target)
					ObjectiveData.Type.ENTER_AREA:
						ok = _f.parts.triggers.has(target)
					ObjectiveData.Type.FLAG:
						ok = flags.has(target)
				_check(ok, "%s / %s -> %s resolves in the world" % [quest.id, objective.id, target])
	_check(quest_count == 5, "five quests exist (%d)" % quest_count)
	var chain := ["if_last_stronghold", "if_inside_the_walls", "if_chain_of_command", "if_final_lockdown", "if_black_site"]
	for i in chain.size() - 1:
		var q := load("%s%s.tres" % [QUEST_DIR, chain[i]]) as QuestData
		_check(String(q.next_quest) == chain[i + 1], "%s leads to %s" % [chain[i], chain[i + 1]])
	_check((load(QUEST_DIR + "if_black_site.tres") as QuestData).next_quest == &"", "the last mission has no next mission: the campaign ends")


func _test_ids() -> void:
	print("-- ids are save-safe")
	var bad := 0
	var all_ids: Array[String] = []
	for id: String in _f.parts.nodes:
		all_ids.append(id)
		all_ids.append("doc_%s_found" % id)
	for id: String in _f.parts.fspawns:
		all_ids.append("%s_cleared" % id)
	for id: String in _f.parts.doors:
		all_ids.append("door_%s_open" % id)
	for flag in _produced_flags():
		all_ids.append(flag)
	for id in all_ids:
		var ok := id.length() > 0 and id.length() <= 48
		for i in id.length():
			var c := id.unicode_at(i)
			ok = ok and ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95)
		if not ok:
			bad += 1
			print("    unsafe id: ", id)
	_check(bad == 0, "every id is a-z, 0-9 and underscore, at most 48 characters (%d scanned)" % all_ids.size())


func _test_connectivity() -> void:
	print("-- connectivity (a physics probe walks the route)")
	var path := IronFortress.main_path()
	var closed := await _walk(path)
	var door_index := 0
	for i in path.size():
		if path[i].z <= Z.Z_A_B:
			door_index = i
			break
	_check(closed < path.size() - 1 and closed <= door_index, "with every door shut the probe stops at or before the main gate (point %d, gate at %d)" % [closed, door_index])
	for id: String in _f.parts.doors:
		(_f.parts.doors[id] as Door).open(false)
	await _frames(3)
	var reached := await _walk(path)
	_check(reached >= path.size() - 1, "with the doors open the probe walks the approach to the transmission console (%d/%d points)" % [reached, path.size()])


func _walk(points: Array[Vector3]) -> int:
	var probe := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	probe.add_child(shape)
	probe.collision_layer = 2
	probe.collision_mask = 1
	probe.position = points[0] + Vector3(0.0, 0.5, 0.0)
	root.add_child(probe)
	await _frames(3)
	var reached := 1
	for i in range(1, points.size()):
		var target := points[i]
		var arrived := false
		for step in 360:
			var flat := Vector3(target.x - probe.global_position.x, 0.0, target.z - probe.global_position.z)
			if flat.length() < 1.2:
				arrived = true
				break
			var direction := flat.normalized()
			probe.velocity.x = direction.x * WALK_SPEED
			probe.velocity.z = direction.z * WALK_SPEED
			probe.velocity.y -= 24.0 * (1.0 / float(Engine.physics_ticks_per_second))
			probe.move_and_slide()
			if probe.is_on_floor():
				probe.velocity.y = 0.0
			await physics_frame
		if not arrived:
			print("    stuck before point %d at %s (target %s)" % [i, str(probe.global_position), str(target)])
			break
		reached += 1
	probe.queue_free()
	await physics_frame
	return reached


func _test_keep_clear() -> void:
	print("-- keep-clear zones")
	var path := IronFortress.main_path()
	var blocking := 0
	for record in _f.parts.placed:
		if String(record["kind"]) == "door":
			continue
		var pos: Vector3 = record["pos"]
		for point in path:
			if Vector2(pos.x - point.x, pos.z - point.z).length() < 1.0 and bool(record["solid"]):
				blocking += 1
				print("    blocks the route: %s at %s" % [record["name"], str(pos)])
				break
	_check(blocking == 0, "no solid interactable sits on the main route")
	var arrival: Vector3 = (_f.entry_points["from_research_complex"] as Transform3D).origin
	var too_close := 0
	for record in _f.parts.placed:
		if (record["pos"] as Vector3).distance_to(arrival) < 2.5:
			too_close += 1
	_check(too_close == 0, "nothing stands within 2.5 m of the arrival")
	var unreachable := 0
	for record in _f.parts.placed:
		var p: Vector3 = record["pos"]
		if absf(p.x) > Z.HALF_W or p.z > Z.Z_SOUTH or p.z < Z.Z_END:
			unreachable += 1
			print("    outside the region: ", record["name"])
	_check(unreachable == 0, "every placed object is inside the fortress walls")


func _test_enemies() -> void:
	print("-- enemy configurations")
	for config_name: String in FortressEnemies.FALLBACKS:
		var res := FortressEnemies.resource(config_name)
		_check(res is FacilityEnemyConfig or res is EnemyConfig, "%s resolves to a usable config (%s)" % [config_name, FortressEnemies.path_for(config_name).get_file()])
	for id: String in _f.parts.fspawns:
		var spawn := _f.parts.fspawns[id] as FortressSpawn
		_check(FortressEnemies.resource(spawn.config_name) != null, "%s uses the config %s" % [id, spawn.config_name])
	var captain := _f.parts.fspawns["if_captain"] as FortressSpawn
	var director := _f.parts.fspawns["if_director"] as FortressSpawn
	_check(captain.trigger_radius == 0.0 and director.trigger_radius == 0.0, "the Captain and the Director are released by their area triggers, not by walking near")
	_check(Enemy.active_patrollers <= PatrolGroup.MAX_ACTIVE_PATROLLERS, "the global patroller cap is respected")


func _test_adapter() -> void:
	print("-- region adapter")
	var scene := (load("res://scenes/regions/IronFortressRegion.tscn") as PackedScene).instantiate() as IronFortressRegion
	root.add_child(scene)
	await _frames(3)
	var specs := scene.exit_specs()
	_check(specs.has(&"to_research_complex") and specs[&"to_research_complex"]["target_region"] == &"research_complex", "the only exit leads back to the Research Complex (the campaign ends here)")
	_check(specs.size() == 1, "there is no exit forward")
	_check(scene.entry_transform(&"from_research_complex").origin.z > 40.0, "the arrival is at the south end of the approach")
	_check(scene.entry_transform(&"from_underground").origin.z > 40.0, "the second entry also lands on the approach")
	_check(scene.entry_transform(&"nowhere").origin == scene.entry_transform(&"from_research_complex").origin, "an unknown entry falls back to the main arrival")
	var data := load("res://resources/regions/iron_fortress.tres") as RegionData
	_check(data != null and data.id == &"iron_fortress" and data.unlock_flag == &"iron_fortress_unlocked", "the region data is registered with its unlock flag")
	_check(RegionStore.IDS.has(&"iron_fortress") and EnvironmentPresets.IDS.has(&"iron_fortress"), "the region store and the environment presets know the region")
	scene.queue_free()
	await _frames(2)


func _test_map() -> void:
	print("-- map and campaign chain")
	var map := load("res://resources/regions/maps/iron_fortress.tres") as MapData
	_check(map != null and map.landmarks.size() == 6, "the map has six landmarks (%d)" % (map.landmarks.size() if map != null else 0))
	_check(CampaignFlow.CHAIN.has(&"iron_fortress") and CampaignFlow.CHAIN[&"iron_fortress"]["after"] == &"research_complex_mission_4_complete", "the Research Complex's last mission unlocks the Iron Fortress")
	_check((CampaignFlow.CHAIN[&"iron_fortress"]["aliases"] as Array).has(&"research_complex_region_complete"), "its region-complete flag is accepted as the same unlock")


func _test_budget() -> void:
	print("-- draw-call budget")
	var meshes := 0
	for node in _f.find_children("*", "MeshInstance3D", true, false):
		meshes += 1
	var lights := _f.find_children("*", "OmniLight3D", true, false).size()
	print("  info mesh instances: %d, lights: %d" % [meshes, lights])
	_check(meshes <= MESH_BUDGET, "at most %d mesh instances (%d)" % [MESH_BUDGET, meshes])
	_check(lights <= 30, "at most 30 real lights (%d)" % lights)
