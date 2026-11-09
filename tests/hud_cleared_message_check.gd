extends SceneTree
## "ARENA CLEARED" shows once when a fight ends, fades after a few seconds, and never lingers or appears by itself.
## godot --headless --path . -s tests/hud_cleared_message_check.gd

var _checks: int = 0
var _failures: int = 0


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
	var qm := root.get_node("QuestManager")
	var rm := root.get_node("RegionManager")
	var sm := root.get_node("SaveManager")
	await _frames(3)
	sm.reset_runtime_state()
	sm.delete_save()
	qm.intro_done = true
	qm.mission_autosave = false
	qm.reset()
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	var huds: Array[Node] = main.find_children("*", "Hud", true, false)
	_check(huds.size() == 1, "Main has one HUD")
	if huds.size() != 1:
		quit(1)
		return
	var hud: Hud = huds[0]
	var message: Label = hud.get("_message")
	_check(not message.visible, "no message is showing at the start")

	# 1) A real finish shows it, and it fades away.
	hud.call("_on_arena_cleared")
	_check(message.visible and message.text == "ARENA CLEARED", "finishing the arena shows ARENA CLEARED")
	hud.call("_process", 2.0)
	_check(message.visible, "still showing after 2 s")
	hud.call("_process", 3.5)
	_check(not message.visible, "gone after about 5 s (it used to stay forever)")

	# 2) A stage's waves have their own wording and also go away.
	hud.call("_on_stage_waves_cleared")
	_check(message.visible and message.text == "WAVES CLEARED", "finishing stage waves shows WAVES CLEARED")
	hud.call("_process", 6.0)
	_check(not message.visible, "and it goes away too")

	# 3) The death message is not timed.
	hud.call("_show_message", "YOU DIED", Color.RED)
	hud.call("_process", 30.0)
	_check(message.visible and message.text == "YOU DIED", "YOU DIED stays up")
	message.visible = false

	# 4) The old bug: a region with no arena and no living enemies drew ARENA CLEARED by itself.
	rm.unlock(&"dead_coast")
	await rm.travel(&"dead_coast", &"from_outpost", null, true)
	await _frames(90)
	for enemy in root.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_dead") and not enemy.is_dead():
			enemy.queue_free()
	await _frames(40)
	_check(not message.visible, "an empty region does not show ARENA CLEARED by itself (%s)" % message.text)

	sm.reset_runtime_state()
	sm.delete_save()
	print("hud_cleared_message_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
