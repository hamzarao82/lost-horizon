class_name DeadCoastRegion
extends Region
## Region-contract adapter around the self-contained DeadCoast builder, so RegionManager can load it.
## The builder keeps its own tests; this node owns the content child, maps entry ids, and offers the
## transforms and exits that RegionManager reads (single source: the builder's tables).

const ENTRY_ALIASES: Dictionary = {
	&"from_outpost": &"beach_arrival", &"from_south": &"beach_arrival", &"from_outpost_17": &"beach_arrival",
	&"": &"beach_arrival",
}
## Destination entry ids as the destination RegionData names them.
const EXIT_TARGETS: Dictionary = {
	"to_outpost_17": {"region": &"outpost_17", "entry": &"from_south"},
	"to_blackwood": {"region": &"blackwood", "entry": &"from_dead_coast"},
}

var content: DeadCoast


func _ready() -> void:
	content = DeadCoast.new()
	content.name = "DeadCoast"
	content.vegetation_density = 0.4 if OS.has_feature("web") or OS.has_feature("mobile") else 1.0
	add_child(content)
	StageWaves.attach(self, &"dead_coast")  # one wave encounter in the stage's middle section
	# Two bosses (checkpoint, cove) and the gate to Blackwood (docs/STAGE_BOSSES.md).
	StageBoss.attach(self, &"dead_coast", 1, "res://resources/enemies/dc_harbor_commander.tres", DeadCoastTerrain.ground(8.5, -121.0),
			"res://resources/items/dc_harbor_cap.tres", "Harbor Commander: This road is closed. It has been closed for a long time.",
			"The Harbor Commander is down. His checkpoint log is still open.")
	StageBoss.attach(self, &"dead_coast", 2, "res://resources/enemies/dc_cove_boss.tres", DeadCoastTerrain.ground(18.0, -170.0),
			"res://resources/items/dc_cove_gloves.tres", "Cove Boss: You found the cargo. Now you carry it out in pieces.",
			"The Cove Boss falls. The shipment answered to someone above him.")
	var forward: Vector3 = (content.exit_points["to_blackwood"] as Dictionary)["position"]
	RegionGate.attach(self, &"blackwood", "Blackwood", forward + Vector3(0.0, 0.0, -2.8))


func enter(entry_id: StringName) -> void:
	content.enter(String(ENTRY_ALIASES.get(entry_id, entry_id)))


func entry_transform(entry_id: StringName) -> Transform3D:
	var id := String(ENTRY_ALIASES.get(entry_id, entry_id))
	var table: Dictionary = content.entry_points
	return table.get(id, table["beach_arrival"])


## Exit id -> {position, size, target_region, target_entry}, the format RegionManager spawns from.
func exit_specs() -> Dictionary:
	var out: Dictionary = {}
	for id: String in content.exit_points:
		var target: Dictionary = EXIT_TARGETS.get(id, {})
		if target.is_empty():
			continue
		out[StringName(id)] = {
			"position": (content.exit_points[id] as Dictionary)["position"] + Vector3(0.0, 1.0, 0.0),
			"size": Vector3(12.0, 3.0, 2.0),
			"target_region": target["region"], "target_entry": target["entry"],
		}
	return out


func capture_state() -> Dictionary:
	return content.capture_state() if content != null else {}


func restore_state(state: Dictionary) -> void:
	# Runs after _ready (the manager adds the region first), so the builder exists.
	if content != null:
		content.restore_state(state)
