class_name TelegraphIndicator
extends Control
## A thin strip under the boss bar that fills while the boss is winding up an attack, so the player can read
## the telegraph at a glance. It only reads the boss; nothing in the combat code knows it exists.

const COLOR_BACK: Color = Color(0.1, 0.05, 0.05, 0.7)
const COLOR_FILL: Color = Color(1.0, 0.55, 0.15)
const COLOR_LATE: Color = Color(1.0, 0.15, 0.1)

var progress_value: float = -1.0  ## -1 = no telegraph; otherwise 0..1 through the windup
var _pulse: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## 0..1 through an attack's startup when `enemy` is telegraphing, else -1. Works on the base melee swing, the
## ranged burst, and the boss states that keep their own phase counter (Director, Warden specials, Elite subjects).
## Progress is exact for the base swing and the Director; the others only report "winding up" (1.0).
static func telegraph_progress(enemy: Enemy) -> float:
	if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
		return -1.0
	if enemy.state == Enemy.State.RANGED_ATTACK:
		var brain: Variant = enemy.get("_ranged_brain")
		if brain != null and brain.is_telegraphing():
			return 1.0
		return -1.0
	if enemy.state != Enemy.State.ATTACK:
		return -1.0
	var swing: Variant = enemy.get("_swing")
	var startup: float = float(swing.startup_frames) if swing != null else 0.0
	var sp_phase: Variant = enemy.get("_sp_phase")
	var own_phase: bool = sp_phase != null
	if own_phase and enemy.get("_special") != null:  # Warden: a plain slam uses the base counter
		own_phase = enemy.get("_special") != &""
	if own_phase and enemy.get("_kind") != null:  # Director: its counter is a plain melee swing
		own_phase = enemy.get("_kind") != &"counter"
	if own_phase:
		if int(sp_phase) != 0:
			return -1.0
		var sp_frames: Variant = enemy.get("_sp_frames")
		if sp_frames != null and startup > 0.0:
			return clampf(float(sp_frames) / startup, 0.0, 1.0)
		return 1.0
	if swing == null or startup <= 0.0:
		return -1.0
	var frames: float = float(enemy.get("_attack_frames"))
	if frames >= startup:
		return -1.0  # the strike has started: the warning is over
	return clampf(frames / startup, 0.0, 1.0)


## Called each frame by the HUD with the current boss (or null) and the strip's rectangle.
func update_for(boss: Enemy, rect: Rect2, delta: float = 0.0) -> void:
	progress_value = telegraph_progress(boss) if boss != null else -1.0
	visible = progress_value >= 0.0
	position = rect.position
	size = rect.size
	_pulse += delta * 14.0
	if visible:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACK)
	var fill := COLOR_FILL.lerp(COLOR_LATE, progress_value)
	fill.a = 0.75 + 0.25 * sin(_pulse)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * progress_value, size.y)), fill)
