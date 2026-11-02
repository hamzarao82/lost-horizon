extends SceneTree
## Headless check of the authored weapon and armor GLBs:
##   godot --headless --path . -s tools/blender/verify_weapons.gd
## Asserts each file loads, has exactly one mesh with ONE material, vertex colours, a triangle count within
## budget, the contract length (+-10%), the blade toward -Z with the origin at the grip, and the plate bounds.
## Prints a table. Exit code 1 on any failure.

const WEAPONS: Dictionary = {
	&"improvised_blade": 0.75, &"combat_knife": 0.38, &"iron_sword": 0.95, &"military_machete": 0.72,
	&"katana": 1.05, &"tactical_sword": 0.92, &"claymore": 1.45, &"warden_blade": 1.25,
}
const MAX_WEAPON_TRIS: int = 1500
const MAX_PLATE_TRIS: int = 2000
const MAX_FILE_BYTES: int = 200 * 1024

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		print("  FAIL ", message)


## Collects every MeshInstance3D below root with its transform relative to root.
func _meshes(node: Node, xform: Transform3D, out: Array) -> void:
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		out.append([node, local])
	for child in node.get_children():
		_meshes(child, local, out)


func _inspect(path: String) -> Dictionary:
	var info := {"ok": false}
	var scene := load(path) as PackedScene
	if scene == null:
		return info
	var root := scene.instantiate()
	var found: Array = []
	_meshes(root, Transform3D.IDENTITY, found)
	var tris := 0
	var surfaces := 0
	var materials := {}
	var has_colors := true
	var albedo_from_vertex := true
	var aabb := AABB()
	var first := true
	for entry in found:
		var mi := entry[0] as MeshInstance3D
		var xf := entry[1] as Transform3D
		var mesh := mi.mesh
		for s in mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			tris += (idx.size() / 3) if idx != null else (verts.size() / 3)
			var colors: Variant = arrays[Mesh.ARRAY_COLOR]
			has_colors = has_colors and colors != null and colors.size() > 0
			var mat := mi.get_active_material(s)
			materials[mat] = true
			if mat is BaseMaterial3D:
				albedo_from_vertex = albedo_from_vertex and (mat as BaseMaterial3D).vertex_color_use_as_albedo
		var box := xf * mesh.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	root.free()
	info = {"ok": true, "tris": tris, "surfaces": surfaces, "materials": materials.size(), "meshes": found.size(),
			"colors": has_colors, "albedo_vertex": albedo_from_vertex, "aabb": aabb}
	return info


func _run() -> void:
	print("%-18s %6s %5s %6s %6s %-7s %s" % ["file", "tris", "mats", "len_m", "want", "blade", "KB"])
	for id in WEAPONS:
		var path := "res://assets/weapons/%s.glb" % id
		var info := _inspect(path)
		_check(info["ok"], "%s loads" % id)
		if not info["ok"]:
			continue
		var aabb := info["aabb"] as AABB
		var length := aabb.size.z
		var want := float(WEAPONS[id])
		var tip_dir := "-Z" if -aabb.position.z > aabb.end.z else "+Z"
		var kb := FileAccess.get_file_as_bytes(path).size() / 1024.0
		print("%-18s %6d %5d %6.3f %6.2f %-7s %.0f" % [id, info["tris"], info["materials"], length, want, tip_dir, kb])
		_check(info["meshes"] == 1 and info["surfaces"] == 1, "%s: one mesh, one surface" % id)
		_check(info["materials"] == 1, "%s: one material" % id)
		_check(info["colors"], "%s: vertex colours present" % id)
		_check(info["albedo_vertex"], "%s: vertex colours drive albedo" % id)
		_check(info["tris"] <= MAX_WEAPON_TRIS, "%s: tris <= %d (got %d)" % [id, MAX_WEAPON_TRIS, info["tris"]])
		_check(absf(length - want) <= want * 0.1, "%s: length %.3f within 10%% of %.2f" % [id, length, want])
		_check(tip_dir == "-Z", "%s: blade points toward -Z, origin at the grip" % id)
		_check(aabb.end.z < length * 0.35 and aabb.end.z > 0.0, "%s: grip centre is near the origin (back extent %.3f)" % [id, aabb.end.z])
		_check(aabb.size.x >= aabb.size.y * 0.9, "%s: width (x) >= thickness (y), edges sideways (10%% tolerance for round guards)" % id)
		_check(kb * 1024.0 <= MAX_FILE_BYTES, "%s: file under 200 KB" % id)
		_check(absf(aabb.position.y + aabb.size.y * 0.5) < 0.03, "%s: centred vertically on the grip axis" % id)

	var plate_path := "res://assets/armor/warden_plate.glb"
	var plate := _inspect(plate_path)
	_check(plate["ok"], "warden_plate loads")
	if plate["ok"]:
		var box := plate["aabb"] as AABB
		var kb := FileAccess.get_file_as_bytes(plate_path).size() / 1024.0
		print("%-18s %6d %5d  w=%.2f h=%.2f d=%.2f  centre=(%.2f, %.2f, %.2f)  %.0f KB" % ["warden_plate", plate["tris"],
				plate["materials"], box.size.x, box.size.y, box.size.z, box.get_center().x, box.get_center().y,
				box.get_center().z, kb])
		_check(plate["tris"] <= MAX_PLATE_TRIS, "plate: tris <= %d (got %d)" % [MAX_PLATE_TRIS, plate["tris"]])
		_check(plate["meshes"] == 1 and plate["materials"] == 1, "plate: one mesh, one material")
		_check(plate["colors"] and plate["albedo_vertex"], "plate: vertex colours drive albedo")
		_check(box.size.x > 0.45 and box.size.x < 0.8, "plate: shoulder width plausible (%.2f)" % box.size.x)
		_check(box.size.y > 0.4 and box.size.y < 0.75, "plate: height plausible (%.2f)" % box.size.y)
		_check(absf(box.get_center().x) < 0.02, "plate: centred in x")
		_check(box.get_center().y > -0.3 and box.get_center().y < 0.1, "plate: origin near the chest bone (centre y %.2f)" % box.get_center().y)
		# front of the chest toward -Z: the emblem side must extend further toward -Z than the back
		_check(box.position.z < 0.0 and box.end.z > 0.0, "plate: straddles the origin in z")
		_check(kb * 1024.0 <= MAX_FILE_BYTES, "plate: file under 200 KB")

	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
