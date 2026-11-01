extends SceneTree
## Windowed timing of ArenaDecor alone (needs a real display):
##   godot --path . -s tests/decor_timing.gd
## Builds the decor once synchronously (the old single-frame behaviour) and once staged, and prints
## the worst frame time and per-stage cost of each.


func _initialize() -> void:
	_run.call_deferred()


func _measure(synchronous: bool) -> Dictionary:
	ArenaDecor.build_synchronously = synchronous
	var holder := Node3D.new()
	root.add_child(holder)
	var camera := Camera3D.new()
	holder.add_child(camera)
	camera.position = Vector3(0, 3, 6)
	camera.look_at(Vector3(0, 1, 0))
	var decor := ArenaDecor.new()
	var last := Time.get_ticks_usec()
	holder.add_child(decor)  # _ready starts the build
	var frames := 0
	var worst := (Time.get_ticks_usec() - last) / 1000.0  # the add_child frame itself
	while not decor.is_built() and frames < 600:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
	# let the first presented frames happen too: shader compile shows up here
	for i in 5:
		await process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	var result := {"worst_frame_ms": worst, "frames": frames, "stage_ms": decor.stage_ms.duplicate()}
	holder.queue_free()
	await process_frame
	return result


func _run() -> void:
	print("DECOR adapter=%s" % RenderingServer.get_video_adapter_name())
	for synchronous in [true, false, true, false]:
		var r: Dictionary = await _measure(synchronous)
		var stages: PackedStringArray = []
		for ms in r["stage_ms"]:
			stages.append("%.1f" % ms)
		print("DECOR %s worst_frame_ms=%.1f frames_to_build=%d stage_ms=[%s]" % [
			"sync  " if synchronous else "staged", r["worst_frame_ms"], r["frames"], ", ".join(stages)])
	quit()
