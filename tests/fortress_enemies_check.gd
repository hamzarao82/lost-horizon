extends SceneTree
## Fortress enemy configurations (Milestone 9): godot --headless --path . -s tests/fortress_enemies_check.gd
## Data checks first (every number a player has to react to is asserted from the .tres files), then each
## configuration spawns and fights a real Player on a private floor far from the arena.

const ORIGIN: Vector3 = Vector3(200.0, 0.0, 200.0)
const CONFIGS: Array[String] = ["fortress_infantry", "elite_security_soldier", "heavy_assault_unit", "tactical_commander",
		"fortress_captain", "director"]
const RANGED_CONFIGS: Array[String] = ["fortress_infantry", "elite_security_soldier", "heavy_assault_unit", "tactical_commander"]

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player
var _pin_at: Vector3


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), message)
	if not condition:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		_player.global_position = _pin_at
		_player.velocity = Vector3.ZERO
		await physics_frame


func _cfg(id: String) -> EnemyConfig:
	return load("res://resources/enemies/%s.tres" % id) as EnemyConfig


func _setup() -> void:
	Projectile.reset_pool()
	if is_instance_valid(_main):
		_main.queue_free()
		for i in 3:
			await physics_frame
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	for i in 3:
		await physics_frame
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = ORIGIN + Vector3(0.0, -0.5, 0.0)
	_main.add_child(floor_body)
	_player = _main.get_node("Player") as Player
	_player.health.max_health = 100000.0
	_player.health.health = 100000.0
	_pin_at = ORIGIN + Vector3(0.0, 0.1, 10.0)
	await _frames(2)


func _run() -> void:
	_test_data()
	await _setup()
	await _test_spawns()
	await _test_loot_and_unique()
	print("fortress_enemies_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	for id in CONFIGS:
		var cfg := _cfg(id)
		_check(cfg != null, "%s loads as an EnemyConfig" % id)
		if cfg == null:
			continue
		_check(load(cfg.scene_path) != null, "%s: scene %s loads" % [id, cfg.scene_path])
		_check(load(cfg.swing_path) is AttackData, "%s: melee attack loads" % id)
		_check(load(cfg.loot_table_path) is LootTable, "%s: loot table loads" % id)
		_check(cfg.hit_points > 0.0, "%s: health %.0f" % [id, cfg.hit_points])
	var infantry := _cfg("fortress_infantry")
	var elite := _cfg("elite_security_soldier")
	var heavy := _cfg("heavy_assault_unit")
	var commander := _cfg("tactical_commander")
	var captain := _cfg("fortress_captain")
	var director := _cfg("director")
	var guard := load("res://resources/enemies/facility_commander.tres") as EnemyConfig
	_check(infantry.hit_points > 70.0 and elite.hit_points > infantry.hit_points, "health climbs infantry (%.0f) to elite (%.0f)" % [infantry.hit_points, elite.hit_points])
	_check(heavy.hit_points > elite.hit_points and heavy.armor > elite.armor and heavy.move_speed < infantry.move_speed,
			"the heavy unit is the most durable and the slowest of the line troops")
	_check(commander.coordinate_alarm and commander.ranged != null, "the commander is a ranged enemy that alerts allies")
	_check(captain.hit_points > 300.0 and captain.hit_points < 420.0, "the captain sits between the elite subject (300) and the Warden (420): %.0f" % captain.hit_points)
	_check(director.hit_points >= 550.0 and director.hit_points <= 700.0, "the Director's health is 650 +/- 100: %.0f" % director.hit_points)
	_check(captain.unique_drop_path != "" and director.unique_drop_path != "", "captain and Director carry a unique reward")
	_check(guard.hit_points < commander.hit_points + 1.0, "the fortress commander is at least as tough as the facility one (%.0f vs %.0f)" % [commander.hit_points, guard.hit_points])
	# Fairness from data: ranged enemies' shot telegraph and recovery windows.
	for id in RANGED_CONFIGS:
		var cfg := _cfg(id)
		_check(cfg.ranged != null and cfg.ranged.validate().is_empty(), "%s: ranged config valid (%s)" % [id, ", ".join(cfg.ranged.validate()) if cfg.ranged else "none"])
		_check(cfg.ranged.telegraph_seconds() >= 0.6 and cfg.ranged.recovery_seconds() >= 0.5,
				"%s: telegraph %.2f s, recovery %.2f s" % [id, cfg.ranged.telegraph_seconds(), cfg.ranged.recovery_seconds()])
	_check(heavy.ranged.telegraph_seconds() >= 0.8, "the heavy weapon telegraph is long: %.2f s" % heavy.ranged.telegraph_seconds())
	_check(heavy.ranged.shot().damage >= infantry.ranged.shot().damage, "the heavy burst hurts more per shot")
	_check(_cfg("fortress_captain").ranged == null and _cfg("director").ranged == null,
			"the captain and the Director run their own move sets, not the ranged brain")
	var unique_items: Array[String] = [captain.unique_drop_path, director.unique_drop_path]
	for path in unique_items:
		var item := load(path) as ItemData
		_check(item != null and item.unique and item.icon() != null, "%s is a unique item with an icon" % path.get_file())


func _spawn(id: String, at: Vector3) -> Enemy:
	var enemy := _cfg(id).spawn(_main, at)
	await _frames(3)
	return enemy


func _test_spawns() -> void:
	for id in CONFIGS:
		var enemy := await _spawn(id, ORIGIN + Vector3(0.0, 0.1, -4.0))
		_check(is_instance_valid(enemy) and enemy.display_name == _cfg(id).display_name, "%s spawns with its display name" % id)
		if _cfg(id).unique_drop_path != "":
			_check(enemy.defeated.get_connections().size() >= 1, "%s: the unique drop is hooked to defeated (%d connections)" % [id, enemy.defeated.get_connections().size()])
		_check(is_equal_approx(enemy._health.max_health, _cfg(id).hit_points), "%s has %.0f health" % [id, _cfg(id).hit_points])
		if _cfg(id).armor > 0.0:
			_check(enemy._health.armor > 0.0, "%s has an armor pool (%.0f)" % [id, enemy._health.armor])
		_check(enemy.state != Enemy.State.DEAD, "%s is alive after spawning" % id)
		var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
		for i in 200 if id != "director" else 1400:
			if enemy.is_dead():
				break
			enemy.receive_hit(heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
			await _frames(1)
		_check(enemy.is_dead(), "%s dies through receive_hit" % id)
		await _frames(2)


func _test_loot_and_unique() -> void:
	var before := _main.find_children("*", "Pickup", true, false).size()
	var enemy := await _spawn("fortress_captain", ORIGIN + Vector3(0.0, 0.1, -4.0))
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 400:
		if enemy.is_dead():
			break
		enemy.receive_hit(heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		await _frames(1)
	await _frames(4)
	var drops: Array[Node] = _main.find_children("*", "Pickup", true, false)
	_check(drops.size() > before, "the captain drops loot (%d pickups)" % (drops.size() - before))
	var ids: PackedStringArray = []
	var badge_found := false
	for node in drops:
		var item = node.get("item")
		if item != null:
			ids.append(String(item.item_id))
			if String(item.item_id) == "fortress_badge":
				badge_found = true
	_check(badge_found, "the captain's unique badge is among the drops (%s)" % ", ".join(ids))
	_player.inventory.unique_claimed["fortress_badge"] = true
	var second := await _spawn("fortress_captain", ORIGIN + Vector3(0.0, 0.1, -4.0))
	var count_before := _main.find_children("*", "Pickup", true, false).size()
	for i in 400:
		if second.is_dead():
			break
		second.receive_hit(heavy, second.global_position + Vector3(0.0, 0.0, 2.0))
		await _frames(1)
	await _frames(4)
	var after: Array[Node] = _main.find_children("*", "Pickup", true, false)
	var again := false
	for i in range(count_before, after.size()):
		var item = after[i].get("item")
		if item != null and String(item.item_id) == "fortress_badge":
			again = true
	_check(not again, "a claimed unique badge never drops twice")
