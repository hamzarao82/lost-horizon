class_name ItemData
extends Resource
## Static item definition. Ownership and equipment state live in Inventory.

enum Kind { WEAPON, ARMOR, CONSUMABLE, ARMOR_PLATE, MATERIAL, QUEST, COLLECTIBLE, UPGRADE_COMPONENT }
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

# --- Milestone 6 additions (every field has a default so older .tres files load unchanged) ---
enum Category { WEAPON, ARMOR, CONSUMABLE, MATERIAL, QUEST, COLLECTIBLE, UPGRADE_COMPONENT }
enum Slot { NONE, PRIMARY_WEAPON, SECONDARY_WEAPON, HEAD, BODY, GLOVES, LEGS, ACCESSORY }

## Equipment slot names used in saves and UI.
const SLOT_NAMES: Array[String] = ["none", "primary_weapon", "secondary_weapon", "head", "body", "gloves", "legs", "accessory"]
const CATEGORY_NAMES: Array[String] = ["Weapon", "Armor", "Consumable", "Material", "Quest", "Collectible", "Upgrade"]
const ICON_DIR: String = "res://assets/icons/"

## NONE = derive from `kind` (weapons: primary, body armor: body).
@export var slot: Slot = Slot.NONE
## 0 = derive: equipment 1, everything else 99.
@export var max_stack: int = 0
## Equipment stats read by Inventory.stat_totals(): damage_mult, damage_reduction, max_health, move_speed_mult.
@export var base_stats: Dictionary = {}
@export var max_upgrade: int = 5
## Unique items (boss rewards, quest items) are claimed once per save and can never be dropped or sold.
@export var unique: bool = false
@export var quest_item: bool = false
## Currency value; vendors buy at value * rarity sell multiplier * vendor multiplier.
@export var value: int = 0
## Items that grant credits on pickup instead of occupying a slot.
@export var currency_amount: int = 0
## Consumables other than the medkit: "heal", "armor_restore", "buff", "teleport_charge". Empty = classic medkit.
@export var effect: String = ""
@export var effect_amount: float = 0.0
@export var buff_stat: String = ""
@export var buff_seconds: float = 0.0
@export var cooldown: float = 0.0
## Region tag for loot tables and merchants ("" = anywhere).
@export var region: String = ""
@export var icon_path: String = ""
## Non-equipment categories use Kind values appended below the original four.


func category() -> Category:
	match kind:
		Kind.WEAPON:
			return Category.WEAPON
		Kind.ARMOR:
			return Category.ARMOR
		Kind.CONSUMABLE, Kind.ARMOR_PLATE:
			return Category.CONSUMABLE
		Kind.MATERIAL:
			return Category.MATERIAL
		Kind.QUEST:
			return Category.QUEST
		Kind.COLLECTIBLE:
			return Category.COLLECTIBLE
		Kind.UPGRADE_COMPONENT:
			return Category.UPGRADE_COMPONENT
	return Category.MATERIAL


func is_equipment() -> bool:
	return kind == Kind.WEAPON or kind == Kind.ARMOR


func equip_slot() -> Slot:
	if slot != Slot.NONE:
		return slot
	if kind == Kind.WEAPON:
		return Slot.PRIMARY_WEAPON
	if kind == Kind.ARMOR:
		return Slot.BODY
	return Slot.NONE


func stack_limit() -> int:
	if max_stack > 0:
		return max_stack
	return 1 if is_equipment() else 99


## Quest and unique items cannot be dropped or sold.
func is_protected() -> bool:
	return unique or quest_item or kind == Kind.QUEST


func icon() -> Texture2D:
	var path := icon_path if icon_path != "" else ICON_DIR + String(item_id) + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


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
