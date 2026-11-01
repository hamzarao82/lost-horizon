extends SceneTree
## Weapon roster, auto-equip rule, armor bar, armor plates, save round trip, weapon models.
##   godot --headless --path . -s tests/equipment_check.gd

const ITEMS: String = "res://resources/items/"
const WEAPONS: Array[String] = [
	"improvised_blade", "combat_knife", "iron_sword", "military_machete",
	"katana", "tactical_sword", "claymore", "warden_blade",
]
const ARMORS: Array[String] = ["light_tactical_armor", "reinforced_armor", "heavy_combat_armor", "warden_plate"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _item(id: String) -> ItemData:
	return load(ITEMS + id + ".tres") as ItemData


func _run() -> void:
	_test_roster()
	_test_auto_equip()
	_test_armor_pool()
	await _test_in_game()
	await _test_weapon_models()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_roster() -> void:
	print("Roster")
	var all_ok := true
	var ids := {}
	for id in WEAPONS:
		var item := _item(id)
		ids[id] = true
		all_ok = all_ok and item != null and item.kind == ItemData.Kind.WEAPON and item.item_id == StringName(id) \
				and item.damage_multiplier >= 1.0 and item.attack_speed > 0.5 and item.attack_speed < 2.0 and item.reach > 0.0
	_check(all_ok, "all %d weapons load and have sane stats" % WEAPONS.size())
	_check(is_equal_approx(_item("claymore").attack_speed, 0.85) and _item("katana").attack_speed > 1.0,
			"claymore is slow, katana is fast")
	_check(_item("combat_knife").attack_speed > 1.0 and _item("iron_sword").rarity == ItemData.Rarity.UNCOMMON,
			"knife is fast, iron sword is uncommon")
	_check(_item("warden_blade").rarity == ItemData.Rarity.LEGENDARY and _item("claymore").rarity == ItemData.Rarity.EPIC,
			"rarities: cleaver legendary, claymore epic")
	var armor_ok := true
	for id in ARMORS:
		var item := _item(id)
		armor_ok = armor_ok and item != null and item.kind == ItemData.Kind.ARMOR and item.armor_points > 0.0 \
				and is_zero_approx(item.damage_reduction)
	_check(armor_ok, "armors have armor points and no percentage reduction")
	_check(_item("light_tactical_armor").armor_points == 30.0 and _item("reinforced_armor").armor_points == 60.0
			and _item("heavy_combat_armor").armor_points == 100.0 and _item("warden_plate").armor_points == 140.0,
			"armor table: 30 / 60 / 100 / 140")
	var plate := _item("armor_plate")
	_check(plate != null and plate.kind == ItemData.Kind.ARMOR_PLATE and plate.armor_restore == 40.0, "armor plate restores 40")
	# Every loot table entry exists, and the new swords are reachable
	var found := {}
	for table_name in ["soldier_loot", "hunter_loot", "heavy_loot", "warden_loot"]:
		var table := load("res://resources/loot/%s.tres" % table_name) as LootTable
		var paths_ok := table.item_paths.size() == table.weights.size()
		for path in table.item_paths:
			paths_ok = paths_ok and load(path) is ItemData
			found[path.get_file().get_basename()] = true
		_check(paths_ok, "%s paths load and weights line up" % table_name)
	_check(found.has("katana") and found.has("claymore") and found.has("iron_sword") and found.has("armor_plate"),
			"new swords and plates appear in loot tables")


func _test_auto_equip() -> void:
	print("Auto-equip rule")
	_check(is_equal_approx(_item("claymore").power(), 2.1 * sqrt(0.85)), "weapon power = damage x speed^0.5")
	_check(is_equal_approx(_item("reinforced_armor").power(), 60.0), "armor power = armor points")
	var inv := Inventory.new()
	inv._ready()
	_check(is_equal_approx(inv.attack_speed(), 1.0), "starting blade attacks at normal speed")
	_check(inv.add_item(_item("iron_sword")) and inv.weapon.item_id == &"iron_sword", "iron sword beats the scrap blade")
	_check(not inv.add_item(_item("combat_knife")), "knife (x1.25, fast) is not better than the iron sword")
	_check(inv.add_item(_item("military_machete")) and inv.add_item(_item("katana")), "machete then katana are upgrades")
	_check(is_equal_approx(inv.attack_speed(), 1.1), "attack_speed() follows the equipped katana")
	_check(inv.add_item(_item("tactical_sword")) and not inv.add_item(_item("katana")), "tactical sword replaces katana, katana is then rejected")
	_check(inv.add_item(_item("claymore")) and is_equal_approx(inv.attack_speed(), 0.85), "claymore (slow but strong) beats the tactical sword")
	_check(is_equal_approx(inv.damage_multiplier(), 2.1), "damage multiplier follows the claymore")
	_check(inv.add_item(_item("warden_blade")) and inv.weapon.item_id == &"warden_blade", "Warden's Cleaver tops the roster")
	_check(not inv.add_item(_item("claymore")), "a worse weapon stays on the ground")
	inv.free()


func _test_armor_pool() -> void:
	print("Armor pool")
	var health := HealthComponent.new()
	health.max_health = 100.0
	health._ready()
	var armor_events := [0]
	var damage_events: Array[float] = []
	var died := [false]
	health.armor_changed.connect(func(_c: float, _m: float) -> void: armor_events[0] += 1)
	health.damaged.connect(func(amount: float) -> void: damage_events.append(amount))
	health.died.connect(func() -> void: died[0] = true)

	_check(health.armor == 0.0 and health.max_armor == 0.0, "no armor by default")
	health.take_damage(10.0)
	_check(is_equal_approx(health.health, 90.0), "without armor, damage goes straight to health")
	health.heal(10.0)
	health.set_armor(60.0)
	_check(is_equal_approx(health.armor, 60.0) and is_equal_approx(health.max_armor, 60.0), "set_armor fills the bar by default")
	health.take_damage(25.0)
	_check(is_equal_approx(health.armor, 35.0) and is_equal_approx(health.health, 100.0), "armor absorbs damage completely while it lasts")
	health.take_damage(50.0)
	_check(is_equal_approx(health.armor, 0.0) and is_equal_approx(health.health, 85.0), "overflow past empty armor reaches health (15)")
	_check(is_equal_approx(damage_events[damage_events.size() - 1], 50.0), "damaged() reports the full incoming amount")
	_check(armor_events[0] >= 3, "armor_changed fires on set and on damage")
	_check(health.restore_armor(40.0) and is_equal_approx(health.armor, 40.0), "restore_armor refills the bar")
	_check(health.restore_armor(100.0) and is_equal_approx(health.armor, 60.0), "restore is clamped to the maximum")
	_check(not health.restore_armor(10.0), "restoring a full bar does nothing (plate would be wasted)")
	var no_armor := HealthComponent.new()
	no_armor._ready()
	_check(not no_armor.restore_armor(40.0), "cannot restore armor you do not have")
	no_armor.free()
	health.take_damage(60.0 + 85.0)
	_check(health.is_dead() and died[0], "death happens only after armor and health are gone")
	health.restore_armor(10.0)
	health.heal(10.0)
	_check(health.is_dead(), "dead stays dead")
	health.free()


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(3)
	return main


func _test_in_game() -> void:
	print("In game")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var inv := player.inventory
	var health := player.health

	_check(inv.add_item(_item("light_tactical_armor")) and is_equal_approx(health.armor, 30.0) and is_equal_approx(health.max_armor, 30.0),
			"equipping armor creates a full bar on the player's health")
	health.take_damage(20.0)
	_check(is_equal_approx(health.armor, 10.0), "damage drains the player's armor")
	_check(inv.add_item(_item("reinforced_armor")) and is_equal_approx(health.armor, 60.0),
			"equipping better armor refills the bar completely")

	# Plates: restore on pickup, stay on the ground when useless
	health.take_damage(50.0)
	var plate := _item("armor_plate")
	_check(inv.add_item(plate) and is_equal_approx(health.armor, 50.0), "armor plate restores 40 points immediately")
	_check(inv.add_item(plate) and is_equal_approx(health.armor, 60.0), "a second plate tops the bar up")
	_check(not inv.add_item(plate), "a plate at a full bar is not wasted (stays on the ground)")
	var pickup := Pickup.spawn(main, plate, player.global_position)
	await _frames(4)
	_check(is_instance_valid(pickup) and not pickup.is_queued_for_deletion(), "plate pickup is left alone at a full bar")
	health.take_damage(30.0)
	await _frames(4)
	# Standing still inside the pickup: re-enter to trigger collection
	pickup.global_position = player.global_position + Vector3(8, 0, 0)
	await _frames(2)
	pickup.global_position = player.global_position
	await _frames(4)
	_check(is_equal_approx(health.armor, 60.0), "walking into a plate restores armor (armor %.0f)" % health.armor)

	inv.from_dict({"weapon": "improvised_blade", "armor": ""})
	_check(not inv.add_item(plate), "plates are not collected without any armor")
	inv.add_item(_item("reinforced_armor"))

	# Save round trip incl. armor points
	health.set_armor(60.0, 20.0)
	var data := inv.to_dict()
	_check(is_equal_approx(float(data["armor_points"]), 20.0) and data["armor"] == "reinforced_armor", "to_dict stores armor id and points")
	var save_manager := root.get_node_or_null("SaveManager")
	if save_manager:
		var clean: Dictionary = save_manager._sanitize({"inventory": data, "player": {"health": 80.0, "max_health": 100.0}})
		_check(is_equal_approx(float(clean["inventory"]["armor_points"]), 20.0), "sanitize keeps armor points")
		health.set_armor(60.0, 60.0)
		inv.from_dict(clean["inventory"])
		_check(is_equal_approx(health.armor, 20.0) and is_equal_approx(health.max_armor, 60.0), "restore re-creates the partially empty bar")
		var legacy: Dictionary = save_manager._sanitize({"inventory": {"weapon": "combat_knife", "armor": "reinforced_armor", "potions": 1},
				"player": {"health": 90.0, "max_health": 100.0}})
		inv.from_dict(legacy["inventory"])
		_check(is_equal_approx(health.armor, 60.0), "a save without armor_points restores a full bar")
		var hostile: Dictionary = save_manager._sanitize({"inventory": {"armor": "reinforced_armor", "armor_points": -9999.0}, "player": {}})
		inv.from_dict(hostile["inventory"])
		_check(health.armor >= 0.0 and health.armor <= health.max_armor, "nonsense armor points are clamped")
	else:
		_check(true, "SaveManager autoload not present; skipped save checks")

	inv.from_dict({"weapon": "improvised_blade", "armor": ""})
	_check(is_zero_approx(health.max_armor) and not inv.armor, "removing armor removes the bar")
	main.queue_free()
	await _frames(3)


func _test_weapon_models() -> void:
	print("Weapon models")
	var model := WeaponModel.new()
	root.add_child(model)
	await _frames(2)
	var built := 0
	var sane := true
	for id in WEAPONS:
		model.show_weapon(_item(id))
		var blade := model._blade_a.mesh as BoxMesh
		sane = sane and blade.size.z > 0.05 and blade.size.x > 0.0 and model._grip.visible and model._tip.mesh is PrismMesh
		built += 1
	_check(built == WEAPONS.size() and sane, "a model builds for every weapon")
	model.show_weapon(null)
	_check(model._blade_a.visible, "null weapon falls back to a generic blade")
	model.show_weapon(_item("claymore"))
	var claymore_len := (model._blade_a.mesh as BoxMesh).size.z
	model.show_weapon(_item("combat_knife"))
	var knife_len := (model._blade_a.mesh as BoxMesh).size.z
	_check(claymore_len > knife_len * 2.0, "claymore blade is much longer than the knife's")
	model.show_weapon(_item("katana"))
	_check(model._blade_b.visible and absf(model._bend.rotation_degrees.y) > 1.0, "katana has a curved tip")
	model.show_weapon(_item("tactical_sword"))
	_check(not model._blade_b.visible, "straight swords have no bend segment")
	model.show_weapon(_item("warden_blade"))
	_check((model._metal as StandardMaterial3D).emission_enabled, "legendary weapons glow")
	model.show_weapon(_item("combat_knife"))
	_check(not model._metal.emission_enabled, "common-tier weapons do not glow")
	model.free()

	# The real player's Weapon node follows the inventory
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var weapon := player.get_node("VisualRoot/WeaponPivot/Weapon") as WeaponModel
	_check(weapon != null and weapon._shown_id == &"improvised_blade", "the player's Weapon node starts with the scrap blade")
	player.inventory.add_item(_item("katana"))
	_check(weapon._shown_id == &"katana", "the model swaps when the equipped weapon changes")
	main.queue_free()
	await _frames(3)
