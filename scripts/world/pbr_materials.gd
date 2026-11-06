class_name PbrMaterials
extends RefCounted
## Shared CC0 PBR materials for the island and Outpost 17 (sources and licences: docs/ASSETS.md).
## The merged meshes keep their vertex colours (tint); the texture adds grain and surface response.
## Web and mobile use the "lite" variant: albedo only, no normal or roughness maps.

const DIR: String = "res://assets/textures/pbr/"

static var _ground: ShaderMaterial
static var _concrete: StandardMaterial3D
static var _metal: StandardMaterial3D
static var _plain_mat: StandardMaterial3D


## Web and mobile always use lite; on desktop only the High quality preset pays for normal and roughness maps.
static func lite() -> bool:
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	var settings := tree.root.get_node_or_null("Settings") if tree else null
	return settings != null and int(settings.quality) < 2  # Settings.Quality.HIGH == 2


static func _tex(set_id: String, kind: String) -> Texture2D:
	return load("%s%s/%s_1K-JPG_%s.jpg" % [DIR, set_id, set_id, kind]) as Texture2D


static func ground() -> Material:
	if OS.has_feature("web"):
		return _plain()
	if _ground == null:
		_ground = ShaderMaterial.new()
		_ground.shader = load("res://assets/shaders/ground_pbr.gdshader") as Shader
		_ground.set_shader_parameter("dirt_albedo", _tex("Ground111", "Color"))
		_ground.set_shader_parameter("rock_albedo", _tex("Gravel043", "Color"))
		var maps := not lite()
		_ground.set_shader_parameter("use_maps", maps)
		if maps:
			_ground.set_shader_parameter("dirt_normal", _tex("Ground111", "NormalGL"))
			_ground.set_shader_parameter("rock_normal", _tex("Gravel043", "NormalGL"))
	return _ground


## Walls, floors and merged props: world-space triplanar concrete grain under the vertex colour.
static func concrete() -> StandardMaterial3D:
	if OS.has_feature("web"):
		return _plain()
	if _concrete == null:
		_concrete = _triplanar("Concrete034", 0.28, Color(1.9, 1.9, 1.9), 0.8, true)
	return _concrete


## Merged kit meshes (containers, barrels, generators): weathered metal grain.
static func metal() -> StandardMaterial3D:
	if OS.has_feature("web"):
		return _plain()
	if _metal == null:
		_metal = _triplanar("Metal041B", 0.45, Color(1.6, 1.6, 1.6), 0.0, false)
	return _metal


static func _triplanar(set_id: String, scale: float, tint: Color, normal_depth: float, with_normal: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _tex(set_id, "Color")
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = 0.9
	if with_normal and not lite():
		m.normal_enabled = true
		m.normal_texture = _tex(set_id, "NormalGL")
		m.normal_scale = normal_depth
	return m


## Web keeps the cheap vertex-colour look: the textured materials add about 15 s of shader compile to the reveal there.
static func _plain() -> StandardMaterial3D:
	if _plain_mat == null:
		_plain_mat = StandardMaterial3D.new()
		_plain_mat.vertex_color_use_as_albedo = true
		_plain_mat.roughness = 1.0
	return _plain_mat
