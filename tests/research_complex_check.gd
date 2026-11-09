extends SceneTree
## Research Complex checks (headless): godot --headless --path . -s tests/research_complex_check.gd
## The builder, quest-to-world consistency, a physics probe that really walks the route, keep-clear zones,
## the floor hazard's fairness, the region adapter and the draw-call budget.
## Mission flow is in research_complex_missions_check.gd, saving in research_complex_persistence_check.gd.

const Z = preload("res://scripts/regions/research_complex/research_complex_zones.gd")
const QUEST_DIR: String = "res://resources/quests/research_complex/"
const MESH_BUDGET: int = 150
const WALK_SPEED: float = 6.0
const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"

var _failures: int = 0
var _checks: int = 0
var _rc: ResearchComplex
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
	_rc = ResearchComplex.new()
	root.add_child(_rc)
	await _frames(4)
	_test_builder()
	_test_quest_consistency()
	_test_ids()
	await _test_connectivity()
	_test_keep_clear()
	await _test_hazard()
	await _test_adapter()
	_test_map()
	_test_budget()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_builder() -> void:
	print("-- builder")
	for key in ["perimeter", "admin", "medical", "containment", "laboratory", "underground"]:
		_check(_rc.kits.has(key) and _rc.get_node_or_null("Area_" + _area_node(key)) != null, "area '%s' exists as its own modular node" % key)
	for area in Z.AREAS:
		_check(_rc.parts.triggers.has(String(area["id"])), "the area trigger %s exists" % area["id"])
	_check(_rc.entry_points.has("from_blackwood") and _rc.entry_points.has("from_underground"), "both entry points exist")
	_check(_rc.exit_points.has("to_blackwood"), "the exit back to Blackwood exists")
	_check(_rc.parts.puzzles.has("containment") and _rc.parts.puzzles.has("lab_power"), "both puzzles are built")
	_check(_rc.parts.spawns.size() >= 12, "enemy spawns are placed (%d)" % _rc.parts.spawns.size())
	_check(get_nodes_in_group("cover_points").size() >= 5, "cover points exist for the Commander (%d)" % get_nodes_in_group("cover_points").size())
	_check(_rc.get_meta(&"ambience_name") == "research_complex" and _rc.get_meta(&"environment_preset") == "research_complex", "region ambience and environment metadata are set")
	_check(Z.location_at(Vector3(0.0, 0.0, -150.0)) == "Central Research Laboratory" and Z.location_at(Vector3(900.0, 0.0, 0.0)) == "", "location_at names the area")


func _area_node(key: String) -> String:
	return {"perimeter": "Perimeter", "admin": "AdminWing", "medical": "MedicalWing", "containment": "Containment",
			"laboratory": "Laboratory", "underground": "Underground"}[key]


## Every quest objective must point at something the world really produces.
func _test_quest_consistency() -> void:
	print("-- quests match the world")
	var areas: Array[String] = []
	var interactions: Array[String] = []
	for id: String in _rc.parts.triggers:
		areas.append(id)
	for id: String in _rc.parts.nodes:
		interactions.append(id)
	var flags := _produced_flags()
	var quests := _load_quests()
	_check(quests.size() == 4, "four Research Complex quests exist")
	for quest in quests:
		_check(quest.validate().is_empty(), "%s validates" % quest.id)
		for objective in quest.objectives:
			var ok := true
			for target in objective.targets:
				match objective.type:
					ObjectiveData.Type.ENTER_AREA:
						ok = ok and areas.has(target)
					ObjectiveData.Type.INTERACT:
						ok = ok and interactions.has(target)
					ObjectiveData.Type.FLAG:
						ok = ok and flags.has(target)
			_check(ok, "%s / %s points at something that exists (%s)" % [quest.id, objective.id, ", ".join(objective.targets)])
	_check(quests[0].next_quest == &"rc_silent_records" and quests[1].next_quest == &"rc_containment_breach" and quests[2].next_quest == &"rc_project_black_site", "the missions chain in order")


func _load_quests() -> Array[QuestData]:
	var out: Array[QuestData] = []
	for id in ["rc_restricted_zone", "rc_silent_records", "rc_containment_breach", "rc_project_black_site"]:
		var q := load(QUEST_DIR + id + ".tres") as QuestData
		if q != null:
			out.append(q)
	return out


## Flags the world can set: credentials, door opens, document reads, crate takes, group results, puzzle results.
func _produced_flags() -> Array[String]:
	var out: Array[String] = []
	out.append(String(RegionFlags.key(&"research_complex", &"waves_cleared")))  # produced by the stage's StageWaves encounter
	out.append(String(StageBoss.flag_for(&"research_complex", 2)))  # the commander boss: set by the stage's StageBoss helper
	for level in FacilityIds.LEVELS:
		out.append(String(FacilityIds.credential_flag(level)))
	for id: String in _rc.parts.doors:
		out.append("door_%s_open" % id)
	for id in _rc.parts.document_ids:
		out.append("doc_%s_found" % id)
	for id in _rc.parts.terminal_ids:
		out.append("doc_%s_found" % id)
		var terminal := _rc.parts.nodes[id] as Terminal
		if terminal.finish_flag != &"":
			out.append(String(terminal.finish_flag))
	for id in _rc.parts.crate_ids:
		out.append("%s_taken" % id)
	for flag in ResearchComplex.GROUPS:
		out.append(String(flag))
	for key: String in _rc.parts.puzzles:
		out.append(String((_rc.parts.puzzles[key] as MultiStepPuzzle).done_flag()))
	out.append(String(ResearchComplex.PERIMETER_PASS))
	out.append(String(ResearchComplex.COMPLETE_FLAG))
	return out


func _test_ids() -> void:
	print("-- saved ids are saveable")
	var bad: Array[String] = []
	var scanned := 0
	var all_ids: Array[String] = []
	for id: String in _rc.parts.nodes:
		all_ids.append(id)
	for id: String in _rc.parts.spawns:
		all_ids.append(id)
	for id: String in _rc.parts.doors:
		all_ids.append(id)
	for id: String in _rc.parts.triggers:
		all_ids.append(id)
	for flag in _produced_flags():
		all_ids.append(flag)
	for key: String in _rc.parts.puzzles:
		for flag in (_rc.parts.puzzles[key] as MultiStepPuzzle).all_flag_ids():
			all_ids.append(String(flag))
	for quest in _load_quests():
		for objective in quest.objectives:
			for target in objective.targets:
				all_ids.append(target)
	for id in all_ids:
		scanned += 1
		if not FacilityIds.is_saveable(id):
			bad.append(id)
	_check(bad.is_empty(), "all %d ids are [a-z0-9_] and at most 48 characters %s" % [scanned, str(bad)])
	var longest := 0
	for id in _rc.parts.document_ids:
		longest = maxi(longest, ("doc_%s_found" % id).length())
	for id in _rc.parts.crate_ids:
		longest = maxi(longest, ("%s_taken" % id).length())
	_check(longest <= 48, "the longest derived document or crate flag is %d characters" % longest)
	var dotted := "door_rc.admin_door_open"
	_check(not FacilityIds.is_saveable(dotted), "a dotted id would be rejected (the control for this scan)")


# --- connectivity ---------------------------------------------------------------------

func _test_keep_clear() -> void:
	print("-- keep-clear zones")
	var path := ResearchComplex.main_path()
	var blocking := 0
	for record in _rc.parts.placed:
		if String(record["kind"]) == "door":
			continue
		var pos: Vector3 = record["pos"]
		if pos.y < -1.0:
			continue
		for point in path:
			if absf(point.y - pos.y) > 3.0:
				continue
			var flat := Vector2(pos.x - point.x, pos.z - point.z).length()
			if flat < 1.0 and bool(record["solid"]):
				blocking += 1
				print("    blocks the route: %s at %s" % [record["name"], str(pos)])
				break
	_check(blocking == 0, "no solid interactable sits on the main route")
	var arrival: Vector3 = (_rc.entry_points["from_blackwood"] as Transform3D).origin
	var too_close := 0
	for record in _rc.parts.placed:
		if (record["pos"] as Vector3).distance_to(arrival) < 2.5:
			too_close += 1
	_check(too_close == 0, "nothing is placed on top of the arrival point")


func _test_connectivity() -> void:
	print("-- connectivity (a physics probe walks the route)")
	var path := ResearchComplex.main_path()
	# closed: the admin door stops the probe at the facade
	var closed := await _walk(path)
	var door_index := 0
	for i in path.size():
		if path[i].z <= Z.Z_A_B:
			door_index = i
			break
	_check(closed < path.size() - 1 and closed <= door_index, "with every door shut the probe stops at or before the admin door (point %d, door at %d)" % [closed, door_index])
	for id: String in _rc.parts.doors:
		(_rc.parts.doors[id] as Door).open(false)
	await _frames(3)
	var reached := await _walk(path)
	_check(reached >= path.size() - 1, "with the doors open the probe walks arrival to sealed exit (%d/%d points)" % [reached, path.size()])


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


# --- the hazard -------------------------------------------------------------------------

func _test_hazard() -> void:
	print("-- the floor hazard is fair")
	var hazard := ResearchComplexHazard.new()
	hazard.size = Vector3(4.0, 1.5, 2.0)
	root.add_child(hazard)
	await _frames(2)
	_check(ResearchComplexHazard.WARN_TIME >= 0.5 and absf(ResearchComplexHazard.CYCLE - 1.5) < 0.001, "a 1.5 s cycle with a warning of at least 0.5 s")
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(3)
	var health: HealthComponent = player.health
	var start_hp: float = health.health
	# step through a whole cycle in small slices and record the phase order and where damage lands
	var order: Array[int] = []
	var damage_phases: Array[int] = []
	var last_hp: float = start_hp
	for i in 300:
		hazard.advance(0.01)
		if order.is_empty() or order[order.size() - 1] != int(hazard.phase):
			order.append(int(hazard.phase))
		if hazard.phase == ResearchComplexHazard.Phase.ACTIVE:
			hazard.hurt(player)
		if health.health < last_hp - 0.01:
			damage_phases.append(int(hazard.phase))
			last_hp = health.health
	var legal := order.size() >= 4
	for i in range(1, order.size()):
		var expect := (order[i - 1] + 1) % 3
		legal = legal and order[i] == expect
	_check(legal, "the phases run SAFE, WARN, ACTIVE in order (%s)" % str(order))
	_check(damage_phases.all(func(p: int) -> bool: return p == int(ResearchComplexHazard.Phase.ACTIVE)), "damage only ever happens in the active phase")
	hazard._set_phase(ResearchComplexHazard.Phase.WARN)
	var before: float = health.health
	_check(not hazard.hurt(player) and is_equal_approx(health.health, before), "the warning phase never damages")
	hazard._set_phase(ResearchComplexHazard.Phase.SAFE)
	_check(not hazard.hurt(player) and is_equal_approx(health.health, before), "the safe phase never damages")
	player.free()
	hazard.free()


# --- adapter and budget --------------------------------------------------------------------

func _test_adapter() -> void:
	print("-- region adapter")
	var scene := load("res://scenes/regions/ResearchComplexRegion.tscn") as PackedScene
	var region := scene.instantiate() as ResearchComplexRegion
	root.add_child(region)
	await _frames(3)
	_check(region.entry_transform(&"from_blackwood").origin.is_equal_approx(Vector3(0.0, 0.1, 47.0)), "the adapter maps the arrival entry")
	_check(region.entry_transform(&"nowhere").origin.is_equal_approx(Vector3(0.0, 0.1, 47.0)), "an unknown entry falls back to the arrival")
	var exits := region.exit_specs()
	_check(exits.has(&"to_blackwood") and exits[&"to_blackwood"]["target_region"] == &"blackwood" and exits[&"to_blackwood"]["target_entry"] == &"from_underground", "the exit leads back to Blackwood")
	var data := load("res://resources/regions/research_complex.tres") as RegionData
	_check(data.scene_path == "res://scenes/regions/ResearchComplexRegion.tscn", "the region data points at the real scene, not the stub")
	region.free()


func _test_budget() -> void:
	print("-- budget")
	var meshes := 0
	var lights := 0
	var shapes := 0
	for node in _rc.find_children("*", "", true, false):
		if node is MeshInstance3D and (node as MeshInstance3D).visible:
			meshes += 1
		elif node is OmniLight3D:
			lights += 1
		elif node is CollisionShape3D:
			shapes += 1
	print("    mesh instances: %d, omni lights: %d, collision shapes: %d" % [meshes, lights, shapes])
	_check(meshes <= MESH_BUDGET, "at most %d mesh instances (an upper bound on draw calls): %d" % [MESH_BUDGET, meshes])
	_check(lights <= 24, "few real lights (%d)" % lights)


func _test_map() -> void:
	print("-- world map")
	var map := MapData.load_for(&"research_complex")
	var ids: Array[String] = []
	var longest := 0
	for landmark in map.landmarks:
		ids.append(String((landmark as Dictionary)["id"]))
		longest = maxi(longest, String((landmark as Dictionary)["flag"]).length())
	var expect: Array[String] = []
	for area in Z.AREAS:
		expect.append(String(area["id"]))
	_check(ids == expect, "the map's landmarks are the builder's areas, in order (regenerate with tools/gen_map_data.gd) %s" % str(ids))
	_check(longest <= 48, "every discovery flag on the map stays within 48 characters (longest %d)" % longest)
	var entry_flag := String(MapData.discovery_flag(&"research_complex", &"rc_medical_wing"))
	_check(entry_flag == "research_complex_discovered_rc_medical_wing" and FacilityIds.is_saveable(entry_flag), "a discovery flag is underscore-only (%s)" % entry_flag)
