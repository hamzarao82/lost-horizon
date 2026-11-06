extends SceneTree
## Save version 3 checks (headless): godot --headless --path . -s tests/save_v3_check.gd
## Progression and the extended inventory through the real SaveManager file, migration from a Milestone 5
## (version 2) save, hostile data, unique rewards and reset. Uses the per-process test save file.

var _failures: int = 0
var _checks: int = 0
var _sm: Node
var _prog: Node


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
	_sm = root.get_node("SaveManager")
	_prog = root.get_node("Progression")
	_clean()
	await _test_milestone5_save_loads()
	await _test_round_trip()
	await _test_unique_reward_once()
	_test_hostile_data()
	_test_type_confusion()
	_test_prerequisites_enforced()
	await _test_reset_and_scene_reload()
	_clean()
	print("\nsave_v3_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _clean() -> void:
	_sm.reset_runtime_state()
	_sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = _sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	_sm.defeated_bosses.clear()


func _write_raw(text: String) -> void:
	var file := FileAccess.open(_sm.save_path(), FileAccess.WRITE)
	file.store_string(text)
	file = null


func _read_save() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_sm.save_path()))
	return parsed if parsed is Dictionary else {}


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _item(id: String) -> ItemData:
	return load("res://resources/items/%s.tres" % id) as ItemData


# A save exactly as Milestone 5 wrote it: version 2, only weapon/armor/armor_points/potions in the inventory.
const M5_SAVE: String = '{"version": 2, "saved_at": 1762300000, "next_wave": 1, "completed": false, "inventory": {"weapon": "iron_sword", "armor": "light_tactical_armor", "armor_points": 40.0, "potions": 2}, "player": {"health": 70.0, "max_health": 100.0}, "defeated_bosses": ["warden"], "world": {"checkpoint_id": "", "position": null}}'


func _test_milestone5_save_loads() -> void:
	print("Milestone 5 (version 2) save")
	_prog.reset()
	_write_raw(M5_SAVE)
	_check(_sm.load_game(), "a real version 2 save still loads")
	var data: Dictionary = _sm.pending_data
	_check(int(data["version"]) == _sm.CURRENT_VERSION, "it is upgraded to the current version (%d)" % _sm.CURRENT_VERSION)
	_check(data["inventory"]["weapon"] == "iron_sword" and data["inventory"]["armor"] == "light_tactical_armor"
			and int(data["inventory"]["potions"]) == 2, "weapon, armor and medkits are intact")
	_check(int(data["inventory"]["currency"]) == 0 and (data["inventory"]["bag"] as Array).is_empty()
			and (data["inventory"]["unique_claimed"] as Array).is_empty(), "the new inventory parts start empty")
	_check(_prog.level() == 1 and _prog.progress.skills.is_empty() and _prog.progress.xp == 0,
			"progression starts at level 1 with no skills")
	_check(data["defeated_bosses"].has("warden"), "defeated bosses are kept")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	_check(player.inventory.weapon != null and String(player.inventory.weapon.item_id) == "iron_sword"
			and player.inventory.potions == 2, "the player gets the old weapon and medkits")
	_check(player.inventory.armor != null and String(player.inventory.armor.item_id) == "light_tactical_armor",
			"the player gets the old armor")
	main.queue_free()
	await _frames(2)
	_clean()


func _test_round_trip() -> void:
	print("Round trip of all new state")
	_prog.reset()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var inv: Inventory = player.inventory
	inv.collect(_item("scrap_metal"), 5)
	inv.add_currency(250)
	inv.collect(_item("combat_helmet"))
	var worn: Dictionary = inv.equip(_item("combat_helmet"))
	inv.upgrades["improvised_blade"] = 2
	inv.unique_claimed["warden_blade"] = true
	inv.merchant_stock["outpost_quartermaster"] = {"antiseptic": 7}
	_prog.award_xp(900, "test")
	var level_before: int = _prog.level()
	var attr_id := StringName(_prog.attribute_defs[0].id)
	_prog.spend_attribute_point(attr_id)
	var skill_id := StringName("")
	for skill in _prog.tree.all():
		if skill.prerequisites.is_empty() and _prog.tree.can_buy(_prog.progress, skill.id):
			skill_id = skill.id
			break
	_check(skill_id != &"" and _prog.unlock_skill(skill_id), "a skill was bought to persist (%s)" % skill_id)
	_check(level_before > 1, "the test character levelled up (level %d)" % level_before)
	var attr_points: int = _prog.progress.attribute_value(attr_id, _prog.attribute_def(attr_id))
	_check(_sm.save_game("test"), "the game saves")
	var file_data := _read_save()
	_check(int(file_data.get("version", 0)) == _sm.CURRENT_VERSION and file_data.has("progression"), "the file is the current version with progression")
	_check(int(file_data["inventory"]["currency"]) == 250, "currency is in the file")
	_check(not file_data.has("inventory_full"), "no stray extra sections")

	main.queue_free()
	await _frames(2)
	_sm.reset_runtime_state()  # progression back to level 1 before the load proves the file carries it
	_check(_prog.level() == 1, "reset returned progression to level 1")
	_check(_sm.load_game(), "the saved v3 file loads")
	_check(_prog.level() == level_before, "level restored (%d)" % _prog.level())
	_check(_prog.progress.skill_rank(skill_id) == 1, "skill restored")
	_check(_prog.progress.attribute_value(attr_id, _prog.attribute_def(attr_id)) == attr_points, "attribute points restored")
	var main2 := await _spawn_main()
	var inv2: Inventory = (main2.get_node("Player") as Player).inventory
	_check(inv2.count_of("scrap_metal") == 5, "bag contents restored")
	_check(inv2.currency == 250, "currency restored")
	_check(worn.get("ok", false) and inv2.equipped(ItemData.Slot.HEAD) != null
			and String(inv2.equipped(ItemData.Slot.HEAD).item_id) == "combat_helmet", "worn head armor restored")
	_check(int(inv2.upgrades.get("improvised_blade", 0)) == 2, "upgrade level restored")
	_check(inv2.unique_claimed.has("warden_blade"), "claimed unique reward restored")
	_check(int(inv2.merchant_stock.get("outpost_quartermaster", {}).get("antiseptic", -1)) == 7, "merchant stock restored")
	main2.queue_free()
	await _frames(2)
	_clean()


func _test_unique_reward_once() -> void:
	print("Unique reward once")
	var main := await _spawn_main()
	var inv: Inventory = (main.get_node("Player") as Player).inventory
	var blade := _item("warden_blade")
	_check(inv.add_item(blade) or inv.collect(blade)["added"] > 0, "the Warden's blade is received once")
	_check(inv.unique_claimed.has("warden_blade"), "it is marked claimed")
	_check(_sm.save_game("test"), "saved")
	main.queue_free()
	await _frames(2)
	_sm.reset_runtime_state()
	_check(_sm.load_game(), "loaded")
	var main2 := await _spawn_main()
	var inv2: Inventory = (main2.get_node("Player") as Player).inventory
	var before := inv2.count_of("warden_blade")
	_check(not inv2.add_item(blade), "after a reload add_item refuses a second blade")
	_check(int(inv2.collect(blade)["added"]) == 0, "after a reload collect refuses a second blade")
	_check(inv2.count_of("warden_blade") == before, "the number of blades did not change")
	var table := load("res://resources/loot/warden_loot.tres") as LootTable
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var again := false
	for entry in table.roll_all(rng, inv2.unique_claimed):
		if (entry["item"] as ItemData).item_id == &"warden_blade":
			again = true
	_check(not again, "the Warden's loot table skips the blade once claimed")
	main2.queue_free()
	await _frames(2)
	_clean()


func _test_hostile_data() -> void:
	print("Hostile data")
	_prog.reset()
	var tree_skill: SkillData = _prog.tree.all()[0]
	var hostile := {
		"version": 3, "saved_at": "x", "next_wave": 99, "completed": "yes",
		"inventory": {
			"weapon": "../../evil", "armor": 5, "armor_points": -50, "potions": -9,
			"currency": 99999999999,
			"bag": [{"id": "nope", "count": -5}, {"id": "scrap_metal", "count": 99999}, "str", 7,
					{"id": "x".repeat(300), "count": 1}],
			"slots": {"head": "warden_plate", "bogus": "combat_helmet"},
			"upgrades": {"iron_sword": 999, "zzz": 5},
			"unique_claimed": ["x".repeat(300), 5, "warden_blade"],
			"merchant_stock": {"outpost_quartermaster": {"antiseptic": -3, "bad id": 4}, "m": "str"},
		},
		"player": {"health": 70, "max_health": 100},
		"defeated_bosses": [],
		"progression": {
			"xp": -5, "currency": -1, "attribute_points": 9999, "skill_points": 9999,
			"attributes": {String(_prog.attribute_defs[0].id): 9999, "unknown": 4},
			"skills": {String(tree_skill.id): 99, "unknown_skill": 3},
		},
	}
	_write_raw(JSON.stringify(hostile))
	_check(_sm.load_game(), "hostile data loads instead of crashing or being rejected")
	var data: Dictionary = _sm.pending_data
	var inv: Dictionary = data["inventory"]
	_check(int(inv["potions"]) >= 0 and int(inv["potions"]) <= 99, "medkits are clamped")
	_check(int(inv["currency"]) == Inventory.MAX_CURRENCY, "huge currency is clamped to the maximum")
	var bag_ok := true
	for entry in inv["bag"]:
		if not (entry is Dictionary) or int(entry["count"]) < 1 or int(entry["count"]) > 99:
			bag_ok = false
	_check(bag_ok, "every bag entry is a valid stack")
	_check(int(inv["upgrades"].get("iron_sword", 0)) <= 20,
			"upgrade levels are bounded")
	_check(not (inv["unique_claimed"] as Array).has(5) and (inv["unique_claimed"] as Array).size() <= 256,
			"claimed ids are validated")
	_check(_prog.level() >= 1 and _prog.progress.xp >= 0, "negative xp becomes 0")
	_check(_prog.progress.skill_rank(tree_skill.id) <= tree_skill.max_rank, "skill rank is capped at its maximum")
	_check(_prog.progress.currency >= 0, "negative progression currency is ignored")
	_apply_sanitised_inventory()
	_clean()


## Dictionaries, arrays and strings where numbers belong must neither crash the load nor reach the game.
func _test_type_confusion() -> void:
	print("Wrong types in the file")
	_prog.reset()
	var confused := {
		"version": 3, "saved_at": {}, "next_wave": [], "completed": {"a": 1},
		"inventory": {
			"weapon": [], "armor": {}, "armor_points": "lots", "potions": {},
			"currency": [1, 2], "bag": [{"id": "scrap_metal", "count": {}}, {"id": ["x"], "count": 1}],
			"slots": [], "upgrades": {"iron_sword": {}}, "unique_claimed": {"a": 1},
			"merchant_stock": {"outpost_quartermaster": {"antiseptic": []}},
		},
		"player": {"health": {}, "max_health": 100},
		"defeated_bosses": {},
		"progression": {"xp": {"a": 1}, "currency": [], "attributes": {String(_prog.attribute_defs[0].id): []},
				"skills": [], "kills": [1, 2], "rewarded_quests": {}},
	}
	_write_raw(JSON.stringify(confused))
	_check(_sm.load_game(), "a save with wrong types loads with safe defaults")
	var inv: Dictionary = _sm.pending_data.get("inventory", {})
	_check(int(inv.get("potions", -1)) == 0 and int(inv.get("currency", -1)) == 0, "numbers fall back to 0")
	_check(_prog.level() == 1 and _prog.progress.xp == 0, "progression falls back to level 1")
	_apply_sanitised_inventory()
	_clean()


## The hostile bag and slots are applied by the real Inventory: check that applying them is safe.
func _apply_sanitised_inventory() -> void:
	var inventory := Inventory.new()
	inventory.from_dict(_sm.pending_data["inventory"])
	_check(inventory.invalid_ids_dropped >= 0, "applying the sanitised inventory does not crash")
	_check(inventory.currency <= Inventory.MAX_CURRENCY and inventory.potions <= 99, "the applied inventory is within limits")
	inventory.free()


func _test_prerequisites_enforced() -> void:
	print("Skill prerequisites on load")
	var child: SkillData = null
	for skill in _prog.tree.all():
		if not skill.prerequisites.is_empty():
			child = skill
			break
	_check(child != null, "the tree has a skill with prerequisites")
	if child == null:
		return
	var max_xp: int = _prog.config.xp_for_level(_prog.config.max_level())
	var raw := {"xp": max_xp, "skills": {String(child.id): 1}}
	var clean: Dictionary = _prog.sanitize(raw)
	_check(not clean["skills"].has(child.id) and not clean["skills"].has(String(child.id)),
			"a skill without its prerequisite is dropped (%s)" % child.id)
	_check(int(clean["skill_points"]) > 0, "its points are not lost")
	var pre_id := StringName(child.prerequisites[0])
	var ok_raw := {"xp": max_xp, "skills": {String(pre_id): 1, String(child.id): 1}}
	var ok_clean: Dictionary = _prog.sanitize(ok_raw)
	_check(ok_clean["skills"].size() == 2, "with the prerequisite both skills stay")
	_prog.reset()


func _test_reset_and_scene_reload() -> void:
	print("Reset and scene reload")
	_prog.reset()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	_prog.award_xp(900, "test")
	var level: int = _prog.level()
	_check(level > 1, "levelled to %d" % level)
	player.health.take_damage(9999.0)
	await _frames(2)
	main.queue_free()
	await _frames(2)
	var main2 := await _spawn_main()
	_check(_prog.level() == level, "progression survives death and a scene reload")
	main2.queue_free()
	await _frames(2)
	_sm.reset_runtime_state()
	_check(_prog.level() == 1 and _prog.progress.xp == 0, "a new game resets progression")
	_clean()
