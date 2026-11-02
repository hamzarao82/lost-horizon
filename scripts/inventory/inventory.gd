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
## The gear that was replaced last, kept only so the equipment screen can compare (not saved).
var previous_weapon: ItemData
var previous_armor: ItemData
var potions: int = 0
var potion_heal: float = 40.0


func _ready() -> void:
	weapon = load(STARTING_WEAPON) as ItemData
	_restore_pending_state()


## Stable ids only; item definitions are never stored in the save.
func to_dict() -> Dictionary:
	var health := _health()
	return {
		"weapon": String(weapon.item_id) if weapon else "",
		"armor": String(armor.item_id) if armor else "",
		"armor_points": health.armor if health and armor else -1.0,
		"potions": potions,
	}


## Unknown ids, wrong item kinds and out-of-range counts are ignored, never fatal.
func from_dict(data: Dictionary) -> void:
	var loaded_weapon := _item_by_id(str(data.get("weapon", "")), ItemData.Kind.WEAPON)
	if loaded_weapon:
		weapon = loaded_weapon
	armor = _item_by_id(str(data.get("armor", "")), ItemData.Kind.ARMOR)
	potions = clampi(int(data.get("potions", 0)), 0, MAX_POTIONS)
	# Saves written before armor became a bar have no points: restore the bar full.
	_sync_armor_pool(float(data.get("armor_points", -1.0)))
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


## Swing speed of the equipped weapon (1.0 = normal). The player scales its attack timings by this.
func attack_speed() -> float:
	return weapon.attack_speed if weapon else 1.0


## Armor is a bar now (see HealthComponent), not a percentage. Kept so older callers still work.
func damage_reduction() -> float:
	return 0.0


## The owner's HealthComponent holds the armor pool; null for a detached Inventory (unit tests).
func _health() -> HealthComponent:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get("health") as HealthComponent


## Size the armor bar to the equipped armor. `points` < 0 fills it; otherwise restores that amount.
func _sync_armor_pool(points: float) -> void:
	var health := _health()
	if health == null:
		return
	if armor == null:
		health.set_armor(0.0, 0.0)
	else:
		health.set_armor(armor.armor_points, points)


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
				previous_weapon = weapon
				weapon = item
				kept = true
		ItemData.Kind.ARMOR:
			if armor == null or item.power() > armor.power():
				previous_armor = armor
				armor = item
				kept = true
				_sync_armor_pool(-1.0)  # a better armor starts with a full bar
		ItemData.Kind.ARMOR_PLATE:
			# Used on pickup; left on the ground if the bar is already full (or there is no armor).
			var health := _health()
			if health:
				kept = health.restore_armor(item.armor_restore)
			else:
				kept = false
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
