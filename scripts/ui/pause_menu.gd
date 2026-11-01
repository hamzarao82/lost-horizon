class_name PauseMenu
extends CanvasLayer
## Pause + settings menu, built in code. P / gamepad Start toggles it; touch uses the "||" button.
## While open it translates touches into mouse clicks, because the project disables
## emulate_mouse_from_touch (a tap must not fire the left-click "light attack" in the game).

signal toggled(open: bool)

const BUTTON_SIZE: Vector2 = Vector2(380, 56)
const FONT_SIZE: int = 24
const PAUSE_BUTTON_POSITION: Vector2 = Vector2(16, 140)  # just below the stamina bar, left side
const PAUSE_BUTTON_SIZE: Vector2 = Vector2(56, 56)
const SENSITIVITY_MIN: float = 0.25  # keep in sync with Settings.MIN_SENSITIVITY
const SENSITIVITY_MAX: float = 3.0

var _open: bool = false
var _root: Control
var _main_page: VBoxContainer
var _settings_page: VBoxContainer
var _pause_button: Button
var _quality_buttons: Array[Button] = []
var _sliders: Dictionary = {}  # name -> HSlider


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _exit_tree() -> void:
	if _open and get_tree():
		get_tree().paused = false


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_controls()
	_show_page(_main_page)
	_root.visible = true
	toggled.emit(true)


func close() -> void:
	if not _open:
		return
	_open = false
	var settings := _settings()
	if settings:
		settings.flush()
	get_tree().paused = false
	_root.visible = false
	# Same rule as CameraController: no capture on web (needs a click) or on mobile.
	if not OS.has_feature("web") and not TouchControls.is_mobile_platform():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	toggled.emit(false)


func _process(_delta: float) -> void:
	_pause_button.visible = TouchControls.touch_active and not _open


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		toggle()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not _open:
			if event.pressed and _pause_button.visible \
					and _pause_button.get_global_rect().has_point(event.position):
				open()
				get_viewport().set_input_as_handled()
			return
		var click := InputEventMouseButton.new()
		click.position = event.position
		click.global_position = event.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = event.pressed
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if event.pressed else 0
		Input.parse_input_event(click)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _open:
		var motion := InputEventMouseMotion.new()
		motion.position = event.position
		motion.global_position = event.position
		motion.relative = event.relative
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(motion)
		get_viewport().set_input_as_handled()


# --- UI construction ---------------------------------------------------------

func _settings() -> Node:
	return get_node_or_null("/root/Settings")


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var holder := VBoxContainer.new()
	margin.add_child(holder)

	_main_page = _build_main_page()
	_settings_page = _build_settings_page()
	holder.add_child(_main_page)
	holder.add_child(_settings_page)

	_pause_button = Button.new()
	_pause_button.text = "||"
	_pause_button.position = PAUSE_BUTTON_POSITION
	_pause_button.size = PAUSE_BUTTON_SIZE
	_pause_button.custom_minimum_size = PAUSE_BUTTON_SIZE
	_pause_button.add_theme_font_size_override("font_size", FONT_SIZE)
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.modulate.a = 0.6
	_pause_button.visible = false
	_pause_button.pressed.connect(open)  # mouse on a touch laptop; touch is handled in _input
	add_child(_pause_button)


func _build_main_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(_title("PAUSED"))
	page.add_child(_button("Resume", close))
	page.add_child(_button("Restart", _on_restart))
	page.add_child(_button("Settings", func() -> void: _show_page(_settings_page)))
	if not OS.has_feature("web") and not TouchControls.is_mobile_platform():
		page.add_child(_button("Quit", func() -> void: get_tree().quit()))
	return page


func _build_settings_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.add_child(_title("SETTINGS"))
	_add_slider(page, "master", "Master volume", 0.0, 1.0, 0.05, "set_master_volume")
	_add_slider(page, "music", "Music volume", 0.0, 1.0, 0.05, "set_music_volume")
	_add_slider(page, "mouse", "Mouse sensitivity", SENSITIVITY_MIN, SENSITIVITY_MAX, 0.05, "set_mouse_sensitivity")
	_add_slider(page, "touch", "Touch look sensitivity", SENSITIVITY_MIN, SENSITIVITY_MAX, 0.05, "set_touch_sensitivity")

	var quality_label := Label.new()
	quality_label.text = "Quality"
	quality_label.add_theme_font_size_override("font_size", FONT_SIZE)
	page.add_child(quality_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for i in 3:
		var b := _button(["Low", "Medium", "High"][i], _on_quality_pressed.bind(i))
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2((BUTTON_SIZE.x - 16.0) / 3.0, BUTTON_SIZE.y)
		row.add_child(b)
		_quality_buttons.append(b)
	page.add_child(row)

	page.add_child(_button("Back", func() -> void: _show_page(_main_page)))
	return page


func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(on_pressed)
	return b


func _add_slider(page: VBoxContainer, key: String, title: String, min_value: float,
		max_value: float, step: float, setter: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	page.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(BUTTON_SIZE.x, 40)
	slider.value_changed.connect(func(value: float) -> void:
		var settings := _settings()
		if settings:
			settings.call(setter, value))
	page.add_child(slider)
	_sliders[key] = slider


# --- behaviour -------------------------------------------------------------

func _show_page(page: Control) -> void:
	_main_page.visible = page == _main_page
	_settings_page.visible = page == _settings_page
	if page == _main_page:
		(_main_page.get_child(1) as Control).grab_focus()
	else:
		_sync_controls()
		(_sliders["master"] as Control).grab_focus()


## Pull the stored values into the controls without re-triggering the setters.
func _sync_controls() -> void:
	var settings := _settings()
	if settings == null:
		return
	_set_slider("master", settings.master_volume)
	_set_slider("music", settings.music_volume)
	_set_slider("mouse", settings.mouse_sensitivity)
	_set_slider("touch", settings.touch_sensitivity)
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == int(settings.quality))


func _set_slider(key: String, value: float) -> void:
	(_sliders[key] as HSlider).set_value_no_signal(value)


func _on_quality_pressed(index: int) -> void:
	var settings := _settings()
	if settings:
		settings.set_quality(index)


func _on_restart() -> void:
	close()
	get_tree().reload_current_scene()
