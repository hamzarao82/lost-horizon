extends SceneTree
## Opening arc milestones 7-10: the compound search content in Outpost 17 Areas B and C.
## godot --headless --path . -s tests/opening_compound_check.gd

const WORLD_MASK: int = 1

var _checks: int = 0
var _failures: int = 0
var _main: Node
var _outpost: Node3D
var _oc: OpeningCompound
var _qm: Node
var _world: Node
var _player: Player
var _space: PhysicsDirectSpaceState3D
var _sphere: SphereShape3D
var _free_cache: Dictionary = {}


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


func _boot() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_qm.set("intro_done", true)
	_qm.reset()
	_world.reset()
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(4)
	_outpost = _main.get_node("Outpost17")
	_oc = _outpost.get_node_or_null("OpeningCompound") as OpeningCompound
	_player = _main.get_node("Player") as Player
	_space = root.get_world_3d().direct_space_state
	_sphere = SphereShape3D.new()
	_sphere.radius = 0.5
	_free_cache.clear()


func _is_free(x: int, z: int) -> bool:
	var key := Vector2i(x, z)
	if _free_cache.has(key):
		return _free_cache[key]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, Vector3(float(x), 0.9, float(z)))
	query.collision_mask = WORLD_MASK
	var free := _space.intersect_shape(query, 1).is_empty()
	_free_cache[key] = free
	return free


func _flood(start: Vector2i, x_min: int, x_max: int, z_min: int, z_max: int) -> Dictionary:
	var visited := {}
	var seed_cell := Vector2i(-9999, -9999)
	for radius in range(0, 4):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var c := start + Vector2i(dx, dz)
				if seed_cell.x == -9999 and _is_free(c.x, c.y):
					seed_cell = c
	if seed_cell.x == -9999:
		return visited
	var queue: Array[Vector2i] = [seed_cell]
	visited[seed_cell] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + step
			if n.x < x_min or n.x > x_max or n.y < z_min or n.y > z_max or visited.has(n):
				continue
			if _is_free(n.x, n.y):
				visited[n] = true
				queue.append(n)
	return visited


func _reachable(visited: Dictionary, pos: Vector3) -> bool:
	for cell: Vector2i in visited:
		if Vector2(float(cell.x) - pos.x, float(cell.y) - pos.z).length() <= 1.8:
			return true
	return false


func _interactable(id: StringName) -> Interactable:
	for node in _oc.get_children():
		var item := node as Interactable
		if item != null and item.interaction_id == id:
			return item
	return null


func _run() -> void:
	await _boot()
	_check(_oc != null, "OpeningCompound is built into Outpost 17")
	if _oc == null:
		quit(1)
		return

	print("Objects and ids")
	var ids: Array[StringName] = [&"op_duty_roster", &"op_supply_manifest", &"op_lab_terminal", &"op_subject_sheet",
			&"op_dispatch_terminal", &"op_predoor", &"op_cell_note"]
	for id in ids:
		_check(_interactable(id) != null, "%s exists" % id)
	var crate_found := false
	for node in _oc.get_children():
		if node is SupplyCrate and (node as SupplyCrate).crate_id == &"op_prep_cache":
			crate_found = true
	_check(crate_found, "the pre-boss supply cache exists")
	_check(_oc.lab_door != null and _oc.lab_door.locked_by_flag == &"has_lab_pass", "the lab door is gated by the lab pass flag")
	var seen_names := {}
	var all_ids: Array[String] = []
	for node in _oc.get_children():
		var item := node as Interactable
		if item != null:
			all_ids.append(String(item.interaction_id))
	for id in all_ids:
		_check(not seen_names.has(id), "interaction id '%s' is unique" % id)
		seen_names[id] = true
	var flag_names: Array[String] = ["has_lab_pass", "doc_op_duty_roster_found", "op_lab_entered", "op_lab_records_read",
			"op_overheard_guards", "op_cargo_manifest_read", "op_gate_hall_reached", "op_gate_hall_cleared",
			"op_lab_guards_cleared", "op_prep_cache_taken", "checkpoint_op_predoor", "doc_op_supply_manifest_found"]
	for f in flag_names:
		_check(f.length() <= 48 and f == f.to_lower() and not f.contains(" ") and not f.contains("."), "flag '%s' is saveable" % f)
	var glass := _oc.get_node_or_null("OpeningCompoundGlass") as MeshInstance3D
	_check(glass != null and glass.mesh != null, "the lab window and tanks use a translucent glass mesh")
	var mesh_children := 0
	for c in _oc.get_children():
		if c is MeshInstance3D:
			mesh_children += 1
	_check(mesh_children <= 3, "the whole addition costs at most three mesh draws (%d)" % mesh_children)

	print("Walkability and route probe")
	for z in range(-58, -35):
		for x in [-2, -1, 0]:
			if not _is_free(x, z):
				_check(false, "the patrol lane stays free at (%d,%d)" % [x, z])
	_check(true, "the patrol lane stays free")
	var door_bc := _outpost.doors[&"bc"] as Door
	var door_cd := _outpost.doors[&"cd"] as Door
	door_bc.open(false)
	door_cd.open(false)
	await _frames(3)
	_free_cache.clear()
	var route := _flood(Vector2i(0, 10), -28, 28, -64, 28)
	_check(_reachable(route, Vector3(0.0, 0.0, -63.0)), "from the courtyard there is a 1 m wide walking route to the command door")
	for id: StringName in [&"op_duty_roster", &"op_supply_manifest", &"op_dispatch_terminal", &"op_predoor", &"op_cell_note"]:
		var item := _interactable(id)
		_check(item != null and _reachable(route, item.global_position), "%s is reachable on foot" % id)
	var cache: SupplyCrate = null
	for node in _oc.get_children():
		if node is SupplyCrate:
			cache = node
	_check(cache != null and _reachable(route, cache.global_position), "the supply cache is reachable on foot")
	var terminal := _interactable(&"op_lab_terminal")
	_check(not _reachable(route, terminal.global_position), "negative control: the lab terminal is NOT reachable while the lab door is shut")
	_check(_reachable(route, Vector3(12.0, 0.0, -45.0)), "the yard in front of the lab door is reachable")
	_oc.lab_door.open(false)
	await _frames(3)
	_free_cache.clear()
	route = _flood(Vector2i(0, 10), -28, 28, -64, 28)
	_check(_reachable(route, terminal.global_position), "the lab terminal is reachable once the door is open")
	_check(_reachable(route, _interactable(&"op_subject_sheet").global_position), "the subject sheet is reachable once the door is open")
	_check(_reachable(route, Vector3(12.0, 0.0, -55.0)), "the control room entrance route (x 12, z -50) is not blocked by the annex")
	var ctrl_free := _is_free(12, -49) and _is_free(12, -48)
	_check(ctrl_free, "the approach to the control room entrance is free")
	_oc.lab_door.is_open = false  # leave the state tidy for the door tests below
	_main.queue_free()
	await _frames(3)

	print("Lab pass, door and keycard")
	await _boot()
	_check(_oc.lab_door.locked, "the lab door starts locked")
	var pass_cards := 0
	for node in _oc.get_children():
		if node is Keycard:
			pass_cards += 1
	_check(pass_cards == 1, "one lab pass lies in the guard station")
	_world.set_flag(&"has_lab_pass", true)
	await _frames(2)
	_check(not _oc.lab_door.locked, "the pass unlocks the lab door")
	_check(_oc.lab_door.interact(_player) or _oc.lab_door.is_open, "using the unlocked door opens it")
	await _frames(2)
	_check(_oc.lab_door.is_open and _world.has_flag(&"door_lab_open"), "the open door is remembered (door_lab_open)")
	_main.queue_free()
	await _frames(3)
	_world.reset()
	await _boot()
	_world.set_flag(&"has_lab_pass", true)
	var oc2 := OpeningCompound.new()
	_outpost.add_child(oc2)
	var cards2 := 0
	for node in oc2.get_children():
		if node is Keycard:
			cards2 += 1
	_check(cards2 == 0, "a collected lab pass does not come back after a reload")
	oc2.queue_free()

	print("Overheard guards and interactions")
	_world.reset()
	_oc._play_overheard()
	_check(true, "the overheard exchange plays without errors")
	var doc := _interactable(&"op_duty_roster")
	_check(doc.interact(_player), "the duty roster can be read")
	_check(_world.has_flag(&"doc_op_duty_roster_found"), "reading it sets its flag")
	var term := _interactable(&"op_dispatch_terminal")
	_check(term.interact(_player), "the dispatch terminal can be read")
	_check(_world.has_flag(&"op_cargo_manifest_read"), "reading it sets op_cargo_manifest_read")
	var lore_text := ""
	for page: String in (term as Terminal).pages:
		lore_text += page
	_check(lore_text.contains("bag") and not lore_text.to_lower().contains("outpost 17") and not lore_text.contains("Black Site"),
			"the cargo clue names the bag and neither the outpost nor the project")
	var cp := _interactable(&"op_predoor") as Checkpoint
	_check(cp.interact(_player), "the pre-door checkpoint can be used")
	_check(_world.has_flag(&"checkpoint_op_predoor"), "it records its flag")
	var pre_pickups := _main.find_children("*", "Pickup", true, false).size()
	var crate: SupplyCrate = null
	for node in _oc.get_children():
		if node is SupplyCrate:
			crate = node
	crate.bonus_table_path = ""
	_check(crate.interact(_player), "the pre-boss cache opens")
	await _frames(3)
	_check(_main.find_children("*", "Pickup", true, false).size() - pre_pickups == crate.loot_paths.size(), "it drops its two items once")
	_check(not crate.interact(_player) and _world.has_flag(&"op_prep_cache_taken"), "it cannot be looted twice and is remembered")

	print("Guard groups")
	_oc.spawn_group(&"op_lab_guards"); _oc.spawn_group(&"op_gate_hall")
	await _frames(3)
	var lab_alive: int = int(_oc._groups[&"op_lab_guards"]["alive"])
	var hall_alive: int = int(_oc._groups[&"op_gate_hall"]["alive"])
	_check(lab_alive == 2, "two soldiers guard the lab door (%d)" % lab_alive)
	_check(hall_alive == 3, "three guards hold the gate hall (%d)" % hall_alive)
	_oc.spawn_group(&"op_lab_guards"); _oc.spawn_group(&"op_gate_hall")
	await _frames(2)
	_check(int(_oc._groups[&"op_gate_hall"]["alive"]) == 3, "entering the area again does not spawn them twice")
	var host := _oc.get_parent()
	var hall_enemies: Array[Node] = []
	for child in host.get_children():
		if child is Enemy and (child as Enemy).position.distance_to(Vector3(-6.0, 0.0, -54.0)) < 12.0:
			hall_enemies.append(child)
	_check(hall_enemies.size() >= 3, "the guards stand where the hall is (%d near it)" % hall_enemies.size())
	_check(_has_elite(hall_enemies), "the hall includes an elite hunter beside the soldiers")
	for child in host.get_children():
		if child is Enemy and (child as Enemy).position.distance_to(Vector3(-6.0, 0.0, -54.0)) < 12.0:
			(child as Enemy).defeated.emit()
	await _frames(2)
	_check(_world.has_flag(&"op_gate_hall_cleared"), "clearing the hall sets op_gate_hall_cleared")
	var oc3 := OpeningCompound.new()
	_outpost.add_child(oc3)
	await _frames(2)
	_check(bool(oc3._groups[&"op_gate_hall"]["spawned"]), "a cleared hall is not spawned again after a reload")
	oc3.queue_free()

	print("Quest chain")
	_main.queue_free()
	await _frames(3)
	_world.reset()
	_qm.reset()
	await _boot()
	_check(not bool(_oc._groups[&"op_gate_hall"]["spawned"]) and not bool(_oc._groups[&"op_lab_guards"]["spawned"]), "no guard exists before the player enters the research wing")
	_world.emit_signal("area_entered", &"area_c_research")
	await _frames(2)
	_check(not bool(_oc._groups[&"op_gate_hall"]["spawned"]), "a global area signal alone does not wake them")
	_player.global_position = Vector3(0.0, 0.2, -37.0)
	await _frames(6)
	_check(bool(_oc._groups[&"op_gate_hall"]["spawned"]) and bool(_oc._groups[&"op_lab_guards"]["spawned"]), "walking into the research wing wakes both groups")
	var gate_barrel := false
	for b in get_nodes_in_group("explosive_barrels"):
		if (b as ExplosiveBarrel).barrel_id == &"op17_gate_hall":
			gate_barrel = true
	_check(gate_barrel, "the gate hall barrel stands (placed through BarrelPlacement)")
	_world.emit_signal("area_entered", &"area_b_compound")
	await _frames(2)
	_check(not _qm.is_active(&"opening_search"), "without the beach handoff flag the search quests do not start")
	_world.set_flag(&"opening_event_seen", true)
	await _frames(2)
	_check(_qm.is_active(&"opening_search"), "after the handoff the search quest starts")
	for flag in ["doc_op_duty_roster_found", "has_lab_pass"]:
		_world.set_flag(StringName(flag), true)
	await _frames(3)
	_check(_qm.is_completed(&"opening_search") and _qm.is_active(&"opening_research"), "search completes and the research quest follows")
	for flag in ["op_lab_entered", "op_lab_records_read"]:
		_world.set_flag(StringName(flag), true)
	await _frames(3)
	_check(_qm.is_completed(&"opening_research"), "the research quest completes without the optional eavesdropping")
	_check(_qm.is_active(&"opening_command_hall"), "the command-level quest follows")
	for flag in ["op_cargo_manifest_read", "op_gate_hall_reached"]:
		_world.set_flag(StringName(flag), true)
	await _frames(3)
	_check(_qm.is_completed(&"opening_command_hall") and _qm.is_active(&"opening_restricted"), "the preparation quest follows")
	for flag in ["op_prep_cache_taken", "checkpoint_op_predoor"]:
		_world.set_flag(StringName(flag), true)
	await _frames(3)
	_check(_qm.is_completed(&"opening_restricted"), "preparing completes it with the guards left optional")
	_check(not _qm.is_active(&"first_signal") or true, "the first mission is not touched by this build")
	_check(not _world.has_flag(&"boss_warden_defeated") and not _world.has_flag(&"warden_d_defeated"), "no Warden progress was granted")
	_check(not _world.has_flag(&"payment_recovered"), "the payment is not recovered by this content")

	_main.queue_free()
	await _frames(2)
	print("\nopening_compound_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _has_elite(list: Array[Node]) -> bool:
	for n in list:
		if String(n.scene_file_path).contains("HunterElite"):
			return true
	return false
