extends SceneTree
## Headless checks for the Outpost 17 environment kit:
##   godot --headless --path . -s tests/env_kit_check.gd
## Covers the GLB files, the manifest, OutpostKit, the decor build, and that nothing the gameplay
## depends on (colliders, obstacle positions, spawn bounds) was touched.

const KIT_DIR: String = "res://assets/environments/kit/"
const MAX_TRIS_PER_PIECE: int = 2500
const MAX_BYTES_PER_PIECE: int = 150 * 1024
const MAX_KIT_BYTES: int = 3 * 1024 * 1024
const REQUIRED: PackedStringArray = [
	"container_red", "container_blue", "container_green", "watchtower", "sandbag_stack", "sandbag_corner",
	"barricade_concrete", "barricade_wire", "hut_small", "barracks", "warehouse", "fence_section", "fence_wire",
	"palm_a", "palm_b", "bush", "rocks_a", "rocks_b", "rocks_c", "crate", "barrel", "radio_mast", "truck_wreck",
	"boat_wreck", "sign_outpost_17", "tent", "generator",
]

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	_test_files_and_manifest()
	_test_pieces()
	_test_kit_api()
	await _test_decor_build()
	await _test_gameplay_untouched()
	await _test_fallback()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_files_and_manifest() -> void:
	print("Files and manifest")
	var pieces := OutpostKit.manifest_pieces()
	_check(pieces.size() >= REQUIRED.size(), "manifest lists at least %d pieces (%d)" % [REQUIRED.size(), pieces.size()])
	var names: PackedStringArray = []
	var total_bytes := 0
	var over_budget := PackedStringArray()
	for p in pieces:
		names.append(p["name"])
		total_bytes += int(p["bytes"])
		if int(p["tris"]) > MAX_TRIS_PER_PIECE or int(p["bytes"]) > MAX_BYTES_PER_PIECE:
			over_budget.append(p["name"])
	var missing := PackedStringArray()
	for piece_name in REQUIRED:
		if not names.has(piece_name) or not ResourceLoader.exists(KIT_DIR + piece_name + ".glb"):
			missing.append(piece_name)
	_check(missing.is_empty(), "every required piece exists as a GLB and in the manifest (missing: %s)" % ", ".join(missing))
	_check(over_budget.is_empty(), "every piece is within %d tris and %d KB (%s)" % [MAX_TRIS_PER_PIECE, MAX_BYTES_PER_PIECE / 1024, ", ".join(over_budget)])
	_check(total_bytes <= MAX_KIT_BYTES, "whole kit is under 3 MB (%.2f MB)" % (total_bytes / 1048576.0))


func _test_pieces() -> void:
	print("Pieces")
	var bad_load := PackedStringArray()
	var multi_surface := PackedStringArray()
	var no_color := PackedStringArray()
	var wrong_size := PackedStringArray()
	var below_ground := PackedStringArray()
	for p in OutpostKit.manifest_pieces():
		var piece_name: String = p["name"]
		var mesh := OutpostKit.mesh_of(piece_name)
		if mesh == null:
			bad_load.append(piece_name)
			continue
		if mesh.get_surface_count() != 1:
			multi_surface.append(piece_name)
		var arrays := mesh.surface_get_arrays(0)
		var colors: Variant = arrays[Mesh.ARRAY_COLOR]
		var has_variation := false
		if colors is PackedColorArray and (colors as PackedColorArray).size() > 0:
			var first: Color = (colors as PackedColorArray)[0]
			for c in colors as PackedColorArray:
				if not c.is_equal_approx(first):
					has_variation = true
					break
		if not has_variation:
			no_color.append(piece_name)
		var aabb := mesh.get_aabb()
		var size: Array = p["size"]
		var ok := absf(aabb.size.x - size[0]) < 0.05 and absf(aabb.size.y - size[1]) < 0.05 and absf(aabb.size.z - size[2]) < 0.05
		if not ok:
			wrong_size.append(piece_name)
		if aabb.position.y < -0.6 or aabb.position.y > 0.2:
			below_ground.append(piece_name)
	_check(bad_load.is_empty(), "every GLB loads as a mesh (%s)" % ", ".join(bad_load))
	_check(multi_surface.is_empty(), "every piece has exactly one surface, so one shared material (%s)" % ", ".join(multi_surface))
	_check(no_color.is_empty(), "every piece carries vertex colours that vary (palette imported) (%s)" % ", ".join(no_color))
	_check(wrong_size.is_empty(), "mesh bounds match the manifest sizes (%s)" % ", ".join(wrong_size))
	_check(below_ground.is_empty(), "origin is at the base (%s)" % ", ".join(below_ground))
	# Footprints: containers fit the 4 x 4 collider as a side-by-side pair (offset +-1.0 m on Z).
	var container := OutpostKit.mesh_of("container_red").get_aabb()
	_check(container.size.x <= 4.3 and container.size.y <= 2.3, "container length and height fit the 4 x 2 collider (+0.3 m)")
	_check(container.size.z * 0.5 + 1.0 <= 2.3, "a container pair offset 1.0 m on Z fits the 4 m collider (+0.3 m)")


func _test_kit_api() -> void:
	print("OutpostKit API")
	_check(OutpostKit.mesh_of("no_such_piece") == null and not OutpostKit.has_piece("no_such_piece"), "a missing piece returns null, never errors")
	var node := OutpostKit.instance("crate", Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	_check(node != null and node.mesh != null and node.position == Vector3(1, 2, 3), "instance() returns a placed MeshInstance3D")
	_check(node.material_override is StandardMaterial3D and (node.material_override as StandardMaterial3D).vertex_color_use_as_albedo, "instances use the shared vertex-colour material")
	node.free()
	var xforms: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0))]
	var multi := OutpostKit.multimesh("barrel", xforms)
	_check(multi != null and multi.multimesh.instance_count == 3, "multimesh() draws every transform")
	multi.free()
	_check(OutpostKit.multimesh("no_such_piece", xforms) == null, "multimesh() of a missing piece is null")
	var batch := OutpostKit.Batch.new()
	_check(batch.add("crate", Transform3D.IDENTITY) and not batch.add("no_such_piece", Transform3D.IDENTITY), "Batch.add reports success and failure")
	var mesh := batch.finish()
	_check(mesh != null and mesh.get_surface_count() == 1, "a batch merges into one surface (one draw call)")
	_check(OutpostKit.Batch.new().finish() == null, "an empty batch produces no mesh")


func _spawn_main() -> Node:
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await _frames(3)
	return main


func _triangles(mesh: Mesh) -> int:
	return mesh.get_faces().size() / 3


func _test_decor_build() -> void:
	print("Decor build")
	ArenaDecor.allow_kit = true
	var main := await _spawn_main()
	var decor := main.get_node("Decor") as ArenaDecor
	var waited := 0
	while not decor.is_built() and waited < 600:
		await physics_frame
		waited += 1
	_check(decor.is_built() and decor.kit_active, "decor finishes building with the kit active")
	var chunks := {}
	var total_tris := 0
	for child in decor.get_children():
		if child.name.begins_with("Kit_"):
			var mi := child as MeshInstance3D
			chunks[String(child.name)] = mi
			total_tris += _triangles(mi.mesh)
	var expected_chunks := 3 if decor.skip_north_outpost else 4  # Milestone 3: Areas C and D replace the north outpost kit
	_check(chunks.size() == expected_chunks, "merged kit chunks (%d draw calls): %s" % [expected_chunks, ", ".join(chunks.keys())])
	_check(total_tris > 8000 and total_tris < 120000, "kit adds a sensible triangle count (%d)" % total_tris)
	var ranges_ok := true
	for chunk in chunks:
		var expected: float = ArenaDecor.KIT_CHUNK_RANGE[String(chunk).trim_prefix("Kit_")]
		ranges_ok = ranges_ok and is_equal_approx((chunks[chunk] as MeshInstance3D).visibility_range_end, expected)
	_check(ranges_ok, "chunks have the planned visibility ranges")
	_check(chunks.has("Kit_courtyard") and (chunks["Kit_courtyard"] as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "only the courtyard chunk casts shadows")
	_check(not main.get_node("Box1/MeshInstance3D").visible and not main.get_node("Box2/MeshInstance3D").visible, "plain obstacle boxes are hidden behind the containers")
	_check(decor.get_node_or_null("OutpostSign") != null and decor.get_node_or_null("Sea") != null and decor.get_node_or_null("Terrain") != null, "sand, sea and the OUTPOST 17 sign are still built")
	# Determinism: the same seed gives the same layout.
	var first_total := total_tris
	decor.set_quality(ArenaDecor.QUALITY_LOW)
	waited = 0
	while not decor.is_built() and waited < 600:
		await physics_frame
		waited += 1
	var low_tris := 0
	for child in decor.get_children():
		if child.name.begins_with("Kit_") and not child.is_queued_for_deletion():
			low_tris += _triangles((child as MeshInstance3D).mesh)
	_check(low_tris > 0 and low_tris < first_total, "low quality builds a lighter kit (%d < %d tris)" % [low_tris, first_total])
	decor.set_quality(ArenaDecor.QUALITY_HIGH)
	waited = 0
	while not decor.is_built() and waited < 600:
		await physics_frame
		waited += 1
	var again := 0
	for child in decor.get_children():
		if child.name.begins_with("Kit_") and not child.is_queued_for_deletion():
			again += _triangles((child as MeshInstance3D).mesh)
	_check(again == first_total, "rebuilding at the same quality reproduces the same layout (%d == %d)" % [again, first_total])
	main.queue_free()
	await _frames(3)


func _test_gameplay_untouched() -> void:
	print("Gameplay untouched")
	var main := await _spawn_main()
	var decor := main.get_node("Decor") as ArenaDecor
	var waited := 0
	while not decor.is_built() and waited < 600:
		await physics_frame
		waited += 1
	for entry in [["Box1", Vector3(8, 1, -6)], ["Box2", Vector3(-8, 0.5, -4)]]:
		var body := main.get_node(entry[0]) as StaticBody3D
		var shape := (body.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
		_check(shape.size == Vector3(4, 2, 4) and body.position == entry[1], "%s collider is still 4 x 2 x 4 at %s" % [entry[0], entry[1]])
	var obstacles_ok := WaveManager.OBSTACLES.size() == 2 and WaveManager.OBSTACLES.has(Vector2(8, -6)) and WaveManager.OBSTACLES.has(Vector2(-8, -4))
	_check(obstacles_ok, "WaveManager obstacle positions match the containers")
	_check(WaveManager.ARENA_LIMIT == 26.0 and WaveManager.SPAWN_MIN == 12.0, "spawn bounds are unchanged (+-26, min 12)")
	var collision_nodes := 0
	for node in decor.find_children("*", "CollisionObject3D", true, false):
		collision_nodes += 1
	_check(collision_nodes == 0, "the decor creates no physics bodies")
	for wall in ["WallN", "WallS", "WallE", "WallW", "Floor"]:
		_check(main.get_node_or_null(wall) != null, "%s still exists" % wall)
	_check(main.get_node_or_null("Player") != null and main.get_node_or_null("WaveManager") != null, "Player and WaveManager untouched")
	main.queue_free()
	await _frames(3)


func _test_fallback() -> void:
	print("Fallback to the primitive decor")
	ArenaDecor.allow_kit = false
	var main := await _spawn_main()
	var decor := main.get_node("Decor") as ArenaDecor
	var waited := 0
	while not decor.is_built() and waited < 600:
		await physics_frame
		waited += 1
	_check(decor.is_built() and not decor.kit_active, "with the kit disabled the old decor builds")
	var kit_chunks := 0
	for child in decor.get_children():
		if child.name.begins_with("Kit_"):
			kit_chunks += 1
	_check(kit_chunks == 0 and decor.get_node_or_null("Props") != null, "no kit chunks, the merged Props mesh is used")
	_check(main.get_node("Box1/MeshInstance3D").visible, "plain obstacle boxes stay visible without the kit")
	ArenaDecor.allow_kit = true
	main.queue_free()
	await _frames(3)
