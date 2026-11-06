class_name PbrMaterials
extends RefCounted
## Shared CC0 PBR materials for the island and Outpost 17 (sources and licences: docs/ASSETS.md).
## The merged meshes keep their vertex colours (tint); the texture adds grain and surface response.
## Web and mobile use the "lite" variant: albedo only, no normal or roughness maps.

const DIR: String = "res://assets/textures/pbr/"

static var _ground: ShaderMaterial
static var _concrete: StandardMaterial3D
static var _metal: StandardMaterial3D


static func lite() -> bool:
	return OS.has_feature("web") or OS.has_feature("mobile")


static func _tex(set_id: String, kind: String) -> Texture2D:
	return load("%s%s/%s_1K-JPG_%s.jpg" % [DIR, set_id, set_id, kind]) as Texture2D


static func ground() -> ShaderMaterial:
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
	if _concrete == null:
		_concrete = _triplanar("Concrete034", 0.28, Color(1.9, 1.9, 1.9), 0.8, true)
	return _concrete


## Merged kit meshes (containers, barrels, generators): weathered metal grain.
static func metal() -> StandardMaterial3D:
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
