extends SceneTree
## Milestone 11 guard stance (headless): godot --headless --path . -s tests/guard_stance_check.gd
## Rule under test: while chasing and facing the attacker (front 120 degrees), light hits are cut by
## guard_reduction and never stagger; each block opens a vulnerability window of guard_vulnerable_seconds in
## which hits land in full. Heavy, sprint and ring attacks, hits from the side or behind, and an enemy that is
## not chasing (attacking, retreating, staggered, idle) are never guarded. Default (guard_reduction = 0) is untouched.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const PLAYER_AT: Vector3 = Vector3(0.0, 0.1, -24.0)

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
		outpost.free()
	_player = _main.get_node("Player") as Player
	await _frames(2)

	await _test_default_unchanged()
	await _test_front_block()
	await _test_window()
	await _test_bypasses()
	await _test_not_chasing()
	for node in _extras:
		if is_instance_valid(node):
			node.queue_free()
	print("\nguard_stance_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _spawn(guard: float, window: float = 1.0) -> Enemy:
	for node in _extras:
		if is_instance_valid(node):
			node.queue_free()
	_extras.clear()
	await _frames(2)
	_player.global_position = PLAYER_AT
	_player.velocity = Vector3.ZERO
	Enemy.active_patrollers = 0
	var enemy := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	enemy.hit_points = 400.0
	enemy.guard_reduction = guard
	enemy.guard_vulnerable_seconds = window
	enemy.position = PLAYER_AT + Vector3(0.0, 0.0, 18.0)
	_main.add_child(enemy)
	_extras.append(enemy)
	enemy.aggro()
	await _frames(3)
	return enemy


func _forward(enemy: Enemy) -> Vector3:
	var yaw := (enemy.get_node("VisualRoot") as Node3D).rotation.y
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func _attack(id: StringName, damage: float = 20.0, ring: float = 0.0) -> AttackData:
	var attack := AttackData.new()
	attack.id = id
	attack.damage = damage
	attack.knockback = 0.0
	attack.stagger_time = 0.2
	attack.aoe_radius = ring
	return attack


## Hits from `side` (1 = front, 0 = right angle, -1 = behind) and returns the health actually lost.
func _hit(enemy: Enemy, attack: AttackData, side: float = 1.0) -> float:
	var forward := _forward(enemy)
	var right := Vector3(-forward.z, 0.0, forward.x)
	var dir := (forward * side + right * sqrt(maxf(0.0, 1.0 - side * side))).normalized()
	var before: float = enemy._health.health
	enemy.receive_hit(attack, enemy.global_position + dir * 2.0)
	return before - enemy._health.health


func _test_default_unchanged() -> void:
	print("Default enemy")
	var enemy := await _spawn(0.0)
	_check(enemy.guard_reduction == 0.0, "guard is off by default")
	var lost := _hit(enemy, _attack(&"light_1"))
	_check(is_equal_approx(lost, 20.0), "a frontal light hit lands in full (%.1f)" % lost)
	_check(enemy.state == Enemy.State.STAGGER, "and staggers as before")


func _test_front_block() -> void:
	print("Frontal block")
	var enemy := await _spawn(0.5)
	_check(enemy.state == Enemy.State.CHASE, "the guard enemy is chasing")
	var lost := _hit(enemy, _attack(&"light_1"))
	_check(is_equal_approx(lost, 10.0), "a frontal light hit is cut by 50%% (%.1f of 20)" % lost)
	_check(enemy.state == Enemy.State.CHASE, "a blocked hit does not stagger")


func _test_window() -> void:
	print("Vulnerability window")
	var enemy := await _spawn(0.5, 0.5)
	_hit(enemy, _attack(&"light_1"))
	var lost := _hit(enemy, _attack(&"light_2"))
	_check(is_equal_approx(lost, 20.0), "the hit right after a block lands in full (%.1f)" % lost)
	_check(enemy.state == Enemy.State.STAGGER, "and staggers: the window is open")
	enemy = await _spawn(0.5, 0.5)
	_hit(enemy, _attack(&"light_1"))
	await _frames(40)  # 0.67 s > the 0.5 s window
	_check(enemy.state == Enemy.State.CHASE, "the enemy is still chasing after the window")
	lost = _hit(enemy, _attack(&"light_1"))
	_check(is_equal_approx(lost, 10.0), "the guard is back after the window (%.1f of 20)" % lost)


func _test_bypasses() -> void:
	print("Bypasses")
	var enemy := await _spawn(0.5)
	var lost := _hit(enemy, _attack(&"light_1"), -1.0)
	_check(is_equal_approx(lost, 20.0), "a hit from behind lands in full (%.1f)" % lost)
	enemy = await _spawn(0.5)
	lost = _hit(enemy, _attack(&"light_1"), 0.0)
	_check(is_equal_approx(lost, 20.0), "a hit from the side (90 degrees) lands in full (%.1f)" % lost)
	enemy = await _spawn(0.5)
	lost = _hit(enemy, _attack(&"heavy_1", 30.0))
	_check(is_equal_approx(lost, 30.0), "a heavy attack bypasses the guard (%.1f)" % lost)
	enemy = await _spawn(0.5)
	lost = _hit(enemy, _attack(&"sprint_attack", 25.0))
	_check(is_equal_approx(lost, 25.0), "a sprint attack bypasses the guard (%.1f)" % lost)
	enemy = await _spawn(0.5)
	lost = _hit(enemy, _attack(&"spin_special", 25.0, 3.0))
	_check(is_equal_approx(lost, 25.0), "a ring attack bypasses the guard (%.1f)" % lost)


func _test_not_chasing() -> void:
	print("Not chasing")
	var enemy := await _spawn(0.5)
	enemy._retreat_left = 2.0
	var lost := _hit(enemy, _attack(&"light_1"))
	_check(is_equal_approx(lost, 20.0), "a retreating enemy does not guard (%.1f)" % lost)
	enemy = await _spawn(0.5)
	enemy.state = Enemy.State.ATTACK
	lost = _hit(enemy, _attack(&"light_1"))
	_check(is_equal_approx(lost, 20.0), "an attacking enemy does not guard (%.1f)" % lost)
	enemy = await _spawn(0.5)
	enemy.state = Enemy.State.IDLE
	lost = _hit(enemy, _attack(&"light_1"))
	_check(is_equal_approx(lost, 20.0), "an idle enemy does not guard (%.1f)" % lost)
	enemy = await _spawn(0.5)
	_check(enemy._guard_blocks(_attack(&"light_1"), enemy.global_position + _forward(enemy) * 2.0), "_guard_blocks agrees for a chasing enemy")
	_check(not enemy._guard_blocks(_attack(&"light_1"), enemy.global_position - _forward(enemy) * 2.0), "_guard_blocks refuses from behind")
