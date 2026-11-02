class_name Hud
extends CanvasLayer
## Player bars, wave status, equipment panel, pickup toasts, and end-of-arena messages.

const BANNER_SECONDS: float = 1.6
const TOAST_SECONDS: float = 2.5
const MAX_QUEUED_BANNERS: int = 3

# --- layout plan (single source of truth, see plan_layout) -------------------
# Vertical bands, top to bottom: wave label 12-40 | boss name 40-62 | boss bar 66-86 | banner 98-140
# (centre) | bars 90-134 and quest tracker 205+ (left) | ... | interaction prompt | subtitle | toast.
const BANNER_Y: float = 98.0
const BANNER_SIZE: Vector2 = Vector2(380.0, 44.0)
const WAVE_LABEL_SIZE: Vector2 = Vector2(320.0, 28.0)
const BOSS_BAR_MAX_WIDTH: float = 440.0
const EQUIPMENT_SIZE: Vector2 = Vector2(400.0, 82.0)
const TOAST_SIZE: Vector2 = Vector2(560.0, 32.0)
const SUBTITLE_LINES: int = 2
const SUBTITLE_LINE_HEIGHT: float = 30.0
const PROMPT_SIZE: Vector2 = Vector2(420.0, 34.0)
const PROMPT_GAP_ABOVE_SUBTITLE: float = 10.0
const HINT_SIZE: Vector2 = Vector2(840.0, 24.0)
const TELEPORT_LABEL_SIZE: Vector2 = Vector2(300.0, 28.0)  # drawn by teleport.gd at y~146
const PAUSE_BUTTON_RECT: Rect2 = Rect2(16.0, 140.0, 56.0, 56.0)
const TOUCH_RESERVE: float = 460.0  # width of the touch button column at the right edge
const LABEL_NEAR: float = 10.0
const LABEL_FAR: float = 16.0
const MAX_ENEMY_LABELS: int = 1

var _root: Control                      # themed parent of every widget (full rect, ignores the mouse)
var _health_bar: HudBar
var _stamina_bar: HudBar
var _armor_bar: HudBar
var _message: Label
var _wave_label: Label
var _banner: Label
var _equipment: HudEquipment
var _teleport: HudTeleport
var _ability: Node                      # the player's TeleportAbility (read only)
var _ability_poll: float = 0.0
var _backdrops: Array[Dictionary] = []  # {panel, labels, centered}: translucent panels behind text
var _toast: Label
var _check_time: float = 0.0
var _banner_time: float = 0.0
var _toast_time: float = 0.0
var _player: Player
var _waves: WaveManager
var _boss: Enemy
var _boss_bar: HudBar
var _boss_name: Label
var _quests: Node
var _tracker_title: Label
var _tracker_objective: Label
var _optional_line: Label
var _location_label: Label
var _location_time: float = 0.0
var _last_location: String = ""
var _subtitle: Label
var _caption_queue: Array[Dictionary] = []
var _subtitle_time: float = 0.0
var _banner_queue: Array[Dictionary] = []
var _hint: Label
var _boss_seen: bool = false
var _label_time: float = 0.0


## Pure layout plan: where every HUD widget sits for a viewport size, as rectangles. `touch` is true
## when the on-screen buttons are showing. _process positions the widgets from this, and the layout
## test checks that the rectangles never overlap each other or the touch buttons.
static func plan_layout(viewport: Vector2, touch: bool) -> Dictionary:
	var right_limit := viewport.x - (TOUCH_RESERVE if touch else 16.0)
	var avail_width := right_limit - 16.0
	var center_x := 16.0 + avail_width * 0.5 if touch else viewport.x * 0.5
	var sub_width := minf(minf(SUBTITLE_MAX_WIDTH, viewport.x * 0.6), avail_width)
	var sub_height := SUBTITLE_LINES * SUBTITLE_LINE_HEIGHT + 8.0
	var sub_y := viewport.y - SUBTITLE_BOTTOM_GAP - sub_height
	var boss_width := minf(BOSS_BAR_MAX_WIDTH, viewport.x * 0.34)
	var plan := {
		"bars": Rect2(16, 90, 240, 44),   # health 90-108, armor 110-124, stamina 126-134
		"teleport": Rect2(84.0 if touch else 16.0, 146, TELEPORT_LABEL_SIZE.x, TELEPORT_LABEL_SIZE.y),
		"wave": Rect2((viewport.x - WAVE_LABEL_SIZE.x) * 0.5, 12, WAVE_LABEL_SIZE.x, WAVE_LABEL_SIZE.y),
		"boss_name": Rect2((viewport.x - 300.0) * 0.5, 40, 300, 22),
		"boss_bar": Rect2((viewport.x - boss_width) * 0.5, 66, boss_width, 20),
		"banner": Rect2((viewport.x - BANNER_SIZE.x) * 0.5, BANNER_Y, BANNER_SIZE.x, BANNER_SIZE.y),
		"equipment": Rect2(viewport.x - EQUIPMENT_SIZE.x - 16.0, 12, EQUIPMENT_SIZE.x, EQUIPMENT_SIZE.y),
		"tracker": Rect2(16, TRACKER_TALL_Y, TRACKER_MAX_WIDTH, 72),
		"subtitle": Rect2(center_x - sub_width * 0.5, sub_y, sub_width, sub_height),
		"toast": Rect2(center_x - TOAST_SIZE.x * 0.5, viewport.y - 110.0, TOAST_SIZE.x, TOAST_SIZE.y),
		"prompt": Rect2(center_x - PROMPT_SIZE.x * 0.5, sub_y - PROMPT_GAP_ABOVE_SUBTITLE - PROMPT_SIZE.y,
				PROMPT_SIZE.x, PROMPT_SIZE.y),
	}
	if touch:
		plan["pause"] = PAUSE_BUTTON_RECT
	else:
		plan["hint"] = Rect2(16, viewport.y - 30.0, HINT_SIZE.x, HINT_SIZE.y)
	return plan


## Prompt rectangle for scripts that draw their own prompt (the Interactor), so it clears the subtitle.
static func prompt_position(viewport: Vector2, touch: bool, prompt_size: Vector2) -> Vector2:
	var rect: Rect2 = plan_layout(viewport, touch)["prompt"]
	return Vector2(rect.get_center().x - prompt_size.x * 0.5, rect.end.y - prompt_size.y)


func _ready() -> void:
	layer = 50
	if get_node_or_null("ObjectivePointer") == null:  # compass arrow toward the current objective (own layer, own file)
		var pointer := ObjectivePointer.new()
		pointer.name = "ObjectivePointer"
		add_child(pointer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = HudTheme.theme()
	add_child(_root)

	# Bars: health (heart + numbers), armor (shield + numbers, hidden until armor is worn), stamina (thin).
	_health_bar = _make_bar(Vector2(16, 90), Vector2(240, 18), HudTheme.HEALTH, &"heart", 14)
	_armor_bar = _make_bar(Vector2(16, 110), Vector2(240, 14), HudTheme.ARMOR, &"shield", 11)
	_armor_bar.visible = false
	_stamina_bar = _make_bar(Vector2(16, 126), Vector2(240, 8), HudTheme.STAMINA, &"", 8)
	_stamina_bar.show_text = false

	_message = _make_label(48, 8)
	_message.visible = false
	_banner = _make_label(HudTheme.FONT_BANNER, 6)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.visible = false
	var wave_backdrop := _make_backdrop(14)
	_wave_label = _make_label(20, 4)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_register_backdrop(wave_backdrop, [_wave_label], Vector2(14, 3))
	var toast_backdrop := _make_backdrop(14)
	_toast = _make_label(22, 4)
	_toast.visible = false
	_register_backdrop(toast_backdrop, [_toast], Vector2(14, 4))

	_equipment = HudEquipment.new()
	_equipment.size = EQUIPMENT_SIZE
	_root.add_child(_equipment)
	_teleport = HudTeleport.new()
	_teleport.size = Vector2(HudTeleport.WIDTH, TELEPORT_LABEL_SIZE.y)
	_root.add_child(_teleport)

	_boss_name = _make_label(20, 4)
	_boss_name.visible = false
	_boss_bar = _make_bar(Vector2.ZERO, Vector2(520, 20), HudTheme.BOSS, &"", 14)
	_boss_bar.show_text = false
	_boss_bar.visible = false

	if not TouchControls.is_mobile_platform():
		_hint = Label.new()
		var hint := _hint
		hint.text = "WASD move | Shift sprint | Space jump | Ctrl or C dodge | LMB light | RMB heavy | R medkit | F3 stats"
		hint.position = Vector2(16, 690)  # re-positioned every frame from the viewport height
		HudTheme.style_label(hint, HudTheme.FONT_SMALL, 4, HudTheme.TEXT_DIM)
		_root.add_child(hint)

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
	var plan := plan_layout(viewport_size, TouchControls.touch_active)
	var toast_rect: Rect2 = plan["toast"]
	_wave_label.position = Vector2((viewport_size.x - _wave_label.size.x) * 0.5, 12)
	var equipment_rect: Rect2 = plan["equipment"]
	_equipment.position = equipment_rect.position
	var teleport_rect: Rect2 = plan["teleport"]
	_teleport.position = teleport_rect.position + Vector2(_teleport.shake_offset, 0.0)
	_toast.position = Vector2(toast_rect.get_center().x - _toast.size.x * 0.5, toast_rect.position.y)
	_banner.position = Vector2((viewport_size.x - _banner.size.x) * 0.5, BANNER_Y)
	if _hint:
		_hint.position = Vector2(16, viewport_size.y - 30.0)

	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time / 0.4, 0.0, 1.0)
		_banner.visible = _banner_time > 0.0
	if _banner_time <= 0.0 and not _banner_queue.is_empty():
		var next: Dictionary = _banner_queue.pop_front()  # banners show one at a time
		_banner.text = String(next["text"])
		_banner.add_theme_color_override("font_color", next["color"] as Color)
		_banner.modulate.a = 1.0
		_banner.visible = true
		_banner_time = BANNER_SECONDS
	_label_time += delta
	if _label_time >= 0.1:
		_label_time = 0.0
		_update_enemy_labels()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.5, 0.0, 1.0)
		_toast.visible = _toast_time > 0.0

	_update_boss_bar(viewport_size)
	_update_story(viewport_size, delta)
	_sync_backdrops()
	_update_teleport(delta)

	_check_time += delta
	if _check_time < 0.25:
		return
	_check_time = 0.0
	_refresh_wave_label()
	if _boss == null or not is_instance_valid(_boss) or _boss.is_dead():
		_boss = get_tree().get_first_node_in_group("boss") as Enemy
	var boss_alive := _boss != null and is_instance_valid(_boss) and not _boss.is_dead()
	if boss_alive and not _boss_seen:
		_cut_captions()  # the boss is the news now: old radio chatter must not run over him
	_boss_seen = boss_alive
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
	var rect: Rect2 = plan_layout(viewport_size, TouchControls.touch_active)["boss_bar"]
	_boss_bar.custom_minimum_size.x = rect.size.x  # narrower on small screens: clears the equipment panel
	_boss_bar.size.x = rect.size.x
	_boss_bar.position = rect.position
	_boss_name.position = Vector2((viewport_size.x - _boss_name.size.x) * 0.5, 40)


func _arena_cleared() -> bool:
	if _waves and is_instance_valid(_waves):
		return _waves.is_finished()
	return get_tree().get_nodes_in_group("enemies").is_empty()


func _make_label(font_size: int, outline: int) -> Label:
	var label := Label.new()
	HudTheme.style_label(label, font_size, outline)
	_root.add_child(label)
	return label


func _make_bar(pos: Vector2, bar_size: Vector2, color: Color, icon: StringName, font: int) -> HudBar:
	var bar := HudBar.new()
	bar.position = pos
	bar.custom_minimum_size = bar_size
	bar.size = bar_size
	bar.fill_color = color
	bar.icon = icon
	bar.font_size = font
	_root.add_child(bar)
	return bar


## A translucent rounded panel that sits behind some text; _sync_backdrops keeps it fitted to the labels.
## Create it BEFORE the labels so it draws underneath them.
func _make_backdrop(radius: int) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style(HudTheme.PANEL_BG, radius))
	panel.visible = false
	_root.add_child(panel)
	return panel


func _register_backdrop(panel: Panel, labels: Array, pad: Vector2, centered: bool = false) -> void:
	_backdrops.append({"panel": panel, "labels": labels, "pad": pad, "centered": centered})


func _sync_backdrops() -> void:
	for entry in _backdrops:
		var panel := entry["panel"] as Panel
		var rect := Rect2()
		var found := false
		var alpha := 1.0
		for node in entry["labels"]:
			var label := node as Label
			if label == null or not label.visible or label.text == "":
				continue
			var label_rect := _label_rect(label, bool(entry["centered"]))
			rect = label_rect if not found else rect.merge(label_rect)
			if not found:
				alpha = label.modulate.a
			found = true
		panel.visible = found
		if found:
			var pad: Vector2 = entry["pad"]
			panel.position = rect.position - pad
			panel.size = rect.size + pad * 2.0
			panel.modulate.a = alpha


## The rectangle a label's text really covers. Centered, wrapped text (the subtitle) is measured so the
## backdrop hugs short lines instead of always spanning the full wrap width.
func _label_rect(label: Label, centered: bool) -> Rect2:
	var minimum := label.get_combined_minimum_size()
	var label_size := Vector2(maxf(label.size.x, minimum.x), maxf(label.size.y, minimum.y))
	if centered and label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var measured := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, label_size.x,
				font_size, label.max_lines_visible)
		var width := clampf(measured.x, 40.0, label_size.x)
		return Rect2(label.position.x + (label_size.x - width) * 0.5, label.position.y, width, label_size.y)
	return Rect2(label.position, label_size)


# --- teleport readout (reads the player's TeleportAbility; never changes it) -------

func _find_ability() -> Node:
	if _player == null or not is_instance_valid(_player):
		return null
	for child in _player.get_children():
		if child is TeleportAbility:
			return child
	return null


func _update_teleport(delta: float) -> void:
	_ability_poll -= delta
	if _ability_poll > 0.0:
		return
	_ability_poll = 0.25
	if _ability == null or not is_instance_valid(_ability):
		_ability = _find_ability()
		if _ability != null:
			# The ability draws its own text label; the pips below replace it (its toast still shows).
			var own_label: Variant = _ability.get("_label")
			if own_label is Label:
				(own_label as Label).visible = false
			_ability.connect("denied", func(_seconds: float) -> void: _teleport.deny())
	_teleport.visible = _ability != null
	if _ability != null:
		_teleport.set_state(int(_ability.get("charges")), TeleportAbility.MAX_CHARGES,
				float(_ability.call("seconds_until_next")))


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
	_queue_banner("WAVE %d" % index, Color(0.95, 0.85, 0.3))
	_cut_captions()  # a wave starting beats any radio chatter still queued
	_refresh_wave_label()


## Banners show one at a time in their own band (top third), never stacked on each other.
func _queue_banner(text: String, color: Color) -> void:
	if _banner_queue.size() >= MAX_QUEUED_BANNERS:
		_banner_queue.pop_front()
	_banner_queue.append({"text": text, "color": color})


## Enemy name/health labels are cluttering unless limited: only the nearest enemy and the locked target
## show one, and they fade out with distance. The boss is read from the boss bar instead.
func _update_enemy_labels() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var enemies := get_tree().get_nodes_in_group("enemies")
	var ranked: Array[Dictionary] = []
	var locked: Node3D = _player.lock_target() if _player.has_method("lock_target") else null
	for node in enemies:
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead():
			continue
		var distance := _player.global_position.distance_to(enemy.global_position)
		ranked.append({"enemy": enemy, "distance": distance, "locked": enemy == locked})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["locked"] != b["locked"]:
			return a["locked"]
		return float(a["distance"]) < float(b["distance"]))
	var shown := 0
	for entry in ranked:
		var enemy := entry["enemy"] as Enemy
		var label := enemy.get_node_or_null("HealthLabel") as Label3D
		if label == null:
			continue
		var distance := float(entry["distance"])
		var visible_now := shown < MAX_ENEMY_LABELS and distance <= LABEL_FAR and not enemy.is_in_group("boss")
		if visible_now:
			shown += 1
			label.modulate.a = 1.0 - smoothstep(LABEL_NEAR, LABEL_FAR, distance)
		label.visible = visible_now


## Drops queued captions and fades the one on screen, for events that matter more.
func _cut_captions() -> void:
	_caption_queue.clear()
	if _subtitle_time > 0.9:
		_subtitle_time = 0.9


func _refresh_wave_label() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies").size()
	var wave := 0
	var total := 4
	if _waves and is_instance_valid(_waves):
		wave = _waves.current_wave
		total = _waves.total_waves()
	_wave_label.text = "Wave %d/%d  Enemies: %d" % [wave, total, enemies]


func _refresh_equipment() -> void:
	if _player == null or _player.inventory == null or _equipment == null:
		return
	var inv := _player.inventory
	var weapon := inv.weapon
	var armor := inv.armor
	var modifier := ""
	if weapon:
		modifier = "x%.2f dmg" % weapon.damage_multiplier
		if not is_equal_approx(weapon.attack_speed, 1.0):
			modifier += "  %.2fx spd" % weapon.attack_speed
	var armor_points := ""
	if armor and _player.health.max_armor > 0.0:
		armor_points = "%d/%d" % [roundi(_player.health.armor), roundi(_player.health.max_armor)]
	_equipment.set_data(
			weapon.display_name if weapon else "None",
			weapon.color() if weapon else HudTheme.TEXT_DIM,
			modifier,
			armor.display_name if armor else "None",
			armor_points,
			armor.color() if armor else HudTheme.TEXT_DIM,
			inv.potions)


func _on_item_collected(item: ItemData, kept: bool) -> void:
	_show_toast(("Picked up %s" if kept else "%s (not an upgrade)") % item.display_name, item.color())


# --- story: quest tracker and subtitles (presentation only) -----------------

const SUBTITLE_FADE: float = 0.4
const SHORT_VIEWPORT_HEIGHT: float = 480.0
const LOCATION_Y: float = 146.0       # under the banner band (98-138), clear of the teleport label on the left
const LOCATION_SIZE: Vector2 = Vector2(420, 32)
const LOCATION_SECONDS: float = 2.6
## World area id -> name shown by the location banner (Milestone 3: Outpost 17).
const AREA_NAMES: Dictionary = {
	"area_a_perimeter": "Outer Perimeter",
	"area_b_compound": "Military Compound",
	"area_c_research": "Research Access Facility",
	"area_d_command": "Command Center",
}
const TRACKER_MAX_WIDTH: float = 360.0
const TRACKER_TALL_Y: float = 205.0   # below the bars (90-134), teleport label (~150) and pause button (140-196)
const TRACKER_SHORT_Y: float = 46.0   # fallback for very short screens: top centre under the wave label
const TRACKER_SHORT_MIN_X: float = 290.0  # right of the bars and the teleport label
const SUBTITLE_MAX_WIDTH: float = 720.0
const SUBTITLE_BOTTOM_GAP: float = 120.0  # subtitle bottom edge sits this far above the screen bottom (toast is at 110)
const MAX_QUEUED_CAPTIONS: int = 3
const CAPTION_MAX_CHARS: int = 110  # two lines at the subtitle width
const CAPTION_MIN_SECONDS: float = 3.0
const CAPTION_MAX_SECONDS: float = 6.0


func _setup_story() -> void:
	var tracker_backdrop := _make_backdrop(10)
	_tracker_title = _make_label(HudTheme.FONT_BODY, 4)
	_tracker_title.add_theme_color_override("font_color", HudTheme.GOLD)
	_tracker_title.visible = false
	_tracker_objective = _make_label(HudTheme.FONT_SMALL + 1, 4)
	_tracker_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tracker_objective.max_lines_visible = 2  # long objectives never grow the tracker past two lines
	_tracker_objective.visible = false
	_optional_line = _make_label(14, 4)
	_optional_line.add_theme_color_override("font_color", Color(0.8, 0.72, 0.4, 0.9))  # dim gold: optional
	_optional_line.clip_text = true
	_optional_line.visible = false
	_location_label = _make_label(22, 6)
	_location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_location_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.88))
	_location_label.visible = false
	_register_backdrop(tracker_backdrop, [_tracker_title, _tracker_objective], Vector2(10, 5))
	var subtitle_backdrop := _make_backdrop(10)
	_subtitle = _make_label(22, 6)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.max_lines_visible = SUBTITLE_LINES
	_subtitle.visible = false
	_register_backdrop(subtitle_backdrop, [_subtitle], Vector2(16, 6), true)
	var world := get_node_or_null("/root/WorldState")
	if world != null and world.has_signal("area_entered"):
		world.area_entered.connect(_on_area_entered)
	_quests = get_node_or_null("/root/QuestManager")
	if _quests == null:
		return
	if _quests.has_signal("quest_item_added"):
		_quests.quest_item_added.connect(_on_quest_item_added)
	_quests.tracker_changed.connect(_refresh_tracker)
	_quests.caption_requested.connect(show_caption)
	_quests.quest_started.connect(_on_quest_started)
	_quests.quest_completed.connect(_on_quest_completed)
	_refresh_tracker()


## Queue a subtitle line (radio and story captions). Lines show one after another, at most
## MAX_QUEUED_CAPTIONS waiting (the oldest is dropped), long text is split to fit two lines, and the
## time on screen follows the text length (3-6 s). A caller that asks for less than the 3 s minimum
## (a deliberate quick flash) gets exactly that; every normal request uses the reading time.
func show_caption(text: String, seconds: float = 4.0) -> void:
	if _subtitle == null or text.is_empty():
		return
	for chunk in split_caption(text):
		if _caption_queue.size() >= MAX_QUEUED_CAPTIONS:
			_caption_queue.pop_front()
		var shown_for := seconds if seconds < CAPTION_MIN_SECONDS else caption_seconds_for(chunk)
		_caption_queue.append({"text": chunk, "seconds": maxf(shown_for, 0.5)})


static func caption_seconds_for(text: String) -> float:
	return clampf(1.8 + text.length() * 0.045, CAPTION_MIN_SECONDS, CAPTION_MAX_SECONDS)


## Splits long text at sentence ends (or spaces) into pieces that fit two subtitle lines.
static func split_caption(text: String) -> Array[String]:
	var pieces: Array[String] = []
	var remaining := text.strip_edges()
	while remaining.length() > CAPTION_MAX_CHARS:
		var cut := -1
		for stop in [". ", "! ", "? ", "; ", ", "]:
			var at := remaining.rfind(stop, CAPTION_MAX_CHARS - 1)
			if at > 20:
				cut = at + 1
				break
		if cut < 0:
			cut = remaining.rfind(" ", CAPTION_MAX_CHARS)
		if cut <= 0:
			cut = CAPTION_MAX_CHARS
		pieces.append(remaining.substr(0, cut).strip_edges())
		remaining = remaining.substr(cut).strip_edges()
	if not remaining.is_empty():
		pieces.append(remaining)
	return pieces


func _refresh_tracker() -> void:
	if _quests == null or _tracker_title == null:
		return
	_tracker_title.text = _quests.tracker_title()
	_tracker_objective.text = _quests.tracker_objective()
	var optional_text: String = _quests.tracker_optional() if _quests.has_method("tracker_optional") else ""
	_optional_line.text = optional_text


func _on_quest_started(quest_id: StringName) -> void:
	var quest: QuestData = _quests.get_quest(quest_id)
	if quest:
		_show_toast("New quest: %s" % quest.title, Color(0.95, 0.85, 0.3))


func _on_quest_completed(quest_id: StringName) -> void:
	var quest: QuestData = _quests.get_quest(quest_id)
	if quest == null:
		return
	_queue_banner("MISSION COMPLETE" if quest.show_mission_banner else "QUEST COMPLETE", Color(0.95, 0.85, 0.3))
	var reward := "" if quest.reward_text.is_empty() else "  Reward: %s" % quest.reward_text
	_show_toast("%s%s" % [quest.title, reward], Color(0.95, 0.85, 0.3))


func _on_quest_item_added(id: StringName) -> void:
	_show_toast("Quest item: %s" % QuestItems.display_name(id), Color(0.95, 0.85, 0.3))


func _on_area_entered(id: StringName) -> void:
	var area_name: String = AREA_NAMES.get(String(id), "")
	if not area_name.is_empty():
		show_location(area_name)


## Location banner: shows an area name for a moment (not again for the same area in a row).
func show_location(area_name: String) -> void:
	if area_name.is_empty() or area_name == _last_location:
		return
	_last_location = area_name
	_location_label.text = area_name
	_location_label.modulate.a = 1.0
	_location_label.visible = true
	_location_time = LOCATION_SECONDS


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
	# Optional-objective line: one dim line directly under the objective (part of the tracker block).
	_optional_line.custom_minimum_size.x = tracker_width
	_optional_line.size.x = tracker_width
	var optional_height := _optional_line.get_combined_minimum_size().y if _optional_line.text != "" else 0.0
	_optional_line.position = Vector2(tracker_x, tracker_y + title_height + objective_height)
	_optional_line.size.y = optional_height
	var tracker_rect := Rect2(tracker_x, tracker_y, tracker_width, title_height + objective_height + optional_height)
	# Location banner: centred under the banner band; not used on very short screens.
	var location_rect := Rect2((viewport_size.x - LOCATION_SIZE.x) * 0.5, LOCATION_Y, LOCATION_SIZE.x, LOCATION_SIZE.y)
	_location_label.custom_minimum_size.x = LOCATION_SIZE.x
	_location_label.size.x = LOCATION_SIZE.x
	_location_label.position = location_rect.position

	# Width, centre and the clear-of-touch-buttons rule come from plan_layout (wrap at ~60% of the screen).
	var sub_plan: Rect2 = plan_layout(viewport_size, TouchControls.touch_active)["subtitle"]
	var subtitle_width := sub_plan.size.x
	_subtitle.custom_minimum_size.x = subtitle_width
	_subtitle.size.x = subtitle_width
	_subtitle.size.y = 0.0
	var subtitle_height := minf(_subtitle.get_combined_minimum_size().y, sub_plan.size.y)  # two lines at most
	_subtitle.size.y = subtitle_height
	var subtitle_x := sub_plan.position.x
	var subtitle_y := viewport_size.y - SUBTITLE_BOTTOM_GAP - subtitle_height
	if short:
		# Below the tracker, and never inside the equipment panel (top-right, bottom edge at y=112).
		subtitle_y = maxf(tracker_rect.end.y + 8.0, 120.0)
	_subtitle.position = Vector2(subtitle_x, subtitle_y)
	return {
		"tracker": tracker_rect,
		"subtitle": Rect2(subtitle_x, subtitle_y, subtitle_width, subtitle_height),
		"location": location_rect,
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
	_optional_line.visible = show_tracker and _optional_line.text != ""
	if _location_time > 0.0:
		_location_time -= delta
		_location_label.modulate.a = clampf(_location_time / 0.6, 0.0, 1.0)
		_location_label.visible = _location_time > 0.0 and not short  # the banner is skipped on very short screens
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
