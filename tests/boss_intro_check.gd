extends SceneTree
## Area D Warden encounter checks (headless): godot --headless --path . -s tests/boss_intro_check.gd

const WARDEN: String = "res://scenes/enemies/Warden.tscn"

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
	await _test_intro_and_victory()
	await _test_flags_and_no_spawn()
	await _test_return_after_death_and_safety()
	print("\n%d checks, %d failed" % [_checks, _failures])
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
	# Open the C-D door itself so only the boss seal can block the doorway.
	(outpost.doors[&"cd"] as Door).open(false)
	await _frames(2)


func _alive_wardens() -> Array:
	return get_nodes_in_group("boss").filter(func(n: Node) -> bool: return n is Enemy and not (n as Enemy).is_dead())


func _doorway_blocked() -> bool:
	var space := (_main as Node3D).get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(0.0, 1.0, -60.0), Vector3(0.0, 1.0, -64.0), 1)
	return not space.intersect_ray(query).is_empty()


func _test_intro_and_victory() -> void:
	print("Introduction and victory")
	_world.reset()
	await _new_main()
	_check(_alive_wardens().is_empty() and not _doorway_blocked(), "before Area D there is no boss and the doorway is open")
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	var wardens := _alive_wardens()
	_check(wardens.size() == 1, "entering Area D spawns exactly one Warden")
	var boss := wardens[0] as Enemy if wardens.size() == 1 else null
	if boss == null:
		return
	_check(boss.global_position.distance_to(Vector3(0.0, 0.1, -75.0)) < 1.0, "he stands in the command building")
	_check(not boss.is_physics_processing(), "he stands still during the introduction")
	_check(_doorway_blocked(), "the doorway behind the player is sealed")
	await create_timer(0.7).timeout
	_check(boss.is_physics_processing() and boss.state == Enemy.State.CHASE, "after the introduction he attacks")
	_check(_world.has_flag(&"warden_intro_done"), "the introduction is remembered")
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	_check(_alive_wardens().size() == 1, "entering again does not spawn a second Warden")
	_check(_doorway_blocked(), "the doorway stays sealed during the fight")
	boss._health.take_damage(100000.0)
	await _frames(3)
	_check(boss.is_dead(), "the Warden can be killed")
	_check(_world.has_flag(&"boss_warden_defeated") and _world.has_flag(&"warden_d_defeated"), "victory sets both defeat flags")
	_check(not _doorway_blocked(), "the doorway unseals on victory")


func _test_flags_and_no_spawn() -> void:
	print("Flags and the wave-5 Warden")
	_world.reset()
	await _new_main()
	var wave_warden := (load(WARDEN) as PackedScene).instantiate() as Enemy
	wave_warden.position = Vector3(10.0, 0.1, 12.0)
	_main.add_child(wave_warden)
	await _frames(3)
	_check(not _world.has_flag(&"boss_warden_defeated"), "no defeat flag while the wave Warden lives")
	wave_warden._health.take_damage(100000.0)
	await _frames(3)
	_check(_world.has_flag(&"boss_warden_defeated") and not _world.has_flag(&"warden_d_defeated"),
			"killing the courtyard Warden sets boss_warden_defeated only")
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	var count := 0
	for w in get_nodes_in_group("boss"):
		if w != wave_warden and w is Enemy and not (w as Enemy).is_dead():
			count += 1
	_check(count == 0 and not _doorway_blocked(), "so Area D has no boss and no seal")
	# A brand-new scene (death restart) with the flag still set behaves the same
	await _new_main()
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	_check(_alive_wardens().is_empty() and not _doorway_blocked(), "after a reload the boss stays gone and the door is open")


func _test_return_after_death_and_safety() -> void:
	print("Returning after dying, and never locked in")
	_world.reset()
	_world.set_flag(&"warden_intro_done", true)  # the full introduction already played in an earlier life
	await _new_main()
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	_check(_alive_wardens().size() == 1, "after a restart the Warden is back")
	_check(_doorway_blocked(), "and the doorway seals again")
	await create_timer(0.5).timeout
	_check(_alive_wardens()[0].is_physics_processing(), "with only the short introduction")
	# Safety net: if the Warden vanishes without dying, the door must open on its own
	var boss := _alive_wardens()[0] as Enemy
	boss.free()
	await create_timer(1.3).timeout
	_check(not _doorway_blocked(), "if the Warden disappears the seal releases by itself")
	_world.reset()
	if is_instance_valid(_main):
		_main.queue_free()
	await _frames(3)
