class_name WorldGate
extends Node3D
## The south gate of the courtyard. It is a real collider until `power_on` is set, then the two
## leaves slide apart and the collider is switched off. State comes from WorldState, so a gate that
## was opened stays open after a death restart.

const HALF_WIDTH: float = 4.0
const HEIGHT: float = 4.0
const OPEN_SECONDS: float = 1.4

static var _metal: StandardMaterial3D
static var _post_metal: StandardMaterial3D

var is_open: bool = false
var interactable: Interactable

var _body: StaticBody3D
var _shape: CollisionShape3D
var _left: MeshInstance3D
var _right: MeshInstance3D


func _ready() -> void:
	_build()
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.flag_changed.connect(_on_flag_changed)
		if state.has_flag(&"power_on"):
			open(false)
	if interactable and not is_open:
		interactable.locked = not (state != null and state.has_flag(&"power_on"))


func _build() -> void:
	if _metal == null:
		_metal = StandardMaterial3D.new()
		_metal.albedo_color = Color(0.36, 0.4, 0.34)
		_metal.roughness = 0.7
		_post_metal = StandardMaterial3D.new()
		_post_metal.albedo_color = Color(0.25, 0.27, 0.25)
	_body = StaticBody3D.new()
	_body.name = "GateBody"
	add_child(_body)
	_shape = CollisionShape3D.new()
	_shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(HALF_WIDTH * 2.0, HEIGHT, 1.0)
	_shape.shape = box
	_shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	_body.add_child(_shape)
	_left = _leaf(-HALF_WIDTH * 0.5)
	_right = _leaf(HALF_WIDTH * 0.5)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.5, HEIGHT + 0.6, 0.6)
		post.mesh = post_mesh
		post.position = Vector3(float(side) * (HALF_WIDTH + 0.25), (HEIGHT + 0.6) * 0.5, 0.0)
		post.material_override = _post_metal
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(post)
	interactable = Interactable.new()
	interactable.name = "GateInteract"
	interactable.interaction_id = &"gate"
	interactable.prompt_text = "Open gate"
	interactable.locked_text = "Gate locked: no power"
	interactable.interact_radius = 3.2
	interactable.locked = true
	interactable.position = Vector3(0.0, 1.0, 0.8)
	add_child(interactable)


func _leaf(x: float) -> MeshInstance3D:
	var leaf := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(HALF_WIDTH - 0.05, HEIGHT - 0.4, 0.22)
	leaf.mesh = mesh
	leaf.position = Vector3(x, (HEIGHT - 0.4) * 0.5 + 0.1, 0.0)
	leaf.material_override = _metal
	leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leaf)
	return leaf


func _on_flag_changed(id: StringName, value: bool) -> void:
	if id == &"power_on" and value:
		open(true)


## Slides the leaves apart and removes the collider. Safe to call twice.
func open(animate: bool = true) -> void:
	if is_open:
		return
	is_open = true
	_shape.set_deferred("disabled", true)
	if interactable:
		interactable.enabled = false
		interactable.locked = false
	var target_left := -HALF_WIDTH * 1.5 + 0.1
	var target_right := HALF_WIDTH * 1.5 - 0.1
	if animate and is_inside_tree():
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_left, "position:x", target_left, OPEN_SECONDS)
		tween.tween_property(_right, "position:x", target_right, OPEN_SECONDS)
		var audio := get_node_or_null("/root/AudioManager")
		if audio and audio.has_method("play"):
			audio.play(&"equip", -4.0, 0.0)
	else:
		_left.position.x = target_left
		_right.position.x = target_right
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(&"gate_open", true)
