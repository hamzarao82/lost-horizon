extends SceneTree
## Explosive barrel (headless): godot --headless --path . -s tests/explosive_barrel_check.gd

const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const PLAYER_AT: Vector3 = Vector3(0.0, 0.1, -24.0)
const REGION: StringName = &"dead_coast"

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player
var _extras: Array[Node] = []


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
	var qm := root.get_node_or_null("/root/QuestManager")
	if qm:
		qm.set("intro_done", true)
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	await _frames(3)
	var outpost := _main.get_node_or_null("Outpost17")
	if outpost:
		outpost.free()
	_player = _main.get_node("Player") as Player
	await _frames(2)

	_test_falloff()
	await _test_fuse_and_blast()
	await _test_player_hurt()
	await _test_once_only()
	await _test_chain()
	await _test_persistence()
	_cleanup()
	print("\nexplosive_barrel_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _cleanup() -> void:
	for node in _extras:
		if is_instance_valid(node):
			node.queue_free()
	_extras.clear()


func _reset() -> void:
	_cleanup()
	_player.global_position = PLAYER_AT
	_player.velocity = Vector3.ZERO
	_player.health.health = _player.health.max_health
	await _frames(2)


func _barrel(at: Vector3, region: StringName = &"", id: StringName = &"") -> ExplosiveBarrel:
	var barrel := ExplosiveBarrel.new()
	barrel.region_id = region
	barrel.barrel_id = id
	barrel.position = at
	_main.add_child(barrel)
	_extras.append(barrel)
	return barrel


func _enemy(at: Vector3) -> Enemy:
	var enemy := (load(SOLDIER) as PackedScene).instantiate() as Enemy
	enemy.position = at
	_main.add_child(enemy)
	_extras.append(enemy)
	return enemy


func _test_falloff() -> void:
	print("Damage falloff")
	_check(is_equal_approx(ExplosiveBarrel.falloff(0.0, 4.5), 1.0), "full damage at the centre")
	_check(is_equal_approx(ExplosiveBarrel.falloff(4.5, 4.5), ExplosiveBarrel.MIN_FALLOFF), "the edge of the radius still does the minimum")
	_check(ExplosiveBarrel.falloff(4.6, 4.5) == 0.0, "nothing outside the radius")
	_check(ExplosiveBarrel.falloff(1.0, 4.5) > ExplosiveBarrel.falloff(3.0, 4.5), "damage drops with distance")


func _test_fuse_and_blast() -> void:
	print("Fuse and blast on enemies")
	await _reset()
	var barrel := _barrel(PLAYER_AT + Vector3(0.0, 0.0, 12.0))
	var near := _enemy(barrel.position + Vector3(1.0, 0.0, 0.0))
	var edge := _enemy(barrel.position + Vector3(4.0, 0.0, 0.0))
	var far := _enemy(barrel.position + Vector3(9.0, 0.0, 0.0))
	await _frames(2)
	var near_hp: float = near._health.health
	var edge_hp: float = edge._health.health
	var far_hp: float = far._health.health
	_check(not barrel.is_lit, "an untouched barrel is not lit")
	var attack := AttackData.new()
	attack.damage = 1.0
	_check(barrel.receive_hit(attack, PLAYER_AT), "a weapon hit lights the barrel")
	_check(barrel.is_lit and barrel._ring.visible, "a lit barrel shows its warning ring")
	_check(near._health.health == near_hp, "no damage during the fuse")
	barrel.advance(ExplosiveBarrel.FUSE_SECONDS * 0.5)
	_check(near._health.health == near_hp and not barrel.is_spent, "the barrel waits out the full fuse")
	barrel.advance(ExplosiveBarrel.FUSE_SECONDS)
	_check(barrel.is_spent, "the barrel is spent after the fuse")
	var near_loss := near_hp - near._health.health
	var edge_loss := edge_hp - edge._health.health
	print("  loss near %.1f, edge %.1f, far %.1f" % [near_loss, edge_loss, far_hp - far._health.health])
	_check(near_loss > 0.0, "an enemy beside the barrel is hurt")
	_check(near_loss > edge_loss and edge_loss > 0.0, "damage falls off toward the edge of the radius")
	_check(far._health.health == far_hp, "an enemy outside the radius is untouched")


func _test_player_hurt() -> void:
	print("Blast on the player")
	await _reset()
	var barrel := _barrel(PLAYER_AT + Vector3(2.0, 0.0, 0.0))
	var before: float = _player.health.health
	barrel.light()
	barrel.advance(ExplosiveBarrel.FUSE_SECONDS + 0.1)
	_check(_player.health.health < before, "the player standing in the blast is hurt too (%.0f to %.0f)" % [before, _player.health.health])

	await _reset()
	var distant := _barrel(PLAYER_AT + Vector3(20.0, 0.0, 0.0))
	before = _player.health.health
	distant.light()
	distant.advance(ExplosiveBarrel.FUSE_SECONDS + 0.1)
	_check(_player.health.health == before, "a player outside the radius is safe")


func _test_once_only() -> void:
	print("One shot")
	await _reset()
	var barrel := _barrel(PLAYER_AT + Vector3(0.0, 0.0, 12.0))
	var enemy := _enemy(barrel.position + Vector3(1.0, 0.0, 0.0))
	await _frames(2)
	barrel.light()
	barrel.advance(2.0)
	var hp_after: float = enemy._health.health
	_check(barrel.explode() == 0, "a spent barrel cannot explode again")
	barrel.light()
	barrel.advance(2.0)
	_check(enemy._health.health == hp_after, "a spent barrel does no further damage")
	var attack := AttackData.new()
	_check(not barrel.receive_hit(attack, PLAYER_AT), "a spent barrel ignores hits")


func _test_chain() -> void:
	print("Chain reaction")
	await _reset()
	var a := _barrel(PLAYER_AT + Vector3(0.0, 0.0, 12.0))
	var b := _barrel(PLAYER_AT + Vector3(3.0, 0.0, 12.0))
	var c := _barrel(PLAYER_AT + Vector3(20.0, 0.0, 12.0))
	a.light()
	a.advance(2.0)
	_check(b.is_lit, "a neighbouring barrel inside the radius catches fire")
	_check(not c.is_lit, "a distant barrel is not affected")


func _test_persistence() -> void:
	print("Destroyed state persists")
	await _reset()
	var manager := root.get_node_or_null("RegionManager")
	_check(manager != null, "RegionManager is available for persistence")
	if manager == null:
		return
	var barrel := _barrel(PLAYER_AT + Vector3(0.0, 0.0, 12.0), REGION, &"crate_yard_1")
	_check(not PersistentIds.is_claimed(REGION, &"barrel_crate_yard_1"), "a fresh barrel is not recorded as destroyed")
	barrel.light()
	barrel.advance(2.0)
	_check(PersistentIds.is_claimed(REGION, &"barrel_crate_yard_1"), "exploding records the barrel as destroyed")
	await _frames(2)
	var again := _barrel(PLAYER_AT + Vector3(0.0, 0.0, 12.0), REGION, &"crate_yard_1")
	await _frames(2)
	_check(not is_instance_valid(again) or again.is_queued_for_deletion(), "after a reload the destroyed barrel does not come back")
	var other := _barrel(PLAYER_AT + Vector3(5.0, 0.0, 12.0), REGION, &"crate_yard_2")
	await _frames(2)
	_check(is_instance_valid(other) and not other.is_queued_for_deletion(), "a different barrel in the same region is unaffected")
	var plain := _barrel(PLAYER_AT + Vector3(8.0, 0.0, 12.0))
	plain.light()
	plain.advance(2.0)
	_check(PersistentIds.count(REGION) == 1, "a barrel without ids saves nothing")
