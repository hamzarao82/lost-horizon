class_name Interactor
extends Node
## Attached to the Player at runtime (by WorldFlow), so player.gd is untouched. Every 0.1 s it picks
## the nearest Interactable in range; it shows a prompt and triggers it on one press of `interact`.
## One press = one interaction: keyboard/gamepad arrive as events, touch as an action edge, and a
## 0.3 s cooldown plus a single combined trigger per physics tick stops a press counting twice.

const SCAN_SECONDS: float = 0.1
const COOLDOWN_SECONDS: float = 0.3
const MAX_HEIGHT_DIFF: float = 2.5

var player: Player
var target: Interactable

var _layer: CanvasLayer
var _label: Label
var _scan_left: float = 0.0
var _cooldown: float = 0.0
var _was_down: bool = false
var _event_press: bool = false


func _ready() -> void:
	player = get_parent() as Player
	_layer = CanvasLayer.new()
	_layer.layer = 49
	add_child(_layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_label.visible = false
	_layer.add_child(_label)


func _exit_tree() -> void:
	TouchControls.interact_available = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo():
		_event_press = true


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	var down := Input.is_action_pressed("interact")
	var pressed := _event_press or (down and not _was_down)
	_event_press = false
	_was_down = down

	if _blocked():
		_set_target(null)
		return
	_scan_left -= delta
	if _scan_left <= 0.0:
		_scan_left = SCAN_SECONDS
		_set_target(find_target())
	if pressed and target != null and _cooldown <= 0.0:
		_cooldown = COOLDOWN_SECONDS
		target.interact(player)
		_refresh_prompt()


## Nearest available Interactable within its own radius, or null.
func find_target() -> Interactable:
	if player == null:
		return null
	var best: Interactable = null
	var best_dist := INF
	var here := player.global_position
	for node in get_tree().get_nodes_in_group("interactables"):
		var item := node as Interactable
		if item == null or not item.is_available() or not item.is_inside_tree():
			continue
		var there := item.global_position
		if absf(there.y - here.y) > MAX_HEIGHT_DIFF:
			continue
		var dist := Vector2(there.x - here.x, there.z - here.z).length()
		if dist <= item.interact_radius and dist < best_dist:
			best_dist = dist
			best = item
	return best


func _blocked() -> bool:
	return player == null or not is_instance_valid(player) or player.is_dead() or get_tree().paused


func _set_target(new_target: Interactable) -> void:
	target = new_target
	TouchControls.interact_available = new_target != null
	_refresh_prompt()


func _refresh_prompt() -> void:
	if target == null or not is_instance_valid(target) or not target.is_available():
		_label.visible = false
		return
	var text := target.current_prompt()
	if not TouchControls.touch_active:
		text = "[E] " + text if target.can_interact() else text
	_label.text = text
	_label.visible = true
	var size := get_viewport().get_visible_rect().size
	_label.reset_size()
	_label.position = Hud.prompt_position(size, TouchControls.touch_active, _label.size)  # above the subtitle band
