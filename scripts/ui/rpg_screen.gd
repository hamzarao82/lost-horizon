class_name RpgScreen
extends CanvasLayer
## Base for the full-screen RPG panels (inventory, character, crafting, merchant): themed dim backdrop,
## one big panel with a title row and a close button, pause-while-open, and ui_cancel / pause to close.
## Subclasses fill `content` in `_build_content()` and rebuild it in `refresh()` (called on signals only).

signal closed

const MARGIN: float = 16.0
const CLOSE_ACTIONS: Array[StringName] = [&"pause", &"ui_cancel"]

var title_text: String = "Screen"
var content: VBoxContainer
var _root: Control
var _title: Label
var _status: Label
var _close_button: Button
var _open: bool = false
var _was_paused: bool = false
var _inventory: Inventory
var _bound_inventory: Inventory


func _init() -> void:
	layer = 91
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_build_frame()
	_build_content()


func is_open() -> bool:
	return _open


## Tests and the pause menu can hand a specific inventory; otherwise the player's is used.
func bind_inventory(inventory: Inventory) -> void:
	_bound_inventory = inventory
	_on_inventory_changed()


func inventory() -> Inventory:
	if _bound_inventory != null and is_instance_valid(_bound_inventory):
		return _bound_inventory
	var player := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	if player != null and player.get("inventory") != null:
		return player.get("inventory") as Inventory
	return null


func progression() -> Node:
	return get_node_or_null("/root/Progression") if is_inside_tree() else null


func open() -> void:
	if _open:
		return
	_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_connect_sources()
	refresh()
	_root.visible = true
	_focus_first()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	get_tree().paused = _was_paused
	if not _was_paused and not OS.has_feature("web") and not TouchControls.is_mobile_platform():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func set_status(text: String, color: Color = HudTheme.TEXT_DIM) -> void:
	if _status:
		_status.text = text
		_status.add_theme_color_override("font_color", color)


func status_text() -> String:
	return _status.text if _status else ""


func root_control() -> Control:
	return _root


## Subclasses override.
func _build_content() -> void:
	pass


func refresh() -> void:
	pass


func _connect_sources() -> void:
	pass


func _on_inventory_changed() -> void:
	if _open:
		refresh()


func _focus_first() -> void:
	_close_button.grab_focus()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	for action in CLOSE_ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
			if _consume_cancel():
				get_viewport().set_input_as_handled()
				return
			close()
			get_viewport().set_input_as_handled()
			return


func _build_frame() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = HudTheme.theme()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, int(MARGIN))
	_root.add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(Color(0.04, 0.06, 0.09, 1.0), 16, 2, Color(1, 1, 1, 0.18)))
	margin.add_child(panel)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(inner)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	inner.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_title = RpgUi.label(title_text, HudTheme.FONT_BANNER, HudTheme.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_close_button = RpgUi.button("Close", close, 140.0)
	header.add_child(_close_button)

	var body := ScrollContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(body)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	body.add_child(content)

	_status = RpgUi.label("", HudTheme.FONT_SMALL, HudTheme.TEXT_DIM)
	column.add_child(_status)


## Subclasses return true when the cancel press was used to dismiss an overlay (confirm dialog).
func _consume_cancel() -> bool:
	return false
