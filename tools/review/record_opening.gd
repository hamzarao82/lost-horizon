extends Node
## Records the game's opening as a story video with Godot's Movie Maker (run windowed, never --headless):
##   Godot --path <worktree> --write-movie out.avi --fixed-fps 30 --resolution 1280x720 res://tools/review/record_opening.tscn
## Sequence: a 3 s title card, then the real opening (OpeningCinematic, then OpeningBeach) exactly as a New Game
## plays it, then a 2 s "Recover your payment." card after the beach hands control to the Player, then quit.
## Failsafe: quits after FAILSAFE_SECONDS of game time. Save safety: SaveManager.test_mode is on before anything
## else runs, so the user's real save file is never read or written.

const TITLE_SECONDS: float = 3.0
const TITLE_FADE_SECONDS: float = 0.5
const CAPTION_SECONDS: float = 2.0
const CAPTION_FADE_SECONDS: float = 0.4
const FAILSAFE_SECONDS: float = 240.0
## If the opening has not started this long after Main is added, something is wrong: stop instead of hanging.
const INTRO_START_TIMEOUT_SECONDS: float = 30.0
const MAIN_SCENE: String = "res://scenes/main/Main.tscn"

enum Phase { TITLE, GAME, END_CARD, DONE }

var _phase: int = Phase.TITLE
var _elapsed: float = 0.0  # game time of this recording (fixed-fps: one frame = one step)
var _phase_time: float = 0.0
var _cinematic_seen: bool = false
var _beach_seen: bool = false
var _main: Node
var _title_layer: CanvasLayer
var _title_rect: ColorRect
var _caption_layer: CanvasLayer
var _caption_rect: ColorRect
var _caption_label: Label


func _init() -> void:
	# First thing this script does: keep every save read/write on the test path, never save_slot_1.json.
	(Engine.get_main_loop() as SceneTree).root.get_node("SaveManager").test_mode = true
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	Player.require_mouse_capture = false
	_build_title_card()
	_build_caption_card()


func _process(delta: float) -> void:
	if _phase == Phase.DONE:
		return
	_elapsed += delta
	_phase_time += delta
	if _elapsed >= FAILSAFE_SECONDS:
		push_error("record_opening: failsafe quit after %.0f s of game time" % _elapsed)
		_finish(1)
		return
	match _phase:
		Phase.TITLE:
			_title_rect.modulate.a = _fade_alpha(_phase_time, TITLE_SECONDS, TITLE_FADE_SECONDS)
			if _phase_time >= TITLE_SECONDS:
				_start_game()
		Phase.GAME:
			_watch_opening()
		Phase.END_CARD:
			_caption_rect.modulate.a = _fade_alpha(_phase_time, CAPTION_SECONDS, CAPTION_FADE_SECONDS)
			if _phase_time >= CAPTION_SECONDS:
				_finish(0)


## Opacity of a card that fades in, holds, and fades out over `total` seconds.
static func _fade_alpha(t: float, total: float, fade: float) -> float:
	if t < fade:
		return clampf(t / fade, 0.0, 1.0)
	if t > total - fade:
		return clampf((total - t) / fade, 0.0, 1.0)
	return 1.0


func _start_game() -> void:
	_phase = Phase.GAME
	_phase_time = 0.0
	_title_layer.visible = false
	# Main as a New Game builds it. WaveManager must not start its waves over the opening.
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	var waves := main.get_node_or_null("WaveManager")
	if waves != null:
		waves.autostart = false
	_main = main
	add_child(main)


## The opening is over when its OpeningBeach has been seen and then freed (it frees itself after handing off).
func _watch_opening() -> void:
	var beach_now := false
	var cinematic_now := false
	for child in get_tree().root.get_children():
		if child is OpeningBeach:
			beach_now = true
		elif child is OpeningCinematic:
			cinematic_now = true
	if beach_now:
		_beach_seen = true
	elif _beach_seen:
		_start_end_card()
	elif cinematic_now:
		_cinematic_seen = true
	elif not _cinematic_seen and _phase_time > INTRO_START_TIMEOUT_SECONDS:
		var qm := get_tree().root.get_node("QuestManager")
		var sm := get_tree().root.get_node("SaveManager")
		push_error("record_opening: the opening never started (display=%s intro_done=%s pending_load=%s checkpoint=%s completed=%d arena=%s)" % [DisplayServer.get_name(), qm.intro_done, sm.pending_load, not sm.checkpoint.is_empty(), qm.completed.size(), ArenaMode.active])
		_finish(1)


func _start_end_card() -> void:
	_phase = Phase.END_CARD
	_phase_time = 0.0
	_caption_label.text = "Recover your payment."
	_caption_layer.visible = true


func _finish(code: int) -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	get_tree().quit(code)


func _build_title_card() -> void:
	_title_layer = CanvasLayer.new()
	_title_layer.layer = 300
	_title_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_title_layer)
	_title_rect = ColorRect.new()
	_title_rect.color = Color.BLACK
	_title_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_rect.modulate.a = 0.0
	_title_layer.add_child(_title_rect)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_rect.add_child(box)
	box.add_child(_make_label("LOST HORIZON: BLACK SITE", 56, Color(0.95, 0.9, 0.78)))
	box.add_child(_make_label("The Opening", 28, Color(0.9, 0.62, 0.2)))


func _build_caption_card() -> void:
	_caption_layer = CanvasLayer.new()
	_caption_layer.layer = 300
	_caption_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_caption_layer.visible = false
	add_child(_caption_layer)
	_caption_rect = ColorRect.new()
	_caption_rect.color = Color.BLACK
	_caption_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption_rect.modulate.a = 0.0
	_caption_layer.add_child(_caption_rect)
	_caption_label = _make_label("", 40, Color(0.95, 0.9, 0.78))
	_caption_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption_rect.add_child(_caption_label)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label
