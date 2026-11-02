class_name HudBar
extends Control
## Rounded HUD bar with an optional icon and "current/max" text. Same property names as ProgressBar
## (max_value, value) so the HUD logic did not change. The fill eases toward the value and a lighter
## "ghost" segment shows the recent loss before it drains. Redraws only while something is moving.

const SMOOTH_RATE: float = 14.0
const GHOST_RATE: float = 3.5
const GHOST_DELAY: float = 0.35
const SETTLE: float = 0.05

@export var fill_color: Color = HudTheme.HEALTH: set = _set_fill_color
@export var icon: StringName = &""
@export var show_text: bool = true
@export var font_size: int = 14

var max_value: float = 100.0: set = _set_max_value
var value: float = 100.0: set = _set_value

var _shown: float = 100.0
var _ghost: float = 100.0
var _ghost_wait: float = 0.0
var _primed: bool = false
var _back_style: StyleBoxFlat
var _fill_style: StyleBoxFlat
var _ghost_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back_style = HudTheme.panel_style(HudTheme.BAR_BACK, 6, 1, Color(1, 1, 1, 0.22))
	_fill_style = HudTheme.panel_style(fill_color, 5, 0)
	_ghost_style = HudTheme.panel_style(Color(fill_color.lightened(0.55), 0.55), 5, 0)
	set_process(false)


func _set_fill_color(color: Color) -> void:
	fill_color = color
	if _fill_style != null:
		_fill_style.bg_color = color
		_ghost_style.bg_color = Color(color.lightened(0.55), 0.55)
	queue_redraw()


func _set_max_value(new_max: float) -> void:
	max_value = maxf(new_max, 0.001)
	queue_redraw()


func _set_value(new_value: float) -> void:
	value = clampf(new_value, 0.0, max_value)
	if not _primed:  # the first value is the starting state: no animation from zero
		_primed = true
		snap()
		return
	if value < _ghost - SETTLE and _ghost_wait <= 0.0:
		_ghost_wait = GHOST_DELAY
	set_process(true)


## Jump straight to the current value (no easing, no ghost).
func snap() -> void:
	_shown = value
	_ghost = value
	_ghost_wait = 0.0
	set_process(false)
	queue_redraw()


func displayed_value() -> float:
	return _shown


func _process(delta: float) -> void:
	_shown = lerpf(_shown, value, 1.0 - exp(-SMOOTH_RATE * delta))
	if absf(_shown - value) < SETTLE:
		_shown = value
	if _ghost < _shown:
		_ghost = _shown
	elif _ghost > _shown:
		if _ghost_wait > 0.0:
			_ghost_wait -= delta
		else:
			_ghost = lerpf(_ghost, _shown, 1.0 - exp(-GHOST_RATE * delta))
			if _ghost - _shown < SETTLE:
				_ghost = _shown
	queue_redraw()
	if _shown == value and _ghost == _shown:
		set_process(false)


func _draw() -> void:
	if _back_style == null:
		return
	draw_style_box(_back_style, Rect2(Vector2.ZERO, size))
	var pad := 2.0
	var icon_w := size.y if icon != &"" else 0.0
	var track := Rect2(icon_w + pad, pad, size.x - icon_w - pad * 2.0, size.y - pad * 2.0)
	if track.size.x <= 2.0 or track.size.y <= 1.0:
		return
	var ghost_w := track.size.x * clampf(_ghost / max_value, 0.0, 1.0)
	if ghost_w > track.size.y and _ghost > _shown + SETTLE:
		draw_style_box(_ghost_style, Rect2(track.position, Vector2(ghost_w, track.size.y)))
	var fill_w := track.size.x * clampf(_shown / max_value, 0.0, 1.0)
	if fill_w > 1.0:
		draw_style_box(_fill_style, Rect2(track.position, Vector2(maxf(fill_w, minf(track.size.y, 6.0)), track.size.y)))
	if icon != &"":
		HudIcons.draw(self, icon, Rect2(3.0, 2.0, size.y - 4.0, size.y - 4.0), fill_color.lightened(0.35))
	if show_text and size.y >= 12.0:
		var font := ThemeDB.fallback_font
		var text := "%d/%d" % [roundi(value), roundi(max_value)]
		var baseline := size.y * 0.5 + font_size * 0.36
		draw_string_outline(font, Vector2(track.position.x, baseline), text, HORIZONTAL_ALIGNMENT_RIGHT,
				track.size.x - 6.0, font_size, 4, Color.BLACK)
		draw_string(font, Vector2(track.position.x, baseline), text, HORIZONTAL_ALIGNMENT_RIGHT,
				track.size.x - 6.0, font_size, HudTheme.TEXT)
