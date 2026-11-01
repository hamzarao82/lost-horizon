class_name TouchControls
extends Control
## On-screen controls. Left half: floating move stick (full push = sprint).
## Right side: drag anywhere free to look, plus action buttons.
## Feeds the same Input Map actions as keyboard/gamepad.
## Shown on mobile platforms, or as soon as a real touch event arrives.

@export var force_visible: bool = false
@export var stick_radius: float = 90.0
@export var button_radius: float = 44.0
@export var look_sensitivity: float = 0.004
@export var sprint_threshold: float = 0.9

const BUTTONS: Array[Dictionary] = [
	{"label": "Jump", "action": &"jump", "offset": Vector2(-90, -90)},
	{"label": "Atk", "action": &"attack_light", "offset": Vector2(-190, -60)},
	{"label": "Heavy", "action": &"attack_heavy", "offset": Vector2(-150, -160)},
	{"label": "Dodge", "action": &"dodge", "offset": Vector2(-60, -190)},
]
const MOVE_ACTIONS: Array[StringName] = [
	&"move_left", &"move_right", &"move_forward", &"move_backward", &"sprint"]

## True once the game is known to be on a touch device (mobile platform or a touch was seen).
static var touch_active: bool = false

var _stick_id: int = -1
var _stick_origin: Vector2
var _stick_pos: Vector2
var _look_id: int = -1
var _button_for_touch: Dictionary = {}  # touch index -> button dict
var _pending_release: Array[StringName] = []


static func is_mobile_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _ready() -> void:
	# Run after the player so a tap shorter than one physics tick is still seen by it.
	process_physics_priority = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_mobile_platform():
		touch_active = true
	visible = force_visible or touch_active


func _physics_process(_delta: float) -> void:
	for action in _pending_release:
		Input.action_release(action)
	_pending_release.clear()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not touch_active:
			touch_active = true
			visible = true
		if event.canceled:
			_release_all()
		elif event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_drag(event.index, event.position, event.relative)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE:
			_release_all()


func _release_all() -> void:
	for action in MOVE_ACTIONS:
		Input.action_release(action)
	for button in BUTTONS:
		Input.action_release(button["action"])
	_button_for_touch.clear()
	_pending_release.clear()
	_stick_id = -1
	_look_id = -1
	queue_redraw()


func _button_center(button: Dictionary) -> Vector2:
	return size + button["offset"]


func _button_at(pos: Vector2) -> Variant:
	for button in BUTTONS:
		if pos.distance_to(_button_center(button)) <= button_radius * 1.2:
			return button
	return null


func _touch_down(index: int, pos: Vector2) -> void:
	var button: Variant = _button_at(pos)
	if button != null:
		_button_for_touch[index] = button
		Input.action_press(button["action"])
	elif pos.x < size.x * 0.5 and _stick_id == -1:
		_stick_id = index
		_stick_origin = pos
		_stick_pos = pos
	elif _look_id == -1:
		_look_id = index
	queue_redraw()


func _touch_up(index: int) -> void:
	if _button_for_touch.has(index):
		# Defer the release to the next physics tick so quick taps are not lost.
		_pending_release.append(_button_for_touch[index]["action"])
		_button_for_touch.erase(index)
	if index == _stick_id:
		_stick_id = -1
		_set_move(Vector2.ZERO)
	if index == _look_id:
		_look_id = -1
	queue_redraw()


func _touch_drag(index: int, pos: Vector2, relative: Vector2) -> void:
	if index == _stick_id:
		_stick_pos = pos
		_set_move((pos - _stick_origin) / stick_radius)
		queue_redraw()
	elif index == _look_id:
		var cam := get_tree().get_first_node_in_group("camera_controller") as CameraController
		if cam:
			cam.apply_look(relative, look_sensitivity)


func _set_move(vec: Vector2) -> void:
	vec = vec.limit_length(1.0)
	_set_axis(&"move_left", maxf(-vec.x, 0.0))
	_set_axis(&"move_right", maxf(vec.x, 0.0))
	_set_axis(&"move_forward", maxf(-vec.y, 0.0))
	_set_axis(&"move_backward", maxf(vec.y, 0.0))
	_set_axis(&"sprint", 1.0 if vec.length() >= sprint_threshold else 0.0)


func _set_axis(action: StringName, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _draw() -> void:
	if _stick_id != -1:
		draw_circle(_stick_origin, stick_radius, Color(1, 1, 1, 0.15))
		draw_circle(_stick_origin + (_stick_pos - _stick_origin).limit_length(stick_radius),
				stick_radius * 0.4, Color(1, 1, 1, 0.35))
	var font := ThemeDB.fallback_font
	for button in BUTTONS:
		var center := _button_center(button)
		var pressed := _button_for_touch.values().has(button)
		draw_circle(center, button_radius, Color(1, 1, 1, 0.4 if pressed else 0.18))
		draw_string(font, center + Vector2(-button_radius, 6), button["label"],
				HORIZONTAL_ALIGNMENT_CENTER, button_radius * 2.0, 16)
