class_name HudEquipment
extends Control
## Equipment panel (top right): weapon with a rarity chip and damage modifier, armor with its points,
## medkits with the key hint. Pure drawing; the HUD pushes the data with set_data().

const ROW_HEIGHT: float = 24.0
const PAD: float = 10.0

var weapon_name: String = "None"
var weapon_color: Color = Color.WHITE
var weapon_mod: String = ""
var armor_name: String = "None"
var armor_points: String = ""
var armor_color: Color = HudTheme.ARMOR
var potions: int = 0

var _style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = HudTheme.panel_style()


func set_data(new_weapon: String, new_weapon_color: Color, new_mod: String, new_armor: String,
		new_armor_points: String, new_armor_color: Color, new_potions: int) -> void:
	weapon_name = new_weapon
	weapon_color = new_weapon_color
	weapon_mod = new_mod
	armor_name = new_armor
	armor_points = new_armor_points
	armor_color = new_armor_color
	potions = new_potions
	queue_redraw()


func _draw() -> void:
	if _style == null:
		return
	draw_style_box(_style, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	var font_size := HudTheme.FONT_SMALL + 1
	var inner := size.x - PAD * 2.0
	_row(font, font_size, 0, &"sword", weapon_color, weapon_name, weapon_mod, HudTheme.GOLD, inner)
	_row(font, font_size, 1, &"armor", armor_color, armor_name, armor_points, HudTheme.ARMOR.lightened(0.25), inner)
	_row(font, font_size, 2, &"medkit", HudTheme.HEALTH.lightened(0.2), "Medkits  x%d" % potions, "[R]", HudTheme.TEXT_DIM, inner)


func _row(font: Font, font_size: int, index: int, icon: StringName, chip: Color, text: String,
		right_text: String, right_color: Color, inner: float) -> void:
	var y := 6.0 + index * ROW_HEIGHT
	HudIcons.draw(self, icon, Rect2(PAD, y + 2.0, 18.0, 18.0), chip.lightened(0.2))
	draw_rect(Rect2(PAD + 24.0, y + 4.0, 4.0, 14.0), chip)  # rarity / type chip
	var baseline := y + 16.0
	draw_string_outline(font, Vector2(PAD + 36.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, inner - 36.0, font_size, 4, Color.BLACK)
	draw_string(font, Vector2(PAD + 36.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, inner - 36.0, font_size, HudTheme.TEXT)
	if right_text != "":
		draw_string_outline(font, Vector2(PAD, baseline), right_text, HORIZONTAL_ALIGNMENT_RIGHT, inner, font_size, 4, Color.BLACK)
		draw_string(font, Vector2(PAD, baseline), right_text, HORIZONTAL_ALIGNMENT_RIGHT, inner, font_size, right_color)
