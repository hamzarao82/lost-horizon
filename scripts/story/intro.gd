class_name StoryIntro
extends CanvasLayer
## The opening (about 22 s): black screen and captions, then a slow camera push in toward the
## survivor with the title card. Skippable with any key, click or tap, or the Skip button.
## The game is paused while it plays (the intro itself keeps running), and unpaused on exit.

signal finished

const CAPTIONS: Array[String] = [
	"A storm hit the transport without warning.",
	"The ship broke apart in the dark.",
	"Everything after that is gone.",
	"You wake on a beach among the wreckage.\nNo weapon. No radio. No memory of how you got here.",
]
const CAPTION_SECONDS: Array[float] = [3.0, 3.0, 3.0, 4.5]
const FADE_SECONDS: float = 0.5
const SKIP_GRACE_SECONDS: float = 0.4
const TITLE: String = "LOST HORIZON: BLACK SITE"
const PUSH_START_OFFSET: Vector3 = Vector3(5.0, 11.0, 26.0)

@export var camera_push_seconds: float = 7.0

var _done: bool = false
var _age: float = 0.0
var _black: ColorRect
var _caption: Label
var _title: Label
var _skip_button: Button
var _intro_camera: Camera3D
var _game_camera: Camera3D
var _was_paused: bool = false


func _ready() -> void:
	layer = 150  # above HUD, pause menu and touch layers; below the Boot overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_was_paused = get_tree().paused
	get_tree().paused = true
	_play_sound(&"hit_heavy", -8.0)  # thunder under the first line
	_run()


func _exit_tree() -> void:
	if get_tree() != null and not _done:
		get_tree().paused = _was_paused


func _process(delta: float) -> void:
	_age += delta


func _input(event: InputEvent) -> void:
	if _done or _age < SKIP_GRACE_SECONDS:
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
	_finish()


# --- sequence --------------------------------------------------------------

func _run() -> void:
	for index in CAPTIONS.size():
		if _done:
			return
		_caption.text = CAPTIONS[index]
		await _fade(_caption, 1.0, FADE_SECONDS)
		await _wait(CAPTION_SECONDS[index])
		await _fade(_caption, 0.0, FADE_SECONDS)
	if _done:
		return
	await _camera_push()
	_finish()


## Interruptible wait on real time (the tree is paused, so scene timers would not run).
func _wait(seconds: float) -> void:
	if _done:
		return
	await get_tree().create_timer(seconds, true, false, true).timeout


func _fade(item: CanvasItem, alpha: float, seconds: float) -> void:
	if _done:
		return
	var tween := create_tween()
	tween.tween_property(item, "modulate:a", alpha, seconds)
	await tween.finished


func _camera_push() -> void:
	_caption.visible = false
	var controller := get_tree().get_first_node_in_group("camera_controller")
	if controller:
		_game_camera = controller.get_node_or_null("SpringArm3D/Camera3D") as Camera3D
	if _game_camera == null:
		await _fade(_black, 0.0, 1.5)  # nothing to fly: just reveal the game
		return
	var target := _game_camera.global_transform
	var focus := target.origin + Vector3(0.0, -1.0, 0.0) + (-target.basis.z) * 5.0
	_intro_camera = Camera3D.new()
	_intro_camera.fov = _game_camera.fov
	_intro_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	var scene := get_tree().current_scene
	(scene if scene else get_tree().root).add_child(_intro_camera)
	var start_origin := focus + PUSH_START_OFFSET
	_intro_camera.look_at_from_position(start_origin, focus, Vector3.UP)
	_intro_camera.make_current()
	var start := _intro_camera.global_transform

	_title.text = TITLE
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_black, "modulate:a", 0.0, 1.8)
	tween.tween_method(func(t: float) -> void: _place_camera(start, target, t), 0.0, 1.0, camera_push_seconds) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_title, "modulate:a", 1.0, 1.0).set_delay(1.2)
	tween.tween_property(_title, "modulate:a", 0.0, 1.0).set_delay(camera_push_seconds - 1.6)
	await tween.finished


func _place_camera(start: Transform3D, target: Transform3D, t: float) -> void:
	if _done or not is_instance_valid(_intro_camera):
		return
	var origin := start.origin.lerp(target.origin, t)
	var basis := start.basis.slerp(target.basis, t)
	_intro_camera.global_transform = Transform3D(basis, origin)


func _finish() -> void:
	if _done:
		return
	_done = true
	if is_instance_valid(_game_camera):
		_game_camera.make_current()
	if is_instance_valid(_intro_camera):
		_intro_camera.queue_free()
	get_tree().paused = _was_paused
	finished.emit()
	queue_free()


# --- UI --------------------------------------------------------------------

func _build_ui() -> void:
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)

	_caption = _make_label(30, 6)
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.modulate.a = 0.0
	add_child(_caption)

	_title = _make_label(52, 8)
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_title.modulate.a = 0.0
	add_child(_title)

	_skip_button = Button.new()
	_skip_button.text = "Skip"
	_skip_button.custom_minimum_size = Vector2(120, 48)
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)


func _make_label(font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _play_sound(sfx_name: StringName, volume_db: float) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play"):
		audio.play(sfx_name, volume_db)
