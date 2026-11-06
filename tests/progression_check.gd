extends SceneTree
## Progression state checks (headless): godot --headless --path . -s tests/progression_check.gd
## Pure PlayerProgress/ProgressionConfig/StatsResolver rules, then the Progression autoload.

var _failures: int = 0
var _checks: int = 0
var _cfg: ProgressionConfig
var _attrs: Array = []
var _tree: SkillTree


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


func _run() -> void:
	_cfg = load("res://resources/progression/progression_config.tres") as ProgressionConfig
	_tree = SkillTree.load_default()
	for file in DirAccess.get_files_at("res://resources/progression/attributes/"):
		if file.ends_with(".tres"):
			_attrs.append(load("res://resources/progression/attributes/" + file))
	_test_config()
	_test_attributes()
	_test_xp_and_levels()
	_test_anti_grind()
	_test_serialisation()
	await _test_autoload()
	await _test_enemy_xp()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_config() -> void:
	print("config")
	_check(_cfg != null, "progression_config.tres loads")
	_check(_cfg.validate().is_empty(), "config validates: %s" % [_cfg.validate()])
	var monotone := true
	for level in range(2, _cfg.max_level() + 1):
		if _cfg.xp_for_level(level) <= _cfg.xp_for_level(level - 1):
			monotone = false
	_check(monotone, "total XP strictly increases with level")
	_check(_cfg.xp_for_level(1) == 0, "level 1 needs 0 XP")
	_check(_cfg.level_for_xp(0) == 1 and _cfg.level_for_xp(99) == 1 and _cfg.level_for_xp(100) == 2, "level boundaries 99/100 XP")
	_check(_cfg.level_for_xp(10 ** 9) == _cfg.max_level(), "huge XP stops at the max level")
	var bad := ProgressionConfig.new()
	bad.xp_to_next = PackedInt32Array([100, 50])
	_check(not bad.validate().is_empty(), "a decreasing curve is rejected")


func _test_attributes() -> void:
	print("attributes")
	var ids := []
	for def: AttributeData in _attrs:
		ids.append(String(def.id))
		_check(def.validate().is_empty(), "%s validates" % def.id)
		_check(def.base == 0, "%s starts at base 0 (level 1 equals today's numbers)" % def.id)
	ids.sort()
	_check(ids == ["agility", "endurance", "strength", "technique", "vitality"], "the five attributes exist: %s" % [ids])
	var useless := AttributeData.new()
	useless.id = &"x"
	useless.display_name = "X"
	useless.purpose = "p"
	_check(not useless.validate().is_empty(), "an attribute with no effect is rejected")


func _test_xp_and_levels() -> void:
	print("xp and levels")
	var p := PlayerProgress.new(_cfg)
	_check(p.level() == 1 and p.attribute_points == 0 and p.skill_points == 0, "new progress: level 1, no points")
	_check(p.add_xp(0) == 0 and p.add_xp(-5) == 0 and p.xp == 0, "zero or negative XP does nothing")
	_check(p.add_xp(100) == 1 and p.level() == 2, "100 XP reaches level 2")
	_check(p.attribute_points == 1 and p.skill_points == 1, "a level grants 1 attribute point and 1 skill point")
	var gained := p.add_xp(_cfg.xp_for_level(5) - p.xp)
	_check(gained == 3 and p.level() == 5, "multi-level gain reports 3 levels")
	_check(p.attribute_points == 4 and p.skill_points == 4, "points accumulate per level crossed")
	p.add_xp(10 ** 7)
	_check(p.level() == _cfg.max_level() and p.xp == _cfg.xp_for_level(_cfg.max_level()), "XP is capped at the max level")
	_check(p.xp_needed_for_next() == 0, "no XP needed past the max level")


func _test_anti_grind() -> void:
	print("anti-grind")
	var grunt1 := StatsResolver.kill_xp(_cfg, &"grunt", 1, 0)
	_check(grunt1 == 8, "a level 1 grunt kill is worth 8 XP (got %d)" % grunt1)
	_check(StatsResolver.kill_xp(_cfg, &"grunt", 5, 0) < grunt1, "over-levelled kills pay less")
	_check(StatsResolver.kill_xp(_cfg, &"grunt", 1, 100) < grunt1, "farming the same enemy pays less")
	_check(StatsResolver.kill_xp(_cfg, &"grunt", 12, 10000) >= 1, "a kill is never worth less than 1 XP")
	_check(StatsResolver.kill_xp(_cfg, &"unknown_tier", 1, 0) == 0, "an unknown tier pays nothing")
	var farm := 0
	for i in 50:
		farm += StatsResolver.kill_xp(_cfg, &"grunt", 1, i)
	_check(farm < 50 * grunt1, "50 repeat kills pay less than 50 fresh kills")
	_check(_cfg.default_quest_xp > 10 * _cfg.kill_xp[&"grunt"], "a quest is worth more than ten grunt kills")
	_check(int(_cfg.quest_xp[&"first_signal"]) > _cfg.kill_xp[&"boss"], "the main mission pays more than the boss kill alone")
	_check(_cfg.discovery_xp > _cfg.kill_xp[&"grunt"], "a discovery pays more than a grunt kill")


func _test_serialisation() -> void:
	print("serialisation")
	var p := PlayerProgress.new(_cfg)
	p.add_xp(_cfg.xp_for_level(6))
	p.attributes[&"strength"] = 2
	p.attributes[&"vitality"] = 1
	p.attribute_points -= 3
	p.skills[&"sharpened_edge"] = 2
	p.skill_points -= 2
	p.currency = 250
	p.rewarded_quests.append("first_signal")
	p.discoveries.append("doc_a_found")
	p.kill_counts["Soldier"] = 7
	var data := p.to_dict()
	var loaded := PlayerProgress.new(_cfg)
	loaded.from_dict(data, _attrs, _tree.skills.values())
	_check(loaded.to_dict() == data, "to_dict -> from_dict round trip is lossless")
	var through_json := PlayerProgress.new(_cfg)
	through_json.from_dict(JSON.parse_string(JSON.stringify(data)), _attrs, _tree.skills.values())
	_check(through_json.xp == p.xp and through_json.skill_rank(&"sharpened_edge") == 2 and int(through_json.attributes.get(&"strength", 0)) == 2, "a JSON round trip keeps XP, skills and attributes")
	_check(through_json.rewarded_quests == ["first_signal"] and through_json.currency == 250, "rewarded quests and currency survive JSON")

	var fallback := PlayerProgress.new(_cfg)
	for junk in [null, "text", 5, [1, 2], {}]:
		fallback.from_dict(junk, _attrs, _tree.skills.values())
		_check(fallback.xp == 0 and fallback.level() == 1 and fallback.currency == 0, "junk %s loads as a fresh state" % [str(junk)])
	var cheat := {"xp": 0, "attribute_points": 99, "skill_points": 99, "currency": 10 ** 12,
		"attributes": {"strength": 99, "ghost": 5}, "skills": {"whirlwind": 9, "ghost": 3}}
	fallback.from_dict(cheat, _attrs, _tree.skills.values())
	_check(fallback.attribute_points == 0 and fallback.skill_points == 0, "level 1 save cannot claim unspent points")
	_check(fallback.attributes.is_empty() and fallback.skills.is_empty(), "level 1 save cannot claim spent points or unknown ids")
	_check(fallback.currency == PlayerProgress.MAX_CURRENCY, "currency is clamped")
	var nan_data := {"xp": NAN, "currency": INF}
	fallback.from_dict(nan_data, _attrs, _tree.skills.values())
	_check(fallback.xp == 0 and fallback.currency == 0, "NaN and INF numbers fall back to 0")
	var overspent := {"xp": _cfg.xp_for_level(3), "attributes": {"strength": 10, "vitality": 10}, "skills": {}}
	fallback.from_dict(overspent, _attrs, _tree.skills.values())
	var spent := 0
	for id in fallback.attributes:
		spent += int(fallback.attributes[id])
	_check(spent <= 2, "spent attribute points never exceed what level 3 grants (spent %d)" % spent)


func _test_autoload() -> void:
	print("autoload")
	var prog := root.get_node_or_null("Progression")
	_check(prog != null, "Progression autoload exists")
	if prog == null:
		return
	prog.reset()
	_check(prog.level() == 1 and prog.currency() == 0, "reset gives a fresh level 1")
	_check(prog.damage_multiplier(&"light") == 1.0 and prog.damage_multiplier(&"heavy") == 1.0 and prog.damage_multiplier(&"special") == 1.0, "level 1 damage multipliers are exactly 1.0")
	_check(prog.incoming_multiplier() == 1.0 and prog.max_health_bonus() == 0.0 and prog.teleport_recharge_multiplier() == 1.0 and prog.dodge_cost_multiplier() == 1.0, "level 1 incoming, health, teleport and dodge multipliers are neutral")
	var levels := []
	var sources := []
	prog.level_up.connect(func(l: int) -> void: levels.append(l))
	prog.xp_gained.connect(func(a: int, s: String) -> void: sources.append([a, s]))
	prog.award_xp(100, "test")
	_check(levels == [2] and sources == [[100, "test"]], "award_xp emits xp_gained and level_up once")
	_check(prog.spend_attribute_point(&"strength") and prog.damage_multiplier(&"light") > 1.0, "spending a point raises damage")
	_check(not prog.spend_attribute_point(&"strength"), "no points left: spend fails")
	_check(not prog.spend_attribute_point(&"ghost"), "unknown attribute fails")
	_check(prog.award_quest(&"first_signal") and not prog.award_quest(&"first_signal"), "a quest pays once")
	_check(prog.award_discovery("doc_x_found") and not prog.award_discovery("doc_x_found"), "a discovery pays once")
	var xp_before: int = prog.progress.xp
	prog.award_discovery("")
	_check(prog.progress.xp == xp_before, "an empty discovery id pays nothing")
	var saved: Dictionary = prog.to_dict()
	prog.reset()
	prog.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(not prog.award_quest(&"first_signal"), "a reloaded save does not pay the quest again")
	_check(prog.award_discovery("doc_x_found") == false, "a reloaded save does not pay the discovery again")

	prog.reset()
	_check(prog.add_currency(100) == 100 and prog.currency() == 100, "currency adds at level 1")
	_check(not prog.spend_currency(101) and prog.currency() == 100, "overspending fails and changes nothing")
	_check(prog.spend_currency(40) and prog.currency() == 60, "spending reduces currency")
	_check(not prog.spend_currency(-5), "a negative spend is rejected")
	_check(prog.add_currency(-5) == 0 and prog.currency() == 60, "a negative gain is ignored")
	prog.award_xp(_cfg.xp_for_level(4), "test")
	prog.unlock_skill(&"focus")
	_check(prog.unlock_skill(&"scavenger") and prog.currency_multiplier() > 1.0, "Scavenger raises earned currency")
	var before: int = prog.currency()
	var earned: int = prog.add_currency(100)
	_check(earned == 110 and prog.currency() == before + 110, "Scavenger rank 1 adds 10 percent (got %d)" % earned)
	_check(prog.add_currency(100, false) == 100, "bonus = false skips the multiplier")
	prog.reset()


## Real enemies: defeating them must award XP through Enemy.defeated, once each, with tier XP.
func _test_enemy_xp() -> void:
	print("enemy XP wiring")
	var prog := root.get_node_or_null("Progression")
	if prog == null:
		return
	prog.reset()
	var specs := {"res://scenes/enemies/PatrolSoldier.tscn": 8, "res://scenes/enemies/HunterElite.tscn": 14, "res://scenes/enemies/HeavySoldier.tscn": 20}
	for path in specs:
		var enemy := (load(path) as PackedScene).instantiate() as Enemy
		enemy.position = Vector3(500, 0, 500)
		root.add_child(enemy)
		await physics_frame
		var before: int = prog.progress.xp
		enemy._health.take_damage(100000.0)
		await physics_frame
		await physics_frame
		var got: int = prog.progress.xp - before
		_check(got == int(specs[path]), "%s kill awards its tier XP (%d, got %d)" % [path.get_file(), int(specs[path]), got])
		enemy.queue_free()
	var warden := (load("res://scenes/enemies/Warden.tscn") as PackedScene).instantiate() as Enemy
	warden.position = Vector3(500, 0, 520)
	root.add_child(warden)
	await physics_frame
	_check(StatsResolver.tier_of(warden) == &"boss", "the Warden is the boss tier")
	warden.queue_free()
	await physics_frame
	prog.reset()
