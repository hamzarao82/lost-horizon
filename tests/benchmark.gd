extends SceneTree
## Windowed frame-rate benchmark (needs a real display, not --headless):
##   godot --path . -s tests/benchmark.gd
## Runs a scripted fight against four enemies for DURATION seconds with vsync off
## and prints average / 1% low FPS, frame time, draw calls and memory.

const DURATION: float = 20.0
const SCENES: Array[String] = [
	"res://scenes/enemies/HeavySoldier.tscn",
	"res://scenes/enemies/HunterElite.tscn",
	"res://scenes/enemies/HunterElite.tscn",
	"res://scenes/enemies/PatrolSoldier.tscn",
]


func _initialize() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _run() -> void:
	HitStop.enabled = false
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	var world := main.get_node_or_null("World")
	if world:
		world.start_on_beach = false  # the fight is staged around the arena origin
	root.add_child(main)
	await process_frame
	var player := main.get_node("Player") as Player
	player.health.max_health = 1.0e6
	player.health.health = 1.0e6
	for i in SCENES.size():
		var enemy := (load(SCENES[i]) as PackedScene).instantiate() as Enemy
		enemy.position = Vector3(cos(i * 1.57) * 7.0, 0.1, sin(i * 1.57) * 7.0)
		main.add_child(enemy)
		enemy.aggro()
		enemy.hit_points = 1.0e6
		var hc := enemy.get_node("HealthComponent") as HealthComponent
		hc.max_health = 1.0e6
		hc.health = 1.0e6
	await create_timer(1.0).timeout  # settle

	var frame_ms: Array[float] = []
	var elapsed := 0.0
	var swing_timer := 0.0
	var peak_draws := 0.0
	var peak_mem := 0.0
	var last := Time.get_ticks_usec()
	while elapsed < DURATION:
		await process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - last) / 1000.0
		last = now
		elapsed += dt / 1000.0
		frame_ms.append(dt)
		swing_timer -= dt / 1000.0
		if swing_timer <= 0.0:
			Input.action_press("attack_light")
			swing_timer = 0.45
		else:
			Input.action_release("attack_light")
		peak_draws = maxf(peak_draws, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		peak_mem = maxf(peak_mem, OS.get_static_memory_usage() / 1048576.0)
	Input.action_release("attack_light")

	frame_ms.sort()
	var total := 0.0
	for ms in frame_ms:
		total += ms
	var avg_ms := total / frame_ms.size()
	var worst_1pct := frame_ms.slice(int(frame_ms.size() * 0.99))
	var worst_sum := 0.0
	for ms in worst_1pct:
		worst_sum += ms
	var low_ms := worst_sum / maxf(worst_1pct.size(), 1)
	print("BENCH adapter=%s" % RenderingServer.get_video_adapter_name())
	print("BENCH frames=%d avg_fps=%.1f avg_ms=%.2f 1pct_low_fps=%.1f max_ms=%.1f draw_calls_peak=%d static_mem_mb=%.0f" % [
		frame_ms.size(), 1000.0 / avg_ms, avg_ms, 1000.0 / low_ms, frame_ms[-1], int(peak_draws), peak_mem])
	quit()
