extends SceneTree
## Combo Extension, Counterattack, enemy scaling and temporary buffs through the real Player,
## Enemy and Inventory: godot --headless --path . -s tests/skills_combat_check.gd

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const SOLDIER_SCENE: String = "res://scenes/enemies/PatrolSoldier.tscn"
const WARDEN_SCENE: String = "res://scenes/enemies/Warden.tscn"

var _failures: int = 0
var _checks: int = 0
var _prog: Node
var _counter_events: Array[float] = []


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


func _spawn_player() -> Player:
	var player := load(PLAYER_SCENE).instantiate() as Player
	root.add_child(player)
	await _frames(4)
	player.health.max_health = 100000.0
	player.health.health = 100000.0
	player.stamina = 100.0
	return player


func _set_rank(id: StringName, rank: int) -> void:
	if rank <= 0:
		_prog.progress.skills.erase(id)
	else:
		_prog.progress.skills[id] = rank


func _run() -> void:
	_prog = root.get_node_or_null("Progression")
	_check(_prog != null, "Progression autoload exists")
	_prog.reset()
	await _test_data()
	await _test_combo()
	await _test_counter()
	await _test_scaling()
	await _test_buffs()
	await _test_enemy_damage()
	_prog.reset()
	print("skills_combat_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("Skill data")
	var tree := SkillTree.load_default()
	for id in [&"combo_extension", &"counterattack"]:
		_check(tree.get_skill(id) != null, "%s loads" % id)
	var combo := tree.get_skill(&"combo_extension")
	var counter := tree.get_skill(&"counterattack")
	_check(combo != null and combo.validate().is_empty(), "combo_extension validates")
	_check(counter != null and counter.validate().is_empty(), "counterattack validates")
	_check(combo != null and combo.prerequisites.has("sharpened_edge"), "combo extension needs Sharpened Edge")
	_check(counter != null and counter.prerequisites.has("light_step"), "counterattack needs Light Step")


func _test_combo() -> void:
	print("Combo Extension")
	var player := await _spawn_player()
	_check(player.call("_progression_scale", load("res://resources/attacks/light_1.tres")) == 1.0, "no skills: attack scale is exactly 1.0")
	# Rank 0: the light chain ends after the third hit, exactly as before.
	player.set("_attack_idx", Player.IDX_LIGHT_1)
	_check(player.call("_next_attack", false) == Player.IDX_LIGHT_2, "rank 0: light 1 -> light 2")
	player.set("_attack_idx", Player.IDX_LIGHT_2)
	_check(player.call("_next_attack", false) == Player.IDX_LIGHT_3, "rank 0: light 2 -> light 3")
	player.set("_attack_idx", Player.IDX_LIGHT_3)
	_check(player.call("_next_attack", false) == -1, "rank 0: the chain ends after light 3")
	player.set("_attack_idx", -1)

	for rank in [1, 2, 3]:
		_set_rank(&"combo_extension", rank)
		player.stamina = 100.0
		player.set("_attack_idx", -1)
		_check(player.call("_start_attack", Player.IDX_LIGHT_1), "rank %d: a fresh combo starts" % rank)
		var steps := 1
		var guard := 0
		while guard < 12:
			guard += 1
			player.stamina = 100.0
			var next: int = player.call("_next_attack", false)
			if next < 0:
				break
			player.call("_start_attack", next)
			steps += 1
		_check(steps == 3 + rank, "rank %d: the combo is %d hits (got %d)" % [rank, 3 + rank, steps])
		_check(int(player.get("_combo_extra_used")) == rank, "rank %d: %d extension hits used" % [rank, rank])

	# A new combo starts over: nothing carries from the last one.
	player.call("_end_attack")
	player.stamina = 100.0
	player.call("_start_attack", Player.IDX_LIGHT_1)
	_check(int(player.get("_combo_extra_used")) == 0, "a fresh combo resets the extension counter")
	# Heavy finishers are unchanged.
	player.set("_attack_idx", Player.IDX_LIGHT_3)
	_check(player.call("_next_attack", true) == Player.HEAVY_INDEX, "heavy still finishes from light 3")
	# Frame data of the three authored lights is untouched (rank only changes how far the chain goes).
	var l1 := load("res://resources/attacks/light_1.tres") as AttackData
	_check(l1.startup_frames >= 1 and l1.active_frames >= 1, "attack data still has startup and active frames")
	_set_rank(&"combo_extension", 0)
	player.queue_free()
	await _frames(2)


func _test_counter() -> void:
	print("Counterattack")
	var swing := load("res://resources/attacks/enemy_swing.tres") as AttackData
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData

	# Rank 0: a dodged hit arms nothing.
	var player := await _spawn_player()
	_counter_events.clear()
	player.counter_triggered.connect(func(bonus: float) -> void: _counter_events.append(bonus))
	_check(player.call("_try_dodge"), "the player dodges")
	var took: bool = player.receive_hit(swing, player.global_position + Vector3(0, 0, 2))
	_check(not took, "i-frames still avoid the hit")
	_check(is_zero_approx(float(player.get("_counter_left"))), "rank 0: nothing is armed")

	for rank in [1, 2, 3]:
		_set_rank(&"counterattack", rank)
		var p := await _spawn_player()
		var events: Array[float] = []
		p.counter_triggered.connect(func(bonus: float) -> void: events.append(bonus))
		p.set("_counter_left", 0.0)
		p.set("_counter_cd", 0.0)
		p.call("_try_dodge")
		_check(not p.receive_hit(swing, p.global_position + Vector3(0, 0, 2)), "rank %d: the dodge avoids the hit" % rank)
		_check(is_equal_approx(float(p.get("_counter_left")), Player.COUNTER_WINDOW), "rank %d: the counter arms for %.1f s" % [rank, Player.COUNTER_WINDOW])
		# A second avoided hit in the same dodge never re-arms or extends it.
		p.set("_counter_left", 0.3)
		p.receive_hit(swing, p.global_position + Vector3(0, 0, 2))
		_check(is_equal_approx(float(p.get("_counter_left")), 0.3), "rank %d: cooldown stops a second arming" % rank)
		p.set("_counter_left", Player.COUNTER_WINDOW)
		# A heavy attack neither gets the bonus nor uses it up.
		p.state = Player.State.FREE
		p.set("_attack_idx", -1)
		p.stamina = 100.0
		p.call("_start_attack", Player.HEAVY_INDEX)
		_check(is_equal_approx(float(p.get("_counter_scale")), 1.0), "rank %d: a heavy attack gets no bonus" % rank)
		_check(is_equal_approx(float(p.get("_counter_left")), Player.COUNTER_WINDOW), "rank %d: and does not use the window up" % rank)
		p.call("_end_attack")
		p.stamina = 100.0
		p.call("_start_attack", Player.IDX_LIGHT_1)
		var expected: float = 1.0 + Player.COUNTER_BONUS_BY_RANK[rank]
		_check(is_equal_approx(float(p.get("_counter_scale")), expected), "rank %d: the light swing carries x%.2f" % [rank, expected])
		_check(events.size() == 1 and is_equal_approx(events[0], Player.COUNTER_BONUS_BY_RANK[rank]), "rank %d: counter_triggered fired once with the bonus" % rank)
		var base_scale: float = _prog.attack_multiplier(light)
		_check(is_equal_approx(float(p.call("_progression_scale", light)), base_scale * expected), "rank %d: the swing's damage scale includes it exactly once" % rank)
		_check(is_equal_approx(float(p.call("_progression_scale", heavy)), _prog.attack_multiplier(heavy)), "rank %d: other attack kinds are untouched" % rank)
		# The very next combo step is back to normal.
		p.stamina = 100.0
		p.call("_start_attack", Player.IDX_LIGHT_2)
		_check(is_equal_approx(float(p.get("_counter_scale")), 1.0), "rank %d: the next hit of the combo has no bonus" % rank)
		_check(is_zero_approx(float(p.get("_counter_left"))), "rank %d: the window is spent" % rank)
		p.queue_free()
		await _frames(2)

	# Spam: dodging with nothing to dodge never arms, and an avoided hit after the i-frames does not either.
	_set_rank(&"counterattack", 3)
	var s := await _spawn_player()
	for i in 6:
		s.state = Player.State.FREE
		s.stamina = 100.0
		s.call("_try_dodge")
		await _frames(1)
	_check(is_zero_approx(float(s.get("_counter_left"))), "dodge spam with no incoming hit never arms the counter")
	s.state = Player.State.FREE
	s.stamina = 100.0
	s.call("_try_dodge")
	s.set("_dodge_time", s.dodge_iframes + 0.05)
	s.set("_invuln_time", 0.5)  # invulnerable for another reason
	s.receive_hit(swing, s.global_position + Vector3(0, 0, 2))
	_check(is_zero_approx(float(s.get("_counter_left"))), "a hit avoided outside the dodge i-frames does not arm it")
	# The window expires on its own.
	s.set("_counter_left", 0.05)
	await _frames(8)
	_check(is_zero_approx(float(s.get("_counter_left"))), "the armed window runs out")
	s.set("_counter_cd", 0.0)
	s.state = Player.State.FREE
	s.set("_attack_idx", -1)
	s.stamina = 100.0
	s.call("_start_attack", Player.IDX_LIGHT_1)
	_check(is_equal_approx(float(s.get("_counter_scale")), 1.0), "an expired window gives no bonus")
	_set_rank(&"counterattack", 0)
	s.queue_free()
	player.queue_free()
	await _frames(2)


func _test_scaling() -> void:
	print("Enemy scaling")
	var cfg := ScalingConfig.new()
	_check(is_equal_approx(cfg.health_mult(1, false), 1.0) and is_equal_approx(cfg.damage_mult(1, false), 1.0), "level 1 is exactly the authored numbers")
	_check(is_equal_approx(cfg.health_mult(6, false), 1.2), "level 6: +20%% health (%.3f)" % cfg.health_mult(6, false))
	_check(is_equal_approx(cfg.damage_mult(6, false), 1.1), "level 6: +10%% damage (%.3f)" % cfg.damage_mult(6, false))
	_check(is_equal_approx(cfg.health_mult(100, false), cfg.max_health_mult) and is_equal_approx(cfg.damage_mult(100, false), cfg.max_damage_mult), "both curves are capped")
	_check(cfg.health_mult(6, true) < cfg.health_mult(6, false), "the boss curve is gentler than the regular one")
	_check(is_equal_approx(cfg.damage_mult(12, true), 1.0), "the boss does not scale its damage")
	_check(cfg.health_mult(12, true) <= cfg.boss_max_health_mult, "the boss curve is capped")
	_check(is_equal_approx(cfg.health_mult(0, false), 1.0), "a nonsense level never lowers health")

	var soldier := load(SOLDIER_SCENE).instantiate() as Enemy
	var base_hp := soldier.hit_points
	_check(EnemyScaling.apply(soldier, 1, cfg) == false, "apply at level 1 changes nothing")
	_check(is_equal_approx(soldier.hit_points, base_hp) and is_equal_approx(soldier.damage_mult, 1.0), "level 1: health and damage unchanged")
	_check(EnemyScaling.apply(soldier, 6, cfg) == false, "apply is once per instance (already marked)")
	soldier.free()

	var s2 := load(SOLDIER_SCENE).instantiate() as Enemy
	var hp2 := s2.hit_points
	_check(EnemyScaling.apply(s2, 6, cfg), "level 6 scales a fresh soldier")
	_check(is_equal_approx(s2.hit_points, hp2 * 1.2) and is_equal_approx(s2.damage_mult, 1.1), "health x1.2 and damage x1.1")
	EnemyScaling.apply(s2, 6, cfg)
	_check(is_equal_approx(s2.hit_points, hp2 * 1.2), "a second apply does not stack")
	s2.free()

	var warden := load(WARDEN_SCENE).instantiate() as Enemy
	var wh := warden.hit_points
	EnemyScaling.apply(warden, 6, cfg)
	_check(is_equal_approx(warden.hit_points, wh * cfg.health_mult(6, true)) and is_equal_approx(warden.damage_mult, 1.0), "the Warden uses the boss curve")
	warden.free()

	# Real wiring: Enemy._ready reads the level of the Progression autoload.
	_prog.reset()
	var level_one := load(SOLDIER_SCENE).instantiate() as Enemy
	root.add_child(level_one)
	await _frames(2)
	_check(is_equal_approx(level_one.hit_points, hp2) and is_equal_approx(level_one.damage_mult, 1.0), "an enemy spawned at level 1 keeps authored numbers")
	_check(is_equal_approx(level_one.get_node("HealthComponent").max_health, hp2), "and its health component matches")
	level_one.queue_free()
	_prog.progress.xp = 99999
	var lvl: int = _prog.level()
	_check(lvl > 1, "the test player is above level 1 (%d)" % lvl)
	var scaled := load(SOLDIER_SCENE).instantiate() as Enemy
	root.add_child(scaled)
	await _frames(2)
	var expect_hp := hp2 * EnemyScaling.config().health_mult(lvl, false)
	_check(is_equal_approx(scaled.hit_points, expect_hp), "an enemy spawned at level %d is scaled by the config (%.1f)" % [lvl, scaled.hit_points])
	_check(is_equal_approx(scaled.get_node("HealthComponent").max_health, expect_hp), "its health component carries the scaled health")
	_check(is_equal_approx(scaled.get_node("HealthComponent").health, expect_hp), "and it starts at full scaled health")
	scaled.queue_free()
	_prog.reset()
	await _frames(2)


func _test_buffs() -> void:
	print("Temporary buffs")
	var player := await _spawn_player()
	var inv = player.inventory
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	var oil := load("res://resources/items/sharpening_oil.tres") as ItemData
	var before: float = inv.damage_multiplier()
	var scale_before: float = before * float(player.call("_progression_scale", light))
	inv.collect(oil)
	var res: Dictionary = inv.use_item("sharpening_oil", player.health)
	_check(bool(res.get("ok", false)), "sharpening oil can be used (%s)" % str(res.get("reason", "")))
	var buffed: float = inv.damage_multiplier()
	_check(is_equal_approx(buffed, before * (1.0 + oil.effect_amount)), "the buff raises the damage multiplier by %.0f%%" % (oil.effect_amount * 100.0))
	var scale_after: float = buffed * float(player.call("_progression_scale", light))
	_check(is_equal_approx(scale_after, scale_before * (1.0 + oil.effect_amount)), "the full swing scale includes the buff exactly once")
	# Re-using refreshes instead of stacking.
	inv.collect(oil)
	inv.use_item("sharpening_oil", player.health)
	_check(is_equal_approx(inv.damage_multiplier(), buffed), "using it again refreshes, never stacks")
	_check(inv.active_buffs().size() == 1, "one active buff")
	inv.tick(oil.buff_seconds + 1.0)
	_check(is_equal_approx(inv.damage_multiplier(), before), "the buff expires")
	_check(inv.active_buffs().is_empty(), "no buffs remain")
	player.queue_free()
	await _frames(2)


## An enemy with a raised damage_mult really hits the player harder than an unscaled one.
func _damage_taken_from(mult: float) -> float:
	var player := await _spawn_player()
	player.global_position = Vector3(0.0, 0.1, 0.0)
	var soldier := load(SOLDIER_SCENE).instantiate() as Enemy
	soldier.position = Vector3(0.0, 0.1, 1.4)
	root.add_child(soldier)
	await _frames(2)
	soldier.damage_mult = mult
	soldier.set("_target", player)
	var start: float = player.health.health
	var guard := 0
	while player.health.health >= start and guard < 480:
		await physics_frame
		guard += 1
	var dealt: float = start - player.health.health
	soldier.queue_free()
	player.queue_free()
	await _frames(3)
	return dealt


func _test_enemy_damage() -> void:
	print("Enemy damage scale in a real fight")
	var normal: float = await _damage_taken_from(1.0)
	var boosted: float = await _damage_taken_from(1.5)
	_check(normal > 0.0 and boosted > 0.0, "the soldier lands a hit in both runs (%.1f and %.1f)" % [normal, boosted])
	_check(normal > 0.0 and is_equal_approx(boosted / normal, 1.5), "damage_mult 1.5 deals 1.5x the damage (%.2fx)" % (boosted / maxf(normal, 0.001)))
