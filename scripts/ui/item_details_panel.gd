class_name ItemDetailsPanel
extends PanelContainer
## Description, stats and, when a comparison item is given, coloured stat deltas (green better, red worse).
## Pure presentation: it reads stats through the Inventory so upgrade levels are included.

var _column: VBoxContainer
var _lines: Array[String] = []


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 6)
	scroll.add_child(_column)
	clear_item()


## All text currently shown, one entry per line (tests and screenshots read this).
func lines() -> Array[String]:
	return _lines


func text_dump() -> String:
	return "\n".join(_lines)


func clear_item() -> void:
	RpgUi.clear(_column)
	_lines.clear()
	_add("Select an item", HudTheme.TEXT_DIM)


## `compare_to` is the item that would be replaced (or null for no comparison).
func show_item(item: ItemData, inventory: Inventory, compare_to: ItemData = null) -> void:
	RpgUi.clear(_column)
	_lines.clear()
	if item == null:
		_add("Select an item", HudTheme.TEXT_DIM)
		return
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(RpgUi.icon_rect(item, 56.0))
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var name_label := RpgUi.label(item.display_name, HudTheme.FONT_TITLE, RpgUi.rarity_color(item))
	titles.add_child(name_label)
	_lines.append(item.display_name)
	var sub := "%s  |  %s" % [RpgUi.rarity_name(item), ItemData.CATEGORY_NAMES[int(item.category())]]
	var level := inventory.level_of(item) if inventory else 0
	if item.is_equipment():
		sub += "  |  +%d / +%d" % [level, item.max_upgrade]
	titles.add_child(RpgUi.label(sub, HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	_lines.append(sub)
	_column.add_child(head)

	if item.description != "":
		_add(item.description, HudTheme.TEXT)
	if item.is_protected():
		_add("Quest or unique item: cannot be dropped or sold.", HudTheme.GOLD)

	if item.is_equipment() and inventory != null:
		_add_stats(item, inventory, compare_to)
	elif item.kind == ItemData.Kind.CONSUMABLE:
		_add_consumable(item)
	if item.value > 0:
		_add("Value: %d credits" % item.value, HudTheme.GOLD)


func _add_stats(item: ItemData, inventory: Inventory, compare_to: ItemData) -> void:
	var stats := inventory.item_stats(item)
	var deltas: Dictionary = {}
	if compare_to != null and compare_to != item:
		deltas = inventory.compare(compare_to, item)
		_add("Compared with %s:" % compare_to.display_name, HudTheme.TEXT_DIM)
	var keys: Array[String] = RpgUi.visible_stat_keys(stats)
	for key in deltas.keys():
		if not keys.has(String(key)) and absf(float(deltas[key])) > 0.0001:
			keys.append(String(key))
	for key in keys:
		var row := HBoxContainer.new()
		var name := RpgUi.label(String(RpgUi.STAT_LABELS.get(key, key)), HudTheme.FONT_BODY, HudTheme.TEXT_DIM)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(name)
		var value_text := RpgUi.format_stat(key, float(stats.get(key, 0.0)))
		var value_label := RpgUi.label(value_text, HudTheme.FONT_BODY, HudTheme.TEXT)
		value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(value_label)
		var line := "%s: %s" % [RpgUi.STAT_LABELS.get(key, key), value_text]
		if deltas.has(key) and absf(float(deltas[key])) > 0.0001:
			var delta := float(deltas[key])
			var delta_text := RpgUi.format_delta(key, delta)
			var color := RpgUi.GOOD if delta > 0.0 else RpgUi.BAD
			var delta_label := RpgUi.label("  " + delta_text, HudTheme.FONT_BODY, color)
			delta_label.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(delta_label)
			line += " (%s)" % delta_text
		_column.add_child(row)
		_lines.append(line)


func _add_consumable(item: ItemData) -> void:
	match item.effect:
		"heal": _add("Restores %d health." % roundi(item.effect_amount), HudTheme.HEALTH)
		"armor_restore": _add("Restores %d armor." % roundi(item.effect_amount), HudTheme.ARMOR)
		"buff": _add("Buff for %d s." % roundi(item.buff_seconds), HudTheme.STAMINA)
		"teleport_charge": _add("Restores a teleport charge.", HudTheme.TELEPORT)
	if item.cooldown > 0.0:
		_add("Cooldown: %d s" % roundi(item.cooldown), HudTheme.TEXT_DIM)


func _add(text: String, color: Color) -> void:
	_column.add_child(RpgUi.label(text, HudTheme.FONT_BODY, color))
	_lines.append(text)
