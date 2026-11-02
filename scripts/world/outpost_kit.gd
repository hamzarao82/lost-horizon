class_name OutpostKit
extends RefCounted
## Loader and batcher for the modular Outpost 17 environment kit (assets/environments/kit/*.glb).
##
## Pieces are original low-poly models with one shared vertex-colour material, origin at the base
## centre, +Y up, front facing -Z, 1 unit = 1 m (see docs/ENVIRONMENT_KIT.md).
## Draw-call strategy: every placement is merged into a few big meshes ("batches") so the whole
## outpost costs a handful of draw calls; repeated pieces can also use MultiMeshInstance3D.
## If a GLB is missing every call returns null/false so the caller falls back to its code-built decor.

const KIT_DIR: String = "res://assets/environments/kit/"
const MANIFEST: String = "res://assets/environments/kit_manifest.json"

static var _meshes: Dictionary = {}   # piece name -> Mesh (or null when missing)
static var _scenes: Dictionary = {}   # piece name -> PackedScene (or null)
static var _material: StandardMaterial3D


## Shared material for merged kit meshes: vertex colours are the albedo.
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.92
		_material.metallic = 0.0
	return _material


static func has_piece(piece: String) -> bool:
	return mesh_of(piece) != null


## The first mesh found in the piece's scene, cached. Null if the file is missing or has no mesh.
static func mesh_of(piece: String) -> Mesh:
	if _meshes.has(piece):
		return _meshes[piece]
	var mesh: Mesh = null
	var scene := _scene_of(piece)
	if scene:
		var root := scene.instantiate()
		var found := _first_mesh_instance(root)
		if found:
			mesh = found.mesh
		root.free()
	_meshes[piece] = mesh
	return mesh


static func _scene_of(piece: String) -> PackedScene:
	if _scenes.has(piece):
		return _scenes[piece]
	var path := KIT_DIR + piece + ".glb"
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	_scenes[piece] = scene
	return scene


static func _first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _first_mesh_instance(child)
		if found:
			return found
	return null


## A standalone instance of the piece (own draw call). Null if the piece is missing.
static func instance(piece: String, xform: Transform3D = Transform3D.IDENTITY) -> MeshInstance3D:
	var mesh := mesh_of(piece)
	if mesh == null:
		return null
	var node := MeshInstance3D.new()
	node.name = piece
	node.mesh = mesh
	node.material_override = material()
	node.transform = xform
	return node


## One MultiMeshInstance3D drawing many copies of a piece in a single draw call.
static func multimesh(piece: String, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mesh := mesh_of(piece)
	if mesh == null or xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.name = piece + "_multi"
	node.multimesh = mm
	node.material_override = material()
	return node


## Pieces listed in the manifest (for tests and tools). Empty if the manifest is missing.
static func manifest_pieces() -> Array:
	if not FileAccess.file_exists(MANIFEST):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if parsed is Dictionary and (parsed as Dictionary).get("pieces") is Array:
		return (parsed as Dictionary)["pieces"]
	return []


## Merges many placements into one mesh (one draw call). Not a Node: call finish() for the result.
class Batch:
	extends RefCounted
	var _st: SurfaceTool = SurfaceTool.new()
	var count: int = 0

	func _init() -> void:
		_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Returns false (and adds nothing) when the piece is not available.
	func add(piece: String, xform: Transform3D) -> bool:
		var mesh := OutpostKit.mesh_of(piece)
		if mesh == null:
			return false
		_st.append_from(mesh, 0, xform)
		count += 1
		return true

	func finish() -> ArrayMesh:
		if count == 0:
			return null
		return _st.commit()
