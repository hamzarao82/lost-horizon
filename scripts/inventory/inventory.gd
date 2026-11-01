class_name Inventory
extends Node
## What the player owns and has equipped. Weapons and armor auto-equip only when better.

signal changed
signal item_collected(item: ItemData, kept: bool)

const STARTING_WEAPON: String = "res://resources/items/improvised_blade.tres"
const ITEM_DIR: String = "res://resources/items/"
const MAX_POTIONS: int = 99

var weapon: ItemData
var armor: ItemData
var potions: int = 0
var potion_heal: float = 40.0


func _ready() -> void:
	weapon = load(STARTING_WEAPON) as ItemData
	_restore_pending_state()


## Stable ids only; item definitions are never stored in the save.
func to_dict() -> Dictionary:
	return {
		"weapon": String(weapon.item_id) if weapon else "",
		"armor": String(armor.item_id) if armor else "",
		"potions": potions,
	}


## Unknown ids, wrong item kinds and out-of-range counts are ignored, never fatal.
func from_dict(data: Dictionary) -> void:
	var loaded_weapon := _item_by_id(str(data.get("weapon", "")), ItemData.Kind.WEAPON)
	if loaded_weapon:
		weapon = loaded_weapon
	armor = _item_by_id(str(data.get("armor", "")), ItemData.Kind.ARMOR)
	potions = clampi(int(data.get("potions", 0)), 0, MAX_POTIONS)
	changed.emit()


func _item_by_id(item_id: String, kind: ItemData.Kind) -> ItemData:
	if item_id.is_empty():
		return null
	for i in item_id.length():  # ids are file names under ITEM_DIR: lowercase letters, digits, underscore
		var c := item_id.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return null
	var path := ITEM_DIR + item_id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var item := load(path) as ItemData
	return item if item and item.kind == kind else null


## A queued Load (or the death checkpoint) is applied when the player's inventory is created.
func _restore_pending_state() -> void:
	if not is_inside_tree():
		return  # detached instances (unit tests) have no autoloads to ask
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null:
		return
	var data: Dictionary = save_manager.peek_restore()
	if data.is_empty():
		return
	from_dict(data.get("inventory", {}))
	var stats: Dictionary = data.get("player", {})
	var owner_health = get_parent().get("health") if get_parent() else null
	if owner_health is HealthComponent and stats.has("max_health"):
		var health_component := owner_health as HealthComponent
		health_component.max_health = float(stats["max_health"])
		health_component.health = clampf(float(stats.get("health", health_component.max_health)),
				1.0, health_component.max_health)
		health_component.changed.emit(health_component.health, health_component.max_health)


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
