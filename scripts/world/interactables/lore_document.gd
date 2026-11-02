class_name LoreDocument
extends Interactable
## A readable log or document. Reading it sets `doc_<id>_found` (counts for the optional objective)
## and can be repeated.

@export var title: String = "Document"
@export_multiline var body_text: String = ""


func _ready() -> void:
	super._ready()
	prompt_text = "Read %s" % title.to_lower()
	interact_radius = maxf(interact_radius, 2.2)


func found_flag() -> StringName:
	return StringName("doc_%s_found" % String(interaction_id))


func _on_interact(_player: Node3D) -> void:
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.set_flag(found_flag(), true)
	var text := "%s: %s" % [title, body_text]
	Outpost17.say(self, text, clampf(3.5 + text.length() * 0.05, 5.0, 10.0))
