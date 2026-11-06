class_name Inventory
extends Node
## What the player owns and has equipped. Weapons and armor auto-equip only when better.
## Milestone 6 adds a stacked bag, extra equipment slots, currency, consumable effects, upgrade levels,
## unique-reward protection and merchant stock state. The original members (weapon, armor, potions,
## add_item, use_potion, the original to_dict/from_dict keys) behave as before.
##
## Damage pipeline note: damage_multiplier() == stat_totals().damage_mult. Use one of them, never both.

signal changed
signal item_collected(item: ItemData, kept: bool)
signal item_changed(item_id: String)
signal currency_changed(amount: int)

const STARTING_WEAPON: String = "res://resources/items/improvised_blade.tres"
const ITEM_DIR: String = "res://resources/items/"
const MAX_POTIONS: int = 99
const BAG_CAPACITY: int = 40
const MAX_CURRENCY: int = 999999
const SAVE_VERSION: int = 2
## Hard limits on equipment bonuses so stacking gear can never run away.
const MAX_DAMAGE_REDUCTION: float = 0.5
const MOVE_SPEED_MIN: float = 0.85
const MOVE_SPEED_MAX: float = 1.2
const SECONDARY_SLOTS: Array[int] = [
	ItemData.Slot.SECONDARY_WEAPON, ItemData.Slot.HEAD, ItemData.Slot.GLOVES,
	ItemData.Slot.LEGS, ItemData.Slot.ACCESSORY,
]

var weapon: ItemData
var armor: ItemData
## The gear that was replaced last, kept only so the equipment screen can compare (not saved).
var previous_weapon: ItemData
var previous_armor: ItemData
var potions: int = 0
var potion_heal: float = 40.0

## Bag stacks: [{"item": ItemData, "count": int}]. Capacity counts stacks.
var _stacks: Array[Dictionary] = []
## Extra equipment slots (Slot -> ItemData). Primary weapon and body armor stay in `weapon` / `armor`.
var _slots: Dictionary = {}
var currency: int = 0
## item_id -> upgrade level (items are shared Resources, so levels live here, never on the resource).
var upgrades: Dictionary = {}
## Unique rewards already received; reloading a save can never give them twice.
var unique_claimed: Dictionary = {}
## merchant_id -> {item_id: remaining stock}; only entries that have changed are stored.
var merchant_stock: Dictionary = {}
## Unknown or invalid item ids dropped by the last from_dict (for tests and warnings).
var invalid_ids_dropped: int = 0

var _cooldowns: Dictionary = {}
var _buffs: Array[Dictionary] = []


func _ready() -> void:
	weapon = load(STARTING_WEAPON) as ItemData
	_restore_pending_state()


func _process(delta: float) -> void:
	tick(delta)


## Stable ids only; item definitions are never stored in the save.
func to_dict() -> Dictionary:
	var health := _health()
	var bag: Array = []
	for stack in _stacks:
		bag.append({"id": String((stack["item"] as ItemData).item_id), "count": int(stack["count"])})
	var slot_ids: Dictionary = {}
	for slot in SECONDARY_SLOTS:
		var worn := _slots.get(slot) as ItemData
		if worn:
			slot_ids[ItemData.SLOT_NAMES[slot]] = String(worn.item_id)
	return {
		"weapon": String(weapon.item_id) if weapon else "",
		"armor": String(armor.item_id) if armor else "",
		"armor_points": health.armor if health and armor else -1.0,
		"potions": potions,
		"inv_version": SAVE_VERSION,
		"bag": bag,
		"slots": slot_ids,
		"currency": currency,
		"upgrades": upgrades.duplicate(),
		"unique_claimed": unique_claimed.keys(),
		"merchant_stock": merchant_stock.duplicate(true),
	}


## Unknown ids, wrong item kinds and out-of-range counts are ignored, never fatal.
## Old saves (no Milestone 6 keys) load with an empty bag, no currency and default upgrades.
func from_dict(data: Dictionary) -> void:
	invalid_ids_dropped = 0
	var loaded_weapon := _item_by_id(str(data.get("weapon", "")), ItemData.Kind.WEAPON)
	if loaded_weapon:
		weapon = loaded_weapon
	elif str(data.get("weapon", "")) != "":
		invalid_ids_dropped += 1
	armor = _item_by_id(str(data.get("armor", "")), ItemData.Kind.ARMOR)
	if armor and armor.equip_slot() != ItemData.Slot.BODY:
		armor = null
	potions = clampi(_whole(data.get("potions", 0)), 0, MAX_POTIONS)
	_load_extended(data)
	# Saves written before armor became a bar have no points: restore the bar full.
	_sync_armor_pool(_num(data.get("armor_points", -1.0)))
	changed.emit()


func _load_extended(data: Dictionary) -> void:
	_stacks.clear()
	_slots.clear()
	upgrades.clear()
	unique_claimed.clear()
	merchant_stock.clear()
	_cooldowns.clear()
	_buffs.clear()
	currency = clampi(_whole(data.get("currency", 0)), 0, MAX_CURRENCY)
	var slots_raw: Variant = data.get("slots", {})
	if slots_raw is Dictionary:
		for slot_name in (slots_raw as Dictionary).keys():
			var slot_index := ItemData.SLOT_NAMES.find(str(slot_name))
			var item := _item_by_id(str((slots_raw as Dictionary)[slot_name]), -1)
			if slot_index < 1 or item == null or not item.is_equipment() \
					or item.equip_slot() != slot_index or not SECONDARY_SLOTS.has(slot_index):
				invalid_ids_dropped += 1
				continue
			_slots[slot_index] = item
	var bag_raw: Variant = data.get("bag", [])
	if bag_raw is Array:
		for entry in bag_raw as Array:
			if not (entry is Dictionary):
				invalid_ids_dropped += 1
				continue
			var item := _item_by_id(str((entry as Dictionary).get("id", "")), -1)
			if item == null or _is_equipped(item) or _stacks.size() >= BAG_CAPACITY:
				invalid_ids_dropped += 1
				continue
			var count := clampi(_whole((entry as Dictionary).get("count", 1)), 1, item.stack_limit())
			_add_to_bag(item, count)
	var upgrades_raw: Variant = data.get("upgrades", {})
	if upgrades_raw is Dictionary:
		for key in (upgrades_raw as Dictionary).keys():
			var item := _item_by_id(str(key), -1)
			if item == null or not item.is_equipment():
				invalid_ids_dropped += 1
				continue
			upgrades[String(item.item_id)] = clampi(_whole((upgrades_raw as Dictionary)[key]), 0, item.max_upgrade)
	var claimed_raw: Variant = data.get("unique_claimed", [])
	if claimed_raw is Array:
		for id in claimed_raw as Array:
			if _valid_id(str(id)):
				unique_claimed[str(id)] = true
	var stock_raw: Variant = data.get("merchant_stock", {})
	if stock_raw is Dictionary:
		for merchant_id in (stock_raw as Dictionary).keys():
			var entry: Variant = (stock_raw as Dictionary)[merchant_id]
			if not _valid_id(str(merchant_id)) or not (entry is Dictionary):
				continue
			var clean: Dictionary = {}
			for item_id in (entry as Dictionary).keys():
				if _valid_id(str(item_id)):
					clean[str(item_id)] = clampi(_whole((entry as Dictionary)[item_id]), 0, 9999)
			merchant_stock[str(merchant_id)] = clean


## Validated copy of the Milestone 6 keys for the save layer (SaveManager may call this so unknown
## fields never reach the game): same shape as to_dict(), but types, lengths and ranges are enforced.
static func sanitize(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	out["currency"] = clampi(_whole(raw.get("currency", 0)), 0, MAX_CURRENCY)
	var bag: Array = []
	var bag_raw: Variant = raw.get("bag", [])
	if bag_raw is Array:
		for entry in bag_raw as Array:
			if entry is Dictionary and _valid_id(str((entry as Dictionary).get("id", ""))) and bag.size() < BAG_CAPACITY:
				bag.append({"id": str(entry["id"]), "count": clampi(_whole((entry as Dictionary).get("count", 1)), 1, 99)})
	out["bag"] = bag
	var slots: Dictionary = {}
	var slots_raw: Variant = raw.get("slots", {})
	if slots_raw is Dictionary:
		for key in (slots_raw as Dictionary).keys():
			if ItemData.SLOT_NAMES.has(str(key)) and _valid_id(str((slots_raw as Dictionary)[key])):
				slots[str(key)] = str((slots_raw as Dictionary)[key])
	out["slots"] = slots
	var upgrades_clean: Dictionary = {}
	var upgrades_raw: Variant = raw.get("upgrades", {})
	if upgrades_raw is Dictionary:
		for key in (upgrades_raw as Dictionary).keys():
			if _valid_id(str(key)):
				upgrades_clean[str(key)] = clampi(_whole((upgrades_raw as Dictionary)[key]), 0, 20)
	out["upgrades"] = upgrades_clean
	var claimed: Array = []
	var claimed_raw: Variant = raw.get("unique_claimed", [])
	if claimed_raw is Array:
		for id in claimed_raw as Array:
			if _valid_id(str(id)) and claimed.size() < 256:
				claimed.append(str(id))
	out["unique_claimed"] = claimed
	var stock_clean: Dictionary = {}
	var stock_raw: Variant = raw.get("merchant_stock", {})
	if stock_raw is Dictionary:
		for merchant_id in (stock_raw as Dictionary).keys():
			var entry: Variant = (stock_raw as Dictionary)[merchant_id]
			if _valid_id(str(merchant_id)) and entry is Dictionary:
				var inner: Dictionary = {}
				for item_id in (entry as Dictionary).keys():
					if _valid_id(str(item_id)):
						inner[str(item_id)] = clampi(_whole((entry as Dictionary)[item_id]), 0, 9999)
				stock_clean[str(merchant_id)] = inner
	out["merchant_stock"] = stock_clean
	return out


## Item ids are file names under ITEM_DIR: lowercase letters, digits, underscore.
static func _valid_id(item_id: String) -> bool:
	if item_id.is_empty() or item_id.length() > 64:
		return false
	for i in item_id.length():
		var c := item_id.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return false
	return true


## `kind` -1 accepts any item kind.
func _item_by_id(item_id: String, kind: int) -> ItemData:
	if not _valid_id(item_id):
		return null
	var path := ITEM_DIR + item_id + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var item := load(path) as ItemData
	if item == null:
		return null
	return item if kind < 0 or int(item.kind) == kind else null


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


## Effective damage multiplier: equipped weapon (with its upgrade level), worn gear and active buffs.
func damage_multiplier() -> float:
	return float(stat_totals()["damage_mult"])


## Swing speed of the equipped weapon (1.0 = normal), including its upgrade level.
func attack_speed() -> float:
	if weapon == null:
		return 1.0
	return float(UpgradeService.stats_at(weapon, level_of(weapon)).get("attack_speed", weapon.attack_speed))


## Armor is a bar now (see HealthComponent), not a percentage. Kept so older callers still work;
## percentage-style reduction from gear is reported by stat_totals().damage_reduction.
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
		health.set_armor(UpgradeService.stats_at(armor, level_of(armor)).get("armor_points", armor.armor_points), points)


## Re-sizes the armor bar after an upgrade or equip change, keeping the points the player has left.
func refresh_gear() -> void:
	var health := _health()
	_sync_armor_pool(health.armor if health and armor else -1.0)
	changed.emit()


## Returns true if the item was taken (and should disappear from the world).
func add_item(item: ItemData) -> bool:
	var kept := false
	if item.unique and unique_claimed.has(String(item.item_id)):
		item_collected.emit(item, false)
		return false
	if item.currency_amount > 0:
		add_currency(item.currency_amount)
		item_collected.emit(item, true)
		return true
	match item.kind:
		ItemData.Kind.CONSUMABLE:
			if item.effect == "":
				potions += 1
				potion_heal = item.heal_amount
				kept = true
			else:
				kept = collect(item, 1)["added"] > 0
		ItemData.Kind.WEAPON:
			kept = _pickup_weapon(item)
		ItemData.Kind.ARMOR:
			kept = _pickup_armor(item)
		ItemData.Kind.ARMOR_PLATE:
			# Used on pickup; left on the ground if the bar is already full (or there is no armor).
			var health := _health()
			if health:
				kept = health.restore_armor(item.armor_restore)
			else:
				kept = false
		_:
			kept = collect(item, 1)["added"] > 0
	if kept:
		if item.unique:
			unique_claimed[String(item.item_id)] = true
		changed.emit()
	item_collected.emit(item, kept)
	return kept


func _pickup_weapon(item: ItemData) -> bool:
	if item.equip_slot() != ItemData.Slot.PRIMARY_WEAPON:
		return _pickup_slot_gear(item)
	if weapon == null or _power(item) > _power(weapon):
		previous_weapon = weapon
		if weapon:
			_add_to_bag_if_room(weapon)
		weapon = item
		return true
	return false


func _pickup_armor(item: ItemData) -> bool:
	if item.equip_slot() != ItemData.Slot.BODY:
		return _pickup_slot_gear(item)
	if armor == null or _power(item) > _power(armor):
		previous_armor = armor
		if armor:
			_add_to_bag_if_room(armor)
		armor = item
		_sync_armor_pool(-1.0)  # a better armor starts with a full bar
		return true
	return false


## Gloves, boots, helmets, accessories and secondary weapons: auto-equip only into an empty slot or
## when clearly better; the replaced piece goes to the bag.
func _pickup_slot_gear(item: ItemData) -> bool:
	var slot := item.equip_slot()
	if slot == ItemData.Slot.NONE or not SECONDARY_SLOTS.has(slot):
		return false
	var current := _slots.get(slot) as ItemData
	if current == null or _power(item) > _power(current):
		if current:
			_add_to_bag_if_room(current)
		_slots[slot] = item
		return true
	return false


## Comparable strength of any equipment piece (upgrade level included).
func _power(item: ItemData) -> float:
	if item.kind == ItemData.Kind.WEAPON and item.equip_slot() == ItemData.Slot.PRIMARY_WEAPON:
		var stats := UpgradeService.stats_at(item, level_of(item))
		return float(stats["damage_mult"]) * pow(maxf(float(stats["attack_speed"]), 0.1), ItemData.SPEED_WEIGHT)
	if item.kind == ItemData.Kind.ARMOR and item.equip_slot() == ItemData.Slot.BODY:
		return float(UpgradeService.stats_at(item, level_of(item))["armor_points"])
	var s := UpgradeService.stats_at(item, level_of(item))
	return (float(s["damage_mult"]) - 1.0) * 5.0 + float(s["damage_reduction"]) * 5.0 \
			+ float(s["max_health"]) * 0.05 + (float(s["move_speed_mult"]) - 1.0) * 3.0 + 0.001


func use_potion(health: HealthComponent) -> bool:
	if potions <= 0 or health.is_dead() or health.health >= health.max_health:
		return false
	potions -= 1
	health.heal(potion_heal * _heal_scale())
	changed.emit()
	return true


# ---------------------------------------------------------------------------------------------
# Bag
# ---------------------------------------------------------------------------------------------

func level_of(item: ItemData) -> int:
	return int(upgrades.get(String(item.item_id), 0))


## How many of an item the player holds in the bag (medkits count their own pool).
func count_of(item_id: String) -> int:
	if item_id == "health_potion":
		return potions
	var total := 0
	for stack in _stacks:
		if String((stack["item"] as ItemData).item_id) == item_id:
			total += int(stack["count"])
	return total


func has_item(item_id: String, quantity: int = 1) -> bool:
	return count_of(item_id) >= quantity


func stack_count() -> int:
	return _stacks.size()


## [{"item": ItemData, "count": int}] copies, optionally filtered by ItemData.Category (-1 = all).
func stacks(category: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stack in _stacks:
		if category < 0 or int((stack["item"] as ItemData).category()) == category:
			out.append({"item": stack["item"], "count": stack["count"]})
	return out


## Category, then rarity (best first), then name. Changes only the order, never the contents.
func sort_bag() -> void:
	_stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia := a["item"] as ItemData
		var ib := b["item"] as ItemData
		if ia.category() != ib.category():
			return ia.category() < ib.category()
		if ia.rarity != ib.rarity:
			return ia.rarity > ib.rarity
		return ia.display_name < ib.display_name)
	changed.emit()


## Room for `quantity` more of this item (stack merge + free stacks).
func can_fit(item: ItemData, quantity: int = 1) -> bool:
	if item.currency_amount > 0:
		return true
	if item.kind == ItemData.Kind.CONSUMABLE and item.effect == "":
		return potions + quantity <= MAX_POTIONS
	var limit := item.stack_limit()
	var free := 0
	var slots_left := BAG_CAPACITY - _stacks.size()
	for stack in _stacks:
		if (stack["item"] as ItemData).item_id == item.item_id:
			free += limit - int(stack["count"])
	free += slots_left * limit
	return free >= quantity


## Adds to the bag with stacking. Returns {"added": int, "overflow": int}. Currency items add credits;
## medkits add to the medkit pool; claimed unique items are refused.
func collect(item: ItemData, quantity: int = 1) -> Dictionary:
	quantity = maxi(quantity, 0)
	if quantity == 0:
		return {"added": 0, "overflow": 0}
	if item.currency_amount > 0:
		add_currency(item.currency_amount * quantity)
		return {"added": quantity, "overflow": 0}
	if item.unique and unique_claimed.has(String(item.item_id)):
		return {"added": 0, "overflow": quantity}
	if item.kind == ItemData.Kind.CONSUMABLE and item.effect == "":
		var room := MAX_POTIONS - potions
		var taken := mini(room, quantity)
		if taken > 0:
			potions += taken
			potion_heal = item.heal_amount
			changed.emit()
			item_changed.emit("health_potion")
		return {"added": taken, "overflow": quantity - taken}
	if item.is_equipment() and (_is_equipped(item) or count_of(String(item.item_id)) > 0):
		return {"added": 0, "overflow": quantity}  # one copy of any equipment piece at a time
	var added := 0
	var remaining := quantity
	while remaining > 0:
		var put := _add_to_bag(item, remaining)
		if put == 0:
			break
		added += put
		remaining -= put
	if added > 0:
		if item.unique:
			unique_claimed[String(item.item_id)] = true
		changed.emit()
		item_changed.emit(String(item.item_id))
	return {"added": added, "overflow": quantity - added}


## Puts up to `quantity` into existing stacks, then a new stack. Returns how many went in.
func _add_to_bag(item: ItemData, quantity: int) -> int:
	var limit := item.stack_limit()
	for stack in _stacks:
		if (stack["item"] as ItemData).item_id == item.item_id and int(stack["count"]) < limit:
			var put := mini(limit - int(stack["count"]), quantity)
			stack["count"] = int(stack["count"]) + put
			return put
	if _stacks.size() >= BAG_CAPACITY:
		return 0
	var first := mini(limit, quantity)
	_stacks.append({"item": item, "count": first})
	return first


func _add_to_bag_if_room(item: ItemData) -> void:
	if not (count_of(String(item.item_id)) > 0):
		_add_to_bag(item, 1)


## All-or-nothing removal; false (and no change) if the bag does not hold enough.
func remove(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		return false
	if item_id == "health_potion":
		if potions < quantity:
			return false
		potions -= quantity
		changed.emit()
		item_changed.emit(item_id)
		return true
	if count_of(item_id) < quantity:
		return false
	var left := quantity
	for i in range(_stacks.size() - 1, -1, -1):
		var stack: Dictionary = _stacks[i]
		if String((stack["item"] as ItemData).item_id) != item_id:
			continue
		var take := mini(int(stack["count"]), left)
		stack["count"] = int(stack["count"]) - take
		left -= take
		if int(stack["count"]) <= 0:
			_stacks.remove_at(i)
		if left == 0:
			break
	changed.emit()
	item_changed.emit(item_id)
	return true


## Drops items out of the bag. Quest and unique items are protected. The caller spawns the Pickup.
func drop(item_id: String, quantity: int = 1) -> Dictionary:
	var item := bag_item(item_id)
	if item == null:
		return {"ok": false, "reason": "not_owned", "item": null}
	if item.is_protected():
		return {"ok": false, "reason": "protected", "item": item}
	if not remove(item_id, quantity):
		return {"ok": false, "reason": "not_enough", "item": item}
	return {"ok": true, "reason": "", "item": item}


func bag_item(item_id: String) -> ItemData:
	for stack in _stacks:
		if String((stack["item"] as ItemData).item_id) == item_id:
			return stack["item"] as ItemData
	return null


# ---------------------------------------------------------------------------------------------
# Currency, unique rewards
# ---------------------------------------------------------------------------------------------

func add_currency(amount: int) -> void:
	if amount <= 0:
		return
	currency = mini(currency + amount, MAX_CURRENCY)
	currency_changed.emit(currency)
	changed.emit()


## False (and no change) if the player cannot afford it.
func spend_currency(amount: int) -> bool:
	if amount < 0 or amount > currency:
		return false
	if amount == 0:
		return true
	currency -= amount
	currency_changed.emit(currency)
	changed.emit()
	return true


func is_unique_claimed(item_id: String) -> bool:
	return unique_claimed.has(item_id)


# ---------------------------------------------------------------------------------------------
# Equipment
# ---------------------------------------------------------------------------------------------

func equipped(slot: int) -> ItemData:
	match slot:
		ItemData.Slot.PRIMARY_WEAPON:
			return weapon
		ItemData.Slot.BODY:
			return armor
	return _slots.get(slot) as ItemData


func _is_equipped(item: ItemData) -> bool:
	if item == weapon or item == armor:
		return item != null
	for worn in _slots.values():
		if worn == item:
			return true
	return false


func is_equipped(item: ItemData) -> bool:
	return _is_equipped(item)


## Equips a piece that is in the bag. The replaced piece returns to the bag. {"ok", "reason", "replaced"}.
func equip(item: ItemData) -> Dictionary:
	if item == null or not item.is_equipment():
		return {"ok": false, "reason": "not_equipment", "replaced": null}
	var slot := item.equip_slot()
	if slot == ItemData.Slot.NONE:
		return {"ok": false, "reason": "no_slot", "replaced": null}
	if _is_equipped(item):
		return {"ok": false, "reason": "already_equipped", "replaced": null}
	if count_of(String(item.item_id)) < 1:
		return {"ok": false, "reason": "not_in_bag", "replaced": null}
	remove(String(item.item_id), 1)
	var replaced := equipped(slot)
	if slot == ItemData.Slot.PRIMARY_WEAPON:
		previous_weapon = weapon
		weapon = item
	elif slot == ItemData.Slot.BODY:
		previous_armor = armor
		armor = item
	else:
		_slots[slot] = item
	if replaced:
		_add_to_bag(replaced, 1)  # the removed stack freed a slot, so this cannot overflow
	if slot == ItemData.Slot.BODY:
		_sync_armor_pool(-1.0)
	changed.emit()
	item_changed.emit(String(item.item_id))
	return {"ok": true, "reason": "", "replaced": replaced}


## Moves a worn piece back to the bag. The primary weapon cannot be taken off (it would leave the player
## unarmed); equip another weapon to replace it.
func unequip(slot: int) -> Dictionary:
	if slot == ItemData.Slot.PRIMARY_WEAPON:
		return {"ok": false, "reason": "weapon_required"}
	var worn := equipped(slot)
	if worn == null:
		return {"ok": false, "reason": "empty"}
	if _stacks.size() >= BAG_CAPACITY and count_of(String(worn.item_id)) == 0:
		return {"ok": false, "reason": "bag_full"}
	if slot == ItemData.Slot.BODY:
		previous_armor = armor
		armor = null
		_sync_armor_pool(0.0)
	else:
		_slots.erase(slot)
	_add_to_bag(worn, 1)
	changed.emit()
	item_changed.emit(String(worn.item_id))
	return {"ok": true, "reason": ""}


## Effective stats of one piece (upgrade level applied).
func item_stats(item: ItemData) -> Dictionary:
	return UpgradeService.stats_at(item, level_of(item))


## b - a for every stat: positive means `b` is better. Keys match item_stats().
func compare(a: ItemData, b: ItemData) -> Dictionary:
	var sa := item_stats(a) if a else UpgradeService.empty_stats()
	var sb := item_stats(b) if b else UpgradeService.empty_stats()
	var out: Dictionary = {}
	for key in sb.keys():
		out[key] = float(sb[key]) - float(sa.get(key, 0.0))
	return out


## The numbers the damage pipeline reads. Exactly these four keys.
func stat_totals() -> Dictionary:
	var damage_mult := 1.0
	var reduction := 0.0
	var health_bonus := 0.0
	var move_mult := 1.0
	if weapon:
		damage_mult *= float(item_stats(weapon)["damage_mult"])
		reduction += float(item_stats(weapon)["damage_reduction"])
	if armor:
		var armor_stats := item_stats(armor)
		reduction += float(armor_stats["damage_reduction"])
		health_bonus += float(armor_stats["max_health"])
		move_mult *= float(armor_stats["move_speed_mult"])
	for slot in SECONDARY_SLOTS:
		var worn := _slots.get(slot) as ItemData
		if worn == null:
			continue
		var s := item_stats(worn)
		damage_mult *= float(s["damage_mult"])
		reduction += float(s["damage_reduction"])
		health_bonus += float(s["max_health"])
		move_mult *= float(s["move_speed_mult"])
	for buff in _buffs:
		match String(buff["stat"]):
			"damage_mult":
				damage_mult *= 1.0 + float(buff["amount"])
			"move_speed_mult":
				move_mult *= 1.0 + float(buff["amount"])
			"damage_reduction":
				reduction += float(buff["amount"])
	return {
		"damage_mult": damage_mult,
		"damage_reduction": clampf(reduction, 0.0, MAX_DAMAGE_REDUCTION),
		"max_health_bonus": health_bonus,
		"move_speed_mult": clampf(move_mult, MOVE_SPEED_MIN, MOVE_SPEED_MAX),
	}


# ---------------------------------------------------------------------------------------------
# Consumables and timers
# ---------------------------------------------------------------------------------------------

## Uses a bag consumable (or the medkit with id "health_potion"). {"ok": bool, "reason": String}.
## Healing goes through HealthComponent.heal exactly like the medkit, so there is one healing path.
func use_item(item_id: String, health: HealthComponent = null) -> Dictionary:
	if health == null:
		health = _health()
	if item_id == "health_potion":
		if health == null:
			return {"ok": false, "reason": "no_target"}
		var used := use_potion(health)
		return {"ok": used, "reason": "" if used else "unavailable"}
	var item := bag_item(item_id)
	if item == null:
		return {"ok": false, "reason": "not_owned"}
	if item.kind != ItemData.Kind.CONSUMABLE or item.effect == "":
		return {"ok": false, "reason": "not_usable"}
	if float(_cooldowns.get(item_id, 0.0)) > 0.0:
		return {"ok": false, "reason": "cooldown"}
	if health != null and health.is_dead():
		return {"ok": false, "reason": "dead"}
	match item.effect:
		"heal":
			if health == null:
				return {"ok": false, "reason": "no_target"}
			if health.health >= health.max_health:
				return {"ok": false, "reason": "full_health"}
			health.heal(item.effect_amount)
		"armor_restore":
			if health == null:
				return {"ok": false, "reason": "no_target"}
			if not health.restore_armor(item.effect_amount):
				return {"ok": false, "reason": "armor_full"}
		"buff":
			_apply_buff(item)
		"teleport_charge":
			var teleport := get_node_or_null("/root/Teleport") if is_inside_tree() else null
			if teleport == null or int(teleport.get("charges")) >= int(teleport.get("MAX_CHARGES")):
				return {"ok": false, "reason": "no_effect"}
			teleport.set("charges", int(teleport.get("charges")) + 1)
			teleport.emit_signal("charges_changed", int(teleport.get("charges")), int(teleport.get("MAX_CHARGES")))
		_:
			return {"ok": false, "reason": "unknown_effect"}
	remove(item_id, 1)
	if item.cooldown > 0.0:
		_cooldowns[item_id] = item.cooldown
	return {"ok": true, "reason": ""}


func _apply_buff(item: ItemData) -> void:
	for buff in _buffs:
		if String(buff["id"]) == String(item.item_id):
			buff["remaining"] = item.buff_seconds  # re-using refreshes, never stacks
			return
	_buffs.append({"id": String(item.item_id), "stat": item.buff_stat, "amount": item.effect_amount,
			"remaining": item.buff_seconds})


func cooldown_left(item_id: String) -> float:
	return float(_cooldowns.get(item_id, 0.0))


func active_buffs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for buff in _buffs:
		out.append(buff.duplicate())
	return out


## Advances cooldowns and buffs (called every frame from _process; tests call it directly).
func tick(delta: float) -> void:
	for key in _cooldowns.keys():
		_cooldowns[key] = maxf(float(_cooldowns[key]) - delta, 0.0)
		if float(_cooldowns[key]) <= 0.0:
			_cooldowns.erase(key)
	for i in range(_buffs.size() - 1, -1, -1):
		_buffs[i]["remaining"] = float(_buffs[i]["remaining"]) - delta
		if float(_buffs[i]["remaining"]) <= 0.0:
			_buffs.remove_at(i)


## Field Medic skill: 1.0 unless the Progression autoload says otherwise (detached inventories in tests too).
func _heal_scale() -> float:
	if not is_inside_tree():
		return 1.0
	var progression := get_node_or_null("/root/Progression")
	if progression != null and progression.has_method("heal_multiplier"):
		return float(progression.heal_multiplier())
	return 1.0


# --- safe conversions for untrusted save data -------------------------------
# int()/float() throw on Dictionary and Array values; saved numbers come through these instead.

static func _num(value: Variant, fallback: float = 0.0) -> float:
	if (value is float and is_finite(value)) or value is int:
		return float(value)
	if value is String and (value as String).is_valid_float():
		return float(value)
	return fallback


static func _whole(value: Variant, fallback: int = 0) -> int:
	return int(clampf(_num(value, float(fallback)), -2147483648.0, 2147483647.0))
