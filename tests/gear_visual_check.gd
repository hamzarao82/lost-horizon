extends SceneTree
## Worn gear shows on the player skeleton per slot and disappears when unequipped, with no leaks.
##   godot --headless --path . -s tests/gear_visual_check.gd

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const ITEMS: String = "res://resources/items/"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _item(id: String) -> ItemData:
	return load(ITEMS + id + ".tres") as ItemData


func _socket(player: Node, slot: int, bone: StringName) -> WeaponSocket:
	return player.find_child(GearVisuals.socket_name(slot, bone), true, false) as WeaponSocket


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _run() -> void:
	# the data table is the only place that maps items to models
	for id in GearVisuals.MODELS:
		_check(ResourceLoader.exists(GearVisuals.ARMOR_DIR + String(GearVisuals.MODELS[id])), "model file exists for %s" % id)
		_check(_item(String(id)) != null, "item resource exists for %s" % id)
	var player := load(PLAYER_SCENE).instantiate() as Player
	root.add_child(player)
	await _frames(6)
	var visual := player.find_children("*", "SkinnedVisual", true, false)
	_check(not visual.is_empty(), "the player has a SkinnedVisual")
	if visual.is_empty():
		quit(1)
		return
	var skinned := visual[0] as SkinnedVisual
	_check(skinned.loaded and skinned.gear != null, "the skinned model loaded and has gear visuals")
	if skinned.gear == null:
		print("gear_visual_check: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	_check(skinned.gear.socket_count() == 5, "five gear sockets exist: head, two hands, two feet (%d)" % skinned.gear.socket_count())
	var slots := {
		ItemData.Slot.HEAD: [&"Head"],
		ItemData.Slot.GLOVES: [&"Hand_R", &"Hand_L"],
		ItemData.Slot.LEGS: [&"Foot_R", &"Foot_L"],
	}
	for slot in slots:
		for bone in slots[slot]:
			var socket := _socket(player, slot, bone)
			_check(socket != null, "socket %s exists" % GearVisuals.socket_name(slot, bone))
			_check(socket != null and socket.held() == null, "nothing is shown on %s before equipping" % bone)
	var inv: Inventory = player.inventory
	var pieces := {
		ItemData.Slot.HEAD: "combat_helmet",
		ItemData.Slot.GLOVES: "tactical_gloves",
		ItemData.Slot.LEGS: "field_boots",
	}
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for slot in pieces:
		var item := _item(pieces[slot])
		inv.collect(item)
		var result := inv.equip(item)
		_check(bool(result.get("ok", false)), "%s equips (%s)" % [pieces[slot], str(result.get("reason", "ok"))])
		await _frames(2)
		for bone in slots[slot]:
			var socket := _socket(player, slot, bone)
			var held := socket.held() if socket else null
			_check(held != null, "%s shows on %s when equipped" % [pieces[slot], bone])
			_check(held != null and not held.find_children("*", "MeshInstance3D", true, false).is_empty(), "the model on %s has a mesh" % bone)
		_check(skinned.gear.shown(slot) == StringName(pieces[slot]), "gear state reports %s for the slot" % pieces[slot])
	# unequipping one slot hides only that slot
	var unequip := inv.unequip(ItemData.Slot.GLOVES)
	_check(bool(unequip.get("ok", false)), "gloves unequip (%s)" % str(unequip.get("reason", "ok")))
	await _frames(3)
	_check(_socket(player, ItemData.Slot.GLOVES, &"Hand_R").held() == null and _socket(player, ItemData.Slot.GLOVES, &"Hand_L").held() == null,
			"both hands are empty after unequipping the gloves")
	_check(_socket(player, ItemData.Slot.HEAD, &"Head").held() != null, "the helmet stays when only the gloves are removed")
	_check(_socket(player, ItemData.Slot.LEGS, &"Foot_R").held() != null, "the boots stay when only the gloves are removed")
	# repeated cycles do not leak nodes
	var glove := _item("tactical_gloves")
	for i in 6:
		inv.equip(glove)
		await _frames(2)
		inv.unequip(ItemData.Slot.GLOVES)
		await _frames(2)
	await _frames(4)
	inv.unequip(ItemData.Slot.HEAD)
	inv.unequip(ItemData.Slot.LEGS)
	await _frames(4)
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check(nodes_after <= nodes_before, "no nodes leak after equip and unequip cycles (%d before, %d after)" % [nodes_before, nodes_after])
	for slot in slots:
		for bone in slots[slot]:
			_check(_socket(player, slot, bone).held() == null, "%s is empty at the end" % bone)
	print("gear_visual_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
