class_name OpeningEnding
extends CanvasLayer
## The short close of the opening arc, played once when the lockdown breaker is thrown: the screen goes
## black, two plain lines, then it clears and the player is free to leave Outpost 17. It is NOT the
## campaign ending (`CampaignEnding`), starts no region and touches no audio or camera, so skipping or
## freeing it early leaves nothing behind except the pause state, which is always restored.
##
## `advance(seconds)` is the real clock (`_process` just calls it) so a test can step the whole thing.

signal finished(skipped: bool)

const FLAG_ARC_COMPLETE: StringName = &"opening_arc_complete"
const FLAG_RECOVERED: StringName = &"payment_recovered"
const LINES: PackedStringArray = [
	"He has what he came for.",
	"He still has to leave the island.",
]
const SKIP_GRACE_SECONDS: float = 0.4
const FADE_IN_SECONDS: float = 1.2
const LINE_SECONDS: float = 3.0
const GAP_SECONDS: float = 0.6
const FADE_OUT_SECONDS: float = 1.5

var is_done: bool = false

var _age: float = 0.0
var _clock: float = 0.0
var _was_paused: bool = false
var _skip_requested: bool = false
var _finished_emitted: bool = false
var _black: ColorRect
var _label: Label
var _skip_button: Button


## True when the ending is due: the payment was recovered and the arc has not been closed yet.
static func should_play(world: Object) -> bool:
	if world == null or not world.has_method("has_flag"):
		return false
	return world.has_flag(FLAG_RECOVERED) and not world.has_flag(FLAG_ARC_COMPLETE)


static func total_duration() -> float:
	return FADE_IN_SECONDS + (LINE_SECONDS + GAP_SECONDS) * LINES.size() + FADE_OUT_SECONDS


## Starts the ending if due. The arc flag is set first, so it never plays twice and never on a later load.
## A headless run records the flag but does not play (there is nobody to watch).
static func trigger(tree: SceneTree, world: Object) -> OpeningEnding:
	if not should_play(world):
		return null
	world.set_flag(FLAG_ARC_COMPLETE, true)
	if DisplayServer.get_name() == "headless" or tree == null:
		return null
	var node := OpeningEnding.new()
	tree.root.add_child(node)
	return node


func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	_build_ui()
	_apply(0.0)


func _exit_tree() -> void:
	if get_tree() != null and not is_done:
		get_tree().paused = _was_paused


func _process(delta: float) -> void:
	advance(delta)


func _input(event: InputEvent) -> void:
	if is_done or _age < SKIP_GRACE_SECONDS:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
		pressed = event.pressed
	if pressed:
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if is_done:
		return
	_skip_requested = true
	_finish(true)


func advance(seconds: float) -> void:
	if is_done:
		return
	_age += seconds
	_clock += seconds
	_apply(_clock)
	if _clock >= total_duration():
		_finish(false)


func _finish(skipped: bool) -> void:
	if is_done:
		return
	is_done = true
	if get_tree() != null:
		get_tree().paused = _was_paused
	if not _finished_emitted:
		_finished_emitted = true
		finished.emit(skipped)
	queue_free()


func _apply(t: float) -> void:
	if _black == null:
		return
	var total := total_duration()
	var alpha := 1.0
	if t < FADE_IN_SECONDS:
		alpha = t / FADE_IN_SECONDS
	elif t > total - FADE_OUT_SECONDS:
		alpha = clampf((total - t) / FADE_OUT_SECONDS, 0.0, 1.0)
	_black.modulate.a = alpha
	var into := t - FADE_IN_SECONDS
	var index := int(floor(into / (LINE_SECONDS + GAP_SECONDS)))
	if into < 0.0 or index < 0 or index >= LINES.size() or t > total - FADE_OUT_SECONDS:
		_label.text = ""
		_label.modulate.a = 0.0
		return
	var within := into - index * (LINE_SECONDS + GAP_SECONDS)
	_label.text = LINES[index]
	var fade := minf(minf(within, LINE_SECONDS - within) / 0.5, 1.0)
	_label.modulate.a = clampf(fade, 0.0, 1.0) if within <= LINE_SECONDS else 0.0


func _build_ui() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	_black.modulate.a = 0.0
	add_child(_black)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.modulate.a = 0.0
	add_child(_label)
	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.custom_minimum_size = Vector2(96, 56)
	_skip_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_button.offset_left = -116.0
	_skip_button.offset_top = -76.0
	_skip_button.offset_right = -20.0
	_skip_button.offset_bottom = -20.0
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)
