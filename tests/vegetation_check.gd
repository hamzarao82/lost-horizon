extends SceneTree
## Headless checks for the vegetation scatter and the story props:
##   godot --headless --path . -s tests/vegetation_check.gd
## Covers the imported CC0 props, seeded determinism, keep-clear zones, the draw-call budget and the
## hook in the real decor build.

const PROPS: PackedStringArray = [
	"barrel_01", "barrel_03", "wooden_crate_01", "wooden_crate_02", "security_camera_02",
]
const MAX_PROP_BYTES: int = 2 * 1024 * 1024
const MAX_PROP_TRIS: int = 15000
## Peak draw calls of the scatter (cells and story props) the player can have in range at once.
const DRAW_CALL_BUDGET: int = 25

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


func _run() -> void:
	_props()
	_generation()
	_clusters()
	_budget()
	await _integration()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _props() -> void:
	print("-- imported props")
	for id in PROPS:
		var path := VegetationScatter.PROPS_DIR + id + ".glb"
		_check(ResourceLoader.exists(path), "%s imports" % id)
		if not ResourceLoader.exists(path):
			continue
		var bytes := FileAccess.get_file_as_bytes(path).size()
		_check(bytes <= MAX_PROP_BYTES, "%s is %d KB (limit 2 MB)" % [id, bytes / 1024])
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		var box := AABB()
		var first := true
		var tris := 0
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var a: AABB = m.transform * m.get_aabb()
			box = a if first else box.merge(a)
			first = false
			for s in m.mesh.get_surface_count():
				tris += m.mesh.surface_get_array_index_len(s) / 3
		_check(tris <= MAX_PROP_TRIS, "%s has %d triangles (limit %d)" % [id, tris, MAX_PROP_TRIS])
		_check(absf(box.position.y) < 0.02, "%s origin sits on its base" % id)
		_check(box.size.y > 0.1 and box.size.y < 4.0, "%s is a believable size in metres (%.2f m tall)" % [id, box.size.y])
		scene.free()


func _generation() -> void:
	print("-- generation")
	var a := VegetationScatter.generate(1.0)
	var b := VegetationScatter.generate(1.0)
	var same := true
	for species: String in a:
		var la: Array = a[species]
		var lb: Array = b[species]
		if la.size() != lb.size():
			same = false
			continue
		for i in la.size():
			if not (la[i] as Transform3D).is_equal_approx(lb[i]):
				same = false
	_check(same, "same seed gives identical placement")
	var other := VegetationScatter.generate(1.0, Callable(), VegetationScatter.SEED + 1)
	_check((a["bush"][0] as Transform3D).origin != (other["bush"][0] as Transform3D).origin, "a different seed changes placement")
	var total_high := 0
	var total_low := 0
	var low := VegetationScatter.generate(0.4)
	for species: String in a:
		total_high += (a[species] as Array).size()
		total_low += (low[species] as Array).size()
	_check(total_high >= 200, "high quality scatters %d plants and rocks" % total_high)
	_check(total_low < total_high * 0.5, "low quality scatters fewer (%d)" % total_low)
	var bad := 0
	for species: String in a:
		for xf: Transform3D in a[species]:
			var p := Vector2(xf.origin.x, xf.origin.z)
			if not VegetationScatter.is_allowed(p):
				bad += 1
	_check(bad == 0, "every placement passes the keep-clear rules (%d bad)" % bad)
	var in_arena := 0
	var in_courtyard := 0
	for species: String in a:
		for xf: Transform3D in a[species]:
			if absf(xf.origin.x) < 16.0 and xf.origin.z < -72.0 and xf.origin.z > -90.0:
				in_arena += 1
			if absf(xf.origin.x) < 30.0 and absf(xf.origin.z) < 30.0:
				in_courtyard += 1
	_check(in_arena == 0, "nothing grows in the boss arena zone")
	_check(in_courtyard == 0, "nothing grows inside the courtyard")
	_check(not VegetationScatter.is_allowed(Vector2(0.0, 0.0)), "the player spawn is kept clear")
	_check(not VegetationScatter.is_allowed(Vector2(6.5, 36.0)), "the checkpoint desk is kept clear")
	_check(VegetationScatter.is_allowed(Vector2(-70.0, 0.0)), "the jungle outside the walls is open for plants")


func _clusters() -> void:
	print("-- story clusters")
	_check(VegetationScatter.CLUSTERS.size() >= 3, "%d story pieces defined" % VegetationScatter.CLUSTERS.size())
	var all_have_reason := true
	var clear := true
	for c in VegetationScatter.CLUSTERS:
		if String(c.get("why", "")).length() < 8:
			all_have_reason = false
		var p: Vector2 = c["pos"]
		for k in VegetationScatter.KEEP_CLEAR:
			if p.distance_to(Vector2(k.x, k.y)) < k.z:
				clear = false
		if absf(p.x) < VegetationScatter.BEACH_FLANKS_X.x:
			clear = false
	_check(all_have_reason, "every story piece states why it is there")
	_check(clear, "story pieces stay off the checkpoint, wreck, spawn, arena and the beach path")


func _budget() -> void:
	print("-- draw-call budget")
	var nodes := VegetationScatter.build(1.0, Callable(), 45.0)
	_check(nodes.size() > 0, "build produces %d cell meshes" % nodes.size())
	var worst := 0
	for spot in [Vector2(0, 0), Vector2(0, 50), Vector2(30, 60), Vector2(-30, 55), Vector2(0, -60), Vector2(-60, 0), Vector2(60, 20)]:
		var visible := 0
		for n in nodes:
			var mm := n as MultiMeshInstance3D
			if Vector2(mm.position.x, mm.position.z).distance_to(spot) <= mm.visibility_range_end:
				visible += 1
		worst = maxi(worst, visible)
	_check(worst <= DRAW_CALL_BUDGET, "at most %d scatter cells are in range at once (budget %d)" % [worst, DRAW_CALL_BUDGET])
	var fades := true
	for n in nodes:
		var g := n as GeometryInstance3D
		if g.visibility_range_end <= 0.0 or g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			fades = false
	_check(fades, "every cell has a view range and casts no shadow")
	for n in nodes:
		n.free()
	var story := VegetationScatter.build_clusters(Callable())
	_check(story.size() >= 9, "%d story nodes build" % story.size())
	for n in story:
		n.free()


func _integration() -> void:
	print("-- decor integration")
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	var decor: Node = main.get_node_or_null("Decor")
	var waited := 0
	while decor != null and not decor.call("is_built") and waited < 600:
		await physics_frame
		waited += 1
	_check(decor != null and decor.call("is_built"), "decor builds")
	var scatter_nodes := 0
	var story_nodes := 0
	if decor != null:
		for child in decor.get_children():
			if child is MultiMeshInstance3D and (child.name.begins_with("palm_") or child.name.begins_with("bush_") or child.name.begins_with("rocks_")):
				scatter_nodes += 1
			if child.name.begins_with("Story_"):
				story_nodes += 1
	_check(decor != null and bool(decor.get("kit_active")), "the environment kit is active")
	_check(scatter_nodes > 0, "scatter cells are part of the decor (%d)" % scatter_nodes)
	_check(story_nodes >= 9, "story pieces are part of the decor (%d)" % story_nodes)
	main.queue_free()
	await physics_frame
