class_name ItemData
extends Resource
## Static item definition. Ownership and equipment state live in Inventory.

enum Kind { WEAPON, ARMOR, CONSUMABLE, ARMOR_PLATE }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_COLORS: Array[Color] = [
	Color(0.85, 0.85, 0.85), Color(0.35, 0.85, 0.4), Color(0.3, 0.55, 1.0),
	Color(0.7, 0.35, 0.95), Color(1.0, 0.6, 0.15),
]

## Weapon power = damage_multiplier * attack_speed ^ SPEED_WEIGHT (speed counts half as much as damage).
const SPEED_WEIGHT: float = 0.5

@export var item_id: StringName
@export var display_name: String
@export var kind: Kind = Kind.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var damage_multiplier: float = 1.0
## Weapons: swing speed multiplier (1.0 = normal). Applied by the player via Inventory.attack_speed().
@export var attack_speed: float = 1.0
## Weapons: visual length multiplier of the model (the hitbox is owned by the player scene).
@export var reach: float = 1.0
## Armor: size of the armor bar this item grants. It absorbs damage before health does.
@export var armor_points: float = 0.0
## Kept for old saves/resources; armor no longer uses a percentage.
@export var damage_reduction: float = 0.0
@export var heal_amount: float = 0.0
## Armor plates: armor points restored when collected.
@export var armor_restore: float = 0.0
@export_multiline var description: String


func color() -> Color:
	return RARITY_COLORS[rarity]


## Comparable strength used by the "auto-equip only when better" rule.
func power() -> float:
	match kind:
		Kind.WEAPON:
			return damage_multiplier * pow(maxf(attack_speed, 0.1), SPEED_WEIGHT)
		Kind.ARMOR:
			return armor_points
	return 0.0


func summary() -> String:
	match kind:
		Kind.WEAPON:
			if is_equal_approx(attack_speed, 1.0):
				return "%s (x%.2f dmg)" % [display_name, damage_multiplier]
			return "%s (x%.2f dmg, %.2fx speed)" % [display_name, damage_multiplier, attack_speed]
		Kind.ARMOR:
			return "%s (%d armor)" % [display_name, roundi(armor_points)]
	return display_name
