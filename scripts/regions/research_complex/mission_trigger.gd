class_name MissionTrigger
extends Area3D
## An invisible box. The first time the player walks into it, it fires a quest event once
## (`WorldState.area_entered(event_id)`), remembered through PersistentIds so a reload does not repeat it.
## Quest objectives already remember events that happened out of order, so firing early never blocks one.

signal fired(event_id: StringName)

@export var trigger_id: StringName = &"trigger"
@export var event_id: StringName = &""
@export var region_id: StringName = FacilityIds.REGION
@export var size: Vector3 = Vector3(4.0, 3.0, 4.0)

var _fired: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # the player's layer
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(shape)
	body_entered.connect(_on_body_entered)
	if PersistentIds.is_claimed(region_id, claim_id()):
		_fired = true


func claim_id() -> StringName:
	return StringName("trigger_%s" % String(trigger_id))


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		fire()


## Returns true only the first time it fires in this save.
func fire() -> bool:
	if _fired:
		return false
	_fired = true
	PersistentIds.claim(region_id, claim_id())
	var id := event_id if event_id != &"" else trigger_id
	var state := get_node_or_null("/root/WorldState")
	if state != null:
		state.emit_area_entered(id)
	fired.emit(id)
	return true
