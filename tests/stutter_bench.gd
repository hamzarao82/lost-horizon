extends SceneTree
## Windowed stutter benchmark (needs a real display, not --headless):
##   godot --path . -s tests/stutter_bench.gd
## Runs scripted scenarios with vsync off and reports, per scenario: frames over SPIKE_MS with the
## event that caused them, 1% low FPS, plus how much real time the game spent in hit-stop slow motion
## (Engine.time_scale < 1) and the longest continuous slow stretch. A "freeze" in game time shows up
## here even when render frames are fast.

const SPIKE_MS: float = 25.0
const SOLDIER: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HEAVY: String = "res://scenes/enemies/HeavySoldier.tscn"
const HUNTER: String = "res://scenes/enemies/HunterElite.tscn"
const WARDEN: String = "res://scenes/enemies/Warden.tscn"
const ITEM_DIR: String = "res://resources/items/"

var _main: Node
var _player: Player
var _scenario: String = ""
var _event: String = ""
var _event_frame: int = -100
var _frame: int = 0
var _last_us: int = 0
var _records: Dictionary = {}  # scenario -> Dictionary of stats
var _order: Array[String] = []


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _begin(name: String) -> void:
	_scenario = name
	_order.append(name)
	_records[name] = {
		"ms": [] as Array[float], "spikes": [] as Array[String], "slow_ms": 0.0, "lost_ms": 0.0, "slow_max_ms": 0.0,
		"slow_run_ms": 0.0, "nodes0": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objs0": Performance.get_monitor(Performance.OBJECT_COUNT),
		"mem0": Performance.get_monitor(Performance.MEMORY_STATIC),
	}


func _end() -> void:
	var rec: Dictionary = _records[_scenario]
	rec["nodes1"] = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	rec["objs1"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	rec["mem1"] = Performance.get_monitor(Performance.MEMORY_STATIC)


func _mark(event: String) -> void:
	_event = event
	_event_frame = _frame


## Waits `seconds` of real time, sampling every rendered frame.
func _sample(seconds: float) -> void:
	var end_us := Time.get_ticks_usec() + int(seconds * 1.0e6)
	while Time.get_ticks_usec() < end_us:
		await process_frame
		_tick()


func _tick() -> void:
	var now := Time.get_ticks_usec()
	var dt := (now - _last_us) / 1000.0
	_last_us = now
	_frame += 1
	var rec: Dictionary = _records[_scenario]
	(rec["ms"] as Array).append(dt)
	if Engine.time_scale < 0.9:
		rec["slow_ms"] += dt
		rec["lost_ms"] += dt * (1.0 - Engine.time_scale)
		rec["slow_run_ms"] += dt
		rec["slow_max_ms"] = maxf(rec["slow_max_ms"], rec["slow_run_ms"])
	else:
		rec["slow_run_ms"] = 0.0
	if dt > SPIKE_MS:
		var cause := _event if _frame - _event_frame <= 4 else "-"
		(rec["spikes"] as Array).append("%.0f ms (%s)" % [dt, cause])


func _frames(count: int) -> void:
	for i in count:
		await process_frame
		_tick()


func _spawn(path: String, pos: Vector3, tough: bool = true) -> Enemy:
	var enemy := (load(path) as PackedScene).instantiate() as Enemy
	enemy.position = pos
	_main.add_child(enemy)
	if tough:
		var hc := enemy.get_node("HealthComponent") as HealthComponent
		hc.max_health = 1.0e6
		hc.health = 1.0e6
	enemy.aggro()
	return enemy


func _clear_enemies() -> void:
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	for node in _main.get_children():
		if node is Pickup:
			node.queue_free()


func _swing(action: String) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)


func _run() -> void:
	var wm_cleanup := true
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := _main.get_node_or_null("WaveManager")
	if wm and wm_cleanup:
		wm.autostart = false
	root.add_child(_main)
	_last_us = Time.get_ticks_usec()
	if "warm" in OS.get_cmdline_user_args():
		_begin("warmup (boot step per frame)")
		var steps := Warmup.steps()
		for step in steps:
			_mark("warm step")
			step.call()
			await _frames(1)
		_end()
	_begin("idle")
	await _frames(2)
	_player = _main.get_node("Player") as Player
	_player.health.max_health = 1.0e6
	_player.health.health = 1.0e6
	await _sample(3.0)
	_end()

	# Fresh effects/audio/number glyphs: the first fight pays every first-use cost.
	_begin("heavy_vs_4_first")
	for i in 4:
		_spawn([SOLDIER, HEAVY, HUNTER, SOLDIER][i], Vector3(cos(i * 1.57) * 4.0, 0.1, sin(i * 1.57) * 4.0))
	await _sample(0.5)
	for i in 5:
		_mark("heavy swing %d" % i)
		await _swing("attack_heavy")
		await _sample(1.1)
	_end()

	_begin("heavy_vs_4_warm")
	for i in 6:
		_mark("heavy swing %d" % i)
		await _swing("attack_heavy")
		await _sample(1.1)
	_end()

	_begin("light_combo_vs_4")
	for i in 8:
		_mark("light %d" % i)
		await _swing("attack_light")
		await _sample(0.32)
	_end()

	_clear_enemies()
	await _frames(3)

	_begin("pickups")
	for id in ["health_potion", "combat_knife", "military_machete", "tactical_sword", "heavy_combat_armor"]:
		_mark("pickup " + id)
		_cost("Pickup.spawn " + id, func() -> Variant: return Pickup.spawn(_main, load(ITEM_DIR + id + ".tres") as ItemData, _player.global_position + Vector3(2.5, 0.0, 0.0)))
		await _sample(0.25)
		_player.global_position += Vector3(2.5, 0.0, 0.0)
		await _sample(0.4)
		_player.global_position -= Vector3(2.5, 0.0, 0.0)
	_end()

	_begin("wave_spawn")
	_clear_enemies()
	await _frames(3)
	var wave := _main.get_node_or_null("WaveManager")
	if wave:
		_mark("wave start")
		wave.start_delay = 0.2
		wave.start()
		await _sample(4.0)
		_clear_enemies()
	_end()

	_begin("boss_shockwave")
	_clear_enemies()
	await _frames(3)
	_mark("warden spawn")
	var boss := _cost("spawn Warden", func() -> Variant: return _spawn(WARDEN, Vector3(0, 0.1, -9))) as Enemy
	await _sample(1.0)
	for i in 3:
		_mark("shockwave %d" % i)
		_cost("Warden._spawn_shockwave", func() -> Variant: return boss.call("_spawn_shockwave"))
		await _sample(1.0)
	_clear_enemies()
	_end()

	_begin("teleport_reposition")
	await _frames(3)
	for i in 8:
		_mark("teleport %d" % i)
		_player.global_position = Vector3(randf_range(-20.0, 20.0), 0.2, randf_range(-20.0, 20.0))
		await _sample(0.35)
	_end()

	_report()
	quit()


func _report() -> void:
	print("STUTTER adapter=%s" % RenderingServer.get_video_adapter_name())
	for name in _order:
		var rec: Dictionary = _records[name]
		var ms: Array = (rec["ms"] as Array).duplicate()
		if ms.is_empty():
			continue
		ms.sort()
		var total := 0.0
		for v in ms:
			total += v
		var avg: float = total / ms.size()
		var tail: Array = ms.slice(int(ms.size() * 0.99))
		var tail_sum := 0.0
		for v in tail:
			tail_sum += v
		var low_ms: float = tail_sum / maxf(tail.size(), 1)
		print("STUTTER %-20s frames=%4d avg=%5.1fms (%5.1f fps) 1%%low=%5.1f fps max=%6.1fms spikes>%dms=%d slow_motion=%6.0fms lost_game_time=%5.0fms longest_slow=%5.0fms nodes %d->%d objs %d->%d mem %.1f->%.1fMB" % [
			name, ms.size(), avg, 1000.0 / avg, 1000.0 / low_ms, ms[-1], int(SPIKE_MS),
			(rec["spikes"] as Array).size(), rec["slow_ms"], rec["lost_ms"], rec["slow_max_ms"],
			int(rec["nodes0"]), int(rec["nodes1"]), int(rec["objs0"]), int(rec["objs1"]),
			rec["mem0"] / 1048576.0, rec["mem1"] / 1048576.0])
		for spike in rec["spikes"]:
			print("STUTTER     spike: %s" % spike)


## Prints how long a synchronous call takes by itself (instantiate/add_child/etc.), separate from
## the render cost of the frame that follows it.
func _cost(label: String, action: Callable) -> Variant:
	var t0 := Time.get_ticks_usec()
	var result: Variant = action.call()
	print("STUTTER   call %-28s %6.2f ms" % [label, (Time.get_ticks_usec() - t0) / 1000.0])
	return result
