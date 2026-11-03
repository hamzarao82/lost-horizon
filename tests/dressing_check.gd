extends SceneTree
## Set-dressing checks (headless): godot --headless --path . -s tests/dressing_check.gd
##
## Reachability method: a 1 m grid is laid over each area. A cell is "free" when a sphere of radius 0.5
## (a 1.0 m wide body) at height 0.9 overlaps nothing on the world layer (physics shape query, layer 1).
## A 4-connected flood fill starts just inside the area's entrance; a target is reachable when a visited
## cell lies within 1.8 m of it. 1 m steps between free cells mean every path is at least 1.0 m wide.

const WORLD_MASK: int = 1

# Area rectangles for the grid (x_min, x_max, z_min, z_max) just inside the walls, and flood-fill starts.
const AREAS: Dictionary = {
	&"A": [-41, 41, 31, 79, Vector2i(0, 64)],
	&"B": [-28, 28, -28, 28, Vector2i(0, 10)],
	&"C": [-21, 21, -60, -32, Vector2i(12, -34)],
	&"D": [-21, 21, -90, -64, Vector2i(0, -64)],
}
const REQUIRED_IDS: Array[StringName] = [
	&"radio", &"checkpoint_desk", &"card_reader_c", &"power_switch_a", &"power_switch_b", &"power_switch_c",
	&"security_panel", &"military_terminal", &"log_sequence", &"log_missing_security",
	&"cache_c_hidden", &"cache_d_hidden", &"checkpoint_b",
]

var _failures: int = 0
var _checks: int = 0
var _main: Node
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


func _run() -> void:
	var qm := root.get_node_or_null("/root/QuestManager")
	if qm:
		qm.set("intro_done", true)
	root.get_node("WorldState").reset()
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(4)
	_space = root.get_world_3d().direct_space_state
	_sphere = SphereShape3D.new()
	_sphere.radius = 0.5

	_test_manifest_rules()
	_test_interiors()
	_test_reachability()
	await _test_flood_detects_blocking()
	await _test_caches()
	_main.queue_free()
	await _frames(2)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- manifest rules ----------------------------------------------------------

func _test_manifest_rules() -> void:
	print("Placement rules")
	var props := AreaDressing.props
	_check(props.size() >= 60, "the outpost is dressed (%d props)" % props.size())
	var names := {}
	var duplicate := ""
	for p in props:
		if names.has(p["name"]):
			duplicate = String(p["name"])
		names[p["name"]] = true
	_check(duplicate == "" and not names.has(""), "every prop has a unique, non-empty name")
	var bad_solid: Array[String] = []
	var bad_tall: Array[String] = []
	var solid_count := 0
	for p in props:
		var fp := AreaDressing.footprint(p)
		var size: Vector3 = p["size"]
		if p["collide"]:
			solid_count += 1
			if fp.intersects(AreaDressing.PATROL_CORRIDOR) or fp.intersects(AreaDressing.BOSS_ZONE) \
					or fp.intersects(AreaDressing.DOOR_BC_CLEAR) or fp.intersects(AreaDressing.DOOR_CD_CLEAR):
				bad_solid.append(String(p["name"]))
		elif size.y > 0.2 and (fp.intersects(AreaDressing.PATROL_CORRIDOR) or fp.intersects(AreaDressing.BOSS_ZONE)):
			bad_tall.append(String(p["name"]))
	_check(bad_solid.is_empty(), "no solid prop blocks the patrol corridor, the doors or the boss zone %s" % [str(bad_solid)])
	_check(bad_tall.is_empty(), "no raised prop stands in the patrol corridor or the boss zone %s" % [str(bad_tall)])
	_check(solid_count <= 32, "few physics bodies were added (%d; limit raised from 20 for the Milestone 5 interiors)" % solid_count)

	# The same rules against the real colliders in the scene (not just the manifest).
	var blocked: Array[String] = []
	for z in range(-58, -35):
		for x in [-2, -1, 0]:  # the walking lane (the existing cover crates sit at the corridor edges, x -3.2 and 1.2)
			if not _is_free(x, z):
				blocked.append("(%d,%d)" % [x, z])
	_check(blocked.is_empty(), "the patrol corridor is free of colliders %s" % [str(blocked)])
	var zone_blocked: Array[String] = []
	for p in props:
		if p["collide"] and AreaDressing.footprint(p).intersects(AreaDressing.BOSS_ZONE):
			zone_blocked.append(String(p["name"]))
	_check(zone_blocked.is_empty(), "no dressing collider sits in the boss arena zone")


# --- reachability ------------------------------------------------------------

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


func _flood(area: StringName) -> Dictionary:
	var spec: Array = AREAS[area]
	var x_min: int = spec[0]
	var x_max: int = spec[1]
	var z_min: int = spec[2]
	var z_max: int = spec[3]
	var start: Vector2i = spec[4]
	# Nearest free cell to the start (a prop or a wall may sit exactly on it).
	var seed_cell := Vector2i(-9999, -9999)
	for radius in range(0, 4):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var c := start + Vector2i(dx, dz)
				if seed_cell.x == -9999 and _is_free(c.x, c.y):
					seed_cell = c
	var visited := {}
	if seed_cell.x == -9999:
		return visited
	var queue: Array[Vector2i] = [seed_cell]
	visited[seed_cell] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + step
			if n.x < x_min or n.x > x_max or n.y < z_min or n.y > z_max or visited.has(n):
				continue
			if _is_free(n.x, n.y):
				visited[n] = true
				queue.append(n)
	return visited


func _area_of(z: float) -> StringName:
	if z > 30.0:
		return &"A"
	if z > -30.0:
		return &"B"
	if z > -62.0:
		return &"C"
	return &"D"


func _reachable(visited: Dictionary, pos: Vector3) -> bool:
	for cell: Vector2i in visited:
		if Vector2(float(cell.x) - pos.x, float(cell.y) - pos.z).length() <= 1.8:
			return true
	return false


func _test_reachability() -> void:
	print("Reachability (1.0 m wide path)")
	var floods := {}
	for area: StringName in AREAS:
		floods[area] = _flood(area)
		_check(floods[area].size() > 200, "area %s has a large connected walkable region (%d cells)" % [area, floods[area].size()])
	var targets: Array[Interactable] = []
	for node in _main.find_children("*", "Interactable", true, false):
		var item := node as Interactable
		if item == null or item is Door:
			continue
		targets.append(item)
	var found_ids := {}
	var unreachable: Array[String] = []
	for item in targets:
		found_ids[item.interaction_id] = true
		var area := _area_of(item.global_position.z)
		if not _reachable(floods[area], item.global_position):
			unreachable.append("%s (area %s)" % [item.interaction_id, area])
	_check(unreachable.is_empty(), "every interactable can be reached %s" % [str(unreachable)])
	var missing: Array[String] = []
	for id in REQUIRED_IDS:
		if not found_ids.has(id):
			missing.append(String(id))
	_check(missing.is_empty(), "all the required objects exist %s" % [str(missing)])
	_check(targets.size() >= 20, "a good number of interactables were checked (%d)" % targets.size())


# --- caches ------------------------------------------------------------------

func _test_caches() -> void:
	print("Hidden caches")
	var player := _main.get_node("Player") as Player
	for id: StringName in [&"cache_c_hidden", &"cache_d_hidden"]:
		var matches: Array[SupplyCrate] = []
		for node in _main.find_children("*", "SupplyCrate", true, false):
			if (node as SupplyCrate).crate_id == id:
				matches.append(node)
		_check(matches.size() == 1, "%s exists exactly once" % id)
		if matches.size() != 1:
			continue
		var crate := matches[0]
		_check(crate.loot_paths.size() >= 2, "%s holds loot (%d items)" % [id, crate.loot_paths.size()])
		var loadable := true
		for path in crate.loot_paths:
			loadable = loadable and load(path) is ItemData
		_check(loadable, "%s loot items all load" % id)
		var pickups_before := _count_pickups()
		_check(crate.interact(player), "%s can be opened" % id)
		await _frames(3)
		_check(_count_pickups() - pickups_before == crate.loot_paths.size(), "%s drops its items once" % id)
		_check(not crate.interact(player), "%s cannot be looted twice" % id)
		_check(root.get_node("WorldState").has_flag(StringName(String(id) + "_taken")), "%s is remembered as taken" % id)


func _count_pickups() -> int:
	return _main.find_children("*", "Pickup", true, false).size()


## Negative control: the flood fill must actually notice a blocked path, otherwise "reachable" proves nothing.
func _test_flood_detects_blocking() -> void:
	print("Negative control")
	# Fence the hidden cache's corner (the strip can also be reached from behind the command building,
	# so a pen right around the cache is the reliable way to cut it off).
	var walls: Array[StaticBody3D] = []
	for spec: Array in [[Vector3(19.5, 1.5, -87.5), Vector3(5.4, 3.0, 0.6)], [Vector3(17.0, 1.5, -89.9), Vector3(0.6, 3.0, 4.8)]]:
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		wall.add_child(shape)
		wall.position = spec[0]
		_main.add_child(wall)
		walls.append(wall)
	await _frames(3)
	_free_cache.clear()
	var cache_pos := Vector3(19.5, 0.0, -90.0)
	_check(not _reachable(_flood(&"D"), cache_pos), "with the cache fenced in it is reported unreachable")
	for wall in walls:
		wall.queue_free()
	await _frames(3)
	_free_cache.clear()
	_check(_reachable(_flood(&"D"), cache_pos), "and reachable again once the fence is removed")


# --- Milestone 5 interiors ----------------------------------------------------

func _test_interiors() -> void:
	print("Interior dressing")
	var by_name := {}
	for p in AreaDressing.props:
		by_name[p["name"]] = p
	for needed: String in ["CabinetC1", "DeskC", "ShelfC", "HazardPanelC", "FuelDrumS1", "ShedPipeH", "WallMapD",
			"ZoneStripeD0".trim_suffix("0"), "CommandRugD", "MonitorScreenC", "AccentStripD"]:
		_check(by_name.has(needed) or by_name.has(needed + "_2"), "interior prop exists: " + needed)
	_check(AreaDressing.floor_tiles >= 70, "floors use varied tiles (%d)" % AreaDressing.floor_tiles)
	_check(AreaDressing.glow_count >= 8, "emissive accents exist (%d)" % AreaDressing.glow_count)
	var greybox := root.find_child("OutpostGreybox", true, false)
	_check(greybox != null, "the merged outpost mesh exists")
	if greybox:
		var outpost := greybox.get_parent()
		var meshes := 0
		for c in outpost.get_children():
			if c is MeshInstance3D:
				meshes += 1
		# the merged mesh plus two emissive meshes plus the Area A sign label parents: budget +3 draw calls
		_check(meshes <= 3, "interiors add at most 2 draw calls beyond the merged mesh (%d mesh nodes)" % meshes)
		_check(outpost.get_node_or_null("OutpostGlowTeal") != null and outpost.get_node_or_null("OutpostGlowAmber") != null,
				"both emissive meshes are attached")
	# Interaction ranges: no solid interior prop within 1.4 m of a switch, terminal, panel or document.
	var spots: Array[Vector3] = [Vector3(6.5, 0, -59.5), Vector3(-16.5, 0, -59.5), Vector3(18.5, 0, -39.0),
			Vector3(12.0, 0, -58.6), Vector3(17.5, 0, -58.7), Vector3(0.0, 0, -78.4), Vector3(-8.0, 0, -72.4),
			Vector3(8.0, 0, -36.4), Vector3(-17.0, 0, -52.0)]
	var crowded: Array[String] = []
	for p in AreaDressing.props:
		if not p["collide"]:
			continue
		var fp := AreaDressing.footprint(p)
		for s in spots:
			if fp.grow(1.4).has_point(Vector2(s.x, s.z)):
				crowded.append("%s near (%.1f,%.1f)" % [p["name"], s.x, s.z])
	_check(crowded.is_empty(), "no solid prop crowds an interactable %s" % [str(crowded)])
