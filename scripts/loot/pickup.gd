class_name Pickup
extends Area3D
## A dropped item. Walk into it to collect. Weapons/armor that are not an upgrade stay on the ground.

const SCENE_PATH: String = "res://scenes/loot/Pickup.tscn"
const LIFETIME: float = 90.0
## Label readability: scale with camera distance (clamped) so it is never huge up close, and only the
## nearest few pickups show one so a pile of drops does not turn into a wall of text.
const LABEL_SCALE_MIN: float = 0.5
const LABEL_SCALE_MAX: float = 1.5
const LABEL_DISTANCE_PER_SCALE: float = 7.0
const LABEL_MAX_DISTANCE: float = 14.0
const LABEL_MAX_SHOWN: int = 3
const LABEL_REFRESH: float = 0.2
const LABEL_BASE_HEIGHT: float = 1.2
const LABEL_STACK_STEP: float = 0.45

static var _all: Array[Pickup] = []

var item: ItemData

var _age: float = 0.0
var _base_y: float = 0.0
var _mesh: MeshInstance3D
var _label: Label3D
var _label_clock: float = randf() * LABEL_REFRESH


static func spawn(parent: Node, new_item: ItemData, position: Vector3) -> Pickup:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null  # the scene was freed or reloaded before this deferred call ran
	var pickup := (load(SCENE_PATH) as PackedScene).instantiate() as Pickup
	pickup.item = new_item
	pickup.position = position  # before add_child so _ready sees the real height
	parent.add_child(pickup)
	return pickup


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	_base_y = position.y
	_mesh = $MeshInstance3D
	_label = $Label3D
	_all.append(self)
	var material := StandardMaterial3D.new()
	material.albedo_color = item.color()
	material.emission_enabled = true
	material.emission = item.color()
	material.emission_energy_multiplier = 0.6
	_mesh.material_override = material
	_label.text = item.display_name
	_label.modulate = item.color()
	_label.font_size = 28
	_label.outline_size = 8
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_age += delta
	_update_label(delta)
	position.y = _base_y + sin(_age * 3.0) * 0.12
	_mesh.rotation.y += delta * 2.0
	if _age > LIFETIME:
		queue_free()


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	if player.inventory.add_item(item):
		var upgrade := item.kind != ItemData.Kind.CONSUMABLE
		var audio := get_node_or_null("/root/AudioManager")
		if audio:
			audio.play(&"equip" if upgrade else &"pickup")
		queue_free()


func _exit_tree() -> void:
	_all.erase(self)


func _update_label(delta: float) -> void:
	_label_clock += delta
	if _label_clock < LABEL_REFRESH:
		return
	_label_clock = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var distance := camera.global_position.distance_to(global_position)
	_label.scale = Vector3.ONE * clampf(distance / LABEL_DISTANCE_PER_SCALE, LABEL_SCALE_MIN, LABEL_SCALE_MAX)
	var nearer := 0
	for other in _all:
		if other != self and is_instance_valid(other) \
				and camera.global_position.distance_to(other.global_position) < distance:
			nearer += 1
	_label.visible = distance <= LABEL_MAX_DISTANCE and nearer < LABEL_MAX_SHOWN
	# Drops lying close together stack their labels vertically (nearest lowest) instead of overprinting.
	_label.position.y = LABEL_BASE_HEIGHT + LABEL_STACK_STEP * nearer * _label.scale.y
