extends SceneTree
## Key rebinding: capture, cancel, swap on conflict, reset, persistence, hostile config, defaults untouched.
##   godot --headless --path . -s tests/key_rebind_check.gd

var _failures: int = 0
var _checks: int = 0
var _baseline: Dictionary = {}  # action -> encoded kb/mouse events + joypad event count at start


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _key(code: int, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code as Key
	e.pressed = pressed
	return e


func _mouse(button: int) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button as MouseButton
	e.pressed = true
	return e


func _joy_count(action: StringName) -> int:
	var n := 0
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			n += 1
	return n


func _snapshot() -> Dictionary:
	var out := {}
	for action in KeyBindings.rebindable_actions():
		out[action] = [InputMap.action_get_events(action).size(), KeyBindings.to_config().get(String(action), ""),
				_joy_count(action)]
	return out


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	KeyBindings.capture_defaults()
	var settings := root.get_node("Settings")
	var saved_path: String = settings.config_path
	settings.config_path = "user://key_rebind_check.cfg"
	DirAccess.remove_absolute(settings.config_path)
	_test_defaults()
	_test_rebind_and_swap()
	_test_panel()
	_test_persistence(settings)
	_test_hostile_config()
	_test_ui_integration()
	KeyBindings.reset_all()
	DirAccess.remove_absolute(settings.config_path)
	settings.config_path = saved_path
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_defaults() -> void:
	print("# defaults")
	var actions := KeyBindings.rebindable_actions()
	_check(actions.size() == 17, "all 17 listed actions exist in the InputMap (%d)" % actions.size())
	_check(KeyBindings.is_default(), "nothing is rebound at the start")
	_check(KeyBindings.to_config().is_empty(), "a default setup saves no bindings")
	_check(not actions.has(&"pause"), "pause (Escape) is not rebindable")
	_check((KeyBindings.primary(&"jump") as InputEventKey).physical_keycode == KEY_SPACE, "jump defaults to Space")
	_check((KeyBindings.primary(&"attack_light") as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT,
			"light attack defaults to the left mouse button")
	_check(KeyBindings.describe(KeyBindings.primary(&"jump")) != "", "bindings have readable text")
	_baseline = _snapshot()


func _test_rebind_and_swap() -> void:
	print("# rebind and swap")
	var res := KeyBindings.rebind(&"jump", _key(KEY_J))
	_check(res["ok"] and res["swapped"] == &"", "rebinding jump to a free key succeeds without a swap")
	_check((KeyBindings.primary(&"jump") as InputEventKey).physical_keycode == KEY_J, "jump is now J")
	_check(Input.is_action_pressed(&"jump") == false, "no stuck press")
	var ev := _key(KEY_J)
	_check(InputMap.event_is_action(ev, &"jump"), "InputMap matches J as jump")
	_check(not InputMap.event_is_action(_key(KEY_SPACE), &"jump"), "Space no longer jumps")
	_check(_joy_count(&"jump") == _baseline[&"jump"][2], "jump keeps its gamepad button")
	var dodge_old := (KeyBindings.primary(&"dodge") as InputEventKey).physical_keycode
	var res2 := KeyBindings.rebind(&"dodge", _key(KEY_J))
	_check(res2["ok"] and res2["swapped"] == &"jump", "binding dodge to J swaps with jump")
	_check((KeyBindings.primary(&"jump") as InputEventKey).physical_keycode == dodge_old,
			"jump received dodge's old primary key")
	_check(InputMap.event_is_action(_key(KEY_J), &"dodge") and not InputMap.event_is_action(_key(KEY_J), &"jump"),
			"J now dodges, not jumps")
	_check(KeyBindings.rebind(&"interact", _key(KEY_ESCAPE))["ok"] == false, "Escape cannot be bound")
	_check(KeyBindings.rebind(&"interact", InputEventMouseMotion.new())["ok"] == false, "a mouse move cannot be bound")
	_check(KeyBindings.rebind(&"pause", _key(KEY_K))["ok"] == false, "pause cannot be rebound")
	_check(KeyBindings.rebind(&"interact", _mouse(MOUSE_BUTTON_RIGHT))["swapped"] == &"attack_heavy",
			"a mouse button can be bound, swapping with the heavy attack")
	_check((KeyBindings.primary(&"attack_heavy") as InputEventKey) != null, "heavy attack took interact's old key")
	_check(not KeyBindings.is_default(), "the setup now counts as changed")
	KeyBindings.reset_all()
	_check(KeyBindings.is_default(), "reset_all restores the defaults")
	_check(_snapshot() == _baseline, "event counts, saved form and gamepad events match the start exactly")
	var sprint_events := InputMap.action_get_events(&"dodge")
	_check(sprint_events.size() == _baseline[&"dodge"][0], "dodge keeps its alternate key after reset")


func _test_panel() -> void:
	print("# panel capture")
	var panel := RebindPanel.new()
	root.add_child(panel)
	var button := panel.button_for(&"teleport")
	_check(button != null and button.text != "", "panel has a labelled button per action")
	panel.begin_capture(&"teleport")
	_check(panel.is_capturing() and button.text == "Press a key...", "clicking an action starts capture")
	_check(panel.handle_event(_key(KEY_ESCAPE)) and not panel.is_capturing(), "Escape cancels the capture")
	_check(KeyBindings.is_default(), "cancel changes nothing")
	panel.begin_capture(&"teleport")
	_check(not panel.handle_event(_key(KEY_Z, false)), "a key release is ignored while capturing")
	_check(panel.is_capturing(), "still capturing after a release")
	_check(panel.handle_event(_key(KEY_Z)), "a key press is consumed")
	_check(not panel.is_capturing(), "capture ends after one key")
	_check(InputMap.event_is_action(_key(KEY_Z), &"teleport"), "Z now teleports")
	_check(button.text == KeyBindings.describe(KeyBindings.primary(&"teleport")), "the button shows the new key")
	panel.begin_capture(&"jump")
	panel.handle_event(_key(KEY_Z))
	_check(panel.notice_text().contains("swapped"), "the panel reports a swap")
	_check(not panel.handle_event(_key(KEY_Q)), "events are ignored when not capturing")
	panel.reset_defaults()
	_check(KeyBindings.is_default() and button.text == KeyBindings.describe(KeyBindings.primary(&"teleport")),
			"Reset to defaults restores bindings and button text")
	panel.free()


func _test_persistence(settings: Node) -> void:
	print("# persistence")
	KeyBindings.rebind(&"use_item", _key(KEY_H))
	KeyBindings.rebind(&"attack_light", _key(KEY_F))
	settings.save()
	var cfg := ConfigFile.new()
	_check(cfg.load(settings.config_path) == OK and cfg.has_section("bindings"), "the file has a bindings section")
	_check(cfg.has_section_key("settings", "quality"), "the existing settings section is still written")
	var expected := KeyBindings.to_config()
	KeyBindings.reset_all()
	_check(KeyBindings.is_default(), "reset before reload")
	settings.load_settings()
	_check(KeyBindings.to_config() == expected, "a reload restores the exact same bindings")
	_check(InputMap.event_is_action(_key(KEY_H), &"use_item"), "H uses the medkit after reload")
	_check(InputMap.event_is_action(_key(KEY_F), &"attack_light"), "F attacks after reload")
	KeyBindings.reset_all()
	settings.save()
	cfg = ConfigFile.new()
	cfg.load(settings.config_path)
	_check(not cfg.has_section("bindings"), "defaults leave no bindings section (old-format file)")
	var old_file := FileAccess.open(settings.config_path, FileAccess.WRITE)
	old_file.store_string("[settings]\nmaster_volume=0.5\n")
	old_file.close()
	settings.load_settings()
	_check(KeyBindings.is_default() and is_equal_approx(settings.master_volume, 0.5),
			"an old settings file without bindings loads and keeps defaults")
	settings.master_volume = 1.0


func _test_hostile_config() -> void:
	print("# hostile data")
	_check(KeyBindings.apply_config("nope") == false, "a non-dictionary is rejected")
	_check(KeyBindings.apply_config({"jump": 12}) == false, "a non-string value is rejected")
	_check(KeyBindings.apply_config({"jump": "k"}) == false, "a truncated token is rejected")
	_check(KeyBindings.apply_config({"jump": "kabc"}) == false, "a non-numeric token is rejected")
	_check(KeyBindings.apply_config({"jump": "x65"}) == false, "an unknown token type is rejected")
	_check(KeyBindings.apply_config({"jump": ""}) == false, "an empty binding is rejected")
	_check(KeyBindings.apply_config({"pause": "k80"}) == false, "a non-rebindable action is rejected")
	_check(KeyBindings.apply_config({"does_not_exist": "k80"}) == false, "an unknown action is rejected")
	_check(KeyBindings.apply_config({"jump": "k%d" % KEY_ESCAPE}) == false, "Escape in a file is rejected")
	_check(KeyBindings.apply_config({"jump": "k%d" % KEY_W}) == false, "stealing another action's key is rejected")
	_check(KeyBindings.apply_config({"jump": "k0"}) == false, "keycode 0 is rejected")
	_check(KeyBindings.apply_config({5: "k80"}) == false, "a non-string key is rejected")
	_check(KeyBindings.is_default(), "every rejection left the defaults in force")
	_check(KeyBindings.apply_config({"jump": "k%d" % KEY_J}), "a valid single change is accepted")
	_check(InputMap.event_is_action(_key(KEY_J), &"jump"), "and takes effect")
	KeyBindings.reset_all()
	_check(KeyBindings.apply_config({}), "an empty config is valid (defaults)")
	_check(KeyBindings.is_default() and _snapshot() == _baseline, "defaults still byte-identical to the start")


func _test_ui_integration() -> void:
	print("# settings page")
	var page := SettingsPage.new()
	root.add_child(page)
	var open_btn: Button = null
	for child in page.get_children():
		if child is Button and (child as Button).text == "Key bindings":
			open_btn = child
	_check(open_btn != null, "the settings page has a Key bindings button")
	var before := page.get_child_count()
	open_btn.pressed.emit()
	_check(page.get_child_count() == before + 1, "opening adds the bindings view")
	_check(not open_btn.visible, "the normal settings controls hide while it is open")
	var rebinder := page.find_children("*", "RebindPanel", true, false)
	_check(rebinder.size() == 1, "exactly one RebindPanel exists")
	(rebinder[0] as RebindPanel).back_pressed.emit()
	_check(open_btn.visible, "Back from the bindings view restores the settings controls")
	page.free()
