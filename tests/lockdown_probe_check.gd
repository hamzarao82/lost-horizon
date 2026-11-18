extends SceneTree
## The escape lockdown against the real geometry (physics flood fill on a 1 m grid), headless:
##   godot --headless --path . -s tests/lockdown_probe_check.gd
## Proves: the shutters seal both exits with no gap, the player is never sealed in without the breaker, the
## breaker stays reachable when the guards' positions are treated as blocked, lifting it reopens the exits,
## and a reload during the lockdown (or after the guards were put down) never doubles the guards.

const WORLD_MASK: int = 1
const X_MIN: int = -60
const X_MAX: int = 60
const Z_MIN: int = -110
const Z_MAX: int = 110

var _checks: int = 0
var _failures: int = 0
var _space: PhysicsDirectSpaceState3D
var _sphere: SphereShape3D
var _cache: Dictionary = {}
var _main: Node
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


func _free(x: int, z: int) -> bool:
	var key := Vector2i(x, z)
	if _cache.has(key):
		return _cache[key]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform = Transform3D(Basis.IDENTITY, Vector3(float(x), 0.9, float(z)))
	query.collision_mask = WORLD_MASK
	var ok := _space.intersect_shape(query, 1).is_empty()
	_cache[key] = ok
	return ok


## Flood from `start`; cells within `avoid_radius` of any `avoid` point count as blocked.
func _flood(start: Vector2, avoid: Array[Vector2] = [], avoid_radius: float = 0.0) -> Dictionary:
	var seed_cell := Vector2i(-9999, -9999)
	var origin := Vector2i(roundi(start.x), roundi(start.y))
	for radius in range(0, 5):
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var c := origin + Vector2i(dx, dz)
				if seed_cell.x == -9999 and _free(c.x, c.y):
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
			if n.x < X_MIN or n.x > X_MAX or n.y < Z_MIN or n.y > Z_MAX or visited.has(n):
				continue
			var blocked := false
			for point in avoid:
				if Vector2(float(n.x), float(n.y)).distance_to(point) < avoid_radius:
					blocked = true
			if not blocked and _free(n.x, n.y):
				visited[n] = true
				queue.append(n)
	return visited


func _near(visited: Dictionary, pos: Vector3) -> bool:
	for cell: Vector2i in visited:
		if Vector2(float(cell.x) - pos.x, float(cell.y) - pos.z).length() <= 1.8:
			return true
	return false


func _extent(visited: Dictionary) -> Rect2:
	var lo := Vector2(99999.0, 99999.0)
	var hi := Vector2(-99999.0, -99999.0)
	for cell: Vector2i in visited:
		lo = Vector2(minf(lo.x, float(cell.x)), minf(lo.y, float(cell.y)))
		hi = Vector2(maxf(hi.x, float(cell.x)), maxf(hi.y, float(cell.y)))
	return Rect2(lo, hi - lo)


func _build_world(saved: Dictionary = {}) -> void:
	_world.reset()
	if not saved.is_empty():
		_world.from_dict(saved)  # the real load order: saved flags exist before the region is built
	_cache.clear()
	if _main != null:
		_main.queue_free()
		await _frames(3)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(5)
	_space = root.get_world_3d().direct_space_state


func _open_ordinary_doors() -> void:
	for node in _main.find_children("*", "Door", true, false):
		var door := node as Door
		if door == null or String(door.door_id).begins_with("lockdown"):
			continue
		door.open(false)
	_world.set_flag(&"boss_warden_defeated", true)
	_world.set_flag(&"boss_warden_defeated", true)


func _store() -> PaymentStore:
	var found := _main.find_children("*", "PaymentStore", true, false)
	return found[0] as PaymentStore if not found.is_empty() else null


func _guards_of(store: Node) -> int:
	var n := 0
	for node in _main.find_children("*", "Enemy", true, false):
		if node.get_parent() == store and not node.is_dead():
			n += 1
	return n


func _leaks(visited: Dictionary, north: bool) -> int:
	var count := 0
	for cell: Vector2i in visited:
		if north and cell.y <= -90 and cell.x > -14:
			count += 1
		if not north and cell.y >= 77:
			count += 1
	return count


func _run() -> void:
	_world = root.get_node("WorldState")
	root.get_node("QuestManager").reset()
	_sphere = SphereShape3D.new()
	_sphere.radius = 0.5

	await _build_world()
	var store := _store()
	_check(store != null, "the payment store exists in the real world")
	if store == null:
		quit(1)
		return
	_open_ordinary_doors()
	await _frames(3)
	_cache.clear()

	var yard := Vector2(4.0, -84.0)
	var south_seed := Vector2(0.0, 72.0)
	var open_north := _flood(yard)
	var open_south := _flood(south_seed)
	_check(open_north.size() > 800, "before the alarm the Area D yard is a large walkable region (%d cells)" % open_north.size())
	_check(open_south.size() > 800, "and so is the beach side of the south exit (%d cells)" % open_south.size())

	# --- the alarm ---
	_world.set_flag(&"payment_recovered", true)
	await _frames(4)
	_cache.clear()
	_check(store.shutters.size() == 2, "two shutters close")
	var north := _flood(yard)
	var south := _flood(south_seed)
	_check(north.size() > 400, "the player still has a region to fight and move in (%d cells)" % north.size())
	_check(_leaks(north, true) == 0, "the north shutter leaves no walkable gap (%d leaking cells)" % _leaks(north, true))
	_check(_leaks(south, false) == 0, "the south shutter leaves no walkable gap (%d leaking cells)" % _leaks(south, false))
	_check(_extent(north).position.x >= -44.0 and _extent(north).end.x <= 44.0, "nothing walkable runs round the sides of the shutters")

	# --- the breaker ---
	var breaker_pos := PaymentStore.BREAKER_POS
	_check(_near(north, breaker_pos), "the breaker is reachable from the yard")
	var from_breaker := _flood(Vector2(breaker_pos.x, breaker_pos.z))
	# Area A (the beach) is not sampled: the trail's rise, fence and berm are not crossable at 0.9 m by this flat probe
	# (opening_approach_check's route probes cover that ground). Everything the player can be inside the alarm is here.
	for sample in [Vector3(4.0, 0.0, -84.0), Vector3(-17.0, 0.0, -87.0), Vector3(-12.0, 0.0, -75.0), Vector3(0.0, 0.0, -70.0),
			Vector3(12.0, 0.0, -45.0), Vector3(-14.0, 0.0, -40.0), Vector3(0.0, 0.0, 10.0), Vector3(-20.0, 0.0, 20.0)]:
		_check(_near(from_breaker, sample), "the player can reach the breaker from (%.0f, %.0f)" % [sample.x, sample.z])
	var guard_points: Array[Vector2] = []
	for p in PaymentStore.GUARD_POSITIONS:
		guard_points.append(Vector2(p.x, p.z))
	var guard_free := _flood(Vector2(-17.0, -87.0), guard_points, 2.0)
	_check(_near(guard_free, breaker_pos), "a path to the breaker exists even with a 2 m ring around each guard's start")

	# --- the breaker lifts it and reopens the exits ---
	_check(store.breaker != null and not store.breaker.locked, "the breaker is usable during the lockdown")
	_world.set_flag(&"lockdown_lifted", true)
	await _frames(40)
	_cache.clear()
	_check(_leaks(_flood(south_seed), false) > 0, "lifting the lockdown reopens the south exit (the shutter was the only seal)")
	_check(_leaks(_flood(yard), true) > 0 or _flood(yard).size() > north.size(), "and the north side widens again")

	# --- reload during the lockdown never doubles the guards ---
	await _build_world()
	_open_ordinary_doors()
	_world.set_flag(&"payment_recovered", true)
	await _frames(4)
	var s1 := _store()
	_check(s1 != null and _guards_of(s1) == 3, "a lockdown spawns exactly three guards (%d)" % _guards_of(s1))
	s1.start_lockdown()
	s1.start_lockdown()
	_check(_guards_of(s1) == 3, "starting the lockdown again does not add guards")
	var saved: Dictionary = _world.to_dict()
	await _build_world(saved)
	await _frames(6)
	var s2 := _store()
	_check(_guards_of(s2) == 3, "after a reload during the lockdown there are exactly three guards again, not six (%d)" % _guards_of(s2))

	# --- put the guards down, then reload ---
	for guard in s2.guards:
		if is_instance_valid(guard):
			guard.get_node("HealthComponent").take_damage(99999.0)
	await _frames(10)
	_check(_world.has_flag(PaymentStore.FLAG_GUARDS_DOWN), "putting all three guards down is remembered")
	saved = _world.to_dict()
	await _build_world(saved)
	await _frames(6)
	var s3 := _store()
	_check(_guards_of(s3) == 0, "a reload after the guards were put down does not bring them back (%d)" % _guards_of(s3))
	_check(s3.shutters.size() == 2, "but the shutters are still down until the breaker is thrown")

	print("lockdown_probe_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
