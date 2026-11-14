class_name DamageDirection
extends Control
## Full-screen cues about the player: a red wedge at the screen edge pointing toward whoever just hit, a pulsing
## red frame while health is low, and the armor-break sound. Purely visual; it never blocks input.

const WEDGE_SECONDS: float = 0.9
const MAX_WEDGES: int = 4
const LOW_HEALTH_FRACTION: float = 0.25
const FRAME_WIDTH: float = 26.0

var _wedges: Array[Dictionary] = []  # {angle, life}; angle 0 = straight up the screen, clockwise
var _low: bool = false
var _armor_last: float = 0.0
var _pulse: float = 0.0
var armor_breaks: int = 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Screen angle (radians, 0 = up, clockwise) of an attacker, from the camera's heading only.
static func screen_angle(camera_basis: Basis, player_pos: Vector3, from_pos: Vector3) -> float:
	var offset := from_pos - player_pos
	var dir := ObjectivePointer.screen_direction(camera_basis, Vector2(offset.x, offset.z))
	if dir.length() < 0.001:
		return PI  # on top of the player: show it behind
	return atan2(dir.x, -dir.y)


static func is_low_health(current: float, maximum: float) -> bool:
	return maximum > 0.0 and current > 0.0 and current / maximum <= LOW_HEALTH_FRACTION


func on_hit(player_pos: Vector3, from_pos: Vector3) -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var basis := camera.global_transform.basis if camera != null else Basis.IDENTITY
	add_wedge(screen_angle(basis, player_pos, from_pos))


func add_wedge(angle: float) -> void:
	_wedges.append({"angle": angle, "life": WEDGE_SECONDS})
	while _wedges.size() > MAX_WEDGES:
		_wedges.pop_front()
	queue_redraw()


func wedge_count() -> int:
	return _wedges.size()


func set_health(current: float, maximum: float) -> void:
	_low = is_low_health(current, maximum)
	queue_redraw()


func low_health_active() -> bool:
	return _low


## Armor reaching zero from a positive value plays the break cue once.
func on_armor_changed(current: float, _maximum: float) -> void:
	if _armor_last > 0.0 and current <= 0.0:
		armor_breaks += 1
		var audio := get_node_or_null("/root/AudioManager")
		if audio != null:
			audio.play(&"armor_break", -2.0)
	_armor_last = current


func advance(delta: float) -> void:
	_pulse += delta * 5.0
	for wedge in _wedges:
		wedge["life"] = float(wedge["life"]) - delta
	var before := _wedges.size()
	_wedges = _wedges.filter(func(w: Dictionary) -> bool: return float(w["life"]) > 0.0)
	if before != _wedges.size() or not _wedges.is_empty() or _low:
		queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.4
	for wedge in _wedges:
		var alpha := clampf(float(wedge["life"]) / WEDGE_SECONDS, 0.0, 1.0)
		var angle := float(wedge["angle"]) - PI * 0.5  # draw_arc measures from +x
		draw_arc(center, radius, angle - 0.3, angle + 0.3, 12, Color(0.9, 0.1, 0.1, 0.8 * alpha), 14.0, true)
	if _low:
		var a := 0.22 + 0.12 * sin(_pulse)
		var c := Color(0.8, 0.0, 0.0, a)
		draw_rect(Rect2(0, 0, size.x, FRAME_WIDTH), c)
		draw_rect(Rect2(0, size.y - FRAME_WIDTH, size.x, FRAME_WIDTH), c)
		draw_rect(Rect2(0, 0, FRAME_WIDTH, size.y), c)
		draw_rect(Rect2(size.x - FRAME_WIDTH, 0, FRAME_WIDTH, size.y), c)
