class_name BarrelPlacement
extends RefCounted
## Where the explosive barrels stand (Milestone 11). Positions are region-local and sit off the walking
## routes and away from spawns, cover points and interactables; ids are saved-flag safe ([a-z0-9_], <= 48).

const LAYOUTS: Dictionary = {
	&"outpost_17": [
		{"id": "op17_arena_w", "pos": Vector3(-17.0, 0.0, 12.0)},
		{"id": "op17_arena_e", "pos": Vector3(17.0, 0.0, 12.0)},
		{"id": "op17_approach_w", "pos": Vector3(-26.0, 0.0, 62.0)},
		{"id": "op17_approach_e", "pos": Vector3(26.0, 0.0, 58.0)},
		{"id": "op17_gate_hall", "pos": Vector3(-6.0, 0.0, -60.2)},
	],
	&"research_complex": [
		{"id": "rc_lab_nw", "pos": Vector3(-15.0, 0.0, -142.0)},
		{"id": "rc_lab_ne", "pos": Vector3(15.0, 0.0, -142.0)},
		{"id": "rc_lab_sw", "pos": Vector3(-15.0, 0.0, -152.0)},
		{"id": "rc_lab_se", "pos": Vector3(15.0, 0.0, -152.0)},
	],
	&"iron_fortress": [
		{"id": "if_bar_w1", "pos": Vector3(-7.0, 0.0, -54.0)},
		{"id": "if_bar_w2", "pos": Vector3(-7.0, 0.0, -75.0)},
		{"id": "if_bar_e1", "pos": Vector3(8.0, 0.0, -74.0)},
		{"id": "if_bar_e2", "pos": Vector3(-18.0, 0.0, -74.0)},
	],
}


## Adds this region's barrels under `parent` (positions are local to it). Returns the barrels built.
static func build(parent: Node3D, region_id: StringName) -> Array[ExplosiveBarrel]:
	var out: Array[ExplosiveBarrel] = []
	for entry: Dictionary in LAYOUTS.get(region_id, []):
		var barrel := ExplosiveBarrel.new()
		barrel.name = "Barrel_" + String(entry["id"])
		barrel.region_id = region_id
		barrel.barrel_id = StringName(entry["id"])
		barrel.position = entry["pos"]
		parent.add_child(barrel)
		out.append(barrel)
	return out
