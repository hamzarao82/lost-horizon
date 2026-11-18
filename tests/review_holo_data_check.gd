extends SceneTree
## The Holo Bay's data export (tools/review/holo_export.gd): every item, attack and character as JSON.
## godot --headless --path . -s tests/review_holo_data_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null


func _run() -> void:
	var dir := OS.get_user_data_dir() + "/holo_test_%d" % OS.get_process_id()
	var counts := HoloExport.export_all(dir)
	var items: Variant = _read(dir + "/items.json")
	var attacks: Variant = _read(dir + "/attacks.json")
	var characters: Variant = _read(dir + "/characters.json")
	_check(items is Array and (items as Array).size() == counts["items"] and (items as Array).size() >= 45, "every item is exported (%d)" % (counts["items"]))
	_check(attacks is Array and (attacks as Array).size() >= 35, "every attack is exported (%d)" % counts["attacks"])
	_check(characters is Array and (characters as Array).size() >= 6, "the player and every enemy scene are exported (%d)" % counts["characters"])
	if items is Array:
		var by_id := {}
		for it in items:
			by_id[String((it as Dictionary)["id"])] = it
		_check(by_id.has("claymore") and by_id.has("warden_blade") and by_id.has("combat_helmet"), "known items are present")
		var clay: Dictionary = by_id.get("claymore", {})
		_check(clay.get("kind") == "WEAPON" and clay.get("rarity") is String and float(clay.get("damage_multiplier", 0.0)) > 1.0, "a weapon carries its kind, rarity and damage multiplier")
		_check(String(clay.get("model", "")) == "weapons/claymore.glb", "a weapon points at its model file")
		_check(String((by_id.get("combat_helmet", {}) as Dictionary).get("model", "")) == "armor/combat_helmet.glb", "an armor piece points at its model file")
		var with_model := 0
		var model_files_exist := true
		for it in items:
			var m := String((it as Dictionary).get("model", ""))
			if m != "":
				with_model += 1
				model_files_exist = model_files_exist and ResourceLoader.exists("res://assets/" + m)
		_check(with_model >= 10 and model_files_exist, "every model path points at a real file (%d items have a model)" % with_model)
		var icons_ok := true
		for it in items:
			var ic := String((it as Dictionary).get("icon", ""))
			if ic != "":
				icons_ok = icons_ok and ResourceLoader.exists("res://assets/icons/" + ic)
		_check(icons_ok, "every icon path points at a real file")
	if attacks is Array:
		var light4 := {}
		var owners := {}
		for a in attacks:
			owners[(a as Dictionary)["owner"]] = true
			if (a as Dictionary)["id"] == "light_5":
				light4 = a
		_check(owners.has("player") and owners.has("enemy"), "attacks are split into player and enemy")
		_check(float(light4.get("damage", 0.0)) == 22.0 and int(light4.get("total_frames", 0)) == 32, "the fifth light hit's numbers match its data file")
		var telegraph_ok := true
		for a in attacks:
			telegraph_ok = telegraph_ok and float((a as Dictionary)["telegraph_seconds"]) > 0.0
		_check(telegraph_ok, "every attack has a telegraph time")
	if characters is Array:
		var ids := {}
		for c in characters:
			ids[String((c as Dictionary)["id"])] = c
		_check(ids.has("player") and ids.has("Warden") and ids.has("PatrolSoldier"), "the player, the Warden and the soldier are listed")
		_check(String((ids.get("Warden", {}) as Dictionary).get("model", "")) == "characters/warden.glb", "the Warden points at its model")
		_check(String((ids.get("Warden", {}) as Dictionary).get("role", "")) == "boss", "the Warden is marked as a boss")
		_check(float(((ids.get("PatrolSoldier", {}) as Dictionary).get("stats", {}) as Dictionary).get("hit_points", 0.0)) > 0.0, "an enemy carries its hit points")
		var untextured := 0
		for c in characters:
			if String((c as Dictionary).get("model", "")) == "":
				untextured += 1
		_check(untextured >= 1, "bosses without a model of their own say so in words (%d)" % untextured)
	for f in ["items.json", "attacks.json", "characters.json"]:
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
	print("review_holo_data_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
