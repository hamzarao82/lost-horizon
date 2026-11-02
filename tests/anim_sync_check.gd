extends SceneTree
## Headless checks for the visual adapter (SkinnedVisual / AnimationDriver / WeaponSocket):
##   godot --headless --path . -s tests/anim_sync_check.gd
## Uses tests/fixtures/humanoid_fixture.glb for exact contract checks, and validates the real
## character and weapon files in assets/ when they exist. Exits non-zero on failure.

const FIXTURE: String = "res://tests/fixtures/humanoid_fixture.glb"
const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const SOLDIER_SCENE: String = "res://scenes/enemies/PatrolSoldier.tscn"
const HEAVY_SCENE: String = "res://scenes/enemies/HeavySoldier.tscn"
const BONES: Array[String] = [
	"Hips", "Spine", "Chest", "Neck", "Head", "UpperArm_L", "LowerArm_L", "Hand_L", "UpperArm_R",
	"LowerArm_R", "Hand_R", "UpperLeg_L", "LowerLeg_L", "Foot_L", "UpperLeg_R", "LowerLeg_R", "Foot_R",
]
const CLIPS: Array[String] = [
	"idle", "walk", "run", "sprint", "jump_start", "fall", "land", "light_1", "light_2", "light_3",
	"heavy", "sprint_attack", "air_attack", "spin", "dodge", "hit", "death", "guard",
]
const BOSS_CLIPS: Array[String] = ["slam", "flurry", "shockwave_cast", "roar"]
const CHARACTERS: Array[String] = ["player", "soldier", "heavy", "elite", "warden"]

var _failures: int = 0
var _checks: int = 0


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


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 1.0, 60.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(ground)
	_test_mapping()
	await _test_driver_fallbacks()
	await _test_missing_and_broken_model()
	await _test_player_adapter()
	await _test_enemy_adapter()
	await _test_equipment_sockets()
	_test_real_assets()
	_test_gameplay_numbers()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- helpers ---------------------------------------------------------------------

func _spawn(scene_path: String, model: String) -> CharacterBody3D:
	var body := (load(scene_path) as PackedScene).instantiate() as CharacterBody3D
	(body.get_node("VisualRoot/SkinnedVisual") as SkinnedVisual).model_path = model
	body.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(body)
	for i in 12:  # let it settle on the floor so is_on_floor() is true
		await physics_frame
	body.set_physics_process(false)  # the test drives the fields gameplay would set
	await _frames(3)
	return body


func _visual(body: Node) -> SkinnedVisual:
	return body.get_node("VisualRoot/SkinnedVisual") as SkinnedVisual


func _clip_position(visual: SkinnedVisual) -> float:
	return visual.driver.player.current_animation_position


# --- pure functions ----------------------------------------------------------------

func _test_mapping() -> void:
	print("Attack clip mapping")
	var length := 0.8
	_check(is_zero_approx(AnimationDriver.attack_clip_position(0.0, 6.0, 20.0, length)), "frame 0 is the start of the clip")
	_check(is_equal_approx(AnimationDriver.attack_clip_position(20.0, 6.0, 20.0, length), length), "the last frame is the end of the clip")
	_check(is_equal_approx(AnimationDriver.attack_clip_position(6.0, 6.0, 20.0, length), 0.35 * length),
			"the first active frame lands exactly on the 35% strike")
	var mid := AnimationDriver.attack_clip_position(13.0, 6.0, 20.0, length)
	_check(mid > 0.35 * length and mid < length, "recovery frames fall between the strike and the end")
	_check(is_equal_approx(AnimationDriver.attack_clip_position(10.0, 6.0, 20.0, length, false), 0.5 * length),
			"plain mode is frames / total * length")
	_check(AnimationDriver.attack_clip_position(99.0, 6.0, 20.0, length) <= length, "frames past the end clamp to the clip length")
	_check(is_zero_approx(AnimationDriver.attack_clip_position(5.0, 6.0, 0.0, length)), "a zero total is safe")
	var previous := -1.0
	var monotonic := true
	for f in range(0, 21):
		var pos := AnimationDriver.attack_clip_position(float(f), 6.0, 20.0, length)
		monotonic = monotonic and pos >= previous
		previous = pos
	_check(monotonic, "the clip position never goes backwards as frames advance")
	_check(AnimationDriver.canonical("Armature|Light_1") == "light_1", "exporter prefixes and capitals are normalised")
	var light := load("res://resources/attacks/light_1.tres") as AttackData
	var heavy_swing := load("res://resources/attacks/heavy_swing.tres") as AttackData
	var slam := load("res://resources/attacks/warden_slam.tres") as AttackData
	_check(SkinnedVisual.clip_for(light) == "light_1" and SkinnedVisual.clip_for(heavy_swing) == "heavy"
			and SkinnedVisual.clip_for(slam) == "slam", "attacks map to clips by id")


func _test_driver_fallbacks() -> void:
	print("Clip fallbacks")
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip_name in ["idle", "walk", "light_1"]:
		var anim := Animation.new()
		anim.length = 1.0
		library.add_animation(clip_name, anim)
	player.add_animation_library("", library)
	var host := Node3D.new()
	host.add_child(player)
	root.add_child(host)
	var driver := AnimationDriver.new()
	_check(driver.setup(player, host), "setup works with a minimal set of clips")
	_check(driver.resolve("walk") == &"walk", "an existing clip resolves to itself")
	_check(driver.resolve("sprint") == &"walk", "sprint falls back to walk when run is missing")
	_check(driver.resolve("guard") == &"idle", "guard falls back to idle")
	_check(driver.resolve("light_3") == &"light_1" and driver.resolve("slam") == &"light_1",
			"light_3 and boss moves fall back to light_1")
	_check(driver.resolve("no_such_clip") == &"" and not driver.has_clip("no_such_clip"), "unknown clips resolve to nothing")
	_check(not driver.scrub("no_such_clip", 0.2), "scrubbing a missing clip returns false and does nothing")
	driver.play_state(&"death")  # no death clip, no tree state: must not error
	await process_frame
	await process_frame
	_check(driver.current_state() == &"death" and driver.resolve("death") == &"idle" and not driver.has_exact("death"),
			"a missing death clip uses a fallback clip instead of failing")
	driver.play_state(&"bogus_state")
	await process_frame
	await process_frame
	_check(driver.current_state() == &"loco", "an unknown tree state falls back to locomotion")
	_check(driver.scrub("light_1", 0.5) and driver.scrubbing, "scrubbing an existing clip switches to scrub mode")
	_check(is_equal_approx(player.current_animation_position, 0.5), "scrub holds the exact requested position")
	driver.end_scrub()
	_check(not driver.scrubbing and driver.tree.active, "leaving scrub mode hands the skeleton back to the tree")
	var empty := AnimationDriver.new()
	_check(not empty.setup(AnimationPlayer.new(), host), "a player without animations is rejected")
	host.free()


func _test_missing_and_broken_model() -> void:
	print("Missing and broken models")
	var missing := await _spawn(PLAYER_SCENE, "res://assets/characters/does_not_exist.glb")
	var rig := missing.get_node("VisualRoot/HumanoidRig") as HumanoidRig
	_check(not _visual(missing).is_skinned() and rig.visible, "a missing model keeps the procedural rig visible")
	_check((missing.get_node("VisualRoot/MeshInstance3D") as MeshInstance3D).visible, "...and the torso mesh")
	_check(_visual(missing).get_node_or_null("ProceduralFallback") != null, "...with a procedural fallback adapter in place")
	missing.free()
	var weapon_glb := "res://assets/weapons/claymore.glb"
	if ResourceLoader.exists(weapon_glb):
		var broken := await _spawn(PLAYER_SCENE, weapon_glb)  # a real GLB, but no skeleton or animations
		_check(not _visual(broken).is_skinned() and (broken.get_node("VisualRoot/HumanoidRig") as Node3D).visible,
				"a GLB without a skeleton is rejected and the rig stays")
		broken.free()
	await _frames(2)


# --- player ----------------------------------------------------------------------

func _test_player_adapter() -> void:
	print("Player adapter")
	var player := await _spawn(PLAYER_SCENE, FIXTURE) as Player
	var visual := _visual(player)
	_check(visual.is_skinned() and visual.driver != null and visual.driver.has_tree(), "the fixture loads, with an AnimationTree built in code")
	_check(not (player.get_node("VisualRoot/HumanoidRig") as Node3D).visible, "the procedural rig is hidden when a model loads")
	_check(not (player.get_node("VisualRoot/MeshInstance3D") as MeshInstance3D).visible, "the old torso mesh is hidden but still in the tree")
	_check((player.get_node("VisualRoot/MeshInstance3D") as MeshInstance3D).material_override != null
			or (player.get_node("VisualRoot/MeshInstance3D") as MeshInstance3D).get_surface_override_material(0) != null,
			"...as the material source for hit flashes")
	for node_path in ["VisualRoot", "VisualRoot/WeaponPivot", "VisualRoot/WeaponPivot/Hitbox", "VisualRoot/WeaponPivot/Weapon",
			"HealthComponent", "CameraPivot/SpringArm3D/Camera3D", "CollisionShape3D"]:
		_check(player.get_node_or_null(node_path) != null, "node intact: %s" % node_path)
	var bodies := 0
	for n in player.find_children("*", "CollisionObject3D", true, false):
		bodies += 1
	_check(bodies == 1, "the model adds no physics bodies or areas (only the Hitbox area, found %d)" % bodies)
	_check((player.get_node("VisualRoot/WeaponPivot/Weapon") as Node3D).visible == false, "the code-built swing weapon is hidden")
	var sample_mesh := visual.meshes[0]
	_check(sample_mesh.get_active_material(0) is BaseMaterial3D
			and (sample_mesh.get_active_material(0) as BaseMaterial3D).vertex_color_use_as_albedo,
			"vertex colours are switched on for the character material in code")
	for clip in ["light_1", "heavy", "dodge", "death", "hit", "guard"]:
		_check(visual.has_clip(clip), "clip available: %s" % clip)

	# locomotion by speed (tree mode)
	player.velocity = Vector3(0, 0, 5.0)
	await _frames(4)
	_check(not visual.driver.scrubbing, "free movement uses the tree, not a scrub")
	_check(is_equal_approx(float(visual.driver.tree.get("parameters/loco/blend_position")), 5.0), "locomotion blends by horizontal speed")
	# regression: an idle player must show its own colours (no flat tint over the model)
	var clear_meshes := true
	for mi in visual.meshes:
		clear_meshes = clear_meshes and mi.material_overlay == null
	_check(clear_meshes and not visual._overlay_on, "an idle player has no overlay on its meshes")
	var torso_node := player.get_node("VisualRoot/MeshInstance3D") as MeshInstance3D
	var torso_material := (torso_node.material_override if torso_node.material_override else torso_node.get_surface_override_material(0)) as BaseMaterial3D
	var torso_before := torso_material.albedo_color
	torso_material.albedo_color = Enemy.WINDUP_COLOR
	await _frames(4)
	clear_meshes = true
	for mi in visual.meshes:
		clear_meshes = clear_meshes and mi.material_overlay == null
	_check(clear_meshes, "a player torso tint (whatever its colour) never floods the model")
	torso_material.albedo_color = torso_before
	await _frames(2)
	player.velocity = Vector3.ZERO

	# attacks are scrubbed to the combat frame counter
	var chain: Array = player.get("_chain")
	var light := chain[0] as AttackData
	var heavy := chain[3] as AttackData
	player.state = Player.State.ATTACK
	player.set("_attack_idx", 0)
	for f in [0.0, 3.0, float(light.startup_frames), 12.0, float(light.total_frames())]:
		player.set("_attack_frames", f)
		await _frames(2)
		var length := visual.driver.clip_length("light_1")
		var expected := AnimationDriver.attack_clip_position(f, float(light.startup_frames), float(light.total_frames()), length)
		if f == 12.0:
			_check(visual.driver.player.current_animation == String(visual.driver.resolve("light_1")), "the light_1 clip is the one playing")
		_check(visual.driver.scrubbing and absf(_clip_position(visual) - expected) < 0.001,
				"light_1 at frame %d sits at %.3f s (got %.3f)" % [int(f), expected, _clip_position(visual)])
	player.set("_attack_idx", 3)
	for f in [0.0, 5.0, float(heavy.startup_frames), 20.0]:
		player.set("_attack_frames", f)
		await _frames(2)
		var length := visual.driver.clip_length("heavy")
		var expected := AnimationDriver.attack_clip_position(f, float(heavy.startup_frames), float(heavy.total_frames()), length)
		_check(visual.driver.player.current_animation == String(visual.driver.resolve("heavy"))
				and absf(_clip_position(visual) - expected) < 0.001, "heavy at frame %d sits at %.3f s" % [int(f), expected])
	# the visual never touches combat state
	var idx_before: int = player.get("_attack_idx")
	var frames_before: float = player.get("_attack_frames")
	await _frames(10)
	_check(player.get("_attack_idx") == idx_before and is_equal_approx(player.get("_attack_frames"), frames_before)
			and not (player.get_node("VisualRoot/WeaponPivot/Hitbox") as Hitbox).is_active()
			and player.state == Player.State.ATTACK, "10 more frames of animation change no combat field and open no hitbox")
	player.set("_attack_idx", -1)
	player.state = Player.State.FREE
	await _frames(4)
	_check(not visual.driver.scrubbing, "leaving the attack state returns the skeleton to the tree")
	_check(player.get("_attack_idx") == -1 and player.state == Player.State.FREE, "a finished clip never restarts an attack")

	# dodge: the clip follows dodge_duration, and the gameplay squash is cancelled on the model
	player.state = Player.State.DODGE
	player.set("_dodge_time", player.dodge_duration * 0.5)
	(player.get_node("VisualRoot") as Node3D).scale.y = 0.6
	await _frames(3)
	var dodge_length := visual.driver.clip_length("dodge")
	_check(visual.driver.scrubbing and absf(_clip_position(visual) - dodge_length * 0.5) < 0.001, "the dodge clip follows dodge_duration")
	_check(absf(visual.model.scale.y * 0.6 - 1.8 / visual.authored_height) < 0.001, "the dodge squash on VisualRoot is cancelled on the model")
	(player.get_node("VisualRoot") as Node3D).scale.y = 1.0
	player.state = Player.State.FREE

	# hit and death use the tree
	player.state = Player.State.HIT
	await _frames(25)
	_check(visual.driver.current_state() == &"hit", "hit reaction plays in the tree")
	player.state = Player.State.DEAD
	await _frames(25)
	_check(visual.driver.current_state() == &"death", "death plays in the tree")
	player.state = Player.State.FREE

	# air states: lift the body and let gravity run for real
	player.state = Player.State.FREE
	player.position.y = 14.0  # a long fall, so it is still airborne when we look
	player.set_physics_process(true)
	for i in 24:
		await physics_frame
	await _frames(6)
	_check(not player.is_on_floor() and visual.driver.current_state() == &"fall", "airborne uses the fall state")
	player.set_physics_process(false)
	player.free()
	await _frames(2)


# --- enemies ---------------------------------------------------------------------

func _test_enemy_adapter() -> void:
	print("Enemy adapter")
	var enemy := await _spawn(SOLDIER_SCENE, FIXTURE) as Enemy
	var visual := _visual(enemy)
	_check(visual.is_skinned(), "an enemy loads the model too")
	_check(not (enemy.get_node("VisualRoot/HumanoidRig") as Node3D).visible, "the enemy's procedural rig is hidden")
	_check(visual.hand_socket != null and visual.hand_socket.held() != null, "the enemy holds a weapon in its hand")

	var swing: AttackData = enemy.get("_swing")
	enemy.state = Enemy.State.ATTACK
	for f in [0.0, 15.0, float(swing.startup_frames), 50.0, float(swing.total_frames())]:
		enemy.set("_attack_frames", f)
		await _frames(2)
		var clip := SkinnedVisual.clip_for(swing)
		var expected := AnimationDriver.attack_clip_position(f, float(swing.startup_frames), float(swing.total_frames()), visual.driver.clip_length(clip))
		_check(visual.driver.scrubbing and absf(_clip_position(visual) - expected) < 0.001,
				"enemy swing at frame %d sits at %.3f s (got %.3f)" % [int(f), expected, _clip_position(visual)])
	enemy.state = Enemy.State.CHASE
	await _frames(25)
	_check(not visual.driver.scrubbing and visual.driver.current_state() == &"guard", "a waiting enemy (chase, standing still) uses the guard clip")
	enemy.velocity = Vector3(0, 0, 3.2)
	await _frames(25)
	_check(visual.driver.current_state() == &"loco", "a moving enemy uses locomotion")
	enemy.velocity = Vector3.ZERO

	# flash: the tint the enemy script puts on its torso material shows on the model
	var torso := enemy.get_node("VisualRoot/MeshInstance3D") as MeshInstance3D
	var material := torso.material_override as StandardMaterial3D
	_check(material != null, "the enemy keeps a material on its torso node for tinting")
	await _frames(2)
	var meshes_clear := true
	for mi in visual.meshes:
		meshes_clear = meshes_clear and mi.material_overlay == null
	_check(meshes_clear, "no overlay while the torso material has the body colour")
	material.albedo_color = Color.WHITE
	await _frames(2)
	var meshes_flash := true
	for mi in visual.meshes:
		meshes_flash = meshes_flash and mi.material_overlay != null
	_check(meshes_flash, "a white hit flash on the torso material shows as an overlay on the model")
	var overlay_color := (visual.meshes[0].material_overlay as StandardMaterial3D).albedo_color
	_check(overlay_color.r > 0.9 and overlay_color.a > 0.3, "...in the same colour")
	material.albedo_color = enemy.body_color
	await _frames(2)
	meshes_clear = true
	for mi in visual.meshes:
		meshes_clear = meshes_clear and mi.material_overlay == null
	_check(meshes_clear, "the overlay goes away when the flash ends")
	# regression: a windup telegraph must not turn a detailed model into one flat colour
	material.albedo_color = Enemy.WINDUP_COLOR
	await _frames(2)
	var windup := visual.meshes[0].material_overlay as StandardMaterial3D
	_check(windup != null and windup.blend_mode == BaseMaterial3D.BLEND_MODE_ADD and windup.albedo_color.a <= 0.4,
			"a red windup is an additive, gentle glow (the model's colours stay visible)")
	material.albedo_color = Color(0.2, 0.2, 0.2)
	await _frames(2)
	var dark_tint := visual.meshes[0].material_overlay as StandardMaterial3D
	_check(dark_tint != null and dark_tint.blend_mode == BaseMaterial3D.BLEND_MODE_MIX, "a dark death tint still blends toward the colour")
	material.albedo_color = enemy.body_color
	await _frames(2)
	meshes_clear = true
	for mi in visual.meshes:
		meshes_clear = meshes_clear and mi.material_overlay == null
	_check(meshes_clear, "the overlay is gone again after the telegraph")

	# death: the enemy tips its VisualRoot, the model keeps its own death pose
	enemy.state = Enemy.State.DEAD
	(enemy.get_node("VisualRoot") as Node3D).rotation.x = -PI * 0.5
	await _frames(25)
	_check(visual.driver.current_state() == &"death", "an enemy death plays the death clip")
	_check(absf(visual.model.rotation.x - PI * 0.5) < 0.01, "the VisualRoot tip-over is cancelled on the model")
	enemy.free()

	var heavy := await _spawn(HEAVY_SCENE, FIXTURE) as Enemy
	var heavy_visual := _visual(heavy)
	await _frames(2)
	var world_height := heavy_visual.authored_height * heavy_visual.model.scale.y * (heavy.get_node("VisualRoot") as Node3D).scale.y
	_check(heavy.body_scale > 1.2 and absf(world_height - 1.8 * heavy.body_scale) < 0.02,
			"the model is fitted to the gameplay height 1.8 x body_scale (world height %.2f m)" % world_height)
	heavy_visual.fit_to_gameplay_height = false
	await _frames(2)
	var natural := heavy_visual.authored_height * heavy_visual.model.scale.y * (heavy.get_node("VisualRoot") as Node3D).scale.y
	_check(absf(natural - heavy_visual.authored_height) < 0.02, "with fitting off the model keeps its authored size (%.2f m)" % natural)
	heavy_visual.fit_to_gameplay_height = true
	_check(heavy_visual.hand_socket != null and heavy_visual.hand_socket.held() != null, "a heavy holds its cosmetic weapon")
	heavy.free()
	await _frames(2)


# --- equipment -------------------------------------------------------------------

func _test_equipment_sockets() -> void:
	print("Weapon and armor sockets")
	var player := await _spawn(PLAYER_SCENE, FIXTURE) as Player
	var visual := _visual(player)
	await _frames(3)
	_check(visual.hand_socket != null and visual.hand_socket.bone_name == "Hand_R", "the weapon socket is attached to Hand_R")
	_check(visual.chest_socket != null and visual.chest_socket.bone_name == "Chest", "the armor socket is attached to Chest")
	var first := visual.hand_socket.held()
	_check(first != null, "the starting weapon is in the hand")
	var inventory := player.inventory
	inventory.add_item(load("res://resources/items/military_machete.tres") as ItemData)
	await _frames(3)
	var second := visual.hand_socket.held()
	_check(second != null and second != first, "equipping a better weapon swaps what is in the hand")
	if ResourceLoader.exists("res://assets/weapons/military_machete.glb"):
		_check(second.scene_file_path == "res://assets/weapons/military_machete.glb", "...to the machete model file")
	else:
		_check(second is WeaponModel, "...to the code-built machete (no model file yet)")
	visual.hand_socket.position_offset = Vector3(0.1, 0.0, 0.0)
	_check(is_equal_approx(visual.hand_socket.holder.position.x, 0.1), "the hand offset is adjustable")
	visual.hand_socket.rotation_offset_deg = Vector3(0.0, 90.0, 0.0)
	_check(absf(visual.hand_socket.holder.rotation_degrees.y - 90.0) < 0.01, "the hand rotation is adjustable")
	var plate_file := "res://assets/armor/warden_plate.glb"
	inventory.add_item(load("res://resources/items/warden_plate.tres") as ItemData)
	await _frames(3)
	if ResourceLoader.exists(plate_file):
		_check(visual.chest_socket.held() != null, "the Warden Plate appears on the chest when equipped")
	else:
		_check(visual.chest_socket.held() == null, "no plate model file yet: nothing is drawn, nothing breaks")
	player.free()
	await _frames(2)


# --- real assets -----------------------------------------------------------------

func _test_real_assets() -> void:
	print("Real art files (validated when present)")
	var present := 0
	for character in CHARACTERS:
		var path := "res://assets/characters/%s.glb" % character
		if not ResourceLoader.exists(path):
			print("  note %s not delivered yet" % path)
			continue
		present += 1
		var inst := (load(path) as PackedScene).instantiate() as Node3D
		var skeleton := inst.find_children("*", "Skeleton3D", true, false)
		var players := inst.find_children("*", "AnimationPlayer", true, false)
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		_check(not skeleton.is_empty() and not players.is_empty() and not meshes.is_empty(), "%s has a skeleton, animations and a mesh" % character)
		if not skeleton.is_empty():
			var missing_bones: Array[String] = []
			for bone in BONES:
				if (skeleton[0] as Skeleton3D).find_bone(bone) < 0:
					missing_bones.append(bone)
			_check(missing_bones.is_empty(), "%s has every contract bone%s" % [character, "" if missing_bones.is_empty() else " (missing %s)" % ", ".join(missing_bones)])
		if not players.is_empty():
			var driver := AnimationDriver.new()
			var host := Node3D.new()
			host.add_child(inst)
			root.add_child(host)
			driver.setup(players[0] as AnimationPlayer, inst)
			var absent: Array[String] = []
			var needed: Array[String] = CLIPS.duplicate()
			if character == "warden":
				needed.append_array(BOSS_CLIPS)
			for clip in needed:
				if driver._names.has(clip) == false:
					absent.append(clip)
			if absent.is_empty():
				_check(true, "%s has every contract clip" % character)
			else:
				print("  note %s is missing clips (fallbacks apply): %s" % [character, ", ".join(absent)])
			host.free()
		else:
			inst.free()
	_check(true, "%d of %d character files present" % [present, CHARACTERS.size()])


# --- gameplay numbers --------------------------------------------------------------

func _test_gameplay_numbers() -> void:
	print("Gameplay numbers unchanged")
	var expected: Dictionary = {
		"light_1": [10.0, 6, 4, 10], "light_2": [12.0, 6, 4, 12], "heavy_1": [28.0, 10, 6, 15],
		"enemy_swing": [12.0, 30, 6, 36], "warden_slam": [22.0, 36, 8, 40],
	}
	for id: String in expected:
		var data := load("res://resources/attacks/%s.tres" % id) as AttackData
		var e: Array = expected[id]
		_check(data != null and is_equal_approx(data.damage, e[0]) and data.startup_frames == e[1]
				and data.active_frames == e[2] and data.recovery_frames == e[3], "%s: damage and frame data are unchanged" % id)
	var blade := load("res://resources/items/warden_blade.tres") as ItemData
	var plate := load("res://resources/items/warden_plate.tres") as ItemData
	_check(is_equal_approx(blade.damage_multiplier, 2.3) and is_equal_approx(plate.armor_points, 140.0),
			"Warden's Cleaver x2.30 and Warden Plate 140 armor are unchanged")
