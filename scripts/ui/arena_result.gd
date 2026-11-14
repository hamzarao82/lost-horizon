class_name ArenaResult
extends CanvasLayer
## End-of-run card for Arena Mode: cleared or failed, waves, time, personal best, and Play again / Main menu.
## It pauses the game while it is open (a cleared arena); a failed run is followed by the normal death reload.

signal play_again_pressed
signal menu_pressed

const BUTTON_SIZE: Vector2 = Vector2(280, 60)

var _root: Control
var _title: Label
var _lines: Label
var _note: Label
var _again: Button
var _menu: Button
var _open: bool = false


func _init() -> void:
	layer = 220
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func is_open() -> bool:
	return _open


func title_text() -> String:
	return _title.text


func lines_text() -> String:
	return _lines.text


func play_again_button() -> Button:
	return _again


func menu_button() -> Button:
	return _menu


static func summary(completed: bool, waves: int, total: int, seconds: float, record: Dictionary) -> String:
	var out: PackedStringArray = []
	out.append("Waves cleared: %d / %d" % [waves, total])
	out.append("Time: %s" % ArenaMode.format_time(seconds))
	if completed:
		out.append("Best time: %s%s" % [ArenaMode.format_time(float(record.get("best_time", 0.0))),
				"   (new best!)" if bool(record.get("new_best_time", false)) else ""])
	out.append("Furthest wave: %d%s" % [int(record.get("best_wave", 0)),
			"   (new best!)" if bool(record.get("new_best_wave", false)) else ""])
	return "\n".join(out)


func show_result(completed: bool, waves: int, total: int, seconds: float, record: Dictionary) -> void:
	_title.text = "ARENA CLEARED" if completed else "ARENA FAILED"
	_title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6) if completed else Color(0.95, 0.4, 0.35))
	_lines.text = summary(completed, waves, total, seconds, record)
	_again.visible = completed
	_open = true
	_root.visible = true
	if completed:
		get_tree().paused = true
		_again.grab_focus()


func close() -> void:
	_open = false
	_root.visible = false
	if is_inside_tree():
		get_tree().paused = false


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = HudTheme.theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	_title = _label("", 48, Color.WHITE)
	box.add_child(_title)
	_lines = _label("", 24, Color(0.9, 0.9, 0.92))
	box.add_child(_lines)
	_note = _label("Arena Mode pays no rewards and never touches your campaign save.", 16, HudTheme.TEXT_DIM)
	box.add_child(_note)
	_again = _button("Play again", func() -> void: play_again_pressed.emit())
	box.add_child(_again)
	_menu = _button("Main menu", func() -> void: menu_pressed.emit())
	box.add_child(_menu)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 26)
	b.pressed.connect(handler)
	return b
