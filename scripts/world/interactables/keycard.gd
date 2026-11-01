class_name Keycard
extends Area3D
## The command keycard. WorldFlow drops it in the courtyard when the last wave (the Warden) is
## cleared. Walking into it sets the world flag `has_keycard`, which unlocks the command terminal.

static var _material: StandardMaterial3D

var _age: float = 0.0
var _base_y: float = 0.0
var _mesh: MeshInstance3D


static func spawn(parent: Node, position: Vector3) -> Keycard:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var card := Keycard.new()
	card.position = position  # before add_child, so _ready sees the real height
	parent.add_child(card)
	return card


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	_base_y = position.y
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1
	shape.shape = sphere
	add_child(shape)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(1.0, 0.75, 0.2)
		_material.emission_enabled = true
		_material.emission = Color(1.0, 0.7, 0.15)
		_material.emission_energy_multiplier = 0.8
	_mesh = MeshInstance3D.new()
	var card := BoxMesh.new()
	card.size = Vector3(0.5, 0.06, 0.32)
	_mesh.mesh = card
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	var label := Label3D.new()
	label.text = "Command Keycard"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.008
	label.modulate = Color(1.0, 0.85, 0.4)
	label.position = Vector3(0.0, 0.7, 0.0)
	add_child(label)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_age += delta
	position.y = _base_y + sin(_age * 3.0) * 0.1
	_mesh.rotation.y += delta * 2.0


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player):
		return
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(&"has_keycard", true)
		state.emit_interacted(&"keycard")
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play"):
		audio.play(&"equip")
	queue_free()
