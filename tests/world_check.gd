extends SceneTree
## Milestone 3 world checks (areas, boundaries, triggers, card reader, encounter, interactables, flags):
##   godot --headless --path . -s tests/world_check.gd

var _failures: int = 0
var _checks: int = 0
var _state: Node


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


func _spawn_main() -> Node:
	_state = root.get_node("WorldState")
	_state.reset()
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(4)
	return main


func _find(id: StringName) -> Interactable:
	for node in get_nodes_in_group("interactables"):
		var item := node as Interactable
		if item != null and item.interaction_id == id:
			return item
	return null


func _ray_hit(main: Node, from: Vector3, to: Vector3) -> String:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit: Dictionary = main.get_world_3d().direct_space_state.intersect_ray(query)
	return "" if hit.is_empty() else String((hit["collider"] as Node).name)


func _run() -> void:
	var main := await _spawn_main()
	var out := main.get_node("Outpost17") as Outpost17
	var player := main.get_node("Player") as Player

	print("Areas")
	var names: Array[String] = []
	for id: StringName in Outpost17.AREAS:
		names.append(Outpost17.AREAS[id]["name"])
	_check(Outpost17.AREAS.size() == 4 and names.has("Outer Perimeter") and names.has("Military Compound")
			and names.has("Research Access Facility") and names.has("Command Center"), "four areas with the contract names")
	_check(out.location_at(Vector3(0, 0, 40)) == "Outer Perimeter", "location_at: beach is the Outer Perimeter")
	_check(out.location_at(Vector3(0, 0, 0)) == "Military Compound", "location_at: courtyard is the Military Compound")
	_check(out.location_at(Vector3(0, 0, -45)) == "Research Access Facility", "location_at: Area C")
	_check(out.location_at(Vector3(0, 0, -80)) == "Command Center", "location_at: Area D")
	_check(out.location_at(Vector3(0, 0, -120)) == "", "location_at: outside every area is empty")

	print("Boundaries and doors")
	await _frames(2)
	_check(_ray_hit(main, Vector3(-30, 1, -46), Vector3(0, 1, -46)) == "WallCW", "Area C west wall blocks")
	_check(_ray_hit(main, Vector3(30, 1, -77), Vector3(0, 1, -77)) == "WallDE", "Area D east wall blocks")
	_check(_ray_hit(main, Vector3(0, 1, -100), Vector3(0, 1, -80)) == "WallDN", "Area D north wall blocks")
	_check(_ray_hit(main, Vector3(-5, 1, -25), Vector3(-5, 1, -35)) == "WallN", "courtyard north wall (left part) blocks")
	_check(_ray_hit(main, Vector3(25, 1, -25), Vector3(25, 1, -35)) == "WallN2", "courtyard north wall (right part) blocks")
	_check(_ray_hit(main, Vector3(12, 1, -25), Vector3(12, 1, -35)) == "DoorBody", "the B-C gap is closed by the door")
	var bc := out.doors[&"bc"] as Door
	var cd := out.doors[&"cd"] as Door
	_check(bc.locked and not bc.is_open, "door B-C starts locked (needs the access card)")
	_check(cd.locked, "door C-D starts locked (needs comms power)")
	_check(_ray_hit(main, Vector3(-5, 1, -60), Vector3(-5, 1, -64)) == "WallCDL", "the C-D partition blocks beside the door")

	print("Triggers")
	var entered: Array[StringName] = []
	_state.area_entered.connect(func(id: StringName) -> void: entered.append(id))
	player.global_position = Vector3(0, 0.1, -46)
	await _frames(4)
	_check(entered.count(&"area_c_research") == 1, "walking into Area C emits area_entered once (%s)" % [entered])
	_check(_state.has_flag(&"discovered_area_c_research"), "and sets discovered_area_c_research")
	await _frames(4)
	_check(entered.count(&"area_c_research") == 1, "standing inside does not repeat it")
	player.global_position = Vector3(0, 0.1, 0)
	await _frames(4)
	player.global_position = Vector3(0, 0.1, -46)
	await _frames(4)
	_check(entered.count(&"area_c_research") == 2, "leaving and re-entering emits again")
	player.global_position = Vector3(0, 0.1, -77)
	await _frames(4)
	_check(entered.has(&"area_d_command") and _state.has_flag(&"discovered_area_d_command"), "Area D trigger works")
	(out.triggers[&"area_a_perimeter"] as AreaTrigger).report_entered()
	_check(_state.has_flag(&"discovered_area_a_perimeter"), "Area A trigger reports through report_entered()")
	player.global_position = Vector3(0, 0.1, 0)
	await _frames(3)

	print("Card reader and door")
	var reader := _find(&"card_reader_c") as CardReader
	_check(reader != null and reader.locked, "card reader is locked without the access card")
	_check(not reader.interact(player), "using a locked reader does nothing")
	_state.set_flag(&"has_access_card", true)
	_check(not reader.locked and not bc.locked, "the access card unlocks the reader and the door")
	_check(reader.interact(player), "the reader accepts the card")
	await _frames(3)
	_check(bc.is_open and _state.has_flag(&"door_bc_open") and _state.has_flag(&"reader_card_reader_c_used"), "door B-C opens and the flags are set")
	_check(_ray_hit(main, Vector3(12, 1, -25), Vector3(12, 1, -35)) == "", "the opening is passable")

	print("Encounter")
	_check(get_nodes_in_group("enemies").is_empty(), "no encounter enemies exist before the player enters the compound")
	_state.emit_area_entered(&"area_b_compound")
	await _frames(2)
	_check(get_nodes_in_group("enemies").filter(func(e: Node) -> bool: return not e.has_method("_has_route") or not e._has_route()).size() == 2, "entering the compound spawns the squad (2)")
	_check(Enemy.active_patrollers == 2, "and wakes the two research-wing guards")
	_state.emit_area_entered(&"area_b_compound")
	await _frames(2)
	_check(get_nodes_in_group("enemies").size() == 4 and Enemy.active_patrollers == 2, "it spawns only once")
	var kill := load("res://resources/attacks/heavy_1.tres") as AttackData
	for enemy in get_nodes_in_group("enemies"):
		for i in 5:
			(enemy as Enemy).receive_hit(kill, player.global_position)
	await _frames(3)
	_check(_state.has_flag(&"encounter_b_cleared"), "killing the squad sets encounter_b_cleared")
	var card: Keycard = null
	for child in out.get_children():
		if child is Keycard:
			card = child
	_check(card != null and card.flag_id == &"has_access_card", "the squad drops the access card")
	_state.set_flag(&"has_access_card", false)
	if card:
		card._on_body_entered(player)
	_check(_state.has_flag(&"has_access_card"), "picking up the card sets has_access_card")

	print("Interactables and contract ids")
	for id: StringName in [&"checkpoint_desk", &"checkpoint_b", &"supply_crate_b1", &"supply_crate_b2", &"supply_crate_c1",
			&"card_reader_c", &"log_sequence", &"security_panel", &"power_switch_a", &"power_switch_b", &"power_switch_c",
			&"military_terminal", &"log_missing_security", &"command_terminal_d", &"door_bc", &"door_cd"]:
		_check(_find(id) != null, "interactable %s exists" % id)
	_check((_find(&"checkpoint_b") as Checkpoint).interact(player) and _state.has_flag(&"checkpoint_b"), "checkpoint sets checkpoint_b")
	_check((_find(&"security_panel") as SecurityPanel).interact(player) and _state.has_flag(&"panel_inspected"), "security panel sets panel_inspected")
	_check((_find(&"log_sequence") as LoreDocument).interact(player) and _state.has_flag(&"doc_log_sequence_found"), "document sets doc_log_sequence_found")
	var terminal := _find(&"military_terminal") as Terminal
	_check(terminal.locked and not terminal.interact(player), "military terminal is offline without power")
	_state.set_flag(&"comms_power_on", true)
	_check(not terminal.locked and terminal.interact(player) and _state.has_flag(&"next_location_unlocked"), "with power it unlocks the next location")
	_check(not cd.locked, "comms power also unlocks door C-D")

	print("Power switches")
	_state.set_flag(&"comms_power_on", false)
	var sw_a := _find(&"power_switch_a") as PowerSwitch
	var sw_b := _find(&"power_switch_b") as PowerSwitch
	sw_a.set_on(false)
	sw_b.set_on(false)
	_check(sw_a.interact(player) and sw_a.is_on, "without a puzzle node a switch just turns on")
	var fake := _FakePuzzle.new()
	fake.add_to_group("sequence_puzzle")
	root.add_child(fake)
	fake.accept = false
	sw_b.interact(player)
	_check(not sw_b.is_on and not sw_a.is_on, "a rejected press resets every switch")
	fake.accept = true
	sw_b.interact(player)
	_check(sw_b.is_on and fake.pressed == [&"power_switch_b", &"power_switch_b"], "an accepted press lights the switch and reports its id")
	fake.queue_free()

	print("Flags persist")
	var snapshot: Dictionary = _state.to_dict()
	_state.reset()
	_check(not _state.has_flag(&"door_bc_open"), "reset clears the flags")
	_state.from_dict(snapshot)
	_check(_state.has_flag(&"door_bc_open") and _state.has_flag(&"encounter_b_cleared") and _state.has_flag(&"discovered_area_c_research"),
			"to_dict / from_dict round-trips the new flags")

	main.queue_free()
	await _frames(3)
	_state.reset()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


class _FakePuzzle extends Node:
	var accept: bool = true
	var pressed: Array = []

	func try_press(id: StringName) -> bool:
		pressed.append(id)
		return accept
