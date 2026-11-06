class_name CraftingScreen
extends RpgScreen
## Recipe list with inputs (have / need), cost and a Craft button. CraftingBook validates and consumes
## atomically; this screen only shows its answer.

var _recipes: Array[Recipe] = []
var _selected: int = -1
var _list: VBoxContainer
var _info: VBoxContainer
var _craft_button: Button
var _hooked: Inventory
var _row_buttons: Array[Button] = []


func _init() -> void:
	super._init()
	title_text = "Crafting"


func recipe_count() -> int:
	return _recipes.size()


func selected_recipe() -> Recipe:
	return _recipes[_selected] if _selected >= 0 and _selected < _recipes.size() else null


func craft_button() -> Button:
	return _craft_button


func row_button(index: int) -> Button:
	return _row_buttons[index] if index >= 0 and index < _row_buttons.size() else null


func info_text() -> String:
	var parts: Array[String] = []
	for child in _info.get_children():
		if child is Label:
			parts.append((child as Label).text)
	return "\n".join(parts)


func select_recipe(index: int) -> void:
	_selected = index
	refresh()


func _build_content() -> void:
	_recipes = CraftingBook.load_recipes()
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.custom_minimum_size = Vector2(0, 240)
	split.add_theme_constant_override("separation", 12)
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
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)
	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(info_scroll)
	_info = VBoxContainer.new()
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.add_theme_constant_override("separation", 4)
	info_scroll.add_child(_info)
	_craft_button = RpgUi.button("Craft", _on_craft, 160.0)
	right.add_child(_craft_button)


func _connect_sources() -> void:
	var inv := inventory()
	if inv == null or inv == _hooked:
		return
	_hooked = inv
	inv.changed.connect(_on_inventory_changed)


func _focus_first() -> void:
	if _row_buttons.size() > 0:
		_row_buttons[maxi(_selected, 0)].grab_focus()
	else:
		super._focus_first()


func refresh() -> void:
	if _list == null:
		return
	var inv := inventory()
	RpgUi.clear(_list)
	RpgUi.clear(_info)
	_row_buttons.clear()
	for i in _recipes.size():
		var recipe := _recipes[i]
		var can := inv != null and bool(CraftingBook.check(inv, recipe)["ok"])
		var row := Button.new()
		row.text = recipe.display_name
		var output := CraftingBook.output_item(recipe)
		row.icon = RpgUi.icon_for(output)
		row.expand_icon = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(0, RpgUi.TOUCH_HEIGHT)
		row.add_theme_constant_override("icon_max_width", 40)
		row.add_theme_color_override("font_color", HudTheme.TEXT if can else HudTheme.TEXT_DIM)
		row.toggle_mode = true
		row.button_pressed = i == _selected
		var index := i
		row.pressed.connect(func() -> void: select_recipe(index))
		_list.add_child(row)
		_row_buttons.append(row)
	var recipe := selected_recipe()
	if recipe == null or inv == null:
		_info.add_child(RpgUi.label("Select a recipe.", HudTheme.FONT_BODY, HudTheme.TEXT_DIM))
		_craft_button.disabled = true
		return
	var output := CraftingBook.output_item(recipe)
	_info.add_child(RpgUi.label(recipe.display_name, HudTheme.FONT_TITLE, RpgUi.rarity_color(output)))
	_info.add_child(RpgUi.label(recipe.description, HudTheme.FONT_BODY))
	_info.add_child(RpgUi.label("Makes: %s x%d" % [output.display_name if output else recipe.output_id, recipe.output_count], HudTheme.FONT_BODY, HudTheme.TEXT))
	var needs := recipe.inputs()
	for id in needs.keys():
		var have := inv.count_of(String(id))
		var need := int(needs[id])
		var item := MerchantService.item_for(String(id))
		_info.add_child(RpgUi.label("%s: %d / %d" % [item.display_name if item else String(id), have, need],
				HudTheme.FONT_BODY, RpgUi.GOOD if have >= need else RpgUi.BAD))
	if recipe.currency_cost > 0:
		_info.add_child(RpgUi.label("Credits: %d / %d" % [inv.currency, recipe.currency_cost], HudTheme.FONT_BODY,
				RpgUi.GOOD if inv.currency >= recipe.currency_cost else RpgUi.BAD))
	var check := CraftingBook.check(inv, recipe)
	_craft_button.disabled = not bool(check["ok"])
	if not bool(check["ok"]):
		_info.add_child(RpgUi.label(RpgUi.reason_text(String(check["reason"])), HudTheme.FONT_SMALL, RpgUi.BAD))


func _on_craft() -> void:
	var inv := inventory()
	var recipe := selected_recipe()
	if inv == null or recipe == null:
		return
	var result := CraftingBook.craft(inv, recipe)
	if bool(result.get("ok", false)):
		set_status("Crafted %s." % recipe.display_name, HudTheme.STAMINA)
	else:
		set_status(RpgUi.reason_text(String(result.get("reason", ""))), RpgUi.BAD)
	refresh()
