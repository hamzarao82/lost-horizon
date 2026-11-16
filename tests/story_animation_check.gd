extends SceneTree
## Story clips on the real rig: the eight opening clips exist on player.glb and nowhere else, the injured walk
## (limp) hook switches walk to limp_walk and back, the beach mini-scene plays the protagonist's poses in order with
## the real models (the workers limp in the soldier model), and the one-shot hooks (pickup, open_bag) run and hand
## the skeleton back.
##   godot --headless --path . -s tests/story_animation_check.gd

const STORY: Array[String] = ["lying_idle", "wake", "sit_up", "hold_side", "stand_up", "limp_walk", "pickup", "open_bag"]
const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const ENEMY_SCENE: String = "res://scenes/enemies/PatrolSoldier.tscn"

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
	await _test_player_clips()
	await _test_injured_walk()
	await _test_beach_timeline()
	await _test_one_shots()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_player_clips() -> void:
	print("Story clips on the player rig")
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(2)
	var visual := player.get_node("VisualRoot/SkinnedVisual") as SkinnedVisual
	_check(visual != null and visual.is_skinned(), "the player is drawn by the skinned model")
	var missing: Array[String] = []
	for clip in STORY:
		if not visual.driver.has_exact(clip):
			missing.append(clip)
	_check(missing.is_empty(), "all eight story clips are on player.glb (missing: %s)" % ", ".join(missing))
	for clip in ["lying_idle", "hold_side", "limp_walk"]:
		_check(AnimationDriver.LOOPING.has(clip), "%s loops" % clip)
	for clip in ["wake", "sit_up", "stand_up", "pickup", "open_bag"]:
		_check(not AnimationDriver.LOOPING.has(clip), "%s plays once" % clip)
	var soldier := (load("res://assets/characters/soldier.glb") as PackedScene).instantiate() as Node3D
	var soldier_ap := soldier.find_children("*", "AnimationPlayer", true, false)
	var has_limp := false
	var has_core := false
	if not soldier_ap.is_empty():
		has_limp = (soldier_ap[0] as AnimationPlayer).has_animation(&"limp_walk")
		has_core = (soldier_ap[0] as AnimationPlayer).has_animation(&"idle")
	_check(has_core and not has_limp, "the soldier file keeps its own clips and has no story clip")
	soldier.free()
	player.queue_free()
	await _frames(1)


func _test_injured_walk() -> void:
	print("Injured walk hook")
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(2)
	var visual := player.get_node("VisualRoot/SkinnedVisual") as SkinnedVisual
	var driver := visual.driver
	player.injured_speed_mult = 1.0
	visual.update(0.016)
	_check(not driver.limp, "healthy: the limp flag is off")
	driver.set_speed(3.0)
	driver.play_state(&"loco")
	_check(driver._current_state == &"loco", "healthy: running plays the normal locomotion blend")
	player.injured_speed_mult = 0.55
	visual.update(0.016)
	_check(driver.limp, "injured (x0.55): the limp flag is on")
	driver.set_speed(3.0)
	driver.play_state(&"loco")
	_check(driver._current_state == &"limp_walk", "injured and moving: the walk becomes limp_walk")
	driver.set_speed(0.0)
	driver.play_state(&"loco")
	_check(driver._current_state == &"loco", "injured and standing still: idle stays idle")
	driver.set_speed(3.0)
	driver.play_state(&"hit")
	_check(driver._current_state == &"hit", "a hit still plays its own state while injured")
	driver.play_state(&"loco")
	player.injured_speed_mult = 1.0
	visual.update(0.016)
	_check(not driver.limp, "recovered: the limp flag clears")
	player.queue_free()
	await _frames(1)


func _test_beach_timeline() -> void:
	print("Beach mini-scene")
	var beach := OpeningBeach.new()
	root.add_child(beach)  # its _ready runs the real-time sequence; this test only builds the scene and steps the clock
	await _frames(1)
	beach._build_scene()
	_check(beach._hero_visual != null and beach._hero_visual.loaded, "the protagonist is the real skinned player model")
	_check(beach._hero_visual != null and beach._hero_visual.model_path == OpeningBeach.PLAYER_MODEL, "...loaded from player.glb")
	_check(beach._guard_visual != null and beach._guard_visual.model_path == OpeningBeach.SOLDIER_MODEL, "the guard is the soldier model")
	_check(beach._worker_visuals.size() == 2, "two worker visuals on the soldier model (%d)" % beach._worker_visuals.size())
	var hero_anim := beach._hero_visual.driver.player
	_check(hero_anim.current_animation == "lying_idle", "the protagonist starts lying (lying_idle)")
	var workers_limp := true
	for visual in beach._worker_visuals:
		workers_limp = workers_limp and visual.driver.player.current_animation == "limp_walk"
	_check(workers_limp, "the workers limp on limp_walk while they are dragged in")
	var expected: Array = [[3.9, "lying_idle"], [4.1, "wake"], [7.1, "sit_up"], [9.1, "stand_up"], [11.0, "hold_side"]]
	var clock := 0.0
	for step in expected:
		while clock < float(step[0]):
			beach._step_scene(0.05)
			clock += 0.05
		_check(hero_anim.current_animation == step[1],
				"at %.1f s the protagonist is in %s (is %s)" % [step[0], step[1], hero_anim.current_animation])
	_check(is_equal_approx(beach._workers[0].scale.x, OpeningBeach.WORKER_SCALE),
			"workers are a little smaller (x%.2f)" % OpeningBeach.WORKER_SCALE)
	var tinted := false
	for mi in beach._worker_visuals[0].meshes:
		if mi.mesh != null and mi.get_surface_override_material(0) is BaseMaterial3D:
			tinted = true
	_check(tinted, "workers carry a tinted copy of the soldier material")
	while clock < 10.5:
		beach._step_scene(0.05)
		clock += 0.05
	_check(not beach._worker_visuals[0].driver.scrubbing, "once the guard has arrived the workers stand (limp released)")
	beach.queue_free()
	await _frames(2)


func _test_one_shots() -> void:
	print("One-shot story clips (pickup, open_bag)")
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	root.add_child(player)
	await _frames(2)
	var driver := (player.get_node("VisualRoot/SkinnedVisual") as SkinnedVisual).driver
	var length := AnimationDriver.play_on(player, "pickup", 1.6)
	# the glTF export rounds the clip to whole frames at 30 fps, so the stored length is about 1.2 s (not exact)
	_check(absf(length - 1.2 / 1.6) < 0.06, "pickup plays at x1.6 (%.3f s)" % length)
	_check(driver.player.current_animation == "pickup", "the pickup clip is on the player's skeleton")
	driver.set_speed(4.0)
	driver.play_state(&"loco")
	_check(driver.player.current_animation == "pickup", "gameplay locomotion does not interrupt the pickup")
	driver.release_story()
	driver.play_state(&"loco")
	_check(not driver.scrubbing and driver._current_state == &"loco", "after the pickup the tree takes the skeleton back")
	var bag := AnimationDriver.play_on(player, "open_bag", 0.7)
	_check(bag > 4.0, "open_bag plays slowly enough for the recovery moment (%.2f s)" % bag)
	_check(driver.player.current_animation == "open_bag", "open_bag is on the skeleton")
	driver.release_story()
	player.queue_free()
	await _frames(1)
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(enemy)
	await _frames(2)
	_check(AnimationDriver.play_on(enemy, "open_bag") == 0.0, "an enemy without the clip is untouched (0.0)")
	_check(AnimationDriver.play_on(null, "pickup") == 0.0, "no body is a safe no-op")
	enemy.queue_free()
	await _frames(1)
