extends SceneTree
## The compound-entrance sign must exist in the real world exactly once, inside the Outer Perimeter, and
## walking up to it must start the First Signal and reveal the name. godot --headless --path . -s tests/outpost_sign_placed_check.gd

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
	var world := root.get_node("WorldState")
	qm.reset()
	world.reset()
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(6)
	var signs := main.find_children("*", "OutpostSign", true, false)
	_check(signs.size() == 1, "exactly one OUTPOST 17 sign exists in the world (%d)" % signs.size())
	if signs.size() == 1:
		var sign_node := signs[0] as OutpostSign
		var pos := sign_node.global_position
		_check(pos.z > 30.0 and pos.z < 45.0, "it stands between the perimeter fence and the compound (z %.1f)" % pos.z)
		_check(not world.has_flag(&"outpost_name_known"), "the name is not known before the player reaches it")
		var player := main.get_node("Player") as Player
		player.global_position = pos + Vector3(1.0, 0.0, 0.0)
		await _frames(8)
		_check(world.has_flag(&"outpost_name_known"), "walking up to it reveals the name")
		_check(qm.is_active(&"first_signal") or qm.is_completed(&"first_signal"), "and starts the First Signal")
	print("outpost_sign_placed_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
