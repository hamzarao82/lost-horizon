extends SceneTree
## Balance simulation (Milestone 11): formula numbers from the real enemy, boss, weapon and scaling
## resources. NOT a playtest: it measures time to kill and damage per hit, not fun.
##   godot --headless --path . -s tests/balance_sim_check.gd

const DOC: String = "res://docs/COMBAT_BALANCE.md"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures += 1


func _item(id: String) -> ItemData:
	return load("res://resources/items/%s.tres" % id) as ItemData


func _run() -> void:
	var reports: Dictionary = {}
	for id in BalanceTable.region_ids():
		reports[id] = BalanceTable.region_report(id)
	_test_table(reports)
	_test_player_side()
	_test_difficulty_curve(reports)
	_test_doc(reports)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_table(reports: Dictionary) -> void:
	print("Table")
	_check(reports.size() == 5, "five regions: Outpost 17, Dead Coast, Blackwood, Research Complex, Iron Fortress")
	var all_valid := true
	var survivable := true
	var blade := _item("improvised_blade")
	var regular_ttk_ok := true
	var boss_ttk_ok := true
	for id: StringName in reports:
		var r: Dictionary = reports[id]
		var expected_bosses := 1 if id == &"outpost_17" else 2
		_check((r["bosses"] as Array).size() == expected_bosses and not (r["regulars"] as Array).is_empty(),
				"%s: %d wave enemies, %d boss(es)" % [r["name"], (r["regulars"] as Array).size(), (r["bosses"] as Array).size()])
		for e: Dictionary in (r["regulars"] as Array) + (r["bosses"] as Array):
			all_valid = all_valid and not e.is_empty() and e["ehp"] > 0.0 and e["hit"] > 0.0 and e["dps"] > 0.0 and e["detection"] > 0.0
			survivable = survivable and BalanceTable.hits_to_die(e["hit"]) >= 4
		for e: Dictionary in r["regulars"]:
			var ttk := BalanceTable.time_to_kill(blade, e["ehp"])
			regular_ttk_ok = regular_ttk_ok and ttk >= 0.5 and ttk <= 20.0
		for e: Dictionary in r["bosses"]:
			var ttk := BalanceTable.time_to_kill(blade, e["ehp"])
			boss_ttk_ok = boss_ttk_ok and ttk >= 5.0 and ttk <= 60.0
	_check(all_valid, "every enemy has positive health, hit damage, damage per second and detection range")
	_check(survivable, "no single hit takes more than a quarter of the player's 100 health (at least 4 hits to die)")
	_check(regular_ttk_ok, "the starting blade kills any ordinary wave enemy in 0.5-20 s of clean chaining")
	_check(boss_ttk_ok, "the starting blade needs 5-60 s of clean hits for any boss (never trivial, never a wall)")
	var dc_soldier: Dictionary = (reports[&"dead_coast"]["regulars"] as Array)[0]
	_check(is_equal_approx(dc_soldier["ehp"], 60.0 * EnemyScaling.config().health_mult(3, false)),
			"Dead Coast soldiers use the real level scaling (%.1f = 60 x level-3 multiplier)" % dc_soldier["ehp"])
	var warden: Dictionary = (reports[&"outpost_17"]["bosses"] as Array)[0]
	_check(warden["is_warden"] and is_equal_approx(warden["ehp"], 420.0), "the Warden is a boss for scaling and keeps 420 health at level 1")


func _test_player_side() -> void:
	print("Weapons")
	var blade := _item("improvised_blade")
	var chain := BalanceTable.light_chain(blade)
	var manual := 0.0
	for id in BalanceTable.LIGHT_CHAIN:
		manual += (load("res://resources/attacks/%s.tres" % id) as AttackData).damage
	_check(is_equal_approx(chain["damage"], manual * blade.damage_multiplier), "the starting blade's chain damage is the three light attacks x its multiplier (%.1f)" % chain["damage"])
	var stick := BalanceTable.light_chain(_item("wooden_stick"))
	_check(is_equal_approx(stick["dps"], chain["dps"]), "the wooden stick is exactly as strong as the starting blade")
	var blade_dps: float = chain["dps"]
	var better := true
	for id in ["combat_knife", "iron_sword", "military_machete", "katana", "tactical_sword", "claymore", "warden_blade"]:
		better = better and BalanceTable.light_chain(_item(id))["dps"] > blade_dps
	_check(better, "every found weapon out-damages the starting blade over time")
	_check(BalanceTable.light_chain(_item("iron_sword"))["dps"] < BalanceTable.light_chain(_item("katana"))["dps"]
			and BalanceTable.light_chain(_item("iron_sword"))["dps"] < BalanceTable.light_chain(_item("tactical_sword"))["dps"],
			"the common Iron Sword stays below the rarer Katana and Tactical Sword")
	var top_damage := ""
	var top_value := 0.0
	for id in BalanceTable.WEAPON_IDS:
		var d: float = BalanceTable.light_chain(_item(id))["damage"]
		if d > top_value:
			top_value = d
			top_damage = id
	_check(top_damage == "warden_blade", "the Warden's Cleaver deals the most damage per chain (%.1f)" % top_value)
	var clay := BalanceTable.light_chain(_item("claymore"))
	_check(clay["seconds"] > chain["seconds"] and clay["damage"] > chain["damage"] * 1.8,
			"the claymore trades speed for damage: %.2f s per chain vs %.2f s, %.0f vs %.0f damage" % [clay["seconds"], chain["seconds"], clay["damage"], chain["damage"]])
	var knife := BalanceTable.light_chain(_item("combat_knife"))
	_check(knife["seconds"] < chain["seconds"], "the knife's chain is the quickest of the plain weapons (%.2f s)" % knife["seconds"])
	var better_ttk := true
	for id in ["katana", "tactical_sword", "warden_blade"]:
		better_ttk = better_ttk and BalanceTable.time_to_kill(_item(id), 792.0) < BalanceTable.time_to_kill(blade, 792.0)
	_check(better_ttk, "Katana, Tactical Sword and the Cleaver all kill the Director faster than the starting blade")


func _test_difficulty_curve(reports: Dictionary) -> void:
	print("Difficulty by data")
	var order: Array[StringName] = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
	var rising := true
	for i in range(1, order.size()):
		rising = rising and reports[order[i]]["threat"] > reports[order[i - 1]]["threat"]
	_check(rising, "threat (total health x total damage per second) rises with every region")
	var fortress: Dictionary = reports[&"iron_fortress"]
	for key in ["wave_ehp", "wave_dps", "boss_ehp", "threat"]:
		var hardest := true
		for id: StringName in reports:
			if id != &"iron_fortress" and reports[id][key] >= fortress[key]:
				hardest = false
		_check(hardest, "Iron Fortress is highest in %s (%.1f)" % [key, fortress[key]])
	var fortress_regular := 0.0
	for e: Dictionary in reports[&"iron_fortress"]["regulars"]:
		fortress_regular = maxf(fortress_regular, e["ehp"])
	var coast_regular := 0.0
	for e: Dictionary in reports[&"dead_coast"]["regulars"]:
		coast_regular = maxf(coast_regular, e["ehp"])
	_check(fortress_regular > coast_regular * 2.0, "the Fortress's toughest ordinary enemy (%.0f) is more than twice the Dead Coast's (%.0f)" % [fortress_regular, coast_regular])


func _test_doc(reports: Dictionary) -> void:
	print("Doc stays honest")
	var file := FileAccess.open(DOC, FileAccess.READ)
	_check(file != null, "docs/COMBAT_BALANCE.md exists")
	if file == null:
		return
	var text := file.get_as_text()
	_check(text.contains("not a human playtest") or text.contains("Not a human playtest"), "the doc says these are formula numbers, not a human playtest")
	var fortress: Dictionary = reports[&"iron_fortress"]
	_check(text.contains("%.1f" % fortress["threat"]), "the doc quotes the current Iron Fortress threat (%.1f): a data change must refresh the doc" % fortress["threat"])
	_check(text.contains("%.0f" % fortress["wave_ehp"]), "the doc quotes the current Iron Fortress wave health (%.0f)" % fortress["wave_ehp"])
