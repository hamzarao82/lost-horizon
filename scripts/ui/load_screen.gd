class_name LoadScreen
extends CanvasLayer
## Load Game list: one row per save file SaveManager.list_saves() finds (never invented slots), with region,
## when it was saved, play time and the checkpoint. A damaged or too-new file is shown disabled with the reason.
## It only reports the choice; the main menu and the pause menu decide how to load it.

signal slot_chosen(slot: int)
signal closed

const WIDTH: float = 760.0
const MAX_LIST_HEIGHT: float = 340.0

var _root: Control
var _list: VBoxContainer
var _empty_label: Label
var _back: Button
var _box: VBoxContainer
var _rows: Array[Button] = []
var _entries: Array[Dictionary] = []


func _init() -> void:
	layer = 225
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _ready() -> void:
	refresh()


## Re-reads the files on disk and rebuilds the rows.
func refresh() -> void:
	var saves := get_node_or_null("/root/SaveManager")
	_entries = saves.list_saves() if saves != null else ([] as Array[Dictionary])
	set_entries(_entries)


func set_entries(entries: Array[Dictionary]) -> void:
	_entries = entries
	for child in _list.get_children():
		child.queue_free()
		_list.remove_child(child)
	_rows.clear()
	_empty_label.visible = entries.is_empty()
	for entry in entries:
		var row := Button.new()
		row.text = describe(entry)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(WIDTH - 40.0, 74.0)
		row.add_theme_font_size_override("font_size", 18)
		row.clip_text = true
		row.disabled = not bool(entry.get("usable", false))
		row.pressed.connect(_choose.bind(int(entry.get("slot", 0))))
		_list.add_child(row)
		_rows.append(row)
	_focus_first()


func rows() -> Array[Button]:
	return _rows


func back_button() -> Button:
	return _back


## The space the dialog asks for: the title, the (capped) list area and the Back button.
func content_minimum_size() -> Vector2:
	return _box.get_combined_minimum_size()


func empty_text_visible() -> bool:
	return _empty_label.visible


## Two lines: "Slot 1 - Dead Coast" and the details; an unusable file says why instead.
static func describe(entry: Dictionary) -> String:
	var slot_number := int(entry.get("slot", 0))
	if not bool(entry.get("usable", false)):
		return "Slot %d - unusable\n%s" % [slot_number, str(entry.get("note", "damaged save")).capitalize()]
	var parts: Array[String] = []
	var saved_at := int(entry.get("saved_at", 0))
	if saved_at > 0:
		parts.append("Saved " + format_saved_at(saved_at))
	var seconds := float(entry.get("seconds", 0.0))
	if seconds > 0.0:
		parts.append("Play time " + CampaignEnding.format_time(seconds))
	var checkpoint_id := str(entry.get("checkpoint_id", ""))
	if DeathScreen.CHECKPOINT_NAMES.has(checkpoint_id):
		parts.append(str(DeathScreen.CHECKPOINT_NAMES[checkpoint_id]))
	if bool(entry.get("campaign_complete", false)):
		parts.append("Campaign complete")
	var region := str(entry.get("region", ""))
	return "Slot %d - %s\n%s" % [slot_number, region if region != "" else RegionLabel.MASKED_NAME,
			"  |  ".join(parts) if not parts.is_empty() else "No details in this save"]


## Local date and time from a unix timestamp: "2026-11-14 18:20".
static func format_saved_at(unix: int) -> String:
	var local := unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(maxi(local, 0))
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


func _choose(slot_number: int) -> void:
	slot_chosen.emit(slot_number)


func close() -> void:
	closed.emit()
	queue_free()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _focus_first() -> void:
	for row in _rows:
		if not row.disabled:
			row.grab_focus.call_deferred()
			return
	if _back != null:
		_back.grab_focus.call_deferred()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = HudTheme.theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var box := VBoxContainer.new()
	_box = box
	box.custom_minimum_size = Vector2(WIDTH, 0.0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = "LOAD GAME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)
	_empty_label = Label.new()
	_empty_label.text = "No saved games."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", 20)
	_empty_label.add_theme_color_override("font_color", HudTheme.TEXT_DIM)
	box.add_child(_empty_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, 0.0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = MAX_LIST_HEIGHT
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(280.0, 56.0)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.add_theme_font_size_override("font_size", 24)
	_back.pressed.connect(close)
	box.add_child(_back)
