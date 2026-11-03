class_name GamepadBindings
extends RefCounted
## Controller bindings added on top of the project's keyboard/mouse input map (nothing is removed).
## Applied once by the Settings autoload; safe to call again (existing events are not duplicated).

const STICK_DEADZONE: float = 0.3
## Right stick look speed in "mouse pixels per second", fed to CameraController.apply_look().
const LOOK_SPEED: float = 900.0

## action -> [joypad buttons], and axes as [axis, sign]. Left stick = move, right stick = look.
const BUTTONS: Dictionary = {
	&"jump": [JOY_BUTTON_A],
	&"dodge": [JOY_BUTTON_B],
	&"sprint": [JOY_BUTTON_LEFT_STICK],
	&"use_item": [JOY_BUTTON_DPAD_LEFT],
	&"equipment": [JOY_BUTTON_DPAD_UP],
	&"ui_accept": [JOY_BUTTON_A],
	&"ui_cancel": [JOY_BUTTON_B],
}
const AXES: Dictionary = {
	&"move_left": [[JOY_AXIS_LEFT_X, -1.0]],
	&"move_right": [[JOY_AXIS_LEFT_X, 1.0]],
	&"move_forward": [[JOY_AXIS_LEFT_Y, -1.0]],
	&"move_backward": [[JOY_AXIS_LEFT_Y, 1.0]],
	&"attack_light": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	&"attack_heavy": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	&"look_left": [[JOY_AXIS_RIGHT_X, -1.0]],
	&"look_right": [[JOY_AXIS_RIGHT_X, 1.0]],
	&"look_up": [[JOY_AXIS_RIGHT_Y, -1.0]],
	&"look_down": [[JOY_AXIS_RIGHT_Y, 1.0]],
}
## Actions the game owns that exist only here (no key in project.godot).
const NEW_ACTIONS: Dictionary = {&"equipment": KEY_I, &"look_left": 0, &"look_right": 0, &"look_up": 0, &"look_down": 0}


static func apply() -> void:
	for action: StringName in NEW_ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, STICK_DEADZONE)
			if NEW_ACTIONS[action] != 0:
				var key := InputEventKey.new()
				key.physical_keycode = NEW_ACTIONS[action]
				InputMap.action_add_event(action, key)
	for action: StringName in BUTTONS:
		for button: int in BUTTONS[action]:
			if not _has_button(action, button):
				var event := InputEventJoypadButton.new()
				event.button_index = button as JoyButton
				InputMap.action_add_event(action, event)
	for action: StringName in AXES:
		for pair: Array in AXES[action]:
			if not _has_axis(action, pair[0], pair[1]):
				var event := InputEventJoypadMotion.new()
				event.axis = pair[0] as JoyAxis
				event.axis_value = pair[1]
				InputMap.action_add_event(action, event)
				InputMap.action_set_deadzone(action, STICK_DEADZONE)


static func has_joypad_event(action: StringName) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false


static func _has_button(action: StringName, button: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and event.button_index == button:
			return true
	return false


static func _has_axis(action: StringName, axis: int, sign_value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and event.axis == axis and signf(event.axis_value) == sign_value:
			return true
	return false
