extends SceneTree
## Regenerates resources/progression/*.tres: godot --headless --path . -s tools/gen_progression_data.gd
## The .tres files are the shipped data; edit values here and re-run, or edit the .tres directly.

const OUT: String = "res://resources/progression/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "attributes")
	DirAccess.make_dir_recursive_absolute(OUT + "skills")
	_config()
	_attribute(&"vitality", "Vitality", "Maximum health: survive more hits.", 10, {&"max_health": 5.0})
	_attribute(&"strength", "Strength", "Melee damage with every weapon.", 10, {&"damage_all": 0.02})
	_attribute(&"endurance", "Endurance", "Stamina pool and a little damage resistance.", 10, {&"max_stamina": 4.0, &"resist": 0.005})
	_attribute(&"agility", "Agility", "Faster movement and cheaper dodges.", 10, {&"move_speed": 0.01, &"dodge_cost": -0.015})
	_attribute(&"technique", "Technique", "Heavy attack damage and faster teleport recharge.", 10, {&"damage_heavy": 0.015, &"teleport_recharge": -0.03})

	var C := SkillData.Category
	_skill(&"sharpened_edge", "Sharpened Edge", "Light attacks hit harder.", C.COMBAT, 3, 1, 2, [], {&"damage_light": 0.04}, Vector2i(0, 0))
	_skill(&"heavy_hitter", "Heavy Hitter", "Heavy and sprint attacks hit harder.", C.COMBAT, 3, 1, 3, [&"sharpened_edge"], {&"damage_heavy": 0.05}, Vector2i(1, 0))
	_skill(&"whirlwind", "Whirlwind", "Spin and air attacks hit harder.", C.COMBAT, 2, 2, 4, [&"heavy_hitter"], {&"damage_special": 0.06}, Vector2i(2, 0))
	_skill(&"toughness", "Toughness", "More maximum health.", C.SURVIVAL, 4, 1, 2, [], {&"max_health": 6.0}, Vector2i(0, 1))
	_skill(&"tempered_nerves", "Tempered Nerves", "Take less damage from every hit.", C.SURVIVAL, 3, 1, 3, [&"toughness"], {&"resist": 0.02}, Vector2i(1, 1))
	_skill(&"field_medic", "Field Medic", "Medkits heal more.", C.SURVIVAL, 3, 1, 3, [&"toughness"], {&"heal": 0.10}, Vector2i(2, 1))
	_skill(&"fleet_foot", "Fleet Foot", "Move faster.", C.MOBILITY, 3, 1, 2, [], {&"move_speed": 0.02}, Vector2i(0, 2))
	_skill(&"light_step", "Light Step", "Dodging costs less stamina.", C.MOBILITY, 2, 1, 3, [&"fleet_foot"], {&"dodge_cost": -0.08}, Vector2i(1, 2))
	_skill(&"deep_lungs", "Deep Lungs", "A larger stamina pool.", C.MOBILITY, 3, 1, 4, [&"fleet_foot"], {&"max_stamina": 8.0}, Vector2i(2, 2))
	_skill(&"quick_recharge", "Quick Recharge", "Teleport recharges faster.", C.SPECIAL, 3, 2, 3, [], {&"teleport_recharge": -0.08}, Vector2i(0, 3))
	_skill(&"focus", "Focus", "Stamina regenerates faster.", C.SPECIAL, 3, 1, 3, [], {&"stamina_regen": 0.10}, Vector2i(1, 3))
	_skill(&"scavenger", "Scavenger", "Find more currency.", C.SPECIAL, 3, 1, 4, [&"focus"], {&"currency": 0.10}, Vector2i(2, 3))
	_skill(&"combo_extension", "Combo Extension", "The light combo continues for one more hit per rank.", C.COMBAT, 3, 2, 5, [&"sharpened_edge"], {&"combo_extra": 1.0}, Vector2i(0, 4))
	_skill(&"counterattack", "Counterattack", "Dodging an attack arms a bonus light attack: +25%, +40%, +55%.", C.COMBAT, 3, 2, 5, [&"light_step"], {&"counter_rank": 1.0}, Vector2i(1, 4))
	print("progression data written")
	quit()


func _config() -> void:
	var config := ProgressionConfig.new()
	assert(config.validate().is_empty())
	ResourceSaver.save(config, OUT + "progression_config.tres")


func _attribute(id: StringName, label: String, purpose: String, max_points: int, effects: Dictionary) -> void:
	var data := AttributeData.new()
	data.id = id
	data.display_name = label
	data.purpose = purpose
	data.max_points = max_points
	data.effects = effects
	assert(data.validate().is_empty())
	ResourceSaver.save(data, OUT + "attributes/%s.tres" % id)


func _skill(id: StringName, label: String, text: String, category: int, max_rank: int, cost: int, min_level: int, prereqs: Array, effects: Dictionary, pos: Vector2i) -> void:
	var data := SkillData.new()
	data.id = id
	data.display_name = label
	data.description = text
	data.category = category as SkillData.Category
	data.max_rank = max_rank
	data.cost = cost
	data.min_level = min_level
	data.prerequisites = PackedStringArray(prereqs)
	data.effects = effects
	data.tree_position = pos
	ResourceSaver.save(data, OUT + "skills/%s.tres" % id)
