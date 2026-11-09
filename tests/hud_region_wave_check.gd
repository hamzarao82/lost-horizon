extends SceneTree
## The arena wave counter belongs to Outpost 17 only.
## godot --headless --path . -s tests/hud_region_wave_check.gd

var _failures: int = 0
var _checks: int = 0


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


func _run() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	for i in 6:
		await physics_frame
	var rm := root.get_node_or_null("RegionManager")
	var huds: Array[Node] = main.find_children("*", "Hud", true, false)
	_check(rm != null and huds.size() == 1, "Main has one HUD and a RegionManager")
	if rm == null or huds.size() != 1:
		quit(1)
		return
	var hud: Hud = huds[0]
	var label: Label = hud.get("_wave_label")
	_check(label.text.begins_with("Wave"), "Outpost 17 shows the wave counter (%s)" % label.text)
	rm.current_region_id = &"dead_coast"
	rm.region_changed.emit(&"outpost_17", &"dead_coast")
	_check(label.text == "", "Dead Coast shows no wave counter")
	rm.current_region_id = &"blackwood"
	rm.region_changed.emit(&"dead_coast", &"blackwood")
	_check(label.text == "", "Blackwood shows no wave counter")
	rm.current_region_id = &"outpost_17"
	rm.region_changed.emit(&"blackwood", &"outpost_17")
	_check(label.text.begins_with("Wave"), "returning to Outpost 17 brings the counter back")
	# A running stage encounter shows its own counter, counting only its own enemies.
	rm.current_region_id = &"dead_coast"
	var stage := StageWaves.attach(main, &"dead_coast")
	await physics_frame
	stage.state = StageWaves.State.ACTIVE
	stage.current_wave = 2
	rm.region_changed.emit(&"outpost_17", &"dead_coast")
	_check(label.text == "Wave 2/3  Enemies: 0", "an active stage encounter shows its own counter (%s)" % label.text)
	stage.state = StageWaves.State.COMPLETE
	rm.region_changed.emit(&"dead_coast", &"dead_coast")
	_check(label.text == "", "a finished encounter shows no counter")
	stage.queue_free()
	print("hud_region_wave_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
