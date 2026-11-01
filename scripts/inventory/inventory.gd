class_name Inventory
extends Node
## What the player owns and has equipped. Weapons and armor auto-equip only when better.

signal changed
signal item_collected(item: ItemData, kept: bool)

const STARTING_WEAPON: String = "res://resources/items/improvised_blade.tres"

var weapon: ItemData
var armor: ItemData
var potions: int = 0
var potion_heal: float = 40.0


func _ready() -> void:
	weapon = load(STARTING_WEAPON) as ItemData


func damage_multiplier() -> float:
	return weapon.damage_multiplier if weapon else 1.0


func damage_reduction() -> float:
	return armor.damage_reduction if armor else 0.0


## Returns true if the item was taken (and should disappear from the world).
func add_item(item: ItemData) -> bool:
	var kept := false
	match item.kind:
		ItemData.Kind.CONSUMABLE:
			potions += 1
			potion_heal = item.heal_amount
			kept = true
		ItemData.Kind.WEAPON:
			if weapon == null or item.power() > weapon.power():
				weapon = item
				kept = true
		ItemData.Kind.ARMOR:
			if armor == null or item.power() > armor.power():
				armor = item
				kept = true
	if kept:
		changed.emit()
	item_collected.emit(item, kept)
	return kept


func use_potion(health: HealthComponent) -> bool:
	if potions <= 0 or health.is_dead() or health.health >= health.max_health:
		return false
	potions -= 1
	health.heal(potion_heal)
	changed.emit()
	return true
