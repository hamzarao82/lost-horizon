extends SceneTree
## A patrol squad held back by the four-patroller cap must still appear once there is room and the player is near,
## and the arrow must lead to a squad that has not appeared. (The old code never retried: an unseen "last enemy".)
## godot --headless --path . -s tests/patrol_retry_check.gd   (uses SaveManager's per-process test file)

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


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _run() -> void:
	var qm := root.get_node("QuestManager")
	var rm := root.get_node("RegionManager")
	var sm := root.get_node("SaveManager")
	await _frames(3)
	sm.reset_runtime_state()
	sm.delete_save()
	qm.intro_done = true
	qm.mission_autosave = false
	qm.reset()
	var main: Node = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	main.get_node("WaveManager").autostart = false
	root.add_child(main)
	await _frames(46)
	rm.unlock(&"dead_coast")
	await rm.travel(&"dead_coast", &"from_outpost", null, true)
	await _frames(60)
	var player := main.get_tree().get_first_node_in_group("player") as Node3D
	var squads: Array[PatrolGroup] = []
	for node in root.find_children("*", "PatrolGroup", true, false):
		squads.append(node as PatrolGroup)
	_check(squads.size() >= 5, "Dead Coast has its patrol squads (%d)" % squads.size())
	var camp: PatrolGroup = null
	for squad in squads:
		if squad.group_id == &"dead_coast_camp":
			camp = squad
	_check(camp != null and not camp.spawned, "the camp squad has not appeared yet")
	if camp == null:
		quit(1)
		return

	# 1) The cap is full: the squad is held back, and it remembers that.
	Enemy.active_patrollers = PatrolGroup.MAX_ACTIVE_PATROLLERS
	_check(camp.spawn() == 0 and not camp.spawned and camp._blocked, "with the cap full the squad is held back and marked blocked")

	# 2) Too far away: it keeps waiting.
	player.global_position = camp.to_global(camp.route_points[0]) + Vector3(0.0, 0.5, PatrolGroup.RETRY_RADIUS + 60.0)
	Enemy.active_patrollers = 0
	camp.call("_process", 1.5)
	_check(not camp.spawned, "room is free but the player is far away: it keeps waiting")

	# 3) The player comes near and there is room: it appears.
	player.global_position = camp.to_global(camp.route_points[0]) + Vector3(0.0, 0.5, 20.0)
	camp.call("_process", 1.5)
	await _frames(5)
	_check(camp.spawned and camp.enemies.size() == camp.scene_paths.size(), "near the player with room free the squad appears (%d members)" % camp.enemies.size())

	# 4) While the cap stays full it keeps trying, and then gets in as soon as a slot frees up.
	var checkpoint: PatrolGroup = null
	for squad in squads:
		if squad.group_id == &"dead_coast_checkpoint":
			checkpoint = squad
	Enemy.active_patrollers = PatrolGroup.MAX_ACTIVE_PATROLLERS
	checkpoint.spawn()
	player.global_position = checkpoint.to_global(checkpoint.route_points[0]) + Vector3(0.0, 0.5, 15.0)
	checkpoint.call("_process", 1.5)
	_check(not checkpoint.spawned, "still blocked while the cap is full")
	Enemy.active_patrollers = 0
	checkpoint.call("_process", 1.5)
	await _frames(5)
	_check(checkpoint.spawned, "it appears the moment room frees up")

	# 5) The arrow leads to a squad that has not appeared when nobody is alive.
	for enemy in root.get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy):
			enemy.queue_free()
	await _frames(3)
	var pointers := main.find_children("*", "ObjectivePointer", true, false)
	_check(pointers.size() == 1, "the HUD has one objective pointer")
	if pointers.size() == 1:
		var pointer := pointers[0] as ObjectivePointer
		pointer.target = null  # _resolve_for clears these before it aims; do the same here
		pointer.label = ""
		pointer.call("_point_at_nearest_enemy")
		_check(pointer.target != null and pointer.label == "Patrol", "with no enemy alive the arrow says Patrol and leads to the waiting squad (%s)" % pointer.label)

	Enemy.active_patrollers = 0
	sm.reset_runtime_state()
	sm.delete_save()
	print("patrol_retry_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
