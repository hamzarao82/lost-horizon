extends SceneTree
## Windowed contact sheet of the environment kit:
##   godot --path . -s tools/env_kit_sheet.gd -- <output_dir>
## Writes sheet_small.png and sheet_large.png (pieces on a ground plane, three-quarter view).

const OUT_DEFAULT: String = "user://"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OUT_DEFAULT
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var pieces := OutpostKit.manifest_pieces()
	var small: Array = []
	var large: Array = []
	for p in pieces:
		var size: Array = p["size"]
		if maxf(maxf(size[0], size[1]), size[2]) > 6.5:
			large.append(p)
		else:
			small.append(p)
	await _shoot(small, 6, 5.0, out + "/sheet_small.png", 15.0)
	await _shoot(large, 3, 17.0, out + "/sheet_large.png", 38.0)
	quit()


func _shoot(group: Array, per_row: int, spacing: float, path: String, cam_dist: float) -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.74, 0.84)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.65, 0.7)
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	root.add_child(sun)
	var rows := int(ceil(float(group.size()) / per_row))
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(per_row * spacing + 6.0, rows * spacing + 6.0)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.74, 0.64, 0.46)
	plane.material = gm
	ground.mesh = plane
	ground.position = Vector3((per_row - 1) * spacing * 0.5, 0, (rows - 1) * spacing * 0.5)
	root.add_child(ground)
	for i in group.size():
		var name: String = group[i]["name"]
		var node := OutpostKit.instance(name)
		if node == null:
			continue
		node.position = Vector3((i % per_row) * spacing, 0, (i / per_row) * spacing)
		root.add_child(node)
		var label := Label3D.new()
		label.text = name
		label.font_size = 40
		label.pixel_size = 0.012 * spacing / 3.6
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = node.position + Vector3(0, -0.05, spacing * 0.42)
		label.rotation_degrees.x = -50
		root.add_child(label)
	var cam := Camera3D.new()
	cam.fov = 40
	var center := Vector3((per_row - 1) * spacing * 0.5, 0.0, (rows - 1) * spacing * 0.5)
	cam.position = center + Vector3(0, cam_dist * (0.55 + rows * 0.05), cam_dist * (0.8 + rows * 0.12))
	root.add_child(cam)
	cam.look_at(center + Vector3(0, 0.5, 0))
	cam.current = true
	for i in 8:
		await process_frame
	get_root().get_viewport().get_texture().get_image().save_png(path)
	root.queue_free()
	await process_frame
