class_name RegionExport
extends RefCounted
## Exports the static geometry of the region that is currently loaded under `main` as ONE glTF binary, for the
## Review Hub's Holo Bay. The regions are built by code at runtime, so there is no scene file to export: this walks
## the live world, builds a clean copy (meshes with converted materials, multi-mesh vegetation merged) and writes it
## with GLTFDocument. Development tool: tools/* is excluded from release builds.
##
## What is left out on purpose (counted in the report): the player, enemies and pickups (they move), planes bigger
## than MAX_EXTENT (the sea), invisible meshes, and shader materials, which become flat colours (glTF has no custom
## shaders; the game's triplanar textures have no UVs to carry either).

const MAX_EXTENT: float = 600.0
const MAX_INSTANCES_PER_MULTIMESH: int = 600
const GROUND_FALLBACK: Color = Color(0.50, 0.44, 0.34)
const UNKNOWN_FALLBACK: Color = Color(0.62, 0.62, 0.62)
const COLOR_PARAMS: PackedStringArray = ["albedo", "albedo_color", "color", "tint", "base_color"]

var report: Dictionary = {}
var _material_cache: Dictionary = {}


func _init() -> void:
	report = {"meshes": 0, "multimesh_nodes": 0, "multimesh_instances": 0, "multimesh_thinned": 0, "skipped_big": [],
			"skipped_invisible": 0, "shader_materials": 0, "textured_materials_kept": 0, "tris": 0}


## Returns {"root": Node3D (free it after exporting), "report": Dictionary, "bounds": [[minx, miny, minz], [maxx, maxy, maxz]]}
static func build(main: Node3D) -> Dictionary:
	var ex := RegionExport.new()
	var root := Node3D.new()
	root.name = "Region"
	var bounds := AABB()
	var first := true
	for entry in ex._collect(main):
		var mi := entry as MeshInstance3D
		root.add_child(mi)
		var box := mi.transform * mi.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	ex.report["tris"] = ex._count_tris(root)
	return {"root": root, "report": ex.report, "bounds": [_v(bounds.position), _v(bounds.end)]}


static func _v(v: Vector3) -> Array:
	return [snappedf(v.x, 0.1), snappedf(v.y, 0.1), snappedf(v.z, 0.1)]


static func write(root: Node3D, path: String) -> int:
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		return err
	return doc.write_to_filesystem(state, path)


func _count_tris(root: Node) -> int:
	var total := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for s in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(s)
				var idx: Variant = arrays[Mesh.ARRAY_INDEX]
				if idx != null and (idx as PackedInt32Array).size() > 0:
					total += (idx as PackedInt32Array).size() / 3
				else:
					total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total


func _collect(node: Node) -> Array:
	var out: Array = []
	_walk(node, out)
	return out


func _walk(node: Node, out: Array) -> void:
	if node is Player or node is Enemy or node is Pickup:
		return
	if node is MeshInstance3D:
		var made := _copy_mesh_instance(node as MeshInstance3D)
		if made != null:
			out.append(made)
	elif node is MultiMeshInstance3D:
		var merged := _merge_multimesh(node as MultiMeshInstance3D)
		if merged != null:
			out.append(merged)
	for child in node.get_children():
		_walk(child, out)


func _copy_mesh_instance(src: MeshInstance3D) -> MeshInstance3D:
	if src.mesh == null:
		return null
	if not src.is_visible_in_tree():
		report["skipped_invisible"] += 1
		return null
	var size := src.get_aabb().size * src.global_transform.basis.get_scale()
	if maxf(size.x, maxf(size.y, size.z)) > MAX_EXTENT:
		(report["skipped_big"] as Array).append(String(src.name))
		return null
	var mi := MeshInstance3D.new()
	mi.name = String(src.name)
	mi.mesh = src.mesh
	mi.transform = src.global_transform
	for s in src.mesh.get_surface_count():
		var has_colors: bool = _has_colors(src.mesh, s)
		mi.set_surface_override_material(s, _convert(src.get_active_material(s), has_colors))
	report["meshes"] += 1
	return mi


func _merge_multimesh(src: MultiMeshInstance3D) -> MeshInstance3D:
	var mm := src.multimesh
	if mm == null or mm.mesh == null or not src.is_visible_in_tree():
		return null
	var count := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	if count <= 0:
		return null
	var stride := maxi(1, ceili(float(count) / MAX_INSTANCES_PER_MULTIMESH))
	var merged := ArrayMesh.new()
	var used := 0
	for s in mm.mesh.get_surface_count():
		var st := SurfaceTool.new()
		for i in range(0, count, stride):
			st.append_from(mm.mesh, s, src.global_transform * mm.get_instance_transform(i))
			if s == 0:
				used += 1
		st.commit(merged)
		var has_colors: bool = _has_colors(mm.mesh, s)
		var mat: Material = src.material_override if src.material_override != null else mm.mesh.surface_get_material(s)
		merged.surface_set_material(merged.get_surface_count() - 1, _convert(mat, has_colors))
	var mi := MeshInstance3D.new()
	mi.name = String(src.name) + "_merged"
	mi.mesh = merged
	report["multimesh_nodes"] += 1
	report["multimesh_instances"] += used
	if stride > 1:
		report["multimesh_thinned"] += count - used
	return mi


func _convert(source: Material, has_vertex_colors: bool) -> StandardMaterial3D:
	var key := "%d:%s" % [source.get_instance_id() if source != null else 0, has_vertex_colors]
	if _material_cache.has(key):
		return _material_cache[key]
	var out := StandardMaterial3D.new()
	out.roughness = 0.9
	if source is StandardMaterial3D:
		var m := source as StandardMaterial3D
		out.albedo_color = m.albedo_color
		out.metallic = minf(m.metallic, 0.6)
		out.roughness = m.roughness
		out.cull_mode = m.cull_mode
		if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if m.emission_enabled:
			out.emission_enabled = true
			out.emission = m.emission
			out.emission_energy_multiplier = m.emission_energy_multiplier
		# Triplanar textures have no UVs to export; every other albedo texture is kept so imported kit pieces look right.
		if m.albedo_texture != null and not m.uv1_triplanar:
			out.albedo_texture = m.albedo_texture
			report["textured_materials_kept"] += 1
		out.vertex_color_use_as_albedo = has_vertex_colors or m.vertex_color_use_as_albedo
	elif source is ShaderMaterial:
		report["shader_materials"] += 1
		out.albedo_color = _shader_color(source as ShaderMaterial)
		out.vertex_color_use_as_albedo = has_vertex_colors
	else:
		out.albedo_color = UNKNOWN_FALLBACK
		out.vertex_color_use_as_albedo = has_vertex_colors
	_material_cache[key] = out
	return out


func _shader_color(m: ShaderMaterial) -> Color:
	for p in COLOR_PARAMS:
		var v: Variant = m.get_shader_parameter(p)
		if v is Color:
			return v
	return GROUND_FALLBACK


## True when the surface carries per-vertex colours (works for every mesh type, primitives included).
func _has_colors(mesh: Mesh, surface: int) -> bool:
	var arrays := mesh.surface_get_arrays(surface)
	return arrays.size() > Mesh.ARRAY_COLOR and arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() > 0
