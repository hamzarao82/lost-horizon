class_name ResultsScreen
extends CanvasLayer
## Shown when a mission quest completes: time, kills, secrets and the reward, then Continue or
## Main menu. Pauses the game while open. The mission is saved when the screen opens.

const MENU_SCENE: String = "res://scenes/boot/Boot.tscn"
const BUTTON_SIZE: Vector2 = Vector2(280, 56)

var _root: Control
var _labels: Dictionary = {}  # key -> Label
var _continue: Button
var _menu: Button
var _open: bool = false
var _was_paused: bool = false


func _init() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _ready() -> void:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null:
		return
	if quests.has_signal("mission_completed"):
		quests.mission_completed.connect(_on_mission_completed)
	else:  # older quest manager: the mission banner flag marks the mission quest
		quests.quest_completed.connect(_on_quest_completed)


static func format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func is_open() -> bool:
	return _open


func label_text(key: String) -> String:
	var label := _labels.get(key) as Label
	return label.text if label else ""


func label_color(key: String) -> Color:
	var label := _labels.get(key) as Label
	return label.get_theme_color("font_color") if label else Color.WHITE


## Like the intro and the ending, the automatic screen stays out of headless runs (tests call show_results).
func _on_mission_completed(quest_id: StringName) -> void:
	if DisplayServer.get_name() != "headless":
		show_results(quest_id)


func _on_quest_completed(quest_id: StringName) -> void:
	var quests := get_node_or_null("/root/QuestManager")
	var quest: QuestData = quests.get_quest(quest_id) if quests else null
	if quest != null and quest.show_mission_banner:
		_on_mission_completed(quest_id)


func show_results(quest_id: StringName) -> void:
	if _open:
		return
	var quests := get_node_or_null("/root/QuestManager")
	var quest: QuestData = quests.get_quest(quest_id) if quests else null
	var stats := get_node_or_null("/root/RunStats")
	_put("quest", quest.title if quest else String(quest_id), HudTheme.TEXT)
	if stats:
		_put("time", "Time played: " + format_time(stats.seconds_played))
		_put("kills", "Enemies defeated: %d" % stats.enemies_defeated)
		_put("secrets", "Secrets found: %d / %d" % [stats.secrets_found(), stats.secrets_total()])
	_show_reward(quest)
	var saves := get_node_or_null("/root/SaveManager")
	var saved: bool = saves != null and saves.autosave("mission")
	_put("saved", "Progress saved" if saved else "Progress could not be saved",
			HudTheme.STAMINA if saved else HudTheme.HEALTH)
	_open = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	_continue.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	# The ending screen owns the pause state when it is up.
	if not _was_paused and not _ending_open():
		get_tree().paused = false
		if not OS.has_feature("web") and not TouchControls.is_mobile_platform():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _ending_open() -> bool:
	for child in get_tree().root.get_children():
		if child is StoryEnding:
			return true
	return false


func _on_main_menu() -> void:
	var saves := get_node_or_null("/root/SaveManager")
	if saves:
		saves.reset_runtime_state()  # the mission was saved on opening; the menu's Continue loads that file
	var stats := get_node_or_null("/root/RunStats")
	if stats:
		stats.reset()
	_open = false
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


func _show_reward(quest: QuestData) -> void:
	var item: ItemData
	if quest != null and quest.rewards.size() > 0:
		var path := QuestData.ITEM_DIR + quest.rewards[0] + ".tres"
		if ResourceLoader.exists(path):
			item = load(path) as ItemData
	if item != null:
		_put("reward", "Reward: " + item.display_name, item.color())
	elif quest != null and quest.reward_text != "":
		_put("reward", "Reward: " + quest.reward_text, HudTheme.GOLD)
	else:
		_put("reward", "Reward: none", HudTheme.TEXT_DIM)


func _put(key: String, text: String, color: Color = HudTheme.TEXT) -> void:
	var label := _labels[key] as Label
	label.text = text
	label.add_theme_color_override("font_color", color)


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = HudTheme.theme()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "MISSION COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)
	_row(box, "quest", 26, true)
	box.add_child(HSeparator.new())
	_row(box, "time", 20)
	_row(box, "kills", 20)
	_row(box, "secrets", 20)
	_row(box, "reward", 22)
	_row(box, "saved", 18, true)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_continue = _button("Continue", close)
	_menu = _button("Main menu", _on_main_menu)
	buttons.add_child(_continue)
	buttons.add_child(_menu)


func _row(parent: Control, key: String, size: int, centered: bool = false) -> void:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	_labels[key] = label


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 24)
	b.pressed.connect(handler)
	return b
