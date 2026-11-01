class_name BreakerSwitch
extends Interactable
## One of the three breakers that restore power. Throwing it sets the world flag named by
## `interaction_id` (switch_1..switch_3); WorldFlow raises `power_on` once all three are set.
## The housing is static scenery built by WorldFlow; this node owns the lever and the lamp.

const OFF_COLOR: Color = Color(0.9, 0.12, 0.08)
const ON_COLOR: Color = Color(0.25, 1.0, 0.4)

static var _lamp_off: StandardMaterial3D
static var _lamp_on: StandardMaterial3D
static var _lever_material: StandardMaterial3D

var is_on: bool = false

var _lever: Node3D
var _lamp: MeshInstance3D


func _ready() -> void:
	super._ready()
	one_shot = true
	if prompt_text == "Use":
		prompt_text = "Throw breaker"
	_build_visuals()
	sync_from_state()


func _build_visuals() -> void:
	if _lamp_off == null:
		_lamp_off = _unshaded(OFF_COLOR)
		_lamp_on = _unshaded(ON_COLOR)
		_lever_material = StandardMaterial3D.new()
		_lever_material.albedo_color = Color(0.75, 0.7, 0.2)
	_lever = Node3D.new()
	_lever.position = Vector3(0.0, 0.85, 0.22)
	add_child(_lever)
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.08, 0.42, 0.08)
	handle.mesh = handle_mesh
	handle.position = Vector3(0.0, 0.21, 0.0)
	handle.material_override = _lever_material
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lever.add_child(handle)
	_lamp = MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.16, 0.16, 0.06)
	_lamp.mesh = lamp_mesh
	_lamp.position = Vector3(0.0, 1.3, 0.2)
	_lamp.material_override = _lamp_off
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp)
	_lever.rotation.z = 0.7


func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Match the visuals to the saved world flag (scene reload / loaded game). No effect is triggered.
func sync_from_state() -> void:
	var state := get_node_or_null("/root/WorldState")
	if state and state.has_flag(interaction_id):
		mark_used(true)
		_apply(true, false)


func _apply(on: bool, animate: bool) -> void:
	is_on = on
	_lamp.material_override = _lamp_on if on else _lamp_off
	var angle := -0.7 if on else 0.7
	if animate and is_inside_tree():
		create_tween().tween_property(_lever, "rotation:z", angle, 0.2)
	else:
		_lever.rotation.z = angle


func _on_interact(_player: Node3D) -> void:
	_apply(true, true)
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(interaction_id, true)
