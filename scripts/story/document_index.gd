class_name DocumentIndex
extends RefCounted
## Read-only catalogue of every story document plus the saved "collected" state. Collected state lives in
## WorldState flags named `journal_collected_<key>` (underscore only, the save drops anything else).

const DIR: String = "res://resources/story/documents/"
const FLAG_PREFIX: String = "journal_collected_"
const REGION_NAMES: Dictionary = {
	&"outpost_17": "Outpost 17", &"dead_coast": "Dead Coast", &"blackwood": "Blackwood",
	&"research_complex": "Research Complex", &"iron_fortress": "Iron Fortress",
}
const CATEGORY_NAMES: Dictionary = {
	&"military_intelligence": "Military intelligence", &"research_record": "Research records",
	&"personnel_file": "Personnel files", &"incident_report": "Incident reports",
	&"communication": "Communications", &"classified": "Classified", &"personal_note": "Personal notes",
}

static var _docs: Array[DocumentData] = []
static var _loaded: bool = false


static func all() -> Array[DocumentData]:
	_load()
	return _docs


static func reload() -> void:
	_loaded = false


static func by_region(region: StringName) -> Array[DocumentData]:
	var out: Array[DocumentData] = []
	for doc in all():
		if doc.region == region:
			out.append(doc)
	return out


static func find(key: StringName) -> DocumentData:
	for doc in all():
		if doc.key == key:
			return doc
	return null


static func with_source(source_id: StringName) -> Array[DocumentData]:
	var out: Array[DocumentData] = []
	for doc in all():
		if doc.source_id == source_id:
			out.append(doc)
	return out


static func flag_for(key: StringName) -> StringName:
	return StringName(FLAG_PREFIX + String(key))


static func is_collected(key: StringName) -> bool:
	var world := _world()
	return world != null and world.has_flag(flag_for(key))


static func collected_count(region: StringName = &"") -> int:
	var n := 0
	for doc in all():
		if (region == &"" or doc.region == region) and is_collected(doc.key):
			n += 1
	return n


## Marks the documents that come from this world object as collected. Returns the titles that are NEW.
static func mark_collected(source_id: StringName) -> Array[String]:
	var fresh: Array[String] = []
	var world := _world()
	if world == null:
		return fresh
	for doc in with_source(source_id):
		if not world.has_flag(flag_for(doc.key)):
			world.set_flag(flag_for(doc.key), true)
			fresh.append(doc.title)
	return fresh


static func region_name(region: StringName) -> String:
	return String(REGION_NAMES.get(region, String(region).capitalize()))


static func category_name(category: StringName) -> String:
	return String(CATEGORY_NAMES.get(category, String(category).capitalize()))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_docs.clear()
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for file in files:
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var doc := load(DIR + name) as DocumentData
		if doc != null and doc.key != &"":
			_docs.append(doc)
	_docs.sort_custom(func(a: DocumentData, b: DocumentData) -> bool:
		if a.region != b.region:
			return String(a.region) < String(b.region)
		return a.order < b.order)


static func _world() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("WorldState") if loop else null
