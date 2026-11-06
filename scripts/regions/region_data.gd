class_name RegionData
extends Resource
## Data for one region of the campaign. New regions are a new .tres plus a scene; no code changes.
##
## entry_points: StringName -> Transform3D, where the player appears when arriving.
## exit_points:  StringName -> {position: Vector3, size: Vector3, target_region: StringName, target_entry: StringName};
##               RegionManager turns each into a RegionExit while the region is loaded.

@export var id: StringName = &""
@export var display_name: String = ""
## Scene to instantiate; "" means the region lives inside the existing Main scene (Outpost 17).
@export_file("*.tscn") var scene_path: String = ""
@export var entry_points: Dictionary = {}
@export var exit_points: Dictionary = {}
## WorldState flag that opens the region; "" means always open.
@export var unlock_flag: StringName = &""
@export var environment_preset: StringName = &""
@export var ambience: StringName = &""
## World-space rectangle (x, z) the map screen draws for this region.
@export var map_extents: Rect2 = Rect2(-50.0, -50.0, 100.0, 100.0)


## First entry point, used when a travel request names none.
func default_entry() -> StringName:
	for key in entry_points:
		return key
	return &""


func entry_transform(entry_id: StringName) -> Transform3D:
	var raw: Variant = entry_points.get(entry_id, null)
	if raw is Transform3D:
		return raw
	var fallback: Variant = entry_points.get(default_entry(), null)
	if fallback is Transform3D:
		return fallback
	return Transform3D(Basis.IDENTITY, Vector3(0.0, 0.1, 0.0))
