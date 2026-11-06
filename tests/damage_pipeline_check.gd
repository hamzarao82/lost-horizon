extends SceneTree
## Damage pipeline checks (headless): godot --headless --path . -s tests/damage_pipeline_check.gd
## Known-number cases for StatsResolver, then the real Player wiring.

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"

var _failures: int = 0
var _checks: int = 0
var _cfg: ProgressionConfig
var _tree: SkillTree
var _attrs: Array = []


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


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


func _progress_at(level: int) -> PlayerProgress:
	var p := PlayerProgress.new(_cfg)
	p.add_xp(_cfg.xp_for_level(level))
	return p


func _run() -> void:
	_cfg = load("res://resources/progression/progression_config.tres") as ProgressionConfig
	_tree = SkillTree.load_default()
	for file in DirAccess.get_files_at("res://resources/progression/attributes/"):
		if file.ends_with(".tres"):
			_attrs.append(load("res://resources/progression/attributes/" + file))
	_test_level_one()
	_test_known_numbers()
	_test_caps()
	_test_equipment()
	_test_kinds()
	await _test_player()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_level_one() -> void:
	print("level 1 equals today's numbers")
	var p := PlayerProgress.new(_cfg)
	for kind in [&"light", &"heavy", &"special"]:
		_check(StatsResolver.damage_multiplier(kind, p, _attrs, _tree) == 1.0, "%s damage x1.0 exactly" % kind)
	_check(StatsResolver.incoming_multiplier(p, _attrs, _tree) == 1.0, "incoming damage x1.0 exactly")
	_check(StatsResolver.max_health_bonus(p, _attrs, _tree) == 0.0 and StatsResolver.max_stamina_bonus(p, _attrs, _tree) == 0.0, "no health or stamina bonus")
	_check(StatsResolver.move_speed_mult(p, _attrs, _tree) == 1.0 and StatsResolver.dodge_cost_mult(p, _attrs, _tree) == 1.0, "speed and dodge cost unchanged")
	_check(StatsResolver.stamina_regen_mult(p, _attrs, _tree) == 1.0 and StatsResolver.heal_mult(p, _attrs, _tree) == 1.0, "regen and heal unchanged")


func _test_known_numbers() -> void:
	print("known numbers")
	var p := _progress_at(12)
	p.attributes = {&"strength": 5}
	_check(_near(StatsResolver.damage_multiplier(&"light", p, _attrs, _tree), 1.10), "Strength 5 = x1.10")
	p.skills = {&"sharpened_edge": 2}
	_check(_near(StatsResolver.damage_multiplier(&"light", p, _attrs, _tree), 1.18), "Strength 5 + Sharpened Edge 2 = 1 + 0.10 + 0.08 = x1.18 (additive inside, one multiplier)")
	_check(_near(StatsResolver.damage_multiplier(&"heavy", p, _attrs, _tree), 1.10), "the light skill does not leak into heavy")
	p.attributes = {&"strength": 5, &"technique": 4}
	p.skills = {&"heavy_hitter": 2}
	_check(_near(StatsResolver.damage_multiplier(&"heavy", p, _attrs, _tree), 1.0 + 0.10 + 0.06 + 0.10), "heavy = 1 + strength 0.10 + technique 0.06 + Heavy Hitter 0.10")
	p.attributes = {&"vitality": 10}
	p.skills = {&"toughness": 4}
	_check(_near(StatsResolver.max_health_bonus(p, _attrs, _tree), 50.0 + 24.0), "Vitality 10 + Toughness 4 = +74 max health")
	p.attributes = {&"endurance": 10}
	p.skills = {&"tempered_nerves": 3}
	_check(_near(StatsResolver.incoming_multiplier(p, _attrs, _tree), 1.0 - (0.05 + 0.06)), "Endurance 10 + Tempered Nerves 3 = take x0.89")
	p.attributes = {&"technique": 10}
	p.skills = {}
	_check(_near(StatsResolver.teleport_recharge_mult(p, _attrs, _tree), 0.70), "Technique 10 = teleport recharge x0.70")
	p.attributes = {&"agility": 4}
	_check(_near(StatsResolver.move_speed_mult(p, _attrs, _tree), 1.04) and _near(StatsResolver.dodge_cost_mult(p, _attrs, _tree), 0.94), "Agility 4 = +4% speed, dodge cost x0.94")
	p.attributes = {&"endurance": 10}
	p.skills = {&"deep_lungs": 3, &"focus": 2}
	_check(_near(StatsResolver.max_stamina_bonus(p, _attrs, _tree), 40.0 + 24.0) and _near(StatsResolver.stamina_regen_mult(p, _attrs, _tree), 1.2), "stamina bonus 64 and regen x1.2")
	p.skills = {&"field_medic": 3}
	_check(_near(StatsResolver.heal_mult(p, _attrs, _tree), 1.3), "Field Medic 3 = medkits heal x1.3")


func _test_caps() -> void:
	print("caps")
	var p := _progress_at(12)
	p.attributes = {&"strength": 10, &"technique": 10}
	p.skills = {&"sharpened_edge": 3, &"heavy_hitter": 3, &"whirlwind": 2}
	for kind in [&"light", &"heavy", &"special"]:
		_check(StatsResolver.damage_multiplier(kind, p, _attrs, _tree) <= _cfg.damage_mult_cap + 0.0001, "%s damage never exceeds the cap %.2f (got %.3f)" % [kind, _cfg.damage_mult_cap, StatsResolver.damage_multiplier(kind, p, _attrs, _tree)])
	p.attributes = {&"endurance": 10, &"strength": 0}
	p.skills = {&"tempered_nerves": 3}
	var gear := {"damage_reduction": 0.9}
	_check(_near(StatsResolver.incoming_multiplier(p, _attrs, _tree, gear), 1.0 - _cfg.max_damage_reduction), "damage reduction is capped at %d%%" % int(_cfg.max_damage_reduction * 100))
	p.attributes = {&"technique": 10}
	p.skills = {&"quick_recharge": 3}
	_check(_near(StatsResolver.teleport_recharge_mult(p, _attrs, _tree), _cfg.min_recharge_mult), "teleport recharge floors at x%.2f" % _cfg.min_recharge_mult)
	p.attributes = {&"agility": 10}
	p.skills = {&"fleet_foot": 3, &"light_step": 2}
	_check(StatsResolver.move_speed_mult(p, _attrs, _tree) <= 1.0 + _cfg.max_move_speed_bonus + 0.0001, "move speed bonus is capped")
	_check(StatsResolver.dodge_cost_mult(p, _attrs, _tree) >= _cfg.min_dodge_cost_mult, "dodge cost floors at x%.2f" % _cfg.min_dodge_cost_mult)


func _test_equipment() -> void:
	print("equipment stats are applied once")
	var p := _progress_at(12)
	p.attributes = {&"strength": 5}
	p.skills = {&"sharpened_edge": 2}
	var gear := {"damage_mult": 1.1, "damage_reduction": 0.1, "max_health_bonus": 20.0, "move_speed_mult": 1.05}
	_check(_near(StatsResolver.damage_multiplier(&"light", p, _attrs, _tree, gear), 1.18 * 1.1), "gear damage multiplies the progression part once: 1.18 x 1.1")
	_check(_near(StatsResolver.incoming_multiplier(p, _attrs, _tree, gear), 1.0 - (0.0 + 0.1)), "gear damage reduction 0.1 -> take x0.9")
	_check(_near(StatsResolver.max_health_bonus(p, _attrs, _tree, gear), 20.0), "gear max health +20 added once")
	_check(_near(StatsResolver.move_speed_mult(p, _attrs, _tree, gear), 1.05), "gear speed x1.05 applied once")
	var junk := StatsResolver.equipment({"damage_mult": NAN, "damage_reduction": "x", "max_health_bonus": 10 ** 9, "move_speed_mult": -3})
	_check(junk[&"damage_mult"] == 1.0 and junk[&"damage_reduction"] == 0.0, "NaN and strings fall back to neutral gear")
	_check(junk[&"max_health_bonus"] == 500.0 and junk[&"move_speed_mult"] == 0.5, "huge and negative gear values are clamped")
	_check(StatsResolver.equipment(null) == StatsResolver.DEFAULT_EQUIPMENT, "no equipment data = neutral gear")


func _test_kinds() -> void:
	print("attack kinds")
	var expected := {&"light_1": &"light", &"light_3": &"light", &"heavy_1": &"heavy", &"sprint_attack": &"heavy", &"air_attack": &"special", &"spin_special": &"special", &"unknown": &"light"}
	for id in expected:
		_check(StatsResolver.kind_of(id) == expected[id], "%s counts as %s" % [id, expected[id]])
	for file in DirAccess.get_files_at("res://resources/attacks/"):
		if file.begins_with("light_") or file.begins_with("heavy_1") or file.begins_with("sprint") or file.begins_with("air") or file.begins_with("spin"):
			var data := load("res://resources/attacks/" + file) as AttackData
			_check(data != null and StatsResolver.kind_of(data.id) in [&"light", &"heavy", &"special"], "%s maps to a kind" % file)


func _test_player() -> void:
	print("player wiring")
	var prog := root.get_node_or_null("Progression")
	_check(prog != null, "Progression autoload exists")
	if prog == null:
		return
	prog.reset()
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(player)
	await physics_frame
	await physics_frame
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	_check(player.health.max_health == 100.0 and player.walk_speed == 5.0 and player.sprint_speed == 8.5 and player.max_stamina == 100.0 and player.dodge_stamina == 20.0, "level 1 player keeps health 100, speeds 5 / 8.5, stamina 100, dodge cost 20")
	_check(player._progression_scale(light) == 1.0 and player._incoming_scale() == 1.0, "level 1 hooks scale damage by exactly 1.0")
	prog.award_xp(_cfg.xp_for_level(3), "test")
	prog.spend_attribute_point(&"vitality")
	prog.spend_attribute_point(&"strength")
	prog.unlock_skill(&"toughness")
	_check(player.health.max_health == 100.0 + 5.0 + 6.0, "Vitality 1 + Toughness 1 raise max health to 111 (got %s)" % player.health.max_health)
	_check(player.health.health == player.health.max_health, "the added health is granted, not only room")
	_check(_near(player._progression_scale(light), 1.02), "Strength 1 raises the light attack scale to 1.02")
	player.health.take_damage(30.0)
	var hp := player.health.health
	prog.award_xp(1000, "test")
	prog.spend_attribute_point(&"endurance")
	_check(player.health.health <= player.health.max_health and player.health.health >= hp, "an attribute change never exceeds max health or lowers current health")
	prog.reset()
	_check(player.health.max_health == 100.0 and player.walk_speed == 5.0 and player._progression_scale(light) == 1.0, "reset returns the player to the level 1 numbers")
	var hit := load("res://resources/attacks/enemy_swing.tres") as AttackData
	var before := player.health.health
	player.receive_hit(hit, player.global_position + Vector3.FORWARD * 2.0, 1.0)
	_check(is_equal_approx(before - player.health.health, hit.damage), "an enemy hit at level 1 takes exactly its damage (%.1f)" % hit.damage)
	player.queue_free()
	await physics_frame
	prog.reset()
