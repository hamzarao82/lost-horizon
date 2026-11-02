extends SceneTree
## Warden design checks (Milestone 4): godot --headless --path . -s tests/warden_design_check.gd
## Fairness comes from the frame data (read from the .tres files); behaviour is checked on a real
## Warden fighting on a private floor far from the arena, so decor never interferes.

const ORIGIN: Vector3 = Vector3(200.0, 0.0, 200.0)

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player
var _seen_patrol_state: bool = false


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


func _data(name: String) -> AttackData:
	return load("res://resources/attacks/%s.tres" % name) as AttackData


func _setup() -> void:
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


func _boss(at: Vector3) -> Warden:
	var boss := (load("res://scenes/enemies/Warden.tscn") as PackedScene).instantiate() as Warden
	boss.position = at
	_main.add_child(boss)
	await _frames(3)
	boss._cooldown = 9999.0
	boss.state = Enemy.State.CHASE
	return boss


func _watch(boss: Warden) -> void:
	if boss.state in [Enemy.State.PATROL, Enemy.State.SUSPICIOUS, Enemy.State.SEARCH, Enemy.State.RETURN]:
		_seen_patrol_state = true


func _pin(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO


func _run() -> void:
	_test_frame_data()
	await _setup()
	await _test_phase_and_roar()
	await _test_attack_choice()
	await _test_charge()
	await _test_leap()
	await _test_fire_lines()
	await _test_defeat()
	_check(not _seen_patrol_state, "the Warden never entered a patrol state during any test")
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_frame_data() -> void:
	print("Frame data (fairness)")
	var slam := _data("warden_slam")
	var charge := _data("warden_charge")
	var leap := _data("warden_leap")
	var fire := _data("warden_fire")
	var flurry := _data("warden_flurry")
	_check(slam.startup_frames >= 36 and charge.startup_frames >= 48 and leap.startup_frames >= 48,
			"telegraphs: slam %d, charge %d, leap %d frames (>= 36 / 48 / 48)" % [slam.startup_frames, charge.startup_frames, leap.startup_frames])
	_check(fire.startup_frames >= 36, "fire lines are telegraphed by the slam that precedes them (%d frames)" % fire.startup_frames)
	for a in [slam, charge, leap, fire]:
		_check(a.recovery_frames >= 30, "%s recovery %d frames >= 30" % [a.id, a.recovery_frames])
	_check(slam.damage == 22.0 and slam.startup_frames == 36 and slam.active_frames == 8 and slam.recovery_frames == 40,
			"baseline slam numbers are unchanged (22 damage, 36/8/40)")
	_check(charge.damage == 18.0 and leap.damage == 20.0, "charge 18 damage, leap 20 damage")
	# The flurry is the documented exception: a quick chained follow-up to the slam (baseline numbers kept).
	var scene := load("res://scenes/enemies/Warden.tscn") as PackedScene
	var cooldown_min := 1.6 * Warden.PHASE2_COOLDOWN_SCALE  # phase 2 minimum cooldown
	_check(flurry.startup_frames == 14 and (flurry.recovery_frames / 60.0 + cooldown_min) >= 0.5,
			"flurry stays 14 startup but is chained after a slam and leaves >= 0.5 s before the next attack")
	_check(scene != null and Warden.PHASE2_THRESHOLD == 0.4, "phase 2 threshold is 40%")


func _test_phase_and_roar() -> void:
	print("Phase change and roar")
	var boss := await _boss(ORIGIN + Vector3(0.0, 0.1, -10.0))
	boss.set_physics_process(false)
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	var hp := boss.get_node("HealthComponent") as HealthComponent
	hp.health = 420.0 * 0.41  # just above 40%
	boss.receive_hit(load("res://resources/attacks/light_1.tres") as AttackData, _player.global_position, 0.0)
	_check(not boss.phase2, "above 40% there is no phase change")
	hp.health = 420.0 * 0.4 + 5.0
	boss.receive_hit(heavy, _player.global_position)
	_check(boss.phase2 and boss.stats["phase_changes"] == 1, "crossing 40% starts phase 2 once")
	var hp_roar := hp.health
	_check(not boss.receive_hit(heavy, _player.global_position) and hp.health == hp_roar, "invulnerable during the roar")
	boss.receive_hit(heavy, _player.global_position)
	_check(boss.stats["phase_changes"] == 1, "a second hit does not start another phase change")
	_check(Warden.ROAR_TIME == 2.5 and is_equal_approx(boss._roar_time, 2.5), "the roar lasts 2.5 s")
	var harmless := true
	for wave in boss._shockwaves:
		harmless = harmless and wave["hit"]
	_check(boss._shockwaves.size() >= 1 and harmless, "the roar pulse is a harmless ring")
	boss.queue_free()
	await _frames(3)


func _test_attack_choice() -> void:
	print("Attack choice")
	var boss := await _boss(ORIGIN + Vector3(0.0, 0.1, -10.0))
	boss.set_physics_process(false)
	var seen := {}
	var streak := 0
	var max_streak := 0
	var specials_back_to_back := false
	var last_special := false
	for i in 400:
		var kind := boss._pick_attack(8.0)
		boss._note_choice(kind)
		seen[kind] = int(seen.get(kind, 0)) + 1
		streak = streak + 1 if kind == &"slam" else 0
		max_streak = maxi(max_streak, streak)
		if kind != &"slam" and last_special:
			specials_back_to_back = true
		last_special = kind != &"slam"
	_check(seen.has(&"slam") and seen.has(&"charge") and not seen.has(&"leap"), "phase 1 mixes slam and charge, no leap")
	_check(max_streak <= 3 and not specials_back_to_back, "at most 3 slams in a row and no two specials in a row")
	_check(boss._pick_attack(2.0) == &"slam", "up close he only slams (no charge without room)")
	boss.phase2 = true
	seen.clear()
	for i in 400:
		var kind := boss._pick_attack(8.0)
		boss._note_choice(kind)
		seen[kind] = int(seen.get(kind, 0)) + 1
	_check(seen.has(&"slam") and seen.has(&"charge") and seen.has(&"leap"), "phase 2 mixes slam, charge and leap")
	boss.queue_free()
	await _frames(3)


func _test_charge() -> void:
	print("Charge")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 6.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = ORIGIN + Vector3(0.0, 3.0, 16.5)
	_main.add_child(wall)
	var boss := await _boss(ORIGIN + Vector3(0.0, 0.1, 4.0))
	_pin(ORIGIN + Vector3(0.0, 0.1, 9.0))
	var hp_before := _player.health.health
	boss.forced_attack = &"charge"
	boss._cooldown = 0.0
	boss._start_attack()
	var telegraph_frames := 0
	while boss._sp_phase == 0 and telegraph_frames < 200:
		await physics_frame
		_pin(ORIGIN + Vector3(0.0, 0.1, 9.0))
		telegraph_frames += 1
		_watch(boss)
	_check(telegraph_frames >= 47, "the rush starts only after the 0.8 s telegraph (%d frames)" % telegraph_frames)
	_check(boss._arrows != null, "two ground arrows were shown during the telegraph")
	var max_z := -INF
	for i in 120:
		await physics_frame
		max_z = maxf(max_z, boss.global_position.z)
		if boss._sp_phase == 2:
			break
	var lost := hp_before - _player.health.health
	_check(is_equal_approx(lost, 18.0), "the charge hit the player once for 18 (lost %.1f)" % lost)
	_check(boss.stats["wall_stuns"] == 1 and is_equal_approx(boss._sp_timer, Warden.CHARGE_WALL_STUN), "it ended against the wall with a 1.5 s stun")
	_check(max_z < ORIGIN.z + 16.0, "he stopped at the wall instead of going through (z %.2f, wall face %.2f)" % [max_z - ORIGIN.z, 16.0])
	var stun_hp := (boss.get_node("HealthComponent") as HealthComponent).health
	boss.receive_hit(load("res://resources/attacks/light_1.tres") as AttackData, ORIGIN)
	_check((boss.get_node("HealthComponent") as HealthComponent).health < stun_hp, "he can be hit during the stun")
	await _frames(100)
	_check(boss.state == Enemy.State.CHASE and boss._special == &"", "after the stun he is back to normal")
	boss.queue_free()
	wall.queue_free()
	await _frames(3)


func _test_leap() -> void:
	print("Leap slam")
	var boss := await _boss(ORIGIN + Vector3(0.0, 0.1, -8.0))
	boss.phase2 = true
	_pin(ORIGIN + Vector3(0.0, 0.1, 4.0))
	var hp_before := _player.health.health
	boss.forced_attack = &"leap"
	boss._cooldown = 0.0
	boss._start_attack()
	await _frames(40)  # past the lock (50% of 60 frames)
	var marker := boss._leap_to
	_check(boss._marker != null and boss._marker.visible, "a shadow marker shows where he will land")
	_pin(ORIGIN + Vector3(15.0, 0.1, -10.0))  # leave the marker
	var frames := 0
	while boss._special == &"leap" and boss._sp_phase < 2 and frames < 200:
		await physics_frame
		_pin(ORIGIN + Vector3(15.0, 0.1, -10.0))
		frames += 1
		_watch(boss)
	var flat := Vector2(boss.global_position.x - marker.x, boss.global_position.z - marker.z)
	_check(flat.length() < 1.0, "he lands on the marker (%.2f m off)" % flat.length())
	_check(_player.health.health == hp_before, "a player who left the marker takes no damage")
	await _frames(80)
	# Second leap: stay on the marker
	boss.state = Enemy.State.CHASE
	_pin(ORIGIN + Vector3(0.0, 0.1, 6.0))
	boss._cooldown = 0.0
	boss._start_attack()
	frames = 0
	while boss._special == &"leap" and boss._sp_phase < 2 and frames < 250:
		await physics_frame
		_pin(boss._leap_to + Vector3(0.0, 0.1, 0.0))
		frames += 1
	var lost := hp_before - _player.health.health
	_check(is_equal_approx(lost, 20.0), "a player on the marker takes 20 once (lost %.1f)" % lost)
	_check(is_equal_approx(boss._sp_timer, 1.0), "1.0 s recovery after landing")
	boss.queue_free()
	await _frames(3)


func _test_fire_lines() -> void:
	print("Fire lines")
	var boss := await _boss(ORIGIN + Vector3(0.0, 0.1, -10.0))
	boss.phase2 = true
	var origin := boss.global_position
	# Between the lines: nothing happens
	_pin(origin + Vector3(0.0, 0.0, 5.0))
	boss._spawn_fire_lines()
	_check(boss._fire_lines.size() == 3, "three fire lines spawn")
	var safe_spot := origin + Vector3(0.0, 0.0, 5.0).rotated(Vector3.UP, deg_to_rad(60.0))
	var hp_before := _player.health.health
	for i in 150:
		_pin(safe_spot)
		await physics_frame
	_check(_player.health.health == hp_before and boss.stats["fire_ticks"] == 0, "standing between the lines costs nothing")
	_check(boss._fire_lines.is_empty(), "the lines are gone after 2.0 s")
	# On a line: ticks no more often than every 0.5 s
	boss.stats["fire_ticks"] = 0
	_pin(origin + Vector3(0.0, 0.0, 5.0))
	boss._spawn_fire_lines()
	hp_before = _player.health.health
	var frames := 0
	while not boss._fire_lines.is_empty() and frames < 300:
		_pin(origin + Vector3(0.0, 0.0, 5.0))
		await physics_frame
		frames += 1
	var ticks: int = boss.stats["fire_ticks"]
	var seconds := frames / 60.0
	_check(ticks >= 1 and ticks <= int(seconds / Warden.FIRE_TICK) + 1, "burn ticks are rate limited: %d ticks in %.2f s" % [ticks, seconds])
	_check(is_equal_approx(hp_before - _player.health.health, ticks * 6.0), "each tick deals 6 (lost %.1f)" % (hp_before - _player.health.health))
	boss.queue_free()
	await _frames(3)


func _test_defeat() -> void:
	print("Defeat")
	var boss := await _boss(ORIGIN + Vector3(0.0, 0.1, -10.0))
	boss.set_physics_process(false)
	boss._begin_phase2()
	await _frames(5)
	var summons := boss._summons.duplicate()
	_check(summons.size() == 2, "two soldiers were summoned (%d)" % summons.size())
	boss._spawn_fire_lines()
	boss.state = Enemy.State.CHASE
	(boss.get_node("HealthComponent") as HealthComponent).take_damage(100000.0)
	await _frames(6)
	var gone := true
	for s in summons:
		gone = gone and (not is_instance_valid(s) or (s as Node).is_queued_for_deletion())
	_check(boss.is_dead() and gone, "he dies and the living summons are removed")
	_check(boss._fire_lines.is_empty(), "fire lines are cleared on death")
	var ids: Array[StringName] = []
	for child in _main.get_children():
		if child is Pickup:
			ids.append((child as Pickup).item.item_id)
	_check(ids.has(&"warden_blade") and ids.has(&"warden_plate") and ids.count(&"health_potion") == 2,
			"the guaranteed loot (cleaver, plate, two medkits) still drops")
	if is_instance_valid(_main):
		_main.queue_free()
	await _frames(3)
