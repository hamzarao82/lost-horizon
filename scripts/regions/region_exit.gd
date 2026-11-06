class_name RegionExit
extends Area3D
## Walk into it to travel to another region. Locked regions refuse with a caption and keep the player here.

const REFUSE_COOLDOWN: float = 3.0

@export var exit_id: StringName = &""
@export var target_region: StringName = &""
@export var target_entry: StringName = &""
@export var size: Vector3 = Vector3(8.0, 3.0, 2.0)

var _refused_until: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # the player's body layer
	monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if not body is Player:
		return
	var manager := get_node_or_null("/root/RegionManager")
	if manager == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if not manager.is_unlocked(target_region):
		if now >= _refused_until:
			_refused_until = now + REFUSE_COOLDOWN
			manager.refuse(target_region)
		return
	manager.travel.call_deferred(target_region, target_entry)  # never reshape the physics world inside this callback
