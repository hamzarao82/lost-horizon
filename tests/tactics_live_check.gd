extends SceneTree
## Milestone 11 tactics in the real enemy configs and the placed barrels (headless):
##   godot --headless --path . -s tests/tactics_live_check.gd
## Proves: a default enemy is unchanged; bosses never get tactics or a guard; the real regular configs carry
## conservative tactics that grow toward the Iron Fortress; fights with those configs terminate (retreaters come
## back, the reinforcement call is capped); every barrel id is saved-flag safe, unique, inside its region, off the
## walking route, not inside another solid, and a destroyed barrel stays gone.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const PLAYER_AT: Vector3 = Vector3(0.0, 0.1, -24.0)
const ENEMY_DIR: String = "res://resources/enemies/"
const BOSS_CONFIGS: Array[String] = ["bw_patrol_chief", "bw_site_overseer", "dc_cove_boss", "dc_harbor_commander", "director",
		"facility_elite_subject", "fortress_captain", "rc_facility_commander_boss", "facility_commander", "facility_experimental_subject"]
const FIELDS: Array[String] = ["scheduled", "flank_slots", "spacing", "retreat_health_fraction", "reinforcement_cap", "guard_reduction"]

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
	_test_config_table()
	await _test_barrel_layouts()
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(3)
	await _test_outpost_barrels()
	var outpost := _main.get_node_or_null("Outpost17")
	if outpost:
		outpost.free()
	_player = _main.get_node("Player") as Player
	await _frames(2)
	await _test_default_enemy()
	await _test_fights_terminate()
	await _test_heavy_guard_fight()
	await _test_reinforcement_cap()
	await _test_real_region_barrels()
	for node in _extras:
		if is_instance_valid(node):
			node.queue_free()
	print("\ntactics_live_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _cfg(config_name: String) -> Resource:
	return load(ENEMY_DIR + config_name + ".tres")


func _f(res: Resource, field: String) -> float:
	var value: Variant = res.get(field)
	return float(value) if value != null else 0.0


# --- the data --------------------------------------------------------------

func _test_config_table() -> void:
	print("Real configs")
	for name in BOSS_CONFIGS:
		var res := _cfg(name)
		var clean := res != null
		if res != null:
			for field in FIELDS:
				if _f(res, field) != 0.0:
					clean = false
		_check(clean, "boss config %s has no tactics and no guard" % name)
	var guard := _cfg("facility_security_guard")
	_check(bool(guard.get("scheduled")) and bool(guard.get("flank_slots")) and bool(guard.get("spacing")), "Research Complex guard: scheduler, flank slots and spacing on")
	_check(_f(guard, "retreat_health_fraction") > 0.0 and _f(guard, "retreat_health_fraction") <= 0.3, "Research Complex guard retreats at a conservative health fraction (%.2f)" % _f(guard, "retreat_health_fraction"))
	_check(_f(guard, "reinforcement_cap") == 1.0, "Research Complex guard calls at most one ally")
	var heavy := _cfg("facility_heavy_guard")
	_check(_f(heavy, "guard_reduction") > 0.0 and _f(heavy, "guard_reduction") <= 0.5, "Heavy Facility Guard has a guard stance (%.2f)" % _f(heavy, "guard_reduction"))
	_check(_f(heavy, "retreat_health_fraction") == 0.0, "heavies never retreat")
	var assault := _cfg("heavy_assault_unit")
	var infantry := _cfg("fortress_infantry")
	var elite := _cfg("elite_security_soldier")
	_check(_f(assault, "guard_reduction") >= _f(heavy, "guard_reduction"), "the Iron Fortress guard is at least as firm as the facility's (%.2f >= %.2f)" % [_f(assault, "guard_reduction"), _f(heavy, "guard_reduction")])
	_check(_f(infantry, "reinforcement_cap") >= _f(guard, "reinforcement_cap") and _f(elite, "reinforcement_cap") >= _f(guard, "reinforcement_cap"), "Iron Fortress infantry call at least as many allies as facility guards")
	_check(_f(infantry, "reinforcement_cap") <= 3.0 and _f(elite, "reinforcement_cap") <= 3.0 and _f(assault, "reinforcement_cap") <= 3.0, "no config calls more than three allies")
	_check(_f(infantry, "guard_reduction") == 0.0 and _f(elite, "guard_reduction") == 0.0, "ranged infantry never guard")
	var shipped := 0
	for name in ["facility_security_guard", "facility_heavy_guard", "fortress_infantry", "elite_security_soldier", "heavy_assault_unit"]:
		var res := _cfg(name)
		for field in FIELDS:
			if _f(res, field) != 0.0:
				shipped += 1
				break
	_check(shipped == 5, "all five regular configs carry some tactic (%d)" % shipped)
	_check(not bool(_cfg("tactical_commander").get("scheduled")), "the Tactical Commander is unchanged")


func _test_default_enemy() -> void:
	print("Default enemy")
	var enemy := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	_check(not enemy.scheduled and not enemy.flank_slots and not enemy.spacing, "a plain soldier has the scheduler, flank and spacing off")
	_check(enemy.retreat_health_fraction == 0.0 and enemy.reinforcement_cap == 0 and enemy.guard_reduction == 0.0, "retreat, reinforcement and guard are off")
	enemy.free()
	var config := _cfg("facility_security_guard") as FacilityEnemyConfig
	var applied := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	config.apply(applied)
	_check(applied.scheduled and applied.flank_slots and applied.spacing and applied.reinforcement_cap == 1 and applied.retreat_health_fraction > 0.0, "FacilityEnemyConfig.apply copies the tactics onto the enemy")
	applied.free()
	var heavy := (load("res://scenes/enemies/HeavySoldier.tscn") as PackedScene).instantiate() as Enemy
	(_cfg("facility_heavy_guard") as FacilityEnemyConfig).apply(heavy)
	_check(heavy.guard_reduction > 0.0, "the heavy guard config sets the guard stance")
	heavy.free()


# --- fights ---------------------------------------------------------------

func _clear() -> void:
	for node in _extras:
		if is_instance_valid(node):
			node.queue_free()
	_extras.clear()
	await _frames(2)
	_player.global_position = PLAYER_AT
	_player.velocity = Vector3.ZERO
	_player.health.health = _player.health.max_health
	Enemy.active_patrollers = 0
	AIScheduler.reset_budget()


func _spawn_config(config_name: String, scene: String, at: Vector3) -> Enemy:
	var enemy := (load(scene) as PackedScene).instantiate() as Enemy
	(_cfg(config_name) as FacilityEnemyConfig).apply(enemy)
	enemy.position = at
	_main.add_child(enemy)
	_extras.append(enemy)
	enemy.aggro()
	return enemy


func _strike(enemy: Enemy, damage: float, id: StringName = &"light_1") -> void:
	var attack := AttackData.new()
	attack.id = id
	attack.damage = damage
	attack.knockback = 0.0
	attack.stagger_time = 0.1
	enemy.receive_hit(attack, _player.global_position)


func _test_fights_terminate() -> void:
	print("Fights with the live tactics end")
	await _clear()
	var group: Array[Enemy] = []
	for i in 4:
		group.append(_spawn_config("facility_security_guard", SOLDIER, PLAYER_AT + Vector3(-6.0 + 4.0 * i, 0.0, 14.0)))
	var retreats := 0
	var frames := 0
	while frames < 3000:
		await _frames(15)
		frames += 15
		_player.health.health = _player.health.max_health
		var alive := 0
		for enemy in group:
			if enemy.is_dead():
				continue
			alive += 1
			_strike(enemy, 9.0)
			if enemy.get("_retreated") == true:
				retreats += 1
		if alive == 0:
			break
	var dead := 0
	for enemy in group:
		if enemy.is_dead():
			dead += 1
	var retreated := 0
	for enemy in group:
		if enemy.get("_retreated") == true:
			retreated += 1
	_check(dead == group.size(), "all four guards with live tactics die within 3000 frames (%d/4, %d frames)" % [dead, frames])
	_check(retreated >= 1, "the retreat actually triggered during the fight (%d enemies)" % retreated)
	await _clear()
	var runner := _spawn_config("facility_security_guard", SOLDIER, PLAYER_AT + Vector3(0.0, 0.0, 10.0))
	await _frames(5)
	_strike(runner, runner.hit_points * 0.82)  # down to ~18% health: the retreat fires
	_check(runner.get("_retreated") == true, "a guard hit below its retreat fraction retreats")
	await _frames(int(AIScheduler.RETREAT_SECONDS * 60.0) + 40)
	_check(not runner.is_dead() and runner.state == Enemy.State.CHASE, "the retreater is back in the chase after %.1f s" % AIScheduler.RETREAT_SECONDS)
	_check(runner.global_position.distance_to(_player.global_position) < 40.0, "and still within reach (%.1f m)" % runner.global_position.distance_to(_player.global_position))
	_strike(runner, 50.0)
	_check(runner.is_dead(), "a retreater can be finished off")


func _test_heavy_guard_fight() -> void:
	print("Heavy guard fight")
	await _clear()
	var heavy := _spawn_config("facility_heavy_guard", "res://scenes/enemies/HeavySoldier.tscn", PLAYER_AT + Vector3(0.0, 0.0, 14.0))
	var frames := 0
	while frames < 3000 and not heavy.is_dead():
		await _frames(15)
		frames += 15
		_player.health.health = _player.health.max_health
		_strike(heavy, 12.0)
	_check(heavy.is_dead(), "a guarding heavy (180 hp) still dies to light hits within 3000 frames (%d)" % frames)
	await _clear()
	heavy = _spawn_config("facility_heavy_guard", "res://scenes/enemies/HeavySoldier.tscn", PLAYER_AT + Vector3(0.0, 0.0, 18.0))
	await _frames(3)
	var hp: float = heavy._health.health
	var yaw := (heavy.get_node("VisualRoot") as Node3D).rotation.y
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var attack := AttackData.new()
	attack.id = &"light_1"
	attack.damage = 20.0
	heavy.receive_hit(attack, heavy.global_position + forward * 2.0)
	var lost := hp - heavy._health.health
	_check(is_equal_approx(lost, 20.0 * (1.0 - heavy.guard_reduction)), "the real heavy guard blocks a frontal light hit (%.1f of 20)" % lost)


func _test_reinforcement_cap() -> void:
	print("Reinforcement cap")
	await _clear()
	var caller := _spawn_config("facility_security_guard", SOLDIER, Vector3(0.0, 0.0, 6.0))
	caller.state = Enemy.State.IDLE
	var allies: Array[Enemy] = []
	for i in 5:
		var ally := (load(SOLDIER) as PackedScene).instantiate() as Enemy
		ally.position = Vector3(2.0 + i, 0.0, 6.0)
		_main.add_child(ally)
		_extras.append(ally)
		allies.append(ally)
	await _frames(2)
	_strike(caller, 5.0)
	var called := 0
	for ally in allies:
		if ally.state != Enemy.State.IDLE:
			called += 1
	_check(called == caller.reinforcement_cap, "five idle allies nearby, exactly %d answer the call (%d)" % [caller.reinforcement_cap, called])
	_strike(caller, 5.0)
	var again := 0
	for ally in allies:
		if ally.state != Enemy.State.IDLE:
			again += 1
	_check(again == called, "a second hit calls nobody more")


# --- barrels --------------------------------------------------------------

func _test_barrel_layouts() -> void:
	print("Barrel layouts")
	var seen: Dictionary = {}
	var all_valid := true
	var regex := RegEx.create_from_string("^[a-z0-9_]+$")
	var rc_path := ResearchComplex.main_path()
	var if_path := IronFortress.main_path()
	var rc_half := 30.0
	var if_half := 32.0
	var off_route := true
	var inside := true
	for region_id: StringName in BarrelPlacement.LAYOUTS:
		var list: Array = BarrelPlacement.LAYOUTS[region_id]
		_check(list.size() >= 2, "%s places at least two barrels (%d)" % [region_id, list.size()])
		for entry: Dictionary in list:
			var id := String(entry["id"])
			if regex.search(id) == null or id.length() > 48 - 7:  # "barrel_" is prefixed to the saved claim id
				all_valid = false
			if seen.has(id):
				all_valid = false
			seen[id] = true
			var pos: Vector3 = entry["pos"]
			if region_id == &"research_complex":
				inside = inside and absf(pos.x) < rc_half and pos.z < 52.0 and pos.z > -172.0
				for point in rc_path:
					if absf(point.y - pos.y) < 3.0 and Vector2(pos.x - point.x, pos.z - point.z).length() < 3.0:
						off_route = false
			elif region_id == &"iron_fortress":
				inside = inside and absf(pos.x) < if_half and pos.z < 54.0 and pos.z > -214.0
				for point in if_path:
					if Vector2(pos.x - point.x, pos.z - point.z).length() < 3.0:
						off_route = false
	_check(all_valid, "every barrel id is [a-z0-9_], unique and short enough once prefixed")
	_check(off_route, "no Research Complex or Iron Fortress barrel is within 3 m of the main route")
	_check(inside, "every barrel is inside its region's walls")


func _solid_overlaps(barrel: ExplosiveBarrel) -> int:
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, barrel.global_position + Vector3(0.0, 0.8, 0.0))
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [barrel.get_rid()]
	return barrel.get_world_3d().direct_space_state.intersect_shape(query, 8).size()


func _test_outpost_barrels() -> void:
	print("Outpost 17 barrels")
	var barrels := get_nodes_in_group("explosive_barrels")
	_check(barrels.size() == (BarrelPlacement.LAYOUTS[&"outpost_17"] as Array).size(), "Main's Outpost 17 holds its barrels (%d)" % barrels.size())
	var clear := 0
	for node in barrels:
		if _solid_overlaps(node as ExplosiveBarrel) == 0:
			clear += 1
		else:
			print("    overlap: ", (node as ExplosiveBarrel).barrel_id, " at ", (node as ExplosiveBarrel).global_position)
	_check(clear == barrels.size(), "none of the Outpost 17 barrels stands inside another solid (%d/%d clear)" % [clear, barrels.size()])


func _test_real_region_barrels() -> void:
	print("Region barrels")
	var world := root.get_node_or_null("WorldState")
	for region_id: StringName in [&"research_complex", &"iron_fortress"]:
		var region: Node3D = (ResearchComplex.new() if region_id == &"research_complex" else IronFortress.new())
		root.add_child(region)
		await _frames(4)
		var barrels: Array[ExplosiveBarrel] = []
		for child in region.get_children():
			if child is ExplosiveBarrel:
				barrels.append(child)
		var expected := (BarrelPlacement.LAYOUTS[region_id] as Array).size()
		_check(barrels.size() == expected, "%s builds its %d barrels (%d)" % [region_id, expected, barrels.size()])
		var clear := 0
		for barrel in barrels:
			if _solid_overlaps(barrel) == 0:
				clear += 1
			else:
				print("    overlap: ", barrel.barrel_id, " at ", barrel.position)
		_check(clear == barrels.size(), "%s: no barrel stands inside another solid (%d/%d clear)" % [region_id, clear, barrels.size()])
		if not barrels.is_empty():
			var first := barrels[0]
			var claim := StringName("barrel_" + String(first.barrel_id))
			first.explode()
			_check(PersistentIds.is_claimed(region_id, claim), "%s: a destroyed barrel is recorded" % region_id)
		region.queue_free()
		await _frames(3)
		var again: Node3D = (ResearchComplex.new() if region_id == &"research_complex" else IronFortress.new())
		root.add_child(again)
		await _frames(4)
		var left := 0
		for child in again.get_children():
			if child is ExplosiveBarrel and not (child as ExplosiveBarrel).is_spent:
				left += 1
		_check(left == expected - 1, "%s: revisiting brings back every barrel except the destroyed one (%d of %d)" % [region_id, left, expected])
		again.queue_free()
		await _frames(3)
	if world != null:
		world.from_dict({})
