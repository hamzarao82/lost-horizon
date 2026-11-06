class_name PlayerProgress
extends RefCounted
## Pure progression state: XP, spendable points, attribute points, skill ranks and currency.
## No scene or autoload access, so it is trivially testable and serialisable.

const MAX_CURRENCY: int = 999999
const MAX_LIST: int = 512

var config: ProgressionConfig
var xp: int = 0
var attribute_points: int = 0  # unspent
var skill_points: int = 0  # unspent
var attributes: Dictionary = {}  # id -> points spent (above base)
var skills: Dictionary = {}  # id -> rank
var currency: int = 0
var rewarded_quests: Array[String] = []
var discoveries: Array[String] = []
var kill_counts: Dictionary = {}  # enemy name -> kills (anti-grind)


func _init(new_config: ProgressionConfig = null) -> void:
	config = new_config if new_config else ProgressionConfig.new()


func level() -> int:
	return config.level_for_xp(xp)


## Adds XP, grants the points of every level crossed and returns the number of levels gained.
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := level()
	xp = mini(xp + amount, config.xp_for_level(config.max_level()))
	var gained := level() - before
	attribute_points += gained * config.attribute_points_per_level
	skill_points += gained * config.skill_points_per_level
	return gained


func xp_into_level() -> int:
	return xp - config.xp_for_level(level())


func xp_needed_for_next() -> int:
	var lv := level()
	return 0 if lv >= config.max_level() else config.xp_to_next[lv - 1]


func attribute_value(id: StringName, data: AttributeData) -> int:
	return data.base + int(attributes.get(id, 0))


func skill_rank(id: StringName) -> int:
	return int(skills.get(id, 0))


func to_dict() -> Dictionary:
	return {
		"xp": xp, "attribute_points": attribute_points, "skill_points": skill_points,
		"attributes": attributes.duplicate(), "skills": skills.duplicate(), "currency": currency,
		"rewarded_quests": rewarded_quests.duplicate(), "discoveries": discoveries.duplicate(),
		"kills": kill_counts.duplicate(),
	}


## Loads untrusted data: unknown ids are dropped, numbers are clamped, and spent points are
## re-validated against what the level could ever have granted, so an edited save cannot exceed it.
func from_dict(raw: Variant, attribute_defs: Array, skill_defs: Array) -> void:
	xp = 0
	attribute_points = 0
	skill_points = 0
	attributes = {}
	skills = {}
	currency = 0
	rewarded_quests = []
	discoveries = []
	kill_counts = {}
	if not raw is Dictionary:
		return
	xp = clampi(_int(raw.get("xp"), 0), 0, config.xp_for_level(config.max_level()))
	currency = clampi(_int(raw.get("currency"), 0), 0, MAX_CURRENCY)
	var lv := level()
	var earned_attr := (lv - 1) * config.attribute_points_per_level
	var earned_skill := (lv - 1) * config.skill_points_per_level
	var spent_attr := 0
	var raw_attrs: Variant = raw.get("attributes")
	if raw_attrs is Dictionary:
		for def in attribute_defs:
			var points := clampi(_int(_lookup(raw_attrs, def.id), 0), 0, def.max_points - def.base)
			points = mini(points, earned_attr - spent_attr)
			if points > 0:
				attributes[def.id] = points
				spent_attr += points
	var spent_skill := 0
	var raw_skills: Variant = raw.get("skills")
	if raw_skills is Dictionary:
		for def in skill_defs:
			var rank := clampi(_int(_lookup(raw_skills, def.id), 0), 0, def.max_rank)
			while rank > 0 and spent_skill + rank * def.cost > earned_skill:
				rank -= 1
			if rank > 0:
				skills[def.id] = rank
				spent_skill += rank * def.cost
	attribute_points = clampi(_int(raw.get("attribute_points"), 0), 0, earned_attr - spent_attr)
	skill_points = clampi(_int(raw.get("skill_points"), 0), 0, earned_skill - spent_skill)
	rewarded_quests = _strings(raw.get("rewarded_quests"))
	discoveries = _strings(raw.get("discoveries"))
	var raw_kills: Variant = raw.get("kills")
	if raw_kills is Dictionary:
		for key in raw_kills:
			if kill_counts.size() < MAX_LIST:
				kill_counts[String(key).left(48)] = clampi(_int(raw_kills[key], 0), 0, 100000)


## JSON round trips turn StringName keys into Strings, so look up either form.
static func _lookup(dict: Dictionary, id: StringName) -> Variant:
	if dict.has(id):
		return dict[id]
	return dict.get(String(id))


static func _int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float and is_finite(value):
		return int(value)
	return fallback


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for item in value:
			if (item is String or item is StringName) and out.size() < MAX_LIST and not out.has(String(item)):
				out.append(String(item).left(64))
	return out
