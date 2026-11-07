class_name RangedBrain
extends RefCounted
## Ranged behaviour for an Enemy that was given a RangedConfig. The enemy only forwards two states to
## it (CHASE and RANGED_ATTACK), so every other enemy is untouched.
##
## Attack timeline (all from the config / shot data, so tests can assert fairness):
##   TELEGRAPH  startup_frames of the shot: a red aim line shows where the burst will go; the aim is
##              committed at AIM_LOCK of the telegraph, so a player who moves after that is not hit.
##   BURST      burst_shots projectiles, shot_spacing seconds apart, all along the committed aim.
##   RECOVERY   recovery_frames of the shot: the enemy stands still and can be punished.

enum Phase { NONE, TELEGRAPH, BURST, RECOVERY }

const FPS: float = 60.0
const AIM_LOCK: float = 0.7
const AIM_LINE_LENGTH: float = 14.0
const MUZZLE: Vector3 = Vector3(0.0, 1.15, 0.0)
const COVER_REPATH: float = 0.6
const CORNERED_SECONDS: float = 0.8

var enemy: Enemy
var cfg: RangedConfig
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var phase: Phase = Phase.NONE
## Counters for tests and tuning.
var shots_fired: int = 0
var shots_blocked: int = 0

var _t: float = 0.0
var _shots_left: int = 0
var _shot_clock: float = 0.0
var _aim_dir: Vector3 = Vector3.FORWARD
var _aim_locked: bool = false
var _aim_line: MeshInstance3D
var _strafe_clock: float = 0.0
var _strafe_sign: float = 1.0
var _cover_clock: float = 0.0
var _cover_target: Variant = null


func _init(owner_enemy: Enemy, config: RangedConfig) -> void:
	enemy = owner_enemy
	cfg = config
	rng.randomize()
	_strafe_sign = enemy._strafe_sign


func shot_data() -> AttackData:
	return cfg.shot()


func is_telegraphing() -> bool:
	return phase == Phase.TELEGRAPH


func aim_direction() -> Vector3:
	return _aim_dir


## Stops whatever is happening: no further shot is fired (called on stagger and on death).
func cancel() -> void:
	phase = Phase.NONE
	_aim_locked = false
	_hide_aim()


func has_line_of_sight(target: Node3D) -> bool:
	return CoverPoint.has_line_of_sight(enemy.get_world_3d(), enemy.global_position, target.global_position)


# --- CHASE replacement ------------------------------------------------------

func chase(delta: float) -> void:
	var e := enemy
	if e._dodge_time > 0.0:
		e._dodge_time -= delta  # keep the sidestep velocity set by Enemy._sidestep()
		return
	var player := e._target()
	if player == null or e._flat_to(player).length() > e.lose_range:
		e._release_token()
		if e._has_route():
			if player != null:
				e._last_known = player.global_position
				e._enter_suspicious()
			else:
				e._begin_return()
		else:
			e.state = Enemy.State.IDLE
		return
	var to := e._flat_to(player)
	var dist := to.length()
	var dir := to.normalized() if dist > 0.001 else Vector3.FORWARD
	e._face(dir, delta)
	e._check_stuck(delta)
	var los := has_line_of_sight(player)
	var cornered := e._stuck_time >= CORNERED_SECONDS
	if dist <= cfg.shove_range and e._cooldown <= 0.0:
		e._start_attack()  # the melee swing configured on the enemy: a close-range shove
		return
	if e._cooldown <= 0.0 and los and dist <= cfg.band_max + 3.0 and (dist >= cfg.band_min * 0.5 or cornered):
		_begin_attack()
		return
	_move(delta, player, dir, dist, los)


func _move(delta: float, player: Player, dir: Vector3, dist: float, los: bool) -> void:
	var e := enemy
	if dist < cfg.band_min:
		e._move_horizontal(-dir, e.move_speed * cfg.retreat_speed_factor)
	elif dist > cfg.band_max or not los:
		var goal: Variant = null
		if cfg.use_cover:
			_cover_clock -= delta
			if _cover_clock <= 0.0:
				_cover_clock = COVER_REPATH
				_cover_target = CoverPoint.best_for(e.get_tree(), e.get_world_3d(), e.global_position,
						player.global_position, cfg.band_min, cfg.band_max)
			goal = _cover_target
		if goal != null and e.global_position.distance_to(goal as Vector3) > 0.8:
			var to_goal: Vector3 = (goal as Vector3) - e.global_position
			to_goal.y = 0.0
			e._move_horizontal(to_goal.normalized(), e.move_speed)
		else:
			e._move_horizontal(dir, e.move_speed)
	else:
		_strafe_clock -= delta
		if _strafe_clock <= 0.0 or e._stuck_time >= 0.6:
			_strafe_clock = rng.randf_range(1.2, 2.4)
			_strafe_sign = -_strafe_sign
			e._stuck_time = 0.0
		var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_sign
		e._move_horizontal(side, e.move_speed * cfg.strafe_speed_factor)


# --- RANGED_ATTACK state ----------------------------------------------------

func _begin_attack() -> void:
	var e := enemy
	phase = Phase.TELEGRAPH
	_t = 0.0
	_aim_locked = false
	e.state = Enemy.State.RANGED_ATTACK
	e._attack_frames = 0.0
	e._move_horizontal(Vector3.ZERO, 0.0)
	e.swing_started.emit()
	_sfx(&"enemy_swing_windup", -4.0)
	_show_aim()


func attack_tick(delta: float) -> void:
	var e := enemy
	e._move_horizontal(Vector3.ZERO, 0.0)
	var player := e._target()
	var shot := cfg.shot()
	match phase:
		Phase.TELEGRAPH:
			_t += delta
			e._attack_frames = _t * FPS
			if player != null and not _aim_locked:
				e._face(e._flat_to(player).normalized(), delta)
				if _t >= cfg.telegraph_seconds() * AIM_LOCK:
					_lock_aim(player)
			_update_aim_line(player)
			if _t >= cfg.telegraph_seconds():
				if not _aim_locked and player != null:
					_lock_aim(player)
				phase = Phase.BURST
				_shots_left = cfg.burst_shots
				_shot_clock = 0.0
		Phase.BURST:
			_shot_clock -= delta
			e._attack_frames = float(shot.startup_frames) + 1.0
			if _shot_clock <= 0.0 and _shots_left > 0:
				_fire_one(player)
				_shots_left -= 1
				_shot_clock = cfg.shot_spacing
			if _shots_left <= 0:
				phase = Phase.RECOVERY
				_t = 0.0
				_hide_aim()
		Phase.RECOVERY:
			_t += delta
			e._attack_frames = minf(float(shot.startup_frames + shot.active_frames) + _t * FPS, float(shot.total_frames()))
			if _t >= cfg.recovery_seconds():
				phase = Phase.NONE
				e._cooldown = rng.randf_range(cfg.cooldown_min, cfg.cooldown_max)
				e.state = Enemy.State.CHASE
		_:
			e.state = Enemy.State.CHASE


## Commits the aim: a partial lead on the player's velocity plus a small random error. Shots keep this
## direction even if the player moves afterwards.
func _lock_aim(player: Player) -> void:
	var e := enemy
	var origin := e.global_position + MUZZLE
	var target := player.global_position + Vector3(0.0, 1.0, 0.0)
	var flat_dist := Vector2(target.x - origin.x, target.z - origin.z).length()
	var lead := Vector3(player.velocity.x, 0.0, player.velocity.z) * (flat_dist / cfg.projectile_speed) * cfg.lead_factor
	var aim := (target + lead) - origin
	aim = aim.rotated(Vector3.UP, deg_to_rad(rng.randf_range(-cfg.aim_error_deg, cfg.aim_error_deg)))
	_aim_dir = aim.normalized()
	_aim_locked = true
	e._visual_root.rotation.y = atan2(-_aim_dir.x, -_aim_dir.z)


func _fire_one(player: Player) -> void:
	var e := enemy
	if player == null or not has_line_of_sight(player):
		shots_blocked += 1  # never shoot through a wall
		return
	var origin := e.global_position + MUZZLE + _aim_dir * 0.8
	var p := Projectile.fire(e.get_parent(), origin, _aim_dir, cfg.shot(), e, cfg.projectile_speed, e.damage_mult)
	if p != null:
		shots_fired += 1
		_sfx(&"swing_light", -6.0)


# --- aim line ---------------------------------------------------------------

func _show_aim() -> void:
	if _aim_line == null:
		_aim_line = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.06, 0.06, 1.0)
		_aim_line.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.15, 0.1, 0.75)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_aim_line.material_override = material
		_aim_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aim_line.top_level = true
		enemy.add_child(_aim_line)
	_aim_line.visible = true


func _update_aim_line(player: Player) -> void:
	if _aim_line == null:
		return
	var dir := _aim_dir
	if not _aim_locked:
		if player == null:
			return
		var d := (player.global_position + Vector3(0.0, 1.0, 0.0)) - (enemy.global_position + MUZZLE)
		dir = d.normalized()
	var origin := enemy.global_position + MUZZLE
	var basis := Basis.looking_at(dir, Vector3.UP).scaled(Vector3(1.0, 1.0, AIM_LINE_LENGTH))
	_aim_line.global_transform = Transform3D(basis, origin + dir * (AIM_LINE_LENGTH * 0.5))


func _hide_aim() -> void:
	if _aim_line != null and is_instance_valid(_aim_line):
		_aim_line.visible = false


func _sfx(sound: StringName, volume_db: float) -> void:
	var tree := enemy.get_tree()
	if tree == null:
		return
	var audio := tree.root.get_node_or_null("AudioManager")
	if audio != null and audio.has_method("play"):
		audio.play(sound, volume_db)
