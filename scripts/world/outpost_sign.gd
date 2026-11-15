class_name OutpostSign
extends Node3D
## The weathered "OUTPOST 17" plate at the compound entrance. Walking up to it is how the player learns the
## name: it sets `outpost_name_known` once, starts the First Signal if it has not started, and starts the
## short contextual quest "Search Outpost 17." Placed by the region builder with OutpostSign.place().

const SEARCH_QUEST: StringName = &"search_outpost"
const TRIGGER_RADIUS: float = 4.5

var revealed: bool = false

var _trigger: Area3D


static func place(parent: Node, at: Vector3) -> OutpostSign:
	var sign_node := OutpostSign.new()
	sign_node.name = "OutpostSign"
	sign_node.position = at
	parent.add_child(sign_node)
	return sign_node


func _ready() -> void:
	_build_plate()
	_trigger = Area3D.new()
	_trigger.name = "Trigger"
	_trigger.collision_layer = 0
	_trigger.collision_mask = 2
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	_trigger.add_child(shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)
	var world := get_node_or_null("/root/WorldState")
	revealed = world != null and world.has_method("has_flag") and world.has_flag(RegionLabel.KNOWN_FLAG)


func _build_plate() -> void:
	for x in [-1.1, 1.1]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.18, 2.6, 0.18)
		post.mesh = post_mesh
		post.position = Vector3(x, 1.3, 0.0)
		post.material_override = _material(Color(0.28, 0.2, 0.13))
		post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(post)
	var plate := MeshInstance3D.new()
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(2.6, 0.9, 0.08)
	plate.mesh = plate_mesh
	plate.position = Vector3(0.0, 2.2, 0.0)
	plate.material_override = _material(Color(0.36, 0.34, 0.3))
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plate)
	var label := Label3D.new()
	label.text = "OUTPOST 17"
	label.font_size = 96
	label.pixel_size = 0.0065
	label.modulate = Color(0.78, 0.74, 0.62)
	label.outline_size = 8
	label.position = Vector3(0.0, 2.2, 0.06)
	label.double_sided = true
	add_child(label)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


func _on_body_entered(body: Node3D) -> void:
	if body is Player:
		reveal()


## Idempotent: the flag, the First Signal and the search quest are each started at most once.
func reveal() -> void:
	var world := get_node_or_null("/root/WorldState")
	var quests := get_node_or_null("/root/QuestManager")
	if world == null or quests == null:
		return
	var first_time: bool = not world.has_flag(RegionLabel.KNOWN_FLAG)
	world.set_flag(RegionLabel.KNOWN_FLAG, true)
	revealed = true
	if first_time:
		quests.say("OUTPOST 17. Painted over, but you can still read it.", 4.0)
	if not quests.is_active(&"first_signal") and not quests.is_completed(&"first_signal"):
		quests.start_quest(&"first_signal")
	if not quests.is_active(SEARCH_QUEST) and not quests.is_completed(SEARCH_QUEST):
		if quests.start_quest(SEARCH_QUEST, true) and quests.tracker_first == &"":
			quests.tracker_first = SEARCH_QUEST
