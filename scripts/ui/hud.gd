class_name Hud
extends CanvasLayer
## Player bars, wave status, equipment panel, pickup toasts, and end-of-arena messages.

const BANNER_SECONDS: float = 2.0
const TOAST_SECONDS: float = 2.5

var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _armor_bar: ProgressBar
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
var _quests: Node
var _tracker_title: Label
var _tracker_objective: Label
var _subtitle: Label
var _caption_queue: Array[Dictionary] = []
var _subtitle_time: float = 0.0


func _ready() -> void:
	layer = 50
	_health_bar = _make_bar(Vector2(16, 90), Color(0.8, 0.15, 0.15))
	# Armor sits between health and stamina; it is hidden (the gap stays) until armor is equipped.
	_armor_bar = _make_bar(Vector2(16, 108), Color(0.3, 0.6, 1.0))
	_armor_bar.custom_minimum_size.y = 12
	_armor_bar.size.y = 12
	_armor_bar.visible = false
	_stamina_bar = _make_bar(Vector2(16, 124), Color(0.2, 0.75, 0.3))
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
		_player.health.armor_changed.connect(_on_armor_changed)
		_on_armor_changed(_player.health.armor, _player.health.max_armor)  # may be restored from a save
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

	_setup_story()


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
	_update_story(viewport_size, delta)

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


func _on_armor_changed(current: float, maximum: float) -> void:
	_armor_bar.visible = maximum > 0.0
	_armor_bar.max_value = maxf(maximum, 1.0)
	_armor_bar.value = current
	_refresh_equipment()  # the panel shows "current/max"


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
	if inv.armor and _player.health.max_armor > 0.0:
		_equipment.text = _equipment.text.replace("Armor: %s" % armor_text,
				"Armor: %s  %d/%d" % [armor_text, roundi(_player.health.armor), roundi(_player.health.max_armor)])


func _on_item_collected(item: ItemData, kept: bool) -> void:
	_show_toast(("Picked up %s" if kept else "%s (not an upgrade)") % item.display_name, item.color())


# --- story: quest tracker and subtitles (presentation only) -----------------

const SUBTITLE_FADE: float = 0.4
const SHORT_VIEWPORT_HEIGHT: float = 480.0
const TRACKER_MAX_WIDTH: float = 360.0
const TRACKER_TALL_Y: float = 205.0   # below the bars (90-134), teleport label (~150) and pause button (140-196)
const TRACKER_SHORT_Y: float = 46.0   # fallback for very short screens: top centre under the wave label
const TRACKER_SHORT_MIN_X: float = 290.0  # right of the bars and the teleport label
const SUBTITLE_MAX_WIDTH: float = 720.0
const SUBTITLE_BOTTOM_GAP: float = 120.0  # subtitle bottom edge sits this far above the screen bottom (toast is at 110)
const MAX_QUEUED_CAPTIONS: int = 8


func _setup_story() -> void:
	_tracker_title = _make_label(18, 4)
	_tracker_title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	_tracker_title.visible = false
	_tracker_objective = _make_label(16, 4)
	_tracker_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tracker_objective.max_lines_visible = 2  # long objectives never grow the tracker past two lines
	_tracker_objective.visible = false
	_subtitle = _make_label(22, 6)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.max_lines_visible = 3
	_subtitle.visible = false
	_quests = get_node_or_null("/root/QuestManager")
	if _quests == null:
		return
	_quests.tracker_changed.connect(_refresh_tracker)
	_quests.caption_requested.connect(show_caption)
	_quests.quest_started.connect(_on_quest_started)
	_quests.quest_completed.connect(_on_quest_completed)
	_refresh_tracker()


## Queue a subtitle line (radio and story captions). Lines show one after another.
func show_caption(text: String, seconds: float = 4.0) -> void:
	if _subtitle == null or text.is_empty():
		return
	if _caption_queue.size() >= MAX_QUEUED_CAPTIONS:
		_caption_queue.pop_front()
	_caption_queue.append({"text": text, "seconds": maxf(seconds, 1.0)})


func _refresh_tracker() -> void:
	if _quests == null or _tracker_title == null:
		return
	_tracker_title.text = _quests.tracker_title()
	_tracker_objective.text = _quests.tracker_objective()


func _on_quest_started(quest_id: StringName) -> void:
	var quest: QuestData = _quests.get_quest(quest_id)
	if quest:
		_show_toast("New quest: %s" % quest.title, Color(0.95, 0.85, 0.3))


func _on_quest_completed(quest_id: StringName) -> void:
	var quest: QuestData = _quests.get_quest(quest_id)
	if quest == null:
		return
	_banner.text = "QUEST COMPLETE"
	_banner.add_theme_color_override("font_color", Color(0.95, 0.85, 0.3))
	_banner.modulate.a = 1.0
	_banner.visible = true
	_banner_time = BANNER_SECONDS
	var reward := "" if quest.reward_text.is_empty() else "  Reward: %s" % quest.reward_text
	_show_toast("%s%s" % [quest.title, reward], Color(0.95, 0.85, 0.3))


## Places the tracker and the subtitle for a screen size and returns their rectangles.
## Tall screens: tracker in the left column below the existing widgets. Short screens (landscape
## phones): tracker at the top centre, subtitle under it. Public so the layout can be tested.
func layout_story(viewport_size: Vector2) -> Dictionary:
	var short := viewport_size.y < SHORT_VIEWPORT_HEIGHT
	var tracker_width := minf(TRACKER_MAX_WIDTH, viewport_size.x * (0.5 if short else 0.4))
	_tracker_title.custom_minimum_size.x = tracker_width
	_tracker_title.size.x = tracker_width
	_tracker_title.clip_text = true
	_tracker_objective.custom_minimum_size.x = tracker_width
	_tracker_objective.size.x = tracker_width
	_tracker_objective.size.y = 0.0
	var title_height := _tracker_title.get_combined_minimum_size().y
	var objective_height := _tracker_objective.get_combined_minimum_size().y if _tracker_objective.text != "" else 0.0
	var tracker_x := maxf((viewport_size.x - tracker_width) * 0.5, TRACKER_SHORT_MIN_X) if short else 16.0
	var tracker_y := TRACKER_SHORT_Y if short else TRACKER_TALL_Y
	_tracker_title.position = Vector2(tracker_x, tracker_y)
	_tracker_objective.position = Vector2(tracker_x, tracker_y + title_height)
	_tracker_objective.size.y = objective_height
	var tracker_rect := Rect2(tracker_x, tracker_y, tracker_width, title_height + objective_height)

	var subtitle_width := minf(SUBTITLE_MAX_WIDTH, viewport_size.x * 0.9)
	_subtitle.custom_minimum_size.x = subtitle_width
	_subtitle.size.x = subtitle_width
	_subtitle.size.y = 0.0
	var subtitle_height := _subtitle.get_combined_minimum_size().y
	_subtitle.size.y = subtitle_height
	var subtitle_x := (viewport_size.x - subtitle_width) * 0.5
	var subtitle_y := viewport_size.y - SUBTITLE_BOTTOM_GAP - subtitle_height
	if short:
		subtitle_y = tracker_rect.end.y + 8.0
	_subtitle.position = Vector2(subtitle_x, subtitle_y)
	return {
		"tracker": tracker_rect,
		"subtitle": Rect2(subtitle_x, subtitle_y, subtitle_width, subtitle_height),
	}


func _update_story(viewport_size: Vector2, delta: float) -> void:
	if _subtitle == null:
		return
	if _subtitle_time > 0.0:
		_subtitle_time -= delta
		_subtitle.modulate.a = clampf(_subtitle_time / SUBTITLE_FADE, 0.0, 1.0)
		if _subtitle_time <= 0.0:
			_subtitle.visible = false
	if _subtitle_time <= 0.0 and not _caption_queue.is_empty():
		var line: Dictionary = _caption_queue.pop_front()
		_subtitle.text = String(line["text"])
		_subtitle.modulate.a = 1.0
		_subtitle.visible = true
		_subtitle_time = float(line["seconds"])
	var has_quest := _tracker_title.text != ""
	var short := viewport_size.y < SHORT_VIEWPORT_HEIGHT
	var show_tracker := has_quest and not (short and _boss_bar.visible)  # the boss bar owns the top centre
	_tracker_title.visible = show_tracker
	_tracker_objective.visible = show_tracker and _tracker_objective.text != ""
	layout_story(viewport_size)


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
