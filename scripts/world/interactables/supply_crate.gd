class_name SupplyCrate
extends Interactable
## A one-time supply crate: opening it drops its items as normal pickups next to it.
## Taken crates are remembered through the world flag `<crate_id>_taken`, so they stay open after a
## death restart and cannot be looted twice.

@export var crate_id: StringName = &"crate_1"
@export var loot_paths: PackedStringArray = PackedStringArray()
## Extra weighted roll on top of the fixed items (materials, credits); "" disables it. Hidden caches use crate_hidden.
@export var bonus_table_path: String = "res://resources/loot/crate_common.tres"


static var _wood: StandardMaterial3D
static var _lid_wood: StandardMaterial3D

var _lid: Node3D


func _ready() -> void:
	super._ready()
	one_shot = true
	if prompt_text == "Use":
		prompt_text = "Open crate"
	interaction_id = crate_id
	_build_visuals()
	var state := get_node_or_null("/root/WorldState")
	if state and state.has_flag(_taken_flag()):
		mark_used(true)
		_set_open(true, false)


func _taken_flag() -> StringName:
	return StringName(String(crate_id) + "_taken")


func _build_visuals() -> void:
	if _wood == null:
		_wood = StandardMaterial3D.new()
		_wood.albedo_color = Color(0.46, 0.33, 0.2)
		_lid_wood = StandardMaterial3D.new()
		_lid_wood.albedo_color = Color(0.55, 0.4, 0.25)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(1.1, 0.75, 0.85)
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.375, 0.0)
	body.material_override = _wood
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(body)
	_lid = Node3D.new()
	_lid.position = Vector3(0.0, 0.75, -0.42)  # hinge on the back top edge
	add_child(_lid)
	var lid_mesh_node := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.16, 0.12, 0.9)
	lid_mesh_node.mesh = lid_mesh
	lid_mesh_node.position = Vector3(0.0, 0.06, 0.44)
	lid_mesh_node.material_override = _lid_wood
	lid_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lid.add_child(lid_mesh_node)


func _set_open(open: bool, animate: bool) -> void:
	var angle := -1.9 if open else 0.0
	if animate and is_inside_tree():
		create_tween().tween_property(_lid, "rotation:x", angle, 0.35)
	else:
		_lid.rotation.x = angle


func _on_interact(_player: Node3D) -> void:
	_set_open(true, true)
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(_taken_flag(), true)
	_drop_loot()
	_drop_bonus()


func _drop_loot() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for i in loot_paths.size():
		var item := load(loot_paths[i]) as ItemData
		if item == null:
			continue
		# Fan the items out in front of the crate (south, toward where the player stands).
		var spread := Vector3((float(i) - (loot_paths.size() - 1) * 0.5) * 0.9, 0.0, 1.3)
		var spot := global_position + spread
		spot.y = global_position.y
		Pickup.spawn(parent, item, spot)


## Rolls the bonus table once at opening; the crate itself stays one-shot through its world flag, so
## a reload cannot roll it again. Unique items already received never drop.
func _drop_bonus() -> void:
	var parent := get_parent()
	var table := load(bonus_table_path) as LootTable if bonus_table_path != "" else null
	if parent == null or table == null:
		return
	var claimed: Dictionary = {}
	var player := get_tree().get_first_node_in_group("player") as Player
	if player and player.inventory:
		claimed = player.inventory.unique_claimed
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var index := 0
	for entry in table.roll_all(rng, claimed):
		for n in mini(int(entry["count"]), 3):
			var spot := global_position + Vector3((float(index) - 1.0) * 0.8, 0.0, -1.2)
			spot.y = global_position.y
			Pickup.spawn(parent, entry["item"], spot)
			index += 1
