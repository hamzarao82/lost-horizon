class_name Pickup
extends Area3D
## A dropped item. Walk into it to collect. Weapons/armor that are not an upgrade stay on the ground.

const SCENE_PATH: String = "res://scenes/loot/Pickup.tscn"
const LIFETIME: float = 90.0

var item: ItemData

var _age: float = 0.0
var _base_y: float = 0.0
var _mesh: MeshInstance3D


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
	var material := StandardMaterial3D.new()
	material.albedo_color = item.color()
	material.emission_enabled = true
	material.emission = item.color()
	material.emission_energy_multiplier = 0.6
	_mesh.material_override = material
	($Label3D as Label3D).text = item.display_name
	($Label3D as Label3D).modulate = item.color()
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_age += delta
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
