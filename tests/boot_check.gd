extends SceneTree
## Headless checks for the boot screen and the staged decor build:
##   godot --headless --path . -s tests/boot_check.gd
## Exits non-zero if any check fails.

const BOOT_SCENE: String = "res://scenes/boot/Boot.tscn"
const STUB: String = "res://tests/_warmup_stub.gd"
const MAX_BOOT_FRAMES: int = 3000
## Generous: headless boots add Main (including a one-frame synchronous decor build) in one frame.
const MAX_FRAME_MS: float = 3000.0

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
		await process_frame


func _run() -> void:
	HitStop.enabled = false
	await _test_boot_flow()
	await _test_boot_failure_and_retry()
	await _test_decor_staged()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _new_boot() -> Node:
	var boot := (load(BOOT_SCENE) as PackedScene).instantiate()
	boot.warmup_script_path = STUB
	return boot


func _test_boot_flow() -> void:
	print("Boot flow")
	var boot := _new_boot()
	var values: Array[float] = []
	var finished_main: Array = []
	boot.progress_changed.connect(func(v: float) -> void: values.append(v))
	boot.finished.connect(func(m: Node) -> void: finished_main.append(m))
	var stub_before: int = load(STUB).get("ran")
	root.add_child(boot)

	var worst_ms := 0.0
	var last := Time.get_ticks_usec()
	var frames := 0
	var disabled_while_booting := true
	var saw_building := false
	while finished_main.is_empty() and frames < MAX_BOOT_FRAMES and boot.phase != boot.Phase.ERROR:
		await process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		worst_ms = maxf(worst_ms, (now - last) / 1000.0)
		last = now
		if boot.main_node != null and boot.phase in [boot.Phase.BUILDING, boot.Phase.WARM_RENDER, boot.Phase.SETTLING]:
			saw_building = true
			disabled_while_booting = disabled_while_booting and boot.main_node.process_mode == Node.PROCESS_MODE_DISABLED

	_check(boot.phase != boot.Phase.ERROR, "boot finishes without an error (%s)" % boot.error_text)
	_check(finished_main.size() == 1, "finished signal fires exactly once")
	_check(frames < MAX_BOOT_FRAMES, "boot completes (%d frames)" % frames)
	_check(worst_ms < MAX_FRAME_MS, "no single frame froze for seconds (worst %.0f ms)" % worst_ms)

	var monotonic := true
	for i in range(1, values.size()):
		monotonic = monotonic and values[i] >= values[i - 1]
	_check(values.size() >= 5, "progress is reported in several steps (%d)" % values.size())
	_check(monotonic, "progress never moves backwards")
	_check(not values.is_empty() and is_equal_approx(values[-1], 1.0), "progress reaches 1.0")
	_check(boot.report.has("load_done_ms") and boot.report.has("warm_done_ms") and boot.report.has("playable_ms"),
			"boot records its timing milestones")
	var stub_after: int = load(STUB).get("ran")
	_check(stub_after - stub_before == 3, "external warm-up steps ran (%d)" % (stub_after - stub_before))
	var stub_frames: Array = load(STUB).get("frames")
	var distinct := {}
	for f in stub_frames.slice(stub_frames.size() - 3):
		distinct[f] = true
	_check(distinct.size() == 3, "external warm-up steps run one per frame (%s)" % str(stub_frames.slice(stub_frames.size() - 3)))

	var main := finished_main[0] as Node if not finished_main.is_empty() else null
	_check(main != null and main.get_node_or_null("Player") != null, "Main was handed over with its Player")
	_check(main != null and current_scene == main, "Main is the current scene (reload_current_scene restarts Main)")
	_check(saw_building and disabled_while_booting, "Main stays disabled behind the boot screen")
	_check(main != null and main.process_mode == Node.PROCESS_MODE_INHERIT, "Main is enabled when the game starts")
	_check(main != null and main.get_node("Decor").is_built(), "the decor finished building before the game started")

	var waited := 0
	while is_instance_valid(boot) and waited < 200:
		await process_frame
		waited += 1
	_check(not is_instance_valid(boot), "the boot screen removes itself after the fade")
	await _frames(3)
	_check(get_nodes_in_group("enemies").is_empty(), "warm-up enemies were removed before play")
	_check(Enemy._alive == 0, "no enemy bookkeeping leaked from the warm-up (alive=%d)" % Enemy._alive)
	var leftover_pickups := 0
	if main != null:
		for child in main.get_children():
			if child is Pickup:
				leftover_pickups += 1
	_check(leftover_pickups == 0, "the warm-up pickup was removed")

	if main != null:
		main.queue_free()
	await _frames(3)


func _test_boot_failure_and_retry() -> void:
	print("Boot failure and retry")
	var boot := _new_boot()
	boot.extra_paths = PackedStringArray(["res://does/not/exist_anywhere.tres"])
	var messages: Array[String] = []
	boot.failed.connect(func(m: String) -> void: messages.append(m))
	var finished_main: Array = []
	boot.finished.connect(func(m: Node) -> void: finished_main.append(m))
	root.add_child(boot)
	var frames := 0
	while boot.phase != boot.Phase.ERROR and frames < 600:
		await process_frame
		frames += 1
	_check(boot.phase == boot.Phase.ERROR, "a missing resource puts the boot screen into the error state")
	_check(messages.size() == 1 and messages[0].contains("exist_anywhere"), "the error names the missing file")
	_check(boot._retry.visible and boot._error.visible, "the Retry button and error text are shown")
	_check(finished_main.is_empty(), "the game does not start after a failure")

	boot.extra_paths = PackedStringArray()
	boot._on_retry()
	frames = 0
	while finished_main.is_empty() and frames < MAX_BOOT_FRAMES and boot.phase != boot.Phase.ERROR:
		await process_frame
		frames += 1
	_check(finished_main.size() == 1, "Retry recovers and finishes the boot")
	_check(not boot._retry.visible, "the Retry button hides again")
	var waited := 0
	while is_instance_valid(boot) and waited < 200:
		await process_frame
		waited += 1
	if not finished_main.is_empty():
		(finished_main[0] as Node).queue_free()
	await _frames(3)


func _test_decor_staged() -> void:
	print("Staged decor")
	ArenaDecor.force_staged = true
	var holder := Node3D.new()
	root.add_child(holder)
	var decor := ArenaDecor.new()
	var finished_count := [0]
	decor.build_finished.connect(func() -> void: finished_count[0] += 1)
	holder.add_child(decor)
	_check(not decor.is_built(), "the decor is not built in the frame it enters the tree")
	var frames := 0
	while not decor.is_built() and frames < 200:
		await process_frame
		frames += 1
	_check(decor.is_built() and frames >= 5, "the build is spread over several frames (%d)" % frames)
	_check(finished_count[0] == 1, "build_finished fires once")
	_check(decor.stage_ms.size() >= 8, "stage costs are recorded (%d stages)" % decor.stage_ms.size())
	_check(decor.get_node_or_null("Props") != null, "props exist after the staged build")

	# Changing quality mid-build must supersede the old build, not duplicate its nodes.
	decor.set_quality(2)
	await _frames(2)
	decor.set_quality(0)
	await _frames(2)
	decor.set_quality(1)
	frames = 0
	while not decor.is_built() and frames < 200:
		await process_frame
		frames += 1
	await _frames(3)
	var props := 0
	for child in decor.get_children():
		if child.name.begins_with("Props"):
			props += 1
	_check(decor.is_built() and props == 1, "a superseded build leaves exactly one Props mesh (%d)" % props)

	# Freed part-way through a build: nothing should blow up.
	var second := ArenaDecor.new()
	holder.add_child(second)
	await _frames(2)
	second.queue_free()
	await _frames(4)
	_check(true, "freeing the decor mid-build is safe")

	ArenaDecor.force_staged = false
	holder.queue_free()
	await _frames(2)
