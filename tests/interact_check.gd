extends SceneTree
## Milestone 1 world flow: WorldState, interactables, power puzzle, gate, crates, keycard, terminal,
## courtyard trigger and the teleport guard.
##   godot --headless --path . -s tests/interact_check.gd

var _failures: int = 0
var _checks: int = 0
var _state: Node
var _courtyard_events: int = 0


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
	_state = root.get_node_or_null("WorldState")
	_check(_state != null, "WorldState autoload is registered")
	if _state == null:
		quit(1)
		return
	_test_world_state()
	await _test_scene_setup()
	await _test_interactor()
	await _test_puzzle_and_gate()
	await _test_crates()
	await _test_keycard_and_terminal()
	await _test_persistence()
	await _test_courtyard_trigger()
	await _test_teleport_guard()
	_state.reset()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	var player := main.get_node("Player") as Player
	player.health.max_health = 100000.0
	player.health.health = 100000.0
	return main


func _free_main(main: Node) -> void:
	main.queue_free()
	await _frames(3)


func _put(player: Player, position: Vector3) -> void:
	player.global_position = position
	player.velocity = Vector3.ZERO


func _press(action: String, hold_frames: int = 3) -> void:
	Input.action_press(action)
	await _frames(hold_frames)
	Input.action_release(action)
	await _frames(2)


func _test_world_state() -> void:
	print("WorldState")
	_state.reset()
	var events: Array = []
	_state.flag_changed.connect(func(id: StringName, value: bool) -> void: events.append([id, value]))
	_check(not _state.has_flag(&"alpha"), "unset flag reads false")
	_state.set_flag(&"alpha")
	_state.set_flag(&"alpha")
	_check(_state.has_flag(&"alpha"), "set_flag sets the flag")
	_check(events.size() == 1, "setting the same flag twice emits once")
	_state.set_flag(&"beta", true)
	_state.set_flag(&"alpha", false)
	_check(not _state.has_flag(&"alpha") and _state.has_flag(&"beta"), "flags clear independently")
	var data: Dictionary = _state.to_dict()
	_check(data["flags"] == ["beta"], "to_dict lists only set flags")
	_state.reset()
	_check(not _state.has_flag(&"beta"), "reset clears everything")
	_state.from_dict({"flags": ["power_on", "crate_1_taken", "Bad Flag!", 42, "x".repeat(80)]})
	_check(_state.has_flag(&"power_on") and _state.has_flag(&"crate_1_taken"), "from_dict restores flags")
	_check(not _state.has_flag(&"Bad Flag!") and not _state.has_flag(StringName("x".repeat(80))), "from_dict rejects odd and over-long ids")
	_state.from_dict({"flags": "not an array"})
	_check(not _state.has_flag(&"power_on"), "a malformed save leaves no flags (and does not crash)")
	_state.from_dict({})
	var relayed: Array = []
	_state.interacted.connect(func(id: StringName) -> void: relayed.append(id))
	_state.area_entered.connect(func(id: StringName) -> void: relayed.append(id))
	_state.emit_interacted(&"radio")
	_state.emit_area_entered(&"courtyard")
	_check(relayed == [&"radio", &"courtyard"], "interacted and area_entered helpers emit")
	_state.reset()


func _test_scene_setup() -> void:
	print("Scene setup")
	_state.reset()
	var main := await _spawn_main()
	var world := main.get_node_or_null("World") as WorldFlow
	_check(world != null, "Main has the World node")
	_check(main.get_node("WaveManager").autostart == false, "waves no longer autostart")
	var ids := {}
	for node in get_nodes_in_group("interactables"):
		ids[(node as Interactable).interaction_id] = true
	for id in [&"radio", &"switch_1", &"switch_2", &"switch_3", &"crate_1", &"crate_2", &"gate", &"command_terminal"]:
		_check(ids.has(id), "interactable %s exists" % id)
	var player := main.get_node("Player") as Player
	_check(player.get_node_or_null("Interactor") != null, "the player gets an Interactor at runtime")
	_check(player.global_position.distance_to(Vector3(0.0, 0.1, 0.0)) < 0.5, "headless runs keep the player at the arena origin")
	world.place_player()
	_check(player.global_position.distance_to(WorldFlow.SPAWN) < 0.1, "place_player puts the player on the beach start")
	_check(main.get_node("WallS").position.x == -17.0 and main.get_node("WallS2").position.x == 17.0, "south wall leaves an 8 m gate gap")
	await _free_main(main)


func _test_interactor() -> void:
	print("Interactor")
	_state.reset()
	var main := await _spawn_main()
	var world := main.get_node("World") as WorldFlow
	var player := main.get_node("Player") as Player
	var interactor := player.get_node("Interactor") as Interactor
	_put(player, Vector3(0.0, 0.1, 64.0))
	await _frames(10)
	_check(interactor.target == null and not TouchControls.interact_available, "nothing in reach: no target, no touch button")

	_put(player, WorldFlow.RADIO_SPOT + Vector3(0.0, 0.1, 1.0))
	await _frames(10)
	_check(interactor.target == world.radio, "the radio is picked when the player stands next to it")
	_check(TouchControls.interact_available, "the touch Use button becomes available")
	var count := [0]
	world.radio.interacted.connect(func(_p: Node3D) -> void: count[0] += 1)
	Input.action_press("interact")
	await _frames(12)  # held down for many frames
	Input.action_release("interact")
	await _frames(2)
	_check(count[0] == 1, "holding the key is still one interaction (got %d)" % count[0])
	_check(_state.has_flag(&"radio_heard"), "using the radio sets radio_heard")
	await _frames(25)
	await _press("interact")
	_check(count[0] == 2, "a second separate press interacts again (radio is repeatable)")

	player.health.take_damage(1.0e9)
	await _frames(12)
	_check(interactor.target == null, "a dead player cannot interact")
	await _free_main(main)


func _throw(world: WorldFlow, player: Player, id: StringName) -> bool:
	for item in world.switches:
		if item.interaction_id == id:
			return item.interact(player)
	return false


func _test_puzzle_and_gate() -> void:
	print("Power puzzle and gate")
	_state.reset()
	var main := await _spawn_main()
	var world := main.get_node("World") as WorldFlow
	var player := main.get_node("Player") as Player
	var gate := world.gate
	_check(not gate.is_open and gate.interactable.locked, "gate starts closed and locked")
	_check(gate.interactable.current_prompt() == "Gate locked: no power", "locked gate explains why")
	var shape := gate.get_node("GateBody/CollisionShape3D") as CollisionShape3D
	_check(not shape.disabled, "closed gate blocks with a collider")
	var locked_events: Array = []
	_state.interacted.connect(func(id: StringName) -> void: locked_events.append(id))
	_check(not gate.interactable.interact(player) and &"gate_locked" in locked_events, "using the locked gate fails and says so")

	_check(_throw(world, player, &"switch_1"), "switch_1 can be thrown")
	_check(not _throw(world, player, &"switch_1"), "a thrown switch cannot be thrown twice")
	_check(_state.has_flag(&"switch_1") and not _state.has_flag(&"power_on"), "one breaker is not enough")
	_throw(world, player, &"switch_2")
	await _frames(3)
	_check(not _state.has_flag(&"power_on") and not gate.is_open, "two breakers are not enough")
	_check(not world.switches[2].is_on, "switch_3 still off")
	_throw(world, player, &"switch_3")
	await _frames(3)
	_check(_state.has_flag(&"power_on"), "all three breakers raise power_on")
	_check(gate.is_open and _state.has_flag(&"gate_open"), "the gate opens with power")
	await _frames(3)
	_check(shape.disabled, "an open gate no longer blocks")
	_check(not gate.interactable.enabled, "the gate prompt disappears once open")
	await _free_main(main)


func _test_crates() -> void:
	print("Supply crates")
	_state.reset()
	var main := await _spawn_main()
	var world := main.get_node("World") as WorldFlow
	var player := main.get_node("Player") as Player
	var crate := world.crates[0]
	var before := _count_pickups(world)
	_check(crate.interact(player), "a crate opens")
	await _frames(3)
	_check(_count_pickups(world) - before == crate.loot_paths.size(), "it drops its items as pickups (%d)" % (_count_pickups(world) - before))
	_check(not crate.interact(player), "a crate cannot be looted twice")
	await _frames(3)
	_check(_count_pickups(world) - before == crate.loot_paths.size(), "no extra loot on the second try")
	_check(_state.has_flag(&"crate_1_taken") and not _state.has_flag(&"crate_2_taken"), "only that crate is marked taken")
	var inventory_before := player.inventory.potions
	for node in world.get_children():
		if node is Pickup and (node as Pickup).item.kind == ItemData.Kind.CONSUMABLE:
			node.global_position = player.global_position
	await _frames(8)
	_check(player.inventory.potions == inventory_before + 1, "walking into the crate's medkit collects it")
	await _free_main(main)


func _count_pickups(world: Node) -> int:
	var n := 0
	for child in world.get_children():
		if child is Pickup:
			n += 1
	return n


func _test_keycard_and_terminal() -> void:
	print("Keycard and terminal")
	_state.reset()
	var main := await _spawn_main()
	var world := main.get_node("World") as WorldFlow
	var wm := main.get_node("WaveManager") as WaveManager
	var player := main.get_node("Player") as Player
	var terminal := world.terminal
	_check(terminal.locked and terminal.current_prompt() == "Terminal locked: keycard required", "terminal starts locked")
	_check(not terminal.interact(player), "a locked terminal does nothing")
	_check(get_nodes_in_group("keycard").is_empty(), "no keycard before the arena is cleared")
	_put(player, Vector3(12.0, 0.1, 12.0))  # not on top of where the keycard will drop
	await _frames(3)

	wm.all_cleared.emit()
	await _frames(3)
	_check(_state.has_flag(&"arena_cleared"), "clearing the arena sets arena_cleared")
	_check(get_nodes_in_group("keycard").size() == 1, "the Warden's keycard appears")
	wm.all_cleared.emit()
	await _frames(3)
	_check(get_nodes_in_group("keycard").size() == 1, "only one keycard, even if the signal repeats")
	_check(terminal.locked, "terminal stays locked until the keycard is taken")

	_put(player, Vector3(0.0, 0.1, 0.0))
	await _frames(8)
	_check(_state.has_flag(&"has_keycard"), "walking onto the keycard picks it up")
	await _frames(3)
	_check(get_nodes_in_group("keycard").is_empty(), "the keycard disappears")
	_check(not terminal.locked, "the terminal unlocks")
	var used: Array = []
	_state.interacted.connect(func(id: StringName) -> void: used.append(id))
	_check(terminal.interact(player), "the terminal works with the keycard")
	_check(&"command_terminal" in used and _state.has_flag(&"command_terminal_used"), "it emits interacted and sets command_terminal_used")
	_check(not terminal.interact(player), "the terminal is one-shot")
	await _free_main(main)


func _test_persistence() -> void:
	print("Persistence across a scene reload")
	_state.reset()
	var main := await _spawn_main()
	var world := main.get_node("World") as WorldFlow
	var player := main.get_node("Player") as Player
	for id in [&"switch_1", &"switch_2", &"switch_3"]:
		_throw(world, player, id)
	world.crates[1].interact(player)
	await _frames(3)
	await _free_main(main)  # a death restart reloads the scene; WorldState is an autoload and survives

	var again := await _spawn_main()
	var world2 := again.get_node("World") as WorldFlow
	_check(world2.gate.is_open, "the gate is still open after the reload")
	await _frames(3)
	_check((world2.gate.get_node("GateBody/CollisionShape3D") as CollisionShape3D).disabled, "and no longer blocks")
	_check(world2.switches[0].is_on and world2.switches[1].is_on and world2.switches[2].is_on, "switches stay on")
	_check(world2.crates[1].is_used() and not world2.crates[0].is_used(), "an opened crate stays opened")
	var pickups_before := _count_pickups(world2)
	_check(not world2.crates[1].interact(again.get_node("Player")), "it cannot be looted again after the reload")
	_check(_count_pickups(world2) == pickups_before, "no loot reappears")
	var dumped: Dictionary = _state.to_dict()
	_state.reset()
	_check(not _state.has_flag(&"power_on"), "reset wipes the world state")
	_state.from_dict(dumped)
	_check(_state.has_flag(&"power_on") and _state.has_flag(&"crate_2_taken"), "to_dict / from_dict round trip")
	await _free_main(again)


func _test_courtyard_trigger() -> void:
	print("Courtyard trigger")
	_state.reset()
	var main := await _spawn_main()
	var world := main.get_node("World") as WorldFlow
	var wm := main.get_node("WaveManager") as WaveManager
	var player := main.get_node("Player") as Player
	_courtyard_events = 0
	_state.area_entered.connect(_count_courtyard)
	_check(not wm.has_started(), "no waves before the player reaches the courtyard")
	_put(player, Vector3(0.0, 0.1, 40.0))
	await _frames(10)
	_check(not wm.has_started(), "standing on the beach does not start waves")
	_put(player, Vector3(0.0, 0.1, 22.0))
	await _frames(10)
	_check(wm.has_started() and world.courtyard_started, "entering the courtyard starts the waves")
	_check(_courtyard_events == 1, "area_entered(courtyard) was emitted")
	var waited := 0
	while wm.current_wave < 1 and waited < 600:
		await physics_frame
		waited += 1
	_check(wm.current_wave == 1, "wave 1 spawns after the start delay")
	_put(player, Vector3(0.0, 0.1, 40.0))
	await _frames(6)
	_put(player, Vector3(0.0, 0.1, 22.0))
	await _frames(10)
	_check(_courtyard_events == 2, "re-entering emits again")
	_check(wm.current_wave == 1, "but the waves are not restarted (still wave 1)")
	await _free_main(main)

	# A won arena stays won: no waves again.
	_state.set_flag(&"arena_cleared", true)
	var won := await _spawn_main()
	var won_wm := won.get_node("WaveManager") as WaveManager
	_put(won.get_node("Player") as Player, Vector3(0.0, 0.1, 22.0))
	await _frames(10)
	_check(not won_wm.has_started(), "an already cleared arena does not start waves again")
	await _free_main(won)


func _test_teleport_guard() -> void:
	print("Teleport guard")
	_state.reset()
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	await _frames(5)
	var ability := player.get_node_or_null("TeleportAbility") as TeleportAbility
	_check(ability != null, "player has a TeleportAbility")
	if ability == null:
		await _free_main(main)
		return
	ability.rng.seed = 12345

	_put(player, Vector3(0.0, 0.1, 64.0))
	var all_on_beach := true
	for i in 40:
		var spot := ability.pick_destination(player)
		if spot.z < 31.0 or spot.z > 80.0 or absf(spot.x) > 42.0:
			all_on_beach = false
	_check(all_on_beach, "with the gate locked, a beach teleport stays on the beach (40 draws)")

	_state.set_flag(&"power_on", true)
	var reached_arena := false
	for i in 80:
		if ability.pick_destination(player).z < 27.0:
			reached_arena = true
	_check(reached_arena, "once the power is on, the beach teleport may also land in the arena")

	_state.reset()
	_put(player, Vector3(0.0, 0.1, 0.0))
	var inside_arena := true
	for i in 40:
		var spot := ability.pick_destination(player)
		if absf(spot.x) > 26.5 or absf(spot.z) > 26.5:
			inside_arena = false
	_check(inside_arena, "from inside the arena, destinations are still inside the arena")
	await _free_main(main)


func _count_courtyard(id: StringName) -> void:
	if id == &"courtyard":
		_courtyard_events += 1
