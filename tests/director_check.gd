extends SceneTree
## The Director and the Fortress Captain (Milestone 9): godot --headless --path . -s tests/director_check.gd
## Fairness is asserted from the attack data files; behaviour from a real Director fighting a real Player
## (pinned, with a huge health pool, so damage is measured as health lost) on a private floor.

const ORIGIN: Vector3 = Vector3(200.0, 0.0, 200.0)
const PLAYER_HP: float = 100000.0

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player
var _pin_at: Vector3
var _defeated_signals: int = 0
var _seen_states: Dictionary = {}
var _grounded: bool = false  # only pin x/z so the player really stands on the floor (is_on_floor)


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), message)
	if not condition:
		_failures += 1




func _frames(count: int, boss: Enemy = null) -> void:
	for i in count:
		if _grounded:
			_player.global_position.x = _pin_at.x
			_player.global_position.z = _pin_at.z
			_player.velocity.x = 0.0
			_player.velocity.z = 0.0
		else:
			_player.global_position = _pin_at
			_player.velocity = Vector3.ZERO
		if boss != null and is_instance_valid(boss):
			_seen_states[boss.state] = true
		await physics_frame


func _lost() -> float:
	return PLAYER_HP - _player.health.health


func _cfg(id: String) -> EnemyConfig:
	return load("res://resources/enemies/%s.tres" % id) as EnemyConfig


func _setup(player_dist: float = 10.0) -> void:
	Projectile.reset_pool()
	if is_instance_valid(_main):
		_main.queue_free()
		for i in 3:
			await physics_frame
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	for i in 3:
		await physics_frame
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = ORIGIN + Vector3(0.0, -0.5, 0.0)
	_main.add_child(floor_body)
	_player = _main.get_node("Player") as Player
	_player.health.max_health = PLAYER_HP
	_player.health.health = PLAYER_HP
	_pin_at = ORIGIN + Vector3(0.0, 0.1, player_dist)
	await _frames(2)


func _boss(id: String = "director") -> Director:
	var boss := _cfg(id).spawn(_main, ORIGIN + Vector3(0.0, 0.1, -4.0)) as Director
	boss.forced_attack = &""
	await _frames(3)
	return boss


func _hit(boss: Enemy, damage: float) -> bool:
	var attack := AttackData.new()
	attack.damage = damage
	attack.stagger_time = 0.0
	return boss.receive_hit(attack, boss.global_position + Vector3(0.0, 0.0, 2.0))


func _run() -> void:
	_test_data()
	await _setup()
	await _test_phases()
	await _test_moves()
	await _test_defeat()
	await _test_captain()
	print("director_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _attack(id: String) -> AttackData:
	return load("res://resources/attacks/%s.tres" % id) as AttackData


func _test_data() -> void:
	var damaging := ["director_volley", "director_sweep", "director_counter", "director_dash", "director_ring", "director_barrage",
			"fortress_captain_volley", "fortress_captain_charge", "fortress_captain_slam"]
	for id in damaging:
		var a := _attack(id)
		_check(a != null and a.validate().is_empty(), "%s loads and validates" % id)
		_check(a.startup_frames >= 36, "%s telegraph is %.2f s (>= 0.6 s)" % [id, a.startup_frames / 60.0])
		_check(a.recovery_frames >= 30, "%s punish window is %.2f s (>= 0.5 s)" % [id, a.recovery_frames / 60.0])
	_check(_attack("director_dash").startup_frames >= 48, "the dash telegraph is at least 0.8 s")
	_check(_attack("fortress_captain_charge").startup_frames >= 48, "the captain's charge telegraph is at least 0.8 s")
	_check(_attack("director_ring").recovery_frames >= 48 and _attack("director_barrage").recovery_frames >= 48,
			"phase 3 attacks leave a vulnerability window of at least 0.8 s")
	_check(Director.TRANSITION_TIME >= 2.0 and Director.GRACE_AFTER_TRANSITION >= 2.0, "transition 2.0 s and grace after it 2.0 s")
	_check(Director.PHASE2_THRESHOLD == 0.6 and Director.PHASE3_THRESHOLD == 0.25, "phase thresholds are 60% and 25%")
	_check(Director.SWEEP_SHOTS <= Projectile.LIVE_CAP and Director.BARRAGE_PER_WAVE * 2 <= Projectile.LIVE_CAP,
			"no single move needs more than the projectile cap (%d)" % Projectile.LIVE_CAP)
	_check(Director.SHOT_SPACING >= 0.25, "shots in a burst are at least 0.25 s apart")
	var scene := load("res://scenes/enemies/Director.tscn") as PackedScene
	var probe := scene.instantiate() as Director
	var phase3 := probe.moves_for_phase(3)
	_check(&"ring" in phase3 and &"barrage" in phase3 and &"sweep" not in phase3, "phase 3 uses wide area attacks")
	_check(&"dash" in probe.moves_for_phase(2) and &"dash" not in probe.moves_for_phase(1), "the dash combo starts in phase 2")
	probe.free()


func _test_phases() -> void:
	var boss := await _boss()
	_check(boss.is_in_group("boss") and boss.is_boss(), "the Director is in the boss group (HUD boss bar)")
	_check(boss.phase == 1 and boss.stats["phase_changes"] == 0, "he starts in phase 1")
	boss.defeated_director.connect(func() -> void: _defeated_signals += 1)
	var max_hp := boss._health.max_health
	# Chip him just above 60%: no change.
	boss._health.health = max_hp * 0.62
	_hit(boss, 1.0)
	await _frames(2, boss)
	_check(boss.phase == 1, "above 60% he stays in phase 1")
	# Cross 60%.
	boss._health.health = max_hp * 0.61
	_hit(boss, max_hp * 0.02)
	await _frames(2, boss)
	_check(boss.phase == 2 and boss.is_transitioning(), "crossing 60% starts the phase 2 transition")
	var hp_during := boss._health.health
	_check(not _hit(boss, 50.0) and is_equal_approx(boss._health.health, hp_during), "he is invulnerable during the transition")
	await _frames(40, boss)
	_check(boss.is_transitioning() and not _hit(boss, 50.0), "still invulnerable 0.7 s in")
	await _frames(100, boss)
	_check(not boss.is_transitioning(), "the transition ends after about 2.0 s")
	_check(boss.stats["phase_changes"] == 1, "exactly one phase change so far")
	# Grace: no attack starts for 2.0 s after the transition ends.
	var attacked := false
	for i in 90:
		await _frames(1, boss)
		if boss.state == Enemy.State.ATTACK:
			attacked = true
	_check(not attacked, "no attack starts in the 2.0 s grace window after a phase change")
	_check(boss.phase == 2 and boss.stats["phase_changes"] == 1, "he stays in phase 2 and no second change fires")
	# A huge hit that skips straight past 25%: both transitions play, one after the other, once each.
	boss._health.health = max_hp * 0.10
	_hit(boss, 1.0)
	await _frames(2, boss)
	_check(boss.phase == 3 and boss.is_transitioning(), "dropping below 25% starts the phase 3 transition")
	await _frames(150, boss)
	_check(boss.phase == 3 and boss.stats["phase_changes"] == 2, "two phase changes in total (%d)" % boss.stats["phase_changes"])
	var again: int = boss.stats["phase_changes"]
	_hit(boss, 5.0)
	await _frames(5, boss)
	_check(boss.stats["phase_changes"] == again, "more damage in phase 3 never repeats a transition")
	boss.queue_free()
	await _frames(2)


func _fight(boss: Director, kind: StringName, frames: int) -> void:
	boss.forced_attack = kind
	boss._cooldown = 0.0
	await _frames(frames, boss)
	boss.forced_attack = &""


func _test_moves() -> void:
	# Volley: three aimed shots after the telegraph.
	await _setup(10.0)
	var boss := await _boss()
	boss.phase = 1
	var start := _lost()
	var first_shot_frame := -1
	var attack_start_frame := -1
	boss.forced_attack = &"volley"
	boss._cooldown = 0.0
	for f in 360:
		await _frames(1, boss)
		if attack_start_frame < 0 and boss.state == Enemy.State.ATTACK:
			attack_start_frame = f
		if first_shot_frame < 0 and boss.stats["shots"] > 0:
			first_shot_frame = f
		if boss.stats["volleys"] >= 1 and boss.stats["shots"] >= 3 and boss._kind == &"":
			break
	boss.set_physics_process(false)
	_check(boss.stats["shots"] == 3, "a volley fires exactly three shots (%d)" % boss.stats["shots"])
	_check(first_shot_frame - attack_start_frame >= _attack("director_volley").startup_frames - 3,
			"the first shot comes after the telegraph (%d frames, data %d)" % [first_shot_frame - attack_start_frame, _attack("director_volley").startup_frames])
	await _frames(90, boss)
	var damage := _lost() - start
	_check(damage <= 3.0 * _attack("director_volley").damage * boss.damage_mult + 0.01,
			"a volley hurts at most once per projectile (lost %.1f)" % damage)
	_check(Projectile.live_count() <= Projectile.LIVE_CAP, "the projectile cap holds (%d live)" % Projectile.live_count())
	boss.queue_free()
	# Sweep, barrage: shot counts and cap.
	for pair in [[&"sweep", Director.SWEEP_SHOTS], [&"barrage", Director.BARRAGE_PER_WAVE * 2]]:
		await _setup(10.0)
		var b := await _boss()
		b.forced_attack = pair[0]
		b._cooldown = 0.0
		for f in 420:
			await _frames(1, b)
			if b.stats["shots"] >= int(pair[1]) and b._kind == &"":
				break
		b.set_physics_process(false)
		_check(b.stats["shots"] == int(pair[1]), "%s fires %d shots (%d)" % [pair[0], int(pair[1]), b.stats["shots"]])
		_check(Projectile.live_count() <= Projectile.LIVE_CAP, "%s respects the projectile cap" % pair[0])
		b.queue_free()
	# Dash: one hit at most, only after the telegraph.
	await _setup(6.0)
	var d := await _boss()
	d.forced_attack = &"dash"
	d._cooldown = 0.0
	var before := _lost()
	var dash_attack_start := -1
	var first_damage := -1
	for f in 300:
		await _frames(1, d)
		if dash_attack_start < 0 and d.state == Enemy.State.ATTACK:
			dash_attack_start = f
		if first_damage < 0 and _lost() > before:
			first_damage = f
		if d.stats["dashes"] >= 1 and d._kind == &"":
			break
	d.set_physics_process(false)
	var dash_damage := _lost() - before
	_check(dash_damage > 0.0 and dash_damage <= _attack("director_dash").damage * d.damage_mult + 0.01,
			"the dash hits once for at most %.0f (lost %.1f)" % [_attack("director_dash").damage, dash_damage])
	_check(first_damage - dash_attack_start >= _attack("director_dash").startup_frames - 3,
			"the dash hit lands after its telegraph (%d frames)" % (first_damage - dash_attack_start))
	d.queue_free()
	# Ring: one hit at most for a player standing on the floor in the band.
	await _setup(1.0)
	var r := await _boss()
	r.phase = 3
	r.forced_attack = &"ring"
	r._cooldown = 0.0
	var ring_before := _lost()
	for f in 300:
		await _frames(1, r)
		if r.stats["rings"] >= 1 and r._kind == &"":
			break
	r.set_physics_process(false)
	await _frames(40, r)
	var ring_damage := _lost() - ring_before
	_check(ring_damage == 0.0,
			"a jumping (airborne) player takes no ring damage (lost %.1f)" % ring_damage)
	r.queue_free()
	# Grounded: the same ring hits a player standing on the floor exactly once.
	await _setup(1.0)
	_grounded = true
	var g := await _boss()
	g.phase = 3
	g.forced_attack = &"ring"
	g._cooldown = 0.0
	var g_before := _lost()
	for f in 300:
		await _frames(1, g)
		if g.stats["rings"] >= 1 and g._kind == &"":
			break
	g.set_physics_process(false)
	await _frames(10)
	var g_damage := _lost() - g_before
	_grounded = false
	_check(is_equal_approx(g_damage, _attack("director_ring").damage * g.damage_mult),
			"a grounded player takes exactly one ring hit (%.1f)" % g_damage)
	g.queue_free()
	await _frames(2)


func _test_defeat() -> void:
	await _setup(10.0)
	_defeated_signals = 0
	_seen_states.clear()
	var boss := await _boss()
	boss.defeated_director.connect(func() -> void: _defeated_signals += 1)
	var world := root.get_node_or_null("WorldState")
	if world != null:
		world.set_flag(Director.DEFEATED_FLAG, false)
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	var max_hp := boss._health.max_health
	for i in 3000:
		if boss.is_dead():
			break
		boss.receive_hit(heavy, boss.global_position + Vector3(0.0, 0.0, 2.0))
		await _frames(1, boss)
	_check(boss.is_dead(), "the Director dies through receive_hit (max health %.0f)" % max_hp)
	_check(boss.stats["phase_changes"] == 2, "he went through both phase changes on the way (%d)" % boss.stats["phase_changes"])
	await _frames(6)
	_check(world != null and world.has_flag(Director.DEFEATED_FLAG), "the flag iron_fortress_director_defeated is set")
	_check(String(Director.DEFEATED_FLAG).length() <= 48, "the flag id is within the 48 character save limit")
	_check(_defeated_signals == 1, "defeated_director fired exactly once (%d)" % _defeated_signals)
	_check(Projectile.live_count() == 0 and boss._rings.is_empty(), "defeat clears projectiles and rings")
	_check(not _seen_states.has(Enemy.State.PATROL) and not _seen_states.has(Enemy.State.SUSPICIOUS)
			and not _seen_states.has(Enemy.State.SEARCH) and not _seen_states.has(Enemy.State.RETURN),
			"the Director never used a patrol state")
	var signet := 0
	for node in _main.find_children("*", "Pickup", true, false):
		var item = node.get("item")
		if item != null and String(item.item_id) == "director_signet":
			signet += 1
	_check(signet == 1, "the unique signet dropped once (%d)" % signet)
	# A second Director on the same save: the flag stays and the claimed signet never drops again.
	_player.inventory.unique_claimed["director_signet"] = true
	var count_before := _main.find_children("*", "Pickup", true, false).size()
	var second := await _boss()
	second.defeated_director.connect(func() -> void: _defeated_signals += 1)
	for i in 3000:
		if second.is_dead():
			break
		second.receive_hit(heavy, second.global_position + Vector3(0.0, 0.0, 2.0))
		await _frames(1, second)
	await _frames(6)
	_check(_defeated_signals == 1, "a repeat kill on the same save emits no second defeated_director")
	var again := 0
	var after := _main.find_children("*", "Pickup", true, false)
	for i in range(count_before, after.size()):
		var item = after[i].get("item")
		if item != null and String(item.item_id) == "director_signet":
			again += 1
	_check(again == 0, "a claimed signet never drops twice")


func _test_captain() -> void:
	await _setup(10.0)
	var world0 := root.get_node_or_null("WorldState")
	if world0 != null:
		world0.set_flag(Director.DEFEATED_FLAG, false)
	var captain := await _boss("fortress_captain")
	_check(captain.profile == Director.PROFILE_CAPTAIN and captain.is_boss(), "the captain is a boss-group enemy with the captain profile")
	_check(captain.moves_for_phase(1) == [&"volley", &"dash", &"ring"], "the captain's moves are volley, charge and slam")
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 1500:
		if captain.is_dead():
			break
		captain.receive_hit(heavy, captain.global_position + Vector3(0.0, 0.0, 2.0))
		await _frames(1, captain)
	_check(captain.is_dead(), "the captain dies through receive_hit")
	_check(captain.phase == 1 and captain.stats["phase_changes"] == 0, "the captain has no phase changes")
	var world := root.get_node_or_null("WorldState")
	_check(world != null and world.has_flag(Director.CAPTAIN_FLAG) and String(Director.CAPTAIN_FLAG).length() <= 48,
			"the captain's own flag is set and short enough to save")
	_check(world != null and not world.has_flag(Director.DEFEATED_FLAG), "the captain does not set the Director's flag")
