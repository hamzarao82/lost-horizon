extends SceneTree
## Warden retry and save/load behaviour in Area D (headless): godot --headless --path . -s tests/warden_retry_check.gd

var _failures: int = 0
var _checks: int = 0
var _world: Node
var _main: Node
var _intro: BossIntro


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
	_world = root.get_node("WorldState")
	var qm := root.get_node_or_null("/root/QuestManager")
	if qm:
		qm.set("intro_done", true)
	await _test_fresh_after_death()
	await _test_reentry_replaces_damaged_warden()
	await _test_save_load_mid_fight()
	print("\nwarden_retry_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _new_main() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
		await _frames(3)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(3)
	var outpost := _main.get_node("Outpost17")
	_intro = outpost.boss_intro
	_intro.intro_seconds = 0.4
	_intro.quick_intro_seconds = 0.2
	(outpost.doors[&"cd"] as Door).open(false)
	await _frames(2)


func _alive() -> Array:
	return get_nodes_in_group("boss").filter(func(n: Node) -> bool: return n is Enemy and not (n as Enemy).is_dead())


func _blocked() -> bool:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.0, 1.0, -60.0), Vector3(0.0, 1.0, -64.0), 1)
	return not space.intersect_ray(query).is_empty()


func _test_fresh_after_death() -> void:
	print("A death reloads the scene: a fresh, full-health Warden")
	_world.reset()
	await _new_main()
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	await create_timer(0.5).timeout
	var first := _alive()[0] as Enemy
	first._health.take_damage(first._health.max_health * 0.6)
	_check(first._health.health < first._health.max_health * 0.5, "the first Warden is badly hurt")
	# The player dies: Main is rebuilt from scratch; the flags that persist are the same ones a respawn keeps.
	await _new_main()
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	var wardens := _alive()
	_check(wardens.size() == 1, "after the restart there is exactly one Warden")
	var again := wardens[0] as Enemy
	_check(is_equal_approx(again._health.health, again._health.max_health), "at full health")
	_check(_blocked(), "and the doorway is sealed")
	await create_timer(0.35).timeout
	_check(again.is_physics_processing(), "after only the short introduction (warden_intro_done was already set)")


func _test_reentry_replaces_damaged_warden() -> void:
	print("Leaving by teleport and coming back resets a damaged Warden")
	_world.reset()
	await _new_main()
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	await create_timer(0.5).timeout
	var old := _alive()[0] as Enemy
	old._health.take_damage(old._health.max_health * 0.5)
	_world.emit_area_entered(&"area_b_compound")
	await _frames(2)
	_world.emit_area_entered(&"area_d_command")
	await create_timer(0.1).timeout
	await _frames(3)
	var wardens := _alive()
	_check(wardens.size() == 1, "exactly one Warden after re-entering")
	if wardens.size() == 1:
		var now := wardens[0] as Enemy
		_check(is_equal_approx(now._health.health, now._health.max_health), "back at full health")
		_check(now != old, "a fresh Warden replaced the damaged one")
	_check(_blocked(), "the doorway stays sealed")
	# a full-health Warden that has not been touched is not replaced
	var keep := _alive()[0] as Enemy
	_world.emit_area_entered(&"area_b_compound")
	await _frames(2)
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	_check(_alive().size() == 1 and _alive()[0] == keep, "an untouched Warden is kept (no churn)")


func _test_save_load_mid_fight() -> void:
	print("Save and load in the middle of the fight")
	_world.reset()
	await _new_main()
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	await create_timer(0.5).timeout
	var boss := _alive()[0] as Enemy
	boss._health.take_damage(boss._health.max_health * 0.3)
	var saved: Dictionary = _world.to_dict()
	_check(saved["flags"].has("warden_intro_done"), "the saved world remembers the introduction")
	_check(not saved["flags"].has("boss_warden_defeated") and not saved["flags"].has("warden_d_defeated"),
			"and does not claim a victory")
	_world.reset()
	_world.from_dict(saved)
	await _new_main()
	_check(_alive().is_empty() and not _blocked(), "after loading, no Warden exists yet and the doorway is open")
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	_check(_alive().size() == 1, "entering Area D after a load spawns exactly one Warden")
	var fresh := _alive()[0] as Enemy
	_check(is_equal_approx(fresh._health.health, fresh._health.max_health), "at full health")
	_check(_blocked(), "with the doorway sealed again")
	_world.reset()
	if is_instance_valid(_main):
		_main.queue_free()
	await _frames(3)
