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
	StageWaves.attach(self, &"blackwood")  # one wave encounter in the stage's middle section
	# Two bosses (patrol camp, testing site) and the gate to the Research Complex (docs/STAGE_BOSSES.md).
	StageBoss.attach(self, &"blackwood", 1, "res://resources/enemies/bw_patrol_chief.tres", Vector3(-44.0, 0.0, -110.0),
			"res://resources/items/bw_chief_boots.tres", "Patrol Chief: No more stragglers on my trail.",
			"The Patrol Chief is down. The trail lanterns will not be lit again.")
	StageBoss.attach(self, &"blackwood", 2, "res://resources/enemies/bw_site_overseer.tres", Vector3(-10.0, 0.0, -218.0),
			"res://resources/items/bw_overseer_badge.tres", "Site Overseer: Nobody walks out of the testing site.",
			"The Site Overseer is down. The way to the facility is open.")
	var forward: Vector3 = (content.exit_points[&"to_research_complex"] as Dictionary)["position"]
	RegionGate.attach(self, &"research_complex", "Research Complex", forward + Vector3(0.0, 0.0, -2.8))


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
