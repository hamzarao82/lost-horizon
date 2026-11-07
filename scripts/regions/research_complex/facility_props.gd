class_name FacilityProps
extends RefCounted
## Small shared models for the components (one mesh and a few materials, built once). Placeholder look:
## Milestone 13 replaces the art without touching the components.

static var _body_mesh: BoxMesh
static var _screen_mesh: BoxMesh
static var _body_material: StandardMaterial3D
static var _screens: Dictionary = {}


## A waist-high console with a glowing screen facing +Z. `screen` picks the screen colour.
static func add_console(parent: Node3D, screen: Color = Color(0.2, 0.75, 0.9)) -> void:
	if _body_mesh == null:
		_body_mesh = BoxMesh.new()
		_body_mesh.size = Vector3(1.1, 1.0, 0.55)
		_screen_mesh = BoxMesh.new()
		_screen_mesh.size = Vector3(0.8, 0.45, 0.04)
		_body_material = StandardMaterial3D.new()
		_body_material.albedo_color = Color(0.22, 0.25, 0.28)
		_body_material.roughness = 0.7
	var body := MeshInstance3D.new()
	body.name = "ConsoleBody"
	body.mesh = _body_mesh
	body.material_override = _body_material
	body.position = Vector3(0.0, 0.5, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(body)
	var glass := MeshInstance3D.new()
	glass.name = "ConsoleScreen"
	glass.mesh = _screen_mesh
	glass.material_override = _screen_material(screen)
	glass.position = Vector3(0.0, 0.78, 0.29)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(glass)


static func _screen_material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _screens.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 1.2
		_screens[key] = m
	return _screens[key]
