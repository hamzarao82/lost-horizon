extends SceneTree
## Headless checks for the teleport ability:
##   godot --headless --path . -s tests/teleport_check.gd
## Uses a fake wall clock and throw-away config files; never touches the real teleport.cfg.

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const R: float = 100.0  # shortened recharge for the logic tests

var _failures: int = 0
var _checks: int = 0
var _files: Array[String] = []
var _nodes: Array[TeleportAbility] = []


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
	_test_logic()
	_test_persistence_and_corruption()
	await _test_in_game()
	for node in _nodes:
		node.free()
	for path in _files:
		DirAccess.remove_absolute(path)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- helpers ----------------------------------------------------------------

var _clock: Array[float] = [1_000_000.0]


func _fake_clock() -> float:
	return _clock[0]


func _unit(file_name: String, fresh: bool = true) -> TeleportAbility:
	var path := "user://%s_%d.cfg" % [file_name, OS.get_process_id()]
	if not _files.has(path):
		_files.append(path)
	if fresh and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var ability := TeleportAbility.new()
	ability.save_path = path
	ability.recharge_seconds = R
	ability.clock = _fake_clock
	ability.rng.seed = 99
	_nodes.append(ability)
	ability.load_state()
	return ability


# --- pure logic ---------------------------------------------------------------

func _test_logic() -> void:
	print("Charges and recharge")
	_clock[0] = 1_000_000.0
	var ability := _unit("tp_logic")
	_check(ability.charges == 2, "starts with 2 charges")
	_check(ability.seconds_until_next() == 0.0, "no timer while full")
	_check(ability.use_charge() and ability.charges == 1, "first use consumes one")
	_check(is_equal_approx(ability.seconds_until_next(), R), "recharge timer starts at the first use")
	_check(ability.use_charge() and ability.charges == 0, "second use consumes the other")
	_check(not ability.use_charge() and ability.charges == 0, "third use is denied")
	_clock[0] += R - 1.0
	ability.refresh()
	_check(ability.charges == 0, "no charge before the recharge time")
	_clock[0] += 2.0
	ability.refresh()
	_check(ability.charges == 1, "one charge returns after the recharge time")
	_check(is_equal_approx(ability.seconds_until_next(), R - 1.0), "second charge is a further R after the first (sequential)")
	_clock[0] += R
	ability.refresh()
	_check(ability.charges == 2 and ability.seconds_until_next() == 0.0, "full again after 2R in total")

	# Using one while the other is already recharging does not restart the timer.
	_clock[0] = 2_000_000.0
	var seq := _unit("tp_seq")
	seq.use_charge()
	_clock[0] += 40.0
	seq.use_charge()
	_check(is_equal_approx(seq.seconds_until_next(), R - 40.0), "spending the 2nd charge keeps the running timer")

	# Downtime catch-up: both used, then the game stays closed for much longer than 2R.
	_clock[0] = 3_000_000.0
	var offline := _unit("tp_offline")
	offline.use_charge()
	offline.use_charge()
	_clock[0] += R * 10.0
	var reopened := _unit("tp_offline", false)
	_check(reopened.charges == 2, "charges catch up after long downtime")
	_clock[0] = 4_000_000.0
	var partial := _unit("tp_partial")
	partial.use_charge()
	partial.use_charge()
	_clock[0] += R * 1.5
	var partial_reopened := _unit("tp_partial", false)
	_check(partial_reopened.charges == 1 and is_equal_approx(partial_reopened.seconds_until_next(), R * 0.5), "partial downtime returns exactly the elapsed charges")

	_check(TeleportAbility.format_time(581.0) == "09:41", "countdown formats as mm:ss (09:41)")
	_check(TeleportAbility.DEFAULT_RECHARGE_SECONDS == 600.0 and TeleportAbility.MAX_CHARGES == 2, "defaults are 2 charges and 10 minutes")
	_check(InputMap.has_action("teleport"), "teleport input action exists")
	var has_button := false
	for button in TouchControls.BUTTONS:
		has_button = has_button or button["action"] == &"teleport"
	_check(has_button, "touch controls have a Tele button")
	_check(ResourceLoader.exists("res://assets/audio/teleport.wav"), "teleport sound exists")


func _test_persistence_and_corruption() -> void:
	print("Persistence and corrupt files")
	_clock[0] = 5_000_000.0
	var first := _unit("tp_persist")
	first.use_charge()
	var second := _unit("tp_persist", false)
	_check(second.charges == 1 and is_equal_approx(second.seconds_until_next(), R), "state survives a restart (round trip)")

	var path := "user://tp_corrupt_%d.cfg" % OS.get_process_id()
	_files.append(path)
	_write_raw(path, "[teleport]\ncharges=0\nready_at=%f\n" % (_clock[0] + R * 50.0))
	var future := _load_raw(path)
	_check(future.charges == 0 and future.seconds_until_next() <= R + 1.0, "a timer far in the future is pulled back to at most R")

	_write_raw(path, "[teleport]\ncharges=-5\nready_at=%f\n" % (_clock[0] + 10.0))
	var negative := _load_raw(path)
	_check(negative.charges == 0, "negative charges clamp to 0")

	_write_raw(path, "[teleport]\ncharges=99\nready_at=5\n")
	var big := _load_raw(path)
	_check(big.charges == 2 and big.ready_at == 0.0, "too many charges clamp to the maximum")

	_write_raw(path, "[teleport]\ncharges=1\nready_at=nan\n")
	var nan_timer := _load_raw(path)
	_check(nan_timer.charges == 1 and is_equal_approx(nan_timer.seconds_until_next(), R), "NaN timer costs a full wait, no free charge")

	_write_raw(path, "[teleport]\ncharges=0\n")
	var missing_timer := _load_raw(path)
	_check(missing_timer.charges == 0 and is_equal_approx(missing_timer.seconds_until_next(), R), "missing timer costs a full wait")

	_write_raw(path, "[teleport]\ncharges=\"lots\"\nready_at=\"soon\"\n")
	var wrong_types := _load_raw(path)
	_check(wrong_types.charges >= 0 and wrong_types.charges <= 2, "wrong value types do not crash")

	_write_raw(path, "this is { not a config file")
	var garbage := _load_raw(path)
	_check(garbage.charges >= 0 and garbage.charges <= 2, "an unreadable file does not crash")


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _load_raw(path: String) -> TeleportAbility:
	var ability := TeleportAbility.new()
	ability.save_path = path
	ability.recharge_seconds = R
	ability.clock = _fake_clock
	_nodes.append(ability)
	ability.load_state()
	return ability


# --- in the game --------------------------------------------------------------

func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(4)
	return main


func _ability(main: Node) -> TeleportAbility:
	return main.get_node("Player").get_node_or_null("TeleportAbility") as TeleportAbility


func _spawn_enemy(main: Node, pos: Vector3) -> Enemy:
	var enemy := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	enemy.position = pos
	main.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _reset_live(ability: TeleportAbility) -> void:
	ability.clock = Callable()  # real clock
	ability.charges = TeleportAbility.MAX_CHARGES
	ability.ready_at = 0.0
	ability.save_state()


func _test_in_game() -> void:
	print("In the game")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var ability := _ability(main)
	_check(ability != null, "the Teleport autoload attaches an ability to the player")
	if ability == null:
		return
	_reset_live(ability)
	_check(ability.save_path.begins_with("user://teleport_test_"), "headless runs use a throw-away config file")

	# Destination rules over many draws, with enemies around.
	var enemies: Array[Enemy] = [
		_spawn_enemy(main, Vector3(-10, 0.1, -15)),
		_spawn_enemy(main, Vector3(12, 0.1, 10)),
		_spawn_enemy(main, Vector3(0, 0.1, -20)),
	]
	await _frames(2)
	ability.rng.seed = 2024
	var origin := player.global_position
	var all_ok := true
	var inside := true
	var no_obstacle := true
	var far_from_player := true
	var far_from_enemies := true
	var count := 60
	for i in count:
		var spot := ability.pick_destination(player)
		inside = inside and absf(spot.x) <= 26.0 and absf(spot.z) <= 26.0
		for obstacle in TeleportAbility.OBSTACLES:
			no_obstacle = no_obstacle and Vector2(spot.x, spot.z).distance_to(obstacle) >= TeleportAbility.OBSTACLE_CLEARANCE
		far_from_player = far_from_player and Vector2(spot.x - origin.x, spot.z - origin.z).length() >= TeleportAbility.MIN_MOVE
		for enemy in enemies:
			far_from_enemies = far_from_enemies and Vector2(spot.x - enemy.global_position.x, spot.z - enemy.global_position.z).length() >= TeleportAbility.MIN_ENEMY_DISTANCE
	all_ok = inside and no_obstacle and far_from_player and far_from_enemies
	_check(inside, "destinations stay inside the arena (%d draws)" % count)
	_check(no_obstacle, "destinations never fall inside the obstacle boxes")
	_check(far_from_player, "destinations are at least 8 m from the starting spot")
	_check(far_from_enemies, "destinations are at least 6 m from every enemy")
	var distinct := {}
	for i in 12:
		var spot := ability.pick_destination(player)
		distinct[Vector2i(roundi(spot.x), roundi(spot.z))] = true
	_check(distinct.size() > 4, "destinations are random, not a fixed point (%d distinct of 12)" % distinct.size())
	_check(all_ok, "all destination rules hold together")

	# Physics check rejects a blocked spot.
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3, 3, 3)
	shape.shape = box
	blocker.add_child(shape)
	blocker.position = Vector3(20, 1.5, 20)
	main.add_child(blocker)
	await _frames(2)
	_check(not ability._is_free(player, Vector3(20, 0.1, 20)), "a spot inside a collider is rejected")
	_check(ability._is_free(player, Vector3(-20, 0.1, 20)), "an open spot is accepted")

	# Using it for real.
	for enemy in enemies:
		enemy.queue_free()
	await _frames(2)
	var denied_seconds := [-1.0]
	ability.denied.connect(func(seconds: float) -> void: denied_seconds[0] = seconds)
	var start := player.global_position
	player.velocity = Vector3(3, 0, 3)
	_check(ability.try_teleport(), "first teleport works")
	_check(ability.charges == 1, "it consumed a charge")
	_check(Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length() >= TeleportAbility.MIN_MOVE, "the player actually moved at least 8 m")
	_check(player.velocity == Vector3.ZERO, "velocity is cleared")
	if player.has_method("grant_invulnerability"):
		_check(player.is_invulnerable(), "a short invulnerability window follows")
	var hp := player.health.health
	_check(ability.try_teleport() and ability.charges == 0, "second teleport works and uses the last charge")
	var stay := player.global_position
	_check(not ability.try_teleport(), "third teleport is denied")
	_check(player.global_position == stay and ability.charges == 0, "a denied teleport does not move the player")
	_check(denied_seconds[0] > 0.0 and denied_seconds[0] <= TeleportAbility.DEFAULT_RECHARGE_SECONDS, "denial reports the time left (%.0f s)" % denied_seconds[0])
	_check(player.health.health == hp, "teleporting costs no health")

	# The key press path.
	_reset_live(ability)
	var before := player.global_position
	Input.action_press("teleport")
	await _frames(3)
	Input.action_release("teleport")
	_check(ability.charges == 1 and player.global_position.distance_to(before) > 1.0, "the teleport key triggers it")

	# Scene reload must not refund.
	_check(ability.charges == 1, "one charge left before the reload")
	main.queue_free()
	await _frames(4)
	var reloaded := await _spawn_main()
	var ability2 := _ability(reloaded)
	_check(ability2 != null and ability2.charges == 1, "a new scene (death restart) does not refund the charge")

	# Dead players cannot teleport.
	var player2 := reloaded.get_node("Player") as Player
	ability2.charges = 2
	ability2.ready_at = 0.0
	player2.health.take_damage(1000.0)
	_check(player2.is_dead(), "player is dead")
	var dead_at := player2.global_position
	_check(not ability2.try_teleport() and player2.global_position == dead_at and ability2.charges == 2, "a dead player cannot teleport and loses no charge")

	_reset_live(ability2)  # leave the throw-away file in a clean state
	reloaded.queue_free()
	await _frames(3)
