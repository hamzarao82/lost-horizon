class_name PerfOverlay
extends CanvasLayer
## FPS / frame time / draw calls / memory readout. F3 toggles; shown by default in debug builds.

@export var refresh_seconds: float = 0.25

var _label: Label
var _elapsed: float = 0.0


func _ready() -> void:
	layer = 100
	add_to_group("perf_overlay")
	_label = Label.new()
	_label.position = Vector2(8, 8)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	visible = OS.is_debug_build()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F3:
		visible = not visible


func _process(delta: float) -> void:
	if not visible:
		return
	_elapsed += delta
	if _elapsed < refresh_seconds:
		return
	_elapsed = 0.0
	var mem_mb := OS.get_static_memory_usage() / 1048576.0
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var tris := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_label.text = "%d FPS  %.1f ms\nDraw calls: %d  Tris: %d\nMem: %.0f MB" % [
		Engine.get_frames_per_second(), delta * 1000.0, draws, tris, mem_mb]


## Used by the pause menu so touch devices (no F3 key) can show or hide the readout.
func toggle() -> void:
	visible = not visible
