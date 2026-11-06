extends SceneTree
## Blackwood region (headless): godot --headless --path . -s tests/blackwood_check.gd
## Layout, connectivity, vegetation rules, the frequency puzzle, the ambush, the ally alert, the gate,
## flag ids and budgets. Luminance and real draw calls need a window: see docs/BLACKWOOD.md.

const HEAVY: String = "res://resources/attacks/heavy_1.tres"

var _checks: int = 0
var _failures: int = 0
var _world: Node
var _region: Blackwood


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


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _fresh_region() -> Blackwood:
	if _region != null and is_instance_valid(_region):
		_region.queue_free()
		await _frames(2)
	_world.reset()
	var region := load("res://scenes/regions/Blackwood_content.tscn").instantiate() as Blackwood
	root.add_child(region)
	await _frames(3)
	_region = region
	return region


func _run() -> void:
	_world = root.get_node("WorldState")
	await _fresh_region()
	_test_layout()
	await _test_connectivity()
	_test_vegetation()
	_test_budgets()
	_test_flags_and_exits()
	await _test_puzzle()
	await _test_gate()
	await _test_ambush()
	await _test_alert_hook()
	_test_environment()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_layout() -> void:
	print("Layout")
	_check(Blackwood.area_ids().size() == 7, "seven areas are defined")
	var triggers := _region.find_children("Trigger_*", "AreaTrigger", true, false)
	_check(triggers.size() == 8, "seven area triggers plus the ambush trigger exist (%d)" % triggers.size())
	var ids := {}
	for a in Blackwood.AREAS:
		ids[a["area"]] = true
	_check(ids.size() == 7, "area ids are unique")
	_check(_region.region_id == &"blackwood" and _region.ambience_name == "blackwood", "region id and ambience metadata")
	_check(_region.entry_points.has(&"from_dead_coast") and _region.entry_points.has(&"from_underground"), "both entry points exist")
	_check(_region.exit_points.has(&"to_dead_coast") and _region.exit_points.has(&"to_research_complex"), "both exit points exist")
	var quests := root.get_node("QuestManager")
	var all_valid := true
	for id: StringName in [&"into_the_blackwood", &"ghost_frequency", &"experimental_site"]:
		var q := quests.get_quest(id) as QuestData
		all_valid = all_valid and q != null and q.validate().is_empty()
	_check(all_valid, "the three quests are registered and valid")


func _ray_hit(a: Vector2, b: Vector2, height: float) -> Dictionary:
	var space := _region.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(a.x, height, a.y), Vector3(b.x, height, b.y))
	query.collision_mask = 1
	return space.intersect_ray(query)


func _ray_blocked(a: Vector2, b: Vector2, height: float) -> bool:
	return not _ray_hit(a, b, height).is_empty()


func _walk(route: Array[Vector2]) -> int:
	var blocked := 0
	for i in route.size() - 1:
		for h in [0.5, 1.5]:
			var hit := _ray_hit(route[i], route[i + 1], h)
			if not hit.is_empty():
				blocked += 1
				print("  info blocked %s -> %s at height %.1f by %s at %s" % [route[i], route[i + 1], h, (hit["collider"] as Node).name, hit["position"]])
	return blocked


func _test_connectivity() -> void:
	print("Connectivity")
	await _frames(3)
	var gate_before := _ray_blocked(Vector2(-10.0, -182.0), Vector2(-10.0, -188.0), 1.5)
	_check(gate_before, "the concealed gate blocks the route while closed")
	_world.set_flag(&"blackwood_gate_open", true)
	await _frames(3)
	_check(_walk(Blackwood.ROUTE) == 0, "the whole main route is free of blocking colliders once the gate is open")
	_check(_walk(Blackwood.BRANCH_ROUTE) == 0, "the branch to the communications station is free")
	var all_in := true
	for p in Blackwood.ROUTE:
		all_in = all_in and Blackwood.BOUNDS.has_point(p)
	_check(all_in, "the route stays inside the region bounds")
	var areas_on_route := 0
	for a in Blackwood.AREAS:
		if a["id"] == "comms_station":
			continue
		var best := INF
		for p in Blackwood.ROUTE:
			best = minf(best, Blackwood.area_rect(a).get_center().distance_to(p))
		if best < 30.0:
			areas_on_route += 1
	_check(areas_on_route == 6, "six areas lie on the main route, the station on the branch (%d)" % areas_on_route)
	_world.set_flag(&"blackwood_gate_open", false)
	await _frames(2)


func _test_vegetation() -> void:
	print("Vegetation")
	var placed := Blackwood.generate_vegetation(1.0)
	var bad := 0
	var total := 0
	for species: String in placed:
		for xf: Transform3D in placed[species]:
			total += 1
			if Blackwood.is_walkable(Vector2(xf.origin.x, xf.origin.z), 1.0):
				bad += 1
	_check(total > 400, "dense vegetation is generated (%d plants)" % total)
	_check(bad == 0, "no plant grows on the trail or inside an area (%d violations)" % bad)
	var again := Blackwood.generate_vegetation(1.0)
	_check(str(again["bush"][5]) == str(placed["bush"][5]) and again["bush"].size() == placed["bush"].size(), "placement is deterministic for the seed")
	var low := Blackwood.generate_vegetation(0.4)
	var low_total := 0
	for species: String in low:
		low_total += low[species].size()
	_check(low_total < total * 0.5, "the low quality scale thins the jungle (%d vs %d)" % [low_total, total])
	var trees := 0
	for species in ["palm_a", "palm_b"]:
		trees += placed[species].size()
	_check(trees >= 200, "tall trees dominate (%d)" % trees)


func _test_budgets() -> void:
	print("Budgets")
	var meshes := _region.find_children("*", "MeshInstance3D", true, false).size()
	var multis := _region.find_children("*", "MultiMeshInstance3D", true, false).size()
	print("  info mesh instances %d, multimesh instances %d" % [meshes, multis])
	_check(meshes + multis <= 160, "the region stays within 160 drawable nodes (%d)" % (meshes + multis))
	_check(multis <= 40, "vegetation uses at most 40 multimesh cells (%d)" % multis)


func _test_flags_and_exits() -> void:
	print("Flags and exits")
	var ok := true
	var longest := 0
	for id in ["blackwood_ambush_cleared", "blackwood_comms_power", "blackwood_transmissions_read", "blackwood_black_site_link",
			"blackwood_gate_open", "blackwood_site_defenders_cleared", "blackwood_research_complex_access", "doc_bw_log_patrol_1_found",
			"doc_bw_log_subject_list_found", "blackwood_crate_station_taken", "blackwood_perimeter_elites_cleared"]:
		longest = maxi(longest, id.length())
		for i in id.length():
			var c: int = id.unicode_at(i)
			if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
				ok = false
	_check(ok and longest <= 48, "flag ids only use a-z 0-9 _ and fit the 48 character limit (longest %d)" % longest)
	_check(_region.exit_locked(&"to_research_complex"), "the Research Complex exit is locked at first")
	_check(not _region.exit_locked(&"to_dead_coast"), "the way back to Dead Coast is never locked")
	_world.set_flag(&"blackwood_research_complex_access", true)
	_check(not _region.exit_locked(&"to_research_complex"), "the Research Complex exit opens with the access flag")
	_world.set_flag(&"blackwood_research_complex_access", false)


func _test_puzzle() -> void:
	print("Frequency puzzle")
	await _fresh_region()
	var p := _region.puzzle
	_check(p != null and not p.is_solved, "the puzzle starts unsolved")
	p.turn(0)
	p.turn(1)
	_check(p.dials == [1, 1, 0], "dials advance one step per turn")
	var wrong := p.transmit()
	_check(not wrong and p.dials == [0, 0, 0], "a wrong transmission resets the dials only")
	_check(not _world.has_flag(&"blackwood_comms_power"), "a wrong transmission sets no flag")
	# Capture and restore after every dial: the puzzle is never stuck on a half-set board.
	var steps_ok := true
	for dial in 3:
		while p.dials[dial] != FrequencyPuzzle.CODE[dial]:
			p.turn(dial)
		var before: Array[int] = p.dials.duplicate()
		p.restore_state(p.capture_state())
		steps_ok = steps_ok and p.dials == before
	_check(steps_ok and p.dials == FrequencyPuzzle.CODE, "dials survive capture and restore after each step")
	_check(p.transmit() and p.is_solved, "the right channel solves it")
	_check(_world.has_flag(&"blackwood_comms_power"), "solving sets blackwood_comms_power")
	p.turn(0)
	_check(p.dials == FrequencyPuzzle.CODE, "a solved puzzle ignores further turns")
	# Hostile data falls back safely and a world flag keeps it solved.
	p.restore_state({"dials": ["x", 99999, null], "solved": "yes"})
	_check(p.is_solved and p.dials == FrequencyPuzzle.CODE, "restoring hostile data keeps the flagged solution")
	_world.set_flag(&"blackwood_comms_power", false)
	p.restore_state({"dials": ["x", 99999, -5], "solved": true})
	_check(not p.is_solved and p.dials[1] == 9 and p.dials[2] == 0 and p.dials[0] == 0, "hostile data is clamped and never trusts 'solved' without the flag")
	var worst := 0
	for start in [0, 5, 9]:
		worst = maxi(worst, (FrequencyPuzzle.CODE[0] - start + 10) % 10)
	_check(worst <= FrequencyPuzzle.DIAL_MAX, "any dial reaches its target within 9 turns (no soft lock)")


func _test_gate() -> void:
	print("Gate")
	await _fresh_region()
	var disabled := _region.gate_body.get_child(0) as CollisionShape3D
	_check(not disabled.disabled and _region.gate_mesh.visible, "the gate starts closed")
	_world.set_flag(&"blackwood_gate_open", true)
	await _frames(3)
	_check(disabled.disabled and not _region.gate_mesh.visible, "the gate opens with its flag")
	var saved := _region.capture_state()
	_check(saved["gate_open"] == true, "capture_state records the open gate")
	await _fresh_region()
	_check(not (_region.gate_body.get_child(0) as CollisionShape3D).disabled, "a new world starts with the gate closed")
	_region.restore_state(saved)
	await _frames(3)
	_check((_region.gate_body.get_child(0) as CollisionShape3D).disabled, "restore_state reopens the gate")
	# The panel is locked until the station's transmissions were read (no way to skip it by accident).
	var panel: Terminal = null
	for t in _region.find_children("*", "Terminal", true, false):
		if (t as Terminal).interaction_id == &"bw_gate_panel":
			panel = t
	_world.set_flag(&"blackwood_transmissions_read", false)
	panel._refresh_lock()
	_check(panel != null and panel.locked, "the gate panel is locked before the transmissions were read")
	_world.set_flag(&"blackwood_transmissions_read", true)
	await _frames(2)
	_check(not panel.locked, "the gate panel unlocks once they were read")


func _kill_all(encounter: BlackwoodEncounter) -> void:
	var kill := load(HEAVY) as AttackData
	for e in encounter.enemies:
		for i in 12:
			if is_instance_valid(e) and not e.is_dead():
				e.receive_hit(kill, e.global_position + Vector3(0.0, 0.0, 2.0))


func _test_ambush() -> void:
	print("Ambush")
	await _fresh_region()
	var ambush: BlackwoodEncounter = _region.encounters[&"ambush"]
	var warnings := [0]
	ambush.warning.connect(func() -> void: warnings[0] += 1)
	_check(ambush.enemies.is_empty(), "nobody exists before the trigger")
	_world.emit_area_entered(&"blackwood_ambush_zone")
	_check(warnings[0] == 1, "the warning cue fires immediately")
	_check(ambush.enemies.is_empty(), "the enemies wait for the warning window")
	await _seconds(1.0)
	_check(ambush.enemies.is_empty(), "still nobody 1.0 s after the warning")
	await _seconds(0.8)
	_check(ambush.enemies.size() == 3, "three attackers appear after about 1.5 s (%d)" % ambush.enemies.size())
	var all_coordinated := true
	for e in ambush.enemies:
		all_coordinated = all_coordinated and e.coordinate_alarm
	_check(all_coordinated, "the attackers coordinate their alarm")
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(0.3)
	_check(ambush.enemies.size() == 3 and warnings[0] == 1, "re-entering does not trigger it twice")
	_kill_all(ambush)
	await _frames(4)
	_check(_world.has_flag(&"blackwood_ambush_cleared"), "clearing it sets blackwood_ambush_cleared")
	var saved_flags: Dictionary = _world.to_dict()
	_region.queue_free()
	await _frames(2)
	_world.from_dict(saved_flags)
	var fresh := load("res://scenes/regions/Blackwood_content.tscn").instantiate() as Blackwood
	root.add_child(fresh)
	_region = fresh
	await _frames(3)
	var again: BlackwoodEncounter = fresh.encounters[&"ambush"]
	_world.emit_area_entered(&"blackwood_ambush_zone")
	await _seconds(2.0)
	_check(again.is_cleared and again.enemies.is_empty(), "a cleared ambush never returns after a reload")
	_world.reset()


func _spawn_enemy(x: float, coordinate: bool) -> Enemy:
	var e := load("res://scenes/enemies/PatrolSoldier.tscn").instantiate() as Enemy
	e.position = Vector3(x, 0.0, 0.0)
	e.coordinate_alarm = coordinate
	root.add_child(e)
	e.set_physics_process(false)
	return e


func _test_alert_hook() -> void:
	print("Ally alert")
	var a := _spawn_enemy(300.0, true)
	var near := _spawn_enemy(306.0, false)
	var far := _spawn_enemy(330.0, false)
	await _frames(2)
	a._alert()
	_check(near.state == Enemy.State.CHASE, "an ally within 10 m joins the chase")
	_check(far.state != Enemy.State.CHASE, "an enemy 30 m away is not alerted")
	var quiet := _spawn_enemy(400.0, false)
	var quiet_ally := _spawn_enemy(403.0, false)
	await _frames(2)
	quiet._alert()
	_check(quiet_ally.state != Enemy.State.CHASE, "without the opt-in flag nobody else is alerted (existing behaviour)")
	for e in [a, near, far, quiet, quiet_ally]:
		e.queue_free()
	await _frames(2)


func _test_environment() -> void:
	print("Environment")
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	Blackwood.apply_environment(we)
	_check(we.environment.fog_enabled and we.environment.fog_density <= 0.02, "fog is on but light enough to read through")
	_check(we.environment.ambient_light_energy >= 0.6, "ambient light keeps a readability floor")
	we.free()
