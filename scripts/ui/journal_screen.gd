class_name JournalScreen
extends RpgScreen
## Campaign journal: Main, Side, Documents, Story and Regions tabs. It only READS existing data (quests,
## flags, the region manager, the document index); there is no second quest or map system. The page is
## rebuilt when it opens, when a tab changes and when a flag changes while it is open, never per frame.

const TABS: Array[StringName] = [&"main", &"side", &"documents", &"story", &"regions"]
const TAB_NAMES: Dictionary = {
	&"main": "Main", &"side": "Side", &"documents": "Documents", &"story": "Story", &"regions": "Regions",
}
const REGIONS: Array[StringName] = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
## Missions in campaign order. Quests that are not loaded (a region that is not built yet) are skipped.
const MISSIONS: Dictionary = {
	&"outpost_17": [&"first_signal", &"leave_outpost"],
	&"dead_coast": [&"dc_wreckage", &"dc_silent_checkpoint", &"dc_lost_cargo"],
	&"blackwood": [&"into_the_blackwood", &"ghost_frequency", &"experimental_site"],
	&"research_complex": [&"rc_restricted_zone", &"rc_silent_records", &"rc_containment_breach", &"rc_project_black_site"],
	&"iron_fortress": [],
}
## Older side quests of the first region (the arena chain).
const SIDE_QUESTS: Array[StringName] = [&"restore_power", &"broken_perimeter", &"final_transmission"]
## Revelations shown in the Story tab once their flag is set. Short, and no more than the documents say.
const STORY_BEATS: Array = [
	[&"mission_first_signal_complete", "The signal and the Black Site",
		"The signal led to a command post that still holds records about Project Black Site, run by someone called the Director."],
	[&"dead_coast_mission_3_complete", "The abandoned shipment",
		"A military shipment was left on the coast, and its trail leads back to Project Black Site."],
	[&"blackwood_mission_3_complete", "The hidden research trail",
		"A hidden communications station and a testing site show that people were being experimented on."],
	[&"research_complex_region_complete", "A deliberate program",
		"The experiments were organized, and the containment failure was not an ordinary accident. The recovered data points to the Iron Fortress."],
	[&"iron_fortress_director_defeated", "The man behind it",
		"The Director, head of Project Black Site, has been confronted at the Iron Fortress."],
]

var _tab: StringName = &"main"
var _tab_row: HFlowContainer
var _page: VBoxContainer
var _selected_doc: StringName = &""
var _bound_world: Node


func _init() -> void:
	super._init()
	title_text = "Journal"


func _build_content() -> void:
	_tab_row = HFlowContainer.new()
	_tab_row.add_theme_constant_override("h_separation", 8)
	_tab_row.add_theme_constant_override("v_separation", 6)
	content.add_child(_tab_row)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 8)
	content.add_child(_page)
	for tab in TABS:
		_tab_row.add_child(RpgUi.button(String(TAB_NAMES[tab]), set_tab.bind(tab), 130.0))


func tab() -> StringName:
	return _tab


func set_tab(tab_id: StringName) -> void:
	if tab_id in TABS:
		_tab = tab_id
		_selected_doc = &""
		refresh()


func select_document(key: StringName) -> void:
	var doc := DocumentIndex.find(key)
	if doc != null and DocumentIndex.is_collected(key):
		_selected_doc = key
		refresh()


func _connect_sources() -> void:
	var world := get_node_or_null("/root/WorldState")
	if world != null and world != _bound_world:
		_bound_world = world
		world.flag_changed.connect(_on_flag_changed)


func _on_flag_changed(_id: StringName, _value: bool) -> void:
	if is_open():
		refresh()


func refresh() -> void:
	if _page == null:
		return
	RpgUi.clear(_page)
	match _tab:
		&"main":
			_build_main()
		&"side":
			_build_side()
		&"documents":
			_build_documents()
		&"story":
			_build_story()
		&"regions":
			_build_regions()
	var total := DocumentIndex.all().size()
	set_status("%s tab. Documents %d / %d." % [TAB_NAMES[_tab], DocumentIndex.collected_count(), total])


# --- data helpers -----------------------------------------------------------

func _quests() -> Node:
	return get_node_or_null("/root/QuestManager")


func _flag(id: StringName) -> bool:
	var world := get_node_or_null("/root/WorldState")
	return world != null and world.has_flag(id)


func _unlocked(region: StringName) -> bool:
	if region == &"outpost_17":
		return true
	var manager := get_node_or_null("/root/RegionManager")
	if manager != null and manager.has_method("is_unlocked"):
		return manager.is_unlocked(region)
	return false


func _quest(quest_id: StringName) -> QuestData:
	var quests := _quests()
	return quests.get_quest(quest_id) if quests != null else null


func _state(quest_id: StringName) -> String:
	var quests := _quests()
	if quests == null or _quest(quest_id) == null:
		return "missing"
	if quests.is_completed(quest_id):
		return "done"
	if quests.is_active(quest_id):
		return "active"
	return "locked"


## The first unfinished required objective of a quest, with progress.
func _current_objective(quest_id: StringName) -> String:
	var quest := _quest(quest_id)
	var quests := _quests()
	if quest == null or quests == null:
		return ""
	for i in quest.objectives.size():
		var objective := quest.objectives[i]
		if objective.optional:
			continue
		var need := maxi(objective.count, 1)
		var have: int = quests.objective_progress(quest_id, i)
		if have < need:
			return objective.text if need <= 1 else "%s (%d/%d)" % [objective.text, have, need]
	return ""


func region_complete(region: StringName) -> bool:
	if _flag(StringName(String(region) + "_region_complete")):
		return true
	var ids: Array = MISSIONS.get(region, [])
	var known := 0
	for quest_id in ids:
		if _state(quest_id) == "missing":
			continue
		known += 1
		if _state(quest_id) != "done":
			return false
	return known > 0


func missions_done(region: StringName) -> Vector2i:
	var done := 0
	var total := 0
	for quest_id in MISSIONS.get(region, []):
		if _state(quest_id) == "missing":
			continue
		total += 1
		if _state(quest_id) == "done":
			done += 1
	return Vector2i(done, total)


func _line(text: String, color: Color = HudTheme.TEXT, size: int = HudTheme.FONT_BODY) -> Label:
	var node := RpgUi.label(text, size, color)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_child(node)
	return node


func _heading(text: String) -> void:
	_line(text, HudTheme.GOLD, HudTheme.FONT_BODY + 2)


# --- tabs -------------------------------------------------------------------

func _build_main() -> void:
	for region in REGIONS:
		var status := "Completed" if region_complete(region) else ("In progress" if _unlocked(region) else "Locked")
		_heading("%s: %s" % [DocumentIndex.region_name(region), status])
		if not _unlocked(region):
			_line("???", HudTheme.TEXT_DIM)
			continue
		var shown := 0
		for quest_id in MISSIONS.get(region, []):
			var state := _state(quest_id)
			if state == "missing":
				continue
			shown += 1
			var quest := _quest(quest_id)
			match state:
				"done":
					_line("[done] %s" % quest.title, RpgUi.GOOD)
				"active":
					_line("[current] %s: %s" % [quest.title, _current_objective(quest_id)], HudTheme.TEXT)
				_:
					_line("[locked] %s" % quest.title, HudTheme.TEXT_DIM)
		if shown == 0:
			_line("No missions yet.", HudTheme.TEXT_DIM)


func _build_side() -> void:
	var any := false
	for region in REGIONS:
		for quest_id in MISSIONS.get(region, []):
			var quest := _quest(quest_id)
			if quest == null:
				continue
			for objective in quest.objectives:
				if not objective.optional:
					continue
				any = true
				var hidden: bool = objective.hidden_until != &"" and not _flag(objective.hidden_until)
				var done := _optional_done(quest_id, quest, objective)
				var label := "???" if hidden else objective.text
				_line("[%s] %s (%s: %s)" % ["done" if done else "open", label, DocumentIndex.region_name(region), quest.title],
						RpgUi.GOOD if done else HudTheme.TEXT)
	for quest_id in SIDE_QUESTS:
		var quest := _quest(quest_id)
		if quest == null:
			continue
		any = true
		var state := _state(quest_id)
		_line("[%s] %s (Outpost 17)" % [("done" if state == "done" else ("open" if state == "active" else "locked")), quest.title],
				RpgUi.GOOD if state == "done" else HudTheme.TEXT)
	if not any:
		_line("No side objectives yet.", HudTheme.TEXT_DIM)


func _optional_done(quest_id: StringName, quest: QuestData, objective: ObjectiveData) -> bool:
	var quests := _quests()
	if quests == null:
		return false
	var index := quest.objectives.find(objective)
	return index >= 0 and quests.objective_progress(quest_id, index) >= maxi(objective.count, 1)


func _build_documents() -> void:
	if _selected_doc != &"":
		var doc := DocumentIndex.find(_selected_doc)
		if doc != null and DocumentIndex.is_collected(_selected_doc):
			_heading(doc.title)
			_line("%s, %s" % [DocumentIndex.region_name(doc.region), DocumentIndex.category_name(doc.category)],
					HudTheme.TEXT_DIM, HudTheme.FONT_SMALL)
			_line(doc.body)
			_page.add_child(HSeparator.new())
	for category in DocumentData.CATEGORIES:
		var docs: Array[DocumentData] = []
		for doc in DocumentIndex.all():
			if doc.category == category:
				docs.append(doc)
		if docs.is_empty():
			continue
		var got := 0
		for doc in docs:
			if DocumentIndex.is_collected(doc.key):
				got += 1
		_heading("%s (%d / %d)" % [DocumentIndex.category_name(category), got, docs.size()])
		for doc in docs:
			if DocumentIndex.is_collected(doc.key):
				var button := RpgUi.button(doc.title, select_document.bind(doc.key))
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_page.add_child(button)
			else:
				_line("???  (%s)" % DocumentIndex.region_name(doc.region), HudTheme.TEXT_DIM)


func _build_story() -> void:
	var found := 0
	for beat in STORY_BEATS:
		if _flag(beat[0]):
			found += 1
			_heading(String(beat[1]))
			_line(String(beat[2]))
		else:
			_line("???", HudTheme.TEXT_DIM)
	if found == 0:
		_line("Nothing discovered yet.", HudTheme.TEXT_DIM)


func _build_regions() -> void:
	for region in REGIONS:
		var status := "Completed" if region_complete(region) else ("Available" if _unlocked(region) else "Locked")
		_heading("%s: %s" % [DocumentIndex.region_name(region), status])
		if not _unlocked(region):
			_line("Locked.", HudTheme.TEXT_DIM)
			continue
		var m := missions_done(region)
		var docs := DocumentIndex.by_region(region).size()
		_line("Missions %d / %d. Documents %d / %d." % [m.x, m.y, DocumentIndex.collected_count(region), docs])


## Every label and button text on the open page, for tests and screen-reader style checks.
func page_text() -> String:
	var parts: PackedStringArray = []
	_collect_text(_page, parts)
	return "\n".join(parts)


func _collect_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label or node is Button:
		parts.append(node.text)
	for child in node.get_children():
		_collect_text(child, parts)
