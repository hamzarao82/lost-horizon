class_name RarityTable
extends RefCounted
## Rarity tuning in one place. Stat ranges are deliberately narrow so rarity never doubles power:
## a legendary item is at most about 20% stronger than a common item of the same kind.

const NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
## Allowed stat multiplier range per rarity (checked by tests against every shipped item).
const STAT_MIN: Array[float] = [1.00, 1.00, 1.03, 1.08, 1.12]
const STAT_MAX: Array[float] = [1.00, 1.05, 1.10, 1.15, 1.20]
## Multiplier on an item's value when a vendor pays the player.
const SELL_MULT: Array[float] = [0.4, 0.5, 0.6, 0.75, 1.0]
## Default relative drop weights; loot tables may override with their own multipliers.
const DROP_WEIGHT: Array[float] = [60.0, 25.0, 10.0, 4.0, 1.0]
## Upgrade cost multiplier.
const COST_MULT: Array[float] = [1.0, 1.2, 1.5, 2.0, 3.0]


static func color(rarity: int) -> Color:
	return ItemData.RARITY_COLORS[clampi(rarity, 0, 4)]


static func rarity_name(rarity: int) -> String:
	return NAMES[clampi(rarity, 0, 4)]


static func sell_multiplier(rarity: int) -> float:
	return SELL_MULT[clampi(rarity, 0, 4)]


static func drop_weight(rarity: int) -> float:
	return DROP_WEIGHT[clampi(rarity, 0, 4)]


static func cost_multiplier(rarity: int) -> float:
	return COST_MULT[clampi(rarity, 0, 4)]


static func stat_range(rarity: int) -> Vector2:
	var r := clampi(rarity, 0, 4)
	return Vector2(STAT_MIN[r], STAT_MAX[r])
