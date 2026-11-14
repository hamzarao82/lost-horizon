class_name ArenaRun
extends Node
## Drives one Arena Mode session inside a freshly loaded Main: puts the player in the courtyard, starts the five
## waves, times the run, records the result and shows the end card. "Play again" restarts the waves in place.

signal run_finished(completed: bool)

const START_POSITION: Vector3 = Vector3(0.0, 0.1, 10.0)
const BOOT_SCENE: String = "res://scenes/boot/Boot.tscn"

var waves: WaveManager
var player: Player
var screen: ArenaResult
var elapsed: float = 0.0
var running: bool = false
var cleared_waves: int = 0
var result: Dictionary = {}
var main_menu_target: String = BOOT_SCENE


static func attach(main: Node) -> ArenaRun:
	if main == null:
		return null
	var existing := main.get_node_or_null("ArenaRun") as ArenaRun
	if existing != null:
		return existing
	var run := ArenaRun.new()
	run.name = "ArenaRun"
	main.add_child(run)
	return run


func _ready() -> void:
	waves = get_parent().get_node_or_null("WaveManager") as WaveManager
	player = get_parent().get_node_or_null("Player") as Player
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Player
	if waves == null:
		return
	waves.all_cleared.connect(_on_cleared)
	waves.arena_failed.connect(_on_failed)
	waves.wave_cleared.connect(func(index: int) -> void: cleared_waves = maxi(cleared_waves, index))
	screen = ArenaResult.new()
	screen.play_again_pressed.connect(play_again)
	screen.menu_pressed.connect(go_to_menu)
	add_child(screen)
	begin_run()


func _process(delta: float) -> void:
	if running:
		elapsed += delta


## Starts (or restarts) the five waves from wave 1 with the player standing in the courtyard.
func begin_run() -> void:
	elapsed = 0.0
	cleared_waves = 0
	result = {}
	running = true
	if player != null and is_instance_valid(player):
		player.global_position = START_POSITION
		player.velocity = Vector3.ZERO
		if player.health != null:
			player.health.health = player.health.max_health
	if waves.has_started():
		waves.replay()
	else:
		waves.start()


func play_again() -> void:
	screen.close()
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and not (enemy.has_method("is_dead") and enemy.is_dead()):
			enemy.queue_free()
	begin_run()


func _on_cleared() -> void:
	_finish(true, waves.total_waves())


func _on_failed() -> void:
	_finish(false, cleared_waves)


func _finish(completed: bool, waves_done: int) -> void:
	if not running:
		return
	running = false
	result = ArenaMode.record_run(waves_done, elapsed, completed)
	result["completed"] = completed
	result["waves"] = waves_done
	result["time"] = elapsed
	if screen != null:
		screen.show_result(completed, waves_done, waves.total_waves(), elapsed, result)
	run_finished.emit(completed)


## Back to the title screen. Everything the run touched is thrown away; the campaign save was never written.
func go_to_menu() -> void:
	ArenaMode.end()
	var saves := get_node_or_null("/root/SaveManager")
	if saves != null:
		saves.reset_runtime_state()
	var stats := get_node_or_null("/root/RunStats")
	if stats != null:
		stats.reset()
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_target)
