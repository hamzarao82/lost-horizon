class_name StatsResolver
extends RefCounted
## The single place where progression turns into gameplay numbers. Pure static functions.
##
## Damage pipeline (every modifier enters exactly once):
##   final = weapon multiplier (Inventory, applied at the call site)
##         x min(1 + damage_all + damage_<kind>, cap)        attributes + skills, additive inside
##         x equipment_stats.damage_mult                      gear bonus other than the weapon itself
## Incoming damage: take = raw x (1 - clamp(resist + equipment_stats.damage_reduction, 0, max)),
## then HealthComponent drains the armor pool before health as before.

## Every effect key attributes and skills may use, with what it does.
const EFFECTS: Dictionary = {
	&"damage_all": "melee damage, fraction added to every attack kind",
	&"damage_light": "light attack damage, fraction",
	&"damage_heavy": "heavy and sprint attack damage, fraction",
	&"damage_special": "spin and air attack damage, fraction",
	&"max_health": "flat maximum health",
	&"max_stamina": "flat maximum stamina",
	&"stamina_regen": "stamina regeneration, fraction",
	&"resist": "incoming damage reduction, fraction",
	&"move_speed": "walk and sprint speed, fraction",
	&"dodge_cost": "dodge stamina cost, fraction (negative = cheaper)",
	&"teleport_recharge": "teleport recharge time, fraction (negative = faster)",
	&"heal": "medkit healing, fraction",
	&"currency": "currency earned, fraction",
}

const DEFAULT_EQUIPMENT: Dictionary = {
	&"damage_mult": 1.0, &"damage_reduction": 0.0, &"max_health_bonus": 0.0, &"move_speed_mult": 1.0,
}


## Clamps whatever the equipment system reports into the shape the resolver expects.
static func equipment(raw: Variant) -> Dictionary:
	var out := DEFAULT_EQUIPMENT.duplicate()
	if raw is Dictionary:
		for key in DEFAULT_EQUIPMENT:
			var value: Variant = raw.get(key, raw.get(String(key)))
			if (value is float and is_finite(value)) or value is int:
				out[key] = float(value)
	out[&"damage_mult"] = clampf(out[&"damage_mult"], 0.5, 3.0)
	out[&"damage_reduction"] = clampf(out[&"damage_reduction"], 0.0, 0.9)
	out[&"max_health_bonus"] = clampf(out[&"max_health_bonus"], -50.0, 500.0)
	out[&"move_speed_mult"] = clampf(out[&"move_speed_mult"], 0.5, 1.5)
	return out


## Sum of one effect over spent attribute points and owned skill ranks.
static func effect_total(key: StringName, progress: PlayerProgress, attribute_defs: Array, tree: SkillTree) -> float:
	var total := 0.0
	for def: AttributeData in attribute_defs:
		if def.effects.has(key):
			total += float(def.effects[key]) * int(progress.attributes.get(def.id, 0))
	if tree:
		for id in progress.skills:
			var skill := tree.get_skill(id)
			if skill and skill.effects.has(key):
				total += float(skill.effects[key]) * int(progress.skills[id])
	return total


## AttackData.id -> light / heavy / special.
static func kind_of(attack_id: StringName) -> StringName:
	var text := String(attack_id)
	if text.begins_with("heavy") or text.begins_with("sprint"):
		return &"heavy"
	if text.begins_with("air") or text.begins_with("spin"):
		return &"special"
	return &"light"


static func damage_multiplier(kind: StringName, progress: PlayerProgress, attribute_defs: Array, tree: SkillTree, equipment_stats: Dictionary = {}) -> float:
	var part := 1.0 + effect_total(&"damage_all", progress, attribute_defs, tree)
	part += effect_total(StringName("damage_" + String(kind)), progress, attribute_defs, tree)
	part = minf(part, progress.config.damage_mult_cap)
	return part * float(equipment(equipment_stats)[&"damage_mult"])


## Multiplier on damage the player takes (1.0 = unchanged).
static func incoming_multiplier(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree, equipment_stats: Dictionary = {}) -> float:
	var reduction := effect_total(&"resist", progress, attribute_defs, tree) + float(equipment(equipment_stats)[&"damage_reduction"])
	return 1.0 - clampf(reduction, 0.0, progress.config.max_damage_reduction)


static func max_health_bonus(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree, equipment_stats: Dictionary = {}) -> float:
	return effect_total(&"max_health", progress, attribute_defs, tree) + float(equipment(equipment_stats)[&"max_health_bonus"])


static func max_stamina_bonus(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree) -> float:
	return effect_total(&"max_stamina", progress, attribute_defs, tree)


static func stamina_regen_mult(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree) -> float:
	return 1.0 + maxf(effect_total(&"stamina_regen", progress, attribute_defs, tree), 0.0)


static func move_speed_mult(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree, equipment_stats: Dictionary = {}) -> float:
	var bonus := clampf(effect_total(&"move_speed", progress, attribute_defs, tree), 0.0, progress.config.max_move_speed_bonus)
	return (1.0 + bonus) * float(equipment(equipment_stats)[&"move_speed_mult"])


static func dodge_cost_mult(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree) -> float:
	return maxf(1.0 + effect_total(&"dodge_cost", progress, attribute_defs, tree), progress.config.min_dodge_cost_mult)


static func teleport_recharge_mult(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree) -> float:
	return maxf(1.0 + effect_total(&"teleport_recharge", progress, attribute_defs, tree), progress.config.min_recharge_mult)


static func heal_mult(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree) -> float:
	return 1.0 + maxf(effect_total(&"heal", progress, attribute_defs, tree), 0.0)


static func currency_mult(progress: PlayerProgress, attribute_defs: Array, tree: SkillTree) -> float:
	return 1.0 + maxf(effect_total(&"currency", progress, attribute_defs, tree), 0.0)


# --- XP ---------------------------------------------------------------------

## grunt / elite / heavy / boss, from the enemy's class and stats.
static func tier_of(enemy: Node) -> StringName:
	if enemy is Warden:
		return &"boss"
	var label := String(enemy.get("display_name")).to_lower() if "display_name" in enemy else ""
	if label.contains("elite") or label.contains("hunter"):
		return &"elite"
	if label.contains("heavy") or (("hit_points" in enemy) and float(enemy.get("hit_points")) >= 100.0):
		return &"heavy"
	return &"grunt"


## XP for one kill after both anti-grind factors: being over-levelled for the tier, and repeat kills
## of the same enemy name. Always at least 1 so a kill is never worth nothing.
static func kill_xp(config: ProgressionConfig, tier: StringName, player_level: int, previous_kills: int) -> int:
	var base := float(config.kill_xp.get(tier, 0))
	if base <= 0.0:
		return 0
	var over := maxi(player_level - int(config.recommended_level.get(tier, 1)), 0)
	var level_factor := maxf(1.0 - config.overlevel_falloff * over, config.min_kill_factor)
	var farm_factor := maxf(1.0 / (1.0 + float(previous_kills) / config.farm_halving), config.farm_floor)
	return maxi(roundi(base * level_factor * farm_factor), 1)
