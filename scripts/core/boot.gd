extends CanvasLayer
## Boot screen. Shows immediately, then loads the game in small pieces so the bar keeps moving:
##   LOADING  - threaded requests for Main and everything the first minute needs (issued within a
##              per-frame budget, so a single-threaded web export does not stall in one frame)
##   WARMING  - one step per frame (about FRAME_BUDGET_USEC): instance Main, optional external
##              warm-up steps (res://scripts/core/warmup.gd), add Main to the tree with processing
##              disabled so nothing plays behind the screen
##   BUILDING - wait for ArenaDecor's staged build
##   WARM_RENDER - spawn one of each enemy/pickup in view for two frames so their shaders and
##              particles compile behind the opaque screen, then free them
##   SETTLING - a few presented frames, then enable Main and fade out
## Pass `-- --boot-report` after the engine arguments to print a timing report and quit.

signal progress_changed(value: float)
signal finished(main: Node)
signal failed(message: String)

enum Phase { LOADING, WARMING, BUILDING, WARM_RENDER, SETTLING, FADING, ERROR, DONE }

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const FRAME_BUDGET_USEC: int = 8000
const FADE_SECONDS: float = 0.35
const SETTLE_FRAMES: int = 3
const BUILD_TIMEOUT_SECONDS: float = 20.0
const TIP_SECONDS: float = 2.6
const DECOR_STAGES: float = 10.0  # stage boundaries ArenaDecor reports in a first (texture-generating) build
## Share of the bar owned by each phase (sums to 1).
const W_LOAD: float = 0.50
const W_WARM: float = 0.15
const W_BUILD: float = 0.27
const W_RENDER: float = 0.08
const RESOURCE_DIRS: Dictionary = {
	"res://resources/attacks/": ["tres"],
	"res://resources/items/": ["tres"],
	"res://resources/loot/": ["tres"],
	"res://scenes/enemies/": ["tscn"],
	"res://scenes/loot/": ["tscn"],
	"res://assets/audio/": ["wav", "ogg"],
}
const WARM_ENEMIES: Array[String] = [
	"res://scenes/enemies/PatrolSoldier.tscn",
	"res://scenes/enemies/HunterElite.tscn",
	"res://scenes/enemies/HeavySoldier.tscn",
]
const WARM_ITEM: String = "res://resources/items/health_potion.tres"
const TIPS: Array[String] = [
	"Dodging makes you invulnerable for the first 0.18 seconds of the roll.",
	"Light, light, heavy chains into a finisher. Heavy attacks are slow: watch for the red windup.",
	"Lock on with middle mouse or Tab, and switch targets with the mouse wheel.",
	"Better weapons and armor equip automatically when you walk over them.",
	"Press R to use a medkit. You can tap it mid-swing and it fires when you recover.",
	"Press P to pause, change volume and sensitivity, or save your progress.",
	"The Warden is waiting at the end of wave five. Bring your best gear.",
]

## Overridable for tests.
var warmup_script_path: String = "res://scripts/core/warmup.gd"
var extra_paths: PackedStringArray = PackedStringArray()
var auto_start: bool = true

var phase: Phase = Phase.LOADING
var progress: float = 0.0
var error_text: String = ""
## Filled in as the boot runs; printed by --boot-report.
var report: Dictionary = {}
var main_node: Node

var _pending: Array[String] = []
var _issued: Array[String] = []
var _done: Dictionary = {}
var _total_requests: int = 0
var _steps: Array[Callable] = []
var _solo: Array[bool] = []
var _steps_total: int = 0
var _steps_done: int = 0
var _decor: Node
var _warm_nodes: Array[Node] = []
var _warm_frames: int = 0
var _settle_left: int = 0
var _fade_left: float = 0.0
var _build_wait: float = 0.0
var _tip_time: float = 0.0
var _tip_index: int = 0
var _worst_frame_ms: float = 0.0
var _frames: int = 0
var _report_mode: bool = false
var _post_frames: int = 0
var _post_worst_ms: float = 0.0

var _ui: Control
var _bar: ProgressBar
var _percent: Label
var _tip: Label
var _status: Label
var _error: Label
var _retry: Button


func _ready() -> void:
	layer = 200  # above the HUD, pause menu and touch layers that Main adds underneath
	_report_mode = OS.get_cmdline_user_args().has("--boot-report")
	report["first_frame_ms"] = Time.get_ticks_msec()  # since engine start, includes autoloads
	_build_ui()
	if auto_start:
		start()


func start() -> void:
	phase = Phase.LOADING
	error_text = ""
	_error.visible = false
	_retry.visible = false
	_done.clear()
	_issued.clear()
	_pending.clear()
	_pending.append(MAIN_SCENE)  # biggest first: its dependencies stream in the background
	for dir in RESOURCE_DIRS:
		_pending.append_array(_list_resources(dir, RESOURCE_DIRS[dir]))
	for extra in extra_paths:
		_pending.append(extra)
	_total_requests = _pending.size()
	_status.text = "Loading..."


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_ui)

	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	box.add_child(_make_label("LOST HORIZON", 56, Color(0.95, 0.9, 0.78)))
	box.add_child(_make_label("BLACK SITE", 24, Color(0.9, 0.62, 0.2)))
	box.add_child(Control.new())

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(480, 18)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.62, 0.2)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.12)
	_bar.add_theme_stylebox_override("fill", fill)
	_bar.add_theme_stylebox_override("background", back)
	box.add_child(_bar)

	_percent = _make_label("0%", 18, Color(0.85, 0.85, 0.85))
	_status = _make_label("", 16, Color(0.6, 0.65, 0.7))
	var row := HBoxContainer.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_status)
	row.add_child(_percent)
	box.add_child(row)

	_tip = _make_label(TIPS[0], 17, Color(0.7, 0.74, 0.8))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.custom_minimum_size = Vector2(480, 60)
	box.add_child(_tip)

	_error = _make_label("", 18, Color(0.95, 0.35, 0.3))
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(480, 0)
	_error.visible = false
	box.add_child(_error)

	_retry = Button.new()
	_retry.text = "Retry"
	_retry.custom_minimum_size = Vector2(160, 56)
	_retry.add_theme_font_size_override("font_size", 24)
	_retry.visible = false
	_retry.pressed.connect(_on_retry)
	box.add_child(_retry)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


# --- frame loop --------------------------------------------------------------

func _process(delta: float) -> void:
	if phase == Phase.DONE:
		_track_post_boot(delta)
		return
	var frame_start := Time.get_ticks_usec()
	_frames += 1
	_worst_frame_ms = maxf(_worst_frame_ms, delta * 1000.0)

	match phase:
		Phase.LOADING:
			_step_loading(frame_start)
		Phase.WARMING:
			_step_warming(frame_start)
		Phase.BUILDING:
			_step_building(delta)
		Phase.WARM_RENDER:
			_step_warm_render()
		Phase.SETTLING:
			_settle_left -= 1
			if _settle_left <= 0:
				_begin_fade()
		Phase.FADING:
			_step_fading(delta)
	_update_ui(delta)


func _update_ui(delta: float) -> void:
	_bar.value = progress
	_percent.text = "%d%%" % roundi(progress * 100.0)
	_tip_time += delta
	if _tip_time >= TIP_SECONDS:
		_tip_time = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_tip.text = TIPS[_tip_index]


func _set_progress(value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	if value > progress:  # never moves backwards
		progress = value
		progress_changed.emit(progress)


# --- LOADING ------------------------------------------------------------------

func _step_loading(frame_start: int) -> void:
	# Issue requests inside the frame budget. With threads each call returns at once; on a
	# single-threaded web export a call may do real work, so the budget spreads them over frames.
	while not _pending.is_empty():
		var path: String = _pending.pop_front()
		var err := ResourceLoader.load_threaded_request(path, "", true)
		if err != OK:
			_fail("Could not start loading %s (error %d)." % [path, err])
			return
		_issued.append(path)
		if Time.get_ticks_usec() - frame_start >= FRAME_BUDGET_USEC:
			break

	var sum := 0.0
	var all_done := _pending.is_empty()
	for path in _issued:
		if _done.has(path):
			sum += 1.0
			continue
		var prog: Array = []
		match ResourceLoader.load_threaded_get_status(path, prog):
			ResourceLoader.THREAD_LOAD_LOADED:
				var res := ResourceLoader.load_threaded_get(path)
				if res == null:
					_fail("Loaded %s but got nothing back." % path)
					return
				_done[path] = res
				sum += 1.0
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				sum += prog[0] if not prog.is_empty() else 0.0
				all_done = false
			_:
				_fail("Failed to load %s." % path)
				return
	_set_progress(W_LOAD * sum / maxf(_total_requests, 1.0))
	_status.text = "Loading... %d / %d" % [_done.size(), _total_requests]
	if all_done:
		report["load_done_ms"] = Time.get_ticks_msec()
		_begin_warming()


func _list_resources(dir: String, extensions: Array) -> Array[String]:
	var out: Array[String] = []
	var entries := PackedStringArray()
	if ResourceLoader.has_method(&"list_directory"):
		entries = ResourceLoader.list_directory(dir)
	if entries.is_empty():
		entries = DirAccess.get_files_at(dir)
	for entry in entries:
		var file := String(entry)
		if file.ends_with("/"):
			continue
		# Exports list imported/remapped resources with a suffix.
		for suffix in [".remap", ".import"]:
			file = file.trim_suffix(suffix)
		if extensions.has(file.get_extension()):
			var path := dir + file
			if not out.has(path):
				out.append(path)
	return out


# --- WARMING ------------------------------------------------------------------

func _begin_warming() -> void:
	phase = Phase.WARMING
	_steps.clear()
	_solo.clear()
	_steps.append(_step_instantiate_main)
	_solo.append(false)
	for step in _external_steps():
		_steps.append(step)
		_solo.append(true)  # external steps may need a rendered frame between them: one per frame
	_steps.append(_step_add_main)
	_solo.append(false)
	_steps_total = _steps.size()
	_steps_done = 0
	_status.text = "Preparing..."


func _step_warming(frame_start: int) -> void:
	while not _steps.is_empty():
		var step: Callable = _steps.pop_front()
		var solo: bool = _solo.pop_front()
		step.call()
		_steps_done += 1
		_set_progress(W_LOAD + W_WARM * float(_steps_done) / maxf(_steps_total, 1.0))
		if solo or phase == Phase.ERROR or Time.get_ticks_usec() - frame_start >= FRAME_BUDGET_USEC:
			break
	if phase == Phase.WARMING and _steps.is_empty():
		report["warm_done_ms"] = Time.get_ticks_msec()
		phase = Phase.BUILDING
		_status.text = "Building the island..."


func _step_instantiate_main() -> void:
	var scene := _done.get(MAIN_SCENE) as PackedScene
	if scene == null:
		_fail("Main scene did not load.")
		return
	main_node = scene.instantiate()
	main_node.process_mode = Node.PROCESS_MODE_DISABLED  # nothing plays behind the boot screen


func _step_add_main() -> void:
	if main_node == null:
		return
	get_tree().root.add_child(main_node)  # runs every _ready in Main
	get_tree().current_scene = main_node  # so reload_current_scene() restarts Main, not Boot
	_decor = main_node.get_node_or_null("Decor")


## Steps from the optional external warm-up script: `static func steps() -> Array[Callable]`.
func _external_steps() -> Array[Callable]:
	var out: Array[Callable] = []
	if not ResourceLoader.exists(warmup_script_path):
		return out
	var script := load(warmup_script_path) as Script
	if script == null or not _script_has_method(script, &"steps"):
		return out
	var steps: Variant = script.call(&"steps")
	if steps is Array:
		for step in steps:
			if step is Callable and (step as Callable).is_valid():
				out.append(step)
	return out


func _script_has_method(script: Script, method: StringName) -> bool:
	for info in script.get_script_method_list():
		if info.get("name") == method:
			return true
	return false


# --- BUILDING -----------------------------------------------------------------

func _step_building(delta: float) -> void:
	_build_wait += delta
	var fraction := 1.0
	var built := true
	if _decor != null and _decor.has_method(&"is_built"):
		built = _decor.call(&"is_built")
		var stage_ms: Variant = _decor.get(&"stage_ms")
		if stage_ms is Array:
			fraction = clampf(float((stage_ms as Array).size()) / DECOR_STAGES, 0.0, 1.0)
	_set_progress(W_LOAD + W_WARM + W_BUILD * (1.0 if built else fraction * 0.95))
	if built or _build_wait >= BUILD_TIMEOUT_SECONDS:
		report["build_done_ms"] = Time.get_ticks_msec()
		if _decor != null and _decor.get(&"stage_ms") is Array:
			report["decor_stage_ms"] = (_decor.get(&"stage_ms") as Array).duplicate()
		_begin_warm_render()


# --- WARM_RENDER --------------------------------------------------------------

## Put one of each enemy and a pickup in front of the player for two rendered frames, so their
## shaders and particles compile now (hidden by this opaque screen) instead of on the first fight.
func _begin_warm_render() -> void:
	phase = Phase.WARM_RENDER
	_warm_frames = 0
	var player := main_node.get_node_or_null("Player") as Node3D if main_node else null
	if player == null:
		return
	var base := player.global_position + Vector3(0.0, 0.0, -3.0)
	var offset := -1.5
	for path in WARM_ENEMIES:
		var scene := _done.get(path) as PackedScene
		if scene == null:
			continue
		var enemy := scene.instantiate() as Node3D
		enemy.position = base + Vector3(offset, 0.0, 0.0)
		main_node.add_child(enemy)
		_warm_nodes.append(enemy)
		offset += 1.5
	var item := _done.get(WARM_ITEM) as ItemData
	if item != null:
		var pickup := Pickup.spawn(main_node, item, base + Vector3(0.0, 0.0, -1.5))
		if pickup != null:
			_warm_nodes.append(pickup)


func _step_warm_render() -> void:
	_warm_frames += 1
	_set_progress(W_LOAD + W_WARM + W_BUILD + W_RENDER * minf(_warm_frames / 2.0, 1.0))
	if _warm_frames < 2:
		return
	for node in _warm_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_warm_nodes.clear()
	phase = Phase.SETTLING
	_settle_left = SETTLE_FRAMES
	_status.text = "Ready"


# --- SETTLING / FADING --------------------------------------------------------

func _begin_fade() -> void:
	_set_progress(1.0)
	if main_node != null:
		main_node.process_mode = Node.PROCESS_MODE_INHERIT  # the game starts now
	report["playable_ms"] = Time.get_ticks_msec()
	report["worst_frame_ms"] = _worst_frame_ms
	report["frames"] = _frames
	phase = Phase.FADING
	_fade_left = FADE_SECONDS
	finished.emit(main_node)


func _step_fading(delta: float) -> void:
	_fade_left -= delta
	_ui.modulate.a = clampf(_fade_left / FADE_SECONDS, 0.0, 1.0)
	if _fade_left <= 0.0:
		phase = Phase.DONE
		_ui.visible = false
		_print_report()
		if not _report_mode:
			queue_free()


# --- errors -------------------------------------------------------------------

func _fail(message: String) -> void:
	phase = Phase.ERROR
	error_text = message
	_error.text = message
	_error.visible = true
	_retry.visible = true
	_status.text = "Something went wrong"
	push_error("Boot: " + message)
	failed.emit(message)


func _on_retry() -> void:
	if main_node != null and is_instance_valid(main_node):
		main_node.queue_free()
		main_node = null
	for node in _warm_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_warm_nodes.clear()
	progress = 0.0
	start()


# --- reporting ----------------------------------------------------------------

func _track_post_boot(delta: float) -> void:
	if not _report_mode:
		return
	_post_frames += 1
	_post_worst_ms = maxf(_post_worst_ms, delta * 1000.0)
	if _post_frames >= 180:
		print("BOOT_AFTER worst_frame_ms_first_180_frames_after=%.1f" % _post_worst_ms)
		get_tree().quit()


func _print_report() -> void:
	if not _report_mode:
		return
	print("BOOT adapter=%s" % RenderingServer.get_video_adapter_name())
	print("BOOT first_boot_frame_ms=%d load_done_ms=%d warm_done_ms=%d build_done_ms=%d playable_ms=%d" % [
		report.get("first_frame_ms", -1), report.get("load_done_ms", -1), report.get("warm_done_ms", -1),
		report.get("build_done_ms", -1), report.get("playable_ms", -1)])
	print("BOOT worst_frame_ms_during_boot=%.1f frames=%d" % [_worst_frame_ms, _frames])
	print("BOOT decor_stage_ms=%s" % str(report.get("decor_stage_ms", [])))
