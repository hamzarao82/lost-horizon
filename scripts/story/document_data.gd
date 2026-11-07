class_name DocumentData
extends Resource
## One readable story document (a log, record or terminal entry). Indexed by tools/gen_document_index.gd
## from the real world objects; the body is copied from them, never rewritten.

const CATEGORIES: Array[StringName] = [
	&"military_intelligence", &"research_record", &"personnel_file", &"incident_report",
	&"communication", &"classified", &"personal_note",
]

## Unique key, [a-z0-9_] and at most 30 characters so `journal_collected_<key>` fits the 48 character flag limit.
@export var key: StringName
## The interaction id of the LoreDocument or Terminal in the world.
@export var source_id: StringName
@export var title: String
@export var category: StringName = &"military_intelligence"
@export var region: StringName = &"outpost_17"
@export_multiline var body: String
## Sort order inside its region and category (scan order).
@export var order: int = 0
