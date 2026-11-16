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
	["annex_inside", Vector3(15.9, 1.7, -43.2), Vector3(17.1, 1.9, -41.2)],
	["gate_hall", Vector3(-1.0, 2.6, -46.0), Vector3(-8.0, 1.0, -55.0)],
	["store_door", Vector3(-12.0, 2.0, -87.0), Vector3(-21.0, 1.2, -87.0)],
	["store_bag", Vector3(-17.6, 1.9, -87.0), Vector3(-21.4, 1.0, -87.0)],
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
	# Uncapped, so the frame time shows the work rather than the monitor refresh.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _save(shot_name: String) -> void:
	var img := root.get_texture().get_image()
	var path := _out + "%s_%s.png" % [_prefix, shot_name]
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)


func _measure(frames: int, scope: Node = null) -> String:
	var t0 := Time.get_ticks_usec()
	var calls := 0
	for i in frames:
		await process_frame
		calls += _draw_calls(scope)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(frames)
	return "avg_frame_ms=%.2f avg_draw_calls=%.1f" % [ms, float(calls) / float(frames)]


func _run() -> void:
	if _mode == "cinematic":
		await _run_cinematic()
	elif _mode == "props":
		await _run_props()
	else:
		await _run_world()
	quit()


func _run_cinematic() -> void:
	var cin := OpeningCinematic.play(self)
	for i in 10:
		await process_frame
	var elapsed := 0.0
	for t: float in CINEMATIC_TIMES:
		while elapsed < t and is_instance_valid(cin):
			cin.advance(0.1)
			elapsed += 0.1
			await process_frame
		for i in 3:
			await process_frame
		var stats := await _measure(20, cin)
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
		if shot[0] == "annex_inside":
			root.get_node("WorldState").set_flag(&"has_lab_pass", true)
			for i in 60:
				await process_frame
		if shot[0] == "store_bag":
			root.get_node("WorldState").set_flag(&"warden_d_defeated", true)
			for i in 90:
				await process_frame
		cam.global_position = shot[1]
		cam.look_at(shot[2], Vector3.UP)
		for i in 10:
			await process_frame
		var stats := await _measure(30)
		_save(shot[0])
		print("WORLD %s %s" % [shot[0], stats])


## Close-ups of the props on a plain stage: the payment bag (shut and opened), the boat, and both walker figures.
## Each shot is a fixed camera, so it shows the model itself rather than whatever the level happens to hold.
func _run_props() -> void:
	var stage := Node3D.new()
	stage.name = "PropStage"
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	sun.light_energy = 1.4
	stage.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.34, 0.37, 0.42)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.56)
	e.ambient_light_energy = 0.9
	env.environment = e
	stage.add_child(env)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	ground.mesh = plane
	ground.material_override = OpeningArt.material(false, 0.9, 0.0)
	(ground.material_override as StandardMaterial3D).albedo_color = Color(0.45, 0.4, 0.32)
	stage.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.05
	stage.add_child(cam)
	cam.current = true
	var look := Vector3(0.0, 0.3, 0.0)

	var bag := PaymentBag.build()
	bag.position = Vector3(0.0, 0.2, 0.0)
	stage.add_child(bag)
	await _frames(6)
	cam.global_position = Vector3(0.75, 0.75, 0.9)
	cam.look_at(look, Vector3.UP)
	await _frames(4)
	_save("props_bag_closed")
	PaymentBag.open(bag, false)
	await _frames(6)
	cam.global_position = Vector3(0.6, 0.85, 0.75)
	cam.look_at(Vector3(0.0, 0.3, 0.0), Vector3.UP)
	await _frames(4)
	_save("props_bag_open")
	bag.queue_free()
	await _frames(2)

	var boat := OpeningArt.boat()
	boat.position = Vector3(0.0, 0.0, 0.0)
	stage.add_child(boat)
	await _frames(4)
	cam.global_position = Vector3(3.8, 3.6, 6.5)
	cam.look_at(Vector3(0.0, 0.2, 0.0), Vector3.UP)
	await _frames(4)
	_save("props_boat")
	boat.queue_free()
	await _frames(2)

	# The wall detail used in the annex and the store: a conduit, two monitors and a plain wall behind them.
	var panel := Node3D.new()
	panel.position = Vector3(0.0, 0.0, -4.0)
	stage.add_child(panel)
	var wall := MeshInstance3D.new()
	var wall_box := BoxMesh.new()
	wall_box.size = Vector3(3.6, 3.0, 0.3)
	wall.mesh = wall_box
	wall.position = Vector3(0.0, 1.5, 0.0)
	wall.material_override = OpeningArt.material(false, 0.9, 0.0)
	(wall.material_override as StandardMaterial3D).albedo_color = Color(0.3, 0.3, 0.29)
	panel.add_child(wall)
	var frame := ArenaDecor.Builder.new()
	var screen := ArenaDecor.Builder.new()
	for mx: float in [-0.8, 0.8]:
		OpeningArt.monitor(frame, screen, Vector3(mx, 1.6, 0.2), Vector3.BACK)
	OpeningArt.pipe(frame, Vector3(-1.6, 2.7, 0.2), Vector3(1.6, 2.7, 0.2), 0.06, OpeningArt.DARK_METAL)
	var frame_node := MeshInstance3D.new()
	frame_node.mesh = frame.finish()
	frame_node.material_override = OpeningArt.material(true, 0.6, 0.2)
	panel.add_child(frame_node)
	var screen_node := MeshInstance3D.new()
	screen_node.mesh = screen.finish()
	var glow := OpeningArt.material(true, 0.3, 0.0)
	glow.emission_enabled = true
	glow.emission = Color(0.3, 0.9, 1.0)
	glow.emission_energy_multiplier = 1.2
	screen_node.material_override = glow
	panel.add_child(screen_node)
	await _frames(6)
	cam.global_position = Vector3(0.0, 1.5, -1.8)
	cam.look_at(Vector3(0.0, 1.6, -4.0), Vector3.UP)
	await _frames(4)
	_save("props_detail")
	panel.queue_free()
	await _frames(2)

	var walkers: Array[WorkerWalker] = []
	for spec: Array in [[Vector3(-0.7, 0.0, 0.0), false, true], [Vector3(0.7, 0.0, 0.0), true, false]]:
		var w := WorkerWalker.new()
		w.path = PackedVector3Array([spec[0], spec[0] + Vector3(0.0, 0.0, 1.0)])
		w.guard = spec[1]
		w.carrying = spec[2]
		stage.add_child(w)
		walkers.append(w)
	await _frames(6)
	cam.global_position = Vector3(0.0, 1.5, 4.2)
	cam.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
	await _frames(4)
	_save("props_walkers")
	for w in walkers:
		w.queue_free()
	await _frames(2)
	stage.queue_free()


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## Draw calls in the last frame: the root viewport plus any SubViewport under `scope` (the cinematic renders
## its scene in one), because the root count alone misses that work.
func _draw_calls(scope: Node) -> int:
	var total := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	if scope != null and is_instance_valid(scope):
		for vp: Node in scope.find_children("*", "SubViewport", true, false):
			total += int(RenderingServer.viewport_get_render_info(
					(vp as SubViewport).get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
					RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	return total
