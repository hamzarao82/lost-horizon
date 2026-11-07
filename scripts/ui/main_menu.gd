class_name MainMenu
extends CanvasLayer
## Title menu shown by Boot once the game has loaded: New Game, Continue, Settings, Credits, Quit.
## It only reports the choice (signals); Boot decides how to start. Touch is translated to clicks
## the same way the pause menu does it, because emulate_mouse_from_touch is off in this project.

signal new_game_pressed
signal continue_pressed
signal quit_pressed

const BUTTON_SIZE: Vector2 = Vector2(380, 60)
const FONT_SIZE: int = 26

var _root: Control
var _main_page: VBoxContainer
var _settings_page: SettingsPage
var _credits_page: VBoxContainer
var _buttons: Dictionary = {}  # name -> Button
var _continue_info: Label
var _loading_label: Label
var _loading: bool = false
var _loading_progress: float = 0.0
var _intro_active: bool = false
var _intro_tween: Tween

## Fade-in of the title and buttons when the menu first appears (Escape, Space or Enter skips it).
const INTRO_SECONDS: float = 1.0


func _init() -> void:
	layer = 210  # above the boot screen (200)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _ready() -> void:
	refresh()
	_show_page(_main_page)
	_start_intro()


## True while the opening fade is playing.
func is_intro_active() -> bool:
	return _intro_active


func _start_intro() -> void:
	_intro_active = true
	_main_page.modulate.a = 0.0
	_intro_tween = create_tween()
	_intro_tween.tween_property(_main_page, "modulate:a", 1.0, INTRO_SECONDS)
	_intro_tween.finished.connect(func() -> void: _intro_active = false)


## Jumps to the finished menu at once and puts focus on a button.
func skip_intro() -> void:
	if not _intro_active:
		return
	if _intro_tween != null:
		_intro_tween.kill()
	_intro_active = false
	_main_page.modulate.a = 1.0
	if _main_page.visible:
		_focus_first()


## The world is still loading: New Game and Continue stay off and show real progress.
func begin_loading() -> void:
	_loading = true
	set_loading(_loading_progress)


## Monotonic: a lower value than one already shown is ignored.
func set_loading(value: float) -> void:
	_loading = true
	_loading_progress = maxf(_loading_progress, clampf(value, 0.0, 1.0))
	_loading_label.text = "Loading world... %d%%" % int(round(_loading_progress * 100.0))
	_loading_label.visible = true
	button("new_game").disabled = true
	button("continue").disabled = true


func is_loading() -> bool:
	return _loading


func loading_text() -> String:
	return _loading_label.text if _loading_label.visible else ""


## The world is ready: buttons turn on with a short highlight on New Game.
func set_ready() -> void:
	_loading = false
	_loading_progress = 1.0
	_loading_label.visible = false
	button("new_game").disabled = false
	refresh()
	var b := button("new_game")
	var tween := create_tween()
	b.modulate = Color(1.7, 1.45, 0.9)
	tween.tween_property(b, "modulate", Color.WHITE, 0.7)
	if _main_page.visible and not _intro_active:
		_focus_first()


func button(key: String) -> Button:
	return _buttons.get(key) as Button


func continue_info() -> String:
	return _continue_info.text


func has_quit_button() -> bool:
	return _buttons.has("quit")


## Re-reads the save so Continue is enabled only when a loadable file exists.
func refresh() -> void:
	var saves := get_node_or_null("/root/SaveManager")
	var data := _peek_save(saves)
	var available: bool = saves != null and saves.has_save()
	var continue_button := button("continue")
	continue_button.disabled = not available or _loading
	continue_button.text = "Continue" if available else "Continue (no save)"
	_continue_info.text = describe_save(data) if available else ""
	_continue_info.visible = _continue_info.text != ""
	if _main_page.visible:
		_focus_first()


## "Military Compound - 0:42:10" from a raw save dictionary; "" when nothing useful is in it.
static func describe_save(data: Dictionary) -> String:
	var parts: Array[String] = []
	var world: Variant = data.get("world", {})
	if world is Dictionary:
		var pos: Variant = (world as Dictionary).get("position", null)
		if pos is Array and (pos as Array).size() >= 3:
			var line := DeathScreen.respawn_line(str((world as Dictionary).get("checkpoint_id", "")), pos)
			parts.append(line.trim_prefix("Respawn: "))
	var stats: Variant = data.get("stats", {})
	if stats is Dictionary and (stats as Dictionary).has("seconds"):
		parts.append(ResultsScreen.format_time(float((stats as Dictionary)["seconds"])))
	return " - ".join(parts)


func _peek_save(saves: Node) -> Dictionary:
	if saves == null or not saves.has_save():
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(saves.save_path())) == OK and json.data is Dictionary:
		return json.data
	return {}


func _input(event: InputEvent) -> void:
	if _intro_active and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			skip_intro()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch:
		var click := InputEventMouseButton.new()
		click.position = event.position
		click.global_position = event.position
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = event.pressed
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if event.pressed else 0
		Input.parse_input_event(click)
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = HudTheme.theme()
	add_child(_root)

	var background := ColorRect.new()
	background.color = Color(0.04, 0.05, 0.07)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(background)
	_root.add_child(MenuEmbers.new())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 6)
	center.add_child(holder)

	_main_page = _build_main_page()
	_settings_page = SettingsPage.new()
	_settings_page.back_pressed.connect(func() -> void: _show_page(_main_page))
	_credits_page = _build_credits_page()
	holder.add_child(_main_page)
	holder.add_child(_settings_page)
	holder.add_child(_credits_page)


func _build_main_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(_label("LOST HORIZON", 56, Color(0.95, 0.9, 0.78)))
	page.add_child(_label("BLACK SITE", 24, Color(0.9, 0.62, 0.2)))
	page.add_child(Control.new())
	_add_button(page, "new_game", "New Game", func() -> void: new_game_pressed.emit())
	_add_button(page, "continue", "Continue", func() -> void: continue_pressed.emit())
	_continue_info = _label("", 16, HudTheme.TEXT_DIM)
	page.add_child(_continue_info)
	_loading_label = _label("", 18, HudTheme.GOLD)
	_loading_label.visible = false
	page.add_child(_loading_label)
	_add_button(page, "settings", "Settings", func() -> void: _show_page(_settings_page))
	_add_button(page, "credits", "Credits", func() -> void: _show_page(_credits_page))
	if not OS.has_feature("web") and not TouchControls.is_mobile_platform():
		_add_button(page, "quit", "Quit", func() -> void: quit_pressed.emit())
	return page


func _build_credits_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	page.add_child(_label("CREDITS", 36, HudTheme.GOLD))
	for line in StoryEnding.CREDITS:
		page.add_child(_label(line, 20, HudTheme.TEXT))
	_add_button(page, "credits_back", "Back", func() -> void: _show_page(_main_page))
	return page


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _add_button(page: Control, key: String, text: String, handler: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(handler)
	page.add_child(b)
	_buttons[key] = b


func _show_page(page: Control) -> void:
	_main_page.visible = page == _main_page
	_settings_page.visible = page == _settings_page
	_credits_page.visible = page == _credits_page
	if page == _main_page:
		_focus_first()
	elif page == _settings_page:
		_settings_page.show_page()
	else:
		button("credits_back").grab_focus()


func _focus_first() -> void:
	var target := button("continue") if not button("continue").disabled else button("new_game")
	target.grab_focus()
