extends SceneTree
## Windowed screenshots of Blackwood, with average luminance and draw calls:
##   godot --path . --resolution 1280x720 -s tools/blackwood_shots.gd
## Set BW_SHOTS_OUT to a folder; the default is user://blackwood_shots/.

var OUT: String = OS.get_environment("BW_SHOTS_OUT") if OS.get_environment("BW_SHOTS_OUT") != "" else "user://blackwood_shots/"
const SPOTS := [
	["1_entrance", Vector3(0.0, 0.3, 9.0), 0.0],
	["2_trail", Vector3(-12.0, 0.3, -52.0), 0.0],
	["3_comms", Vector3(26.0, 0.3, -130.0), 0.0],
	["4_testing", Vector3(-10.0, 0.3, -205.0), 0.0],
]


func _initialize() -> void:
	if not OUT.ends_with("/"):
		OUT += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT) if OUT.begins_with("user://") else OUT)
	Player.require_mouse_capture = false
	HitStop.enabled = false
	_run.call_deferred()


func _luminance(img: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 6):
		for x in range(0, img.get_width(), 6):
			var c := img.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return total / maxf(n, 1)


func _run() -> void:
	root.get_node("QuestManager").intro_done = true  # no intro cutscene over the shots
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.4, 0.45)
	sky_mat.sky_horizon_color = Color(0.5, 0.6, 0.55)
	sky.sky_material = sky_mat
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	Blackwood.apply_environment(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.light_energy = 0.9
	sun.shadow_enabled = true
	root.add_child(sun)
	var region: Node = load("res://scenes/regions/Blackwood_content.tscn").instantiate()
	root.add_child(region)
	var player := load("res://scenes/player/Player.tscn").instantiate() as Player
	player.position = SPOTS[0][1]
	root.add_child(player)
	for i in 30:
		await physics_frame
	var report := ""
	for spot in SPOTS:
		player.global_position = spot[1]
		player.velocity = Vector3.ZERO
		for i in 40:
			await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		img.save_png(OUT + spot[0] + ".png")
		var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		report += "%s luminance %.3f draw_calls %d\n" % [spot[0], _luminance(img), calls]
	print(report)
	var f := FileAccess.open(OUT + "report.txt", FileAccess.WRITE)
	f.store_string(report)
	f.close()
	quit()
