extends SceneTree
## Windowed screenshots of the beach approach (Area A): the spawn view, the gap, the rise and the fence.
##   godot --path . --resolution 1280x720 -s tools/approach_shots.gd
## Set APPROACH_SHOTS_OUT to a folder; the default is user://approach_shots/.

var OUT: String = OS.get_environment("APPROACH_SHOTS_OUT") if OS.get_environment("APPROACH_SHOTS_OUT") != "" else "user://approach_shots/"
const SHOTS := [
	["1_spawn_view", Vector3(0.0, 4.2, 69.0), Vector3(0.0, 2.0, 40.0)],
	["2_trail_gap", Vector3(-1.0, 2.2, 58.0), Vector3(0.0, 1.8, 49.0)],
	["3_rise_ramp", Vector3(8.0, 3.0, 66.0), Vector3(14.0, 2.0, 55.0)],
	["4_viewpoint", Vector3(14.0, 6.0, 53.0), Vector3(10.0, 2.5, 26.0)],
	["5_fence_gate", Vector3(-4.0, 2.5, 49.0), Vector3(2.0, 1.4, 42.0)],
	["6_bypass_cut", Vector3(26.0, 2.4, 52.0), Vector3(19.0, 1.4, 44.0)],
]


func _initialize() -> void:
	if not OUT.ends_with("/"):
		OUT += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT) if OUT.begins_with("user://") else OUT)
	Player.require_mouse_capture = false
	HitStop.enabled = false
	_run.call_deferred()


func _run() -> void:
	root.get_node("QuestManager").intro_done = true
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 30:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 200.0
	root.add_child(cam)
	cam.current = true
	for shot in SHOTS:
		cam.global_position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
		for i in 8:
			await process_frame
		var img := root.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT + shot[0] + ".png") if OUT.begins_with("user://") else OUT + shot[0] + ".png")
		print("shot ", shot[0], " ", img.get_width(), "x", img.get_height())
	quit()
