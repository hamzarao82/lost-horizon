class_name HudTeleport
extends Control
## Teleport readout: swirl icon, two charge pips and the recharge time. The HUD feeds it from the
## player's TeleportAbility (read-only); drawing only, redrawn when the state changes.

const WIDTH: float = 232.0

var charges: int = 2
var maximum: int = 2
var seconds_left: float = 0.0

var _style: StyleBoxFlat
var shake_offset: float = 0.0   # the HUD adds this to the widget x each frame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = HudTheme.panel_style(HudTheme.PANEL_BG, 14)


func set_state(new_charges: int, new_maximum: int, new_seconds_left: float) -> void:
	if new_charges == charges and new_maximum == maximum and is_equal_approx(new_seconds_left, seconds_left):
		return
	charges = new_charges
	maximum = maxi(new_maximum, 1)
	seconds_left = new_seconds_left
	queue_redraw()


## A denied use (no charge): nudge the readout sideways.
func deny() -> void:
	var tween := create_tween()
	for offset in [6.0, -6.0, 4.0, 0.0]:
		tween.tween_property(self, "shake_offset", offset, 0.04)


func time_text() -> String:
	if charges >= maximum:
		return "READY"
	var total := ceili(seconds_left)
	return "%02d:%02d" % [total / 60, total % 60]


func _draw() -> void:
	if _style == null:
		return
	var rect := Rect2(0.0, 0.0, minf(size.x, WIDTH), size.y)
	draw_style_box(_style, rect)
	var dim := charges <= 0
	var tint := HudTheme.TELEPORT if not dim else Color(HudTheme.TELEPORT, 0.45)
	HudIcons.draw(self, &"swirl", Rect2(6.0, 4.0, size.y - 8.0, size.y - 8.0), tint)
	var pip_y := size.y * 0.5
	for i in maximum:
		var center := Vector2(size.y + 12.0 + i * 22.0, pip_y)
		if i < charges:
			draw_circle(center, 7.0, HudTheme.TELEPORT)
			draw_arc(center, 7.0, 0.0, TAU, 16, Color.WHITE, 1.5)
		else:
			draw_arc(center, 7.0, 0.0, TAU, 16, Color(HudTheme.TELEPORT, 0.6), 2.0)
	var font := ThemeDB.fallback_font
	var label := "%s  [T]" % time_text() if charges < maximum else "READY  [T]"
	var baseline := size.y * 0.5 + 6.0
	var x := size.y + 12.0 + maximum * 22.0 + 4.0
	var width := rect.size.x - x - 8.0
	draw_string_outline(font, Vector2(x, baseline), label, HORIZONTAL_ALIGNMENT_RIGHT, width, HudTheme.FONT_SMALL + 1, 4, Color.BLACK)
	draw_string(font, Vector2(x, baseline), label, HORIZONTAL_ALIGNMENT_RIGHT, width, HudTheme.FONT_SMALL + 1,
			HudTheme.TEXT if not dim else HudTheme.TEXT_DIM)
