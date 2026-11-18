extends SceneTree
## Combo strings: one button per string (light = 5 hits, heavy = 3 hits), mixable in one combo, each step with its
## own attack data and sword animation, resets on a fresh combo, stamina-gated, and driven through the real
## buffered-press handler. godot --headless --path . -s tests/combo_chain_check.gd

var _checks: int = 0
var _failures: int = 0


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


func _new_player() -> Player:
	var player := (load("res://scenes/player/Player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(3)
	player.stamina = 100.0
	return player


## Starts `idx` as the next hit of a combo and returns whether it started.
func _hit(player: Player, idx: int) -> bool:
	player.stamina = 100.0
	return player._start_attack(idx)


func _run() -> void:
	_test_data()
	await _test_light_string()
	await _test_heavy_string()
	await _test_mixed()
	await _test_resets_and_stamina()
	await _test_real_presses()
	_test_animations()
	print("combo_chain_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_data() -> void:
	print("Attack data")
	var damages: Array[float] = []
	for path in Player.CHAIN_PATHS:
		_check(load(path) is AttackData, "%s loads as AttackData" % path.get_file())
	for idx in Player.LIGHT_STEPS:
		var data := load(Player.CHAIN_PATHS[idx]) as AttackData
		damages.append(data.damage)
		_check(data.startup_frames >= 1 and data.active_frames >= 1 and data.recovery_frames >= 1,
				"light step %d has real frame data" % idx)
	_check(damages == [10.0, 12.0, 15.0, 17.0, 22.0], "light damage rises with every hit and the fifth is the finisher %s" % str(damages))
	var heavy: Array[float] = []
	for idx in Player.HEAVY_STEPS:
		heavy.append((load(Player.CHAIN_PATHS[idx]) as AttackData).damage)
	_check(heavy == [28.0, 34.0, 46.0], "heavy damage rises with every hit %s" % str(heavy))
	_check(Player.LIGHT_STEPS.size() == 5 and Player.HEAVY_STEPS.size() == 3, "five light steps, three heavy steps")


func _test_light_string() -> void:
	print("Light string")
	var player := await _new_player()
	_check(_hit(player, Player.IDX_LIGHT_1), "the first light hit starts")
	var order: Array[int] = [Player.IDX_LIGHT_1]
	for i in 6:
		var next := player._next_attack(false)
		if next < 0:
			break
		_hit(player, next)
		order.append(next)
	_check(order == [0, 1, 2, 7, 8], "one button gives light 1, 2, 3, 4, 5 in order %s" % str(order))
	_check(player._next_attack(false) == -1, "the sixth light press is refused: the string ends at five")
	player.queue_free()
	await _frames(2)


func _test_heavy_string() -> void:
	print("Heavy string")
	var player := await _new_player()
	_check(_hit(player, Player.HEAVY_INDEX), "the first heavy hit starts")
	var order: Array[int] = [Player.HEAVY_INDEX]
	for i in 5:
		var next := player._next_attack(true)
		if next < 0:
			break
		_hit(player, next)
		order.append(next)
	_check(order == [3, 9, 10], "one button gives heavy 1, 2, 3 in order %s" % str(order))
	_check(player._next_attack(true) == -1, "the fourth heavy press is refused: the string ends at three")
	player.queue_free()
	await _frames(2)


func _test_mixed() -> void:
	print("Mixed combos")
	var player := await _new_player()
	# L L H L H H, then a light carries on from where the light string left off.
	var plan: Array = [[false, 0], [false, 1], [true, 3], [false, 2], [true, 9], [true, 10], [false, 7], [false, 8]]
	_hit(player, Player.IDX_LIGHT_1)
	var ok := true
	for step in plan.slice(1):
		var next := player._next_attack(step[0])
		ok = ok and next == step[1]
		if next != step[1]:
			print("    expected ", step[1], " got ", next)
		if next >= 0:
			_hit(player, next)
	_check(ok, "L L H L H H L L plays the next hit of each string every time")
	_check(player._next_attack(false) == -1 and player._next_attack(true) == -1, "after all eight hits both strings are spent")
	player.set("_attack_idx", -1)
	# Heavy first, then light: the light string starts at light 1.
	_hit(player, Player.HEAVY_INDEX)
	_check(player._next_attack(false) == Player.IDX_LIGHT_1, "heavy first, then light: the light string starts at light 1")
	_check(player._next_attack(true) == Player.IDX_HEAVY_2, "and the heavy string continues with heavy 2")
	# The spin special ends any chain.
	player.set("_attack_idx", Player.IDX_SPIN)
	_check(player._next_attack(false) == -1 and player._next_attack(true) == -1, "the spin special ends the chain")
	player.queue_free()
	await _frames(2)


func _test_resets_and_stamina() -> void:
	print("Resets and stamina")
	var player := await _new_player()
	_hit(player, Player.IDX_LIGHT_1)
	_hit(player, Player.IDX_LIGHT_2)
	_hit(player, Player.HEAVY_INDEX)
	_check(player._light_step == 2 and player._heavy_step == 1, "the step counters follow the combo (%d, %d)" % [player._light_step, player._heavy_step])
	player._end_attack()
	player.stamina = 100.0
	player._start_attack(Player.IDX_LIGHT_1)
	_check(player._light_step == 1 and player._heavy_step == 0, "a fresh combo starts both strings over")
	# Not enough stamina: the hit does not start and the strings do not advance.
	player.stamina = 0.0
	var steps_before := [player._light_step, player._heavy_step]
	_check(not player._start_attack(Player.IDX_LIGHT_2), "with no stamina the next hit does not start")
	_check([player._light_step, player._heavy_step] == steps_before, "and the counters stay where they were")
	# A sprint or air attack flows into the light string.
	player.set("_attack_idx", Player.IDX_SPRINT)
	_check(player._next_attack(false) == Player.IDX_LIGHT_1, "a sprint attack flows into light 1")
	player.queue_free()
	await _frames(2)


## Drives the real buffered-press handler: a press during recovery moves the combo on, one during the swing waits.
func _test_real_presses() -> void:
	print("Real presses")
	var player := await _new_player()
	player.stamina = 100.0
	_check(player._start_attack(Player.IDX_LIGHT_1), "set-up: light 1 is running")
	_check(player._handle_attack_action(&"attack_light") == Player.Result.KEEP, "a light press inside the swing is kept (waits for recovery)")
	var seen: Array[int] = [player._attack_idx]
	for i in 6:
		var data := player._weapon_attack(player._attack_idx)
		player._attack_frames = float(data.startup_frames + data.active_frames) + 1.0
		player.stamina = 100.0
		var result := player._handle_attack_action(&"attack_light")
		if result == Player.Result.CHANGED_STATE:
			seen.append(player._attack_idx)
		else:
			break
	_check(seen == [0, 1, 2, 7, 8], "five light presses in recovery play the five light hits %s" % str(seen))
	player._end_attack()
	player.stamina = 100.0
	player._start_attack(Player.HEAVY_INDEX)
	seen = [player._attack_idx]
	for i in 5:
		var data := player._weapon_attack(player._attack_idx)
		player._attack_frames = float(data.startup_frames + data.active_frames) + 1.0
		player.stamina = 100.0
		var result := player._handle_attack_action(&"attack_heavy")
		if result == Player.Result.CHANGED_STATE:
			seen.append(player._attack_idx)
		else:
			break
	_check(seen == [3, 9, 10], "three heavy presses in recovery play the three heavy hits %s" % str(seen))
	player.queue_free()
	await _frames(2)


func _test_animations() -> void:
	print("Sword animations")
	var scene := load("res://assets/characters/player.glb") as PackedScene
	var model := scene.instantiate()
	var anim: AnimationPlayer = null
	for node in model.find_children("*", "AnimationPlayer", true, false):
		anim = node as AnimationPlayer
	_check(anim != null, "the player model has an AnimationPlayer")
	for clip in ["light_1", "light_2", "light_3", "light_4", "light_5", "heavy", "heavy_2", "heavy_3"]:
		_check(anim != null and anim.has_animation(clip), "the player model has a '%s' clip" % clip)
	for id in [&"light_4", &"light_5", &"heavy_2", &"heavy_3"]:
		_check(SkinnedVisual.ATTACK_CLIPS.has(id) and SkinnedVisual.ATTACK_CLIPS[id] == String(id), "attack %s is mapped to its own clip" % id)
	# Every attack step maps to a clip the model really has (no step silently reuses another swing).
	for idx in Player.LIGHT_STEPS + Player.HEAVY_STEPS:
		var data := load(Player.CHAIN_PATHS[idx]) as AttackData
		var clip: String = SkinnedVisual.ATTACK_CLIPS.get(data.id, "")
		_check(anim != null and clip != "" and anim.has_animation(clip), "%s has a clip on the model (%s)" % [data.id, clip])
	model.free()
