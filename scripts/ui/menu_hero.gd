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
const STRIKE_MIN: float = 10.0
const STRIKE_MAX: float = 16.0
const STRIKE_CLIPS: PackedStringArray = ["light_1", "heavy"]

var storm: MenuStorm
var active: bool = false
var key_light: DirectionalLight3D
var model: Node3D
var strikes: int = 0  # attack clips played so far
var _viewport: SubViewport
var _anim: AnimationPlayer
var _rng := RandomNumberGenerator.new()
var _clock: float = 0.0
var _next_strike: float = 0.0
var _strike_scheduled: bool = false
var _attack_until: float = -1.0
var _last_flash: float = 0.0


func _init(storm_ref: MenuStorm = null) -> void:
	storm = storm_ref
	_rng.randomize()
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


func _process(delta: float) -> void:
	tick(delta)
	if not active or key_light == null:
		return
	var flash := storm.flash_intensity() if storm != null else 0.0
	key_light.light_energy = KEY_ENERGY_BASE + KEY_ENERGY_FLASH * flash


## Advances the strike timer by `delta` seconds (a stepped clock in tests). Every 10 to 16 seconds the next
## lightning flash plays an attack clip, then the model returns to idle. Does nothing unless the hero is built.
func tick(delta: float) -> void:
	if not active:
		return
	_clock += delta
	if not _strike_scheduled:
		_strike_scheduled = true
		_next_strike = _clock + _rng.randf_range(STRIKE_MIN, STRIKE_MAX)
	var flash := storm.flash_intensity() if storm != null else 0.0
	var rising := flash > _last_flash + 0.5
	_last_flash = flash
	if _attack_until >= 0.0 and _clock >= _attack_until:
		_attack_until = -1.0
		if _anim != null and _anim.has_animation("idle"):
			_anim.play("idle")
	if rising and _clock >= _next_strike and _attack_until < 0.0:
		_play_strike()


func _play_strike() -> void:
	if _anim == null:
		return
	var clip := ""
	for name in STRIKE_CLIPS:
		if _anim.has_animation(name):
			clip = name
			break
	if clip == "":
		return
	_anim.play(clip)
	_attack_until = _clock + _anim.get_animation(clip).length
	_next_strike = _clock + _rng.randf_range(STRIKE_MIN, STRIKE_MAX)
	strikes += 1
