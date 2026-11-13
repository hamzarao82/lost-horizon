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

	print("opening_cinematic_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
