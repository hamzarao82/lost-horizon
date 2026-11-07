class_name IronFortressRegion
extends Region
## Region-contract adapter around the self-contained IronFortress builder (see ResearchComplexRegion):
## RegionManager reads the entry transforms and exits from the builder's tables.

const ENTRY_ALIASES: Dictionary = {
	&"from_research_complex": &"from_research_complex", &"from_underground": &"from_underground", &"": &"from_research_complex",
}
## Destination entry ids as the destination region names them.
const EXIT_TARGETS: Dictionary = {
	"to_research_complex": {"region": &"research_complex", "entry": &"from_iron_fortress"},
}

var content: IronFortress


func _ready() -> void:
	content = IronFortress.new()
	content.name = "IronFortress"
	add_child(content)


func enter(entry_id: StringName) -> void:
	content.enter(String(ENTRY_ALIASES.get(entry_id, entry_id)))


func entry_transform(entry_id: StringName) -> Transform3D:
	var id := String(ENTRY_ALIASES.get(entry_id, entry_id))
	var table: Dictionary = content.entry_points
	return table.get(id, table["from_research_complex"])


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
