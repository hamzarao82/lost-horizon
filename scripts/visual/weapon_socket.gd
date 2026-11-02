class_name WeaponSocket
extends BoneAttachment3D
## A bone attachment with an adjustable holder: whatever is held follows the bone, and the holder's
## offset/rotation can be tuned (in the editor or from the owning visual) without touching the model.
## Used on Hand_R (weapon) and Chest (armor plate).

@export var position_offset: Vector3 = Vector3.ZERO:
	set(value):
		position_offset = value
		_apply_offsets()
@export var rotation_offset_deg: Vector3 = Vector3.ZERO:
	set(value):
		rotation_offset_deg = value
		_apply_offsets()

var holder: Node3D


## Creates the socket as a child of `skeleton` on `bone`. Returns null when the bone does not exist.
static func attach(skeleton: Skeleton3D, bone: StringName, socket_name: String) -> WeaponSocket:
	if skeleton == null or skeleton.find_bone(String(bone)) < 0:
		return null
	var socket := WeaponSocket.new()
	socket.name = socket_name
	skeleton.add_child(socket)
	socket.bone_name = String(bone)
	socket.holder = Node3D.new()
	socket.holder.name = "Holder"
	socket.add_child(socket.holder)
	socket._apply_offsets()
	return socket


func _apply_offsets() -> void:
	if holder == null:
		return
	holder.position = position_offset
	holder.rotation_degrees = rotation_offset_deg


## Replaces whatever is held. Pass null to just empty the socket.
func hold(node: Node3D) -> void:
	clear()
	if node and holder:
		holder.add_child(node)


func clear() -> void:
	if holder == null:
		return
	for child in holder.get_children():
		holder.remove_child(child)
		child.queue_free()


func held() -> Node3D:
	if holder and holder.get_child_count() > 0:
		return holder.get_child(0) as Node3D
	return null
