class_name UpgradeService
extends RefCounted
## Equipment upgrading: stat curve per level, material + credit costs, preview and apply.
## Levels live in Inventory.upgrades (items are shared Resources and are never modified).
##
## Generic curve (per level, linear so the cap stays predictable):
##   primary weapon damage  +4% of its base multiplier
##   body armor points      +6% of its base points
##   other gear stats       +8% of each bonus (additive stats) / of the distance from 1.0 (multipliers)
## At the default cap of 5 levels that is at most +20% weapon damage and +30% armor points.
##
## Unique items use their own curve: a few small stat steps plus a distinct bonus each, so the
## Warden's Cleaver stays recognisable instead of being a bigger number.

const WEAPON_PER_LEVEL: float = 0.04
const ARMOR_PER_LEVEL: float = 0.06
const GEAR_PER_LEVEL: float = 0.08
const KIT_WEAPON: String = "upgrade_kit_weapon"
const KIT_ARMOR: String = "upgrade_kit_armor"
const BASE_CREDITS: int = 40

## Cumulative per-level deltas (index 0 = level 1). Keys are item_stats() keys.
## Warden's Cleaver: heavier hits early, then it swings faster, then it shrugs off a little damage,
## and the last level is a hit-or-miss executioner step. Total at level 5: damage +0.36 (about +15.6%,
## less than the generic +20%), attack speed +0.06, damage reduction +0.02.
const UNIQUE_CURVES: Dictionary = {
	"warden_blade": [
		{"damage_mult": 0.06},
		{"damage_mult": 0.06, "attack_speed": 0.03},
		{"damage_mult": 0.06, "damage_reduction": 0.02},
		{"damage_mult": 0.08},
		{"damage_mult": 0.10, "attack_speed": 0.03},
	],
}
## Extra materials a unique item needs per level (on top of the kit), multiplied by (level + 1).
const UNIQUE_EXTRA_MATERIALS: Dictionary = {
	"warden_blade": {"electronics": 2},
}


static func empty_stats() -> Dictionary:
	return {
		"damage_mult": 1.0, "attack_speed": 1.0, "armor_points": 0.0,
		"damage_reduction": 0.0, "max_health": 0.0, "move_speed_mult": 1.0,
	}


## Effective stats of an item at a given upgrade level.
static func stats_at(item: ItemData, level: int) -> Dictionary:
	var stats := empty_stats()
	var lvl := clampi(level, 0, item.max_upgrade)
	var is_primary_weapon := item.kind == ItemData.Kind.WEAPON and item.equip_slot() == ItemData.Slot.PRIMARY_WEAPON
	if is_primary_weapon:
		stats["damage_mult"] = item.damage_multiplier
		stats["attack_speed"] = item.attack_speed
	elif item.base_stats.has("damage_mult"):
		stats["damage_mult"] = float(item.base_stats["damage_mult"])
	if item.kind == ItemData.Kind.ARMOR:
		stats["armor_points"] = item.armor_points
	stats["damage_reduction"] = float(item.base_stats.get("damage_reduction", 0.0))
	stats["max_health"] = float(item.base_stats.get("max_health", 0.0))
	stats["move_speed_mult"] = float(item.base_stats.get("move_speed_mult", 1.0))
	if lvl == 0:
		return stats
	var id := String(item.item_id)
	if UNIQUE_CURVES.has(id):
		var curve: Array = UNIQUE_CURVES[id]
		for i in mini(lvl, curve.size()):
			for key in (curve[i] as Dictionary).keys():
				stats[key] = float(stats[key]) + float((curve[i] as Dictionary)[key])
		return stats
	if is_primary_weapon:
		stats["damage_mult"] = float(stats["damage_mult"]) * (1.0 + WEAPON_PER_LEVEL * lvl)
	if item.kind == ItemData.Kind.ARMOR:
		stats["armor_points"] = float(stats["armor_points"]) * (1.0 + ARMOR_PER_LEVEL * lvl)
	var gear := 1.0 + GEAR_PER_LEVEL * lvl
	stats["damage_reduction"] = float(stats["damage_reduction"]) * gear
	stats["max_health"] = float(stats["max_health"]) * gear
	stats["move_speed_mult"] = 1.0 + (float(stats["move_speed_mult"]) - 1.0) * gear
	if not is_primary_weapon:
		stats["damage_mult"] = 1.0 + (float(stats["damage_mult"]) - 1.0) * gear
	return stats


## {"materials": {id: count}, "currency": int} for going from `level` to `level + 1`.
static func cost(item: ItemData, level: int) -> Dictionary:
	var kit := KIT_WEAPON if item.kind == ItemData.Kind.WEAPON else KIT_ARMOR
	var steps := level + 1
	var materials: Dictionary = {kit: steps}
	var extra: Variant = UNIQUE_EXTRA_MATERIALS.get(String(item.item_id), {})
	for key in (extra as Dictionary).keys():
		materials[key] = int((extra as Dictionary)[key]) * steps
	var credits := roundi(BASE_CREDITS * steps * RarityTable.cost_multiplier(item.rarity))
	return {"materials": materials, "currency": credits}


## Everything the confirmation dialog needs, with no side effects.
static func preview(item: ItemData, inventory: Inventory) -> Dictionary:
	var from_level := inventory.level_of(item)
	var out := {
		"ok": false, "reason": "", "from": from_level, "to": from_level + 1,
		"before": stats_at(item, from_level), "after": stats_at(item, from_level + 1),
		"materials": {}, "currency": 0, "missing": {},
	}
	if not item.is_equipment():
		out["reason"] = "not_equipment"
		return out
	if not inventory.is_equipped(item) and inventory.count_of(String(item.item_id)) < 1:
		out["reason"] = "not_owned"
		return out
	if from_level >= item.max_upgrade:
		out["reason"] = "max_level"
		out["after"] = out["before"]
		out["to"] = from_level
		return out
	var price := cost(item, from_level)
	out["materials"] = price["materials"]
	out["currency"] = price["currency"]
	var missing: Dictionary = {}
	for id in (price["materials"] as Dictionary).keys():
		var short := int(price["materials"][id]) - inventory.count_of(String(id))
		if short > 0:
			missing[id] = short
	out["missing"] = missing
	if not missing.is_empty():
		out["reason"] = "missing_materials"
	elif inventory.currency < int(price["currency"]):
		out["reason"] = "not_enough_currency"
	else:
		out["ok"] = true
	return out


## Spends the preview's costs and raises the level. All-or-nothing.
static func upgrade(item: ItemData, inventory: Inventory) -> Dictionary:
	var plan := preview(item, inventory)
	if not plan["ok"]:
		return plan
	for id in (plan["materials"] as Dictionary).keys():
		inventory.remove(String(id), int(plan["materials"][id]))
	inventory.spend_currency(int(plan["currency"]))
	inventory.upgrades[String(item.item_id)] = int(plan["to"])
	inventory.refresh_gear()
	inventory.item_changed.emit(String(item.item_id))
	return plan
