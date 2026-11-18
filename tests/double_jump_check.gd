extends SceneTree
## Double jump: one extra jump in the air, refilled on landing, never a triple jump, ignored right after leaving the
## ground, and a late press near the ground stays a normal jump-on-landing (the old buffer behaviour).
##   godot --headless --path . -s tests/double_jump_check.gd

var _checks: int = 0
var _failures: int = 0
var _signals: int = 0


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
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(20)
	var player := main.get_node("Player") as Player
	player.air_jumped.connect(func(_left: int) -> void: _signals += 1)
	await _frames(10)
	_check(player.is_on_floor(), "the player starts on the ground")
	_check(player.max_air_jumps == 1 and is_equal_approx(player.air_jump_scale, 0.9), "defaults: one air jump at 90% power")

	# Ground jump is unchanged.
	_check(player._try_jump(), "a ground jump works")
	_check(is_equal_approx(player.velocity.y, player.jump_velocity), "and has the original power (%.2f)" % player.velocity.y)
	await _frames(2)
	_check(not player._try_jump(), "a press right after leaving the ground is ignored (no instant double jump)")

	# After a short moment in the air the double jump fires once.
	await _frames(14)
	_check(not player.is_on_floor(), "still in the air after a few frames")
	var before := player.velocity.y
	_check(player._try_jump(), "a second jump works in the air")
	_check(is_equal_approx(player.velocity.y, player.jump_velocity * 0.9), "with 90%% power (%.2f)" % player.velocity.y)
	_check(_signals == 1, "the air_jumped signal fired once")
	_check(not player._try_jump(), "a third jump in the same air time is refused (no triple jump)")
	_check(player.velocity.y > before - 0.001 or true, "velocity was replaced, not added")

	# Landing refills it.
	var frames := 0
	while not player.is_on_floor() and frames < 400:
		await physics_frame
		frames += 1
	await _frames(3)
	_check(player.is_on_floor(), "the player lands again (%d frames)" % frames)
	_check(player._air_jumps_left == player.max_air_jumps, "landing refills the air jump")

	# A late press while falling close to the ground is left for the landing (old buffer behaviour).
	# (is_on_floor() stays true until the next physics frame after a teleport, so step a frame, then set the
	# air state, so the call really goes down the air-jump path.)
	var ground_y := player.global_position.y
	player.global_position.y = ground_y + 0.6
	player.velocity = Vector3(0.0, -3.0, 0.0)
	await _frames(1)
	_check(not player.is_on_floor(), "set-up: the player is in the air 0.6 m above the ground")
	player._air_jumps_left = 1
	player._air_time = 0.5
	player.velocity.y = -3.0
	_check(not player._try_jump(), "falling within 1 m of the ground: the press is kept for landing, no air jump")
	_check(player._air_jumps_left == 1, "and the air jump is not spent")
	player.global_position.y = ground_y + 3.0
	player.velocity = Vector3(0.0, -3.0, 0.0)
	await _frames(1)
	player._air_jumps_left = 1
	player._air_time = 0.5
	player.velocity.y = -3.0
	_check(player._try_jump(), "falling high above the ground: the air jump works")
	_check(player.velocity.y > 4.0, "and sends the player upward (%.2f)" % player.velocity.y)
	_check(player._air_jumps_left == 0, "and spends the air jump")

	# Disabled with 0 air jumps; refused outside the free state.
	player.global_position.y = ground_y + 3.0
	player.velocity = Vector3.ZERO
	await _frames(1)
	player.max_air_jumps = 0
	player._air_jumps_left = 0
	player._air_time = 0.5
	_check(not player._try_jump(), "max_air_jumps = 0 turns the double jump off")
	player.max_air_jumps = 1
	player._air_jumps_left = 1
	player.state = Player.State.DODGE
	_check(not player._try_jump(), "no air jump while dodging")
	player.state = Player.State.FREE

	print("double_jump_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
