class_name GearVisuals
extends RefCounted
## Shows worn head, glove and leg gear on the player skeleton. One data table maps an item id to its
## model; every slot maps to the bones it is worn on. Sockets are WeaponSockets (BoneAttachment3D)
## created once; equipping holds an instance, unequipping empties the socket.

const ARMOR_DIR: String = "res://assets/armor/"

## item_id -> model file. Add an entry to dress a new item; no other code changes.
const MODELS: Dictionary = {
	&"combat_helmet": "combat_helmet.glb",
	&"tactical_gloves": "tactical_gloves.glb",
	&"field_boots": "field_boots.glb",
}

## Equipment slot -> bones that wear it (the model is symmetric, so one model serves both sides).
const SLOT_BONES: Dictionary = {
	ItemData.Slot.HEAD: [&"Head"],
	ItemData.Slot.GLOVES: [&"Hand_R", &"Hand_L"],
	ItemData.Slot.LEGS: [&"Foot_R", &"Foot_L"],
}

var _sockets: Dictionary = {}  # "slot:bone" -> WeaponSocket
var _shown: Dictionary = {}    # slot -> item_id currently shown
var _scenes: Dictionary = {}   # item_id -> PackedScene


static func socket_name(slot: int, bone: StringName) -> String:
	return "Gear_%s_%s" % [ItemData.SLOT_NAMES[slot], bone]


func attach(skeleton: Skeleton3D) -> void:
	for slot in SLOT_BONES:
		for bone in SLOT_BONES[slot]:
			var socket := WeaponSocket.attach(skeleton, bone, socket_name(slot, bone))
			if socket:
				_sockets["%d:%s" % [slot, bone]] = socket


## Brings the worn visuals in line with the inventory. Cheap when nothing changed.
func refresh(inventory: Inventory) -> void:
	if inventory == null:
		return
	for slot in SLOT_BONES:
		var item := inventory.equipped(slot)
		var item_id: StringName = item.item_id if item else &""
		if _shown.get(slot, &"") == item_id:
			continue
		_shown[slot] = item_id
		for bone in SLOT_BONES[slot]:
			var socket := _sockets.get("%d:%s" % [slot, bone]) as WeaponSocket
			if socket == null:
				continue
			var scene := _scene_for(item_id)
			socket.hold(scene.instantiate() as Node3D if scene else null)


func shown(slot: int) -> StringName:
	return _shown.get(slot, &"")


func socket_count() -> int:
	return _sockets.size()


func _scene_for(item_id: StringName) -> PackedScene:
	if item_id == &"" or not MODELS.has(item_id):
		return null
	if not _scenes.has(item_id):
		var path: String = ARMOR_DIR + String(MODELS[item_id])
		_scenes[item_id] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[item_id]
