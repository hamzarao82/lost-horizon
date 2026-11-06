extends SceneTree
## Skill tree checks (headless): godot --headless --path . -s tests/skills_check.gd

var _failures: int = 0
var _checks: int = 0
var _cfg: ProgressionConfig
var _tree: SkillTree
var _attrs: Array = []


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


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
	_test_data()
	_test_rules()
	_test_states()
	_test_effects()
	_test_validation()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("data")
	_check(_tree.skills.size() == 14, "14 skills load (got %d)" % _tree.skills.size())
	_check(_tree.validate().is_empty(), "the shipped tree validates: %s" % [_tree.validate()])
	var categories := {}
	for skill: SkillData in _tree.all():
		categories[skill.category] = true
	_check(categories.size() == 4, "all four categories are used")
	var roots := 0
	for skill: SkillData in _tree.all():
		if skill.prerequisites.is_empty():
			roots += 1
	_check(roots >= 4, "every category can be entered without prerequisites (roots: %d)" % roots)
	_check(_tree.all().size() == 14, "all() returns every skill, sorted")


func _test_rules() -> void:
	print("rules")
	var p := _progress_at(1)
	_check(_tree.block_reason(p, &"sharpened_edge") == "Requires level 2", "level gate reason: '%s'" % _tree.block_reason(p, &"sharpened_edge"))
	_check(not _tree.buy(p, &"sharpened_edge") and p.skills.is_empty(), "a blocked buy changes nothing")
	p = _progress_at(2)
	_check(_tree.can_buy(p, &"sharpened_edge"), "level 2 with 1 point can buy a root skill")
	_check(_tree.block_reason(p, &"heavy_hitter") == "Requires level 3", "the level gate is reported before the prerequisite: '%s'" % _tree.block_reason(p, &"heavy_hitter"))
	var p3 := _progress_at(3)
	_check(_tree.block_reason(p3, &"heavy_hitter") == "Requires Sharpened Edge", "prerequisite reason: '%s'" % _tree.block_reason(p3, &"heavy_hitter"))
	_check(_tree.buy(p, &"sharpened_edge") and p.skill_rank(&"sharpened_edge") == 1 and p.skill_points == 0, "buying spends the point and raises the rank")
	_check(_tree.block_reason(p, &"sharpened_edge").begins_with("Needs 1 skill point"), "out of points reason: '%s'" % _tree.block_reason(p, &"sharpened_edge"))
	p = _progress_at(6)
	_check(_tree.buy(p, &"sharpened_edge") and _tree.buy(p, &"sharpened_edge") and _tree.buy(p, &"sharpened_edge"), "three ranks can be bought with enough points")
	_check(_tree.block_reason(p, &"sharpened_edge") == "Already at maximum rank" and not _tree.buy(p, &"sharpened_edge"), "max rank cannot be exceeded")
	_check(p.skill_points == 2, "3 ranks cost 3 of 5 points")
	_check(_tree.buy(p, &"heavy_hitter") and not _tree.can_buy(p, &"whirlwind"), "a prerequisite unlocks the next skill but level 4 is still required")
	p = _progress_at(8)
	_tree.buy(p, &"sharpened_edge")
	_tree.buy(p, &"heavy_hitter")
	var before := p.skill_points
	_check(_tree.buy(p, &"whirlwind") and before - p.skill_points == 2, "Whirlwind costs 2 points")
	_check(not _tree.buy(p, &"ghost"), "an unknown skill cannot be bought")


func _test_states() -> void:
	print("states")
	var p := _progress_at(1)
	var S := SkillTree.State
	_check(_tree.state(p, &"sharpened_edge") == S.LOCKED, "level gate shows LOCKED")
	p = _progress_at(4)
	_check(_tree.state(p, &"sharpened_edge") == S.AVAILABLE, "an enterable skill shows AVAILABLE")
	_check(_tree.state(p, &"heavy_hitter") == S.LOCKED, "a missing prerequisite shows LOCKED")
	_tree.buy(p, &"sharpened_edge")
	_check(_tree.state(p, &"sharpened_edge") == S.OWNED, "rank 1 of 3 shows OWNED")
	_check(_tree.state(p, &"heavy_hitter") == S.AVAILABLE, "the prerequisite being owned makes the next AVAILABLE")
	_tree.buy(p, &"sharpened_edge")
	_tree.buy(p, &"sharpened_edge")
	_check(_tree.state(p, &"sharpened_edge") == S.MAXED, "max rank shows MAXED")


func _test_effects() -> void:
	print("effects")
	var p := _progress_at(6)
	_tree.buy(p, &"sharpened_edge")
	_tree.buy(p, &"sharpened_edge")
	_check(is_equal_approx(StatsResolver.damage_multiplier(&"light", p, _attrs, _tree), 1.08), "Sharpened Edge rank 2 = +8% light damage")
	_check(StatsResolver.damage_multiplier(&"heavy", p, _attrs, _tree) == 1.0, "light skills do not touch heavy damage")
	_tree.buy(p, &"toughness")
	_check(StatsResolver.max_health_bonus(p, _attrs, _tree) == 6.0, "Toughness rank 1 = +6 max health")
	var q := _progress_at(8)
	_tree.buy(q, &"fleet_foot")
	_tree.buy(q, &"quick_recharge")
	_check(is_equal_approx(StatsResolver.move_speed_mult(q, _attrs, _tree), 1.02), "Fleet Foot rank 1 = +2% speed")
	_check(is_equal_approx(StatsResolver.teleport_recharge_mult(q, _attrs, _tree), 0.92), "Quick Recharge rank 1 = teleport recharge x0.92")
	_check(StatsResolver.teleport_recharge_mult(PlayerProgress.new(_cfg), _attrs, _tree) == 1.0, "no skills = teleport recharge x1.0 (existing mechanic untouched)")


func _test_validation() -> void:
	print("validation")
	var tree := SkillTree.new()
	var a := SkillData.new()
	a.id = &"a"
	a.display_name = "A"
	a.description = "d"
	a.effects = {&"max_health": 1.0}
	a.prerequisites = PackedStringArray(["b"])
	var b := SkillData.new()
	b.id = &"b"
	b.display_name = "B"
	b.description = "d"
	b.effects = {&"max_health": 1.0}
	b.prerequisites = PackedStringArray(["a"])
	tree.skills = {&"a": a, &"b": b}
	_check(not tree.validate().is_empty(), "a prerequisite cycle is reported")
	b.prerequisites = PackedStringArray(["missing"])
	_check(not tree.validate().is_empty(), "a missing prerequisite is reported")
	b.prerequisites = PackedStringArray()
	a.prerequisites = PackedStringArray()
	b.effects = {&"not_an_effect": 1.0}
	_check(not tree.validate().is_empty(), "an unknown effect key is reported")
