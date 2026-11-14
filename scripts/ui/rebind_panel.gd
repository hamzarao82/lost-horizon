class_name RebindPanel
extends VBoxContainer
## One row per rebindable action: click it, press a key or mouse button, done. Escape cancels.
## Rebinding to an input another action uses swaps the two. Changes persist through Settings.

signal back_pressed

const ROW_FONT: int = 20

var _buttons: Dictionary = {}  # action -> Button
var _capturing: StringName = &""
var _notice: Label


func _init() -> void:
	add_theme_constant_override("separation", 4)
	_build()


func _build() -> void:
	var title := Label.new()
	title.text = "KEY BINDINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	add_child(title)
	_notice = Label.new()
	_notice.text = "Click an action, then press a key. Esc cancels."
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.add_theme_font_size_override("font_size", 16)
	add_child(_notice)
	for action in KeyBindings.rebindable_actions():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _label_for(action)
		label.custom_minimum_size = Vector2(190, 0)
		label.add_theme_font_size_override("font_size", ROW_FONT)
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(190, 36)
		button.add_theme_font_size_override("font_size", ROW_FONT)
		button.pressed.connect(begin_capture.bind(action))
		row.add_child(button)
		add_child(row)
		_buttons[action] = button
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.add_theme_font_size_override("font_size", ROW_FONT)
	reset.pressed.connect(reset_defaults)
	add_child(reset)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", ROW_FONT)
	back.pressed.connect(func() -> void:
		cancel_capture()
		back_pressed.emit())
	add_child(back)
	refresh()


func is_capturing() -> bool:
	return _capturing != &""


func begin_capture(action: StringName) -> void:
	cancel_capture()
	if not _buttons.has(action):
		return
	_capturing = action
	(_buttons[action] as Button).text = "Press a key..."
	_notice.text = "Press a key or mouse button for %s. Esc cancels." % _label_for(action)


func cancel_capture() -> void:
	if _capturing == &"":
		return
	_capturing = &""
	refresh()


## Feed an input event to the capture. Returns true when the event was consumed.
func handle_event(event: InputEvent) -> bool:
	if _capturing == &"":
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return false
		if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
			cancel_capture()
			_notice.text = "Cancelled."
			return true
	elif event is InputEventMouseButton:
		if not (event as InputEventMouseButton).pressed:
			return false
	else:
		return false
	if not KeyBindings.is_bindable(event):
		return true
	var action := _capturing
	_capturing = &""
	var result := KeyBindings.rebind(action, event)
	if result["ok"]:
		var swapped: StringName = result["swapped"]
		_notice.text = "%s -> %s" % [_label_for(action), KeyBindings.describe(KeyBindings.primary(action))]
		if swapped != &"":
			_notice.text += " (swapped with %s)" % _label_for(swapped)
		var settings := get_node_or_null("/root/Settings")
		if settings:
			settings.call("bindings_changed")
	refresh()
	return true


func reset_defaults() -> void:
	cancel_capture()
	KeyBindings.reset_all()
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.call("bindings_changed")
	_notice.text = "Defaults restored."
	refresh()


func refresh() -> void:
	for action: StringName in _buttons:
		(_buttons[action] as Button).text = KeyBindings.describe(KeyBindings.primary(action))


func button_for(action: StringName) -> Button:
	return _buttons.get(action)


func notice_text() -> String:
	return _notice.text


func _input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


func _label_for(action: StringName) -> String:
	for entry: Array in KeyBindings.ACTIONS:
		if entry[0] == action:
			return entry[1]
	return String(action)
