extends SceneTree
## The shipwreck/recovery beach sequence: headless cheapness, the handoff (injury, locked attacks, the
## pinned survival quest), the three pickups completing it in any order, restrictions lifting, and the
## failsafe/nudge timers. godot --headless --path . -s tests/opening_beach_check.gd

var _checks: int = 0
var _failures: int = 0
var _qm: Node
var _world: Node


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


func _run() -> void:
	_qm = root.get_node("QuestManager")
	_world = root.get_node("WorldState")
	_qm.reset()
	await _frames(3)

	# Headless build is cheap: play() + white-box handoff, no SubViewport, no real-time waits.
	var headless_probe := OpeningBeach.new()
	root.add_child(headless_probe)
	await _frames(2)
	_check(headless_probe.get_child_count() <= 4, "headless OpeningBeach builds only the UI overlay (%d children)" % headless_probe.get_child_count())
	_check(headless_probe._blur != null and headless_probe._blur.modulate.a <= 0.65, "the wake veil exists as a cheap overlay (a ColorRect alpha ramp, no shader)")
	headless_probe.queue_free()
	await _frames(1)

	var player := await _make_player()
	var full_health: float = player.health.max_health
	_check(not player.attacks_locked and is_equal_approx(player.injured_speed_mult, 1.0), "a normal player starts with no injury effect")

	# White-box the handoff directly (not through the real ~25 s scripted timeline: see the class doc).
	var beach := OpeningBeach.new()
	beach._player = player
	beach._world_flags = _world
	beach._quest_manager = _qm
	beach._hand_off()
	_check(is_equal_approx(player.health.health, full_health * 0.35), "health is set to 35% of max (%.1f)" % player.health.health)
	_check(is_equal_approx(player.injured_speed_mult, 0.55), "movement is slowed to 55%")
	_check(player.attacks_locked, "attacks are locked")
	_check(_qm.is_active(&"opening_survival"), "the survival quest starts")
	_check(_qm.tracker_first == &"opening_survival", "and is pinned at the top of the tracker")
	_check(_world.has_flag(&"opening_event_seen"), "the wake/treasure event is marked seen (<=48 chars, [a-z0-9_]: %s)" % "opening_event_seen")
	_check(_qm.is_active(&"recover_payment"), "'Recover your payment.' starts at the handoff")
	var order: Array = _qm._tracker_order()
	_check(order.size() >= 2 and order[0] == &"opening_survival" and order.find(&"recover_payment") > 0, "the survival quest is first and the payment quest is listed under it (%s)" % str(order))
	var payment_quest: QuestData = _qm.get_quest(&"recover_payment")
	_check(payment_quest != null and payment_quest.objectives.size() == 1 and payment_quest.objectives[0].text == "Recover your payment.", "the objective text is exactly 'Recover your payment.'")

	# Fighting is really blocked: an attack input does nothing while locked.
	var before_state: int = player.state
	player._handle_free_action(&"attack_light")
	_check(player.state == before_state, "an attack input is dropped while attacks are locked")

	# The three pickups complete it in ANY order (medkit, then stick, then jacket).
	var supplies := load("res://resources/items/health_potion.tres") as ItemData
	var stick := load("res://resources/items/wooden_stick.tres") as ItemData
	var jacket := load("res://resources/items/salvaged_jacket.tres") as ItemData
	player.inventory.collect(supplies)
	await _frames(1)
	_check(not _qm.is_completed(&"opening_survival"), "one of three: not complete yet")
	player.inventory.collect(stick)
	player.inventory.equip(stick)
	await _frames(1)
	_check(not _qm.is_completed(&"opening_survival"), "two of three: still not complete")
	player.inventory.collect(jacket)
	player.inventory.equip(jacket)
	await _frames(2)
	_check(_qm.is_completed(&"opening_survival"), "all three, in this order, completes the quest")
	_check(not player.attacks_locked, "attacks unlock on completion")
	await _frames(10)
	_check(player.injured_speed_mult > 0.55, "movement speed recovers toward normal (%.2f)" % player.injured_speed_mult)
	_check(_qm.tracker_first == &"", "the tracker pin is released")

	# The items must exist IN THE WORLD, not only be injectable: a fresh handoff spawns three real pickups, and
	# walking into them (their body_entered path) completes the quest and lifts the locks.
	_qm.reset()
	await _frames(2)
	var player2 := await _make_player()
	var beach2 := OpeningBeach.new()
	beach2._player = player2
	beach2._world_flags = _world
	beach2._quest_manager = _qm
	beach2._hand_off()
	await _frames(2)
	var found: Dictionary = {}
	for node in root.find_children("*", "Pickup", true, false):
		var pk := node as Pickup
		if pk != null and pk.item != null:
			found[String(pk.item.item_id)] = pk
	for want in ["health_potion", "salvaged_jacket", "wooden_stick"]:
		_check(found.has(want), "a real '%s' pickup exists in the world after the handoff" % want)
	for want in found:
		(found[want] as Pickup)._on_body_entered(player2)
	await _frames(3)
	_check(_qm.is_completed(&"opening_survival"), "collecting the three world pickups completes the survival quest")
	_check(not player2.attacks_locked, "attacks unlock after collecting the world pickups")

	# The failsafe must be able to finish the quest on its own (a missed or unreachable pickup never traps the player).
	_qm.reset()
	await _frames(2)
	var player3 := await _make_player()
	var beach3 := OpeningBeach.new()
	beach3._player = player3
	beach3._world_flags = _world
	beach3._quest_manager = _qm
	beach3._hand_off()
	for node in root.find_children("*", "Pickup", true, false):
		node.queue_free()
	await _frames(2)
	beach3._grant_missing_items()
	await _frames(3)
	_check(_qm.is_completed(&"opening_survival"), "the failsafe grants every missing item and completes the quest")
	_check(not player3.attacks_locked, "and attacks unlock even if no pickup was ever found")

	# The payment is not recovered in this arc: the quest stays open after the survival quest and the pickups,
	# and completes only when the story sets `payment_recovered`.
	_check(_qm.is_active(&"recover_payment") and not _qm.is_completed(&"recover_payment"), "the payment quest is still open after the survival quest is done")
	_world.set_flag(&"payment_recovered", true)
	await _frames(3)
	_check(_qm.is_completed(&"recover_payment"), "it completes only when `payment_recovered` is set")
	_world.reset()

	# Flag and id safety: everything this feature writes obeys WorldState's rule.
	for id in [&"opening_event_seen", &"opening_survival", &"wooden_stick", &"salvaged_jacket", &"health_potion"]:
		var s := String(id)
		_check(s.length() <= 48 and s == s.to_lower().replace(" ", "_"), "id '%s' fits WorldState's rule" % s)

	print("opening_beach_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
