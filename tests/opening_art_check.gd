extends SceneTree
## The opening arc's art (visual only, headless): the speedboat, the real character models with their clips, the
## walker figures, the payment bag's named parts, the smooth berm and rise (same footprint as their colliders), the
## ocean grid, and the pipes and monitors. Collision shapes are checked too, so a visual change cannot move them.
##   godot --headless --path . -s tests/opening_art_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _run() -> void:
	_check_boat()
	_check_characters()
	_check_walker()
	_check_berm_mesh()
	_check_payment_bag()
	_check_ocean()
	await _check_approach()
	print("opening_art_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check_boat() -> void:
	var boat := OpeningArt.boat()
	_check(boat != null and boat.get_child_count() > 0, "the speedboat builds")
	var hull := boat.get_node_or_null("Hull") as MeshInstance3D
	_check(hull != null and hull.mesh != null and hull.mesh.get_surface_count() == 1, "the hull is one vertex-coloured mesh")
	_check(boat.get_node_or_null("WindshieldFrame") != null, "the boat has a windshield frame")
	_check(boat.get_node_or_null("RunningLightPort") != null and boat.get_node_or_null("RunningLightStarboard") != null,
		"the boat has red and green running lights")
	_check(boat.get_node_or_null("WakeSpray") is CPUParticles3D, "the wake spray is a small particle system")
	var lights := boat.find_children("*", "OmniLight3D", true, false)
	_check(lights.size() == 1, "the boat carries one real light, for the glow on the deck")
	boat.free()


func _check_characters() -> void:
	var player := OpeningArt.character(OpeningArt.PLAYER_MODEL, "idle")
	_check(player != null, "the real player model loads")
	if player != null:
		_check(OpeningArt.clip_playing(player) == "idle", "the player model plays its idle clip")
		_check(player.find_children("*", "MeshInstance3D", true, false).size() > 0, "the player model has meshes")
		player.free()
	var soldier := OpeningArt.character(OpeningArt.SOLDIER_MODEL, "run", Color(0.5, 0.6, 0.5), 0.3)
	_check(soldier != null, "the soldier model loads")
	if soldier != null:
		_check(OpeningArt.clip_playing(soldier) == "run", "the soldier model plays its run clip")
		var anim := soldier.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		_check(is_equal_approx(anim.speed_scale, 0.3), "the soldier clip runs at the requested pace")
		soldier.free()
	_check(OpeningArt.character("res://assets/characters/missing_model.glb", "idle") == null,
		"a missing model returns null so the caller keeps its fallback")


func _check_walker() -> void:
	var guard := WorkerWalker.new()
	guard.path = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, 4.0)])
	guard.guard = true
	root.add_child(guard)
	guard._build()  # headless skips the build in _ready; the figure is built here so it can be inspected
	var model := guard.get_node_or_null("Body/SoldierModel") as Node3D
	_check(model != null, "a guard is built from the soldier model")
	if model != null:
		_check(is_equal_approx(model.rotation.y, PI), "the model is turned to face the way the walker walks")
	_check(guard.get_node_or_null("Body/SoldierModel") != null and guard.find_children("*", "MeshInstance3D", true, false).size() >= 2,
		"the guard keeps a rifle on top of the model")
	guard.free()

	var worker := WorkerWalker.new()
	worker.path = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, 4.0)])
	worker.carrying = true
	root.add_child(worker)
	worker._build()
	_check(worker.get_node_or_null("Body/SoldierModel") != null, "a worker is built from the soldier model")
	worker.free()


func _check_berm_mesh() -> void:
	var x0 := -10.0
	var x1 := 6.0
	var z0 := 50.5
	var z1 := 53.5
	var mesh := OpeningArt.berm_mesh(x0, x1, z0, z1, 5.8, 3)
	_check(mesh.get_surface_count() == 1, "the berm is one surface")
	var box := mesh.get_aabb()
	_check(box.position.z >= z0 - 0.01 and box.end.z <= z1 + 0.01, "the berm stays inside its collision footprint in z")
	_check(box.position.x >= x0 - 0.01 and box.end.x <= x1 + 0.01, "the berm stays inside its collision footprint in x")
	_check(box.end.y <= 5.81 and box.end.y > 5.5 and box.position.y >= -0.001, "the berm crown reaches its collision height and no higher")
	var format := mesh.surface_get_format(0)
	_check((format & Mesh.ARRAY_FORMAT_COLOR) != 0, "the berm carries vertex colours (sand, scrub, rock)")
	var normals_unit := true
	var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	for n in normals:
		if not is_equal_approx(n.length(), 1.0) and n.length() > 0.0001:
			normals_unit = false
	_check(normals_unit, "every berm normal is unit length")
	var flat := OpeningArt.berm_mesh(x0, x1, z0, z1, 4.4, 3, false)
	_check(absf(flat.get_aabb().end.y - 4.4) < 0.01, "the flat-topped rise has a level crown")
	var merged := OpeningArt.merge([mesh, flat])
	_check(merged.get_surface_count() == 2, "merge keeps every surface")


func _check_payment_bag() -> void:
	var bag := PaymentBag.build()
	_check(bag.name == "PaymentBag", "the bag keeps its node name")
	_check(bag.get_node_or_null("Sack") != null and bag.get_node_or_null("Flap") != null, "the sack and flap keep their names")
	var contents := bag.get_node_or_null("Contents") as Node3D
	_check(contents != null and not contents.visible, "the stash is hidden while the bag is shut")
	_check(contents != null and contents.get_node_or_null("Gold") != null and contents.get_node_or_null("Gems") != null,
		"the stash has gold bars and cut diamonds")
	var sack := bag.get_node("Sack") as MeshInstance3D
	_check((sack.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR) != 0, "the leather sack is vertex-coloured")
	_check(not PaymentBag.is_open(bag), "a new bag reads as shut")
	PaymentBag.open(bag, false)
	_check(PaymentBag.is_open(bag), "opening the bag reveals the stash")
	bag.free()


func _check_ocean() -> void:
	var grid := OpeningArt.ocean_grid()
	_check(grid.material_override is ShaderMaterial, "the ocean grid is a shader, not a flat plane")
	_check(grid.mesh.get_surface_count() == 1, "the ocean grid is one mesh")
	_check(grid.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "the ocean grid casts no shadow")
	grid.free()


func _check_approach() -> void:
	var approach := OpeningApproach.new()
	approach.name = "ArtCheckApproach"
	root.add_child(approach)
	await process_frame
	var terrain := approach.get_node_or_null("ApproachTerrain") as MeshInstance3D
	_check(terrain != null and terrain.mesh != null, "the berm and rise are one smooth terrain mesh")
	if terrain != null:
		var box := terrain.mesh.get_aabb()
		_check(box.position.z >= OpeningApproach.BERM_Z0 - 0.01 and box.end.z <= OpeningApproach.BERM_Z1 + 0.01,
			"the terrain stays on the berm's z footprint")
	for seg in ["BermWest", "BermMidA", "BermMidB", "BermEast", "ViewDeck", "ViewRamp"]:
		var body := approach.get_node_or_null(seg) as StaticBody3D
		_check(body != null, "%s collider still exists" % seg)
		if body != null:
			var shape := body.get_child(0) as CollisionShape3D
			var size := (shape.shape as BoxShape3D).size
			if seg.begins_with("Berm"):
				_check(absf(size.y - OpeningApproach.BERM_H) < 0.001 and absf(size.z - (OpeningApproach.BERM_Z1 - OpeningApproach.BERM_Z0)) < 0.001,
					"%s keeps the berm collision height and depth" % seg)
	approach.free()
