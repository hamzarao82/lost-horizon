extends SceneTree
## Patrol AI checks (headless): godot --headless --path . -s tests/patrol_check.gd
## Runs in the courtyard of Main with the Outpost 17 extension removed, so only the test's enemies exist.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player
var _extras: Array[Node] = []


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
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(3)
	var outpost := _main.get_node_or_null("Outpost17")
	if outpost:
		outpost.free()  # no encounter group, no guard squad, no doors: just the courtyard
	_player = _main.get_node("Player") as Player
	await _frames(2)

	await _test_route_walk()
	await _test_notice_front_and_behind()
	await _test_line_of_sight()
	await _test_noise_search_return()
	await _test_stuck_recovery()
	await _test_attack_and_neighbour_noise()
	await _test_group_cap_and_cleared_flag()
	await _test_ordinary_enemies_unchanged()
	_cleanup()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _cleanup() -> void:
	for node in _extras:
		if is_instance_valid(node):
			node.queue_free()
	_extras.clear()


func _reset(player_at: Vector3 = Vector3(0.0, 0.1, -24.0)) -> void:
	_cleanup()
	_player.global_position = player_at
	_player.velocity = Vector3.ZERO


func _route(points: PackedVector3Array, loop: bool = false, wait: float = 0.2) -> PatrolRoute:
	var route := PatrolRoute.new()
	route.loop = loop
	route.wait_seconds = wait
	route.set_points(points)
	_main.add_child(route)
	_extras.append(route)
	return route


func _patroller(route: PatrolRoute, scene: String = SOLDIER, index: int = 0) -> Enemy:
	var enemy := (load(scene) as PackedScene).instantiate() as Enemy
	enemy.patrol_route = route
	enemy.patrol_index = index
	enemy.position = route.global_point(index)  # before add_child: never overlaps the player
	_main.add_child(enemy)
	_extras.append(enemy)
	return enemy


func _wall(center: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	wall.add_child(shape)
	wall.position = center
	_main.add_child(wall)
	_extras.append(wall)
	return wall


func _test_route_walk() -> void:
	print("Walking a route")
	_reset()
	var route := _route(PackedVector3Array([Vector3(-2.5, 0.1, 10.0), Vector3(2.5, 0.1, 10.0)]))
	var enemy := _patroller(route)
	_check(enemy.state == Enemy.State.PATROL and Enemy.active_patrollers == 1, "an enemy with a route starts in PATROL")
	var min_x := 99.0
	var max_x := -99.0
	var seen_index_change := false
	for i in 420:
		await physics_frame
		min_x = minf(min_x, enemy.global_position.x)
		max_x = maxf(max_x, enemy.global_position.x)
		if enemy.patrol_index != 0:
			seen_index_change = true
	_check(max_x - min_x > 4.0, "it walks the whole route (covered %.1f m)" % (max_x - min_x))
	_check(seen_index_change, "it moves on to the next waypoint after waiting")
	_check(enemy.state == Enemy.State.PATROL, "and is still patrolling")


func _test_notice_front_and_behind() -> void:
	print("Noticing the player")
	_reset(Vector3(0.0, 0.1, 6.0))
	var route := _route(PackedVector3Array([Vector3(0.0, 0.1, 10.0)]))
	var enemy := _patroller(route)
	await _frames(25)
	_check(enemy.state == Enemy.State.CHASE, "a player 4 m in front is noticed and chased")
	_reset(Vector3(0.0, 0.1, 14.0))  # 4 m behind (the enemy faces -Z)
	route = _route(PackedVector3Array([Vector3(0.0, 0.1, 10.0)]))
	enemy = _patroller(route)
	await _frames(40)
	_check(enemy.state == Enemy.State.PATROL, "a player standing behind it is not noticed")


func _test_line_of_sight() -> void:
	print("Line of sight")
	_reset(Vector3(0.0, 0.1, 5.0))
	_wall(Vector3(0.0, 2.0, 8.0), Vector3(12.0, 4.0, 0.5))
	var route := _route(PackedVector3Array([Vector3(0.0, 0.1, 10.0)]))
	var enemy := _patroller(route)
	await _frames(40)
	_check(not enemy._sees_player(), "a wall between them blocks sight")
	_check(enemy.state == Enemy.State.PATROL, "so a player behind a wall is not chased")


func _test_noise_search_return() -> void:
	print("Investigate, search, return")
	_reset()
	var route := _route(PackedVector3Array([Vector3(0.0, 0.1, 10.0)]))
	var enemy := _patroller(route)
	enemy.search_seconds = 0.5
	await _frames(5)
	enemy.hear(Vector3(6.0, 0.1, 10.0))
	_check(enemy.state == Enemy.State.SUSPICIOUS, "a noise makes a patrolling enemy suspicious")
	var order: Array[int] = [enemy.state]
	for i in 900:
		await physics_frame
		if enemy.state != order[-1]:
			order.append(enemy.state)
		if enemy.state == Enemy.State.PATROL:
			break
	var expected: Array[int] = [Enemy.State.SUSPICIOUS, Enemy.State.SEARCH, Enemy.State.RETURN, Enemy.State.PATROL]
	_check(order == expected, "it investigates, searches, returns and resumes patrolling (%s)" % [str(order)])


func _test_stuck_recovery() -> void:
	print("Never permanently stuck")
	_reset()
	_wall(Vector3(0.0, 2.0, 10.0), Vector3(0.5, 4.0, 12.0))  # a wall across the middle of the route
	var route := _route(PackedVector3Array([Vector3(-6.0, 0.1, 10.0), Vector3(6.0, 0.1, 10.0)]))
	var enemy := _patroller(route)
	var changes := 0
	var last := enemy.patrol_index
	for i in 1100:
		await physics_frame
		if enemy.patrol_index != last:
			changes += 1
			last = enemy.patrol_index
	_check(changes >= 3, "blocked by a wall it skips the waypoint and keeps patrolling (%d waypoint changes)" % changes)
	_check(enemy.global_position.x < 0.0, "and is still on its own side of the wall")


func _test_attack_and_neighbour_noise() -> void:
	print("Being attacked and combat noise")
	_reset(Vector3(0.0, 0.1, 4.0))  # near enough that the victim can still see and chase the player
	var route := _route(PackedVector3Array([Vector3(-4.0, 0.1, 10.0), Vector3(-4.0, 0.1, 18.0)]))
	var victim := _patroller(route, SOLDIER, 0)
	var neighbour := _patroller(route, HUNTER, 1)
	await _frames(3)
	var attack := load("res://resources/attacks/light_1.tres") as AttackData
	victim.receive_hit(attack, _player.global_position)
	_check(neighbour.state == Enemy.State.SUSPICIOUS, "a hit nearby makes the other patroller suspicious")
	await _frames(60)
	_check(victim.state == Enemy.State.CHASE or victim.state == Enemy.State.ATTACK, "the enemy that was hit turns on the player")


func _test_group_cap_and_cleared_flag() -> void:
	print("Patrol groups")
	_reset()
	var world := root.get_node("WorldState")
	world.reset()
	var group := PatrolGroup.new()
	group.group_id = &"test_a"
	group.area_id = &"test_area"
	group.scene_paths = PackedStringArray([SOLDIER, SOLDIER])
	group.route_points = PackedVector3Array([Vector3(-6.0, 0.1, 12.0), Vector3(6.0, 0.1, 12.0)])
	_main.add_child(group)
	_extras.append(group)
	await _frames(2)
	_check(Enemy.active_patrollers == 0, "nothing spawns before the area is entered")
	world.emit_area_entered(&"test_area")
	await _frames(3)
	_check(group.enemies.size() == 2 and Enemy.active_patrollers == 2, "entering the area wakes the squad (2 enemies)")
	world.emit_area_entered(&"test_area")
	await _frames(2)
	_check(group.enemies.size() == 2, "entering again does not spawn a second squad")

	var big := PatrolGroup.new()
	big.group_id = &"test_b"
	big.scene_paths = PackedStringArray([SOLDIER, SOLDIER, SOLDIER])
	big.route_points = group.route_points
	_main.add_child(big)
	_extras.append(big)
	_check(big.spawn() == 0 and Enemy.active_patrollers == 2, "a squad that would exceed 4 active patrollers does not spawn")
	var small := PatrolGroup.new()
	small.group_id = &"test_c"
	small.scene_paths = PackedStringArray([SOLDIER, SOLDIER])
	small.route_points = group.route_points
	_main.add_child(small)
	_extras.append(small)
	_check(small.spawn() == 2 and Enemy.active_patrollers == 4, "a squad that fits is allowed (exactly 4 active)")

	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	for enemy in group.enemies:
		for i in 4:
			enemy.receive_hit(heavy, _player.global_position)
	await _frames(3)
	_check(world.has_flag(&"patrol_test_a_cleared"), "killing the whole squad sets its cleared flag")
	var again := PatrolGroup.new()
	again.group_id = &"test_a"
	again.scene_paths = group.scene_paths
	again.route_points = group.route_points
	_main.add_child(again)
	_extras.append(again)
	await _frames(2)
	_check(again.spawn() == 0, "a squad that was already wiped out stays dead")
	world.reset()


func _test_ordinary_enemies_unchanged() -> void:
	print("Waves and bosses are unaffected")
	_reset()
	await _frames(3)  # let the previous tests' enemies finish freeing before counting
	var before := Enemy.active_patrollers
	var enemy := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	enemy.position = Vector3(0.0, 0.1, 10.0)
	_main.add_child(enemy)
	_extras.append(enemy)
	await _frames(3)
	_check(enemy.state == Enemy.State.IDLE and enemy.patrol_route == null, "an enemy without a route still starts IDLE")
	_check(Enemy.active_patrollers == before, "and does not count as a patroller")
	var warden := (load("res://scenes/enemies/Warden.tscn") as PackedScene).instantiate() as Enemy
	warden.position = Vector3(10.0, 0.1, 12.0)
	_main.add_child(warden)
	_extras.append(warden)
	await _frames(3)
	_check(warden.patrol_route == null and warden.state != Enemy.State.PATROL, "the Warden never patrols")
