class_name CharacterScreen
extends RpgScreen
## Level and XP, derived stats, attribute point spending and the skill tree (grid of nodes with
## prerequisite lines; locked / available / owned / maxed states). All rules live in Progression and
## SkillTree; this screen only calls them and redraws on Progression signals.

const CELL: Vector2 = Vector2(176, 84)
const NODE_SIZE: Vector2 = Vector2(160, 64)
const ROW_NAMES: Array[String] = ["Combat", "Survival", "Mobility", "Special"]
const STATE_COLORS: Array[Color] = [
	Color(0.5, 0.5, 0.55), Color(0.97, 0.85, 0.35), Color(0.45, 0.9, 0.5), Color(0.45, 0.75, 1.0),
]  # LOCKED, AVAILABLE, OWNED, MAXED (SkillTree.State order)

var _stats_box: VBoxContainer
var _attr_box: VBoxContainer
var _tree_canvas: Control
var _skill_info: VBoxContainer
var _selected_skill: StringName = &""
var _skill_buttons: Dictionary = {}  # id -> Button
var _attr_buttons: Dictionary = {}  # id -> Button
var _hooked: Node
var _xp_bar: ProgressBar


func _init() -> void:
	super._init()
	title_text = "Character"


func selected_skill() -> StringName:
	return _selected_skill


func skill_button(id: StringName) -> Button:
	return _skill_buttons.get(id) as Button


func attribute_button(id: StringName) -> Button:
	return _attr_buttons.get(id) as Button


func stats_text() -> String:
	var parts: Array[String] = []
	for child in _stats_box.get_children():
		if child is Label:
			parts.append((child as Label).text)
	return "\n".join(parts)


func skill_info_text() -> String:
	var parts: Array[String] = []
	for child in _skill_info.get_children():
		if child is Label:
			parts.append((child as Label).text)
	return "\n".join(parts)


func select_skill(id: StringName) -> void:
	_selected_skill = id
	_refresh_skill_info()


func _build_content() -> void:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 240)
	split.add_theme_constant_override("separation", 12)
	content.add_child(split)

	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 0.9
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	left_scroll.add_child(left)
	_stats_box = VBoxContainer.new()
	left.add_child(_stats_box)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 18)
	_xp_bar.show_percentage = false
	_xp_bar.add_theme_stylebox_override("background", HudTheme.panel_style(HudTheme.BAR_BACK, 6, 1))
	_xp_bar.add_theme_stylebox_override("fill", HudTheme.panel_style(HudTheme.GOLD, 6, 0))
	left.add_child(_xp_bar)
	left.add_child(RpgUi.label("Attributes", HudTheme.FONT_TITLE, HudTheme.GOLD))
	_attr_box = VBoxContainer.new()
	_attr_box.add_theme_constant_override("separation", 4)
	left.add_child(_attr_box)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.4
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	right.add_child(RpgUi.label("Skills", HudTheme.FONT_TITLE, HudTheme.GOLD))
	var tree_scroll := ScrollContainer.new()
	tree_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_scroll.size_flags_stretch_ratio = 1.6
	right.add_child(tree_scroll)
	_tree_canvas = Control.new()
	_tree_canvas.custom_minimum_size = Vector2(CELL.x * 3.0 + 8.0, CELL.y * 4.0 + 8.0)
	_tree_canvas.draw.connect(_draw_lines)
	tree_scroll.add_child(_tree_canvas)
	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(info_scroll)
	_skill_info = VBoxContainer.new()
	_skill_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(_skill_info)


func _connect_sources() -> void:
	var node := progression()
	if node == null or node == _hooked:
		return
	_hooked = node
	for signal_name in ["points_changed", "skill_changed", "level_up", "xp_gained"]:
		node.connect(signal_name, _on_progression_signal)


func _on_progression_signal(_a: Variant = null, _b: Variant = null) -> void:
	if _open:
		refresh.call_deferred()


func _focus_first() -> void:
	var first := _skill_buttons.keys()
	if first.size() > 0:
		(_skill_buttons[first[0]] as Button).grab_focus()
	else:
		super._focus_first()


func refresh() -> void:
	if _stats_box == null:
		return
	var node := progression()
	RpgUi.clear(_stats_box)
	RpgUi.clear(_attr_box)
	RpgUi.clear(_tree_canvas)
	_skill_buttons.clear()
	_attr_buttons.clear()
	if node == null or node.get("progress") == null:
		_stats_box.add_child(RpgUi.label("Progression is not available.", HudTheme.FONT_BODY, HudTheme.TEXT_DIM))
		return
	var progress: PlayerProgress = node.get("progress")
	_stats_box.add_child(RpgUi.label("Level %d" % progress.level(), HudTheme.FONT_BANNER, HudTheme.TEXT))
	var needed := progress.xp_needed_for_next()
	var into := progress.xp_into_level()
	if needed > 0:
		_stats_box.add_child(RpgUi.label("XP %d / %d" % [into, needed], HudTheme.FONT_BODY, HudTheme.TEXT_DIM))
		_xp_bar.max_value = needed
		_xp_bar.value = into
	else:
		_stats_box.add_child(RpgUi.label("Maximum level", HudTheme.FONT_BODY, HudTheme.GOLD))
		_xp_bar.max_value = 1.0
		_xp_bar.value = 1.0
	_stats_box.add_child(RpgUi.label("Attribute points: %d    Skill points: %d" % [
		progress.attribute_points, progress.skill_points], HudTheme.FONT_BODY, HudTheme.GOLD))
	var resist := 1.0 - float(node.call("incoming_multiplier"))
	_stats_box.add_child(RpgUi.label("Damage resistance: %d%%" % roundi(resist * 100.0), HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	_stats_box.add_child(RpgUi.label("Max health bonus: +%d" % roundi(float(node.call("max_health_bonus"))), HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	_stats_box.add_child(RpgUi.label("Teleport recharge: x%.2f" % float(node.call("teleport_recharge_multiplier")), HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	var inv := inventory()
	if inv != null:
		_stats_box.add_child(RpgUi.label("Credits: %d" % inv.currency, HudTheme.FONT_SMALL, HudTheme.GOLD))

	for data in node.get("attribute_defs"):
		_add_attribute_row(node, progress, data as AttributeData)
	_build_tree(node, progress)
	_refresh_skill_info()


func _add_attribute_row(node: Node, progress: PlayerProgress, data: AttributeData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spent := int(progress.attributes.get(data.id, 0))
	text.add_child(RpgUi.label("%s  %d / %d" % [data.display_name, data.base + spent, data.base + data.max_points], HudTheme.FONT_BODY))
	text.add_child(RpgUi.label(data.purpose, HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	row.add_child(text)
	var plus := RpgUi.button("+", func() -> void: _spend_attribute(node, data.id), 64.0)
	plus.disabled = progress.attribute_points < 1 or spent >= data.max_points
	row.add_child(plus)
	_attr_box.add_child(row)
	_attr_buttons[data.id] = plus


func _spend_attribute(node: Node, id: StringName) -> void:
	if node.call("spend_attribute_point", id):
		set_status("Attribute raised.", HudTheme.STAMINA)
	else:
		set_status("No attribute points to spend, or already at the limit.", RpgUi.BAD)
	refresh.call_deferred()


func _build_tree(node: Node, progress: PlayerProgress) -> void:
	var tree: SkillTree = node.get("tree")
	if tree == null:
		return
	for skill in tree.all():
		var data := skill as SkillData
		var state: int = tree.state(progress, data.id)
		var rank := progress.skill_rank(data.id)
		var button := Button.new()
		button.text = "%s\n%d / %d" % [data.display_name, rank, data.max_rank]
		button.position = Vector2(data.tree_position.x * CELL.x + 4.0, data.tree_position.y * CELL.y + 8.0)
		button.size = NODE_SIZE
		button.custom_minimum_size = NODE_SIZE
		button.add_theme_color_override("font_color", STATE_COLORS[state])
		button.add_theme_font_size_override("font_size", HudTheme.FONT_SMALL)
		button.toggle_mode = true
		button.button_pressed = data.id == _selected_skill
		var id := data.id
		button.pressed.connect(func() -> void: select_skill(id))
		_tree_canvas.add_child(button)
		_skill_buttons[data.id] = button
	_tree_canvas.queue_redraw()


func _draw_lines() -> void:
	var node := progression()
	if node == null or node.get("tree") == null or node.get("progress") == null:
		return
	var tree: SkillTree = node.get("tree")
	var progress: PlayerProgress = node.get("progress")
	for skill in tree.all():
		var data := skill as SkillData
		var to_button := _skill_buttons.get(data.id) as Button
		if to_button == null:
			continue
		for pre in data.prerequisites:
			var from_button := _skill_buttons.get(StringName(pre)) as Button
			if from_button == null:
				continue
			var active := progress.skill_rank(StringName(pre)) >= 1
			var color := Color(0.45, 0.9, 0.5, 0.9) if active else Color(0.5, 0.5, 0.55, 0.6)
			_tree_canvas.draw_line(from_button.position + from_button.size * 0.5,
					to_button.position + to_button.size * 0.5, color, 3.0)


func _refresh_skill_info() -> void:
	if _skill_info == null:
		return
	RpgUi.clear(_skill_info)
	var node := progression()
	if node == null or node.get("tree") == null or _selected_skill == &"":
		_skill_info.add_child(RpgUi.label("Select a skill.", HudTheme.FONT_BODY, HudTheme.TEXT_DIM))
		return
	var tree: SkillTree = node.get("tree")
	var progress: PlayerProgress = node.get("progress")
	var data := tree.get_skill(_selected_skill)
	if data == null:
		return
	var rank := progress.skill_rank(data.id)
	_skill_info.add_child(RpgUi.label("%s  (%s)" % [data.display_name, ROW_NAMES[int(data.category)]], HudTheme.FONT_TITLE, HudTheme.GOLD))
	_skill_info.add_child(RpgUi.label(data.description, HudTheme.FONT_BODY))
	_skill_info.add_child(RpgUi.label("Rank %d / %d    Cost: %d    Requires level %d" % [
		rank, data.max_rank, data.cost, data.min_level], HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	var reason := tree.block_reason(progress, data.id)
	var buy := RpgUi.button("Upgrade" if rank > 0 else "Unlock", func() -> void: _buy_skill(node, data.id), 160.0)
	buy.disabled = reason != ""
	if reason != "":
		_skill_info.add_child(RpgUi.label(reason, HudTheme.FONT_SMALL, RpgUi.BAD))
	_skill_info.add_child(buy)


func _buy_skill(node: Node, id: StringName) -> void:
	if node.call("unlock_skill", id):
		set_status("Skill improved.", HudTheme.STAMINA)
	else:
		set_status("That skill is not available yet.", RpgUi.BAD)
	refresh.call_deferred()
