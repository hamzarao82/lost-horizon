class_name ExperimentalSubject
extends Enemy
## Research Complex melee enemy (Milestone 8). Never patrols: it wakes when the player comes close,
## closes in with erratic sidesteps and commits to a lunge. The lunge is telegraphed (red tell for the
## whole startup, at least 0.4 s) and leaves a recovery of at least 0.4 s, so it is dodgeable and punishable.
## Everything else (health, hits, death, loot, stagger) is the shared Enemy code.

const LUNGE_RANGE: float = 4.2
const STRAFE_MIN: float = 0.5
const STRAFE_MAX: float = 1.3
const CLOSE_SPEED_FACTOR: float = 1.15

var _strafe_dir: float = 1.0
var _strafe_left: float = 0.0
## What actually happened, for tests (not what the data says).
var stats: Dictionary = {"lunges": 0}


func _ready() -> void:
	patrol_route = null  # subjects never patrol
	super()
	_strafe_dir = _strafe_sign


func is_subject() -> bool:
	return true


func _state_chase(delta: float) -> void:
	if _dodge_time > 0.0:
		_dodge_time -= delta
		return
	var player := _target()
	if player == null or _flat_to(player).length() > lose_range:
		_release_token()
		state = State.IDLE
		return
	var to := _flat_to(player)
	var dist := to.length()
	var dir := to.normalized()
	_face(dir, delta)
	if _cooldown <= 0.0 and dist <= LUNGE_RANGE:
		stats["lunges"] += 1
		_start_attack()
		return
	_strafe_left -= delta
	if _strafe_left <= 0.0:
		_strafe_left = randf_range(STRAFE_MIN, STRAFE_MAX)
		_strafe_dir = -_strafe_dir if randf() < 0.7 else _strafe_dir
	var side := Vector3(-dir.z, 0.0, dir.x) * _strafe_dir
	if _cooldown <= 0.0:
		# Ready to attack: close in (with a wobble) until inside lunge range, then the check above fires.
		var move := dir + side * 0.55
		_move_horizontal(move.normalized(), move_speed * CLOSE_SPEED_FACTOR)
	elif dist > LUNGE_RANGE + 1.5:
		_move_horizontal((dir + side * 0.55).normalized(), move_speed * CLOSE_SPEED_FACTOR)
	else:
		_move_horizontal(side, move_speed * 0.8)  # circle while the cooldown runs out
