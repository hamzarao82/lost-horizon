class_name Hud
extends CanvasLayer
## Player health / stamina bars, controls hint, and end-of-arena messages.

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _message: Label
var _check_time: float = 0.0
var _player: Player


func _ready() -> void:
	layer = 50
	_health_bar = _make_bar(Vector2(16, 90), Color(0.8, 0.15, 0.15))
	_stamina_bar = _make_bar(Vector2(16, 112), Color(0.2, 0.75, 0.3))
	_stamina_bar.custom_minimum_size.y = 10
	_stamina_bar.size.y = 10

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 48)
	_message.add_theme_color_override("font_outline_color", Color.BLACK)
	_message.add_theme_constant_override("outline_size", 8)
	_message.visible = false
	add_child(_message)

	if not TouchControls.is_mobile_platform():
		var hint := Label.new()
		hint.text = "WASD move | Shift sprint | Space jump | Ctrl or C dodge | LMB light | RMB heavy | F3 stats"
		hint.position = Vector2(16, 690)
		hint.add_theme_color_override("font_outline_color", Color.BLACK)
		hint.add_theme_constant_override("outline_size", 4)
		add_child(hint)

	_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_player.health.changed.connect(_on_health_changed)
		_player.stamina_changed.connect(_on_stamina_changed)
		_on_health_changed(_player.health.max_health, _player.health.max_health)
		_on_stamina_changed(_player.max_stamina, _player.max_stamina)


func _process(delta: float) -> void:
	_check_time += delta
	if _check_time < 0.25:
		return
	_check_time = 0.0
	if _player and _player.is_dead():
		_show_message("YOU DIED", Color(0.9, 0.15, 0.15))
	elif get_tree().get_nodes_in_group("enemies").is_empty():
		_show_message("ARENA CLEARED", Color(0.95, 0.85, 0.3))


func _make_bar(pos: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.custom_minimum_size = Vector2(240, 16)
	bar.size = bar.custom_minimum_size
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	add_child(bar)
	return bar


func _on_health_changed(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current


func _show_message(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = true
	_message.position = (get_viewport().get_visible_rect().size - _message.size) * 0.5
