class_name HudTheme
extends RefCounted
## One look for every HUD and menu widget: colours, font sizes, panel/button styles and a shared Theme.
## Presentation only; no widget here knows anything about gameplay.

const TEXT: Color = Color(0.96, 0.97, 1.0)
const TEXT_DIM: Color = Color(0.72, 0.78, 0.88)
const HEALTH: Color = Color(0.86, 0.2, 0.22)
const ARMOR: Color = Color(0.35, 0.65, 1.0)
const STAMINA: Color = Color(0.3, 0.8, 0.4)
const GOLD: Color = Color(0.97, 0.85, 0.35)
const BOSS: Color = Color(0.74, 0.1, 0.14)
const TELEPORT: Color = Color(0.45, 0.9, 1.0)
const PANEL_BG: Color = Color(0.04, 0.06, 0.09, 0.62)
const PANEL_EDGE: Color = Color(1.0, 1.0, 1.0, 0.16)
const BAR_BACK: Color = Color(0.02, 0.03, 0.05, 0.7)

const FONT_SMALL: int = 15
const FONT_BODY: int = 18
const FONT_TITLE: int = 22
const FONT_BANNER: int = 30
const OUTLINE: int = 4
const CORNER: int = 10

static var _theme: Theme


## Rounded translucent panel used behind text clusters (equipment, tracker, subtitles, pills).
static func panel_style(bg: Color = PANEL_BG, radius: int = CORNER, border: int = 1,
		edge: Color = PANEL_EDGE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(border)
	style.border_color = edge
	style.anti_aliasing = true
	return style


static func style_label(label: Label, size: int = FONT_BODY, outline: int = OUTLINE, color: Color = TEXT) -> void:
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)


## The shared Theme (cached): labels get an outline, buttons and panels get the rounded dark style.
## Touch-friendly: buttons keep generous content margins.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	_theme.set_default_font_size(FONT_BODY)
	_theme.set_color("font_color", "Label", TEXT)
	_theme.set_color("font_outline_color", "Label", Color.BLACK)
	_theme.set_constant("outline_size", "Label", OUTLINE)

	var normal := panel_style(Color(0.1, 0.13, 0.18, 0.9), 12, 2, Color(1, 1, 1, 0.2))
	var hover := panel_style(Color(0.16, 0.2, 0.28, 0.95), 12, 2, Color(GOLD, 0.7))
	var pressed := panel_style(Color(0.22, 0.26, 0.34, 1.0), 12, 2, GOLD)
	var focus := panel_style(Color(0.0, 0.0, 0.0, 0.0), 12, 3, GOLD)
	var disabled := panel_style(Color(0.08, 0.1, 0.13, 0.7), 12, 2, Color(1, 1, 1, 0.08))
	for style in [normal, hover, pressed, disabled]:
		(style as StyleBoxFlat).content_margin_left = 16.0
		(style as StyleBoxFlat).content_margin_right = 16.0
		(style as StyleBoxFlat).content_margin_top = 8.0
		(style as StyleBoxFlat).content_margin_bottom = 8.0
	_theme.set_stylebox("normal", "Button", normal)
	_theme.set_stylebox("hover", "Button", hover)
	_theme.set_stylebox("pressed", "Button", pressed)
	_theme.set_stylebox("focus", "Button", focus)
	_theme.set_stylebox("disabled", "Button", disabled)
	_theme.set_color("font_color", "Button", TEXT)
	_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_theme.set_color("font_pressed_color", "Button", GOLD)
	_theme.set_color("font_disabled_color", "Button", Color(TEXT_DIM, 0.5))
	_theme.set_color("font_outline_color", "Button", Color.BLACK)
	_theme.set_constant("outline_size", "Button", 3)

	_theme.set_stylebox("panel", "PanelContainer", panel_style(Color(0.05, 0.07, 0.1, 0.94), 16, 2, Color(1, 1, 1, 0.18)))
	return _theme
