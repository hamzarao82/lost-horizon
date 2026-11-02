extends SceneTree
## Door state checks:  godot --headless --path . -s tests/door_check.gd

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
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


func _make(flag: StringName, door_name: String) -> Door:
	var door := Door.new()
	door.door_id = StringName(door_name)
	door.locked_by_flag = flag
	door.lock_reason = "Needs the thing"
	root.add_child(door)
	return door


func _run() -> void:
	var state := root.get_node("WorldState")
	state.reset()
	var player := Node3D.new()
	root.add_child(player)

	print("Locked door")
	var door := _make(&"test_key", "t1")
	await _frames(2)
	_check(door.locked and door.current_prompt() == "Needs the thing", "a door with a missing flag is locked and says why")
	_check(not door.interact(player) and not door.is_open, "using a locked door does nothing")
	state.set_flag(&"test_key", true)
	_check(not door.locked and door.current_prompt() == "Open door", "setting the flag unlocks it")
	var collider := door.get_node("DoorBody/CollisionShape3D") as CollisionShape3D
	_check(not collider.disabled, "closed: the collider is active")

	print("Opening")
	_check(door.interact(player), "an unlocked door opens")
	await _frames(2)
	_check(door.is_open and collider.disabled, "open: collider disabled")
	_check(state.has_flag(&"door_t1_open"), "the open flag is set")
	_check(not door.enabled and not door.can_interact(), "an open door no longer offers a prompt")
	door.open(true)
	_check(door.is_open, "opening twice is harmless")

	print("Restore from state")
	var again := _make(&"", "t1")
	await _frames(2)
	_check(again.is_open, "a door whose flag is already set starts open (death restart)")
	var free_door := _make(&"", "t2")
	await _frames(2)
	_check(not free_door.locked and free_door.can_interact(), "a door without a lock flag is usable")
	_check(free_door.interact(player) and free_door.is_open, "and opens")

	print("\n%d checks, %d failed" % [_checks, _failures])
	state.reset()
	quit(1 if _failures > 0 else 0)
