class_name RpgNotifications
extends CanvasLayer
## Loot toasts (rarity colour, extra emphasis for rare and better), a level-up banner and credit changes.
## Purely signal driven (Inventory.item_collected / currency_changed, Progression.level_up): no per-frame work.

const MAX_TOASTS: int = 4
const TOAST_SECONDS: float = 3.0
const BANNER_SECONDS: float = 3.5
const TOAST_WIDTH: float = 320.0
const MIN_XP_TOAST: int = 25

var shown_texts: Array[String] = []  # every notification text, in order (tests and logs)
var _toasts: VBoxContainer
var _banner: Label
var _hooked_inventories: Array[Inventory] = []
var _last_currency: Dictionary = {}  # instance id -> last known credits
var _banner_tween: Tween


func _init() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 1.0
	_toasts.anchor_right = 1.0
	_toasts.offset_left = -TOAST_WIDTH - 16.0
	_toasts.offset_right = -16.0
	_toasts.offset_top = 108.0
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.theme = HudTheme.theme()
	add_child(_toasts)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.offset_top = 150.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HudTheme.style_label(_banner, 40, 6, HudTheme.GOLD)
	_banner.modulate.a = 0.0
	add_child(_banner)

	get_tree().node_added.connect(_on_node_added)
	for node in get_tree().root.find_children("*", "Inventory", true, false):
		hook_inventory(node as Inventory)
	var progression := get_node_or_null("/root/Progression")
	if progression:
		progression.level_up.connect(notify_level)
		progression.xp_gained.connect(_on_xp_gained)


func _on_node_added(node: Node) -> void:
	if node is Inventory:
		hook_inventory.call_deferred(node as Inventory)


func hook_inventory(inventory: Inventory) -> void:
	if inventory == null or not is_instance_valid(inventory) or _hooked_inventories.has(inventory):
		return
	_hooked_inventories.append(inventory)
	_last_currency[inventory.get_instance_id()] = inventory.currency
	inventory.item_collected.connect(_on_item_collected)
	inventory.currency_changed.connect(func(amount: int) -> void: _on_currency(inventory, amount))


func toast_count() -> int:
	return _toasts.get_child_count() if _toasts else 0


func banner_text() -> String:
	return _banner.text if _banner else ""


func _on_item_collected(item: ItemData, kept: bool) -> void:
	if item == null:
		return
	if not kept:
		_toast("Bag full: could not take %s" % item.display_name, RpgUi.BAD, false)
		return
	notify_loot(item)


func notify_loot(item: ItemData, quantity: int = 1) -> void:
	var text := item.display_name if quantity <= 1 else "%s x%d" % [item.display_name, quantity]
	var rarity := int(item.rarity)
	var prefix := ""
	if rarity >= ItemData.Rarity.LEGENDARY:
		prefix = "LEGENDARY  "
	elif rarity >= ItemData.Rarity.EPIC:
		prefix = "EPIC  "
	elif rarity >= ItemData.Rarity.RARE:
		prefix = "RARE  "
	_toast(prefix + text, RpgUi.rarity_color(item), rarity >= ItemData.Rarity.RARE, RpgUi.icon_for(item))


func notify_level(level: int) -> void:
	var text := "LEVEL %d" % level
	shown_texts.append(text)
	if _banner == null:
		return
	_banner.text = text
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.modulate.a = 1.0
	_banner_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_banner_tween.tween_interval(BANNER_SECONDS * 0.6)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, BANNER_SECONDS * 0.4)


func _on_xp_gained(amount: int, source: String) -> void:
	if amount >= MIN_XP_TOAST:
		_toast("+%d XP  %s" % [amount, source], HudTheme.TEXT_DIM, false)


func _on_currency(inventory: Inventory, amount: int) -> void:
	var key := inventory.get_instance_id()
	var delta := amount - int(_last_currency.get(key, amount))
	_last_currency[key] = amount
	if delta != 0:
		notify_currency(delta)


func notify_currency(delta: int) -> void:
	_toast("%s%d credits" % ["+" if delta > 0 else "", delta], HudTheme.GOLD if delta > 0 else HudTheme.TEXT_DIM, false)


func _toast(text: String, color: Color, emphasis: bool, icon: Texture2D = null) -> void:
	shown_texts.append(text)
	if _toasts == null:
		return
	while _toasts.get_child_count() >= MAX_TOASTS:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(TOAST_WIDTH, 0)
	var style := HudTheme.panel_style(HudTheme.PANEL_BG, 10, 2 if emphasis else 1, color if emphasis else HudTheme.PANEL_EDGE)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	if icon != null:
		var rect := TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = Vector2(32, 32)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(rect)
	var label := RpgUi.label(text, HudTheme.FONT_BODY, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	_toasts.add_child(panel)
	var tween := panel.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(TOAST_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)
