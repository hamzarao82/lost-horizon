class_name ItemData
extends Resource
## Static item definition. Ownership and equipment state live in Inventory.

enum Kind { WEAPON, ARMOR, CONSUMABLE }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

const RARITY_COLORS: Array[Color] = [
	Color(0.85, 0.85, 0.85), Color(0.35, 0.85, 0.4), Color(0.3, 0.55, 1.0),
	Color(0.7, 0.35, 0.95), Color(1.0, 0.6, 0.15),
]

@export var item_id: StringName
@export var display_name: String
@export var kind: Kind = Kind.WEAPON
@export var rarity: Rarity = Rarity.COMMON
@export var damage_multiplier: float = 1.0
@export var damage_reduction: float = 0.0
@export var heal_amount: float = 0.0
@export_multiline var description: String


func color() -> Color:
	return RARITY_COLORS[rarity]


func power() -> float:
	match kind:
		Kind.WEAPON:
			return damage_multiplier
		Kind.ARMOR:
			return damage_reduction
	return 0.0


func summary() -> String:
	match kind:
		Kind.WEAPON:
			return "%s (x%.2f dmg)" % [display_name, damage_multiplier]
		Kind.ARMOR:
			return "%s (-%d%% dmg)" % [display_name, roundi(damage_reduction * 100.0)]
	return display_name
