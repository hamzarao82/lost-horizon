class_name CampaignAudit
extends RefCounted
## Read-only helpers shared by tools/campaign_audit.gd and tests/story_continuity_check.gd.
## Nothing here writes a file or changes a resource. Producer checks are TEXT heuristics: a flag counts as
## produced when its literal appears in a script (or matches a known dynamically built pattern); that is
## evidence, not proof, and the callers say so.

const QUEST_ROOT: String = "res://resources/quests"
const REGION_ROOT: String = "res://resources/regions"
const SCRIPT_ROOT: String = "res://scripts"
const FLAG_RULE: String = "^[a-z0-9_]{1,48}$"

static var _script_cache: Dictionary = {}


static func files_under(root: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := root.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				out.append_array(files_under(path, ext))
		elif name.ends_with(ext) or name.ends_with(ext + ".remap"):
			out.append(path.trim_suffix(".remap"))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in files_under(QUEST_ROOT, ".tres"):
		var quest := load(path) as QuestData
		out.append({"path": path, "quest": quest})
	return out


static func region_of_quest_path(path: String) -> String:
	var folder := path.get_base_dir().get_file()
	return folder if folder in ["dead_coast", "blackwood", "research_complex", "iron_fortress"] else "outpost_17"


static func regions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in files_under(REGION_ROOT, ".tres"):
		var data := load(path) as RegionData
		if data != null:
			out.append({"path": path, "data": data})
	return out


static func script_texts() -> Dictionary:
	if _script_cache.is_empty():
		for path in files_under(SCRIPT_ROOT, ".gd"):
			_script_cache[path] = FileAccess.get_file_as_string(path)
	return _script_cache


## Files whose text contains the literal (as `"x"` or `&"x"`).
static func script_refs(literal: String) -> Array[String]:
	var out: Array[String] = []
	var needle := "\"%s\"" % literal
	var texts := script_texts()
	for path in texts:
		if String(texts[path]).contains(needle):
			out.append(String(path))
	return out


static func flag_name_ok(flag: String) -> bool:
	var re := RegEx.new()
	re.compile(FLAG_RULE)
	return re.search(flag) != null


## Constant of a script file without instantiating it (works for autoload scripts in a SceneTree run).
static func script_constant(path: String, const_name: String) -> Variant:
	var script := load(path) as GDScript
	if script == null:
		return null
	return script.get_script_constant_map().get(const_name, null)


## Story documents found in the builders: {id, title, body, region, source}.
static func documents() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Outpost 17: LoreDocument variables set field by field, then placed with an id.
	var o17 := FileAccess.get_file_as_string("res://scripts/world/outpost17.gd")
	var title_re := RegEx.new()
	title_re.compile("(\\w+)\\.title = \"([^\"]*)\"")
	var body_re := RegEx.new()
	body_re.compile("(\\w+)\\.body_text = \"([^\"]*)\"")
	var place_re := RegEx.new()
	place_re.compile("_place\\((\\w+), &\"(\\w+)\"")
	var titles: Dictionary = {}
	var bodies: Dictionary = {}
	for line in o17.split("\n"):
		var m := title_re.search(line)
		if m != null:
			titles[m.get_string(1)] = m.get_string(2)
		m = body_re.search(line)
		if m != null:
			bodies[m.get_string(1)] = m.get_string(2)
		m = place_re.search(line)
		if m != null and bodies.has(m.get_string(1)):
			out.append({"id": m.get_string(2), "title": String(titles.get(m.get_string(1), "")),
					"body": String(bodies[m.get_string(1)]), "region": "outpost_17", "source": "outpost17.gd"})
	# Dead Coast: doc("id", "title", "text", ...)
	_scan_calls(out, "res://scripts/regions/dead_coast/dead_coast_content.gd", "dead_coast", "doc\\(\"(\\w+)\", \"([^\"]*)\",\\s*\"([^\"]*)\"")
	# Blackwood: _add_doc(&"id", "title", pos, "text") spanning two lines; the text is on the next line
	_scan_blackwood(out)
	# Research Complex: DOCS dictionary of pages
	var rc: Variant = script_constant("res://scripts/regions/research_complex/research_complex_story.gd", "DOCS")
	if rc is Dictionary:
		for id in rc:
			var entry: Dictionary = rc[id]
			out.append({"id": String(id), "title": String(entry.get("title", "")),
					"body": "\n".join(PackedStringArray(entry.get("pages", []))), "region": "research_complex",
					"source": "research_complex_story.gd"})
	return out


static func _scan_calls(out: Array[Dictionary], path: String, region: String, pattern: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	var re := RegEx.new()
	re.compile(pattern)
	for m in re.search_all(text):
		out.append({"id": m.get_string(1), "title": m.get_string(2), "body": m.get_string(3), "region": region,
				"source": path.get_file()})


static func _scan_blackwood(out: Array[Dictionary]) -> void:
	var path := "res://scripts/regions/blackwood/blackwood.gd"
	var text := FileAccess.get_file_as_string(path)
	var re := RegEx.new()
	re.compile("_add_doc\\(&\"(\\w+)\", \"([^\"]*)\",[^\\n]*\\n\\s*\"([^\"]*)\"")
	for m in re.search_all(text):
		out.append({"id": m.get_string(1), "title": m.get_string(2), "body": m.get_string(3), "region": "blackwood",
				"source": path.get_file()})


static func words(text: String) -> Dictionary:
	var set: Dictionary = {}
	for w in text.to_lower().split(" ", false):
		var clean := w.strip_edges().trim_prefix("'").trim_suffix(".").trim_suffix(",")
		if clean.length() > 3:
			set[clean] = true
	return set


## Jaccard similarity of two documents' word sets (0 to 1).
static func similarity(a: String, b: String) -> float:
	var wa := words(a)
	var wb := words(b)
	if wa.is_empty() or wb.is_empty():
		return 0.0
	var shared := 0
	for w in wa:
		if wb.has(w):
			shared += 1
	return float(shared) / float(wa.size() + wb.size() - shared)


## Does this flag have a producer? Returns {ok, how}. Dynamic names built by format strings are matched by pattern.
static func flag_producer(flag: String, doc_ids: Array[String], region_ids: Array[String]) -> Dictionary:
	var refs := script_refs(flag)
	if not refs.is_empty():
		return {"ok": true, "how": "literal in %s" % ", ".join(PackedStringArray(refs.map(func(p: String) -> String: return p.get_file())))}
	var re := RegEx.new()
	re.compile("^doc_(\\w+)_found$")
	var m := re.search(flag)
	if m != null and doc_ids.has(m.get_string(1)):
		return {"ok": true, "how": "dynamic: LoreDocument sets doc_<id>_found"}
	re.compile("^(\\w+)_unlocked$")
	m = re.search(flag)
	if m != null and region_ids.has(m.get_string(1)):
		return {"ok": true, "how": "dynamic: CampaignFlow derives <region>_unlocked"}
	re.compile("^(\\w+)_mission_(\\d)_complete$")
	m = re.search(flag)
	if m != null and region_ids.has(m.get_string(1)):
		return {"ok": true, "how": "dynamic: CampaignFlow.mark_mission_complete(region, n)"}
	for entry in DYNAMIC_FLAGS:
		re.compile(String(entry["pattern"]))
		if re.search(flag) != null:
			return {"ok": true, "how": "dynamic: %s" % entry["how"]}
	return {"ok": false, "how": "no literal or known dynamic producer found"}


## Interaction ids built from a format string (confirmed in code: blackwood.gd `"bw_test_equipment_%d"`).
static func interact_target_known(target: String) -> bool:
	return not script_refs(target).is_empty() or target.begins_with("bw_test_equipment_")


## Flag names built by format strings, each confirmed in code when this audit was written.
const DYNAMIC_FLAGS: Array[Dictionary] = [
	{"pattern": "^patrol_\\w+_cleared$", "how": "PatrolGroup sets patrol_<id>_cleared (patrol_group.gd:23)"},
	{"pattern": "^door_\\w+_open$", "how": "Door sets door_<id>_open (door.gd:41)"},
	{"pattern": "^credential_\\w+$", "how": "AccessPanel sets credential_<level> (facility_ids.gd:10)"},
	{"pattern": "^\\w+_taken$", "how": "SupplyCrate sets <crate_id>_taken (supply_crate.gd:32)"},
	{"pattern": "^blackwood_\\w+_cleared$", "how": "BlackwoodEncounter sets blackwood_<id>_cleared (blackwood_encounter.gd:36)"},
]
