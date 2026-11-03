extends SceneTree
## Controller bindings: every gameplay action has a joypad event, no keyboard/mouse event was lost.
##   godot --headless --path . -s tests/gamepad_check.gd

const GAMEPLAY: Array[StringName] = [
	&"move_forward", &"move_backward", &"move_left", &"move_right", &"jump", &"sprint", &"dodge",
	&"interact", &"attack_light", &"attack_heavy", &"use_item", &"teleport", &"pause", &"lock_on",
	&"target_next", &"target_prev", &"special", &"equipment", &"look_left", &"look_right",
	&"look_up", &"look_down", &"ui_accept", &"ui_cancel", &"ui_up", &"ui_down", &"ui_left", &"ui_right",
]

var _failures: int = 0
var _checks: int = 0


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _non_pad(action: StringName) -> int:
	var n := 0
	for event in InputMap.action_get_events(action):
		if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			n += 1
	return n


func _initialize() -> void:
	var before := {}
	for action in GAMEPLAY:
		before[action] = _non_pad(action) if InputMap.has_action(action) else -1
	GamepadBindings.apply()
	for action in GAMEPLAY:
		_check(InputMap.has_action(action), "%s exists" % action)
		_check(GamepadBindings.has_joypad_event(action), "%s has a joypad event" % action)
		if before[action] >= 0:
			_check(_non_pad(action) >= before[action], "%s kept its keyboard/mouse events" % action)
	var key_i := false
	for event in InputMap.action_get_events(&"equipment"):
		if event is InputEventKey and event.physical_keycode == KEY_I:
			key_i = true
	_check(key_i, "equipment keeps the I key")
	var counts := {}
	for action in GAMEPLAY:
		counts[action] = InputMap.action_get_events(action).size()
	GamepadBindings.apply()
	var stable := true
	for action in GAMEPLAY:
		stable = stable and counts[action] == InputMap.action_get_events(action).size()
	_check(stable, "applying twice adds no duplicate events")
	var settings_src := FileAccess.get_file_as_string("res://scripts/core/settings.gd")
	_check(settings_src.contains("GamepadBindings.apply()"), "Settings applies the bindings at startup")
	var cam_src := FileAccess.get_file_as_string("res://scripts/camera/camera_controller.gd")
	_check(cam_src.contains("look_left"), "camera reads the right stick")
	var pause_src := FileAccess.get_file_as_string("res://scripts/ui/pause_menu.gd")
	_check(pause_src.contains('is_action_pressed("equipment")'), "pause menu opens equipment from the action")
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
