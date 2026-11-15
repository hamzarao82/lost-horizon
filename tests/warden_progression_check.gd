extends SceneTree
## Warden victory and flag behaviour (headless): godot --headless --path . -s tests/warden_progression_check.gd

var _failures: int = 0
var _checks: int = 0
var _world: Node
var _main: Node
var _intro: BossIntro
var _captions: Array = []
var _recorder: Node


class Recorder extends Node:
	var log: Array = []

	func caption(text: String, _seconds: float = 4.0) -> void:
		log.append(text)


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
	await _test_area_d_victory_once()
	await _test_courtyard_warden_flags()
	print("\nwarden_progression_check: %d checks, %d failed" % [_checks, _failures])
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
	_intro.intro_seconds = 0.3
	_intro.quick_intro_seconds = 0.2
	(outpost.doors[&"cd"] as Door).open(false)
	# Replace the world-flow caption sink with a recorder so captions can be counted.
	for flow in get_nodes_in_group("world_flow"):
		flow.remove_from_group("world_flow")
	_recorder = Recorder.new()
	_recorder.add_to_group("world_flow")
	root.add_child(_recorder)
	await _frames(2)


func _alive() -> Array:
	return get_nodes_in_group("boss").filter(func(n: Node) -> bool: return n is Enemy and not (n as Enemy).is_dead())


func _count(text: String) -> int:
	var n := 0
	for line: String in _recorder.log:
		if line == text:
			n += 1
	return n


func _test_area_d_victory_once() -> void:
	print("Area D victory happens once")
	_world.reset()
	await _new_main()
	var xp_events: Array = [0]
	var progression := root.get_node("Progression")
	progression.xp_gained.connect(func(_a: int, source: String) -> void:
		if source == "kill":
			xp_events[0] += 1)
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	await create_timer(0.5).timeout
	var boss := _alive()[0] as Enemy
	boss._health.take_damage(100000.0)
	boss._health.take_damage(100000.0)  # a second lethal hit must not repeat anything
	await _frames(4)
	_check(boss.is_dead(), "the Warden dies")
	_check(_world.has_flag(&"boss_warden_defeated") and _world.has_flag(&"warden_d_defeated"), "both defeat flags are set")
	await create_timer(5.0).timeout
	_check(_count("The Warden falls.") == 1, "'The Warden falls.' is shown exactly once (%d)" % _count("The Warden falls."))
	_check(_count(BossIntro.FALL_LEAD) == 1, "the lead toward the command room is shown exactly once (%d)" % _count(BossIntro.FALL_LEAD))
	_check(xp_events[0] == 1, "kill XP is awarded once (%d)" % xp_events[0])
	var loot := 0
	for node in root.find_children("*", "Pickup", true, false):
		loot += 1
	_check(loot >= 1, "his loot dropped (%d pickups)" % loot)
	var loot_after := 0
	_world.emit_area_entered(&"area_d_command")
	await _frames(4)
	for node in root.find_children("*", "Pickup", true, false):
		loot_after += 1
	_check(loot_after <= loot, "walking back in does not drop loot again")
	_check(_alive().is_empty(), "walking back in spawns no new Warden after the victory")
	_check(not _world.has_flag(&"payment_recovered"), "the payment is not recovered here")


func _test_courtyard_warden_flags() -> void:
	print("Which Warden sets which flag")
	_world.reset()
	await _new_main()
	var wave_warden := (load("res://scenes/enemies/Warden.tscn") as PackedScene).instantiate() as Enemy
	wave_warden.position = Vector3(10.0, 0.1, 12.0)
	_main.add_child(wave_warden)
	await _frames(3)
	wave_warden._health.take_damage(100000.0)
	await _frames(3)
	_check(_world.has_flag(&"boss_warden_defeated"), "the courtyard Warden sets boss_warden_defeated (the road and terminal use it)")
	_check(not _world.has_flag(&"warden_d_defeated"), "but never warden_d_defeated, which only the Area D fight sets (the payment store uses it)")
	_world.reset()
	await _new_main()
	_world.emit_area_entered(&"area_d_command")
	await _frames(3)
	await create_timer(0.4).timeout
	_alive()[0]._health.take_damage(100000.0)
	await _frames(3)
	_check(_world.has_flag(&"warden_d_defeated") and _world.has_flag(&"boss_warden_defeated"), "the Area D Warden sets both")
	_world.reset()
	if is_instance_valid(_main):
		_main.queue_free()
	await _frames(3)
