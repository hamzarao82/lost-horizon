class_name EncounterGroup
extends Node3D
## A small patrol-free encounter: 2-4 existing enemies that do not exist until the player enters
## an area. When all of them are dead the group sets `encounter_<id>_cleared` and drops the access
## card. Uses the existing enemy AI unchanged (they start idle and notice the player on their own).

@export var group_id: StringName = &"b"
@export var scene_paths: PackedStringArray
@export var offsets: PackedVector3Array
@export var trigger_area: StringName = &"area_b_compound"
@export var card_position: Vector3 = Vector3(0.0, 0.9, 0.0)

var spawned: bool = false
var cleared: bool = false

var _alive: int = 0


func _ready() -> void:
	var state := get_node_or_null("/root/WorldState")
	if state == null:
		return
	if state.has_flag(cleared_flag()):
		cleared = true
		spawned = true
		return
	state.area_entered.connect(_on_area_entered)


func cleared_flag() -> StringName:
	return StringName("encounter_%s_cleared" % String(group_id))


func _on_area_entered(id: StringName) -> void:
	if id == trigger_area:
		spawn()


## Spawns the group once (positions are set before entering the tree, like wave spawns).
func spawn() -> void:
	if spawned:
		return
	spawned = true
	var parent := get_parent()
	for i in scene_paths.size():
		var scene := load(scene_paths[i]) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate() as Node3D
		enemy.position = position + (offsets[i] if i < offsets.size() else Vector3.ZERO)
		parent.add_child(enemy)
		if enemy.has_signal("defeated"):
			enemy.connect("defeated", _on_defeated.bind(enemy))
			_alive += 1


func _on_defeated(last: Node3D) -> void:
	_alive -= 1
	if _alive > 0 or cleared:
		return
	cleared = true
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(cleared_flag(), true)
	var drop := (last.position + Vector3(0.0, 0.8, 0.0)) if is_instance_valid(last) else (position + card_position)
	Keycard.spawn(get_parent(), drop, &"has_access_card", "Access Card")
