class_name MerchantScreen
extends RpgScreen
## Buy and sell with a vendor. Opens for a MerchantData (`open_for`) and listens to MerchantNpc's
## `trade_requested` signal. MerchantService validates every transaction; this screen shows its answer.

const MAX_QTY: int = 99

var merchant: MerchantData
var _buying: bool = true
var _qty: int = 1
var _selected_id: String = ""
var _list: VBoxContainer
var _details: ItemDetailsPanel
var _qty_label: Label
var _action_button: Button
var _header_label: Label
var _tab_buy: Button
var _tab_sell: Button
var _hooked: Inventory
var _row_buttons: Dictionary = {}  # item_id -> Button


func _init() -> void:
	super._init()
	title_text = "Merchant"


func _ready() -> void:
	super._ready()
	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "MerchantNpc", true, false):
		_hook_npc(node)


func _hook_npc(node: Node) -> void:
	if node is MerchantNpc and not (node as MerchantNpc).trade_requested.is_connected(_on_trade_requested):
		(node as MerchantNpc).trade_requested.connect(_on_trade_requested)


func _on_node_added(node: Node) -> void:
	_hook_npc(node)


func _on_trade_requested(data: MerchantData, _player: Node3D) -> void:
	open_for(data)


func open_for(data: MerchantData) -> void:
	merchant = data
	title_text = data.display_name if data else "Merchant"
	if _title:
		_title.text = title_text
	_buying = true
	_qty = 1
	_selected_id = ""
	open()


func is_buying() -> bool:
	return _buying


func quantity() -> int:
	return _qty


func selected_id() -> String:
	return _selected_id


func row_ids() -> Array:
	return _row_buttons.keys()


func action_button() -> Button:
	return _action_button


func header_text() -> String:
	return _header_label.text if _header_label else ""


func details() -> ItemDetailsPanel:
	return _details


func set_mode(buying: bool) -> void:
	_buying = buying
	_selected_id = ""
	_qty = 1
	refresh()


func select(item_id: String) -> void:
	_selected_id = item_id
	refresh()


func set_quantity(value: int) -> void:
	_qty = clampi(value, 1, MAX_QTY)
	refresh()


func _build_content() -> void:
	_header_label = RpgUi.label("", HudTheme.FONT_BODY, HudTheme.GOLD)
	content.add_child(_header_label)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	content.add_child(tabs)
	_tab_buy = RpgUi.button("Buy", func() -> void: set_mode(true), 120.0)
	_tab_buy.toggle_mode = true
	tabs.add_child(_tab_buy)
	_tab_sell = RpgUi.button("Sell", func() -> void: set_mode(false), 120.0)
	_tab_sell.toggle_mode = true
	tabs.add_child(_tab_sell)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 240)
	split.add_theme_constant_override("separation", 10)
	content.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var qty_row := HBoxContainer.new()
	qty_row.add_theme_constant_override("separation", 6)
	right.add_child(qty_row)
	qty_row.add_child(RpgUi.button("-", func() -> void: set_quantity(_qty - 1), 64.0))
	_qty_label = RpgUi.label("1", HudTheme.FONT_TITLE)
	_qty_label.custom_minimum_size = Vector2(48, 0)
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_row.add_child(_qty_label)
	qty_row.add_child(RpgUi.button("+", func() -> void: set_quantity(_qty + 1), 64.0))
	_action_button = RpgUi.button("Buy", _on_action, 160.0)
	qty_row.add_child(_action_button)


func _connect_sources() -> void:
	var inv := inventory()
	if inv == null or inv == _hooked:
		return
	_hooked = inv
	inv.changed.connect(_on_inventory_changed)
	inv.currency_changed.connect(func(_amount: int) -> void: _on_inventory_changed())


func _focus_first() -> void:
	if _row_buttons.size() > 0:
		(_row_buttons[_row_buttons.keys()[0]] as Button).grab_focus()
	else:
		super._focus_first()


func refresh() -> void:
	if _list == null:
		return
	var inv := inventory()
	RpgUi.clear(_list)
	_row_buttons.clear()
	_tab_buy.button_pressed = _buying
	_tab_sell.button_pressed = not _buying
	_qty_label.text = str(_qty)
	_action_button.text = "Buy" if _buying else "Sell"
	if inv == null or merchant == null:
		_header_label.text = "No vendor"
		_details.clear_item()
		_action_button.disabled = true
		return
	_header_label.text = "Credits: %d" % inv.currency
	if _buying:
		for i in merchant.stock_ids.size():
			var id := String(merchant.stock_ids[i])
			var item := MerchantService.item_for(id)
			if item == null:
				continue
			var left := MerchantService.stock_left(inv, merchant, id)
			var stock_text := "" if left == -1 else ("  (sold out)" if left == 0 else "  (%d left)" % left)
			_add_row(item, "%s  -  %d%s" % [item.display_name, MerchantService.buy_price(merchant, id), stock_text])
	else:
		for stack in inv.stacks():
			var item := stack["item"] as ItemData
			var price := MerchantService.sell_price(merchant, item)
			if price <= 0:
				continue
			_add_row(item, "%s  x%d  -  %d each" % [item.display_name, int(stack["count"]), price])
	var selected := MerchantService.item_for(_selected_id) if _selected_id != "" else null
	_details.show_item(selected, inv, null)
	_action_button.disabled = selected == null


func _add_row(item: ItemData, text: String) -> void:
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
	_row_buttons[id] = row


func _on_action() -> void:
	var inv := inventory()
	if inv == null or merchant == null or _selected_id == "":
		return
	var result: Dictionary
	if _buying:
		result = MerchantService.buy(inv, merchant, _selected_id, _qty)
	else:
		result = MerchantService.sell(inv, merchant, _selected_id, _qty)
	if bool(result.get("ok", false)):
		set_status("%s x%d done." % ["Bought" if _buying else "Sold", _qty], HudTheme.STAMINA)
	else:
		set_status(RpgUi.reason_text(String(result.get("reason", ""))), RpgUi.BAD)
	refresh()
