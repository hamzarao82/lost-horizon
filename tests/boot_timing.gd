extends SceneTree
## Windowed timing of the "old" startup: load Main synchronously, instance it, add it, then record
## frame times. Needs a real display (not --headless):
##   godot --path . -s tests/boot_timing.gd
## Prints: BOOT_DIRECT load_ms instantiate_ms add_ms first_frames_max_ms frames_over_33ms
## For the real boot flow run the game itself with:  godot --path . -- --boot-report

const FRAMES: int = 240


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "build_synchronously" in ArenaDecor:
		ArenaDecor.build_synchronously = true  # the pre-boot behaviour: whole decor in one frame
	var t0 := Time.get_ticks_usec()
	var packed := load("res://scenes/main/Main.tscn") as PackedScene
	var t1 := Time.get_ticks_usec()
	var main := packed.instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	var t2 := Time.get_ticks_usec()
	root.add_child(main)  # runs every _ready, including the decor build
	var t3 := Time.get_ticks_usec()
	var worst := 0.0
	var over := 0
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		worst = maxf(worst, ms)
		if ms > 33.4:
			over += 1
	print("BOOT_DIRECT adapter=%s" % RenderingServer.get_video_adapter_name())
	print("BOOT_DIRECT load_ms=%.1f instantiate_ms=%.1f add_child_ms=%.1f worst_frame_ms=%.1f frames_over_33ms=%d of %d" % [
		(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, worst, over, FRAMES])
	quit()
