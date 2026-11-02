extends SceneTree
## Full playthrough of the main quest "The First Signal" with real game events:
##   godot --headless --path . -s tests/playthrough_bot.gd
## The bot teleports the player body to each place (area triggers and pickups fire as they do in play),
## calls Interactable.interact() the way the Interactor does, and kills enemies through receive_hit().
## Quest progress is never set directly. Each step prints a BOT line and asserts what it must achieve.

const HEAVY: String = "res://resources/attacks/heavy_1.tres"
const FIRST: StringName = &"first_signal"

var _checks: int = 0
var _failures: int = 0
var _main: Node
var _player: Player
var _qm: Node
var _world: Node
var _sm: Node


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


func _step(text: String) -> void:
	print("BOT ", text)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _move(position: Vector3) -> void:
	_player.global_position = position
	_player.velocity = Vector3.ZERO
	await _frames(8)  # area triggers and pickups react on the next physics steps


func _interactable(id: StringName) -> Interactable:
	for node in get_nodes_in_group("interactables"):
		var item := node as Interactable
		if item != null and item.interaction_id == id:
			return item
	return null


func _use(id: StringName) -> bool:
	var item := _interactable(id)
	if item == null:
		print("  FAIL no interactable with id ", id)
		_failures += 1
		_checks += 1
		return false
	return item.interact(_player)


## Is objective `index` of the main quest done? (A completed quest has all of them done.)
func _done(index: int) -> bool:
	if _qm.is_completed(FIRST):
		return true
	if not _qm.is_active(FIRST):
		return false
	return bool(_qm.active[FIRST]["done"][index])


func _kill_everything() -> int:
	var killed := 0
	var heavy := load(HEAVY) as AttackData
	for node in get_nodes_in_group("enemies").duplicate():
		var enemy := node as Enemy
		if enemy == null:
			continue
		for i in 20:
			if enemy.is_dead():
				break
			enemy.receive_hit(heavy, _player.global_position)
			await physics_frame
		if enemy.is_dead():
			killed += 1
	return killed


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_sm = root.get_node("SaveManager")
	_sm.reset_runtime_state()  # a fresh run: the quest line starts again
	_qm.intro_done = true
	_check_pointer_placement()

	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(6)
	_player = _main.get_node("Player") as Player
	_player.health.max_health = 1.0e6
	_player.health.health = 1.0e6
	_check(_qm.is_active(FIRST), "the main quest starts with the game")

	_step("1 reach the outer perimeter")
	await _move(Vector3(0.0, 0.1, 38.0))
	_check(_done(0), "entering Area A completes 'Reach the outer perimeter'")

	_step("2 investigate the abandoned checkpoint")
	_check(_use(&"checkpoint_desk"), "the checkpoint desk can be read")
	await _frames(2)
	_check(_done(1), "'Investigate the abandoned checkpoint' is done")

	_step("3 find the source of the transmission")
	_check(_use(&"radio"), "the emergency radio can be used")
	await _frames(2)
	_check(_done(2), "'Find the source of the transmission' is done")

	_step("4 enter the courtyard, eliminate the soldiers")
	await _move(Vector3(0.0, 0.1, 22.0))  # the real courtyard trigger: wakes the squad and the guards
	var waves := _main.get_node_or_null("WaveManager")
	if waves:
		waves.free()  # the arena waves are not part of this quest
	await _frames(10)
	var present := get_nodes_in_group("enemies").size()
	_check(present >= 4, "entering the compound wakes the squad and the research-wing guards (%d enemies)" % present)
	var killed := await _kill_everything()
	await _frames(6)
	_check(killed >= 4, "the bot defeats %d enemies" % killed)
	_check(_done(3), "'Eliminate the hostile soldiers' is done (4 kills)")

	_step("5 locate the security access card")
	var card: Node3D = null
	for node in root.find_children("*", "Keycard", true, false):
		card = node as Node3D
	_check(card != null, "the squad drops an access card")
	if card != null:
		await _move(card.global_position)
		await _frames(4)
	_check(_world.has_flag(&"has_access_card"), "walking onto it sets has_access_card")
	_check(_qm.has_quest_item(&"access_card"), "and the access card is a quest item")
	_check(_done(4), "'Locate the security access card' is done")

	_step("6 open the door to the research facility")
	await _move(Vector3(9.0, 0.1, -27.0))
	_check(_use(&"card_reader_c"), "the card reader accepts the card")
	await _frames(4)
	_check(_world.has_flag(&"door_bc_open"), "door B-C is open")

	_step("7 discover the restricted research facility")
	await _move(Vector3(12.0, 0.1, -40.0))
	_check(_done(7), "entering Area C completes 'Discover the restricted research facility'")

	_step("8 restore power: panel, then the switches in order B, A, C")
	var puzzle := get_first_node_in_group("sequence_puzzle") as SequencePuzzle
	_check(puzzle != null, "the game creates the sequence puzzle node itself (regression guard: it once did not)")
	puzzle.reset_progress()
	await _move(Vector3(12.0, 0.1, -57.0))
	_use(&"power_switch_b")  # before the panel has been inspected
	_check(puzzle.current_step() == 0 and not _world.has_flag(&"comms_power_on"), "a switch pressed before the panel is inspected does nothing")
	_check(_use(&"security_panel"), "the damaged panel can be inspected")
	_check(_world.has_flag(&"panel_inspected"), "inspecting it sets panel_inspected")
	if puzzle != null:
		puzzle.reset_progress()
		_use(&"power_switch_a")  # wrong first switch
		_check(puzzle.current_step() == 0 and not _world.has_flag(&"comms_power_on"), "a wrong first press leaves nothing set")
		_use(&"power_switch_b")
		_check(puzzle.current_step() == 1, "switch B is correct first")
		_use(&"power_switch_c")  # out of order: resets
		_check(puzzle.current_step() == 0, "pressing C too early resets the sequence")
		_use(&"power_switch_b")
		_use(&"power_switch_a")
		_check(puzzle.current_step() == 2, "B then A advances to step 2")
		_use(&"power_switch_c")
		await _frames(3)
		_check(puzzle.is_solved() and _world.has_flag(&"comms_power_on"), "B, A, C restores power")
	_check(_done(5), "'Restore power to the communications facility' is done")

	_step("optional: the missing security log in Area D")
	await _move(Vector3(0.0, 0.1, -70.0))  # Area D: the Warden encounter starts here
	_player.grant_invulnerability(999.0)
	await _frames(20)
	var wardens := get_nodes_in_group("boss").size()
	_check(wardens == 1, "entering Area D starts the Warden encounter with exactly one Warden (%d)" % wardens)
	await _move(Vector3(-19.0, 0.1, -88.0))
	_check(_use(&"log_missing_security"), "the missing security log can be read")
	await _frames(2)
	_check(_world.has_flag(&"doc_log_missing_security_found"), "it is recorded as found")

	_step("9 access the military terminal")
	await _move(Vector3(17.5, 0.1, -57.0))
	_check(_use(&"military_terminal"), "the powered terminal can be used")
	await _frames(4)
	_check(_world.has_flag(&"next_location_unlocked"), "it unlocks the next mission location")

	_step("check the result")
	await _frames(4)
	var count := 0
	for id in _qm.completed:
		if id == FIRST:
			count += 1
	_check(count == 1, "'The First Signal' is completed exactly once")
	_check(_qm._rewarded.count(FIRST) == 1, "its reward was granted exactly once")
	_check(_qm.has_quest_item(&"access_card"), "the access card is still held")
	var optional_key: String = _qm._history_key(ObjectiveData.Type.INTERACT, &"log_missing_security")
	_check(_qm._history.has(optional_key), "the optional objective (missing log) was recorded")

	_step("save at a checkpoint and load")
	_check(_sm.activate_checkpoint("checkpoint_bot"), "a checkpoint writes the save")
	_sm.reset_runtime_state()
	_check(not _qm.is_completed(FIRST), "a deliberate restart forgets the quest")
	_check(_sm.load_game(), "the save loads")
	_check(_qm.is_completed(FIRST), "loading keeps 'The First Signal' completed")
	_sm.delete_save()
	_sm.reset_runtime_state()

	if is_instance_valid(_main):
		_main.queue_free()
	await _frames(3)
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## The pointer keeps clear of the HUD for every direction, on mouse and touch layouts.
func _check_pointer_placement() -> void:
	var clear_all := true
	var inside_all := true
	for viewport in [Vector2(1280, 720), Vector2(1600, 720)]:
		for touch in [false, true]:
			var rects := ObjectivePointer.avoid_rects(viewport, touch)
			for deg in range(0, 360, 15):
				var pos := ObjectivePointer.place(Vector2.from_angle(deg_to_rad(deg)), viewport, touch)
				var box := Rect2(pos - ObjectivePointer.SIZE * 0.5, ObjectivePointer.SIZE)
				if not Rect2(Vector2.ZERO, viewport).encloses(box):
					inside_all = false
				for rect in rects:
					if box.intersects(rect) and (pos - viewport * 0.5).length() > ObjectivePointer.MIN_RADIUS + 1.0:
						clear_all = false
	_check(inside_all, "the objective pointer always stays on screen (1280x720, 1600x720, mouse and touch)")
	_check(clear_all, "and keeps clear of the HUD bands and the touch buttons")
