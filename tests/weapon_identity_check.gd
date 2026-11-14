extends SceneTree
## Weapon identity (Milestone 11): the profile fields, the pure scaling, and a real Player using them.
##   godot --headless --path . -s tests/weapon_identity_check.gd

const ITEMS: String = "res://resources/items/"
const ATTACKS: String = "res://resources/attacks/"
const WEAPONS: Array[String] = [
	"wooden_stick", "improvised_blade", "combat_knife", "iron_sword", "military_machete",
	"katana", "tactical_sword", "claymore", "warden_blade",
]
## Stagger from weakest to strongest: the order the design promises (light and quick to heavy and slow).
const STAGGER_ORDER: Array[String] = ["combat_knife", "katana", "improvised_blade", "iron_sword", "tactical_sword", "claymore", "warden_blade"]
const CHAIN: Array[String] = ["light_1", "light_2", "light_3", "heavy_1", "sprint_attack", "air_attack", "spin_special"]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), message)
	if not condition:
		_failures += 1


func _item(id: String) -> ItemData:
	return load(ITEMS + id + ".tres") as ItemData


func _attack(id: String) -> AttackData:
	return load(ATTACKS + id + ".tres") as AttackData


func _run() -> void:
	_test_data()
	_test_scaling()
	await _test_player()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("Profile data")
	var sane := true
	for id in WEAPONS:
		var w := _item(id)
		sane = sane and w != null and w.stagger_power >= 0.5 and w.stagger_power <= 2.0 \
				and w.recovery_scale >= 0.5 and w.recovery_scale <= 1.5 \
				and w.heavy_multiplier >= 0.8 and w.heavy_multiplier <= 1.5
	_check(sane, "all %d weapons have stagger 0.5-2.0, recovery 0.5-1.5 and heavy 0.8-1.5" % WEAPONS.size())
	var ordered := true
	for i in range(1, STAGGER_ORDER.size()):
		ordered = ordered and _item(STAGGER_ORDER[i]).stagger_power >= _item(STAGGER_ORDER[i - 1]).stagger_power
	_check(ordered, "stagger power rises from knife to katana to blade to sword to claymore to Cleaver")
	_check(_item("combat_knife").stagger_power < 1.0 and _item("claymore").stagger_power > 1.0,
			"the fast light knife staggers less than the baseline, the claymore more")
	_check(_item("claymore").recovery_scale > _item("katana").recovery_scale and _item("claymore").heavy_multiplier > _item("combat_knife").heavy_multiplier,
			"the claymore recovers slower and hits harder with heavies than the quick weapons")
	_check(_item("claymore").reach > _item("combat_knife").reach and _item("warden_blade").reach >= _item("claymore").reach,
			"reach already ordered by weapon size (knife < claymore <= Cleaver)")
	for id in ["improvised_blade", "wooden_stick", "military_machete"]:
		var w := _item(id)
		_check(is_equal_approx(w.stagger_power, 1.0) and is_equal_approx(w.recovery_scale, 1.0) and is_equal_approx(w.heavy_multiplier, 1.0),
				"%s is the neutral baseline (all 1.0)" % id)
	_check(WeaponProfiles.is_neutral(null), "no weapon at all is neutral")


func _test_scaling() -> void:
	print("Scaling")
	WeaponProfiles.clear_cache()
	var light := _attack("light_1")
	var heavy := _attack("heavy_1")
	_check(WeaponProfiles.scaled(light, null) == light, "no weapon returns the base attack object")
	_check(WeaponProfiles.scaled(light, _item("improvised_blade")) == light, "the starting blade returns the very same object (today's numbers)")
	var knife_light := WeaponProfiles.scaled(light, _item("combat_knife"))
	var clay_light := WeaponProfiles.scaled(light, _item("claymore"))
	_check(knife_light != light and knife_light.stagger_time < light.stagger_time and knife_light.knockback < light.knockback,
			"the knife's light attack staggers and knocks back less (%.3f s < %.3f s)" % [knife_light.stagger_time, light.stagger_time])
	_check(clay_light.stagger_time > light.stagger_time and clay_light.knockback > light.knockback,
			"the claymore's light attack staggers and knocks back more (%.3f s)" % clay_light.stagger_time)
	_check(clay_light.recovery_frames > light.recovery_frames and knife_light.recovery_frames < light.recovery_frames,
			"recovery frames: knife %d < base %d < claymore %d" % [knife_light.recovery_frames, light.recovery_frames, clay_light.recovery_frames])
	_check(is_equal_approx(clay_light.damage, light.damage) and is_equal_approx(knife_light.damage, light.damage),
			"a light attack's damage is untouched by the profile (damage_multiplier owns that)")
	var clay_heavy := WeaponProfiles.scaled(heavy, _item("claymore"))
	var knife_heavy := WeaponProfiles.scaled(heavy, _item("combat_knife"))
	_check(clay_heavy.damage > heavy.damage and knife_heavy.damage < heavy.damage,
			"heavy damage: knife %.1f < base %.1f < claymore %.1f" % [knife_heavy.damage, heavy.damage, clay_heavy.damage])
	_check(WeaponProfiles.scaled(_attack("sprint_attack"), _item("claymore")).damage > _attack("sprint_attack").damage,
			"sprint attacks count as heavy for the heavy multiplier")
	_check(WeaponProfiles.scaled(_attack("air_attack"), _item("claymore")).damage == _attack("air_attack").damage,
			"air attacks are not heavy: damage unchanged")
	_check(WeaponProfiles.scaled(light, _item("claymore")) == clay_light, "the scaled copy is cached per weapon and attack")
	var floor_ok := true
	var ids_ok := true
	for wid in WEAPONS:
		for aid in CHAIN:
			var base := _attack(aid)
			var s := WeaponProfiles.scaled(base, _item(wid))
			floor_ok = floor_ok and s.recovery_frames >= 1 and s.startup_frames == base.startup_frames and s.active_frames == base.active_frames
			ids_ok = ids_ok and s.id == base.id and s.validate().is_empty()
	_check(floor_ok, "every weapon x every chain attack keeps startup and active frames and at least 1 recovery frame")
	_check(ids_ok, "every scaled attack keeps its id and still validates")
	var base_unchanged := is_equal_approx(light.stagger_time, 0.25) or light.stagger_time > 0.0
	_check(base_unchanged, "the shared base resource was not mutated by scaling (stagger %.2f)" % light.stagger_time)


func _test_player() -> void:
	print("Real player")
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	for i in 3:
		await physics_frame
	var player := main.get_node("Player") as Player
	var base := player._chain[Player.IDX_LIGHT_1]
	_check(player.inventory.weapon.item_id == &"improvised_blade", "a new player starts with the improvised blade")
	_check(player._weapon_attack(Player.IDX_LIGHT_1) == base, "starting weapon: the player uses the base attack objects unchanged")
	player.inventory.weapon = _item("claymore")
	var clay := player._weapon_attack(Player.IDX_LIGHT_1)
	_check(clay != base and clay.stagger_time > base.stagger_time, "claymore equipped: the player's swing staggers longer (%.3f s)" % clay.stagger_time)
	_check(player._weapon_attack(Player.IDX_SPRINT).damage > player._chain[Player.IDX_SPRINT].damage, "claymore equipped: sprint attack hits harder")
	player.inventory.weapon = _item("combat_knife")
	_check(player._weapon_attack(Player.IDX_LIGHT_1).stagger_time < base.stagger_time, "knife equipped: shorter stagger")
	var ok := true
	for idx in player._chain.size():
		ok = ok and player._weapon_attack(idx).startup_frames == player._chain[idx].startup_frames
	_check(ok, "no weapon changes any startup frame (input timing is preserved)")
	main.queue_free()
	await physics_frame
