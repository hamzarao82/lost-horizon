extends SceneTree
## Ranged combat checks (Milestone 8): godot --headless --path . -s tests/ranged_check.gd
## Fairness comes from data (RangedConfig / AttackData); projectiles are checked on real physics on a
## private floor far from the arena.

const ORIGIN: Vector3 = Vector3(200.0, 0.0, 200.0)

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), message)
	if not condition:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _setup() -> void:
	Projectile.reset_pool()
	if is_instance_valid(_main):
		_main.queue_free()
		await _frames(3)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(3)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = ORIGIN + Vector3(0.0, -0.5, 0.0)
	_main.add_child(floor_body)
	_player = _main.get_node("Player") as Player
	_player.health.max_health = 100000.0
	_player.health.health = 100000.0
	_player.global_position = ORIGIN + Vector3(0.0, 0.1, 8.0)
	_player.velocity = Vector3.ZERO
	await _frames(2)


func _wall(at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 4.0, 0.5)
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_main.add_child(body)
	return body


func _shot() -> AttackData:
	return load("res://resources/attacks/ranged_shot.tres") as AttackData


## A projectile fired straight at the player's chest from `distance` metres away along -z.
func _fire_at_player(distance: float) -> Projectile:
	var origin := _player.global_position + Vector3(0.0, 1.0, -distance)
	return Projectile.fire(_main, origin, Vector3.BACK, _shot(), null, 18.0, 1.0)


func _wait_end(p: Projectile, max_frames: int = 120) -> void:
	for i in max_frames:
		if not p.is_active():
			return
		await physics_frame


func _run() -> void:
	_test_data()
	await _setup()
	await _test_hit()
	await _test_wall()
	await _test_iframes()
	await _test_armor()
	await _test_cap_and_pool()
	await _test_expiry()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("Data (fairness)")
	var cfg := (load("res://resources/enemies/facility_commander.tres") as EnemyConfig).ranged
	_check(cfg != null and cfg.validate().is_empty(), "the commander's RangedConfig validates (%s)" % str(cfg.validate()))
	_check(cfg.telegraph_seconds() >= 0.6, "telegraph %.2f s >= 0.6 s" % cfg.telegraph_seconds())
	_check(cfg.recovery_seconds() >= 0.5, "recovery %.2f s >= 0.5 s" % cfg.recovery_seconds())
	_check(cfg.shot_spacing >= 0.25, "shot spacing %.2f s >= 0.25 s" % cfg.shot_spacing)
	_check(_shot().damage == 8.0 and _shot().id == &"ranged_shot", "the shot deals 8 damage per projectile")
	var bad := RangedConfig.new()
	bad.shot_path = "res://resources/attacks/enemy_swing.tres"  # 30 frame startup = 0.5 s
	_check(not bad.validate().is_empty(), "a too-short telegraph is rejected by validate()")
	var shove := load("res://resources/attacks/ranged_shove.tres") as AttackData
	_check(shove.startup_frames >= 24, "the close-range shove is telegraphed %d frames (>= 24 = 0.4 s)" % shove.startup_frames)
	_check(Projectile.LIVE_CAP == 12, "the live projectile cap is 12")


func _test_hit() -> void:
	print("Projectile hit")
	var before: float = _player.health.health
	var p := _fire_at_player(10.0)
	_check(p != null and p.is_active(), "a projectile fires")
	await _wait_end(p)
	_check(p.ended_by == "player", "it ends on the player (%s)" % p.ended_by)
	_check(is_equal_approx(before - _player.health.health, 8.0), "it deals exactly 8 damage at level 1 (%.2f)" % (before - _player.health.health))
	var after: float = _player.health.health
	await _frames(30)
	_check(is_equal_approx(_player.health.health, after), "a projectile hits at most once")
	_check(Projectile.live_count() == 0, "no projectile stays live after the hit")
	await _frames(40)  # let the player recover from the hit state


func _test_wall() -> void:
	print("Projectile vs walls")
	await _setup()
	_wall(_player.global_position + Vector3(0.0, 2.0, -5.0))
	var before: float = _player.health.health
	var p := _fire_at_player(10.0)
	await _wait_end(p)
	_check(p.ended_by == "world", "a wall stops the projectile (%s)" % p.ended_by)
	_check(is_equal_approx(_player.health.health, before), "nothing reaches the player behind a wall")


func _test_iframes() -> void:
	print("Dodge i-frames")
	await _setup()
	_player.grant_invulnerability(2.0)
	var before: float = _player.health.health
	var p := _fire_at_player(10.0)
	await _wait_end(p)
	_check(p.ended_by == "player" and is_equal_approx(_player.health.health, before),
			"an invulnerable player takes no damage and the shot is consumed")


func _test_armor() -> void:
	print("Armor")
	await _setup()
	_player.health.set_armor(20.0)
	var health_before: float = _player.health.health
	var p := _fire_at_player(10.0)
	await _wait_end(p)
	_check(is_equal_approx(_player.health.armor, 12.0) and is_equal_approx(_player.health.health, health_before),
			"armor absorbs the shot first (armor %.1f, health lost %.1f)" % [_player.health.armor, health_before - _player.health.health])


func _test_cap_and_pool() -> void:
	print("Live cap and pool")
	await _setup()
	var up := Vector3.UP
	var shots: Array[Projectile] = []
	var refused := 0
	for i in 20:
		var p := Projectile.fire(_main, ORIGIN + Vector3(0.0, 5.0, 0.0), up, _shot(), null, 18.0, 1.0)
		if p == null:
			refused += 1
		else:
			shots.append(p)
	_check(shots.size() == 12 and refused == 8, "20 shots in one frame: 12 live, 8 refused (%d / %d)" % [shots.size(), refused])
	_check(Projectile.live_count() == 12, "live count is capped at 12")
	for p in shots:
		p.deactivate()
	_check(Projectile.live_count() == 0, "deactivating frees every slot")
	var nodes_before := _main.find_children("*", "Projectile", true, false).size()
	for round in 3:
		for i in 6:
			Projectile.fire(_main, ORIGIN + Vector3(0.0, 5.0, 0.0), up, _shot(), null, 18.0, 1.0)
		await _frames(2)
		for p in _main.find_children("*", "Projectile", true, false):
			(p as Projectile).deactivate()
	var nodes_after := _main.find_children("*", "Projectile", true, false).size()
	_check(nodes_after == nodes_before, "reusing the pool adds no nodes (%d before, %d after)" % [nodes_before, nodes_after])


func _test_expiry() -> void:
	print("Lifetime")
	await _setup()
	var p := Projectile.fire(_main, ORIGIN + Vector3(0.0, 5.0, 0.0), Vector3.UP, _shot(), null, 18.0, 1.0)
	await _frames(int(Projectile.LIFETIME * 60.0) + 10)
	_check(not p.is_active() and p.ended_by == "expired", "a shot that hits nothing expires (%s)" % p.ended_by)
	_check(Projectile.live_count() == 0, "expiry releases the slot")
