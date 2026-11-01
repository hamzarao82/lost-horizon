extends SceneTree
## Headless test runner:
##   godot --headless --path . -s tests/run_tests.gd
## Exits non-zero if any check fails.

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
	_test_attack_data()
	_test_health()
	await _test_combat()
	await _test_enemy_ai()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_attack_data() -> void:
	print("AttackData")
	for id in ["light_1", "light_2", "heavy_1", "enemy_swing"]:
		var data := load("res://resources/attacks/%s.tres" % id) as AttackData
		_check(data != null and data.validate().is_empty(), "%s loads and validates" % id)
	var bad := AttackData.new()
	bad.damage = 0.0
	_check(not bad.validate().is_empty(), "invalid attack data is rejected")


func _test_health() -> void:
	print("HealthComponent")
	var health := HealthComponent.new()
	health.max_health = 50.0
	health._ready()
	var died := [false]
	health.died.connect(func() -> void: died[0] = true)
	health.take_damage(20.0)
	_check(is_equal_approx(health.health, 30.0), "damage reduces health")
	health.take_damage(100.0)
	_check(health.is_dead() and died[0], "overkill kills once and clamps at 0")
	health.take_damage(5.0)
	_check(is_equal_approx(health.health, 0.0), "dead target takes no more damage")
	health.free()


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	return main


func _test_combat() -> void:
	print("Combat")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := main.get_node("Enemy1") as Enemy
	var enemy2 := main.get_node("Enemy2") as Enemy
	enemy2.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.global_position = player.global_position + Vector3(0, 0, -1.5)
	await _frames(2)
	var start_hp := enemy.get_node("HealthComponent").health as float

	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	_check(player.state == Player.State.ATTACK, "light attack starts on input")
	var hp_during_startup := enemy.get_node("HealthComponent").health as float
	_check(hp_during_startup == start_hp, "no damage during startup frames")
	await _frames(14)
	var hp_after := enemy.get_node("HealthComponent").health as float
	_check(is_equal_approx(start_hp - hp_after, 10.0), "light_1 deals exactly 10 once per swing (got %s)" % (start_hp - hp_after))
	await _frames(30)
	_check(player.state == Player.State.FREE, "player returns to FREE after recovery")

	# Combo: light, light chains into light_2 (12 dmg)
	enemy.global_position = player.global_position + Vector3(0, 0, -1.5)
	await _frames(2)
	var hp_before_combo := enemy.get_node("HealthComponent").health as float
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	await _frames(12)  # now in recovery of light_1
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	await _frames(20)
	var combo_damage := hp_before_combo - (enemy.get_node("HealthComponent").health as float)
	_check(is_equal_approx(combo_damage, 22.0), "light, light chain deals 10 + 12 (got %s)" % combo_damage)
	await _frames(40)

	# Dodge: stamina spent and i-frames block damage, then expire
	var stamina_before := player.stamina
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	_check(player.state == Player.State.DODGE, "dodge starts on input")
	_check(player.stamina < stamina_before, "dodge spends stamina")
	_check(player.is_invulnerable(), "invulnerable during i-frames")
	var swing := load("res://resources/attacks/enemy_swing.tres") as AttackData
	var player_hp := player.health.health
	_check(not player.receive_hit(swing, player.global_position + Vector3(0, 0, -1)), "hit during i-frames is ignored")
	await _frames(20)  # past 0.18 s
	_check(not player.is_invulnerable(), "i-frames expire")
	await _frames(20)
	_check(player.state == Player.State.FREE, "dodge ends")
	_check(player.receive_hit(swing, player.global_position + Vector3(0, 0, -1)), "hit after i-frames lands")
	_check(is_equal_approx(player.health.health, player_hp - swing.damage), "damage applied to player")

	# Death
	await _frames(40)
	player.health.take_damage(1000.0)
	_check(player.is_dead(), "player dies at 0 health")
	main.queue_free()
	await _frames(3)


func _test_enemy_ai() -> void:
	print("Enemy AI")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy1 := main.get_node("Enemy1") as Enemy
	var enemy2 := main.get_node("Enemy2") as Enemy
	enemy1.global_position = player.global_position + Vector3(0, 0, -20)
	enemy2.global_position = player.global_position + Vector3(6, 0, -22)
	enemy1.state = Enemy.State.IDLE
	enemy2.state = Enemy.State.IDLE
	await _frames(10)
	_check(enemy1.state == Enemy.State.IDLE, "enemy outside detection range stays idle")
	enemy1.global_position = player.global_position + Vector3(0, 0, -8)
	enemy2.global_position = player.global_position + Vector3(6, 0, -8)
	await _frames(30)
	_check(enemy1.state != Enemy.State.IDLE, "enemy detects player and leaves idle")

	var d0 := enemy1.global_position.distance_to(player.global_position)
	await _frames(60)
	var d1 := enemy1.global_position.distance_to(player.global_position)
	_check(d1 < d0 or enemy1.state == Enemy.State.ATTACK, "enemy closes distance")

	var attackers := 0
	var max_attackers := 0
	var player_start_hp := player.health.health
	for i in 600:
		await physics_frame
		attackers = 0
		for e in [enemy1, enemy2]:
			if (e as Enemy).state == Enemy.State.ATTACK:
				attackers += 1
		max_attackers = maxi(max_attackers, attackers)
	_check(max_attackers <= 1, "never more than one enemy attacking at once (max %d)" % max_attackers)
	_check(player.health.health < player_start_hp, "idle player eventually gets hit by enemies")

	# Kill enemy1 directly: death, group removal
	var swing := load("res://resources/attacks/heavy_1.tres") as AttackData
	enemy1.receive_hit(swing, player.global_position)
	enemy1.receive_hit(swing, player.global_position)
	enemy1.receive_hit(swing, player.global_position)
	_check(enemy1.is_dead(), "enemy dies when health reaches 0")
	_check(not enemy1.is_in_group("enemies"), "dead enemy leaves the enemies group")
	main.queue_free()
	await _frames(3)
