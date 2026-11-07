extends SceneTree
## Research Complex enemies (Milestone 8): godot --headless --path . -s tests/experimental_enemies_check.gd
## Fairness comes from the attack data (read from the .tres files). Behaviour is checked on real enemies
## fighting the real Player on a private floor far from the arena.

const ORIGIN: Vector3 = Vector3(300.0, 0.0, 300.0)
const FPS: float = 60.0

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player
var _seen_patrol: bool = false


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
	_pin(ORIGIN + Vector3(0.0, 0.1, 8.0))
	root.get_node("WorldState").reset()
	root.get_node("RegionManager").reset()


func _pin(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO


func _spawn_config(name: String, at: Vector3) -> Enemy:
	var config := load("res://resources/enemies/facility_%s.tres" % name) as FacilityEnemyConfig
	var scene := load(config.base_scene_path) as PackedScene
	var enemy := scene.instantiate() as Enemy
	config.apply(enemy)
	enemy.position = at
	_main.add_child(enemy)
	await _frames(3)
	return enemy


func _watch(enemy: Enemy) -> void:
	if enemy.state in [Enemy.State.PATROL, Enemy.State.SUSPICIOUS, Enemy.State.SEARCH, Enemy.State.RETURN]:
		_seen_patrol = true


func _pickups() -> Array:
	return _main.find_children("*", "Pickup", true, false)


func _kill_by_hits(enemy: Enemy, limit: int = 600) -> void:
	var heavy := _data("heavy_1")
	for i in limit:
		if enemy.is_dead():
			return
		enemy.receive_hit(heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame


func _run() -> void:
	_test_data()
	await _setup()
	await _test_subject()
	await _test_heavy_guard()
	await _test_elite_attacks()
	await _test_elite_charge_wall()
	await _test_elite_defeat()
	print("experimental_enemies_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("-- fairness from the data")
	for name in ["facility_shield_bash", "experimental_lunge", "experimental_claw", "experimental_ring", "experimental_charge"]:
		var attack := _data(name)
		_check(attack != null and attack.validate().is_empty(), "%s loads and validates" % name)
	var lunge := _data("experimental_lunge")
	_check(lunge.startup_frames >= 24, "the subject's lunge telegraph is at least 0.4 s (%.2f s)" % (lunge.startup_frames / FPS))
	_check(lunge.recovery_frames >= 24, "and its recovery is at least 0.4 s (%.2f s)" % (lunge.recovery_frames / FPS))
	var bash := _data("facility_shield_bash")
	_check(bash.startup_frames >= 36 and bash.recovery_frames >= 30, "the heavy guard's bash has a long telegraph (%.2f s) and a punish window (%.2f s)" % [bash.startup_frames / FPS, bash.recovery_frames / FPS])
	for name in ["experimental_claw", "experimental_ring"]:
		var a := _data(name)
		_check(a.startup_frames >= 36, "%s telegraph is at least 0.6 s (%.2f s)" % [name, a.startup_frames / FPS])
		_check(a.recovery_frames >= 30, "%s punish window is at least 0.5 s (%.2f s)" % [name, a.recovery_frames / FPS])
	var charge := _data("experimental_charge")
	_check(charge.startup_frames >= 48, "the charge telegraph is at least 0.8 s (%.2f s)" % (charge.startup_frames / FPS))
	_check(charge.recovery_frames >= 30 and EliteExperimentalSubject.CHARGE_SHORT_STUN >= 0.5 and EliteExperimentalSubject.CHARGE_WALL_STUN >= 1.0, "the charge always leaves a stun of at least 0.5 s (wall stun %.1f s)" % EliteExperimentalSubject.CHARGE_WALL_STUN)
	var elite := load("res://resources/enemies/facility_elite_subject.tres") as FacilityEnemyConfig
	var warden_phase1 := 420.0 * (1.0 - Warden.PHASE2_THRESHOLD)
	_check(elite.hit_points > warden_phase1 and elite.hit_points < 420.0, "elite health (%.0f) is above the Warden's phase 1 share (%.0f) and below the Warden (420)" % [elite.hit_points, warden_phase1])
	var subject := load("res://resources/enemies/facility_experimental_subject.tres") as FacilityEnemyConfig
	_check(not subject.patrols and not elite.patrols, "subjects never patrol (config)")
	_check(elite.reward_item_path != "" and (load(elite.reward_item_path) as ItemData).unique, "the elite's reward is a unique item")


func _test_subject() -> void:
	print("-- experimental subject")
	_pin(ORIGIN + Vector3(0.0, 0.1, 40.0))
	var subject := await _spawn_config("experimental_subject", ORIGIN + Vector3(0.0, 0.1, 0.0)) as ExperimentalSubject
	_check(subject != null and subject.patrol_route == null, "the subject has no patrol route")
	for i in 120:
		_watch(subject)
		await physics_frame
	_check(subject.state == Enemy.State.IDLE and not _seen_patrol, "far from the player it idles (no patrol, no wandering)")
	_pin(ORIGIN + Vector3(0.0, 0.1, 7.0))
	await _frames(20)
	_check(subject.state == Enemy.State.CHASE or subject.state == Enemy.State.ATTACK, "it wakes by proximity")
	var health_before: float = _player.health.health
	var lunge_damage := _data("experimental_lunge").damage
	var pinned := ORIGIN + Vector3(0.0, 0.1, 7.0)
	for i in 600:
		_pin(pinned + (Vector3(0.0, 0.0, 0.0)))
		_watch(subject)
		await physics_frame
		if subject.stats["lunges"] >= 3:
			break
	await _frames(70)
	var lunges: int = subject.stats["lunges"]
	var lost: float = health_before - _player.health.health
	_check(lunges >= 2, "it lunges repeatedly at a standing player (%d lunges)" % lunges)
	_check(lost <= lunges * lunge_damage + 0.01, "each lunge hurts at most once (%.0f lost over %d lunges, %.0f each)" % [lost, lunges, lunge_damage])
	_check(not _seen_patrol, "it never entered a patrol state")
	var table := load(subject.loot_table_path) as LootTable
	var original_chance := table.drop_chance
	_pin(ORIGIN + Vector3(0.0, 0.1, 40.0))  # away from the body, so a pickup is not collected the moment it drops
	table.drop_chance = 1.0
	await _kill_by_hits(subject)
	table.drop_chance = original_chance
	await _frames(4)
	_check(subject.is_dead(), "it dies to real hits (receive_hit)")
	_check(not _pickups().is_empty(), "it dropped loot")
	for pickup in _pickups():
		pickup.queue_free()
	await _frames(2)


func _test_heavy_guard() -> void:
	print("-- heavy facility guard")
	var guard := await _spawn_config("security_guard", ORIGIN + Vector3(-20.0, 0.1, 0.0))
	var heavy := await _spawn_config("heavy_guard", ORIGIN + Vector3(20.0, 0.1, 0.0))
	_check(heavy.hit_points > guard.hit_points and heavy.move_speed < guard.move_speed, "the heavy guard is tougher (%.0f vs %.0f) and slower (%.1f vs %.1f)" % [heavy.hit_points, guard.hit_points, heavy.move_speed, guard.move_speed])
	_check(heavy._swing.id == &"facility_shield_bash", "the heavy guard swings the shield bash")
	_pin(ORIGIN + Vector3(20.0, 0.1, 5.0))
	var used_bash := false
	var windup_seen := false
	for i in 400:
		_pin(ORIGIN + Vector3(20.0, 0.1, 5.0))
		await physics_frame
		if heavy.state == Enemy.State.ATTACK:
			used_bash = true
			if heavy._attack_frames < heavy._swing.startup_frames and heavy._material.albedo_color.is_equal_approx(Enemy.WINDUP_COLOR):
				windup_seen = true
			if windup_seen:
				break
	_check(used_bash and windup_seen, "it attacks with a red tell during the whole telegraph")
	guard.queue_free()
	heavy.queue_free()
	await _frames(3)


func _start_elite() -> EliteExperimentalSubject:
	var elite := await _spawn_config("elite_subject", ORIGIN + Vector3(0.0, 0.1, 14.0)) as EliteExperimentalSubject
	elite._cooldown = 9999.0
	elite.state = Enemy.State.CHASE
	return elite


func _force(elite: EliteExperimentalSubject, kind: StringName, player_at: Vector3) -> Dictionary:
	_pin(player_at)
	elite.forced_attack = kind
	elite._cooldown = 0.0
	var health_before: float = _player.health.health
	var frames := 0
	while frames < 360:
		_pin(player_at)
		_watch(elite)
		await physics_frame
		frames += 1
		if elite.stats[String(kind) + "s"] >= 1 and elite.state == Enemy.State.CHASE:
			break
	elite.forced_attack = &""
	elite._cooldown = 9999.0
	await _frames(5)
	return {"lost": health_before - _player.health.health, "frames": frames}


func _test_elite_attacks() -> void:
	print("-- elite experimental subject: attacks")
	var elite := await _start_elite()
	_check(elite.is_in_group("miniboss") and elite.patrol_route == null, "it is a mini-boss with no patrol route")
	var claw := await _force(elite, &"claw", ORIGIN + Vector3(0.0, 0.1, 7.0))
	_check(elite.stats["claws"] == 1, "the leaping claw ran once")
	_check(claw["lost"] <= _data("experimental_claw").damage + 0.01, "the claw hurts at most once per use (%.0f)" % claw["lost"])
	var claw_error: float = elite.stats["last_claw_error"]
	_check(claw_error >= 0.0 and claw_error < 1.0, "it landed where the marker was (%.2f m off at impact)" % claw_error)
	var ring := await _force(elite, &"ring", elite.global_position + Vector3(0.0, 0.0, 3.0))
	_check(elite.stats["rings"] == 1, "the ground slam ring ran once")
	_check(ring["lost"] <= _data("experimental_ring").damage + 0.01, "the ring hurts at most once per use (%.0f)" % ring["lost"])
	var telegraph_red := false
	elite.forced_attack = &"claw"
	elite._cooldown = 0.0
	_pin(elite.global_position + Vector3(0.0, 0.0, 6.0))
	for i in 60:
		_pin(elite.global_position + Vector3(0.0, 0.0, 6.0))
		await physics_frame
		if elite.state == Enemy.State.ATTACK and elite._attack_frames > 3.0 and elite._attack_frames < elite._swing.startup_frames \
				and elite._material.albedo_color.is_equal_approx(Enemy.WINDUP_COLOR):
			telegraph_red = true
			break
	_check(telegraph_red, "the claw shows the red tell during its telegraph")
	elite.forced_attack = &""
	elite._cooldown = 9999.0
	await _frames(150)  # let the claw finish and the elite settle before the next telegraph
	var ring_marker_ok := false
	elite.forced_attack = &"ring"
	elite._cooldown = 0.0
	_pin(elite.global_position + Vector3(0.0, 0.0, 6.0))
	for i in 80:
		_pin(elite.global_position + Vector3(0.0, 0.0, 6.0))
		await physics_frame
		if elite.state == Enemy.State.ATTACK and elite._special == &"ring" and elite._attack_frames > 5.0 \
				and elite._attack_frames < elite._swing.startup_frames and elite._marker != null and elite._marker.visible \
				and is_equal_approx(elite._marker.scale.x, EliteExperimentalSubject.RING_RADIUS):
			ring_marker_ok = true
			break
	_check(ring_marker_ok, "the ring telegraph marks its whole danger zone on the ground")
	await _frames(120)
	_check(elite._marker == null or not elite._marker.visible, "the marker is gone once the ring is released")
	_check(not _seen_patrol, "the elite never entered a patrol state")
	elite.queue_free()
	await _frames(3)


func _test_elite_charge_wall() -> void:
	print("-- elite experimental subject: charge into a wall")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 4.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = ORIGIN + Vector3(0.0, 2.0, -6.0)
	_main.add_child(wall)
	var elite := await _start_elite()
	elite.global_position = ORIGIN + Vector3(0.0, 0.1, 6.0)
	await _frames(2)
	_pin(ORIGIN + Vector3(0.0, 0.1, -1.0))
	elite.forced_attack = &"charge"
	elite._cooldown = 0.0
	var health_before: float = _player.health.health
	var stun_seen: float = 0.0
	for i in 420:
		_pin(ORIGIN + Vector3(0.0, 0.1, -1.0))
		await physics_frame
		if elite.stats["wall_stuns"] >= 1:
			stun_seen = elite._sp_timer
			break
	_check(elite.stats["charges"] == 1 and elite.stats["wall_stuns"] == 1, "the charge ended against the wall with a stun")
	_check(stun_seen >= 1.4, "the wall stun is a long punish window (%.2f s)" % stun_seen)
	_check(elite.global_position.z >= wall.position.z + 0.4, "it did not tunnel through the wall (z %.2f, wall %.2f)" % [elite.global_position.z, wall.position.z])
	elite.forced_attack = &""
	elite._cooldown = 9999.0
	await _frames(90)
	var lost: float = health_before - _player.health.health
	_check(lost <= _data("experimental_charge").damage + 0.01, "the charge hurt at most once (%.0f)" % lost)
	wall.queue_free()
	elite.queue_free()
	await _frames(3)


func _test_elite_defeat() -> void:
	print("-- elite experimental subject: defeat and reward")
	var elite := await _start_elite()
	_pin(ORIGIN + Vector3(0.0, 0.1, 9.0))
	# Make a ring exist at the moment of death, then kill through real hits.
	elite.forced_attack = &"ring"
	elite._cooldown = 0.0
	for i in 200:
		_pin(ORIGIN + Vector3(0.0, 0.1, 9.0))
		await physics_frame
		if not elite._rings.is_empty():
			break
	_check(not elite._rings.is_empty(), "a live ring hazard exists before the kill")
	elite.forced_attack = &""
	elite._health.take_damage(elite.hit_points - 1.0)
	await _kill_by_hits(elite)
	await _frames(4)
	_check(elite.is_dead() and elite._rings.is_empty(), "defeat removes the live hazards")
	var sigils := 0
	for pickup in _pickups():
		if (pickup as Pickup).item != null and (pickup as Pickup).item.item_id == &"containment_sigil":
			sigils += 1
	_check(sigils == 1, "the unique reward dropped exactly once (%d)" % sigils)
	var sigil := load("res://resources/items/containment_sigil.tres") as ItemData
	_player.inventory.collect(sigil)
	_check(_player.inventory.is_unique_claimed("containment_sigil"), "collecting it claims the unique item")
	for pickup in _pickups():
		pickup.queue_free()
	await _frames(2)
	var second := await _start_elite()
	await _kill_by_hits(second)
	await _frames(4)
	var again := 0
	for pickup in _pickups():
		if (pickup as Pickup).item != null and (pickup as Pickup).item.item_id == &"containment_sigil":
			again += 1
	_check(second.is_dead() and again == 0, "a second elite never drops the reward again (%d)" % again)
