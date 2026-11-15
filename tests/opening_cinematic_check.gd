extends SceneTree
## The opening speedboat/storm cinematic: timeline data, headless cheapness, the skip contract, and that
## `finished` always fires exactly once. Godot --headless --path . -s tests/opening_cinematic_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _run() -> void:
	# Timeline data, checked directly (cheap, no nodes).
	_check(OpeningTimeline.SCENES.size() == 12, "twelve scenes (%d)" % OpeningTimeline.SCENES.size())
	var total := OpeningTimeline.total_duration()
	_check(total >= 45.0 and total <= 70.0, "total duration is 45 to 70 s (%.1f)" % total)
	var ids := {}
	for scene in OpeningTimeline.SCENES:
		ids[scene["id"]] = true
	_check(ids.size() == 12, "every scene id is unique (%d distinct)" % ids.size())
	var prev_storm := -1.0
	var climbs := true
	for i in range(4, 9):
		var s: float = OpeningTimeline.SCENES[i]["storm"]
		if s < prev_storm:
			climbs = false
		prev_storm = s
	_check(climbs, "storm intensity does not fall from scene 5 to scene 9")
	var consecutive_differ := true
	for i in range(1, OpeningTimeline.SCENES.size()):
		if OpeningTimeline.SCENES[i]["cam_pos"] == OpeningTimeline.SCENES[i - 1]["cam_pos"]:
			consecutive_differ = false
	_check(consecutive_differ, "consecutive scenes use different camera positions")

	# Headless build: no SubViewport, no audio player (cheap).
	var a := OpeningCinematic.play(self)
	await process_frame
	_check(a is OpeningCinematic, "play() returns an OpeningCinematic")
	_check(a.get_child_count() <= 3, "headless builds only the cheap UI overlay, no SubViewport (%d children)" % a.get_child_count())
	var has_viewport := false
	for child in a.get_children():
		if child is SubViewportContainer:
			has_viewport = true
	_check(not has_viewport, "no SubViewportContainer on a headless run")

	# finished fires exactly once on a full, unskipped playthrough. (An Array, not a captured local int,
	# because a lambda's writes to an outer value-typed local do not reliably reach the outer scope.)
	var record_a := [0, null]  # [times fired, last "skipped" value]
	a.finished.connect(func(skipped: bool) -> void:
		record_a[0] += 1
		record_a[1] = skipped)
	var guard := 0
	while not a.is_done and guard < 400:
		a.advance(0.5)
		guard += 1
	_check(a.is_done, "the timeline reaches its end")
	_check(record_a[0] == 1 and record_a[1] == false, "finished fires exactly once, not skipped (%s)" % str(record_a))
	_check(paused == false, "the tree is unpaused after finishing (it was not paused before)")
	await process_frame
	_check(not is_instance_valid(a) or a.is_queued_for_deletion(), "the node frees itself")

	# Skipping jumps to the end quickly, fires finished(true) exactly once, and a second skip changes nothing.
	var b := OpeningCinematic.play(self)
	await process_frame
	var record_b := [0, null]
	b.finished.connect(func(skipped: bool) -> void:
		record_b[0] += 1
		record_b[1] = skipped)
	b.advance(1.0)
	b.skip()
	b.skip()  # a second skip before resolving must not double the count
	var guard_b := 0
	while not b.is_done and guard_b < 60:
		b.advance(0.5)
		guard_b += 1
	_check(b.is_done and record_b[0] == 1 and record_b[1] == true, "skip resolves once, finished(true) fires exactly once (%s)" % str(record_b))
	_check(guard_b < 60, "skipping reaches the end well before the full timeline would")

	# Freeing the node early (simulating a scene change) must not emit finished twice.
	var c := OpeningCinematic.play(self)
	await process_frame
	var record_c := [0]
	c.finished.connect(func(_skipped: bool) -> void: record_c[0] += 1)
	c.advance(1.0)
	c.queue_free()
	await process_frame
	_check(record_c[0] == 0, "freeing early does not itself emit finished (%d)" % record_c[0])

	# Camera shake: zero when calm, grows with the storm, never above the cap.
	_check(OpeningCinematic.shake_amplitude(0.0) == 0.0, "no camera shake in calm weather")
	_check(OpeningCinematic.shake_amplitude(0.5) > 0.0 and OpeningCinematic.shake_amplitude(0.9) > OpeningCinematic.shake_amplitude(0.5), "shake grows with the storm")
	_check(OpeningCinematic.shake_amplitude(5.0) <= OpeningCinematic.SHAKE_MAX + 0.0001 and OpeningCinematic.SHAKE_MAX <= 0.1, "shake is capped so shots stay readable (%.3f m)" % OpeningCinematic.shake_amplitude(5.0))

	# The payment bag: rests in calm scenes, slides when the waves hit, ends overboard, and is stable after.
	_check(OpeningCinematic.bag_position(&"aerial", 0.5) == OpeningCinematic.BAG_REST, "the bag rests in the calm scenes")
	_check(OpeningCinematic.bag_position(&"waves_hit", 0.0) == OpeningCinematic.BAG_REST and not OpeningCinematic.bag_position(&"waves_hit", 1.0).is_equal_approx(OpeningCinematic.BAG_REST), "the bag starts sliding on waves_hit")
	_check(OpeningCinematic.bag_position(&"overwhelmed", 1.0).is_equal_approx(OpeningCinematic.BAG_RAIL), "it is pinned at the rail while the boat is overwhelmed")
	_check(OpeningCinematic.bag_position(&"thrown_overboard", 1.0).is_equal_approx(OpeningCinematic.BAG_OVERBOARD), "it leaves the boat on thrown_overboard")
	_check(OpeningCinematic.bag_position(&"to_black", 0.3) == OpeningCinematic.BAG_OVERBOARD, "and stays gone afterwards")

	# The underwater muffle on the Master bus is added in thrown_overboard and ALWAYS removed again:
	# on a normal finish, on a skip, and when the node is freed early.
	var base_effects := AudioServer.get_bus_effect_count(0)
	var m1 := OpeningCinematic.play(self)
	await process_frame
	var g1 := 0
	while m1.current_scene_id() != &"thrown_overboard" and g1 < 200:
		m1.advance(0.5)
		g1 += 1
	_check(m1.muffle_active() and AudioServer.get_bus_effect_count(0) == base_effects + 1, "the muffle is on during thrown_overboard")
	var g1b := 0
	while not m1.is_done and g1b < 200:
		m1.advance(0.5)
		g1b += 1
	await process_frame
	_check(AudioServer.get_bus_effect_count(0) == base_effects, "the muffle is gone after a normal finish")

	var m2 := OpeningCinematic.play(self)
	await process_frame
	var g2 := 0
	while m2.current_scene_id() != &"thrown_overboard" and g2 < 200:
		m2.advance(0.5)
		g2 += 1
	m2.skip()
	var g2b := 0
	while not m2.is_done and g2b < 60:
		m2.advance(0.5)
		g2b += 1
	await process_frame
	_check(AudioServer.get_bus_effect_count(0) == base_effects, "the muffle is gone after a skip in the middle of it")

	var m3 := OpeningCinematic.play(self)
	await process_frame
	var g3 := 0
	while m3.current_scene_id() != &"thrown_overboard" and g3 < 200:
		m3.advance(0.5)
		g3 += 1
	_check(AudioServer.get_bus_effect_count(0) == base_effects + 1, "the muffle is on again for a third run")
	m3.queue_free()
	await process_frame
	await process_frame
	_check(AudioServer.get_bus_effect_count(0) == base_effects, "the muffle is gone when the node is freed early")
	paused = false

	print("opening_cinematic_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
