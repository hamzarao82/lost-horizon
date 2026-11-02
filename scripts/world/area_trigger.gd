class_name AreaTrigger
extends Area3D
## A volume that reports the player entering an area once per entry: sets `discovered_<id>`,
## emits WorldState.area_entered(<id>) and the local `entered` signal.

signal entered(area_id: StringName)

@export var area_id: StringName
@export var size: Vector3 = Vector3(10.0, 6.0, 10.0)

var _inside: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # the player
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not (body is Player) or _inside:
		return
	_inside = true
	report_entered()


func _on_body_exited(body: Node3D) -> void:
	if body is Player:
		_inside = false


## Public so tests (and other triggers) can fire it without physics.
func report_entered() -> void:
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(StringName("discovered_" + String(area_id)), true)
		state.emit_area_entered(area_id)
	entered.emit(area_id)
