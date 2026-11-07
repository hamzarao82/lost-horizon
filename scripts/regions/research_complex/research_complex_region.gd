class_name ResearchComplexRegion
extends Region
## Region-contract adapter around the self-contained ResearchComplex builder (see DeadCoastRegion):
## RegionManager reads the entry transforms and exits from the builder's tables.

const ENTRY_ALIASES: Dictionary = {
	&"from_blackwood": &"from_blackwood", &"from_south": &"from_blackwood", &"": &"from_blackwood",
}
## Destination entry ids as the destination region names them.
const EXIT_TARGETS: Dictionary = {
	"to_blackwood": {"region": &"blackwood", "entry": &"from_underground"},
}

var content: ResearchComplex


func _ready() -> void:
	content = ResearchComplex.new()
	content.name = "ResearchComplex"
	add_child(content)


func enter(entry_id: StringName) -> void:
	content.enter(String(ENTRY_ALIASES.get(entry_id, entry_id)))


func entry_transform(entry_id: StringName) -> Transform3D:
	var id := String(ENTRY_ALIASES.get(entry_id, entry_id))
	var table: Dictionary = content.entry_points
	return table.get(id, table["from_blackwood"])


## Exit id -> {position, size, target_region, target_entry}, the format RegionManager spawns from.
func exit_specs() -> Dictionary:
	var out: Dictionary = {}
	for id: String in content.exit_points:
		var target: Dictionary = EXIT_TARGETS.get(id, {})
		if target.is_empty():
			continue
		out[StringName(id)] = {
			"position": (content.exit_points[id] as Dictionary)["position"] + Vector3(0.0, 1.0, 0.0),
			"size": Vector3(10.0, 3.0, 2.0),
			"target_region": target["region"], "target_entry": target["entry"],
		}
	return out


func capture_state() -> Dictionary:
	return content.capture_state() if content != null else {}


func restore_state(state: Dictionary) -> void:
	if content != null:
		content.restore_state(state)
