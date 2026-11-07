extends SceneTree
## Survival rules: health and armor, medkits, teleport charges and landing spots. Asserts today's
## numbers; none of these limits may change.
## godot --headless --path . -s tests/survival_check.gd

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const TEST_SAVE: String = "user://survival_check_teleport.json"

var _failures: int = 0
var _checks: int = 0
var _now: float = 1000000.0


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


func _run() -> void:
	_test_health_and_armor()
	_test_medkit()
	_test_teleport_charges()
	await _test_teleport_landing()
	print("survival_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _health(max_health: float = 100.0, armor: float = 0.0) -> HealthComponent:
	var health := HealthComponent.new()
	health.max_health = max_health
	root.add_child(health)
	health.health = max_health
	if armor > 0.0:
		health.set_armor(armor)
	return health


func _test_health_and_armor() -> void:
	var h := _health(100.0, 50.0)
	var reported: Array[float] = []
	var deaths: Array[bool] = []
	h.damaged.connect(func(a: float) -> void: reported.append(a))
	h.died.connect(func() -> void: deaths.append(true))
	h.take_damage(30.0)
	_check(h.armor == 20.0 and h.health == 100.0, "armor absorbs first: 30 damage leaves armor 20, health 100")
	h.take_damage(40.0)
	_check(h.armor == 0.0 and h.health == 80.0, "the rest goes to health: armor 0, health 80")
	_check(reported == [30.0, 40.0], "the reported damage is the full incoming amount (%s)" % str(reported))
	h.take_damage(0.0)
	h.take_damage(-5.0)
	_check(reported.size() == 2 and h.health == 80.0, "zero and negative damage do nothing")
	_check(h.restore_armor(10.0) and h.armor == 0.0 + 0.0 + 10.0, "armor can be restored (to 10)")
	_check(h.restore_armor(1000.0) and h.armor == 50.0, "restoring never exceeds the maximum")
	_check(not h.restore_armor(5.0), "restoring a full bar reports false")
	h.take_damage(1000.0)
	_check(h.is_dead() and deaths.size() == 1, "lethal damage kills exactly once")
	h.take_damage(1000.0)
	h.take_damage(5.0)
	_check(deaths.size() == 1 and h.health == 0.0, "damage after death neither re-kills nor goes below zero")
	h.heal(50.0)
	_check(h.health == 0.0, "a dead character cannot be healed")
	h.queue_free()
	var plain := _health(100.0)
	plain.take_damage(100.0)
	_check(plain.is_dead(), "exactly lethal damage kills with no armor")
	plain.queue_free()


func _test_medkit() -> void:
	var inventory := Inventory.new()
	root.add_child(inventory)
	var h := _health(100.0)
	inventory.potions = 2
	_check(not inventory.use_potion(h) and inventory.potions == 2, "a medkit is not used at full health and is not consumed")
	h.take_damage(60.0)
	_check(inventory.use_potion(h), "a medkit heals when hurt")
	_check(inventory.potions == 1, "exactly one medkit is consumed per heal")
	_check(h.health == minf(40.0 + inventory.potion_heal, 100.0), "it heals potion_heal (%.0f): health %.0f" % [inventory.potion_heal, h.health])
	h.health = 100.0
	_check(not inventory.use_potion(h) and inventory.potions == 1, "healing again at full health is refused, nothing consumed")
	h.take_damage(50.0)
	inventory.potions = 0
	_check(not inventory.use_potion(h), "no medkits means no heal")
	inventory.potions = 1
	h.take_damage(1000.0)
	_check(not inventory.use_potion(h) and inventory.potions == 1, "a dead player cannot use a medkit and keeps it")
	_check(Player.HEAL_BUFFER == 0.8, "the medkit input buffer is 0.8 s")
	_check(Inventory.MAX_POTIONS == 99, "the medkit cap is 99")
	h.queue_free()
	inventory.queue_free()


func _make_teleport() -> TeleportAbility:
	var tp := TeleportAbility.new()
	tp.save_path = TEST_SAVE
	tp.clock = func() -> float: return _now
	root.add_child(tp)
	tp.charges = TeleportAbility.MAX_CHARGES
	tp.ready_at = 0.0
	return tp


func _test_teleport_charges() -> void:
	_check(TeleportAbility.MAX_CHARGES == 2, "there are exactly two teleport charges")
	_check(TeleportAbility.DEFAULT_RECHARGE_SECONDS == 600.0, "a charge takes 10 minutes (600 s) to return")
	_now = 1000000.0
	var tp := _make_teleport()
	_check(tp.recharge_seconds > 0.0 and tp.recharge_seconds <= 600.0, "skills can only shorten the recharge, never lengthen it (%.0f s)" % tp.recharge_seconds)
	var recharge := tp.recharge_seconds
	_check(tp.use_charge() and tp.charges == 1, "the first use leaves one charge")
	_check(is_equal_approx(tp.ready_at, _now + recharge), "the recharge timer starts on first use")
	_check(tp.use_charge() and tp.charges == 0, "the second use leaves none")
	_check(not tp.use_charge() and tp.charges == 0, "a third use is refused")
	_now += recharge - 1.0
	tp.refresh()
	_check(tp.charges == 0, "one second early: still no charge")
	_now += 1.0
	tp.refresh()
	_check(tp.charges == 1, "after the recharge time one charge is back")
	_now += recharge
	tp.refresh()
	_check(tp.charges == 2 and tp.ready_at == 0.0, "after twice the time both charges are back")
	tp.use_charge()
	var other := TeleportAbility.new()
	other.save_path = TEST_SAVE
	other.clock = func() -> float: return _now
	root.add_child(other)
	_check(other.charges == 1, "a spent charge survives a reload (new instance reads %d)" % other.charges)
	_now -= 100000.0  # a clock set back must never create a longer wait
	other.refresh()
	_check(other.seconds_until_next() <= other.recharge_seconds + 1.0, "a clock set back never means waiting longer than one recharge")
	tp.queue_free()
	other.queue_free()
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _test_teleport_landing() -> void:
	_now = 2000000.0
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(4)
	var player: Player = main.get_node("Player")
	var tp: TeleportAbility = player.find_children("*", "TeleportAbility", true, false)[0]
	tp.save_path = TEST_SAVE
	tp.clock = func() -> float: return _now
	tp.charges = 2
	tp.ready_at = 0.0
	tp.rng.seed = 7
	player.global_position = Vector3(0.0, 0.1, 0.0)
	var in_arena := true
	for i in 30:
		var spot := tp.pick_destination(player)
		if absf(spot.x) > TeleportAbility.ARENA_LIMIT or absf(spot.z) > TeleportAbility.ARENA_LIMIT or Vector2(spot.x, spot.z).distance_to(Vector2(8, -6)) < 4.5:
			in_arena = false
	_check(in_arena, "in Outpost 17 every landing spot is inside the arena and clear of the containers")
	var regions := root.get_node_or_null("RegionManager")
	_check(regions != null, "the region manager exists")
	if regions == null:
		return
	var original: StringName = regions.current_region_id
	regions.current_region_id = &"dead_coast"
	player.global_position = Vector3(0.0, 0.1, 0.0)
	var ring_ok := true
	var found := 0
	for i in 30:
		var spot := tp.pick_destination(player)
		if spot == Vector3.INF:
			continue
		found += 1
		var d := Vector2(spot.x, spot.z).distance_to(Vector2(0.0, 0.0))
		if d < TeleportAbility.LOCAL_MIN - 0.01 or d > TeleportAbility.LOCAL_MAX + 0.01:
			ring_ok = false
	_check(found > 0 and ring_ok, "in another region the landing spot is 8 to 18 m from the player (%d of 30 found)" % found)
	# Open water or void: no ground below any candidate, so there is nowhere to land.
	player.global_position = Vector3(900.0, 0.1, 900.0)
	_check(tp.pick_destination(player) == Vector3.INF, "with no ground nearby there is no landing spot")
	var charges_before := tp.charges
	var before := player.global_position
	_check(not tp.try_teleport(), "the teleport is refused when there is nowhere safe to land")
	_check(tp.charges == charges_before and player.global_position == before, "a refused teleport keeps the charge and the position")
	regions.current_region_id = original
	main.queue_free()
	await _frames(2)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
