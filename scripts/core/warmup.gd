class_name Warmup
extends RefCounted
## Pays first-use costs (shader/pipeline compiles, font glyph rasterizing, audio mixer setup) before
## the player is in a fight. Everything is drawn once in a tiny private SubViewport with its own
## camera, a shadow-casting light and fog, so the shader variants match the arena's materials.
##
## Boot usage: run steps() one Callable per frame behind a progress bar.
##   var steps := Warmup.steps()
##   for i in steps.size(): steps[i].call(); progress = float(i + 1) / steps.size(); await frame
## Nothing depends on this having run: without it the first hit/pickup/slam just pays the cost then.

const STAGE_SIZE: Vector2i = Vector2i(128, 128)
const RENDER_WAIT_STEPS: int = 3  # frames the stage must be rendered before it is torn down
const CHARSET: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '+-[]#()%.,:!x/"

## Folders whose resources are all read from disk up front (first load of a .tres/.tscn costs
## several ms; doing it mid-fight is a visible hitch). Listed with DirAccess, which also works in
## exported builds (files appear with a ".remap" suffix there).
const PRELOAD_DIRS: PackedStringArray = [
	"res://resources/attacks/", "res://resources/items/", "res://resources/loot/",
	"res://scenes/enemies/", "res://scenes/loot/",
]

static var _stage: SubViewport
static var _done: bool = false
static var _held: Array[Resource] = []  # keeps preloaded resources in the engine cache


static func is_done() -> bool:
	return _done


static func steps() -> Array[Callable]:
	var list: Array[Callable] = []
	for dir_path in PRELOAD_DIRS:
		list.append(Warmup._preload_dir.bind(dir_path))
	list.append_array([
		Warmup._open_stage,
		Warmup._stage_lit_and_emissive,
		Warmup._stage_labels,
		Warmup._stage_fx,
		Warmup._stage_boss_ring,
	])
	var audio := _autoload("AudioManager")
	if audio and audio.has_method("warm_up_names"):
		for sfx_name: StringName in audio.call("warm_up_names"):
			list.append(Warmup._warm_sfx.bind(sfx_name))
	for i in RENDER_WAIT_STEPS:
		list.append(Warmup._wait)
	list.append(Warmup._close_stage)
	return list


## Convenience for code that is not driving a loading screen (tests, benchmarks).
static func run(tree: SceneTree) -> void:
	for step in steps():
		step.call()
		await tree.process_frame


static func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null(node_name) if tree else null


static func _wait() -> void:
	pass


static func _preload_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file_name in dir.get_files():
		var clean := file_name.trim_suffix(".remap")
		if clean.ends_with(".tres") or clean.ends_with(".tscn"):
			# The engine's cache only keeps a resource alive while something references it, so hold it.
			var res := ResourceLoader.load(dir_path + clean)
			if res:
				_held.append(res)


static func _open_stage() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	_stage = SubViewport.new()
	_stage.size = STAGE_SIZE
	_stage.own_world_3d = true
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera := Camera3D.new()
	camera.current = true
	_stage.add_child(camera)
	var light := DirectionalLight3D.new()
	light.shadow_enabled = true
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_stage.add_child(light)
	var env := Environment.new()
	env.fog_enabled = true
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_stage.add_child(world_env)
	tree.root.add_child(_stage)


## Characters (lit, shadow-casting) and pickups (emissive), the two opaque material variants.
static func _stage_lit_and_emissive() -> void:
	var lit := MeshInstance3D.new()
	lit.mesh = BoxMesh.new()
	var lit_material := StandardMaterial3D.new()
	lit_material.albedo_color = Color(0.5, 0.3, 0.3)
	lit.material_override = lit_material
	lit.position = Vector3(-1.0, 0.0, -4.0)
	_stage.add_child(lit)

	var glow := MeshInstance3D.new()
	glow.mesh = BoxMesh.new()
	var glow_material := StandardMaterial3D.new()
	glow_material.albedo_color = Color(0.3, 0.55, 1.0)
	glow_material.emission_enabled = true
	glow_material.emission = Color(0.3, 0.55, 1.0)
	glow_material.emission_energy_multiplier = 0.6
	glow.material_override = glow_material
	glow.position = Vector3(1.0, 0.0, -4.0)
	_stage.add_child(glow)


## Enemy health labels, pickup names and the HUD-style text: rasterize the whole charset once.
static func _stage_labels() -> void:
	var label := Label3D.new()
	label.text = CHARSET
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.01
	label.position = Vector3(0.0, 1.5, -4.0)
	_stage.add_child(label)


static func _stage_fx() -> void:
	var fx := _autoload("Fx")
	if fx == null or not fx.has_method("make_warmup_nodes"):
		return
	var index := 0
	for node: Node3D in fx.call("make_warmup_nodes"):
		node.position = Vector3(-1.0 + index, -1.2, -3.5)
		_stage.add_child(node)
		index += 1


static func _stage_boss_ring() -> void:
	var resources := Warden.ring_resources()
	var ring := MeshInstance3D.new()
	ring.mesh = resources[0]
	ring.material_override = resources[1]
	ring.scale = Vector3(0.4, 1.0, 0.4)
	ring.position = Vector3(0.0, -1.6, -4.0)
	_stage.add_child(ring)


static func _warm_sfx(sfx_name: StringName) -> void:
	var audio := _autoload("AudioManager")
	if audio and audio.has_method("warm_up"):
		audio.call("warm_up", sfx_name)


static func _close_stage() -> void:
	if _stage and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_done = true
