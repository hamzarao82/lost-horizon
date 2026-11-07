extends SceneTree
## Writes the Milestone 9 fortress enemy configs, attack data, loot tables and unique items.
## godot --headless --path . -s tools/gen_director_data.gd
## Edit the numbers here, rerun, commit the .tres files: the tests assert fairness from the data.

const ATTACKS: Dictionary = {
	# id: [damage, startup, active, recovery, knockback, stagger, lunge]
	"fortress_burst": [8.0, 44, 1, 40, 2.5, 0.2, 0.0],
	"fortress_heavy_burst": [12.0, 54, 1, 54, 3.0, 0.3, 0.0],
	"fortress_shove": [10.0, 30, 6, 30, 3.0, 0.3, 0.0],
	"fortress_captain_volley": [9.0, 42, 1, 44, 2.5, 0.2, 0.0],
	"fortress_captain_charge": [18.0, 48, 10, 54, 4.0, 0.5, 0.0],
	"fortress_captain_slam": [20.0, 40, 6, 52, 5.0, 0.5, 0.0],
	"director_volley": [9.0, 42, 1, 40, 2.5, 0.2, 0.0],
	"director_sweep": [8.0, 48, 1, 48, 2.5, 0.2, 0.0],
	"director_counter": [12.0, 36, 6, 36, 4.0, 0.4, 0.0],
	"director_dash": [16.0, 48, 10, 54, 4.5, 0.5, 0.0],
	"director_ring": [14.0, 54, 1, 54, 4.0, 0.4, 0.0],
	"director_barrage": [8.0, 60, 1, 60, 2.5, 0.2, 0.0],
}


func _initialize() -> void:
	for id in ATTACKS:
		_write_attack(id, ATTACKS[id])
	_write_loot("iron_fortress_regular", 0.55, 0,
			["bandage", "credits_small", "electronics", "armor_patch", "antiseptic", "sharpening_oil"], [])
	_write_loot("iron_fortress_elite", 0.8, 1,
			["credits_medium", "scrap_metal", "electronics", "armor_patch", "health_potion", "combat_helmet"], [])
	_write_loot("iron_fortress_captain", 1.0, 2,
			["credits_medium", "health_potion", "scrap_metal", "armor_patch", "electronics"], ["upgrade_kit_armor"])
	_write_loot("iron_fortress_director", 1.0, 3,
			["credits_medium", "health_potion", "upgrade_kit_armor", "scrap_metal"], ["upgrade_kit_weapon"])
	_write_item("fortress_badge", "Fortress Captain's Badge", 3, 120,
			"A dented command badge taken from a captain who never left his post. The lockdown codes are still scratched on the back.",
			"{\n\"damage_reduction\": 0.04,\n\"max_health\": 8.0\n}", "iron_fortress")
	_write_item("director_signet", "The Director's Signet", 4, 300,
			"A heavy signet ring that once opened every door on the island. It is warm, as if it still expects its owner.",
			"{\n\"damage_reduction\": 0.05,\n\"max_health\": 10.0,\n\"damage_mult\": 1.04\n}", "iron_fortress")
	# id, scene, name, hp, armor, color, scale, stagger, swing, loot, speed, alarm, burst, lead, shot, unique, ranged?
	_write_config("fortress_infantry", "res://scenes/enemies/PatrolSoldier.tscn", "Fortress Infantry", 95.0, 20.0,
			Color(0.3, 0.34, 0.28), 1.0, 0.1, "res://resources/attacks/fortress_shove.tres", "iron_fortress_regular",
			3.4, false, 3, 0.35, "fortress_burst", "", true)
	_write_config("elite_security_soldier", "res://scenes/enemies/HunterElite.tscn", "Elite Security Soldier", 150.0, 40.0,
			Color(0.2, 0.22, 0.3), 1.1, 0.35, "res://resources/attacks/fortress_shove.tres", "iron_fortress_elite",
			3.8, false, 3, 0.3, "fortress_burst", "", true)
	_write_config("heavy_assault_unit", "res://scenes/enemies/HeavySoldier.tscn", "Heavy Assault Unit", 260.0, 90.0,
			Color(0.28, 0.26, 0.24), 1.35, 0.75, "res://resources/attacks/facility_shield_bash.tres", "iron_fortress_elite",
			2.1, false, 3, 0.5, "fortress_heavy_burst", "", true)
	_write_config("tactical_commander", "res://scenes/enemies/PatrolSoldier.tscn", "Tactical Commander", 160.0, 50.0,
			Color(0.2, 0.3, 0.45), 1.1, 0.3, "res://resources/attacks/fortress_shove.tres", "iron_fortress_elite",
			3.8, true, 3, 0.3, "fortress_burst", "", true)
	# The captain and the Director run their own attack sets (fortress_captain.gd, director.gd): no ranged brain.
	_write_config("fortress_captain", "res://scenes/enemies/FortressCaptain.tscn", "Fortress Captain", 360.0, 80.0,
			Color(0.45, 0.16, 0.12), 1.5, 0.7, "res://resources/attacks/fortress_captain_slam.tres", "iron_fortress_captain",
			3.0, true, 3, 0.3, "fortress_captain_volley", "res://resources/items/fortress_badge.tres", false)
	_write_config("director", "res://scenes/enemies/Director.tscn", "The Director", 600.0, 0.0,
			Color(0.12, 0.12, 0.16), 1.15, 0.85, "res://resources/attacks/director_counter.tres", "iron_fortress_director",
			3.0, false, 3, 0.3, "director_volley", "res://resources/items/director_signet.tres", false)
	print("director data written")
	quit()


func _write_attack(id: String, v: Array) -> void:
	var text := "[gd_resource type=\"Resource\" script_class=\"AttackData\" load_steps=2 format=3]\n\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/combat/attack_data.gd\" id=\"1_attack\"]\n\n[resource]\n"
	text += "script = ExtResource(\"1_attack\")\nid = &\"%s\"\ndamage = %.1f\nstamina_cost = 0.0\n" % [id, v[0]]
	text += "startup_frames = %d\nactive_frames = %d\nrecovery_frames = %d\nknockback = %.1f\nstagger_time = %.1f\n" % [v[1], v[2], v[3], v[4], v[5]]
	text += "lunge_speed = %.1f\nhit_stop = 0.05\nshake = 0.3\nswing_arc = 0.0\nswing_flip = false\n" % v[6]
	_save("res://resources/attacks/%s.tres" % id, text)


func _write_loot(id: String, chance: float, source: int, items: Array, guaranteed: Array) -> void:
	var text := "[gd_resource type=\"Resource\" script_class=\"LootTable\" format=3]\n\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/loot/loot_table.gd\" id=\"1_table\"]\n\n[resource]\n"
	text += "script = ExtResource(\"1_table\")\ndrop_chance = %.2f\nitem_paths = PackedStringArray(%s)\n" % [chance, _paths(items)]
	text += "source = %d\nregion = \"iron_fortress\"\n" % source
	if not guaranteed.is_empty():
		text += "guaranteed_paths = PackedStringArray(%s)\n" % _paths(guaranteed)
	_save("res://resources/loot/%s.tres" % id, text)


func _paths(names: Array) -> String:
	var parts: PackedStringArray = []
	for n in names:
		parts.append("\"res://resources/items/%s.tres\"" % n)
	return ", ".join(parts)


func _write_item(id: String, display: String, rarity: int, value: int, desc: String, stats: String, region: String) -> void:
	var text := "[gd_resource type=\"Resource\" script_class=\"ItemData\" format=3]\n\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/inventory/item_data.gd\" id=\"1_item\"]\n\n[resource]\n"
	text += "script = ExtResource(\"1_item\")\nitem_id = &\"%s\"\ndisplay_name = \"%s\"\nkind = 1\nrarity = %d\n" % [id, display, rarity]
	text += "description = \"%s\"\nslot = 7\nbase_stats = %s\nvalue = %d\nunique = true\nregion = \"%s\"\n" % [desc, stats, value, region]
	_save("res://resources/items/%s.tres" % id, text)


func _write_config(id: String, scene: String, display: String, hp: float, armor: float, color: Color, body_scale: float,
		stagger: float, swing: String, loot: String, speed: float, alarm: bool, burst: int, lead: float, shot: String,
		unique: String, with_ranged: bool) -> void:
	var text := "[gd_resource type=\"Resource\" script_class=\"EnemyConfig\" load_steps=4 format=3]\n\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/ai/enemy_config.gd\" id=\"1_cfg\"]\n"
	text += "[ext_resource type=\"Script\" path=\"res://scripts/ai/ranged/ranged_config.gd\" id=\"2_ranged\"]\n\n"
	text += "[sub_resource type=\"Resource\" id=\"Resource_ranged\"]\nscript = ExtResource(\"2_ranged\")\n"
	text += "shot_path = \"res://resources/attacks/%s.tres\"\nburst_shots = %d\nshot_spacing = 0.3\n" % [shot, burst]
	text += "band_min = 7.0\nband_max = 12.0\ncooldown_min = 1.6\ncooldown_max = 2.4\naim_error_deg = 4.0\n"
	text += "lead_factor = %.2f\nprojectile_speed = 18.0\nshove_range = 2.0\nuse_cover = true\n\n" % lead
	text += "[resource]\nscript = ExtResource(\"1_cfg\")\nscene_path = \"%s\"\ndisplay_name = \"%s\"\n" % [scene, display]
	text += "hit_points = %.1f\narmor = %.1f\nbody_color = Color(%.2f, %.2f, %.2f, 1)\nbody_scale = %.2f\n" % [hp, armor, color.r, color.g, color.b, body_scale]
	text += "stagger_resist = %.2f\nswing_path = \"%s\"\nloot_table_path = \"res://resources/loot/%s.tres\"\n" % [stagger, swing, loot]
	text += "move_speed = %.1f\ndetection_range = 18.0\nattack_range = 2.2\nring_distance = 3.4\ncooldown_min = 1.0\ncooldown_max = 1.6\n" % speed
	text += "coordinate_alarm = %s\n" % ("true" if alarm else "false")
	if with_ranged:
		text += "ranged = SubResource(\"Resource_ranged\")\n"
	if unique != "":
		text += "unique_drop_path = \"%s\"\n" % unique
	_save("res://resources/enemies/%s.tres" % id, text)


func _save(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _ones(n: int) -> String:
	var parts: PackedStringArray = []
	for i in n:
		parts.append("1")
	return ", ".join(parts)
