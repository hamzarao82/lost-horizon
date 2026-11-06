class_name StubRegion
extends Region
## Placeholder region scene for Dead Coast, Blackwood and the Research Complex until their real levels exist:
## a ground slab, a sign and the arrival marker. The framework, saving and transitions are real; the level is not.

const GROUND_SIZE: Vector3 = Vector3(80.0, 1.0, 80.0)
const GROUND_COLORS: Dictionary = {
	&"dead_coast": Color(0.74, 0.66, 0.46),
	&"blackwood": Color(0.16, 0.25, 0.16),
	&"research_complex": Color(0.36, 0.38, 0.4),
}

## Example of region-specific state that survives travel and saving.
var visits: int = 0


func _ready() -> void:
	_build_ground()
	_build_sign()


func enter(_entry_id: StringName) -> void:
	visits += 1


func capture_state() -> Dictionary:
	return {"visits": visits}


func restore_state(state: Dictionary) -> void:
	visits = int(state.get("visits", 0))


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	body.position = Vector3(0.0, -GROUND_SIZE.y * 0.5, 0.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = GROUND_SIZE
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = GROUND_SIZE
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLORS.get(region_id, Color(0.4, 0.4, 0.4))
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)


func _build_sign() -> void:
	var data := RegionStore.load_data(region_id)
	var label := Label3D.new()
	label.name = "Sign"
	label.text = "%s\nUnder construction" % (data.display_name if data else String(region_id))
	label.font_size = 96
	label.pixel_size = 0.01
	label.position = Vector3(0.0, 3.0, 8.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
