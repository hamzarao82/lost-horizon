class_name CampaignEnding
extends CanvasLayer
## The campaign ending: fade, closing captions, statistics, credits, then a choice between exploring on and
## the main menu. Starts once when `campaign_complete` turns true (never when a save that already has the
## flag is loaded), pauses the tree while shown and hides the HUD. See docs/CAMPAIGN_ENDING.md.

signal finished(choice: StringName)

const FLAG_COMPLETE: StringName = &"campaign_complete"
const FLAG_SEEN: StringName = &"ending_seen"
const MENU_SCENE: String = "res://scenes/boot/Boot.tscn"
const CHOICE_EXPLORE: StringName = &"explore"
const CHOICE_MENU: StringName = &"menu"
const FADE_SECONDS: float = 1.2
const REGION_ORDER: Array[StringName] = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
const REGION_NAMES: Dictionary = {
	&"outpost_17": "Outpost 17", &"dead_coast": "Dead Coast", &"blackwood": "Blackwood",
	&"research_complex": "Research Complex", &"iron_fortress": "Iron Fortress",
}
## Closing beats (original text). The protagonist's reason for being on the transport is the bible's proposal.
const BEATS: Array[Dictionary] = [
	{"text": "The Director falls. The control room goes quiet, then every screen begins to burn through its own records.", "seconds": 5.0},
	{"text": "Radio: Transmission received. All of it: the trial records, the route table, the Director's own files. It reached the outside.", "seconds": 5.5},
	{"text": "Radio: Command on the island is exposed. The people who gave the orders have stopped answering theirs.", "seconds": 5.0},
	{"text": "Radio: The lost transport's manifest was in the records. One passenger had witnessed the first containment failure. They moved the witness to bury it.", "seconds": 6.0},
	{"text": "Radio: The transport was meant to vanish. It did not. You are still here, and that is why this ended the way it did.", "seconds": 5.5},
	{"text": "The island is not finished. Below Sublevel 1 a counter is still running, and a voice in the Blackwood is still counting.", "seconds": 5.5},
	{"text": "For now the signal is out, and the island is yours to walk.", "seconds": 4.5},
]

enum Stage { FADE, BEATS, STATS, CREDITS, CHOICE, DONE }

var stage: Stage = Stage.FADE
var beat_index: int = -1
## True when started from a menu or a test without touching save flags or the world.
var replay: bool = false
## Tests turn this off so choosing the main menu does not really change scenes.
var go_to_menu_scene: bool = true
## Replay from the main menu: statistics read from the chosen save (nothing is loaded into the running game).
var stats_override: Dictionary = {}


var _beat_left: float = 0.0
var _fade_left: float = FADE_SECONDS
var _was_paused: bool = false
var _hidden_huds: Array = []
var _dim: ColorRect
var _holder: CenterContainer
var _title: Label
var _body: Label
var _hint: Label
var _box: VBoxContainer
var _buttons: VBoxContainer
var _stats: Dictionary = {}


# --- start-up ----------------------------------------------------------------

## True when a flag change should start the ending: exactly the completion flag turning on, once.
static func should_start(world: Object, flag_id: StringName, value: bool) -> bool:
	if flag_id != FLAG_COMPLETE or not value:
		return false
	return world == null or not world.has_method("has_flag") or not world.has_flag(FLAG_SEEN)


## Listens to WorldState once. A loaded save emits the wildcard id `*`, which never matches.
static func watch(world: Node) -> void:
	if world == null or not world.has_signal("flag_changed"):
		return
	world.flag_changed.connect(func(id: StringName, value: bool) -> void:
		if should_start(world, id, value):
			start(world.get_tree()))


static func start(tree: SceneTree, as_replay: bool = false, stats: Dictionary = {}) -> CampaignEnding:
	if tree == null:
		return null
	var existing := tree.root.get_node_or_null("CampaignEnding")
	if existing != null:
		return existing as CampaignEnding
	var ending := CampaignEnding.new()
	ending.name = "CampaignEnding"
	ending.replay = as_replay
	ending.stats_override = stats
	tree.root.add_child(ending)
	return ending


## What the statistics screen shows. Campaign progress and optional discoveries are reported separately.
static func collect_stats(tree: SceneTree) -> Dictionary:
	var out := {"time_played": 0.0, "enemies": 0, "campaign": {}, "optional": {}}
	if tree == null:
		return out
	var run := tree.root.get_node_or_null("RunStats")
	if run != null:
		out["time_played"] = float(run.seconds_played)
		out["enemies"] = int(run.enemies_defeated)
		out["optional"] = {
			"secrets_found": int(run.secrets_found()), "secrets_total": int(run.secrets_total()),
			"documents": int(run.documents_found()),
		}
	var world := tree.root.get_node_or_null("WorldState")
	var done := 0
	var names: Array[String] = []
	for index in REGION_ORDER.size():
		if region_complete(world, index):
			done += 1
			names.append(String(REGION_NAMES[REGION_ORDER[index]]))
	var quests := tree.root.get_node_or_null("QuestManager")
	out["campaign"] = {
		"regions_completed": done, "regions_total": REGION_ORDER.size(), "region_names": names,
		"missions_completed": quests.completed.size() if quests != null else 0,
		"campaign_complete": world != null and world.has_flag(FLAG_COMPLETE),
	}
	return out


## Statistics for a replay, read from a raw save dictionary only (the running game is not touched). The optional
## discovery counters live in autoloads that a menu session has not loaded, so they are left out.
static func stats_from_save(data: Dictionary) -> Dictionary:
	var out := {"time_played": 0.0, "enemies": 0, "campaign": {}, "optional": {}}
	var stats: Variant = data.get("stats", {})
	if stats is Dictionary:
		out["time_played"] = maxf(float((stats as Dictionary).get("seconds", 0.0)) if (stats as Dictionary).get("seconds") is float or (stats as Dictionary).get("seconds") is int else 0.0, 0.0)
		out["enemies"] = maxi(int((stats as Dictionary).get("kills", 0)) if (stats as Dictionary).get("kills") is float or (stats as Dictionary).get("kills") is int else 0, 0)
	var world := load("res://scripts/core/world_state.gd").new() as Node
	var quests: Variant = data.get("quests", {})
	var missions := 0
	if quests is Dictionary:
		var world_raw: Variant = (quests as Dictionary).get("world", {})
		if world_raw is Dictionary:
			world.call("from_dict", world_raw)
		var done: Variant = (quests as Dictionary).get("completed", [])
		missions = (done as Array).size() if done is Array else 0
	var regions := 0
	var names: Array[String] = []
	for index in REGION_ORDER.size():
		if region_complete(world, index):
			regions += 1
			names.append(String(REGION_NAMES[REGION_ORDER[index]]))
	out["campaign"] = {"regions_completed": regions, "regions_total": REGION_ORDER.size(), "region_names": names,
			"missions_completed": missions, "campaign_complete": world.call("has_flag", FLAG_COMPLETE)}
	world.free()
	return out


## A region counts as complete when the next region's unlock flag (or its aliases) is set; the last one
## completes with the campaign flag.
static func region_complete(world: Node, index: int) -> bool:
	if world == null:
		return false
	if index >= REGION_ORDER.size() - 1:
		return world.has_flag(FLAG_COMPLETE)
	var next_region: StringName = REGION_ORDER[index + 1]
	var rule: Dictionary = CampaignFlow.CHAIN.get(next_region, {})
	if rule.is_empty():
		return false
	if world.has_flag(StringName(rule["after"])):
		return true
	for alias in rule["aliases"]:
		if world.has_flag(StringName(alias)):
			return true
	return false


static func format_time(seconds: float) -> String:
	var total := maxi(int(seconds), 0)
	return "%d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


# --- life cycle ----------------------------------------------------------------

func _ready() -> void:
	layer = 230 if replay else 170  # a replay runs over the main menu (layer 210)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	_hide_huds()
	_stats = stats_override if not stats_override.is_empty() else collect_stats(get_tree())
	_build_ui()
	if not replay:
		var world := get_tree().root.get_node_or_null("WorldState")
		if world != null:
			world.set_flag(FLAG_SEEN, true)
	_audio_call("play", [&"mission_complete"])
	_set_duck(0.0)
	stage = Stage.FADE


func _exit_tree() -> void:
	_restore_huds()
	_set_duck(1.0)


func _process(delta: float) -> void:
	match stage:
		Stage.FADE:
			_fade_left -= delta
			_dim.color.a = clampf(1.0 - _fade_left / FADE_SECONDS, 0.0, 1.0) * 0.96
			if _fade_left <= 0.0:
				_next_beat()
		Stage.BEATS:
			_beat_left -= delta
			if _beat_left <= 0.0:
				_next_beat()


func _input(event: InputEvent) -> void:
	if not _is_skip(event):
		return
	match stage:
		Stage.FADE:
			_fade_left = 0.0
			get_viewport().set_input_as_handled()
		Stage.BEATS:
			_next_beat()
			get_viewport().set_input_as_handled()


func _is_skip(event: InputEvent) -> bool:
	if not event.is_pressed() or (event is InputEventKey and (event as InputEventKey).echo):
		return false
	if event is InputEventKey:
		var key := (event as InputEventKey).keycode
		return key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_ESCAPE
	return event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")


# --- stages ----------------------------------------------------------------------

func _next_beat() -> void:
	beat_index += 1
	if beat_index >= BEATS.size():
		_show_stats()
		return
	stage = Stage.BEATS
	var beat: Dictionary = BEATS[beat_index]
	_show_text("", String(beat["text"]), true)
	_beat_left = float(beat["seconds"])


func _show_stats() -> void:
	stage = Stage.STATS
	var campaign: Dictionary = _stats["campaign"]
	var optional: Dictionary = _stats["optional"]
	var lines: Array[String] = [
		"Campaign",
		"Regions completed: %d / %d" % [int(campaign.get("regions_completed", 0)), int(campaign.get("regions_total", 5))],
		"Missions completed: %d" % int(campaign.get("missions_completed", 0)),
		"Time played: %s" % format_time(float(_stats["time_played"])),
		"Enemies defeated: %d" % int(_stats["enemies"]),
	]
	if not optional.is_empty():  # a replay from a save has no discovery counters to show
		lines.append_array(["", "Optional discoveries (tracked separately)",
			"Secrets found: %d / %d" % [int(optional.get("secrets_found", 0)), int(optional.get("secrets_total", 0))],
			"Documents read: %d" % int(optional.get("documents", 0))])
	_show_text("CAMPAIGN COMPLETE", "\n".join(lines), false)
	_set_buttons([["Continue", _show_credits]])


func _show_credits() -> void:
	stage = Stage.CREDITS
	_show_text("LOST HORIZON: BLACK SITE", "\n".join(StoryEnding.CREDITS), false)
	_set_buttons([["Continue", _show_choice]])


func _show_choice() -> void:
	stage = Stage.CHOICE
	_show_text("THE SIGNAL IS OUT", "Every region stays open. Optional discoveries can still be found.", false)
	var items: Array = [["Continue Exploring", _choose.bind(CHOICE_EXPLORE)], ["Main Menu", _choose.bind(CHOICE_MENU)]]
	if replay:
		items = [["Close", _choose.bind(CHOICE_EXPLORE)]]
	_set_buttons(items)


func _choose(choice: StringName) -> void:
	if stage == Stage.DONE:
		return
	stage = Stage.DONE
	if not replay:
		var saves := get_tree().root.get_node_or_null("SaveManager")
		if saves != null and saves.has_method("autosave"):
			saves.autosave("ending")  # persists campaign_complete and ending_seen before anything else happens
		if choice == CHOICE_MENU:
			if saves != null and saves.has_method("reset_runtime_state"):
				saves.reset_runtime_state()  # the menu's Continue loads the file just written
			var stats := get_tree().root.get_node_or_null("RunStats")
			if stats != null:
				stats.reset()
	get_tree().paused = _was_paused if choice == CHOICE_EXPLORE else false
	finished.emit(choice)
	if choice == CHOICE_MENU and not replay and go_to_menu_scene:
		get_tree().change_scene_to_file(MENU_SCENE)
	queue_free()


# --- ui --------------------------------------------------------------------------

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = HudTheme.theme()
	add_child(root)
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_dim)
	_holder = CenterContainer.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_holder)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(520.0, 0.0)
	_box.add_theme_constant_override("separation", 16)
	_holder.add_child(_box)
	_title = _make_label(34, HudTheme.GOLD)
	_body = _make_label(HudTheme.FONT_BODY + 4, HudTheme.TEXT)
	_hint = _make_label(HudTheme.FONT_SMALL, HudTheme.TEXT_DIM)
	_hint.text = "Space, Enter or Esc to skip"
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	for node in [_title, _body, _buttons, _hint]:
		_box.add_child(node)


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _show_text(title: String, body: String, show_hint: bool) -> void:
	_title.text = title
	_title.visible = title != ""
	_body.text = body
	_hint.visible = show_hint
	_dim.color.a = 0.96
	for child in _buttons.get_children():
		child.queue_free()


func _set_buttons(items: Array) -> void:
	for child in _buttons.get_children():
		child.queue_free()
	var first: Button
	for item in items:
		var button := RpgUi.button(String(item[0]), item[1] as Callable, 280.0)
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 56.0)
		_buttons.add_child(button)
		if first == null:
			first = button
	if first != null:
		first.grab_focus.call_deferred()


# --- hud and audio -----------------------------------------------------------------

func _hide_huds() -> void:
	_hidden_huds.clear()
	for node in get_tree().root.find_children("*", "Hud", true, false):
		if node is CanvasLayer and (node as CanvasLayer).visible:
			(node as CanvasLayer).visible = false
			_hidden_huds.append(node)


func _restore_huds() -> void:
	for node in _hidden_huds:
		if is_instance_valid(node):
			(node as CanvasLayer).visible = true
	_hidden_huds.clear()


func _set_duck(linear: float) -> void:
	_audio_call("set_ambience_duck", [linear])


func _audio_call(method: String, args: Array) -> void:
	var audio := get_tree().root.get_node_or_null("AudioManager") if is_inside_tree() else null
	if audio != null and audio.has_method(method):
		audio.callv(method, args)
