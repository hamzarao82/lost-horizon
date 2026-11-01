extends Node
## Quest tracking (autoload "QuestManager"; no class_name on purpose, it would clash with the autoload).
## Progress reacts to gameplay events only: WorldState signals (interacted, area_entered, flag_changed),
## WaveManager signals, Enemy.defeated and Inventory.item_collected. Nothing in a scene hardcodes a quest.
## Also runs the opening (new run) and the ending (final quest). See docs/STORY.md.

signal quest_started(quest_id: StringName)
signal objective_updated(quest_id: StringName, objective_index: int, progress: int, required: int)
signal quest_completed(quest_id: StringName)
signal tracker_changed
## Story / radio lines for the HUD subtitle queue.
signal caption_requested(text: String, seconds: float)
signal ending_started

const QUEST_PATHS: Array[String] = [
	"res://resources/quests/first_signal.tres",
	"res://resources/quests/restore_power.tres",
	"res://resources/quests/broken_perimeter.tres",
	"res://resources/quests/final_transmission.tres",
]
const FIRST_QUEST: StringName = &"first_signal"
const FINAL_QUEST: StringName = &"final_transmission"
const KEYCARD_FLAG: StringName = &"has_keycard"
const INTRO_SCENE: String = "res://scenes/story/Intro.tscn"
const ENDING_SCENE: String = "res://scenes/story/Ending.tscn"
const INTRO_SETTLE_SECONDS: float = 0.6

## Quest id -> QuestData.
var quests: Dictionary = {}
## Quest id -> {"progress": [int], "seen": [[String]], "done": [bool]} (one entry per objective).
var active: Dictionary = {}
var completed: Array[StringName] = []
var intro_done: bool = false
var ending_shown: bool = false

var _rewarded: Array[StringName] = []
var _pending_rewards: Array[String] = []
## "type:target" of every non-counting event seen so far; replayed when a quest starts, so doing
## things "early" (a switch before the radio) still counts once the quest begins.
var _history: Dictionary = {}
var _kill_ids: Dictionary = {}
var _world: Node
var _world_stash: Dictionary = {}
var _intro: Node
var _ending: Node


func _ready() -> void:
	_load_quests()
	get_tree().node_added.connect(_on_node_added)
	_bind_world_state.call_deferred()
	_ensure_progress()


# --- data ------------------------------------------------------------------

func _load_quests() -> void:
	quests.clear()
	for path in QUEST_PATHS:
		var quest := load(path) as QuestData
		if quest == null:
			push_warning("QuestManager: could not load %s" % path)
			continue
		var errors := quest.validate()
		if not errors.is_empty():
			push_warning("QuestManager: %s is invalid: %s" % [path, "; ".join(errors)])
			continue
		quests[quest.id] = quest


func get_quest(quest_id: StringName) -> QuestData:
	return quests.get(quest_id) as QuestData


func is_active(quest_id: StringName) -> bool:
	return active.has(quest_id)


func is_completed(quest_id: StringName) -> bool:
	return completed.has(quest_id)


func objective_progress(quest_id: StringName, objective_index: int) -> int:
	if not active.has(quest_id):
		return 0
	var progress: Array = active[quest_id]["progress"]
	return int(progress[objective_index]) if objective_index < progress.size() else 0


# --- starting and completing -----------------------------------------------

func _ensure_progress() -> void:
	if active.is_empty() and completed.is_empty():
		start_quest(FIRST_QUEST)
		return
	if active.is_empty():
		# Everything started so far is done: continue with whatever the last quest unlocks.
		for quest_id in completed:
			var quest := get_quest(quest_id)
			if quest and quest.next_quest != &"" and not completed.has(quest.next_quest):
				start_quest(quest.next_quest)


func prerequisites_met(quest_id: StringName) -> bool:
	var quest := get_quest(quest_id)
	if quest == null:
		return false
	for prerequisite in quest.prerequisites:
		if not completed.has(StringName(prerequisite)):
			return false
	return true


func start_quest(quest_id: StringName) -> bool:
	var quest := get_quest(quest_id)
	if quest == null or active.has(quest_id) or completed.has(quest_id) or not prerequisites_met(quest_id):
		return false
	var progress: Array = []
	var seen: Array = []
	var done: Array = []
	for objective in quest.objectives:
		progress.append(0)
		seen.append([])
		done.append(false)
	active[quest_id] = {"progress": progress, "seen": seen, "done": done}
	_replay_history(quest_id)
	quest_started.emit(quest_id)
	say_lines(quest.start_captions, quest.caption_seconds)
	tracker_changed.emit()
	_check_complete(quest_id)
	return true


func _replay_history(quest_id: StringName) -> void:
	var quest := get_quest(quest_id)
	for index in quest.objectives.size():
		var objective: ObjectiveData = quest.objectives[index]
		if not objective.is_set_type():
			continue
		for target in objective.targets:
			if _history.has(_history_key(objective.type, StringName(target))):
				_credit(quest_id, index, objective, StringName(target), false)
	# A flag that is already set counts too (WorldState may have been restored from a save).
	if _world != null and _world.has_method("has_flag"):
		for index in quest.objectives.size():
			var objective: ObjectiveData = quest.objectives[index]
			if objective.type == ObjectiveData.Type.FLAG:
				for target in objective.targets:
					if _world.has_flag(StringName(target)):
						_credit(quest_id, index, objective, StringName(target), false)


func _check_complete(quest_id: StringName) -> void:
	if not active.has(quest_id):
		return
	for done in active[quest_id]["done"]:
		if not done:
			return
	_complete(quest_id)


func _complete(quest_id: StringName) -> void:
	if completed.has(quest_id) or not active.has(quest_id):
		return  # duplicate protection: a quest completes (and pays out) exactly once
	var quest := get_quest(quest_id)
	active.erase(quest_id)
	completed.append(quest_id)
	if quest and not _rewarded.has(quest_id):
		_rewarded.append(quest_id)
		for item_id in quest.rewards:
			_pending_rewards.append(item_id)
	_flush_rewards()
	quest_completed.emit(quest_id)
	if quest:
		say_lines(quest.complete_captions, quest.caption_seconds)
		if quest.next_quest != &"":
			start_quest(quest.next_quest)
	tracker_changed.emit()
	if quest_id == FINAL_QUEST:
		_begin_ending(quest)


# --- rewards ---------------------------------------------------------------

## Hands queued reward items to the player. Items that cannot be delivered yet (no player in the
## scene during a reload) stay queued, and are saved, until a player exists.
func _flush_rewards() -> void:
	if _pending_rewards.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.inventory == null:
		return
	var queued := _pending_rewards.duplicate()
	_pending_rewards.clear()
	for item_id in queued:
		var item := load(QuestData.ITEM_DIR + item_id + ".tres") as ItemData
		if item:
			player.inventory.add_item(item)


# --- events ----------------------------------------------------------------

func _history_key(type: int, target: StringName) -> String:
	return "%d:%s" % [type, target]


## Central entry point for everything that can advance a quest. Public so tests (and other
## systems) can report events without going through a scene.
func notify(type: ObjectiveData.Type, target: StringName = &"", amount: int = 1, instance_id: int = 0) -> void:
	if type != ObjectiveData.Type.KILL_COUNT and type != ObjectiveData.Type.WAVE_CLEARED:
		_history[_history_key(type, target)] = true
	for quest_id in active.keys():
		if not active.has(quest_id):
			continue
		var quest := get_quest(quest_id)
		if quest == null:
			continue
		for index in quest.objectives.size():
			var objective: ObjectiveData = quest.objectives[index]
			if objective.type != type or active[quest_id]["done"][index]:
				continue
			_apply(quest_id, index, objective, target, amount, instance_id)
		_check_complete(quest_id)


func _apply(quest_id: StringName, index: int, objective: ObjectiveData, target: StringName, amount: int, instance_id: int) -> void:
	match objective.type:
		ObjectiveData.Type.KILL_COUNT:
			if not objective.targets.is_empty() and not objective.targets.has(String(target)):
				return
			if instance_id != 0:
				if _kill_ids.has(instance_id):
					return  # the same enemy never counts twice
				_kill_ids[instance_id] = true
			_set_progress(quest_id, index, objective, objective_progress(quest_id, index) + amount)
		ObjectiveData.Type.WAVE_CLEARED:
			_set_progress(quest_id, index, objective, maxi(objective_progress(quest_id, index), amount))
		_:
			if objective.targets.has(String(target)):
				_credit(quest_id, index, objective, target, true)


## Set types: each distinct target counts once.
func _credit(quest_id: StringName, index: int, objective: ObjectiveData, target: StringName, announce: bool) -> void:
	var seen: Array = active[quest_id]["seen"][index]
	if seen.has(String(target)):
		return
	seen.append(String(target))
	_set_progress(quest_id, index, objective, seen.size(), announce)


func _set_progress(quest_id: StringName, index: int, objective: ObjectiveData, value: int, announce: bool = true) -> void:
	var state: Dictionary = active[quest_id]
	var needed := objective.required()
	var clamped := mini(value, needed)
	if clamped == int(state["progress"][index]):
		return
	state["progress"][index] = clamped
	if clamped >= needed:
		state["done"][index] = true
	if announce:
		objective_updated.emit(quest_id, index, clamped, needed)
	tracker_changed.emit()


# --- signal wiring ---------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node.name == &"WorldState" and node.get_parent() == get_tree().root:
		_bind_world_state.call_deferred()
	elif node is WaveManager:
		_bind_waves(node as WaveManager)
	elif node is Enemy:
		var enemy := node as Enemy
		if not enemy.has_meta(&"quest_bound"):  # bound callables cannot be tested with is_connected
			enemy.set_meta(&"quest_bound", true)
			enemy.defeated.connect(_on_enemy_defeated.bind(enemy))
	elif node is Inventory:
		var inventory := node as Inventory
		if not inventory.item_collected.is_connected(_on_item_collected):
			inventory.item_collected.connect(_on_item_collected)
	elif node is Player:
		_on_player_added(node as Player)


func _bind_world_state() -> void:
	var world := get_node_or_null("/root/WorldState")
	if world == null or world == _world:
		return
	_world = world
	if world.has_signal("interacted"):
		world.interacted.connect(_on_interacted)
	if world.has_signal("area_entered"):
		world.area_entered.connect(_on_area_entered)
	if world.has_signal("flag_changed"):
		world.flag_changed.connect(_on_flag_changed)
	if not _world_stash.is_empty() and world.has_method("from_dict"):
		world.from_dict(_world_stash)
		_world_stash = {}
	for quest_id in active.keys():
		_replay_history(quest_id)
		_check_complete(quest_id)


func _bind_waves(waves: WaveManager) -> void:
	if not waves.wave_cleared.is_connected(_on_wave_cleared):
		waves.wave_cleared.connect(_on_wave_cleared)
	if not waves.all_cleared.is_connected(_on_all_cleared):
		waves.all_cleared.connect(_on_all_cleared)


func _on_interacted(id: StringName) -> void:
	notify(ObjectiveData.Type.INTERACT, id)


func _on_area_entered(id: StringName) -> void:
	notify(ObjectiveData.Type.ENTER_AREA, id)


func _on_flag_changed(id: StringName, value: bool) -> void:
	if value:
		notify(ObjectiveData.Type.FLAG, id)


func _on_wave_cleared(index: int) -> void:
	notify(ObjectiveData.Type.WAVE_CLEARED, &"", index)


func _on_all_cleared() -> void:
	notify(ObjectiveData.Type.WAVE_CLEARED, &"", WaveManager.WAVES.size())


func _on_item_collected(item: ItemData, kept: bool) -> void:
	if kept and item:
		notify(ObjectiveData.Type.ITEM_COLLECTED, item.item_id)


func _on_enemy_defeated(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	notify(ObjectiveData.Type.KILL_COUNT, StringName(enemy.display_name), 1, enemy.get_instance_id())
	if enemy.is_in_group("boss"):
		var boss_id := boss_id_for(enemy.display_name)
		notify(ObjectiveData.Type.BOSS_DEFEATED, boss_id)
		if boss_id == &"warden":
			# The Warden carries the command keycard: it unlocks the terminal in the final quest.
			if _world != null and _world.has_method("set_flag"):
				_world.set_flag(KEYCARD_FLAG, true)
			notify(ObjectiveData.Type.FLAG, KEYCARD_FLAG)


## "The Warden" -> &"warden".
static func boss_id_for(display_name: String) -> StringName:
	var text := display_name.strip_edges().to_lower()
	if text.begins_with("the "):
		text = text.substr(4)
	return StringName(text.replace(" ", "_"))


# --- subtitles -------------------------------------------------------------

func say(text: String, seconds: float = 4.0) -> void:
	if not text.is_empty():
		caption_requested.emit(text, seconds)


func say_lines(lines: PackedStringArray, seconds: float = 4.0) -> void:
	for line in lines:
		say(line, seconds)


# --- tracker text for the HUD ----------------------------------------------

func tracker_title() -> String:
	for quest_id in active.keys():
		var quest := get_quest(quest_id)
		if quest:
			return quest.title
	return ""


## The first unfinished objective of the current quest, with progress ("... (Switches 1/3)").
func tracker_objective() -> String:
	for quest_id in active.keys():
		var quest := get_quest(quest_id)
		if quest == null:
			continue
		var state: Dictionary = active[quest_id]
		for index in quest.objectives.size():
			if state["done"][index]:
				continue
			var objective: ObjectiveData = quest.objectives[index]
			var needed := objective.required()
			if needed > 1:
				var label := objective.progress_label if not objective.progress_label.is_empty() else "Progress"
				return "%s (%s %d/%d)" % [objective.text, label, int(state["progress"][index]), needed]
			return objective.text
	return ""


# --- intro -----------------------------------------------------------------

## Truth table for "does the opening play". Pure so tests can check every case.
static func should_play_intro(headless: bool, pending_load: bool, has_checkpoint: bool, progress_made: bool, intro_already_done: bool) -> bool:
	return not (headless or pending_load or has_checkpoint or progress_made or intro_already_done)


func _on_player_added(player: Player) -> void:
	_flush_rewards.call_deferred()
	var save_manager := get_node_or_null("/root/SaveManager")
	var pending: bool = save_manager != null and save_manager.pending_load
	var has_checkpoint: bool = save_manager != null and not save_manager.checkpoint.is_empty()
	var headless := DisplayServer.get_name() == "headless"
	if should_play_intro(headless, pending, has_checkpoint, not completed.is_empty(), intro_done):
		intro_done = true  # decided synchronously: a reload during the intro must not replay it
		_run_intro(player)
	elif not intro_done and (pending or has_checkpoint or not completed.is_empty()):
		intro_done = true


func _run_intro(player: Player) -> void:
	# Boot adds Main with processing disabled behind its loading screen; wait for the hand-over.
	while is_instance_valid(player) and not player.can_process():
		await get_tree().process_frame
	if not is_instance_valid(player):
		return
	await get_tree().create_timer(INTRO_SETTLE_SECONDS, true, false, true).timeout
	if not is_instance_valid(player) or _intro != null:
		return
	var scene := load(INTRO_SCENE) as PackedScene
	if scene == null:
		return
	_intro = scene.instantiate()
	_intro.tree_exited.connect(func() -> void: _intro = null)
	get_tree().root.add_child(_intro)


# --- ending ----------------------------------------------------------------

func _begin_ending(quest: QuestData) -> void:
	ending_started.emit()
	if DisplayServer.get_name() == "headless":
		return
	var seconds := 0.0
	if quest:
		seconds = quest.complete_captions.size() * quest.caption_seconds
	await get_tree().create_timer(seconds + 1.0, true, false, true).timeout
	if _ending != null:
		return
	var scene := load(ENDING_SCENE) as PackedScene
	if scene == null:
		return
	ending_shown = true
	_ending = scene.instantiate()
	_ending.tree_exited.connect(func() -> void: _ending = null)
	get_tree().root.add_child(_ending)


# --- save / load / reset ---------------------------------------------------

func to_dict() -> Dictionary:
	var data := {
		"active": active.duplicate(true),
		"completed": completed.map(func(id: StringName) -> String: return String(id)),
		"rewarded": _rewarded.map(func(id: StringName) -> String: return String(id)),
		"pending_rewards": _pending_rewards.duplicate(),
		"history": _history.keys(),
		"intro_done": intro_done,
	}
	if _world != null and _world.has_method("to_dict"):
		data["world"] = _world.to_dict()
	return data


## Restores quest state from (already sanitised) save data. Unknown quests are dropped, and a quest whose
## objective list changed since the save is restarted from its history instead of mis-assigning progress.
func from_dict(raw: Variant) -> void:
	var data := QuestState.sanitize(raw)
	_clear_state()
	if data.is_empty():
		_ensure_progress()
		tracker_changed.emit()
		return
	for entry in data["completed"]:
		if quests.has(StringName(entry)):
			completed.append(StringName(entry))
	for entry in data["rewarded"]:
		_rewarded.append(StringName(entry))
	for entry in data["pending_rewards"]:
		_pending_rewards.append(String(entry))
	for entry in data["history"]:
		_history[String(entry)] = true
	intro_done = bool(data["intro_done"])
	var active_data: Dictionary = data["active"]
	for key in active_data.keys():
		var quest_id := StringName(key)
		var quest := get_quest(quest_id)
		if quest == null or completed.has(quest_id):
			continue
		var entry: Dictionary = active_data[key]
		var size := quest.objectives.size()
		if entry["progress"].size() == size and entry["seen"].size() == size and entry["done"].size() == size:
			active[quest_id] = entry
		else:
			start_quest(quest_id)
	var world_data: Dictionary = data["world"]
	if not world_data.is_empty():
		if _world != null and _world.has_method("from_dict"):
			_world.from_dict(world_data)
		else:
			_world_stash = world_data
	_ensure_progress()
	_flush_rewards()
	tracker_changed.emit()


## Called by SaveManager.load_game(): quest data from the save, or none for a pre-quest save.
func on_game_loaded(raw: Variant) -> void:
	from_dict(raw)
	intro_done = true  # a continued game never replays the opening


func _clear_state() -> void:
	active.clear()
	completed.clear()
	_rewarded.clear()
	_pending_rewards.clear()
	_history.clear()
	_kill_ids.clear()
	_world_stash = {}


## A fresh run: quests, history and world flags go back to the start. The intro is not replayed
## unless `replay_intro` is set (a deliberate Restart or Play Again should not repeat it).
func reset(replay_intro: bool = false) -> void:
	_clear_state()
	ending_shown = false
	if replay_intro:
		intro_done = false
	if _world != null and _world.has_method("reset"):
		_world.reset()
	_ensure_progress()
	tracker_changed.emit()
