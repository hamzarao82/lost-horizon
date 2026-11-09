class_name RegionGate
extends Node3D
## A visible gate just beyond a stage's forward exit trigger. While the next region is locked it is a
## barricade with a "ROAD CLOSED" sign (walking up to it still shows the exit's refusal caption: the
## trigger sits in front of the barricade); when the next region unlocks the barricade goes away and a lit
## door marked "ROAD TO <NEXT STAGE>" shows where the way on is. Same look as Outpost 17's beach gate.
## Holds no saved state: it only reads the `<next>_unlocked` flag, so loading a save can never desync it.

const BARRICADE_NAME: String = "Barricade"
const DOOR_NAME: String = "OpenRoad"

var next_region: StringName = &""
var next_label: String = ""
var width: float = 16.0
## 0 faces +z (the sign is read by a player walking north, toward -z); PI faces -z.
var face_yaw: float = 0.0

var _barricade: Node3D
var _door: Node3D
var _world: Node


## `at` is the gate position (the exit's position pushed 2.8 m on towards the way on).
static func attach(parent: Node3D, next: StringName, label: String, at: Vector3, gate_width: float = 16.0,
		yaw: float = 0.0) -> RegionGate:
	var gate := RegionGate.new()
	gate.name = "RegionGate_%s" % String(next)
	gate.next_region = next
	gate.next_label = label
	gate.width = gate_width
	gate.face_yaw = yaw
	gate.position = at  # set before add_child
	parent.add_child(gate)
	return gate


func is_open() -> bool:
	return _world != null and _world.has_flag(CampaignFlow.unlock_flag(next_region))


func _ready() -> void:
	add_to_group("region_gates")
	_world = get_node_or_null("/root/WorldState")
	if _world != null and _world.has_signal("flag_changed"):
		_world.flag_changed.connect(_on_flag_changed)
	_refresh()


func _on_flag_changed(_id: StringName, _value: bool) -> void:
	_refresh()


func _refresh() -> void:
	if is_open():
		if _barricade != null and is_instance_valid(_barricade):
			_barricade.queue_free()
		_barricade = null
		if _door == null or not is_instance_valid(_door):
			_door = _build_door()
			add_child(_door)
	else:
		if _door != null and is_instance_valid(_door):
			_door.queue_free()
		_door = null
		if _barricade == null or not is_instance_valid(_barricade):
			_barricade = _build_barricade()
			add_child(_barricade)


func _build_barricade() -> Node3D:
	var root := Node3D.new()
	root.name = BARRICADE_NAME
	root.rotation.y = face_yaw
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 1.8, 0.8)
	shape.shape = box
	shape.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(shape)
	root.add_child(body)
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	mesh.position = shape.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.72, 0.36, 0.12)
	material.roughness = 0.9
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	root.add_child(_sign("ROAD CLOSED", Color(1.0, 0.92, 0.7), Color(0.1, 0.05, 0.0), Vector3(0.0, 1.1, 0.45)))
	return root


func _build_door() -> Node3D:
	var root := Node3D.new()
	root.name = DOOR_NAME
	root.rotation.y = face_yaw
	var mesh := MeshInstance3D.new()
	var visual := BoxMesh.new()
	visual.size = Vector3(5.0, 3.4, 0.25)
	mesh.mesh = visual
	mesh.position = Vector3(0.0, 1.7, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.35, 0.2)
	material.emission_enabled = true
	material.emission = Color(0.2, 0.9, 0.45)
	material.emission_energy_multiplier = 0.35
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	root.add_child(_sign("ROAD TO %s" % next_label.to_upper(), Color(0.75, 1.0, 0.8), Color(0.0, 0.1, 0.03), Vector3(0.0, 3.9, 0.2)))
	return root


func _sign(text: String, color: Color, outline: Color, at: Vector3) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_modulate = outline
	label.position = at
	return label
