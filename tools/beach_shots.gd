extends SceneTree
## Windowed captures of the opening beach mini-scene at several points on its clock (the protagonist's wake, the
## guard and the workers arriving). The 3D view is read from the scene's own SubViewport.
##   godot --path . --resolution 1280x720 -s tools/beach_shots.gd
## Set BEACH_SHOTS_OUT to a folder (default user://beach_shots/).

var OUT: String = OS.get_environment("BEACH_SHOTS_OUT") if OS.get_environment("BEACH_SHOTS_OUT") != "" else "user://beach_shots/"
const SHOT_TIMES: Array[float] = [2.0, 5.5, 8.2, 11.0]


func _initialize() -> void:
	if not OUT.ends_with("/"):
		OUT += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT) if OUT.begins_with("user://") else OUT)
	Player.require_mouse_capture = false
	HitStop.enabled = false
	_run.call_deferred()


func _run() -> void:
	var beach := OpeningBeach.new()
	root.add_child(beach)
	var started := 0.0
	for i in SHOT_TIMES.size():
		var wait: float = SHOT_TIMES[i] - started
		await create_timer(wait).timeout
		started = SHOT_TIMES[i]
		await process_frame
		var image := beach._viewport.get_texture().get_image()
		var path := "%s%d_beach_%.1fs.png" % [OUT, i + 1, SHOT_TIMES[i]]
		image.save_png(path if not OUT.begins_with("user://") else ProjectSettings.globalize_path(path))
		print("SHOT ", path)
	quit(0)
