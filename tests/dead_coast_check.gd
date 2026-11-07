extends SceneTree
## Dead Coast region checks (headless): godot --headless --path . -s tests/dead_coast_check.gd
## Builder, connectivity (a physics probe really walks the route), keep-clear zones, interactables,
## patrols, persistence and the draw-call budget. Quest flow is in dead_coast_missions_check.gd.

const SCENE: String = "res://scenes/regions/DeadCoast_content.tscn"
const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const DRAW_CALL_BUDGET: int = 140
const WALK_SPEED: float = 6.0

var _failures: int = 0
var _checks: int = 0
var _region: DeadCoast
var _world: Node
var _qm: Node


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
	_qm = root.get_node_or_null("QuestManager")
	if _qm:
		_qm.set("intro_done", true)
		_qm.set("mission_autosave", false)
	_region = (load(SCENE) as PackedScene).instantiate() as DeadCoast
	_region.owns_lighting = false
	root.add_child(_region)
	await _frames(4)

	_test_builder()
	await _test_walkability()
	_test_keep_clear()
	await _test_interactables_reachable()
	await _test_patrols()
	await _test_persistence()
	_test_budget()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_builder() -> void:
	print("-- builder")
	_check(_region.triggers.size() == DeadCoast.AREAS.size() and DeadCoast.AREAS.size() == 7, "seven areas, each with a trigger")
	for area in DeadCoast.AREAS:
		_check(_region.triggers.has(area["id"]), "area trigger exists: %s" % area["name"])
	_check(_region.entry_points.has("beach_arrival") and _region.entry_points.has("from_blackwood"), "two entry points")
	_check(_region.exit_points.has("to_outpost_17") and _region.exit_points.has("to_blackwood"), "two exit points")
	_check(String(_region.exit_points["to_blackwood"]["locked_flag"]) == String(DeadCoast.COMPLETE_FLAG), "the Blackwood exit is locked until the cargo mission is done")
	_check(String(_region.exit_points["to_outpost_17"]["locked_flag"]) == "", "the way back to Outpost 17 is never locked")
	_check(_region.get_meta(&"ambience_name") == "dead_coast" and _region.get_meta(&"region_id") == &"dead_coast", "region metadata for the framework")
	_check(_region.get_node_or_null("Terrain") != null and _region.get_node_or_null("Sea") != null, "terrain and sea exist")
	_check(_region.content.crate_ids.size() >= 10, "at least ten caches and containers (%d)" % _region.content.crate_ids.size())
	_check(_region.content.document_ids.size() >= 8, "at least eight story documents (%d)" % _region.content.document_ids.size())
	_check(_region.content.patrols.size() >= 6, "six patrol groups (%d)" % _region.content.patrols.size())
	var ids: Array[String] = []
	var unique := true
	for id in _region.content.crate_ids + _region.content.document_ids:
		if ids.has(id):
			unique = false
		ids.append(id)
	_check(unique, "every persistent id is unique")
	var namespaced := true
	for id in ids:
		if not id.begins_with("dead_coast_"):
			namespaced = false
	_check(namespaced, "every persistent id carries the dead_coast_ prefix")
	for quest_id in [&"dc_wreckage", &"dc_silent_checkpoint", &"dc_lost_cargo"]:
		_check(_qm != null and _qm.quests.has(quest_id), "quest registered: %s" % quest_id)
	var in_water := 0  # the pier and crane stand in the water on purpose
	for record in _region.props.placed:
		# Shore structures stand in the surf on purpose: the hull wall, the crane legs and the wire along the sea wall.
		var shore_piece: bool = String(record["name"]).begins_with("Hull") or String(record["name"]).begins_with("CraneLeg") or record["name"] == "fence_wire"
		if record["kind"] == "scatter" or record["kind"] == "landmark" or shore_piece:
			continue
		var p: Vector3 = record["pos"]
		if DeadCoastTerrain.inland_distance(p.x, p.z) < 0.0:
			in_water += 1
			print("    in the sea: ", record["name"], " at ", str(p))
	_check(in_water == 0, "no ordinary prop is placed in the sea (%d)" % in_water)


## A real CharacterBody3D walks the main path and both branches (the gate opened first).
func _test_walkability() -> void:
	print("-- walkability")
	# Closed, the barrier really stops the probe in front of it (the route is not bypassable along the coast).
	var closed_main := DeadCoast.main_path()
	var stopped := await _walk(closed_main)
	var gate_index := 0
	for i in closed_main.size():
		if closed_main[i].z <= -118.0:
			gate_index = i
			break
	_check(stopped < closed_main.size() - 1 and stopped <= gate_index, "the closed barrier stops the probe at the gate (reached %d, gate at %d)" % [stopped, gate_index])
	var gate_node := _region.content.nodes["dc_gate"] as Door
	_check(gate_node.locked, "the barrier is locked without the guard pass")
	# ...and it cannot be walked round: not along the inland side (rock) nor along the shoreline (sea wall).
	for d_side in [14.0, 20.0, -2.0]:
		var around: Array[Vector3] = [DeadCoastTerrain.ground(d_side, -108.0), DeadCoastTerrain.ground(d_side, -114.0), DeadCoastTerrain.ground(d_side, -124.0), DeadCoastTerrain.ground(d_side, -130.0)]
		var bypass := await _walk(around)
		_check(bypass < around.size(), "the closed gate cannot be bypassed along d=%.0f (reached %d of %d)" % [d_side, bypass, around.size()])
	var gate := _region.content.nodes["dc_gate"] as Door
	gate.open(false)
	await _frames(2)
	var main := DeadCoast.main_path()
	var reached := await _walk(main)
	_check(reached >= main.size() - 1, "the probe walks the whole main route, arrival to exit (%d/%d points)" % [reached, main.size()])
	var branches := DeadCoast.branch_paths()
	var ramp: Array[Vector3] = branches["watchpoint"]
	var ramp_reached := await _walk(ramp)
	_check(ramp_reached >= ramp.size() - 1, "the probe climbs the ramp to the watchpoint (%d/%d)" % [ramp_reached, ramp.size()])
	var depot: Array[Vector3] = branches["depot"]
	var depot_reached := await _walk(depot)
	_check(depot_reached >= depot.size() - 1, "the probe passes the hidden cleft into the depot (%d/%d)" % [depot_reached, depot.size()])
	# every area is on a walked route
	var walked: Array[Vector3] = []
	walked.append_array(main)
	walked.append_array(ramp)
	walked.append_array(depot)
	for area in DeadCoast.AREAS:
		var rect := _region._area_rect(area)
		var hit := false
		for p in walked:
			if rect.has_point(Vector2(p.x, p.z)):
				hit = true
				break
		_check(hit, "the walked routes enter %s" % area["name"])
	# the gate really blocks until opened (reset it and probe the wall)
	_check(gate.width >= 12.0, "the barrier spans the whole corridor (%.0f m)" % gate.width)


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
			if flat.length() < 1.4:
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
	var arrival: Vector3 = (_region.entry_points["beach_arrival"] as Transform3D).origin
	var main := DeadCoast.main_path()
	var blocked_arrival := 0
	var blocking_route := 0
	for record in _region.props.placed:
		if not bool(record["solid"]) or record["kind"] == "scatter":
			continue
		var pos: Vector3 = record["pos"]
		var flat := Vector2(pos.x, pos.z)
		if _footprint_distance(Vector2(arrival.x, arrival.z), record) < 3.0:
			blocked_arrival += 1
		if record["kind"] == "gate":
			continue
		for p in main:
			if _footprint_distance(Vector2(p.x, p.z), record) < 0.6:
				blocking_route += 1
				print("    on the route: ", record["name"], " at ", str(pos))
				break
	_check(blocked_arrival == 0, "nothing solid within 3 m of the arrival point")
	_check(blocking_route == 0, "no solid prop sits on the main route (%d)" % blocking_route)
	var stacked := 0
	for a in _region.props.placed:
		if a["kind"] != "interactable":
			continue
		for other in _region.props.placed:
			if other == a or other["kind"] != "interactable":
				continue
			if Vector2((a["pos"] as Vector3).x, (a["pos"] as Vector3).z).distance_to(Vector2((other["pos"] as Vector3).x, (other["pos"] as Vector3).z)) < 1.2:
				stacked += 1
	_check(stacked == 0, "no two interactables overlap (%d)" % stacked)
	var purposeless := 0
	for record in _region.props.placed:
		if record["kind"] != "scatter" and String(record["why"]) == "":
			purposeless += 1
	_check(purposeless == 0, "every placed prop records why it is there (%d without)" % purposeless)


## Documents and terminals must not be buried inside a collider.
func _test_interactables_reachable() -> void:
	print("-- interactables")
	var space := _region.get_world_3d().direct_space_state
	var buried := 0
	for id in _region.content.document_ids:
		var item := _region.content.nodes[id] as Node3D
		var query := PhysicsPointQueryParameters3D.new()
		query.position = item.global_position
		query.collision_mask = 1
		if not space.intersect_point(query, 1).is_empty():
			buried += 1
			print("    buried: ", id, " at ", str(item.global_position))
	_check(buried == 0, "no document is inside a solid (%d)" % buried)
	for id in ["dead_coast_radio_wreck", "dead_coast_checkpoint_terminal", "dead_coast_guard_pass"]:
		var item := _region.content.nodes[id] as Node3D
		var query := PhysicsPointQueryParameters3D.new()
		query.position = item.global_position
		query.collision_mask = 1
		_check(space.intersect_point(query, 1).is_empty(), "terminal not buried: %s" % id)
	var below := 0
	for record in _region.props.placed:
		if record["kind"] != "interactable":
			continue
		var p: Vector3 = record["pos"]
		if p.y < DeadCoastTerrain.height(p.x, p.z) - 0.05:
			below += 1
	_check(below == 0, "no interactable sits below the terrain (%d)" % below)


func _test_patrols() -> void:
	print("-- patrols")
	var beach := _region.content.patrols["dead_coast_beach"] as PatrolGroup
	_check(not beach.spawned, "the beach patrol waits for the player")
	(_region.triggers[&"dc_wreckage_beach"] as AreaTrigger).report_entered()
	await _frames(3)
	_check(beach.spawned and beach.enemies.size() == 2, "entering the beach spawns two soldiers (%d)" % beach.enemies.size())
	var on_route := 0
	for enemy in beach.enemies:
		if is_instance_valid(enemy) and enemy.patrol_route != null:
			on_route += 1
	_check(on_route == 2, "both patrollers have a route")
	_region._tick()
	var tagged := 0
	for enemy in beach.enemies:
		if is_instance_valid(enemy) and enemy.loot_table_path == DeadCoast.ENEMY_TABLE_REGULAR:
			tagged += 1
	_check(tagged == 2, "Dead Coast soldiers use the region's loot table")
	# group cap: with four patrollers out a fifth group waits and retries instead of flooding the level
	var camp := _region.content.patrols["dead_coast_camp"] as PatrolGroup
	var cove := _region.content.patrols["dead_coast_cove"] as PatrolGroup
	(_region.triggers[&"dc_cove"] as AreaTrigger).report_entered()
	(_region.triggers[&"dc_coastal_trail"] as AreaTrigger).report_entered()
	await _frames(3)
	_check(Enemy.active_patrollers <= PatrolGroup.MAX_ACTIVE_PATROLLERS, "never more than %d patrollers at once (%d)" % [PatrolGroup.MAX_ACTIVE_PATROLLERS, Enemy.active_patrollers])
	# kill the beach squad: the cleared flag is set and capture reports it
	var attack := load("res://resources/attacks/heavy_1.tres") as AttackData
	for enemy in beach.enemies:
		for i in 6:
			if is_instance_valid(enemy) and not enemy.is_dead():
				enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, 2.0))
				await physics_frame
	await _frames(4)
	_check(_world.has_flag(&"patrol_dead_coast_beach_cleared"), "killing the squad sets patrol_dead_coast_beach_cleared")
	_check((_region.capture_state()["cleared"] as Array).has("dead_coast_beach"), "capture_state lists the cleared beach patrol")
	_check(camp != null and cove != null, "camp and cove groups exist")


func _test_persistence() -> void:
	print("-- persistence")
	var crate := _region.content.nodes["dead_coast_cache_wreck"] as SupplyCrate
	var dummy := Node3D.new()
	root.add_child(dummy)
	var before := _count_pickups()
	_check(crate.interact(dummy), "the wreck cache opens")
	await _frames(4)
	var after_first := _count_pickups()
	_check(after_first > before, "opening it drops loot (%d -> %d)" % [before, after_first])
	_check(not crate.interact(dummy), "an opened cache cannot be opened again")
	var doc := _region.content.nodes["dead_coast_log_cove_ledger"] as LoreDocument
	doc.interact(dummy)
	_check(_world.has_flag(&"doc_dead_coast_log_cove_ledger_found"), "reading a log sets its flag")
	var saved := _region.capture_state()
	_check((saved["claimed"] as Array).has("dead_coast_cache_wreck") and (saved["read"] as Array).has("dead_coast_log_cove_ledger"), "capture_state lists the claimed cache and read log")
	# wipe the world flags and restore: the cache stays shut, nothing is handed out twice
	_world.from_dict({})
	_check(not _world.has_flag(&"dead_coast_cache_wreck_taken"), "(flags wiped)")
	crate.mark_used(false)
	_region.restore_state(saved)
	_check(_world.has_flag(&"dead_coast_cache_wreck_taken"), "restore_state re-claims the cache")
	_check(_world.has_flag(&"patrol_dead_coast_beach_cleared"), "restore_state keeps the beach patrol dead")
	var pickups := _count_pickups()
	_check(not crate.interact(dummy), "after a reload the cache cannot be looted again")
	await _frames(3)
	_check(_count_pickups() == pickups, "nothing is dropped after the reload")
	_region.restore_state({"claimed": [123, "not.an.id"], "read": "oops", "cleared": null, "flags": ["totally_unknown"]})
	_check(not _world.has_flag(&"totally_unknown"), "hostile state data is ignored")
	_region.restore_state("garbage")
	_check(true, "non-dictionary state does not crash")
	dummy.queue_free()


func _count_pickups() -> int:
	return root.find_children("*", "Pickup", true, false).size()


func _test_budget() -> void:
	print("-- budget")
	var draw := 0
	var tris := 0
	for node in _region.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and (node as MeshInstance3D).visible:
			draw += mesh.get_surface_count()
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				if arrays.size() > 0 and arrays[Mesh.ARRAY_VERTEX] != null:
					tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	for node in _region.find_children("*", "MultiMeshInstance3D", true, false):
		draw += 1
	var interactables := _region.find_children("*", "Interactable", true, false).size()
	var bodies := _region.find_children("*", "StaticBody3D", true, false).size()
	print("    draw calls (static + multimesh, interactables add a few): %d, triangles about %d, nodes %d, interactables %d, static bodies %d" % [draw, tris, _region.find_children("*", "Node", true, false).size(), interactables, bodies])
	_check(draw <= DRAW_CALL_BUDGET, "draw calls within the budget of %d (%d)" % [DRAW_CALL_BUDGET, draw])


## Distance in the ground plane from a point to a record's footprint (oriented box when it has one, else a circle).
func _footprint_distance(p: Vector2, record: Dictionary) -> float:
	if not record.has("half"):
		var pos: Vector3 = record["pos"]
		return maxf(p.distance_to(Vector2(pos.x, pos.z)) - float(record["radius"]), 0.0)
	var center: Vector3 = record["center"]
	var local := Basis(Vector3.UP, float(record["yaw"])).inverse() * Vector3(p.x - center.x, 0.0, p.y - center.z)
	var half: Vector2 = record["half"]
	var dx := maxf(absf(local.x) - half.x, 0.0)
	var dz := maxf(absf(local.z) - half.y, 0.0)
	return sqrt(dx * dx + dz * dz)
