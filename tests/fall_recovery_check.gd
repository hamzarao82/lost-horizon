extends SceneTree
## A player who falls out of the world is put back on solid ground, or dies into the normal respawn path.
## godot --headless --path . -s tests/fall_recovery_check.gd

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


func _run() -> void:
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	for i in 90:
		await physics_frame
	var player := main.get_tree().get_first_node_in_group("player") as Player
	_check(player != null, "the player exists")
	if player == null:
		quit(1)
		return
	_check(player.is_on_floor(), "the player stands on the ground (y %.2f)" % player.global_position.y)
	var ground := player.global_position
	var full_health: float = player.health.health

	# 1) A fall: back on the remembered ground, no damage, no leftover fall speed.
	player.global_position = Vector3(ground.x, -120.0, ground.z)
	for i in 4:
		await physics_frame
	_check(player.global_position.y > Player.FALL_RECOVERY_Y, "after a fall the player is above the kill height (y %.2f)" % player.global_position.y)
	_check(Vector2(player.global_position.x - ground.x, player.global_position.z - ground.z).length() < 2.0, "and back near the last ground")
	_check(is_equal_approx(player.health.health, full_health) and player.state != Player.State.DEAD, "without damage")
	_check(player.velocity.y > -5.0, "and without the fall speed (%.1f)" % player.velocity.y)

	# 2) A region change or teleport must not send the player back to the old region's ground.
	player.global_position = Vector3(ground.x + 400.0, 0.5, ground.z)
	await physics_frame
	_check(not player._last_safe_position.is_finite(), "a position jump forgets the old ground")

	# 3) No known ground: the normal death path takes over (checked before the reload timer fires).
	player._last_safe_position = Vector3.INF
	player.global_position = Vector3(ground.x + 400.0, -120.0, ground.z)
	for i in 3:
		await physics_frame
	_check(player.state == Player.State.DEAD, "with no known ground a fall ends in the normal death")
	print("fall_recovery_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
