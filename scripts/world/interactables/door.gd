class_name Door
extends Interactable
## A sliding door in a wall gap. A real collider until opened; opening is remembered in WorldState
## (`door_<id>_open`) so it stays open after a death restart. Locked by an optional flag.

const OPEN_SECONDS: float = 1.0

@export var door_id: StringName = &"door"
@export var width: float = 4.0
@export var height: float = 4.0
## While this WorldState flag is missing the door cannot be used (empty = never locked).
@export var locked_by_flag: StringName = &""
@export var lock_reason: String = "Locked"

var is_open: bool = false

var _shape: CollisionShape3D
var _leaf: MeshInstance3D

static var _leaf_material: StandardMaterial3D


func _ready() -> void:
	super._ready()
	add_to_group("doors")
	if interaction_id == &"":
		interaction_id = StringName("door_" + String(door_id))
	prompt_text = "Open door"
	locked_text = lock_reason
	interact_radius = maxf(interact_radius, 3.2)
	_build()
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.flag_changed.connect(_on_flag_changed)
		if state.has_flag(open_flag()):
			open(false)
	_refresh_lock()


func open_flag() -> StringName:
	return StringName("door_%s_open" % String(door_id))


func _build() -> void:
	if _leaf_material == null:
		_leaf_material = StandardMaterial3D.new()
		_leaf_material.albedo_color = Color(0.3, 0.33, 0.32)
		_leaf_material.roughness = 0.7
	var body := StaticBody3D.new()
	body.name = "DoorBody"  # layer 1 (world): blocks the player and enemies until opened
	add_child(body)
	_shape = CollisionShape3D.new()
	_shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.8)
	_shape.shape = box
	_shape.position = Vector3(0.0, height * 0.5, 0.0)
	body.add_child(_shape)
	_leaf = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width - 0.1, height - 0.3, 0.3)
	_leaf.mesh = mesh
	_leaf.position = Vector3(0.0, (height - 0.3) * 0.5 + 0.05, 0.0)
	_leaf.material_override = _leaf_material
	_leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_leaf)


func _refresh_lock() -> void:
	if is_open:
		locked = false
		return
	var state := get_node_or_null("/root/WorldState")
	locked = locked_by_flag != &"" and not (state != null and state.has_flag(locked_by_flag))


func _on_flag_changed(id: StringName, _value: bool) -> void:
	if id == locked_by_flag or id == &"*":
		_refresh_lock()


func _on_interact(_player: Node3D) -> void:
	open(true)


## Slides the leaf up and removes the collider. Safe to call twice.
func open(animate: bool = true) -> void:
	if is_open:
		return
	is_open = true
	enabled = false
	locked = false
	_shape.set_deferred("disabled", true)
	var target := Vector3(_leaf.position.x, _leaf.position.y + height - 0.2, _leaf.position.z)
	if animate and is_inside_tree():
		create_tween().tween_property(_leaf, "position", target, OPEN_SECONDS)
		var audio := get_node_or_null("/root/AudioManager")
		if audio and audio.has_method("play"):
			audio.play(&"equip", -4.0, 0.0)
	else:
		_leaf.position = target
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(open_flag(), true)
