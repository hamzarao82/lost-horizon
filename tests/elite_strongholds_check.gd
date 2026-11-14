extends SceneTree
## Optional elite strongholds: data, the one-line hook in each of the five region builders, real-geometry placement
## (free ground, off the main route), the squad, the guaranteed drop, the claim and the reload.
##   godot --headless --path . -s tests/elite_strongholds_check.gd

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"

var _failures: int = 0
var _checks: int = 0
var _heavy: AttackData
var _ids: Array = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]


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


func _run() -> void:
	_heavy = load("res://resources/attacks/heavy_1.tres") as AttackData
	var regions := root.get_node_or_null("RegionManager")
	_check(regions != null, "RegionManager exists")
	if regions == null:
		quit(1)
		return
	_test_data()
	for id in _ids:
		await _test_region(id)
	await _test_reload_and_timeout()
	_test_no_config()
	regions.reset()
	print("elite_strongholds_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("-- data")
	_check(EliteStrongholds.region_ids().size() == 5, "five regions have a stronghold")
	var drops: Array[String] = []
	for id in _ids:
		_check(EliteStrongholds.has_config(id), "%s has a config" % id)
		var cfg: Dictionary = EliteStrongholds.CONFIG[id]
		var key := String(cfg["id"])
		_check(RegionStore.is_known(id), "%s is a known region id" % id)
		_check(key.length() <= RegionStore.MAX_ID_LENGTH and key == key.to_lower() and key.is_valid_identifier(), "%s claim id is save-safe (%s)" % [id, key])
		var guards: Array = cfg["guards"]
		var loadable := guards.size() >= 3 and guards.size() <= 4
		for path in guards:
			loadable = loadable and load(path) is PackedScene
		_check(loadable, "%s has 3-4 guards that all load" % id)
		var item := load(cfg["drop"]) as ItemData
		_check(item != null and item.item_id != &"", "%s drop loads (%s)" % [id, cfg["drop"].get_file()])
		drops.append(cfg["drop"])
	var unique := true
	for i in drops.size():
		for j in range(i + 1, drops.size()):
			unique = unique and drops[i] != drops[j]
	_check(unique, "each region drops a different item")


func _make_region(id: StringName) -> Node3D:
	match id:
		&"outpost_17":
			return (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
		&"dead_coast":
			return DeadCoast.new()
		&"blackwood":
			return Blackwood.new()
		&"research_complex":
			return ResearchComplex.new()
		_:
			return IronFortress.new()


func _stronghold_of(region: Node, id: StringName) -> EliteStrongholds:
	if id == &"outpost_17":
		var outpost := region.get_node_or_null("Outpost17")
		return outpost.get_node_or_null("EliteStronghold") as EliteStrongholds if outpost != null else null
	return region.get_node_or_null("EliteStronghold") as EliteStrongholds


func _base_for(id: StringName, sh: EliteStrongholds) -> Vector3:
	var c := sh.center
	if id == &"dead_coast":
		return DeadCoastTerrain.ground(c.x - DeadCoastTerrain.shore_x(c.y), c.y, 1.5)
	return Vector3(c.x, 1.0, c.y)


func _spawn_player(at: Vector3) -> Player:
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	player.position = at
	root.add_child(player)
	player.health.max_health = 100000.0
	player.health.health = 100000.0
	return player


func _free_all(player: Node, region: Node) -> void:
	if player != null:
		player.queue_free()
	if region != null:
		region.queue_free()
	for i in 40:
		await physics_frame
		if (region == null or not is_instance_valid(region)) and (player == null or not is_instance_valid(player)):
			break
	await _frames(2)


func _kill_all(sh: EliteStrongholds, max_frames: int = 3000) -> void:
	for i in max_frames:
		var alive := false
		for enemy in sh.enemies:
			if is_instance_valid(enemy) and not enemy.is_dead():
				alive = true
				enemy.receive_hit(_heavy, enemy.global_position + Vector3(0.0, 0.0, 2.0))
		if not alive:
			return
		await physics_frame


func _test_region(id: StringName) -> void:
	print("-- %s" % id)
	var region := _make_region(id)
	if id == &"outpost_17":
		region.get_node("WaveManager").autostart = false
	root.add_child(region)
	await _frames(4)
	var sh := _stronghold_of(region, id)
	_check(sh != null, "the builder added one stronghold node")
	if sh == null:
		await _free_all(null, region)
		return
	_check(sh.region_id == id and sh.stronghold_id == &"elite_stronghold", "it knows its region and id")
	_check(not sh.spawned and sh.enemies.is_empty(), "nothing spawns until the player is near")
	sh.step()
	_check(not sh.spawned, "a poll with no player near spawns nothing")
	var base := _base_for(id, sh)
	var player: Player
	if id == &"outpost_17":
		player = region.get_node("Player") as Player  # Main brings its own; a second one would split the player group
		player.global_position = base
		player.velocity = Vector3.ZERO
	else:
		player = _spawn_player(base)
	await _frames(12)
	var spot: Variant = sh.find_spot()
	_check(spot != null, "free ground is found near the preferred centre")
	if spot == null:
		await _free_all(player, region)
		return
	var found: Vector3 = spot
	_check(Vector2(found.x, found.z).distance_to(Vector2(sh.to_global(Vector3(sh.center.x, 0, sh.center.y)).x, sh.to_global(Vector3(sh.center.x, 0, sh.center.y)).z)) <= 24.0, "the spot is within 24 m of the preferred centre")
	_check(sh._route_distance(found) >= EliteStrongholds.ROUTE_CLEARANCE, "the spot is at least %d m from the main route" % int(EliteStrongholds.ROUTE_CLEARANCE))
	_check(sh._is_free(found) and sh._ring_is_free(found), "no solid object sits on the spot or the guard ring")
	# The player is placed near the spot so the proximity poll wakes the squad the real way.
	player.global_position = sh._center_global() + Vector3(0.0, 1.0, 8.0)
	player.velocity = Vector3.ZERO
	await _frames(4)
	sh.step()
	_check(sh.spawned, "the player coming near wakes the squad")
	_check(sh.enemies.size() == (EliteStrongholds.CONFIG[id]["guards"] as Array).size(), "the whole squad spawned (%d)" % sh.enemies.size())
	var near := true
	for enemy in sh.enemies:
		near = near and is_instance_valid(enemy) and (enemy as Node3D).global_position.distance_to(found) < 6.0
	_check(near, "every guard stands on the ring around the spot")
	_check(sh.has_node("Marker"), "a marker beacon shows the stronghold")
	_check(sh.spawn() == 0, "a second spawn is refused")
	sh.step()
	_check(sh.pickup == null, "while guards live there is no drop")
	await _kill_all(sh)
	sh.step()
	_check(sh.pickup != null and is_instance_valid(sh.pickup), "the squad dead: the drop appears")
	var expected := String((load(EliteStrongholds.CONFIG[id]["drop"]) as ItemData).item_id)
	_check(sh.pickup != null and String(sh.pickup.item.item_id) == expected, "it is the region's guaranteed item (%s)" % expected)
	_check(not PersistentIds.is_claimed(id, sh.stronghold_id), "nothing is claimed before the item is picked up")
	# A pickup that is no upgrade is not kept, so it must not claim.
	var other := load("res://resources/items/health_potion.tres") as ItemData
	player.inventory.add_item(other)
	_check(not PersistentIds.is_claimed(id, sh.stronghold_id), "collecting some other item claims nothing")
	# Walk into the real pickup.
	var item_before := sh.pickup
	item_before._on_body_entered(player)
	await _frames(3)
	var claimed := PersistentIds.is_claimed(id, sh.stronghold_id)
	if not claimed:
		print("    (item not kept as an upgrade; checking the not-kept path instead)")
		_check(sh.pickup != null and not sh.retired, "an item that is not kept stays on the ground, unclaimed")
		# Equip-proof path: grant it directly through the inventory signal with kept=true.
		player.inventory.item_collected.emit(sh.pickup.item, true)
		claimed = PersistentIds.is_claimed(id, sh.stronghold_id)
	_check(claimed, "picking the item up claims the stronghold once")
	_check(sh.retired, "the stronghold retires after the claim")
	_check(not PersistentIds.claim(id, sh.stronghold_id), "a second claim of the same id is refused")
	await _free_all(null if id == &"outpost_17" else player, region)


func _test_reload_and_timeout() -> void:
	print("-- reload and timeouts")
	var id := &"dead_coast"
	_check(PersistentIds.is_claimed(id, &"elite_stronghold"), "setup: dead_coast was claimed above")
	var region := DeadCoast.new()
	root.add_child(region)
	await _frames(4)
	var sh := _stronghold_of(region, id)
	var player := _spawn_player(_base_for(id, sh))
	await _frames(8)
	sh.step()
	_check(sh.retired and not sh.spawned and sh.enemies.is_empty(), "after a reload a claimed stronghold stays gone")
	_check(not sh.has_node("Marker"), "and shows no marker")
	await _free_all(null if id == &"outpost_17" else player, region)

	# An unclaimed stronghold comes back in full after a reload, and a timed-out pickup drops again.
	id = &"blackwood"
	var fresh_ids: Dictionary = EliteStrongholds.CONFIG[id]
	var region2 := Blackwood.new()
	root.add_child(region2)
	await _frames(4)
	var sh2 := _stronghold_of(region2, id)
	_check(PersistentIds.is_claimed(id, sh2.stronghold_id), "setup: blackwood was claimed above too")
	root.get_node("RegionManager").reset()
	_check(not PersistentIds.is_claimed(id, sh2.stronghold_id), "a new game forgets the claim")
	var player2 := _spawn_player(_base_for(id, sh2))
	await _frames(12)
	var spot: Variant = sh2.find_spot()
	if spot != null:
		player2.global_position = (spot as Vector3) + Vector3(0.0, 1.0, 12.0)
		await _frames(4)
	sh2.step()
	_check(sh2.spawned and sh2.enemies.size() == (fresh_ids["guards"] as Array).size(), "an unclaimed stronghold respawns in full")
	await _kill_all(sh2)
	sh2.step()
	var first_pickup := sh2.pickup
	_check(first_pickup != null, "the drop appears")
	first_pickup.queue_free()
	await _frames(3)
	_check(not sh2.retired and not PersistentIds.is_claimed(id, sh2.stronghold_id), "a pickup that disappears without being collected claims nothing")
	sh2.step()
	_check(sh2.pickup != null and sh2.pickup != first_pickup, "and the item is dropped again")
	await _free_all(player2, region2)


func _test_no_config() -> void:
	print("-- unknown region")
	var holder := Node3D.new()
	root.add_child(holder)
	_check(EliteStrongholds.add_to(holder, &"nowhere") == null, "an unknown region gets no stronghold")
	_check(EliteStrongholds.add_to(null, &"dead_coast") == null, "a null region gets none")
	holder.queue_free()
