class_name InventoryScreen
extends RpgScreen
## Bag and equipment: category filter, sort, equipped list, item details with comparison, and the
## equip / unequip / use / drop / upgrade actions. Upgrades show a preview and need a confirmation.
## Rebuilds on Inventory signals only (never per frame).

const SLOTS: Array[int] = [
	ItemData.Slot.PRIMARY_WEAPON, ItemData.Slot.SECONDARY_WEAPON, ItemData.Slot.HEAD,
	ItemData.Slot.BODY, ItemData.Slot.GLOVES, ItemData.Slot.LEGS, ItemData.Slot.ACCESSORY,
]
const FILTER_LABELS: Array[String] = ["All", "Weapons", "Armor", "Consumables", "Materials", "Quest", "Collectibles", "Upgrades"]

var _filter: int = -1  # -1 = all, otherwise ItemData.Category
var _selected_id: String = ""
var _list: VBoxContainer
var _details: ItemDetailsPanel
var _actions: HFlowContainer
var _filter_row: HFlowContainer
var _header_label: Label
var _confirm: PanelContainer
var _confirm_body: VBoxContainer
var _refresh_queued: bool = false
var _hooked: Inventory
var _row_buttons: Dictionary = {}  # item_id -> Button


func _init() -> void:
	super._init()
	title_text = "Inventory"


func details() -> ItemDetailsPanel:
	return _details


func selected_id() -> String:
	return _selected_id


func current_filter() -> int:
	return _filter


func row_ids() -> Array:
	return _row_buttons.keys()


func action_labels() -> Array[String]:
	var out: Array[String] = []
	for child in _actions.get_children():
		out.append((child as Button).text)
	return out


func action_button(label: String) -> Button:
	for child in _actions.get_children():
		if (child as Button).text == label:
			return child as Button
	return null


func header_text() -> String:
	return _header_label.text if _header_label else ""


func is_confirming() -> bool:
	return _confirm != null and _confirm.visible


func select(item_id: String) -> void:
	_selected_id = item_id
	_refresh_now()


func set_filter(category: int) -> void:
	_filter = category
	_refresh_now()


func _build_content() -> void:
	_header_label = RpgUi.label("", HudTheme.FONT_BODY, HudTheme.GOLD)
	content.add_child(_header_label)

	_filter_row = HFlowContainer.new()
	_filter_row.add_theme_constant_override("h_separation", 6)
	_filter_row.add_theme_constant_override("v_separation", 6)
	content.add_child(_filter_row)
	for i in FILTER_LABELS.size():
		var category := i - 1
		_filter_row.add_child(RpgUi.button(FILTER_LABELS[i], func() -> void: set_filter(category), 96.0))
	_filter_row.add_child(RpgUi.button("Sort", _on_sort, 96.0))

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 240)
	split.add_theme_constant_override("separation", 10)
	content.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = 1.2
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)
	_details = ItemDetailsPanel.new()
	right.add_child(_details)
	_actions = HFlowContainer.new()
	_actions.add_theme_constant_override("h_separation", 6)
	_actions.add_theme_constant_override("v_separation", 6)
	right.add_child(_actions)

	_build_confirm()


func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.visible = false
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.custom_minimum_size = Vector2(380, 0)
	_root.add_child(_confirm)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_confirm.add_child(margin)
	_confirm_body = VBoxContainer.new()
	_confirm_body.add_theme_constant_override("separation", 8)
	margin.add_child(_confirm_body)


func _connect_sources() -> void:
	var inv := inventory()
	if inv == null or inv == _hooked:
		return
	if _hooked != null and is_instance_valid(_hooked):
		_hooked.changed.disconnect(_queue_refresh)
		_hooked.item_changed.disconnect(_queue_refresh_id)
		_hooked.currency_changed.disconnect(_queue_refresh_currency)
	_hooked = inv
	inv.changed.connect(_queue_refresh)
	inv.item_changed.connect(_queue_refresh_id)
	inv.currency_changed.connect(_queue_refresh_currency)


func _queue_refresh_id(_id: String) -> void:
	_queue_refresh()


func _queue_refresh_currency(_amount: int) -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	if not _open or _refresh_queued:
		return
	_refresh_queued = true
	_refresh_now.call_deferred()


func _refresh_now() -> void:
	_refresh_queued = false
	if _list == null:
		return
	refresh()


func _focus_first() -> void:
	if _row_buttons.has(_selected_id):
		(_row_buttons[_selected_id] as Button).grab_focus()
	elif _row_buttons.size() > 0:
		(_row_buttons[_row_buttons.keys()[0]] as Button).grab_focus()
	else:
		super._focus_first()


func refresh() -> void:
	var inv := inventory()
	RpgUi.clear(_list)
	_row_buttons.clear()
	if inv == null:
		_header_label.text = "No inventory"
		_details.clear_item()
		_refresh_actions(null, null)
		return
	_header_label.text = "Credits: %d    Bag: %d / %d    Medkits: %d" % [
		inv.currency, inv.stack_count(), Inventory.BAG_CAPACITY, inv.potions]

	_list.add_child(RpgUi.label("Equipped", HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	for slot in SLOTS:
		var worn := inv.equipped(slot)
		var slot_name := String(ItemData.SLOT_NAMES[slot]).replace("_", " ").capitalize()
		if worn != null:
			_add_row(worn, "%s: %s" % [slot_name, worn.display_name], inv, true)
		else:
			_list.add_child(RpgUi.label("%s: empty" % slot_name, HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	_list.add_child(RpgUi.label("Bag", HudTheme.FONT_SMALL, HudTheme.TEXT_DIM))
	for stack in inv.stacks(_filter):
		var item := stack["item"] as ItemData
		var text := item.display_name if int(stack["count"]) <= 1 else "%s  x%d" % [item.display_name, int(stack["count"])]
		_add_row(item, text, inv, false)

	var item := _selected_item(inv)
	if item == null:
		_selected_id = ""
	var compare_to: ItemData = null
	if item != null and item.is_equipment() and not inv.is_equipped(item):
		compare_to = inv.equipped(int(item.equip_slot()))
	_details.show_item(item, inv, compare_to)
	_refresh_actions(item, inv)


func _selected_item(inv: Inventory) -> ItemData:
	if _selected_id == "":
		return null
	for slot in SLOTS:
		var worn := inv.equipped(slot)
		if worn != null and String(worn.item_id) == _selected_id:
			return worn
	return inv.bag_item(_selected_id)


func _add_row(item: ItemData, text: String, _inv: Inventory, _worn: bool) -> void:
	var id := String(item.item_id)
	var row := Button.new()
	row.text = text
	row.icon = RpgUi.icon_for(item)
	row.expand_icon = true
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.custom_minimum_size = Vector2(0, RpgUi.TOUCH_HEIGHT)
	row.add_theme_constant_override("icon_max_width", 40)
	row.add_theme_color_override("font_color", RpgUi.rarity_color(item))
	row.toggle_mode = true
	row.button_pressed = id == _selected_id
	row.pressed.connect(func() -> void: select(id))
	_list.add_child(row)
	if not _row_buttons.has(id):
		_row_buttons[id] = row


func _refresh_actions(item: ItemData, inv: Inventory) -> void:
	RpgUi.clear(_actions)
	if item == null or inv == null:
		return
	if item.is_equipment():
		if inv.is_equipped(item):
			_actions.add_child(RpgUi.button("Unequip", _on_unequip, 120.0))
		else:
			_actions.add_child(RpgUi.button("Equip", _on_equip, 120.0))
		var up := RpgUi.button("Upgrade", _on_upgrade, 120.0)
		up.disabled = item.max_upgrade <= 0
		_actions.add_child(up)
	if item.kind == ItemData.Kind.CONSUMABLE and item.effect != "":
		_actions.add_child(RpgUi.button("Use", _on_use, 120.0))
	if not inv.is_equipped(item):
		var drop := RpgUi.button("Drop", _on_drop, 120.0)
		drop.disabled = item.is_protected()
		_actions.add_child(drop)


func _on_sort() -> void:
	var inv := inventory()
	if inv:
		inv.sort_bag()
		set_status("Bag sorted.")
		_refresh_now()


func _on_equip() -> void:
	var inv := inventory()
	var item := _selected_item(inv) if inv else null
	if item == null:
		return
	var result := inv.equip(item)
	if result.get("ok", false):
		set_status("Equipped %s." % item.display_name, HudTheme.STAMINA)
	else:
		set_status(RpgUi.reason_text(String(result.get("reason", ""))), RpgUi.BAD)
	_refresh_now()


func _on_unequip() -> void:
	var inv := inventory()
	var item := _selected_item(inv) if inv else null
	if item == null:
		return
	var result := inv.unequip(int(item.equip_slot()))
	if result.get("ok", false):
		set_status("Unequipped %s." % item.display_name, HudTheme.TEXT)
	else:
		set_status(RpgUi.reason_text(String(result.get("reason", ""))), RpgUi.BAD)
	_refresh_now()


func _on_use() -> void:
	var inv := inventory()
	if inv == null or _selected_id == "":
		return
	var result := inv.use_item(_selected_id)
	if result.get("ok", false):
		set_status("Used.", HudTheme.STAMINA)
	else:
		set_status(RpgUi.reason_text(String(result.get("reason", ""))), RpgUi.BAD)
	_refresh_now()


func _on_drop() -> void:
	var inv := inventory()
	if inv == null or _selected_id == "":
		return
	var result := inv.drop(_selected_id, 1)
	if result.get("ok", false):
		set_status("Dropped one.", HudTheme.TEXT)
	else:
		set_status(RpgUi.reason_text(String(result.get("reason", ""))), RpgUi.BAD)
	_refresh_now()


# --- upgrade confirmation -----------------------------------------------------------------------

func _on_upgrade() -> void:
	var inv := inventory()
	var item := _selected_item(inv) if inv else null
	if item == null:
		return
	var preview := UpgradeService.preview(item, inv)
	RpgUi.clear(_confirm_body)
	_confirm_body.add_child(RpgUi.label("Upgrade %s" % item.display_name, HudTheme.FONT_TITLE, HudTheme.GOLD))
	_confirm_body.add_child(RpgUi.label("Level +%d  ->  +%d" % [int(preview["from"]), int(preview["to"])], HudTheme.FONT_BODY))
	var before := preview["before"] as Dictionary
	var after := preview["after"] as Dictionary
	var keys := RpgUi.visible_stat_keys(before)
	for key in RpgUi.visible_stat_keys(after):
		if not keys.has(key):
			keys.append(key)
	for key in keys:
		var delta := float(after.get(key, 0.0)) - float(before.get(key, 0.0))
		var line := "%s: %s -> %s" % [RpgUi.STAT_LABELS.get(key, key),
				RpgUi.format_stat(key, float(before.get(key, 0.0))), RpgUi.format_stat(key, float(after.get(key, 0.0)))]
		var color := HudTheme.TEXT
		if absf(delta) > 0.0001:
			color = RpgUi.GOOD if delta > 0.0 else RpgUi.BAD
		_confirm_body.add_child(RpgUi.label(line, HudTheme.FONT_BODY, color))
	var cost_parts: Array[String] = []
	for id in (preview["materials"] as Dictionary).keys():
		var need := int((preview["materials"] as Dictionary)[id])
		var have := inv.count_of(String(id))
		var mat := MerchantService.item_for(String(id))
		cost_parts.append("%s %d/%d" % [mat.display_name if mat else String(id), have, need])
	if int(preview["currency"]) > 0:
		cost_parts.append("Credits %d/%d" % [inv.currency, int(preview["currency"])])
	if not cost_parts.is_empty():
		_confirm_body.add_child(RpgUi.label("Cost: " + ", ".join(cost_parts), HudTheme.FONT_BODY, HudTheme.GOLD))
	var reason := String(preview["reason"])
	if reason != "":
		_confirm_body.add_child(RpgUi.label(RpgUi.reason_text(reason), HudTheme.FONT_BODY, RpgUi.BAD))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var ok := RpgUi.button("Confirm", func() -> void: confirm_upgrade(item), 140.0)
	ok.disabled = not bool(preview["ok"])
	buttons.add_child(ok)
	buttons.add_child(RpgUi.button("Cancel", cancel_upgrade, 140.0))
	_confirm_body.add_child(buttons)
	_confirm.visible = true
	(buttons.get_child(1) as Button).grab_focus()


func confirm_upgrade(item: ItemData) -> void:
	var inv := inventory()
	if inv == null:
		return
	var result := UpgradeService.upgrade(item, inv)
	_confirm.visible = false
	if result.get("ok", false):
		set_status("%s upgraded." % item.display_name, HudTheme.STAMINA)
	else:
		set_status(RpgUi.reason_text(String(result.get("reason", ""))), RpgUi.BAD)
	_refresh_now()


func cancel_upgrade() -> void:
	_confirm.visible = false
	_focus_first()


func _consume_cancel() -> bool:
	if is_confirming():
		cancel_upgrade()
		return true
	return false
