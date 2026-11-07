extends SceneTree
## Document index, journal tabs, collection hooks, persistence and layout.
## godot --headless --path . -s tests/journal_check.gd

const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(800, 360)]
const MIN_DOCS: Dictionary = {&"outpost_17": 5, &"dead_coast": 8, &"blackwood": 8, &"research_complex": 10}

var _failures: int = 0
var _checks: int = 0
var _world: Node
var _qm: Node
var _rm: Node
var _sm: Node


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _plain(s: String) -> bool:
	for c in s:
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return s.length() > 0


func _all_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_all_buttons(child, out)


func _run() -> void:
	_world = root.get_node("WorldState")
	_qm = root.get_node("QuestManager")
	_rm = root.get_node("RegionManager")
	_sm = root.get_node("SaveManager")
	_sm.reset_runtime_state()
	_world.reset()
	_qm.reset()
	_rm.reset()
	_test_index()
	await _test_hooks()
	await _test_tabs()
	await _test_persistence()
	await _test_pause_hook()
	await _test_layout()
	_world.reset()
	print("journal_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_index() -> void:
	print("-- index")
	var docs := DocumentIndex.all()
	_check(docs.size() >= 40, "the index holds the real documents (%d)" % docs.size())
	var keys: Dictionary = {}
	var bad_keys := 0
	var empty := 0
	var bad_cat := 0
	var long_flag := 0
	for doc in docs:
		keys[doc.key] = true
		if not _plain(String(doc.key)) or String(doc.key).length() > 30:
			bad_keys += 1
		if doc.body.strip_edges() == "" or doc.title.strip_edges() == "":
			empty += 1
		if not doc.category in DocumentData.CATEGORIES:
			bad_cat += 1
		if String(DocumentIndex.flag_for(doc.key)).length() > 48:
			long_flag += 1
	_check(keys.size() == docs.size(), "every key is unique")
	_check(bad_keys == 0, "every key is [a-z0-9_] and at most 30 characters (%d bad)" % bad_keys)
	_check(long_flag == 0, "every collected flag fits the 48 character limit (%d bad)" % long_flag)
	_check(empty == 0, "no document has an empty title or body (%d)" % empty)
	_check(bad_cat == 0, "every category is known (%d bad)" % bad_cat)
	for region in MIN_DOCS:
		var n := DocumentIndex.by_region(region).size()
		print("  INFO ", region, " documents: ", n)
		_check(n >= int(MIN_DOCS[region]), "%s has its documents indexed (%d)" % [region, n])


func _test_hooks() -> void:
	print("-- collection hooks")
	var doc: DocumentData = DocumentIndex.by_region(&"dead_coast")[0]
	_check(not DocumentIndex.is_collected(doc.key), "a document starts uncollected")
	var lore := LoreDocument.new()
	lore.interaction_id = doc.source_id
	lore.title = doc.title
	lore.body_text = doc.body
	root.add_child(lore)
	await _frames(2)
	lore._on_interact(null)
	_check(DocumentIndex.is_collected(doc.key), "reading a LoreDocument collects it")
	_check(DocumentIndex.mark_collected(doc.source_id).is_empty(), "collecting twice reports nothing new")
	lore.queue_free()
	var other: DocumentData = DocumentIndex.by_region(&"blackwood")[0]
	var term := Terminal.new()
	term.interaction_id = other.source_id
	term.pages = PackedStringArray([other.body])
	root.add_child(term)
	await _frames(2)
	term._on_interact(null)
	_check(DocumentIndex.is_collected(other.key), "reading a Terminal collects it")
	term.queue_free()
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	var notes: Array[Node] = main.find_children("*", "RpgNotifications", true, false)
	_check(notes.size() == 1, "Main has the notification layer")
	if notes.size() == 1:
		var toasts: Control = notes[0].get("_toasts")
		var before := toasts.get_child_count()
		get_first_node_in_group("rpg_notifications").notify_document("Test document")
		_check(toasts.get_child_count() == before + 1, "a discovery toast appears")
	main.queue_free()
	await _frames(4)


func _journal() -> JournalScreen:
	var j := JournalScreen.new()
	root.add_child(j)
	return j


func _test_tabs() -> void:
	print("-- tabs")
	_world.reset()
	_qm.reset()
	_rm.reset()
	var j := _journal()
	await _frames(2)
	j.open()
	await _frames(2)
	j.set_tab(&"main")
	var text := j.page_text()
	_check("Outpost 17: In progress" in text, "Main shows Outpost 17 in progress")
	_check("Dead Coast: Locked" in text and "???" in text, "a locked region shows only the question marks")
	_check("Wreckage" not in text, "a locked region's missions are not listed")
	_rm.unlock(&"dead_coast")
	j.set_tab(&"main")
	text = j.page_text()
	_check("Dead Coast: In progress" in text and "[locked] Wreckage" in text, "an unlocked region lists its missions")
	_qm.start_quest(&"first_signal")
	j.set_tab(&"main")
	text = j.page_text()
	_check("[current] The First Signal:" in text, "an active mission shows its current objective")
	j.set_tab(&"side")
	text = j.page_text()
	_check("[open]" in text and "The First Signal" in text, "Side lists the optional objective of the first mission")
	var coast := DocumentIndex.by_region(&"dead_coast")
	var got: DocumentData = coast[0]
	var hidden: DocumentData = coast[coast.size() - 1]
	DocumentIndex.mark_collected(got.source_id)
	j.set_tab(&"documents")
	text = j.page_text()
	_check(got.title in text, "a collected document is listed by title")
	_check("???  (Dead Coast)" in text, "an uncollected document shows only the question marks and its region")
	_check(hidden.title not in text and hidden.body not in text, "an uncollected document's title and text are hidden")
	j.select_document(got.key)
	text = j.page_text()
	_check(got.body.substr(0, 20) in text, "selecting a collected document shows its text")
	j.select_document(hidden.key)
	_check(hidden.body not in j.page_text(), "an uncollected document cannot be opened")
	j.set_tab(&"story")
	_check("Nothing discovered yet." in j.page_text(), "Story starts empty")
	_world.set_flag(&"mission_first_signal_complete", true)
	j.set_tab(&"story")
	text = j.page_text()
	_check("The signal and the Black Site" in text and "The man behind it" not in text, "a revelation appears only after its flag")
	j.set_tab(&"regions")
	text = j.page_text()
	_check("Dead Coast: Available" in text and "Blackwood: Locked" in text, "Regions shows availability")
	_world.set_flag(&"dead_coast_region_complete", true)
	j.set_tab(&"regions")
	_check("Dead Coast: Completed" in j.page_text(), "Regions shows a completed region")
	j.close()
	j.queue_free()
	await _frames(2)


func _test_persistence() -> void:
	print("-- persistence")
	_sm.reset_runtime_state()
	_world.reset()
	_qm.reset()
	_rm.reset()
	var doc: DocumentData = DocumentIndex.by_region(&"research_complex")[2]
	DocumentIndex.mark_collected(doc.source_id)
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_check(not DocumentIndex.is_collected(doc.key), "a reset clears collected documents")
	_world.from_dict(saved)
	_check(DocumentIndex.is_collected(doc.key), "collected documents survive a real WorldState save and load")
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	_check(_sm.save_game("manual"), "the game saves")
	main.queue_free()
	await _frames(4)
	_world.reset()
	_qm.reset()
	_rm.reset()
	_check(not DocumentIndex.is_collected(doc.key), "wiped state has no collected documents")
	_check(_sm.load_game(), "the save loads")
	var main2: Node = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main2)
	await _frames(14)
	_check(DocumentIndex.is_collected(doc.key), "collected documents survive a real SaveManager save and load")
	main2.queue_free()
	await _frames(4)
	_world.reset()


func _test_pause_hook() -> void:
	print("-- pause menu")
	var main: Node = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	await _frames(6)
	var menus: Array[Node] = main.find_children("*", "PauseMenu", true, false)
	_check(menus.size() == 1, "Main has the pause menu")
	if menus.size() == 1:
		var menu: Node = menus[0]
		menu.show_journal()
		await _frames(2)
		var journal: JournalScreen = menu.get("_journal_screen")
		_check(journal != null and journal.is_open(), "the pause menu opens the journal")
		_check(menu._rpg_screen_open(), "an open journal counts as an open RPG screen")
		journal.close()
		menu.close()
	main.queue_free()
	await _frames(4)


func _test_layout() -> void:
	print("-- layout")
	var j := _journal()
	await _frames(2)
	var scale_mode := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var doc: DocumentData = DocumentIndex.by_region(&"blackwood")[0]
	DocumentIndex.mark_collected(doc.source_id)
	for size in SIZES:
		root.size = size
		await _frames(3)
		for tab in JournalScreen.TABS:
			j.open()
			j.set_tab(tab)
			if tab == &"documents":
				j.select_document(doc.key)
			await _frames(3)
			var name := "journal %s %dx%d" % [tab, size.x, size.y]
			var panel := j.root_control().get_child(1).get_child(0) as Control
			_check(Rect2(Vector2.ZERO, Vector2(size)).encloses(panel.get_global_rect().grow(-0.5)), "%s: panel fits" % name)
			var buttons: Array[Button] = []
			_all_buttons(j.root_control(), buttons)
			var short := 0
			for button in buttons:
				if button.is_visible_in_tree() and button.get_global_rect().size.y < RpgUi.TOUCH_HEIGHT - 0.5 and button.size.y > 0.0:
					short += 1
			_check(short == 0, "%s: buttons are at least 56 px tall (%d short)" % [name, short])
			var overlaps := 0
			for a in buttons.size():
				for b in range(a + 1, buttons.size()):
					if buttons[a].is_visible_in_tree() and buttons[b].is_visible_in_tree() \
							and buttons[a].get_global_rect().grow(-1.0).intersects(buttons[b].get_global_rect().grow(-1.0)):
						overlaps += 1
			_check(overlaps == 0, "%s: no overlapping buttons (%d)" % [name, overlaps])
			j.close()
			await _frames(2)
	root.size = SIZES[0]
	root.content_scale_mode = scale_mode
	j.queue_free()
