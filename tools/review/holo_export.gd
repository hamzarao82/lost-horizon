class_name HoloExport
extends RefCounted
## Data for the Review Hub's Holo Bay: every item, attack and character in the game as plain JSON, read from the
## game's own resources. (The 3D models themselves are already GLB files; the hub copies those byte for byte.)
## Development tool: tools/* is excluded from release builds.
##   HoloExport.export_all("C:/.../holo")  -> {items, attacks, characters}  (counts)

const ITEM_DIR: String = "res://resources/items/"
const ATTACK_DIR: String = "res://resources/attacks/"
const ENEMY_DIR: String = "res://scenes/enemies/"
const ICON_DIR: String = "res://assets/icons/"
const WEAPON_GLB_DIR: String = "res://assets/weapons/"
const ARMOR_GLB_DIR: String = "res://assets/armor/"
const PLAYER_ATTACK_PREFIXES: PackedStringArray = ["light_", "heavy_", "sprint_", "air_", "spin_"]
## Which model file each enemy scene is drawn with (SkinnedVisual.ENEMY_MODELS / MODEL_WEAPONS); the other bosses are
## the same models tinted and scaled, which the card says in words.
const MODEL_FOR_SCENE: Dictionary = {
	"PatrolSoldier": "soldier", "HeavySoldier": "heavy", "HunterElite": "elite", "Warden": "warden",
}
## Scenes whose enemy joins the "boss" group in _ready (which does not run for an instance outside the tree).
const BOSS_SCENES: PackedStringArray = ["Warden", "Director", "FortressCaptain", "StageBoss"]
const MODEL_WEAPON: Dictionary = {
	"player": "improvised_blade", "soldier": "military_machete", "heavy": "claymore", "elite": "katana", "warden": "warden_blade",
}


static func export_all(dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir)
	var items := _items()
	var attacks := _attacks()
	var characters := _characters()
	_write(dir + "/items.json", items)
	_write(dir + "/attacks.json", attacks)
	_write(dir + "/characters.json", characters)
	return {"items": items.size(), "attacks": attacks.size(), "characters": characters.size()}


static func _write(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()


static func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		var name := f.trim_suffix(".remap")
		if name.ends_with(ext):
			out.append(name)
	out.sort()
	return out


static func _items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for file in _files(ITEM_DIR, ".tres"):
		var item := load(ITEM_DIR + file) as ItemData
		if item == null:
			continue
		var id := String(item.item_id)
		var icon_file := id + ".png"
		var model := ""
		if ResourceLoader.exists(WEAPON_GLB_DIR + id + ".glb"):
			model = "weapons/" + id + ".glb"
		elif ResourceLoader.exists(ARMOR_GLB_DIR + id + ".glb"):
			model = "armor/" + id + ".glb"
		out.append({
			"id": id, "name": item.display_name, "kind": ItemData.Kind.keys()[item.kind], "category": ItemData.Category.keys()[item.category()],
			"rarity": ItemData.Rarity.keys()[item.rarity], "slot": ItemData.SLOT_NAMES[item.equip_slot()],
			"damage_multiplier": item.damage_multiplier, "attack_speed": item.attack_speed, "reach": item.reach,
			"stagger_power": item.stagger_power, "recovery_scale": item.recovery_scale, "heavy_multiplier": item.heavy_multiplier,
			"armor_points": item.armor_points, "heal_amount": item.heal_amount, "armor_restore": item.armor_restore,
			"base_stats": item.base_stats, "max_upgrade": item.max_upgrade, "unique": item.unique, "quest_item": item.quest_item,
			"value": item.value, "description": item.description, "power": snappedf(item.power(), 0.01),
			"icon": icon_file if ResourceLoader.exists(ICON_DIR + icon_file) else "", "model": model,
		})
	return out


static func _attacks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for file in _files(ATTACK_DIR, ".tres"):
		var a := load(ATTACK_DIR + file) as AttackData
		if a == null:
			continue
		var id := String(a.id)
		var owner := "enemy"
		for prefix in PLAYER_ATTACK_PREFIXES:
			if id.begins_with(prefix):
				owner = "player"
		out.append({
			"id": id, "owner": owner, "damage": a.damage, "stamina_cost": a.stamina_cost,
			"startup_frames": a.startup_frames, "active_frames": a.active_frames, "recovery_frames": a.recovery_frames,
			"total_frames": a.total_frames(), "total_seconds": snappedf(a.total_frames() / 60.0, 0.001),
			"telegraph_seconds": snappedf(a.startup_frames / 60.0, 0.001),
			"knockback": a.knockback, "stagger_time": a.stagger_time, "lunge_speed": a.lunge_speed,
			"hit_stop": a.hit_stop, "swing_arc": a.swing_arc, "aoe_radius": a.aoe_radius,
		})
	return out


static func _characters() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"id": "player", "name": "The player (the thief)", "role": "player", "model": "characters/player.glb",
			"weapon": MODEL_WEAPON["player"], "stats": {"max_health": 100.0, "walk_speed": 5.0, "sprint_speed": 8.5},
			"note": "The only model with the story clips (waking, limping, picking up, opening the bag) and the 4th/5th light and 2nd/3rd heavy hits."})
	for file in _files(ENEMY_DIR, ".tscn"):
		var scene := load(ENEMY_DIR + file) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate()
		var id := file.get_basename()
		var model_key: String = MODEL_FOR_SCENE.get(id, "")
		var entry := {
			"id": id, "name": String(enemy.get("display_name")), "role": "boss" if BOSS_SCENES.has(id) else "enemy",
			"model": ("characters/%s.glb" % model_key) if model_key != "" else "",
			"weapon": MODEL_WEAPON.get(model_key, ""),
			"stats": {"hit_points": enemy.get("hit_points"), "move_speed": enemy.get("move_speed"),
					"detection_range": enemy.get("detection_range"), "attack_range": enemy.get("attack_range"),
					"body_scale": enemy.get("body_scale"), "swing": String(enemy.get("swing_path")).get_file().get_basename()},
			"tactics": {"scheduled": enemy.get("scheduled"), "flank_slots": enemy.get("flank_slots"), "spacing": enemy.get("spacing"),
					"reinforcement_cap": enemy.get("reinforcement_cap")},
			"note": "" if model_key != "" else "Drawn with one of the existing character models, tinted and scaled (no model file of its own).",
		}
		enemy.free()
		out.append(entry)
	return out
