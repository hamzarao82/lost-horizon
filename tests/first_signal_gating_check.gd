extends SceneTree
## The First Signal no longer starts on arrival in a real New Game: it starts at the compound sign. Headless
## runs (every other suite) still start it as before. godot --headless --path . -s tests/first_signal_gating_check.gd

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node
var _captions: Array = []


func _initialize() -> void:
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
		await process_frame


func _fresh() -> void:
	_qm.reset()
	_qm.active.clear()
	_qm.completed.clear()
	_world.reset()
	_qm.tracker_first = &""


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_qm.caption_requested.connect(func(text: String, _s: float) -> void: _captions.append(text))
	await _frames(2)

	print("-- the rule")
	_check(RegionLabel.opening_pending_for(false, false, false), "a real New Game waits for the sign")
	_check(not RegionLabel.opening_pending_for(true, false, false), "a headless run never waits")
	_check(not RegionLabel.opening_pending_for(false, true, false), "once the opening has run, the quest is no longer held back by it")
	_check(not RegionLabel.opening_pending_for(false, false, true), "a known name never waits")

	print("-- headless still starts it (every other suite relies on this)")
	_qm.reset()
	_check(_qm.is_active(&"first_signal"), "reset starts the First Signal in a headless run")
	_check(_world.has_flag(RegionLabel.KNOWN_FLAG), "starting it marks the name as known")

	print("-- the sign")
	_fresh()
	var sign_node := OutpostSign.place(root, Vector3(0.0, 0.0, 20.0))
	await _frames(2)
	_check(not _qm.is_active(&"first_signal") and not _world.has_flag(RegionLabel.KNOWN_FLAG), "before the sign: no mission, no name")
	_captions.clear()
	sign_node.reveal()
	_check(_world.has_flag(RegionLabel.KNOWN_FLAG), "the sign sets outpost_name_known")
	_check(_qm.is_active(&"first_signal"), "the sign starts the First Signal")
	_check(_qm.is_active(&"search_outpost"), "the sign starts 'Search Outpost 17.'")
	_check(_qm.tracker_first == &"search_outpost", "which is pinned when nothing else is")
	var count_after_first: int = _captions.size()
	sign_node.reveal()
	_check(_captions.size() == count_after_first, "revealing again says nothing more and starts nothing twice")
	_check(_qm.active.has(&"first_signal") and _qm.completed.is_empty(), "no quest was restarted or completed by the second reveal")

	print("-- the sign does not steal another pin")
	_fresh()
	_qm.start_quest(&"opening_survival", true)
	_qm.tracker_first = &"opening_survival"
	var sign2 := OutpostSign.place(root, Vector3(5.0, 0.0, 20.0))
	await _frames(2)
	sign2.reveal()
	_check(_qm.tracker_first == &"opening_survival", "the opening's pin stays on the survival quest")
	_check(_qm.is_active(&"search_outpost"), "while the search quest still starts")

	print("-- the search quest completes by entering the research access facility")
	_world.emit_area_entered(&"area_c_research")
	await _frames(2)
	_check(_qm.is_completed(&"search_outpost"), "entering Area C completes 'Search Outpost 17.'")
	_check(_qm.is_active(&"first_signal"), "and the First Signal carries on")

	print("-- walking up to the sign (the real trigger)")
	_fresh()
	var sign3 := OutpostSign.place(root, Vector3(0.0, 0.0, 40.0))
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(2)
	sign3._on_body_entered(player)
	_check(_qm.is_active(&"first_signal"), "a Player entering the trigger reveals the name")
	var other := Node3D.new()
	root.add_child(other)
	_fresh()
	sign3.revealed = false
	sign3._on_body_entered(other as Node3D)
	_check(not _qm.is_active(&"first_signal"), "anything that is not the player does nothing")

	print("-- old saves keep working")
	_fresh()
	_qm.start_quest(&"first_signal")
	var progressed: Dictionary = _qm.to_dict()
	_world.reset()
	_qm.on_game_loaded(progressed)
	_check(_world.has_flag(RegionLabel.KNOWN_FLAG), "a save with the First Signal in progress gets the name flag")
	_check(_qm.is_active(&"first_signal"), "and the mission is still active")
	_fresh()
	_qm.start_quest(&"opening_survival", true)
	var opening_only: Dictionary = _qm.to_dict()
	opening_only["world"] = {"flags": []}
	_world.reset()
	_qm.on_game_loaded(opening_only)
	_check(not _world.has_flag(RegionLabel.KNOWN_FLAG), "a save made during the opening does not reveal the name early")
	_check(not _qm.is_active(&"first_signal"), "and does not start the First Signal")
	_fresh()
	_qm.start_quest(&"first_signal")
	_qm.completed.append(&"first_signal")
	_qm.active.erase(&"first_signal")
	var finished: Dictionary = _qm.to_dict()
	finished["world"] = {"flags": []}
	_world.reset()
	_qm.on_game_loaded(finished)
	_check(_world.has_flag(RegionLabel.KNOWN_FLAG), "a save with a finished mission gets the flag")

	print("-- ids are saveable")
	for id in [&"outpost_name_known", &"search_outpost", &"search_compound"]:
		var s := String(id)
		_check(s.length() <= 48 and s == s.to_lower().replace(" ", "_"), "'%s' fits WorldState's rule" % s)

	print("first_signal_gating_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
