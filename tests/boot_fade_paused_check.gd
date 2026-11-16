extends SceneTree
## The loading overlay must finish fading even when the game tree is paused the instant boot finishes. The
## opening cinematic and beach scene pause the tree, and the overlay (layer 200) sits above them, so a fade that
## stops ticking while paused leaves a "Ready 100%" overlay stuck over the whole opening (seen in the web build).
##   godot --headless --path . -s tests/boot_fade_paused_check.gd

const BOOT_SCENE: String = "res://scenes/boot/Boot.tscn"
const STUB: String = "res://tests/_warmup_stub.gd"
const MAX_BOOT_FRAMES: int = 3000

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _run() -> void:
	var boot := (load(BOOT_SCENE) as PackedScene).instantiate()
	boot.warmup_script_path = STUB
	var finished_main: Array = []
	boot.finished.connect(func(m: Node) -> void:
		finished_main.append(m)
		paused = true)  # exactly what a story scene does right after boot finishes
	root.add_child(boot)
	var frames := 0
	while finished_main.is_empty() and frames < MAX_BOOT_FRAMES and boot.phase != boot.Phase.ERROR:
		await process_frame
		frames += 1
	_check(not finished_main.is_empty(), "boot finishes (%d frames)" % frames)
	_check(paused, "the tree is paused right after boot finished")
	var waited := 0.0
	while is_instance_valid(boot) and boot.phase == boot.Phase.FADING and waited < 3.0:
		await process_frame
		waited += 1.0 / 60.0
	var done: bool = not is_instance_valid(boot) or boot.phase == boot.Phase.DONE
	_check(done, "the loading overlay finishes its fade while the tree is paused")
	if is_instance_valid(boot):
		var ui := boot.get("_ui") as CanvasItem
		_check(ui == null or not ui.visible, "and the overlay is hidden, not left drawn over the story scene")
	else:
		_check(true, "and the overlay was removed")
	paused = false
	print("boot_fade_paused_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
