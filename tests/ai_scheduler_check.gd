extends SceneTree
## Milestone 11 AI scheduler and tactics (headless): godot --headless --path . -s tests/ai_scheduler_check.gd
## Runs in the courtyard of Main with the Outpost 17 extension removed, so only the test's enemies exist.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const WARDEN: String = "res://scenes/enemies/Warden.tscn"
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

	_test_pure_helpers()
	_test_defaults()
	await _test_behaviour_preserved()
	await _test_scheduler_throttles()
	await _test_flank()
	await _test_spacing()
	await _test_retreat()
	await _test_reinforcement()
	_cleanup()
	print("\nai_scheduler_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _cleanup() -> void:
	for node in _extras:
		if is_instance_valid(node):
			node.queue_free()
	_extras.clear()


func _reset() -> void:
	_reset_state()
	await _frames(2)


func _reset_state() -> void:
	_cleanup()
	_player.global_position = PLAYER_AT
	_player.velocity = Vector3.ZERO
	_player.health.health = _player.health.max_health
	Enemy.active_patrollers = 0
	AIScheduler.reset_budget()


func _spawn(at: Vector3, scene: String = SOLDIER, aggro: bool = true) -> Enemy:
	var enemy := (load(scene) as PackedScene).instantiate() as Enemy
	enemy.position = at
	_main.add_child(enemy)
	_extras.append(enemy)
	if aggro:
		enemy.aggro()
	return enemy


func _hit(enemy: Enemy, damage: float) -> void:
	var attack := AttackData.new()
	attack.id = &"test_hit"
	attack.damage = damage
	attack.knockback = 0.0
	attack.stagger_time = 0.05
	enemy.receive_hit(attack, enemy.global_position + Vector3(0.0, 0.0, -2.0))


# --- pure helpers ----------------------------------------------------------

func _test_pure_helpers() -> void:
	print("Pure helpers")
	_check(AIScheduler.interval_for(3.0, false) == AIScheduler.INTERVAL_NEAR, "near enemies think every 0.1 s")
	_check(AIScheduler.interval_for(9.0, false) == AIScheduler.INTERVAL_MID, "mid-range enemies think every 0.2 s")
	_check(AIScheduler.interval_for(20.0, false) == AIScheduler.INTERVAL_FAR, "far enemies think every 0.3 s")
	_check(AIScheduler.interval_for(30.0, true) == 0.0, "the attack-token holder always thinks every frame")
	_check(AIScheduler.INTERVAL_NEAR >= 0.1 and AIScheduler.INTERVAL_FAR <= 0.3, "intervals stay inside 0.1 to 0.3 s")

	AIScheduler.reset_budget()
	var granted := 0
	for i in 8:
		if AIScheduler.take_budget():
			granted += 1
	_check(granted == AIScheduler.MAX_THINKS_PER_FRAME, "a frame hands out at most %d thinks (got %d)" % [AIScheduler.MAX_THINKS_PER_FRAME, granted])
	AIScheduler.reset_budget()

	_check(AIScheduler.flank_angle(0, 1) == 0.0, "a lone flanker approaches head-on")
	_check(is_equal_approx(AIScheduler.flank_angle(0, 3), -AIScheduler.flank_angle(2, 3)), "three slots fan out symmetrically")
	_check(AIScheduler.flank_angle(1, 3) == 0.0, "the middle slot is straight on")
	_check(AIScheduler.flank_angle(0, 4) != AIScheduler.flank_angle(1, 4), "every slot has its own angle")


func _test_defaults() -> void:
	print("Defaults keep the original behaviour")
	var enemy := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	_check(not enemy.scheduled and not enemy.flank_slots and not enemy.spacing, "a plain enemy has the scheduler, flanking and spacing off")
	_check(enemy.retreat_health_fraction == 0.0 and enemy.reinforcement_cap == 0, "a plain enemy never retreats and never calls help")
	enemy.free()
	var config := EnemyConfig.new()
	_check(not config.scheduled and not config.flank_slots and not config.spacing, "a plain EnemyConfig has every tactic off")
	_check(config.retreat_health_fraction == 0.0 and config.reinforcement_cap == 0, "a plain EnemyConfig has no retreat and no reinforcement call")
	config.scheduled = true
	config.flank_slots = true
	config.spacing = true
	config.retreat_health_fraction = 0.3
	config.reinforcement_cap = 2
	var target := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	config.apply(target)
	_check(target.scheduled and target.flank_slots and target.spacing, "EnemyConfig.apply copies the tactic switches")
	_check(is_equal_approx(target.retreat_health_fraction, 0.3) and target.reinforcement_cap == 2, "EnemyConfig.apply copies retreat and reinforcement values")
	target.free()


# --- behaviour preserved -----------------------------------------------------

## Runs one soldier against the idle player for `frames`; returns {first_attack: frames, damage: hp lost}.
func _fight(scheduled: bool, frames: int) -> Dictionary:
	await _reset()
	seed(12345)
	var enemy := _spawn(PLAYER_AT + Vector3(0.0, 0.0, 9.0), SOLDIER, false)
	enemy.scheduled = scheduled
	enemy.aggro()
	var first_attack := -1
	for i in frames:
		await physics_frame
		if first_attack < 0 and enemy.state == Enemy.State.ATTACK:
			first_attack = i
	var result := {"first_attack": first_attack, "damage": _player.health.max_health - _player.health.health}
	return result


func _test_behaviour_preserved() -> void:
	print("Scheduler on vs off: same fight")
	var old_path: Dictionary = await _fight(false, 420)
	var scheduled: Dictionary = await _fight(true, 420)
	print("  off: ", old_path, "  on: ", scheduled)
	_check(old_path["first_attack"] > 0, "the unscheduled soldier reaches its first attack")
	_check(scheduled["first_attack"] > 0, "the scheduled soldier reaches its first attack")
	_check(absi(int(old_path["first_attack"]) - int(scheduled["first_attack"])) <= 30,
		"first attack starts within half a second of the old path (%d vs %d frames)" % [old_path["first_attack"], scheduled["first_attack"]])
	var swing_damage: float = (load("res://resources/attacks/enemy_swing.tres") as AttackData).damage
	_check(absf(float(old_path["damage"]) - float(scheduled["damage"])) <= swing_damage * 1.01 + 0.01,
		"damage dealt differs by at most one swing (%s vs %s)" % [old_path["damage"], scheduled["damage"]])
	_check(float(scheduled["damage"]) > 0.0, "the scheduled soldier really hurts the player")


func _test_scheduler_throttles() -> void:
	print("Scheduler throttles thinking")
	await _reset()
	var crowd: Array[Enemy] = []
	for i in 12:
		var e := _spawn(PLAYER_AT + Vector3(-11.0 + i * 2.0, 0.0, 20.0), SOLDIER, false)
		e.scheduled = true
		e.aggro()
		crowd.append(e)
	AIScheduler.reset_budget()
	var worst := 0
	for i in 60:
		await physics_frame
		worst = maxi(worst, AIScheduler._budget_used)
	var granted := AIScheduler.thinks_granted
	print("  thinks in 1 s for 12 far enemies: ", granted, " (every frame would be 720)")
	_check(granted > 0, "scheduled enemies do think")
	_check(granted <= 12 * 5, "twelve far enemies think far less than every frame (%d of 720)" % granted)
	_check(worst <= AIScheduler.MAX_THINKS_PER_FRAME, "no frame exceeds the think budget (worst %d)" % worst)


# --- tactics ----------------------------------------------------------------

func _heading(enemy: Enemy) -> float:
	return atan2(enemy.velocity.x, enemy.velocity.z)


func _spread(angles: Array) -> float:
	var widest := 0.0
	for a: float in angles:
		for b: float in angles:
			widest = maxf(widest, absf(angle_difference(a, b)))
	return widest


func _test_flank() -> void:
	print("Flank slots")
	var spreads: Array[float] = []
	for flank in [false, true]:
		await _reset()
		var group: Array[Enemy] = []
		for i in 3:
			var e := _spawn(PLAYER_AT + Vector3(-0.6 + 0.6 * i, 0.0, 10.0), SOLDIER, false)
			e.flank_slots = flank
			e.aggro()
			e._cooldown = 9.0  # nobody takes the attack token: they just approach
			group.append(e)
		await _frames(3)
		if flank:
			var slots: Array[int] = []
			for e in group:
				slots.append(AIScheduler.flank_slot(e, _player.global_position).x)
			slots.sort()
			_check(slots == [0, 1, 2], "three flankers hold three different slots")
		spreads.append(_spread([_heading(group[0]), _heading(group[1]), _heading(group[2])]))
	print("  heading spread without flanking: %.2f rad, with: %.2f rad" % [spreads[0], spreads[1]])
	_check(spreads[0] < 0.25, "without flanking the three walk almost the same line")
	_check(spreads[1] > 0.5 and spreads[1] > spreads[0] * 3.0, "with flanking they fan out onto different approach angles")


func _test_spacing() -> void:
	print("Spacing")
	await _reset()
	var a := _spawn(PLAYER_AT + Vector3(0.0, 0.0, 5.0), SOLDIER, false)
	var b := _spawn(PLAYER_AT + Vector3(0.5, 0.0, 5.0), SOLDIER, false)
	var push := AIScheduler.separation(a)
	_check(push.length() > 0.5 and push.x < 0.0, "a crowded enemy is pushed away from its neighbour")
	b.global_position = PLAYER_AT + Vector3(8.0, 0.0, 5.0)
	_check(AIScheduler.separation(a).length() < 0.001, "no push when the neighbour is far away")
	var gaps: Array[float] = []
	for spaced in [false, true]:
		await _reset()
		var p := _spawn(PLAYER_AT + Vector3(0.0, 0.0, 3.4), SOLDIER, false)
		var q := _spawn(PLAYER_AT + Vector3(0.5, 0.0, 3.4), SOLDIER, false)
		for e in [p, q]:
			e.spacing = spaced
			e.aggro()
			e._cooldown = 99.0  # waiting on the ring, no token
		await _frames(20)
		gaps.append(p.global_position.distance_to(q.global_position))
	print("  gap after 20 frames without spacing: %.2f, with: %.2f" % [gaps[0], gaps[1]])
	_check(gaps[1] > gaps[0] + 0.1, "with spacing two waiting enemies end up farther apart")


func _test_retreat() -> void:
	print("Retreat at low health")
	await _reset()
	var e := _spawn(PLAYER_AT + Vector3(0.0, 0.0, 6.0))
	e.retreat_health_fraction = 0.5
	e._cooldown = 9.0
	await _frames(2)
	var max_hp: float = e._health.max_health
	_hit(e, max_hp * 0.2)
	_check(e._retreat_left <= 0.0, "a healthy enemy (80%) does not retreat")
	_hit(e, max_hp * 0.4)
	_check(e._retreat_left > 0.0, "an enemy at 40% health starts retreating")
	await _frames(25)
	var d1 := e.global_position.distance_to(_player.global_position)
	await _frames(25)
	var d2 := e.global_position.distance_to(_player.global_position)
	_check(d2 > d1, "while retreating the enemy moves away from the player (%.2f to %.2f)" % [d1, d2])
	e._retreat_left = 0.0
	_hit(e, 1.0)
	_check(e._retreat_left <= 0.0, "it retreats only once")

	await _reset()
	var boss := _spawn(PLAYER_AT + Vector3(0.0, 0.0, 8.0), WARDEN)
	boss.retreat_health_fraction = 0.95
	boss.reinforcement_cap = 3
	await _frames(2)
	_hit(boss, boss._health.max_health * 0.2)
	_check(boss._retreat_left <= 0.0 and not boss._reinforced, "a boss ignores retreat and reinforcement settings")


func _chasing(allies: Array[Enemy]) -> int:
	var n := 0
	for ally in allies:
		if ally.state == Enemy.State.CHASE:
			n += 1
	return n


func _test_reinforcement() -> void:
	print("Reinforcements")
	var called: Array[int] = []
	for cap in [0, 2]:
		await _reset()
		var caller := _spawn(Vector3(0.0, 0.0, 6.0), SOLDIER, false)
		caller.reinforcement_cap = cap
		var allies: Array[Enemy] = []
		for i in 4:
			allies.append(_spawn(Vector3(2.0 + i, 0.0, 6.0), SOLDIER, false))
		await _frames(2)
		_hit(caller, 5.0)
		called.append(_chasing(allies))  # read straight away: a far-off ally gives up the chase a frame later
		if cap == 2:
			for ally in allies:
				ally.state = Enemy.State.IDLE
			_hit(caller, 5.0)
			_check(_chasing(allies) == 0, "the call happens once, not on every hit")
	print("  allies called with cap 0: %d, cap 2: %d" % [called[0], called[1]])
	_check(called[0] == 0, "no reinforcement cap means no call")
	_check(called[1] == 2, "a cap of two brings exactly two allies into the fight")
