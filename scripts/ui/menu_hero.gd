class_name MenuHero
extends Control
## The real player model (assets/characters/player.glb, the same file SkinnedVisual loads) in side profile
## beside the title, looping its own idle clip in a private World3D. A dim key light is brightened by the
## storm's lightning flash. Nothing is built on a headless run, on the LOW quality preset or on web
## (where an extra 3D viewport is not worth its load time), so tests and small devices pay nothing.

const MODEL_PATH: String = "res://assets/characters/player.glb"
const VIEW_SIZE: Vector2i = Vector2i(420, 640)
const KEY_ENERGY_BASE: float = 0.8
const KEY_ENERGY_FLASH: float = 2.4
const FILL_ENERGY: float = 0.12

var storm: MenuStorm
var active: bool = false
var key_light: DirectionalLight3D
var model: Node3D
var _viewport: SubViewport
var _anim: AnimationPlayer


func _init(storm_ref: MenuStorm = null) -> void:
	storm = storm_ref
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## True when this device/build should draw the hero at all.
static func wanted() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	if OS.has_feature("web"):
		return false
	var loop := Engine.get_main_loop() as SceneTree
	var settings: Node = loop.root.get_node_or_null("Settings") if loop != null else null
	if settings != null and int(settings.get("quality")) == 0:  # Settings.Quality.LOW
		return false
	return true


func _ready() -> void:
	if not wanted() or not ResourceLoader.exists(MODEL_PATH):
		return
	_build()


func _build() -> void:
	var container := SubViewportContainer.new()
	container.name = "HeroContainer"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	container.anchor_right = 0.0
	container.offset_left = 24.0
	container.offset_right = 24.0 + float(VIEW_SIZE.x)
	container.offset_top = 40.0
	container.offset_bottom = -40.0
	add_child(container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = VIEW_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	container.add_child(_viewport)

	var scene := load(MODEL_PATH) as PackedScene
	if scene == null:
		return
	model = scene.instantiate() as Node3D
	if model == null:
		return
	model.rotation_degrees.y = 180.0  # side profile, facing the title (right on screen)
	_viewport.add_child(model)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var material := mi.get_active_material(surface) as BaseMaterial3D
			if material:
				material.vertex_color_use_as_albedo = true  # the art contract colours with vertices
	_anim = model.find_children("*", "AnimationPlayer", true, false).front() as AnimationPlayer if not model.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	if _anim != null and _anim.has_animation("idle"):
		_anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		_anim.play("idle")

	var camera := Camera3D.new()
	camera.fov = 32.0
	camera.position = Vector3(-4.4, 1.15, 0.0)
	_viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)

	key_light = DirectionalLight3D.new()
	key_light.light_color = Color(0.7, 0.8, 1.0)
	key_light.light_energy = KEY_ENERGY_BASE
	key_light.rotation_degrees = Vector3(-25.0, -70.0, 0.0)
	_viewport.add_child(key_light)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.4, 0.5, 0.7)
	fill.light_energy = FILL_ENERGY
	fill.rotation_degrees = Vector3(-10.0, 110.0, 0.0)
	_viewport.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.14, 0.2)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	active = true


func _process(_delta: float) -> void:
	if not active or key_light == null:
		return
	var flash := storm.flash_intensity() if storm != null else 0.0
	key_light.light_energy = KEY_ENERGY_BASE + KEY_ENERGY_FLASH * flash
