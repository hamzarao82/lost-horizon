class_name MenuEmbers
extends Control
## Cheap animated background for the title menu: a few dozen embers drifting upward and one slow
## scan band, drawn by a single Control that redraws at most 30 times a second.

const COUNT: int = 36
const STEP: float = 1.0 / 30.0
const EMBER_COLOR: Color = Color(0.91, 0.6, 0.2)
const SCAN_COLOR: Color = Color(0.47, 0.67, 0.78, 0.05)
const SCAN_HEIGHT: float = 90.0
const SCAN_PERIOD: float = 6.0

var _embers: Array[Dictionary] = []
var _acc: float = 0.0
var _clock: float = 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 7
	for i in COUNT:
		_embers.append(_new_ember(true))


func _new_ember(scatter: bool) -> Dictionary:
	return {
		"x": _rng.randf(),
		"y": _rng.randf() if scatter else 1.02,
		"speed": _rng.randf_range(0.03, 0.09),
		"drift": _rng.randf_range(-0.01, 0.01),
		"size": _rng.randf_range(1.5, 3.5),
		"phase": _rng.randf() * TAU,
	}


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_acc += delta
	if _acc < STEP:
		return
	var dt := _acc
	_acc = 0.0
	_clock += dt
	for e in _embers:
		e["y"] -= float(e["speed"]) * dt
		e["x"] += float(e["drift"]) * dt
		if float(e["y"]) < -0.02:
			e.assign(_new_ember(false))
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	for e in _embers:
		var y := float(e["y"])
		var fade := clampf(sin(float(e["phase"]) + _clock * 1.4) * 0.5 + 0.5, 0.0, 1.0) * clampf(y * 3.0, 0.0, 1.0)
		var c := EMBER_COLOR
		c.a = 0.75 * fade
		draw_circle(Vector2(float(e["x"]) * w, y * h), float(e["size"]), c)
	var band_y := fposmod(_clock / SCAN_PERIOD, 1.0) * (h + SCAN_HEIGHT) - SCAN_HEIGHT
	draw_rect(Rect2(0.0, band_y, w, SCAN_HEIGHT), SCAN_COLOR)
