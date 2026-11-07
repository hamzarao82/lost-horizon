extends SceneTree
## Facility Commander checks (Milestone 8): godot --headless --path . -s tests/facility_commander_check.gd
## A real Commander fights a real Player on a private floor far from the arena.

const ORIGIN: Vector3 = Vector3(200.0, 0.0, 200.0)
const TRAUMA_KIT: String = "facility_trauma_kit"

var _failures: int = 0
var _checks: int = 0
var _main: Node
var _player: Player
var _cfg: EnemyConfig
var _pin_at: Vector3


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	print(("  ok   " if condition else "  FAIL "), message)
	if not condition:
		_failures += 1


func _frames(count: int) -> void:
	for i in count:
		_pin()
		await physics_frame


func _pin() -> void:
	_player.global_position = _pin_at
	_player.velocity = Vector3.ZERO


func _setup(player_offset: Vector3 = Vector3(0.0, 0.1, 10.0)) -> void:
	Projectile.reset_pool()
	if is_instance_valid(_main):
		_main.queue_free()
		await physics_frame
		await physics_frame
		await physics_frame
	_main = (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	_main.get_node("WaveManager").autostart = false
	root.add_child(_main)
	for i in 3:
		await physics_frame
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = ORIGIN + Vector3(0.0, -0.5, 0.0)
	_main.add_child(floor_body)
	_player = _main.get_node("Player") as Player
	_player.health.max_health = 100000.0
	_player.health.health = 100000.0
	_pin_at = ORIGIN + player_offset
	_pin()
	await _frames(2)


func _commander(at: Vector3, fight: bool = true) -> Enemy:
	var c := _cfg.spawn(_main, at)
	await _frames(3)
	if fight:
		c.aggro()
		c._cooldown = 0.0
	return c


func _flat_dist(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _trauma_pickups() -> Array:
	var found: Array = []
	for node in _main.find_children("*", "Pickup", true, false):
		var pickup := node as Pickup
		if pickup != null and pickup.item != null and String(pickup.item.item_id) == TRAUMA_KIT:
			found.append(pickup)
	return found


func _kill(c: Enemy) -> void:
	var heavy := load("res://resources/attacks/heavy_1.tres") as AttackData
	for i in 60:
		if c.is_dead():
			break
		c.receive_hit(heavy, c.global_position + Vector3(0.0, 0.0, 2.0))
		await physics_frame
	await _frames(6)


func _run() -> void:
	_cfg = load("res://resources/enemies/facility_commander.tres") as EnemyConfig
	await _setup()
	await _test_config()
	await _test_timeline()
	await _test_interrupt()
	await _test_no_line_of_sight()
	await _test_retreat()
	await _test_shove()
	await _test_unique_drop()
	await _test_ally_alert()
	await _test_defaults()
	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_config() -> void:
	print("Configuration")
	var c := await _commander(ORIGIN, false)
	_check(c.display_name == "Commander" and is_equal_approx(c.hit_points, 110.0), "a Commander with 110 health")
	_check(is_equal_approx(c._health.max_armor, 30.0) and is_equal_approx(c._health.armor, 30.0), "armor pool 30")
	_check(c.ranged != null and c._ranged_brain != null, "it has ranged behaviour")
	_check(c.coordinate_alarm, "it alerts nearby allies")
	_check(c.loot_table_path.ends_with("hunter_loot.tres"), "elite loot tier")
	_check(c.swing_path.ends_with("ranged_shove.tres"), "its melee swing is the shove")
	var health_before: float = c._health.health
	c.receive_hit(load("res://resources/attacks/light_1.tres") as AttackData, c.global_position + Vector3(0.0, 0.0, 2.0))
	_check(c._health.armor < 30.0 and is_equal_approx(c._health.health, health_before), "armor drains before health when the player hits it")


func _test_timeline() -> void:
	print("Attack timeline (telegraph, burst, recovery)")
	await _setup()
	var c := await _commander(ORIGIN)
	var brain: RangedBrain = c._ranged_brain
	var health_before: float = _player.health.health
	var start := -1
	var shot_frames: Array[int] = []
	var seen := 0
	var end := -1
	var first_dir := Vector3.ZERO
	var last_dir := Vector3.ZERO
	for f in 600:
		_pin()
		await physics_frame
		if start < 0 and c.state == Enemy.State.RANGED_ATTACK:
			start = f
		if brain.shots_fired > seen:
			seen = brain.shots_fired
			shot_frames.append(f)
			if shot_frames.size() == 1:
				first_dir = brain.aim_direction()
			last_dir = brain.aim_direction()
		if start >= 0 and shot_frames.size() >= 3 and c.state == Enemy.State.CHASE:
			end = f
			break
	_check(start >= 0, "it starts a ranged attack at 10 m with a clear line (frame %d)" % start)
	_check(shot_frames.size() == 3, "a burst fires exactly 3 shots (%d)" % shot_frames.size())
	if shot_frames.size() >= 3:
		var telegraph: int = shot_frames[0] - start
		_check(telegraph >= 36, "telegraph before the first shot: %d frames (>= 36 = 0.6 s)" % telegraph)
		var gap1: int = shot_frames[1] - shot_frames[0]
		var gap2: int = shot_frames[2] - shot_frames[1]
		_check(gap1 >= 15 and gap2 >= 15, "shot spacing %d and %d frames (>= 15 = 0.25 s)" % [gap1, gap2])
		var recovery: int = end - shot_frames[2]
		_check(recovery >= 30, "recovery after the last shot: %d frames (>= 30 = 0.5 s)" % recovery)
	_check(brain.shots_fired == 3, "no extra shot fires during recovery (%d total)" % brain.shots_fired)
	_check(first_dir.is_equal_approx(last_dir), "the aim is committed: every shot of the burst uses one direction")
	var lost: float = health_before - _player.health.health
	_check(is_equal_approx(fmod(lost, 8.0), 0.0) and lost <= 24.0, "damage is 8 per hit and at most 3 hits (%.1f)" % lost)
	_check(Projectile.live_count() <= 3, "shots stay within the live cap")


func _test_interrupt() -> void:
	print("Interrupted telegraph")
	await _setup()
	var c := await _commander(ORIGIN)
	var brain: RangedBrain = c._ranged_brain
	for f in 200:
		_pin()
		await physics_frame
		if c.state == Enemy.State.RANGED_ATTACK:
			break
	_check(c.state == Enemy.State.RANGED_ATTACK and brain.phase == RangedBrain.Phase.TELEGRAPH, "it is telegraphing")
	await _frames(10)
	c.receive_hit(load("res://resources/attacks/light_1.tres") as AttackData, c.global_position + Vector3(0.0, 0.0, 2.0))
	_check(c.state == Enemy.State.STAGGER and brain.phase == RangedBrain.Phase.NONE, "a hit staggers it and cancels the telegraph")
	await _frames(25)
	_check(brain.shots_fired == 0 and Projectile.live_count() == 0, "no shot is fired by an interrupted attack")


func _test_no_line_of_sight() -> void:
	print("No line of sight")
	await _setup()
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 4.0, 0.5)
	shape.shape = box
	wall.add_child(shape)
	wall.position = ORIGIN + Vector3(0.0, 2.0, 5.0)
	_main.add_child(wall)
	var c := await _commander(ORIGIN)
	var brain: RangedBrain = c._ranged_brain
	var attacked := false
	for f in 240:
		_pin()
		await physics_frame
		if c.state == Enemy.State.RANGED_ATTACK:
			attacked = true
	_check(not attacked and brain.shots_fired == 0, "it never starts or fires an attack through a wall")
	_check(Projectile.live_count() == 0, "no projectile was fired")


func _test_retreat() -> void:
	print("Distance band")
	await _setup(Vector3(0.0, 0.1, 4.0))
	var c := await _commander(ORIGIN)
	c._cooldown = 99.0  # isolate the movement
	var before := _flat_dist(c, _player)
	await _frames(60)
	var after := _flat_dist(c, _player)
	_check(after > before + 1.5, "inside the band minimum it backs away (%.1f m to %.1f m)" % [before, after])


func _test_shove() -> void:
	print("Close range shove")
	await _setup(Vector3(0.0, 0.1, 1.6))
	var c := await _commander(ORIGIN)
	var shoved := false
	for f in 30:
		_pin()
		await physics_frame
		if c.state == Enemy.State.ATTACK:
			shoved = true
			break
	_check(shoved, "within 2 m it uses the melee shove instead of shooting")
	_check((c._ranged_brain as RangedBrain).shots_fired == 0, "no projectile fired point-blank")


func _test_unique_drop() -> void:
	print("Unique medical drop")
	await _setup()
	var c := await _commander(ORIGIN, false)
	await _kill(c)
	_check(c.is_dead(), "the Commander can be defeated")
	_check(_trauma_pickups().size() == 1, "the first kill drops the unique trauma kit (%d)" % _trauma_pickups().size())
	for pickup in _trauma_pickups():
		(pickup as Node).queue_free()
	await _frames(3)
	_player.inventory.unique_claimed[TRAUMA_KIT] = true  # as if it had been collected
	var second := await _commander(ORIGIN + Vector3(3.0, 0.0, 0.0), false)
	await _kill(second)
	_check(second.is_dead() and _trauma_pickups().is_empty(), "once claimed it never drops again")


func _test_ally_alert() -> void:
	print("Ally alert")
	await _setup()
	# The ally exists before the Commander can notice the player, or the alarm would fire with nobody to hear it.
	var ally := (load("res://scenes/enemies/PatrolSoldier.tscn") as PackedScene).instantiate() as Enemy
	ally.position = ORIGIN + Vector3(0.0, 0.0, -6.0)  # 16 m from the player: out of its own sight range
	_main.add_child(ally)
	await _frames(3)
	_check(ally.state == Enemy.State.IDLE, "the ally starts idle on its own")
	var c := await _commander(ORIGIN, false)
	await _frames(15)
	_check(c.state != Enemy.State.IDLE, "the Commander notices the player")
	_check(ally.state == Enemy.State.CHASE, "and its nearby ally joins the fight")


func _test_defaults() -> void:
	print("Other enemies are unchanged")
	await _setup()
	var soldier := (load("res://scenes/enemies/PatrolSoldier.tscn") as PackedScene).instantiate() as Enemy
	soldier.position = ORIGIN
	_main.add_child(soldier)
	await _frames(3)
	_check(soldier.ranged == null and soldier._ranged_brain == null, "a plain soldier has no ranged behaviour")
	_check(Enemy.State.RETURN == 8 and Enemy.State.RANGED_ATTACK == 9, "existing State values are unchanged; RANGED_ATTACK is appended")
