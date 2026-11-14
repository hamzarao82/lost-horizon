class_name AIScheduler
extends RefCounted
## Staggered think intervals and small tactical helpers for Enemy. Everything here is opt-in per enemy
## (Enemy.scheduled, flank_slots, spacing, retreat_health_fraction, reinforcement_cap): defaults keep the
## original every-frame behaviour. See docs/AI_SCHEDULER.md.

const NEAR_DISTANCE: float = 6.0
const MID_DISTANCE: float = 12.0
const INTERVAL_NEAR: float = 0.1
const INTERVAL_MID: float = 0.2
const INTERVAL_FAR: float = 0.3
const MAX_THINKS_PER_FRAME: int = 4
const FLANK_STEP: float = 0.6          # radians between neighbouring flank slots
const FLANK_RANGE: float = 18.0        # enemies farther than this from the player take no slot
const SPACING_RADIUS: float = 1.6
const RETREAT_SECONDS: float = 2.5

static var _budget_frame: int = -1
static var _budget_used: int = 0
## Thinks granted since the last reset_budget (a measurement hook for tests and the perf overlay).
static var thinks_granted: int = 0


## Think interval for an enemy `distance` metres from its target; a token holder always thinks every frame.
static func interval_for(distance: float, has_token: bool) -> float:
	if has_token:
		return 0.0
	if distance <= NEAR_DISTANCE:
		return INTERVAL_NEAR
	if distance <= MID_DISTANCE:
		return INTERVAL_MID
	return INTERVAL_FAR


## Takes one think from this frame's budget. False once MAX_THINKS_PER_FRAME were handed out, so a
## crowd spreads its thinking over several frames instead of all enemies thinking together.
static func take_budget() -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _budget_frame:
		_budget_frame = frame
		_budget_used = 0
	if _budget_used >= MAX_THINKS_PER_FRAME:
		return false
	_budget_used += 1
	thinks_granted += 1
	return true


static func reset_budget() -> void:
	_budget_frame = -1
	_budget_used = 0
	thinks_granted = 0


## Angle offset (radians) for slot `index` out of `count`: slots fan out symmetrically around 0.
static func flank_angle(index: int, count: int) -> float:
	if count <= 1:
		return 0.0
	return (float(index) - float(count - 1) * 0.5) * FLANK_STEP


## This enemy's slot among every living flanking enemy near the same target, ordered by instance id so
## the assignment is stable from frame to frame.
static func flank_slot(enemy: Enemy, target_position: Vector3) -> Vector2i:
	var ids: Array[int] = []
	for node in enemy.get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other.is_dead() or not other.flank_slots:
			continue
		if other.global_position.distance_to(target_position) <= FLANK_RANGE:
			ids.append(other.get_instance_id())
	ids.sort()
	var index := ids.find(enemy.get_instance_id())
	return Vector2i(maxi(index, 0), maxi(ids.size(), 1))


## Horizontal push away from crowding neighbours (length 0 when nobody is within SPACING_RADIUS).
static func separation(enemy: Enemy) -> Vector3:
	var push := Vector3.ZERO
	for node in enemy.get_tree().get_nodes_in_group("enemies"):
		var other := node as Enemy
		if other == null or other == enemy or other.is_dead():
			continue
		var away := enemy.global_position - other.global_position
		away.y = 0.0
		var d := away.length()
		if d < SPACING_RADIUS:
			push += (away / d if d > 0.01 else Vector3.RIGHT) * (1.0 - d / SPACING_RADIUS)
	return push


## Bosses ignore every tactical mode: retreating or calling help would break their authored patterns.
static func is_boss(enemy: Enemy) -> bool:
	return enemy is Warden or enemy is Director or enemy is StageBossEnemy
