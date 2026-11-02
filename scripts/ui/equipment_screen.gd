class_name EquipmentScreen
extends CanvasLayer
## Read-only gear overview: weapon (with a comparison to the one it replaced), armor, medkits,
## teleport charges, quest items and documents. Opened from the pause menu or with I.

signal closed

const PANEL_WIDTH: float = 560.0
const CLOSE_SIZE: Vector2 = Vector2(280, 56)
const CLOSE_ACTIONS: Array[StringName] = [&"pause", &"ui_cancel"]

var _root: Control
var _close_button: Button
var _labels: Dictionary = {}  # key -> Label
var _open: bool = false


func _init() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	refresh()
	_root.visible = true
	_close_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	var is_close: bool = event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_I
	for action in CLOSE_ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action) and not event.is_echo():
			is_close = true
	if is_close:
		close()
		get_viewport().set_input_as_handled()


func label_text(key: String) -> String:
	var label := _labels.get(key) as Label
	return label.text if label else ""


func label_color(key: String) -> Color:
	var label := _labels.get(key) as Label
	return label.get_theme_color("font_color") if label else Color.WHITE


## "+25%" / "-10%" for how much stronger `now` is than `before` (weapon power, armor points).
static func compare_text(now: ItemData, before: ItemData) -> String:
	if now == null or before == null or now == before:
		return ""
	var old_power := before.power()
	if old_power <= 0.0:
		return ""
	var percent := roundi((now.power() / old_power - 1.0) * 100.0)
	return "%s%d%% vs %s" % ["+" if percent >= 0 else "", percent, before.display_name]


func refresh() -> void:
	var player := get_tree().get_first_node_in_group("player") as Player if is_inside_tree() else null
	var inventory: Inventory = player.inventory if player else null
	var weapon: ItemData = inventory.weapon if inventory else null
	var armor: ItemData = inventory.armor if inventory else null
	_put("weapon_name", weapon.display_name if weapon else "None", weapon.color() if weapon else HudTheme.TEXT_DIM)
	if weapon:
		_put("weapon_stats", "Damage x%.2f   Speed x%.2f   Power %.2f" % [
				weapon.damage_multiplier, weapon.attack_speed, weapon.power()])
	else:
		_put("weapon_stats", "")
	var compare := compare_text(weapon, inventory.previous_weapon) if inventory else ""
	_put("weapon_compare", compare if compare != "" else "No earlier weapon to compare",
			(HudTheme.STAMINA if compare.begins_with("+") else HudTheme.HEALTH) if compare != "" else HudTheme.TEXT_DIM)

	if armor and player:
		_put("armor_name", armor.display_name, armor.color())
		_put("armor_points", "Armor %d / %d" % [roundi(player.health.armor), roundi(player.health.max_armor)])
		var armor_compare := compare_text(armor, inventory.previous_armor)
		_put("armor_compare", armor_compare, HudTheme.STAMINA if armor_compare.begins_with("+") else HudTheme.HEALTH)
	else:
		_put("armor_name", "None", HudTheme.TEXT_DIM)
		_put("armor_points", "No armor equipped")
		_put("armor_compare", "")
	_put("medkits", "Medkits: %d" % (inventory.potions if inventory else 0))
	_put("teleport", _teleport_text(player))
	_put("quest_items", _quest_items_text())
	var stats := get_node_or_null("/root/RunStats")
	_put("documents", "Documents found: %d" % (stats.documents_found() if stats else 0))


func _teleport_text(player: Player) -> String:
	var ability := player.get_node_or_null("TeleportAbility") as TeleportAbility if player else null
	if ability == null:
		return "Teleport: unavailable"
	var text := "Teleport: %d / %d charges" % [ability.charges, TeleportAbility.MAX_CHARGES]
	if ability.charges < TeleportAbility.MAX_CHARGES:
		var seconds := ceili(ability.seconds_until_next())
		text += "   next in %d:%02d" % [seconds / 60, seconds % 60]
	return text


func _quest_items_text() -> String:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null or quests.quest_items == null:
		return "Quest items: none"
	var names: Array[String] = []
	for id in quests.quest_items.all():
		names.append(str(QuestItems.NAMES.get(String(id), String(id).capitalize().replace("_", " "))))
	return "Quest items: " + (", ".join(names) if not names.is_empty() else "none")


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
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(Color(0.05, 0.07, 0.1, 1.0), 16, 2, Color(1, 1, 1, 0.18)))  # opaque: the pause menu sits behind
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)

	var title := Label.new()
	title.text = "EQUIPMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", HudTheme.GOLD)
	box.add_child(title)

	_row(box, "WEAPON", HudTheme.TEXT_DIM, 15)
	_row(box, "weapon_name", HudTheme.TEXT, 26)
	_row(box, "weapon_stats", HudTheme.TEXT, 18)
	_row(box, "weapon_compare", HudTheme.TEXT_DIM, 18)
	_row(box, "ARMOR", HudTheme.TEXT_DIM, 15)
	_row(box, "armor_name", HudTheme.TEXT, 26)
	_row(box, "armor_points", HudTheme.ARMOR, 18)
	_row(box, "armor_compare", HudTheme.TEXT_DIM, 18)
	_row(box, "SUPPLIES", HudTheme.TEXT_DIM, 15)
	_row(box, "medkits", HudTheme.HEALTH, 20)
	_row(box, "teleport", HudTheme.TELEPORT, 20)
	_row(box, "quest_items", HudTheme.GOLD, 18)
	_row(box, "documents", HudTheme.TEXT, 18)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = CLOSE_SIZE
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.add_theme_font_size_override("font_size", 24)
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


## Upper-case keys are plain section headings; anything else becomes a named, refreshable label.
func _row(parent: Control, key: String, color: Color, size: int) -> void:
	var label := Label.new()
	label.text = key if key == key.to_upper() else ""
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	if key != key.to_upper():
		_labels[key] = label
