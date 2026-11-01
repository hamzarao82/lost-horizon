extends SceneTree
## Headless check for the Fx autoload and Enemy.damaged:
##   godot --headless --path . -s tests/fx_check.gd
## Exits non-zero if any check fails.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"
const ITEMS: String = "res://resources/items/"

var _failures: int = 0
var _checks: int = 0
var _fx: Node


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


func _settle() -> void:
	# Fx animates on scaled process time; wait past the longest effect (0.7 s numbers, 0.6 s bursts).
	await create_timer(1.2).timeout
	await process_frame


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _spawn_enemy(main: Node, path: String, pos: Vector3, frozen: bool = true) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	enemy.position = pos  # before add_child so it never overlaps the player at the origin
	main.add_child(enemy)
	if frozen:
		enemy.set_physics_process(false)
	return enemy


func _item(id: String) -> ItemData:
	return load(ITEMS + id + ".tres") as ItemData


func _run() -> void:
	_fx = root.get_node_or_null("Fx")
	_check(_fx != null, "Fx autoload is present")
	if _fx == null:
		quit(1)
		return
	var caps: Dictionary = _fx.pool_sizes()
	_check(caps == {
		"sparks": 8, "dust": 4, "bursts": 3, "shimmers": 6, "rings": 6, "numbers": 16,
	}, "pools are built at their caps %s" % [caps])
	var total_cap := 0
	for key in caps:
		total_cap += int(caps[key])

	await _test_enemy_damage_signal()
	await _test_pool_caps(total_cap)
	await _test_kill_and_death_effects()
	await _test_player_effects()
	await _test_quality()
	await _test_dodge_dust_and_pickup()
	await _test_reload()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_enemy_damage_signal() -> void:
	print("Enemy.damaged")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _spawn_enemy(main, SOLDIER, player.global_position + Vector3(0, 0, -1.5))
	player.inventory.add_item(_item("military_machete"))
	await _frames(2)
	var seen: Array = []
	enemy.damaged.connect(func(amount: float, pos: Vector3, was_kill: bool) -> void:
		seen.append([amount, pos, was_kill]))
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	await _frames(14)
	_check(seen.size() == 1, "one damaged signal per landed swing (got %d)" % seen.size())
	if seen.size() == 1:
		_check(is_equal_approx(seen[0][0], 15.0), "damaged carries the machete-scaled amount (got %s)" % seen[0][0])
		_check((seen[0][1] as Vector3).distance_to(enemy.global_position) < 2.0, "impact point is on the enemy")
		_check(seen[0][2] == false, "a non-lethal hit is not flagged as a kill")
	_check(_fx.active_count() >= 2, "a landed hit spawns sparks and a damage number (%d active)" % _fx.active_count())
	await _settle()
	_check(_fx.active_count() == 0, "effects return to idle after they finish")
	main.queue_free()
	await _frames(3)


func _test_pool_caps(total_cap: int) -> void:
	print("Pool caps")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _spawn_enemy(main, SOLDIER, Vector3(-20, 0.1, -20))
	var hc := enemy.get_node("HealthComponent") as HealthComponent
	hc.max_health = 1.0e6
	hc.health = 1.0e6
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	await _frames(2)
	var children_before := _fx.get_child_count()
	var sizes_before: Dictionary = _fx.pool_sizes()
	var peak := 0
	for i in 200:
		enemy.receive_hit(light, player.global_position)
		peak = maxi(peak, _fx.active_count())
	_check(_fx.get_child_count() == children_before, "200 rapid hits add no nodes under Fx")
	_check(_fx.pool_sizes() == sizes_before, "pool sizes are unchanged after 200 hits")
	_check(peak <= total_cap, "active effects never exceed the caps (peak %d / %d)" % [peak, total_cap])
	await _settle()
	_check(_fx.active_count() == 0, "all effects are idle again after the flood")
	main.queue_free()
	await _frames(3)


func _test_kill_and_death_effects() -> void:
	print("Kill and death burst")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _spawn_enemy(main, SOLDIER, Vector3(-20, 0.1, -20))
	var kills: Array = []
	enemy.damaged.connect(func(_a: float, _p: Vector3, was_kill: bool) -> void: kills.append(was_kill))
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 3:
		enemy.receive_hit(heavy, player.global_position)
	_check(enemy.is_dead() and kills.size() == 3, "three heavy hits kill a soldier with three damaged signals")
	_check(kills.size() == 3 and kills[2] == true and kills[0] == false, "only the last hit is flagged as the kill")
	await process_frame
	_check(_fx.active_count() >= 5, "death spawns a burst and ring on top of hit effects (%d active)" % _fx.active_count())
	await _settle()
	main.queue_free()
	await _frames(3)


func _test_player_effects() -> void:
	print("Player numbers")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	await _settle()
	_check(_fx.active_count() == 0, "idle before player damage")
	player.health.take_damage(12.0)
	_check(_fx.active_count() == 1, "taking damage shows one floating number")
	await _settle()
	player.health.heal(5.0)
	_check(_fx.active_count() == 1, "healing shows one floating number")
	await _settle()
	main.queue_free()
	await _frames(3)


func _test_quality() -> void:
	print("Quality scale")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _spawn_enemy(main, SOLDIER, Vector3(-20, 0.1, -20))
	var hc := enemy.get_node("HealthComponent") as HealthComponent
	hc.max_health = 1.0e6
	hc.health = 1.0e6
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	await _settle()

	_fx.quality_scale = 0.0
	enemy.receive_hit(light, player.global_position)
	_check(_fx.active_count() == 1, "quality 0 disables particles but keeps the damage number")
	await _settle()

	_fx.quality_scale = 0.4
	_check((_fx.get("_sparks").nodes[0] as CPUParticles3D).amount == 5, "Low quality trims spark count to 5")
	_fx.quality_scale = 1.0
	_check((_fx.get("_sparks").nodes[0] as CPUParticles3D).amount == 12, "High quality restores 12 sparks")
	enemy.receive_hit(light, player.global_position)
	_check(_fx.active_count() >= 2, "quality 1 spawns sparks plus a number")
	await _settle()
	main.queue_free()
	await _frames(3)


func _test_dodge_dust_and_pickup() -> void:
	print("Dust, dodge and pickup")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	await _settle()
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	await _frames(2)
	await process_frame
	_check(player.state == Player.State.DODGE and _fx.active_count() >= 1, "dodging kicks up a dust puff")
	await _settle()
	await _frames(40)

	var hunter := _spawn_enemy(main, HUNTER, Vector3(-20, 0.1, -20))
	hunter.dodge_chance = 1.0
	hunter.state = Enemy.State.CHASE
	var damaged_count := [0]
	hunter.damaged.connect(func(_a: float, _p: Vector3, _k: bool) -> void: damaged_count[0] += 1)
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	hunter.receive_hit(light, hunter.global_position + Vector3(0, 0, 2))
	_check(damaged_count[0] == 0, "a dodged hit emits no damaged signal")
	_check(_fx.active_count() >= 1, "a dodged hit puffs dust")
	hunter.set_physics_process(false)
	await _settle()

	Pickup.spawn(main, _item("health_potion"), Vector3(10, 0.0, 10))
	_check(_fx.active_count() >= 1, "a new pickup shimmers")
	await _settle()
	main.queue_free()
	await _frames(3)


func _test_reload() -> void:
	print("Scene reload")
	var children_before := _fx.get_child_count()
	var sizes_before: Dictionary = _fx.pool_sizes()
	for i in 3:
		var main := await _spawn_main()
		var player := main.get_node("Player") as Player
		var enemy := _spawn_enemy(main, SOLDIER, Vector3(-20, 0.1, -20))
		enemy.receive_hit(load("res://resources/attacks/heavy_1.tres") as AttackData, player.global_position)
		main.queue_free()
		await _frames(3)
	_check(_fx.get_child_count() == children_before and _fx.pool_sizes() == sizes_before,
			"pools survive repeated scene teardown with no growth")
	await _settle()
	_check(_fx.active_count() == 0, "no effect is stuck after reloads")
