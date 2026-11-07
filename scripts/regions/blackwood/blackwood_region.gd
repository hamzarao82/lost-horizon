class_name BlackwoodRegion
extends Region
## Region-contract adapter around the self-contained Blackwood builder (see DeadCoastRegion).

const ENTRY_ALIASES: Dictionary = {
	&"from_coast": &"from_dead_coast", &"from_dead_coast": &"from_dead_coast", &"": &"from_dead_coast",
}
const EXIT_TARGETS: Dictionary = {
	&"to_dead_coast": {"region": &"dead_coast", "entry": &"from_blackwood"},
	&"to_research_complex": {"region": &"research_complex", "entry": &"from_blackwood"},
}

var content: Blackwood


func _ready() -> void:
	content = Blackwood.new()
	content.density = 0.4 if OS.has_feature("web") or OS.has_feature("mobile") else 1.0
	add_child(content)


func entry_transform(entry_id: StringName) -> Transform3D:
	var id: StringName = ENTRY_ALIASES.get(entry_id, entry_id)
	var table: Dictionary = content.entry_points
	return table.get(id, table[&"from_dead_coast"])


func exit_specs() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in content.exit_points:
		var target: Dictionary = EXIT_TARGETS.get(id, {})
		if target.is_empty():
			continue
		out[id] = {
			"position": (content.exit_points[id] as Dictionary)["position"] + Vector3(0.0, 1.0, 0.0),
			"size": Vector3(12.0, 3.0, 2.0),
			"target_region": target["region"], "target_entry": target["entry"],
		}
	return out


func capture_state() -> Dictionary:
	return content.capture_state() if content != null else {}


func restore_state(state: Dictionary) -> void:
	if content != null:
		content.restore_state(state)
