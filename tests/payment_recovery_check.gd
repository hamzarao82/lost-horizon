extends SceneTree
## Opening Milestone 12: the payment store, the recovery, the lockdown and the quest that ties them together.
## The bag must not be granted before the Area D Warden has fallen, before the store door is opened, before
## the interaction, or twice; a reload shows an empty shelf; the lockdown shuts both exits until the breaker.
##   godot --headless --path . -s tests/payment_recovery_check.gd

var _checks: int = 0
var _failures: int = 0
var _world: Node
var _qm: Node
var _regions: Node


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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _make_player() -> Player:
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(2)
	return player


func _fresh_state() -> void:
	_world.reset()
	_qm.reset()
	_regions.reset()


func _build_store() -> PaymentStore:
	var host := Node3D.new()
	root.add_child(host)
	var store := PaymentStore.build(host)
	await _frames(2)
	return store


func _run() -> void:
	_world = root.get_node("WorldState")
	_qm = root.get_node("QuestManager")
	_regions = root.get_node("RegionManager")
	_fresh_state()
	await _frames(3)

	var item := load("res://resources/items/payment_bag.tres") as ItemData
	_check(item != null and item.item_id == &"payment_bag" and item.unique and item.quest_item, "the payment bag is a unique quest item")
	_check(item.kind == ItemData.Kind.QUEST and not item.is_equipment(), "and it cannot be equipped")
	_check(load("res://resources/quests/campaign/opening_getaway.tres") != null, "the getaway quest resource loads")

	var player := await _make_player()
	var store := await _build_store()
	var rec := store.recovery
	var door := store.door
	_check(rec != null and door != null, "the store builds a door and a recovery interactable")
	_check(is_instance_valid(rec.bag) and PaymentBag.build() != null, "the bag prop is on the shelf, built by PaymentBag")

	# --- nothing before the Warden -------------------------------------------------------------
	_check(rec.locked and door.locked, "before the Warden falls both the store door and the bag are locked")
	_check(not rec.interact(player), "the bag cannot be taken yet")
	_check(not rec.grant(player), "grant() refuses before the Warden has fallen")
	_check(player.inventory.count_of("payment_bag") == 0, "no bag in the inventory")
	_check(not _world.has_flag(&"payment_recovered"), "the recovery flag is not set")
	var credits_before: int = player.inventory.currency
	_check(not door.interact(player), "the sealed store door will not open")

	# --- Warden down: the quest starts, the door can open ---------------------------------------
	# Only the generic flag, with NO warden_d_defeated: a save that beat the courtyard (wave 5) Warden must still work.
	_world.set_flag(&"boss_warden_defeated", true)
	await _frames(2)
	_check(_qm.is_active(&"opening_getaway"), "the getaway quest starts when either Warden falls (here only the generic flag is set)")
	_check(not door.locked, "the store door unlocks")
	_check(rec.locked, "but the bag stays locked while the door is shut")
	_check(not rec.interact(player), "the bag still cannot be taken through the shut door")
	_check(door.interact(player), "the store door opens")
	_check(_world.has_flag(&"door_payment_store_open"), "and sets its world flag")
	await _frames(2)
	var quest_before: Dictionary = {}
	_check(not _qm.is_completed(&"opening_getaway"), "the quest is not complete after finding the store")
	_check(not rec.locked, "the bag is now takeable")

	# --- the recovery -----------------------------------------------------------------------
	_check(rec.interact(player), "taking the bag works")
	await _frames(2)
	_check(player.inventory.count_of("payment_bag") == 1, "exactly one bag is in the inventory")
	_check(player.inventory.currency == credits_before + PaymentRecovery.CREDITS, "the credits were added (%d)" % PaymentRecovery.CREDITS)
	_check(_world.has_flag(&"payment_recovered"), "payment_recovered is set")
	_check(rec.bag == null, "the shelf prop is removed")
	_check(not rec.interact(player), "the interaction cannot repeat")
	_check(not rec.grant(player), "grant() cannot run a second time")
	_check(player.inventory.count_of("payment_bag") == 1 and player.inventory.currency == credits_before + PaymentRecovery.CREDITS, "still one bag and one payment")
	_check(not player.inventory.collect(item)["added"] > 0, "the inventory's own unique rule also refuses a duplicate")

	# --- the lockdown ---------------------------------------------------------------------
	_check(_world.has_flag(&"getaway_lockdown"), "the alarm lockdown starts after the recovery")
	_check(store.shutters.size() == 2, "two shutters shut the two region exits")
	var all_locked := true
	for shutter in store.shutters:
		all_locked = all_locked and shutter.locked and not shutter.is_open
	_check(all_locked, "both shutters are shut and locked")
	_check(store.guards.size() >= 2 and store.guards.size() <= 3, "two or three guards come (%d), no wave" % store.guards.size())
	_check(not _qm.is_completed(&"opening_getaway"), "the quest is not complete until the way out is open")
	_check(not _world.has_flag(&"opening_arc_complete"), "the opening arc is not closed yet")
	var breaker := store.breaker
	_check(not breaker.locked, "the breaker is usable during the lockdown")
	_check(breaker.interact(player), "the breaker is thrown")
	await _frames(2)
	_check(_world.has_flag(&"lockdown_lifted"), "lockdown_lifted is set")
	var all_open := true
	for shutter in store.shutters:
		all_open = all_open and shutter.is_open
	_check(all_open, "both shutters open")
	_check(_world.has_flag(&"opening_arc_complete"), "the opening arc is closed (the ending is due once)")
	_check(not OpeningEnding.should_play(_world), "and the ending will not be due again")
	_check(_qm.is_completed(&"opening_getaway"), "the getaway quest completes")
	_check(_qm.is_active(&"leave_outpost") or _qm.is_completed(&"leave_outpost"), "the road quest is handed on")
	_check(not breaker.interact(player), "the breaker cannot be reused")

	# --- reload: an empty shelf, no second bag --------------------------------------------------
	for node in root.get_children():
		if node is Node3D and node != player and node.has_node("PaymentStore"):
			node.free()
	await _frames(2)
	var store2 := await _build_store()
	_check(store2.recovery.bag == null, "after a reload the shelf is empty")
	_check(store2.recovery.is_recovered() and not store2.recovery.interact(player), "the recovery cannot be repeated after a reload")
	_check(store2.shutters.is_empty(), "no new lockdown after the way out was opened")
	_check(player.inventory.count_of("payment_bag") == 1, "still one bag")

	# --- the claim holds even if a flag is lost ---------------------------------------------------
	_world.set_flag(&"payment_recovered", false)
	var player_b := await _make_player()
	_check(not store2.recovery.grant(player_b), "a lost flag cannot mint a second bag: the persistent claim refuses")
	_check(player_b.inventory.count_of("payment_bag") == 0, "the second player got nothing")

	# --- id safety ---------------------------------------------------------------------------------
	for id in [&"payment_recovered", &"warden_d_defeated", &"getaway_lockdown", &"lockdown_lifted", &"opening_arc_complete", &"door_payment_store_open", &"payment_bag", &"opening_getaway"]:
		var s := String(id)
		_check(s.length() <= 48 and s == s.to_lower() and s.is_valid_identifier(), "id '%s' fits WorldState's rule" % s)

	_fresh_state()
	print("payment_recovery_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
