class_name OpeningCinematic
extends CanvasLayer
## The speedboat-and-storm opening (~45 to 55 s): a real-time scene in its OWN SubViewport/World3D (it
## cannot touch Main, physics or the HUD), following `OpeningTimeline`'s twelve scenes with a camera that
## never holds a single angle for long. Skippable at any time; the storm audio crossfades into the beach
## ambience in the final black scene either way. Same pause/skip pattern as the older `StoryIntro`.
##
## Visual honesty note: the protagonist, the guard and the boat are simple procedural low-poly stand-ins
## (capsules, boxes, a wedge hull), not the rigged game character — see docs/OPENING_CINEMATIC.md.
##
## `advance(seconds)` is the real clock; `_process` just calls it, so a test can step the whole timeline
## without a window, a renderer, or real time.

signal finished(skipped: bool)

const SKIP_GRACE_SECONDS: float = 0.4
const FINAL_FADE_SECONDS: float = 1.0

var is_done: bool = false
var _age: float = 0.0
var _clock: float = 0.0
var _skip_requested: bool = false
var _was_paused: bool = false
var _headless: bool = false
var _finished_emitted: bool = false

var _viewport: SubViewport
var _cam: Camera3D
var _boat: Node3D
var _rain: CPUParticles3D
var _flash_rect: ColorRect
var _black: ColorRect
var _skip_button: Button
var _ocean_mat: StandardMaterial3D
var _last_scene_index: int = -1
var _wind_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _next_strike: float = 2.0
var _from_cam_pos: Vector3 = OpeningTimeline.SCENES[0]["cam_pos"]
var _from_cam_look: Vector3 = OpeningTimeline.SCENES[0]["cam_look"]


static func play(tree: SceneTree) -> OpeningCinematic:
	var node := OpeningCinematic.new()
	tree.root.add_child(node)
	return node


func _init() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_rng.randomize()


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	_build_ui()
	if not _headless:
		_build_scene()
		_build_audio()


func _exit_tree() -> void:
	if get_tree() != null and not is_done:
		get_tree().paused = _was_paused


func _process(delta: float) -> void:
	advance(delta)


func _input(event: InputEvent) -> void:
	if is_done or _age < SKIP_GRACE_SECONDS:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
		pressed = event.pressed
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if is_done:
		return
	_skip_requested = true


## The real clock. Driving the whole timeline through one function lets a test step it without frames.
func advance(seconds: float) -> void:
	if is_done:
		return
	_age += seconds
	if _skip_requested and _clock < OpeningTimeline.total_duration() - OpeningTimeline.SCENES[OpeningTimeline.SCENES.size() - 1]["duration"]:
		_clock = OpeningTimeline.total_duration() - OpeningTimeline.SCENES[OpeningTimeline.SCENES.size() - 1]["duration"] - 0.001
		_apply_skip_jump()
	_clock += seconds
	var at := OpeningTimeline.scene_at(_clock)
	var index: int = at["index"]
	var scene: Dictionary = at["scene"]
	var progress: float = at["progress"]
	if index != _last_scene_index:
		_on_scene_entered(index, scene)
		_last_scene_index = index
	if not _headless:
		_update_visuals(scene, progress)
	if _clock >= OpeningTimeline.total_duration():
		_finish(_skip_requested)


func _apply_skip_jump() -> void:
	if not _headless:
		if is_instance_valid(_black):
			_black.modulate.a = 1.0
		if is_instance_valid(_flash_rect):
			_flash_rect.modulate.a = 0.0
		if is_instance_valid(_skip_button):
			_skip_button.visible = false


func storm_intensity() -> float:
	return float(OpeningTimeline.scene_at(_clock)["scene"]["storm"])


func current_scene_id() -> StringName:
	return OpeningTimeline.scene_at(_clock)["scene"]["id"]


func _on_scene_entered(_index: int, scene: Dictionary) -> void:
	if _last_scene_index >= 0:
		var previous: Dictionary = OpeningTimeline.SCENES[_last_scene_index]
		_from_cam_pos = previous["cam_pos"]
		_from_cam_look = previous["cam_look"]
	if _headless:
		return
	if scene["id"] == &"to_black":
		var tween := create_tween()
		tween.tween_property(_black, "modulate:a", 1.0, FINAL_FADE_SECONDS)
	if scene["id"] == &"ambience_crossfade":
		_crossfade_to_beach_ambience()


func _finish(skipped: bool) -> void:
	if is_done:
		return
	is_done = true
	get_tree().paused = _was_paused
	if not _finished_emitted:
		_finished_emitted = true
		finished.emit(skipped)
	queue_free()


# --- scene build (skipped entirely on headless) -----------------------------

func _build_scene() -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.move_to_front()  # built before _black/_skip in _build_ui, but the viewport must sit under them

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.size = get_viewport().get_visible_rect().size if get_viewport() else Vector2i(1280, 720)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.10)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.45)
	env.ambient_light_energy = 0.6
	var cam_attrs := WorldEnvironment.new()
	cam_attrs.environment = env
	_viewport.add_child(cam_attrs)
	container.add_child(_viewport)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 0.9
	sun.light_color = Color(0.85, 0.85, 0.95)
	_viewport.add_child(sun)

	var ocean := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ocean.mesh = plane
	_ocean_mat = StandardMaterial3D.new()
	_ocean_mat.albedo_color = Color(0.05, 0.10, 0.15)
	_ocean_mat.roughness = 0.25
	_ocean_mat.metallic = 0.1
	ocean.material_override = _ocean_mat
	ocean.position = Vector3(0.0, -0.6, -10.0)
	_viewport.add_child(ocean)

	_boat = _build_boat()
	_boat.position = Vector3(0.0, 0.0, -8.0)
	_viewport.add_child(_boat)

	_cam = Camera3D.new()
	_cam.fov = 55.0
	_viewport.add_child(_cam)
	_cam.current = true

	_rain = CPUParticles3D.new()
	_rain.amount = 160
	_rain.lifetime = 1.2
	_rain.emitting = false
	_rain.direction = Vector3(0.1, -1.0, 0.0)
	_rain.spread = 8.0
	_rain.initial_velocity_min = 10.0
	_rain.initial_velocity_max = 14.0
	_rain.gravity = Vector3(0.0, -4.0, 0.0)
	_rain.color = Color(0.7, 0.8, 0.9, 0.5)
	var rain_mesh := BoxMesh.new()
	rain_mesh.size = Vector3(0.02, 0.3, 0.02)
	_rain.mesh = rain_mesh
	_rain.position = Vector3(0.0, 6.0, -8.0)
	_rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_rain.emission_box_extents = Vector3(8.0, 0.2, 8.0)
	_viewport.add_child(_rain)


func _build_boat() -> Node3D:
	var boat := Node3D.new()
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(2.0, 0.6, 4.5)
	hull.mesh = hull_mesh
	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.82, 0.78, 0.68)
	hull.material_override = hull_mat
	boat.add_child(hull)

	var bow := MeshInstance3D.new()
	var bow_mesh := PrismMesh.new()
	bow_mesh.size = Vector3(2.0, 0.6, 1.4)
	bow.mesh = bow_mesh
	bow.material_override = hull_mat
	bow.position = Vector3(0.0, 0.0, -2.7)
	bow.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	boat.add_child(bow)

	var windshield := MeshInstance3D.new()
	var ws_mesh := BoxMesh.new()
	ws_mesh.size = Vector3(1.6, 0.7, 0.08)
	windshield.mesh = ws_mesh
	var ws_mat := StandardMaterial3D.new()
	ws_mat.albedo_color = Color(0.55, 0.75, 0.85, 0.5)
	ws_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	windshield.material_override = ws_mat
	windshield.position = Vector3(0.0, 0.75, -0.9)
	boat.add_child(windshield)

	var nav_light := OmniLight3D.new()
	nav_light.light_color = Color(0.3, 1.0, 0.4)
	nav_light.light_energy = 0.6
	nav_light.omni_range = 2.0
	nav_light.position = Vector3(0.9, 0.5, -1.8)
	boat.add_child(nav_light)

	var protagonist := _build_protagonist()
	protagonist.position = Vector3(0.0, 0.6, -0.4)
	protagonist.name = "Protagonist"
	boat.add_child(protagonist)

	var bag := _build_bag()
	bag.position = Vector3(0.6, 0.55, 1.4)
	bag.name = "TreasureBag"
	boat.add_child(bag)
	return boat


## A simple procedural stand-in for the protagonist: see the class doc. Milestone 13 can replace this
## with the rigged `SkinnedVisual` player model.
func _build_protagonist() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.1
	body.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.27, 0.3)
	body.material_override = mat
	body.position = Vector3(0.0, 0.55, 0.0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	head.mesh = sphere
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.65, 0.5)
	head.material_override = skin
	head.position = Vector3(0.0, 1.25, 0.0)
	root.add_child(head)
	return root


func _build_bag() -> Node3D:
	var root := Node3D.new()
	var sack := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.36
	sack.mesh = sphere
	var sack_mat := StandardMaterial3D.new()
	sack_mat.albedo_color = Color(0.4, 0.3, 0.18)
	sack.material_override = sack_mat
	root.add_child(sack)
	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.95, 0.78, 0.2)
	gold_mat.emission_enabled = true
	gold_mat.emission = Color(0.7, 0.5, 0.1)
	gold_mat.emission_energy_multiplier = 0.6
	for i in 4:
		var coin := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.05
		disc.bottom_radius = 0.05
		disc.height = 0.015
		coin.mesh = disc
		coin.material_override = gold_mat
		coin.position = Vector3(0.1 * cos(i * 1.6), 0.18 + 0.03 * i, 0.1 * sin(i * 1.6))
		root.add_child(coin)
	return root


func _build_audio() -> void:
	_wind_player = AudioStreamPlayer.new()
	_wind_player.bus = "Master"
	_wind_player.volume_db = -10.0
	add_child(_wind_player)
	var stream := load("res://assets/audio/menu_wind.wav") as AudioStream
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_wind_player.stream = stream
	_wind_player.play()


func _crossfade_to_beach_ambience() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("set_region_ambience"):
		audio.call("set_region_ambience", &"outpost", 3.0)
	if is_instance_valid(_wind_player):
		var tween := create_tween()
		tween.tween_property(_wind_player, "volume_db", -40.0, 2.5)
		tween.tween_callback(_wind_player.stop)


func _update_visuals(scene: Dictionary, progress: float) -> void:
	var storm: float = scene["storm"]
	if is_instance_valid(_ocean_mat):
		_ocean_mat.albedo_color = Color(0.05, 0.10, 0.15).lerp(Color(0.015, 0.02, 0.03), storm)
	if is_instance_valid(_boat):
		var rock := storm * 0.12
		_boat.rotation.z = sin(_clock * 1.7) * rock
		_boat.rotation.x = sin(_clock * 1.3 + 1.0) * rock * 0.6
		_boat.position.y = sin(_clock * 2.1) * storm * 0.25
	if is_instance_valid(_cam) and _last_scene_index >= 0:
		_place_camera(scene, progress)
	if is_instance_valid(_rain):
		_rain.emitting = storm > 0.3
	_update_lightning(storm)
	if scene["id"] == &"thrown_overboard" and is_instance_valid(_boat):
		var p := progress
		var proto := _boat.get_node_or_null("Protagonist")
		if proto:
			proto.position = Vector3(0.0, 0.6, -0.4).lerp(Vector3(1.6, -0.6, 1.2), p)
			proto.rotation.x = p * PI * 1.5


## Eases from the previous scene's framing into this one's over the first half of the scene, then holds
## (a brief, smooth move into position rather than an instant cut or a move that never settles). The path
## arcs through a point well above the boat so a move between two close-up spots never clips through the
## hull on the way (a straight line between two points near the deck can pass right through it).
func _place_camera(scene: Dictionary, progress: float) -> void:
	var move_t := clampf(progress / 0.5, 0.0, 1.0)
	var eased := ease(move_t, 0.3)
	var from_pos: Vector3 = _from_cam_pos
	var to_pos: Vector3 = scene["cam_pos"]
	var mid := (from_pos + to_pos) * 0.5 + Vector3(0.0, 3.5, 0.0)
	var ab := from_pos.lerp(mid, eased)
	var bc := mid.lerp(to_pos, eased)
	var local_pos := ab.lerp(bc, eased)
	var local_look: Vector3 = _from_cam_look.lerp(scene["cam_look"], eased)
	_cam.global_position = _boat.to_global(local_pos)
	var look := _boat.to_global(local_look)
	if _cam.global_position.distance_to(look) > 0.01:
		_cam.look_at(look, Vector3.UP)


func _update_lightning(storm: float) -> void:
	if storm < 0.15 or not is_instance_valid(_flash_rect):
		return
	if _clock >= _next_strike:
		_next_strike = _clock + _rng.randf_range(maxf(1.5, 6.0 - storm * 4.0), maxf(2.5, 8.0 - storm * 4.0))
		var tween := create_tween()
		tween.tween_property(_flash_rect, "modulate:a", 0.8 * storm, 0.04)
		tween.tween_property(_flash_rect, "modulate:a", 0.0, 0.25)
		_play_thunder()


func _play_thunder() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and audio.has_method("play"):
		audio.call("play", &"menu_thunder", -4.0)


# --- UI (black overlay, flash overlay, skip button) -------------------------

func _build_ui() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)

	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(0.85, 0.9, 1.0)
	_flash_rect.modulate.a = 0.0
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)

	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.custom_minimum_size = Vector2(120.0, 48.0)
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)
	var tween := create_tween()
	tween.tween_property(_black, "modulate:a", 0.0, 1.2).set_delay(0.3)
