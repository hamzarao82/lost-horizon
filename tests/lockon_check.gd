extends SceneTree
## Lock-on checks:
##   godot --headless --path . -s tests/lockon_check.gd
## Exits non-zero if any check fails.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"

var _failures: int = 0
var _checks: int = 0


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
	_test_targeting_logic()
	await _test_player_lock()
	await _test_locked_attacks()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _fake_enemy(pos: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	root.add_child(node)
	return node


func _test_targeting_logic() -> void:
	print("Targeting")
	var forward := Vector3(0, 0, -1)
	var origin := Vector3.ZERO
	var ahead := _fake_enemy(Vector3(0, 0, -6))
	var right := _fake_enemy(Vector3(4, 0, -4))
	var left := _fake_enemy(Vector3(-4, 0, -4))
	var behind := _fake_enemy(Vector3(0, 0, 5))
	var far := _fake_enemy(Vector3(0, 0, -30))
	var all: Array = [ahead, right, left, behind, far]

	_check(Targeting.signed_angle(forward, Vector3(1, 0, 0)) > 0.0, "an enemy on the right has a positive angle")
	_check(Targeting.signed_angle(forward, Vector3(-1, 0, 0)) < 0.0, "an enemy on the left has a negative angle")

	var found := Targeting.candidates(origin, forward, all)
	_check(not found.has(behind) and not found.has(far), "enemies behind the camera or out of range are not candidates")
	_check(found.size() == 3 and found[0] == ahead, "the enemy nearest the screen centre ranks first")

	var targeting := Targeting.new()
	_check(targeting.acquire(origin, forward, all) == ahead, "acquire picks the enemy nearest the centre")
	_check(targeting.cycle(1, origin, forward, all) == right, "cycling right picks the enemy on the right")
	_check(targeting.cycle(1, origin, forward, all) == left, "cycling right again wraps to the leftmost enemy")
	_check(targeting.cycle(-1, origin, forward, all) == right, "cycling left steps back")

	targeting.acquire(origin, forward, all)
	_check(targeting.update(0.016, origin), "a nearby living target stays locked")
	ahead.position = Vector3(0, 0, -25)
	_check(not targeting.update(0.016, origin) and targeting.target == null, "the lock drops beyond the drop range")

	var solo := Targeting.new()
	solo.acquire(origin, forward, [right])
	right.queue_free()
	await _frames(2)
	_check(not solo.update(0.016, origin) and solo.target == null, "the lock drops when the target is freed")
	_check(solo.cycle(1, origin, forward, []) == null, "cycling with no enemies returns nothing and does not crash")

	for node in [ahead, left, behind, far]:
		node.queue_free()
	await _frames(2)


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _spawn_enemy(main: Node, pos: Vector3) -> Enemy:
	var enemy := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	enemy.position = pos  # before add_child so it never overlaps the player
	main.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _press(action: String, hold_frames: int = 2) -> void:
	Input.action_press(action)
	await _frames(hold_frames)
	Input.action_release(action)


func _hp(enemy: Enemy) -> float:
	return (enemy.get_node("HealthComponent") as HealthComponent).health


func _test_player_lock() -> void:
	print("Player lock-on")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var camera := main.get_node("Player/CameraPivot") as CameraController

	await _press("lock_on")
	_check(player.lock_target() == null and not camera.has_lock_target(), "locking with no enemies is a harmless no-op")

	var near := _spawn_enemy(main, Vector3(0, 0.1, -4))
	var side := _spawn_enemy(main, Vector3(5, 0.1, -5))
	await _frames(2)
	await _press("lock_on")
	_check(player.lock_target() == near, "pressing lock_on locks the enemy ahead")
	_check(camera.has_lock_target(), "the camera follows the locked target")
	_check(near.get_children().any(func(c: Node) -> bool: return c is MeshInstance3D and c.get_parent() == near and c.position.y > 2.0),
			"a marker floats above the locked enemy")

	_check(player.cycle_lock(1) and player.lock_target() == side, "cycle_lock moves to the next enemy")
	camera.set_lock_target(side)
	await _frames(30)
	_check(true, "camera lock follow runs without errors")

	await _press("lock_on")
	_check(player.lock_target() == null and not camera.has_lock_target(), "pressing lock_on again releases the lock")

	await _press("lock_on")
	_check(player.lock_target() != null, "the lock can be re-acquired")
	side.set_physics_process(true)
	side.receive_hit(load("res://resources/attacks/heavy_1.tres") as AttackData, Vector3.ZERO, 100.0)
	await _frames(4)
	if player.lock_target() == side:
		await _frames(2)
	_check(player.lock_target() != side, "the lock drops when its target dies")

	camera.clear_lock_target()
	camera.add_trauma(0.5)
	camera.set_lock_target(null)
	await _frames(5)
	_check(true, "camera API accepts null and shake still runs")

	main.queue_free()
	await _frames(3)


func _test_locked_attacks() -> void:
	print("Locked attacks")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	# Player faces -Z. 'target' is straight ahead in reach; 'decoy' is closer but behind-right.
	var target := _spawn_enemy(main, Vector3(0, 0.1, -1.6))
	var decoy := _spawn_enemy(main, Vector3(1.0, 0.1, 0.9))
	await _frames(3)
	await _press("lock_on")
	_check(player.lock_target() == target, "lock-on picks the enemy in front even though another is closer")

	var target_hp := _hp(target)
	var decoy_hp := _hp(decoy)
	await _press("attack_light")
	await _frames(16)
	_check(_hp(target) < target_hp, "the attack hits the locked target")
	_check(_hp(decoy) == decoy_hp, "the nearer, unlocked enemy is not the one faced")
	main.queue_free()
	await _frames(3)
