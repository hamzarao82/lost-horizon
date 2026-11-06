class_name RpgUi
extends RefCounted
## Shared widgets and formatting for the RPG screens. Presentation only: no gameplay decisions here.

const TOUCH_HEIGHT: float = 56.0
const STAT_LABELS: Dictionary = {
	"damage_mult": "Damage",
	"attack_speed": "Attack speed",
	"armor_points": "Armor points",
	"damage_reduction": "Damage reduction",
	"max_health": "Max health",
	"move_speed_mult": "Move speed",
}
const STAT_ORDER: Array[String] = [
	"damage_mult", "attack_speed", "armor_points", "damage_reduction", "max_health", "move_speed_mult",
]
const GOOD: Color = Color(0.45, 0.9, 0.5)
const BAD: Color = Color(0.95, 0.4, 0.4)

static var _icons: Dictionary = {}  # item_id -> Texture2D (or null when the item has no icon)


## Icon texture for an item, loaded once.
static func icon_for(item: ItemData) -> Texture2D:
	if item == null:
		return null
	var key := String(item.item_id)
	if not _icons.has(key):
		_icons[key] = item.icon()
	return _icons[key]


static func icon_rect(item: ItemData, size: float = 40.0) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = icon_for(item)
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func label(text: String, size: int = HudTheme.FONT_BODY, color: Color = HudTheme.TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HudTheme.style_label(node, size, 3, color)
	return node


## Touch-sized button (at least 56 px tall).
static func button(text: String, callback: Callable, min_width: float = 0.0) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size = Vector2(min_width, TOUCH_HEIGHT)
	node.pressed.connect(callback)
	return node


static func rarity_color(item: ItemData) -> Color:
	return RarityTable.color(int(item.rarity)) if item else HudTheme.TEXT


static func rarity_name(item: ItemData) -> String:
	return RarityTable.rarity_name(int(item.rarity)) if item else ""


## Display text of one stat value, e.g. "x1.25", "+8%", "+10".
static func format_stat(key: String, value: float) -> String:
	match key:
		"damage_mult", "attack_speed", "move_speed_mult":
			return "x%.2f" % value
		"damage_reduction":
			return "%d%%" % roundi(value * 100.0)
		"armor_points", "max_health":
			return "%d" % roundi(value)
	return "%.2f" % value


## Signed difference text, e.g. "+0.25", "-5%".
static func format_delta(key: String, delta: float) -> String:
	var sign_text := "+" if delta > 0.0 else ""
	match key:
		"damage_reduction":
			return "%s%d%%" % [sign_text, roundi(delta * 100.0)]
		"armor_points", "max_health":
			return "%s%d" % [sign_text, roundi(delta)]
	return "%s%.2f" % [sign_text, delta]


## Stats worth showing for an item: those that differ from the neutral value.
static func visible_stat_keys(stats: Dictionary) -> Array[String]:
	var neutral := UpgradeService.empty_stats()
	var out: Array[String] = []
	for key in STAT_ORDER:
		if not stats.has(key):
			continue
		if not is_equal_approx(float(stats[key]), float(neutral[key])):
			out.append(key)
	return out


static func clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


## Human text for a failed action reason from Inventory/UpgradeService/CraftingBook/MerchantService.
static func reason_text(reason: String) -> String:
	match reason:
		"protected": return "Quest and unique items cannot be dropped or sold."
		"not_owned": return "You do not have that item."
		"not_enough": return "Not enough of that item."
		"missing_materials": return "Missing materials."
		"not_enough_currency": return "Not enough credits."
		"max_level": return "Already at the maximum level."
		"no_room": return "Your bag is full."
		"already_claimed": return "You already have this unique item."
		"cooldown": return "Still recharging."
		"dead": return "You cannot do that now."
		"unavailable": return "Nothing to do right now."
		"not_usable": return "This item cannot be used."
		"already_equipped": return "Already equipped."
		"sold_out": return "Sold out."
		"": return ""
	return reason.replace("_", " ").capitalize() + "."
