extends SceneTree
## Input queue, simultaneous presses, combo chain and the new moves:
##   godot --headless --path . -s tests/input_check.gd

const HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"

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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	_test_actions_and_layout()
	await _test_queue()
	await _test_simultaneous()
	await _test_combo_and_moves()
	await _test_special_and_air()
	await _test_heavy_and_cancel()
	await _test_attack_speed()
	await _test_invulnerability()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(12)  # let the player settle on the floor
	return main


func _enemy(main: Node, path: String, pos: Vector3) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	enemy.position = pos  # before add_child so it never overlaps the player
	main.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _hp(enemy: Enemy) -> float:
	return (enemy.get_node("HealthComponent") as HealthComponent).health


## A real InputEvent (what the keyboard/mouse/gamepad produce).
func _event(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()  # headless has no per-frame flush


func _release_all() -> void:
	for action in ["move_forward", "move_backward", "move_left", "move_right", "sprint",
			"attack_light", "attack_heavy", "dodge", "jump", "special", "use_item", "lock_on"]:
		Input.action_release(action)


func _hold_player(player: Player) -> void:
	player.state = Player.State.HIT  # a state that never consumes the queue
	player._hit_time = 99.0
	player._queue.clear()


func _test_actions_and_layout() -> void:
	print("Actions and touch layout")
	_check(InputMap.has_action("special"), "special action exists")
	var has_q := false
	for ev in InputMap.action_get_events("special"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_Q:
			has_q = true
	_check(has_q, "special is bound to Q")
	var spec_ok := false
	for button in TouchControls.BUTTONS:
		if button["action"] == &"special":
			spec_ok = true
	_check(spec_ok, "touch Special button exists")
	var radius := 44.0
	for size in [Vector2(1280, 720), Vector2(800, 360)]:
		var inside := true
		var apart := true
		var buttons := TouchControls.BUTTONS
		for i in buttons.size():
			var c: Vector2 = size + (buttons[i]["offset"] as Vector2)
			inside = inside and c.x >= radius and c.y >= radius and c.x <= size.x - radius and c.y <= size.y - radius
			for j in range(i + 1, buttons.size()):
				var d: float = c.distance_to(size + (buttons[j]["offset"] as Vector2))
				apart = apart and d >= radius * 2.0
		_check(inside, "all touch buttons fit on %dx%d" % [size.x, size.y])
		_check(apart, "touch buttons do not overlap on %dx%d" % [size.x, size.y])


func _test_queue() -> void:
	print("Input queue")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player

	_hold_player(player)
	_event("attack_light", true)
	_event("attack_light", false)  # press and release inside one tick: must still register
	await _frames(2)
	_check(player.queued_count(&"attack_light") == 1, "press+release within one tick registers exactly once (event path)")

	_hold_player(player)
	Input.action_press("attack_heavy")  # touch-style: no InputEvent
	await _frames(2)
	Input.action_release("attack_heavy")
	await _frames(1)
	_check(player.queued_count(&"attack_heavy") == 1, "touch-style press queues exactly once (no double queue)")

	_hold_player(player)
	_event("dodge", true)
	await _frames(1)
	_event("dodge", false)
	await _frames(1)
	_event("attack_light", true)
	await _frames(1)
	_event("attack_light", false)
	await _frames(1)
	_event("attack_heavy", true)
	await _frames(1)
	_event("attack_heavy", false)
	await _frames(1)
	_event("jump", true)
	await _frames(1)
	_event("jump", false)
	await _frames(1)
	var order: Array = []
	for entry in player._queue:
		order.append(entry["action"])
	_check(order == [&"attack_light", &"attack_heavy", &"jump"], "queue keeps 3, oldest dropped, FIFO order (got %s)" % [order])

	await _frames(15)
	_check(player._queue.is_empty(), "buffered presses expire after ~0.2 s")

	# While not captured, a mouse click must not become an attack
	Player.require_mouse_capture = true
	_hold_player(player)
	_event("attack_light", true)
	_event("attack_light", false)
	await _frames(2)
	_check(player.queued_count(&"attack_light") == 0, "uncaptured-mouse click does not queue an attack")
	Player.require_mouse_capture = false
	main.queue_free()
	await _frames(3)


func _test_simultaneous() -> void:
	print("Simultaneous inputs")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _enemy(main, HEAVY, player.global_position + Vector3(0, 0, -6))

	# Hold forward + sprint, then press attack on the same frame as dodge+jump+heal
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(40)
	_check(player.is_sprinting(), "forward + sprint held together makes the player sprint")
	var z_before := player.global_position.z
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	_check(player.state == Player.State.ATTACK and player._attack_idx == Player.IDX_SPRINT,
			"attack while sprinting starts the sprint attack")
	_check(player.global_position.z < z_before and Input.is_action_pressed("move_forward"),
			"movement keys stay held and the player keeps moving through the attack")
	_release_all()
	await _frames(60)
	_check(player.state == Player.State.FREE, "player returns to FREE")

	# Dodge pressed during an attack is buffered and fires in recovery
	player.stamina = player.max_stamina
	enemy.global_position = Vector3(30, 0.1, 30)  # out of the way
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	_check(player.state == Player.State.ATTACK and player.queued_count(&"dodge") == 1,
			"dodge pressed in startup stays buffered, attack keeps going")
	await _frames(16)
	_check(player.state == Player.State.DODGE, "buffered dodge fires when the attack reaches recovery")
	await _frames(40)

	# Heal buffered during an attack
	player.health.take_damage(30.0)
	player.inventory.add_item(load("res://resources/items/health_potion.tres") as ItemData)
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	Input.action_press("use_item")
	await _frames(2)
	Input.action_release("use_item")
	_check(player.state == Player.State.ATTACK and player.inventory.potions == 1, "heal is held while attacking")
	await _frames(40)
	_check(player.inventory.potions == 0, "heal is used right after the attack")
	await _frames(20)

	# Jump + attack on the same frame is an air attack
	Input.action_press("jump")
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("jump")
	Input.action_release("attack_light")
	_check(player._attack_idx == Player.IDX_AIR and player.velocity.y > 0.0 or player._attack_idx == Player.IDX_AIR,
			"jump + attack on the same frame starts an air attack")
	await _frames(70)
	main.queue_free()
	await _frames(3)


func _swing(player: Player, action: String, wait_frames: int) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(wait_frames)


func _test_combo_and_moves() -> void:
	print("Combo and moves")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _enemy(main, HEAVY, player.global_position + Vector3(0, 0, -1.5))
	await _frames(2)
	var start := _hp(enemy)

	await _swing(player, "attack_light", 10)  # frame ~12: inside recovery of light_1 (ends ~20)
	_check(player._attack_idx == 0, "first light is light_1")
	await _swing(player, "attack_light", 10)
	_check(player._attack_idx == 1, "second light chains to light_2")
	await _swing(player, "attack_light", 10)
	_check(player._attack_idx == Player.IDX_LIGHT_3, "third light chains to light_3")
	await _swing(player, "attack_heavy", 18)
	_check(player._attack_idx == Player.HEAVY_INDEX or player.state == Player.State.FREE, "heavy finishes the combo")
	await _frames(40)
	var dealt := start - _hp(enemy)
	_check(is_equal_approx(dealt, 10.0 + 12.0 + 15.0 + 28.0), "L-L-L-H deals 10+12+15+28 (got %s)" % dealt)
	_check(player.state == Player.State.FREE, "player is free after the combo")

	# light after light_3 does not start a new chain
	await _frames(20)
	await _swing(player, "attack_light", 8)
	await _swing(player, "attack_light", 8)
	await _swing(player, "attack_light", 8)
	var idx_before := player._attack_idx
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	_check(idx_before == Player.IDX_LIGHT_3, "reached light_3 again")
	await _frames(50)
	_check(player.state == Player.State.FREE, "no fourth light: chain ends, press is dropped")
	main.queue_free()
	await _frames(3)


func _test_special_and_air() -> void:
	print("Special and air attack")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var east := _enemy(main, HEAVY, player.global_position + Vector3(2.0, 0, 0))
	var west := _enemy(main, HEAVY, player.global_position + Vector3(-2.0, 0, 0))
	var far := _enemy(main, HEAVY, player.global_position + Vector3(0, 0, -6.0))
	await _frames(2)
	var stamina := player.stamina
	await _swing(player, "special", 14)
	_check(is_equal_approx(_hp(east), 140.0 - 20.0) and is_equal_approx(_hp(west), 140.0 - 20.0),
			"spin hits enemies on both sides for 20")
	_check(is_equal_approx(_hp(far), 140.0), "spin does not reach an enemy 6 m away")
	_check(stamina - player.stamina >= 30.0 - 0.01, "spin costs 30 stamina")
	_check(player.special_cooldown_left > 5.0 and is_equal_approx(player.special_cooldown, 6.0), "spin starts a 6 s cooldown")
	await _frames(45)
	player.stamina = player.max_stamina
	var west_hp := _hp(west)
	await _swing(player, "special", 14)
	_check(is_equal_approx(_hp(west), west_hp), "spin is ignored while on cooldown")
	player.special_cooldown_left = 0.0
	await _frames(30)
	main.queue_free()
	await _frames(3)

	# Air attack: slash in front plus a landing ring that catches the enemy behind
	main = await _spawn_main()
	player = main.get_node("Player") as Player
	var front := _enemy(main, HEAVY, player.global_position + Vector3(0, 0, -1.5))
	var behind := _enemy(main, HEAVY, player.global_position + Vector3(0, 0, 1.6))
	await _frames(2)
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await _frames(12)
	_check(not player.is_on_floor(), "player is airborne after jumping")
	await _swing(player, "attack_light", 40)
	_check(is_equal_approx(140.0 - _hp(front), 18.0) or 140.0 - _hp(front) > 0.0, "air slash hits the enemy in front")
	var ring := 140.0 - _hp(behind)
	_check(is_equal_approx(ring, 18.0 * 0.8), "landing ring hits the enemy behind for 80%% (got %s)" % ring)
	_check(player.state == Player.State.FREE, "player recovers after the air attack")
	main.queue_free()
	await _frames(3)

	# Sprint attack covers more ground than a standing light
	main = await _spawn_main()
	player = main.get_node("Player") as Player
	var s_start := player.global_position
	await _swing(player, "attack_light", 30)
	var standing := player.global_position.distance_to(s_start)
	await _frames(30)
	var s2 := player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _frames(30)
	var s3 := player.global_position
	await _swing(player, "attack_light", 20)
	_release_all()
	_check(player.global_position.distance_to(s3) > standing, "sprint attack lunges farther than a standing light")
	main.queue_free()
	await _frames(3)


func _test_heavy_and_cancel() -> void:
	print("Heavy timing and cancel")
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	_check(heavy.startup_frames == 10 and heavy.recovery_frames == 15, "heavy_1 is retuned to 10f startup / 15f recovery")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var enemy := _enemy(main, HEAVY, player.global_position + Vector3(0, 0, -1.5))
	await _frames(2)
	var start := _hp(enemy)
	Input.action_press("attack_heavy")
	await _frames(2)
	Input.action_release("attack_heavy")
	_check(player.state == Player.State.ATTACK and player._weapon_pivot.visible, "heavy starts and shows the swing on the first tick")
	await _frames(13)
	_check(is_equal_approx(start - _hp(enemy), 28.0), "heavy lands within ~14 frames of the press (got %s)" % (start - _hp(enemy)))

	# After the heavy connected, a dodge may cancel from the active window
	await _frames(40)
	player.stamina = player.max_stamina
	Input.action_press("attack_heavy")
	await _frames(2)
	Input.action_release("attack_heavy")
	var waited := 0
	while not player._attack_connected and waited < 12:
		await physics_frame
		waited += 1
	var heavy_data := load("res://resources/attacks/heavy_1.tres") as AttackData
	var active_end := float(heavy_data.startup_frames + heavy_data.active_frames)
	_check(player._attack_connected and player._attack_frames < active_end - 1.0,
			"heavy connected while still in its active window (frame %.0f)" % player._attack_frames)
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	_check(player.state == Player.State.DODGE, "dodge cancels a connected heavy before recovery")
	await _frames(40)

	# A miss cannot be dodge-cancelled during startup
	enemy.global_position = Vector3(30, 0.1, 30)
	player.stamina = player.max_stamina
	Input.action_press("attack_heavy")
	await _frames(2)
	Input.action_release("attack_heavy")
	await _frames(2)
	Input.action_press("dodge")
	await _frames(2)
	Input.action_release("dodge")
	_check(player.state == Player.State.ATTACK, "dodge cannot cancel the startup of a heavy")
	main.queue_free()
	await _frames(3)


func _test_invulnerability() -> void:
	print("Invulnerability grant")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var swing := load("res://resources/attacks/enemy_swing.tres") as AttackData
	player.grant_invulnerability(0.3)
	_check(player.is_invulnerable(), "grant_invulnerability makes the player invulnerable")
	_check(not player.receive_hit(swing, player.global_position + Vector3(0, 0, -1)), "hits are ignored while granted")
	player.grant_invulnerability(0.05)
	await _frames(10)
	_check(player.is_invulnerable(), "a shorter grant does not cut an existing one")
	await _frames(20)
	_check(not player.is_invulnerable(), "the grant expires")
	_check(player.receive_hit(swing, player.global_position + Vector3(0, 0, -1)), "hits land again afterwards")
	main.queue_free()
	await _frames(3)


func _ticks_for_light(player: Player) -> int:
	player.stamina = player.max_stamina
	Input.action_press("attack_light")
	await _frames(2)
	Input.action_release("attack_light")
	var ticks := 2
	while player.state != Player.State.FREE and ticks < 120:
		await physics_frame
		ticks += 1
	await _frames(20)
	return ticks


func _test_attack_speed() -> void:
	print("Weapon attack speed")
	var main := await _spawn_main()
	var player := main.get_node("Player") as Player
	var normal := await _ticks_for_light(player)
	var fast := ItemData.new()
	fast.kind = ItemData.Kind.WEAPON
	fast.attack_speed = 2.0
	player.inventory.weapon = fast
	var quick := await _ticks_for_light(player)
	_check(quick < normal * 0.7, "a 2x attack-speed weapon finishes a swing much sooner (%d vs %d ticks)" % [quick, normal])
	main.queue_free()
	await _frames(3)
