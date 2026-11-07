extends SceneTree
## Scans the real regions for LoreDocument and Terminal nodes and writes resources/story/documents/*.tres.
## The text is copied from the world objects. Run: godot --headless --path . -s tools/gen_document_index.gd
## Rerun after adding documents or a region (add its scene to REGIONS).

const REGIONS: Array = [
	[&"outpost_17", "res://scenes/main/Main.tscn"],
	[&"dead_coast", "res://scenes/regions/DeadCoastRegion.tscn"],
	[&"blackwood", "res://scenes/regions/BlackwoodRegion.tscn"],
	[&"research_complex", "res://scenes/regions/ResearchComplexRegion.tscn"],
	[&"iron_fortress", "res://scenes/regions/IronFortressRegion.tscn"],
]
const OUT: String = "res://resources/story/documents/"
const KEY_MAX: int = 30

var _report: Array[String] = []
var _seen_keys: Dictionary = {}


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for old in DirAccess.get_files_at(OUT):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + old))
	var total := 0
	for entry in REGIONS:
		var region: StringName = entry[0]
		if not ResourceLoader.exists(entry[1]):
			_report.append("%s: scene missing, skipped" % region)
			continue
		var scene := load(entry[1]) as PackedScene
		var node := scene.instantiate()
		root.add_child(node)
		for i in 6:
			await physics_frame
		if node.get_child_count() < 3 and node.has_method("build"):
			node.call("build")
			for i in 3:
				await physics_frame
		var n := _scan(region, node)
		_report.append("%s: %d documents" % [region, n])
		total += n
		node.queue_free()
		for i in 3:
			await physics_frame
	for line in _report:
		print("INDEX ", line)
	print("INDEX total ", total)
	quit()


func _scan(region: StringName, node: Node) -> int:
	var found: Array[Node] = []
	found.append_array(node.find_children("*", "LoreDocument", true, false))
	found.append_array(node.find_children("*", "Terminal", true, false))
	var order := 0
	var count := 0
	var by_source: Dictionary = {}
	for item in found:
		var source := StringName(String(item.get("interaction_id")))
		if source == &"" or by_source.has(source):
			continue
		var title: String = ""
		var body: String = ""
		if item is LoreDocument:
			title = item.title
			body = item.body_text
		else:
			title = item.terminal_title
			body = "\n".join(item.pages)
		if body.strip_edges() == "":
			_report.append("EMPTY body skipped: %s / %s" % [region, source])
			continue
		by_source[source] = true
		var doc := DocumentData.new()
		doc.source_id = source
		doc.key = _make_key(region, source)
		doc.title = title
		doc.body = body
		doc.region = region
		doc.order = order
		doc.category = _category(title, body)
		order += 1
		var err := ResourceSaver.save(doc, OUT + "%s.tres" % doc.key)
		if err != OK:
			_report.append("SAVE FAILED: %s" % doc.key)
		count += 1
	return count


func _make_key(region: StringName, source: StringName) -> StringName:
	var prefix := {"outpost_17": "o17", "dead_coast": "dc", "blackwood": "bw", "research_complex": "rc", "iron_fortress": "if"}.get(region, "x") as String
	var raw := ("%s_%s" % [prefix, String(source).to_lower()]).replace("-", "_").replace(" ", "_")
	var clean := ""
	for c in raw:
		clean += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" else "_"
	if clean.length() > KEY_MAX:
		clean = clean.substr(0, KEY_MAX - 5) + "_" + str(absi(clean.hash()) % 10000).pad_zeros(4)
	while _seen_keys.has(clean):
		_report.append("DUPLICATE key %s" % clean)
		clean = clean.substr(0, mini(clean.length(), KEY_MAX - 2)) + "_x"
	_seen_keys[clean] = true
	return StringName(clean)


## Heuristic: the first matching rule wins. Categories are a reading aid, not canon.
func _category(title: String, body: String) -> StringName:
	var t := (title + " " + body).to_lower()
	if "personnel" in t or "service record" in t or "patient" in t or "roster" in t:
		return &"personnel_file"
	if "incident" in t or "breach" in t or "containment failure" in t or "after-action" in t:
		return &"incident_report"
	if "radio" in t or "transmission" in t or "frequency" in t or "signal log" in t or "message" in t:
		return &"communication"
	if "experiment" in t or "subject" in t or "research" in t or "laboratory" in t or "specimen" in t or "trial" in t:
		return &"research_record"
	if "classified" in t or "black site" in t or "director" in t or "eyes only" in t:
		return &"classified"
	if "diary" in t or "personal" in t or "letter" in t or "note to" in t or "dear " in t:
		return &"personal_note"
	return &"military_intelligence"
