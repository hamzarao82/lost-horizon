class_name Hud
extends CanvasLayer
## Player bars, wave status, equipment panel, pickup toasts, and end-of-arena messages.

const BANNER_SECONDS: float = 2.0
const TOAST_SECONDS: float = 2.5

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _message: Label
var _wave_label: Label
var _banner: Label
var _equipment: Label
var _toast: Label
var _check_time: float = 0.0
var _banner_time: float = 0.0
var _toast_time: float = 0.0
var _player: Player
var _waves: WaveManager
var _boss: Enemy
var _boss_bar: ProgressBar
var _boss_name: Label


func _ready() -> void:
	layer = 50
	_health_bar = _make_bar(Vector2(16, 90), Color(0.8, 0.15, 0.15))
	_stamina_bar = _make_bar(Vector2(16, 112), Color(0.2, 0.75, 0.3))
	_stamina_bar.custom_minimum_size.y = 10
	_stamina_bar.size.y = 10

	_message = _make_label(48, 8)
	_message.visible = false
	_banner = _make_label(40, 8)
	_banner.visible = false
	_wave_label = _make_label(20, 4)
	_toast = _make_label(22, 4)
	_toast.visible = false
	_equipment = _make_label(18, 4)
	_equipment.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_boss_name = _make_label(20, 4)
	_boss_name.visible = false
	_boss_bar = _make_bar(Vector2.ZERO, Color(0.7, 0.1, 0.12))
	_boss_bar.custom_minimum_size = Vector2(520, 20)
	_boss_bar.size = _boss_bar.custom_minimum_size
	_boss_bar.visible = false

	if not TouchControls.is_mobile_platform():
		var hint := Label.new()
		hint.text = "WASD move | Shift sprint | Space jump | Ctrl or C dodge | LMB light | RMB heavy | R medkit | F3 stats"
		hint.position = Vector2(16, 690)
		hint.add_theme_color_override("font_outline_color", Color.BLACK)
		hint.add_theme_constant_override("outline_size", 4)
		add_child(hint)

	_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_player.health.changed.connect(_on_health_changed)
		_player.stamina_changed.connect(_on_stamina_changed)
		_on_health_changed(_player.health.health, _player.health.max_health)  # may be restored from a save
		_on_stamina_changed(_player.max_stamina, _player.max_stamina)
		if _player.inventory:
			_player.inventory.changed.connect(_refresh_equipment)
			_player.inventory.item_collected.connect(_on_item_collected)
		_refresh_equipment()

	_waves = get_tree().get_first_node_in_group("wave_manager") as WaveManager
	if _waves:
		_waves.wave_started.connect(_on_wave_started)
	_refresh_wave_label()

	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager:
		save_manager.saved.connect(_on_saved)
		var notice: String = save_manager.consume_notice()
		if not notice.is_empty():
			_show_toast(notice, Color(0.5, 0.85, 1.0))


func _process(delta: float) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_wave_label.position = Vector2((viewport_size.x - _wave_label.size.x) * 0.5, 12)
	_equipment.position = Vector2(viewport_size.x - _equipment.size.x - 16, 12)
	_toast.position = Vector2((viewport_size.x - _toast.size.x) * 0.5, viewport_size.y - 110)
	_banner.position = Vector2((viewport_size.x - _banner.size.x) * 0.5, viewport_size.y * 0.25)

	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time / 0.5, 0.0, 1.0)
		_banner.visible = _banner_time > 0.0
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
		_toast.visible = _toast_time > 0.0

	_update_boss_bar(viewport_size)

	_check_time += delta
	if _check_time < 0.25:
		return
	_check_time = 0.0
	_refresh_wave_label()
	if _boss == null or not is_instance_valid(_boss) or _boss.is_dead():
		_boss = get_tree().get_first_node_in_group("boss") as Enemy
	if _player and _player.is_dead():
		_show_message("YOU DIED", Color(0.9, 0.15, 0.15))
	elif _arena_cleared():
		_show_message("ARENA CLEARED", Color(0.95, 0.85, 0.3))


func _update_boss_bar(viewport_size: Vector2) -> void:
	var show_boss := _boss != null and is_instance_valid(_boss) and not _boss.is_dead()
	_boss_bar.visible = show_boss
	_boss_name.visible = show_boss
	if not show_boss:
		return
	var health := _boss.get_node("HealthComponent") as HealthComponent
	_boss_bar.max_value = health.max_health
	_boss_bar.value = health.health
	_boss_name.text = _boss.display_name
	_boss_bar.position = Vector2((viewport_size.x - _boss_bar.size.x) * 0.5, 66)
	_boss_name.position = Vector2((viewport_size.x - _boss_name.size.x) * 0.5, 40)


func _arena_cleared() -> bool:
	if _waves and is_instance_valid(_waves):
		return _waves.is_finished()
	return get_tree().get_nodes_in_group("enemies").is_empty()


func _make_label(font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	add_child(label)
	return label


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


func _on_wave_started(index: int, _total: int) -> void:
	_banner.text = "WAVE %d" % index
	_banner.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	_banner.modulate.a = 1.0
	_banner.visible = true
	_banner_time = BANNER_SECONDS
	_refresh_wave_label()


func _refresh_wave_label() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var wave := 0
	var total := 4
	if _waves and is_instance_valid(_waves):
		wave = _waves.current_wave
		total = _waves.total_waves()
	_wave_label.text = "Wave %d/%d  Enemies: %d" % [wave, total, enemies]


func _refresh_equipment() -> void:
	if _player == null or _player.inventory == null:
		return
	var inv := _player.inventory
	var weapon_text := inv.weapon.summary() if inv.weapon else "None"
	var armor_text := inv.armor.summary() if inv.armor else "None"
	_equipment.text = "Weapon: %s\nArmor: %s\nMedkits: %d  [R]" % [weapon_text, armor_text, inv.potions]


func _on_item_collected(item: ItemData, kept: bool) -> void:
	_show_toast(("Picked up %s" if kept else "%s (not an upgrade)") % item.display_name, item.color())


func _on_saved(_reason: String) -> void:
	_show_toast("Progress saved", Color(0.6, 0.95, 0.6))


func _show_toast(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_time = TOAST_SECONDS


func _show_message(text: String, color: Color) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = true
	_message.position = (get_viewport().get_visible_rect().size - _message.size) * 0.5
