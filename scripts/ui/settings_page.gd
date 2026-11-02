class_name SettingsPage
extends VBoxContainer
## The settings controls (volumes, sensitivities, quality, FPS readout). Shared by the pause menu
## and the main menu so both edit the same Settings autoload.

signal back_pressed

const BUTTON_SIZE: Vector2 = Vector2(380, 56)
const FONT_SIZE: int = 24
const SENSITIVITY_MIN: float = 0.25  # keep in sync with Settings.MIN_SENSITIVITY
const SENSITIVITY_MAX: float = 3.0

var _quality_buttons: Array[Button] = []
var _sliders: Dictionary = {}  # name -> HSlider

func _init() -> void:
	add_theme_constant_override("separation", 10)
	_build()

func _settings() -> Node:
	return get_node_or_null("/root/Settings")

func _build() -> void:
	add_child(_title("SETTINGS"))
	_add_slider("master", "Master volume", 0.0, 1.0, 0.05, "set_master_volume")
	_add_slider("music", "Music volume", 0.0, 1.0, 0.05, "set_music_volume")
	_add_slider("mouse", "Mouse sensitivity", SENSITIVITY_MIN, SENSITIVITY_MAX, 0.05, "set_mouse_sensitivity")
	_add_slider("touch", "Touch look sensitivity", SENSITIVITY_MIN, SENSITIVITY_MAX, 0.05, "set_touch_sensitivity")

	var quality_label := Label.new()
	quality_label.text = "Quality"
	quality_label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(quality_label)
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
	add_child(row)

	# F3 does not exist on touch devices, so the FPS/draw-call readout gets a menu button too.
	add_child(_button("Show / hide FPS", func() -> void:
		for overlay in get_tree().get_nodes_in_group("perf_overlay"):
			overlay.call("toggle")))

	add_child(_button("Back", func() -> void: back_pressed.emit()))

## Pull the stored values into the controls without re-triggering the setters, and focus the first one.
func show_page() -> void:
	sync_controls()
	(_sliders["master"] as Control).grab_focus()

func sync_controls() -> void:
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

func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", HudTheme.GOLD)
	return label

func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(on_pressed)
	return b

func _add_slider(key: String, title: String, min_value: float, max_value: float,
		step: float, setter: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 20)
	add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(BUTTON_SIZE.x, 40)
	slider.value_changed.connect(func(value: float) -> void:
		var settings := _settings()
		if settings:
			settings.call(setter, value))
	add_child(slider)
	_sliders[key] = slider
