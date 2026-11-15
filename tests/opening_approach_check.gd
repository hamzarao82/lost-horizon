extends SceneTree
## Opening Milestones 3 to 5 (Area A): the berm that screens the compound, the two routes (direct and bypass), the
## rise with a ramp, the fence with a cranked gate and a cut, the patrols, the walkers, the quests and their chain.
##   godot --headless --path . -s tests/opening_approach_check.gd

var _checks: int = 0
var _failures: int = 0
var _main: Node
var _approach: OpeningApproach
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


func _clear(path: Vector3, radius: float = 0.4) -> bool:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.collision_mask = 1
	params.transform = Transform3D(Basis.IDENTITY, path)
	return space.intersect_shape(params, 1).is_empty()


## Samples the polyline every 0.4 m with a sphere and reports the first blocked point (or null).
func _route_blocked(points: Array[Vector3]) -> Variant:
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var steps := int(ceil(a.distance_to(b) / 0.4))
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(maxi(steps, 1)))
			if not _clear(p):
				return p
	return null


func _run() -> void:
	_world = root.get_node("WorldState")
	_qm = root.get_node("QuestManager")
	_world.reset()
	_qm.reset()
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	await _frames(4)
	_approach = _main.find_child("OpeningApproach", true, false) as OpeningApproach
	_check(_approach != null, "Outpost 17 builds an OpeningApproach through its one hook line")
	if _approach == null:
		quit(1)
		return
	_test_data()
	await _test_routes()
	await _test_screen_and_ramp()
	await _test_quests()
	await _test_patrols_and_walkers()
	print("opening_approach_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("-- data")
	for path in ["res://resources/quests/campaign/opening_trail.tres", "res://resources/quests/campaign/opening_perimeter.tres"]:
		var quest := load(path) as QuestData
		_check(quest != null and not quest.objectives.is_empty(), "%s loads with objectives" % path.get_file())
		if quest == null:
			continue
		var s := String(quest.id)
		_check(s.length() <= 48 and s == s.to_lower() and s.is_valid_identifier(), "quest id '%s' is save-safe" % s)
		for obj in quest.objectives:
			for t in obj.targets:
				_check(_approach.triggers.has(StringName(t)), "objective '%s' targets a real trigger (%s)" % [obj.id, t])
	var trail := load("res://resources/quests/campaign/opening_trail.tres") as QuestData
	_check(trail.next_quest == &"opening_perimeter", "the trail hands over to the perimeter quest")
	_check(trail.objectives[0].text.begins_with("Follow the trail"), "the first objective reads 'Follow the trail inland'")
	var perimeter := load("res://resources/quests/campaign/opening_perimeter.tres") as QuestData
	_check(perimeter.objectives[0].text.begins_with("Find a way inside"), "then 'Find a way inside'")
	_check(perimeter.objectives[1].text.begins_with("Get past the security perimeter"), "then 'Get past the security perimeter'")
	for id in [&"supply_crate_a1", &"checkpoint_trail_end", &"perimeter_crank", &"perimeter_crank_turned", &"settlement_seen", &"opening_trail_start"]:
		var s := String(id)
		_check(s.length() <= 48 and s == s.to_lower() and s.replace("_", "").is_valid_identifier(), "id '%s' is save-safe" % s)
	var forbidden := ["outpost", "black site", "director"]
	var text := (OpeningApproach.VIEW_CAPTION + " " + OpeningApproach.FENCE_CAPTION).to_lower()
	var clean := true
	for word in forbidden:
		clean = clean and not text.contains(word)
	_check(clean, "the captions never name the place, the project or its leader")
	var jump_apex := pow(6.0, 2.0) / (2.0 * float(ProjectSettings.get_setting("physics/3d/default_gravity")))
	_check(jump_apex > 0.8 + 0.4, "the fallen log (0.8 m) can be jumped (apex %.2f m)" % jump_apex)
	var run := 61.0 - OpeningApproach.BERM_Z1
	var angle := rad_to_deg(atan2(OpeningApproach.DECK_H, run))
	_check(angle < 40.0, "the ramp to the rise is walkable (%.1f degrees)" % angle)


func _test_routes() -> void:
	print("-- routes")
	await _frames(2)
	var direct: Array[Vector3] = [Vector3(0.0, 0.9, 64.0), Vector3(0.0, 0.9, 50.0), Vector3(0.0, 0.9, 46.0)]
	_check(_route_blocked(direct) == null, "the direct way from the spawn to the fence is open through the gap")
	var through_gate: Array[Vector3] = [Vector3(0.0, 0.9, 46.0), Vector3(0.0, 0.9, 40.0)]
	_check(_route_blocked(through_gate) != null, "the gate blocks the direct way until it is opened")
	_approach.gate.open(false)
	await _frames(3)
	_check(_route_blocked(through_gate) == null, "an opened gate lets the direct route reach the checkpoint area")
	var bypass: Array[Vector3] = [Vector3(26.0, 0.9, 64.0), Vector3(26.0, 0.9, 50.0), Vector3(26.0, 0.9, 49.6),
			Vector3(17.0, 0.9, 49.6), Vector3(17.0, 0.9, 47.0), Vector3(19.0, 0.9, 45.6), Vector3(19.0, 0.9, 40.0)]
	_check(_route_blocked(bypass) == null, "the bypass reaches the same point through the bushes and the cut in the fence")
	var low_log: Array[Vector3] = [Vector3(26.0, 0.3, 50.0), Vector3(26.0, 0.3, 47.0)]
	_check(_route_blocked(low_log) != null, "a walker at ground level is stopped by the log")
	var around_fence: Array[Vector3] = [Vector3(-20.0, 0.9, 49.6), Vector3(-20.0, 0.9, 40.0)]
	_check(_route_blocked(around_fence) != null, "the fence cannot be walked through away from the gate or the cut")
	var east_edge: Array[Vector3] = [Vector3(40.0, 0.9, 49.0), Vector3(40.0, 0.9, 40.0)]
	_check(_route_blocked(east_edge) != null, "nor around its east end")


func _test_screen_and_ramp() -> void:
	print("-- screen and rise")
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var camera := Vector3(0.0, 4.5, 68.0)
	var hidden := 0
	var tested := 0
	for x in [-34.0, -22.0, -10.0, 10.0, 22.0, 34.0]:
		var target := Vector3(float(x), 4.0, 30.0)
		var query := PhysicsRayQueryParameters3D.create(camera, target, 1)
		var hit := space.intersect_ray(query)
		tested += 1
		if not hit.is_empty():
			var collider := hit["collider"] as Node
			if collider != null and (collider.name.begins_with("Berm") or collider.name.begins_with("View")):
				hidden += 1
	_check(hidden == tested, "from the spawn the berm hides the compound wall away from the gaps (%d of %d lines)" % [hidden, tested])
	var surface_y := OpeningApproach.DECK_H
	var on_deck := Vector3(14.0, surface_y + 0.9, 52.0)
	_check(_clear(on_deck, 0.4), "there is standing room on the rise")
	var climb: Array[Vector3] = [Vector3(14.0, 0.9, 63.0), Vector3(14.0, 0.9 + 0.2, 61.0)]
	_check(_route_blocked(climb) == null, "the foot of the ramp is open")
	var viewpoint_fires: Array = [false]
	_approach.triggers[&"opening_viewpoint"].entered.connect(func(_id: StringName) -> void: viewpoint_fires[0] = true)
	_approach.triggers[&"opening_viewpoint"].report_entered()
	_check(viewpoint_fires[0] and _world.has_flag(&"settlement_seen"), "the viewpoint reports and sets settlement_seen")


func _test_quests() -> void:
	print("-- quests")
	_qm.reset()
	_world.reset()
	var started := _approach.try_start_quest()
	_check(not started and not _qm.is_active(&"opening_trail"), "the trail does not start before the opening has handed over control")
	_world.set_flag(&"opening_event_seen", true)
	_approach._started = false
	started = _approach.try_start_quest()
	_check(started and _qm.is_active(&"opening_trail"), "once the opening has finished, The Trail starts")
	_approach.triggers[&"opening_trail_gap"].report_entered()
	await _frames(2)
	_check(_qm.is_completed(&"opening_trail") and _qm.is_active(&"opening_perimeter"), "the gap completes the trail and starts the perimeter quest")
	_approach.triggers[&"opening_fence_reached"].report_entered()
	await _frames(2)
	_check(_world.has_flag(&"fence_seen"), "reaching the fence sets fence_seen")
	_check(not _qm.is_completed(&"opening_perimeter"), "reaching the fence is not yet getting past it")
	_approach.triggers[&"opening_perimeter_in"].report_entered()
	await _frames(2)
	_check(_qm.is_completed(&"opening_perimeter"), "passing the fence completes the perimeter quest")
	_check(_approach.gate.locked_by_flag == &"perimeter_crank_turned" and _approach.control.finish_flag == &"perimeter_crank_turned", "the gate is unlocked by the crank box's own flag")
	_check(not _world.has_flag(&"perimeter_crank_turned"), "the flag is not set until the crank is used")


func _test_patrols_and_walkers() -> void:
	print("-- patrols and walkers")
	var before := Enemy.active_patrollers
	_world.emit_area_entered(OpeningApproach.START_AREA)
	await _frames(3)
	_check(_approach.patrol_trail.spawned and _approach.patrol_trail.enemies.size() == 2, "two guards walk the trail beside the gap")
	_check(_approach.patrol_gate.spawned and _approach.patrol_gate.enemies.size() == 1, "one guard watches the gate")
	_check(Enemy.active_patrollers - before <= PatrolGroup.MAX_ACTIVE_PATROLLERS, "within the active patroller cap")
	var route_ok := true
	for enemy in _approach.patrol_trail.enemies:
		route_ok = route_ok and absf(enemy.global_position.z - 47.0) < 3.0
	_check(route_ok, "the trail guards start on their beat just north of the berm")
	_check(_approach.walkers.size() == 4, "four distant figures work the yard (three workers, one guard)")
	var guard_count := 0
	for walker in _approach.walkers:
		if walker.guard:
			guard_count += 1
	_check(guard_count == 1, "one of them is armed")
	var walker := _approach.walkers[0]
	var start := walker.position
	for i in 20:
		walker.advance(0.1)
	_check(walker.position.distance_to(start) > 0.5, "a worker walks along its path")
	var player := get_first_node_in_group("player") as Player
	player.global_position = Vector3(0.0, 0.1, 64.0)
	await _frames(2)
	walker._check = 0.0
	walker.advance(0.1)
	_check(walker.awake, "within view distance the figures are active")
	player.global_position = Vector3(0.0, 0.1, 400.0)
	walker._check = 0.0
	walker.advance(0.1)
	_check(not walker.awake, "far away they sleep")
