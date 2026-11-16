extends SceneTree
## Windowed screenshots and frame measurements of the opening arc's art (not headless):
##   godot --path . --resolution 1280x720 -s tools/art_shots.gd -- <cinematic|world> <prefix> [out_dir]
## Writes <out_dir>/<prefix>_<name>.png and prints average frame ms and draw calls per shot.

var _mode: String = "world"
var _prefix: String = "after"
var _out: String = "user://art_shots/"

const CINEMATIC_TIMES := [2.5, 7.5, 12.0, 16.0, 20.0, 24.5, 29.5, 34.5, 39.5, 44.0]
const WORLD_SHOTS := [
	["berm_front", Vector3(0.0, 4.2, 69.0), Vector3(0.0, 2.0, 40.0)],
	["berm_side", Vector3(-22.0, 3.0, 64.0), Vector3(-8.0, 3.0, 52.0)],
	["rise_ramp", Vector3(8.0, 3.0, 66.0), Vector3(14.0, 2.0, 55.0)],
	["yard_view", Vector3(14.5, 6.2, 53.0), Vector3(34.0, 1.2, 37.0)],
	["guard_station", Vector3(-22.0, 3.0, -19.0), Vector3(-22.0, 0.8, -28.0)],
	["worker_stores", Vector3(-7.0, 2.6, -37.0), Vector3(-15.0, 1.0, -43.0)],
	["annex", Vector3(8.0, 2.6, -44.5), Vector3(18.0, 1.4, -45.0)],
	["gate_hall", Vector3(-1.0, 2.6, -46.0), Vector3(-8.0, 1.0, -55.0)],
	["store_door", Vector3(-12.0, 2.0, -87.0), Vector3(-21.0, 1.2, -87.0)],
	["store_bag", Vector3(-19.0, 1.6, -85.6), Vector3(-21.4, 1.1, -87.0)],
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]
	if args.size() > 1:
		_prefix = args[1]
	if args.size() > 2:
		_out = args[2]
	if not _out.ends_with("/"):
		_out += "/"
	var abs_dir := ProjectSettings.globalize_path(_out) if _out.begins_with("user://") else _out
	DirAccess.make_dir_recursive_absolute(abs_dir)
	Player.require_mouse_capture = false
	HitStop.enabled = false
	_run.call_deferred()


func _save(shot_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out + "%s_%s.png" % [_prefix, shot_name]
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)


func _measure(frames: int) -> String:
	var t0 := Time.get_ticks_usec()
	var calls := 0
	for i in frames:
		await process_frame
		calls += int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	return "avg_frame_ms=%.2f avg_draw_calls=%.1f" % [ms, float(calls) / float(frames)]


func _run() -> void:
	if _mode == "cinematic":
		await _run_cinematic()
	else:
		await _run_world()
	quit()


func _run_cinematic() -> void:
	var cin := OpeningCinematic.play(self)
	for i in 10:
		await process_frame
	var elapsed := 0.0
	for t: float in CINEMATIC_TIMES:
		while elapsed < t:
			cin.advance(0.1)
			elapsed += 0.1
			await process_frame
		for i in 3:
			await process_frame
		var stats := await _measure(20)
		_save("cin_%02d" % int(t))
		print("CIN t=%.1f %s" % [t, stats])
	if is_instance_valid(cin):
		cin.skip()


func _run_world() -> void:
	root.get_node("QuestManager").intro_done = true
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 40:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 70.0
	cam.far = 250.0
	root.add_child(cam)
	cam.current = true
	for shot in WORLD_SHOTS:
		if shot[0] == "store_door":
			pass
		if shot[0] == "store_bag":
			root.get_node("WorldState").set_flag(&"warden_d_defeated", true)
			for i in 10:
				await process_frame
		cam.global_position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
		for i in 10:
			await process_frame
		var stats := await _measure(30)
		_save(shot[0])
		print("WORLD %s %s" % [shot[0], stats])
