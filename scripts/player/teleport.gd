class_name TeleportAbility
extends Node
## Teleport to a random safe spot in the arena. 2 charges; charges come back one at a time, each
## RECHARGE_SECONDS (10 min) of real wall-clock time after the previous one. State is persisted, so
## closing the game or reloading the scene never refunds a charge.
##
## Recharge model (single sequential timer): using a charge when none is recharging starts the timer
## (ready_at = now + R). Using another while it runs just spends the charge. When the timer fires,
## one charge returns and, if still below the maximum, the timer restarts for another R measured from
## the moment the previous charge returned. Both used at t=0: charge 1 back at R, charge 2 back at 2R.

signal charges_changed(charges: int, maximum: int)
signal teleported(from_position: Vector3, to_position: Vector3)
signal denied(seconds_left: float)

const MAX_CHARGES: int = 2
const DEFAULT_RECHARGE_SECONDS: float = 600.0
const INVULNERABLE_SECONDS: float = 0.5

# Arena rules (kept in sync with WaveManager).
const ARENA_LIMIT: float = 26.0
const OBSTACLES: Array[Vector2] = [Vector2(8.0, -6.0), Vector2(-8.0, -4.0)]
const OBSTACLE_CLEARANCE: float = 4.5
const MIN_MOVE: float = 8.0
const MIN_ENEMY_DISTANCE: float = 6.0
const STRICT_TRIES: int = 20
const MAX_TRIES: int = 40
const SAFE_SPOTS: Array[Vector2] = [Vector2(22, 22), Vector2(-22, 22), Vector2(22, -22), Vector2(-22, -22)]
const PLAYER_MASK: int = 1 | 4  # world + enemies
## Outside Outpost 17 the landing spot is searched around the player instead of in the arena rectangle.
const LOCAL_MIN: float = 8.0
const LOCAL_MAX: float = 18.0
const GROUND_MAX_STEP: float = 3.0
const GROUND_PROBE: float = 6.0

# While the south gate is locked, a player on the beach may only teleport along the beach, so
# teleporting cannot skip the power puzzle. (Matches the beach colliders in WorldFlow.)
const BEACH_EDGE_Z: float = 31.0
const BEACH_RECT: Rect2 = Rect2(-38.0, 36.0, 76.0, 38.0)
const BEACH_FALLBACK: Vector3 = Vector3(0.0, 0.1, 62.0)

var charges: int = MAX_CHARGES
var ready_at: float = 0.0  # unix time the next charge returns; 0 when full
var recharge_seconds: float = DEFAULT_RECHARGE_SECONDS
var save_path: String = ""
var clock: Callable = Callable()  # returns unix seconds; tests inject a fake clock
var rng := RandomNumberGenerator.new()

var _layer: CanvasLayer
var _label: Label
var _toast: Label
var _toast_time: float = 0.0
var _tick: float = 0.0
var _fx: TeleportFx
var _shake_tween: Tween


static func default_save_path() -> String:
	if DisplayServer.get_name() == "headless":
		return "user://teleport_test_%d.cfg" % OS.get_process_id()
	return "user://teleport.cfg"


func _ready() -> void:
	rng.randomize()
	if save_path == "":
		save_path = default_save_path()
	load_state()
	_apply_progression_recharge()
	if get_parent() is Player:
		_build_ui()
		_fx = TeleportFx.new()
		add_child(_fx)
		var fx_manager := get_node_or_null("/root/Fx")
		if fx_manager and "quality_scale" in fx_manager:
			_fx.quality_scale = fx_manager.quality_scale
	_refresh_ui()


func _physics_process(_delta: float) -> void:
	if get_parent() is Player and Input.is_action_just_pressed("teleport"):
		try_teleport()


func _process(delta: float) -> void:
	_tick += delta
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0 and _toast:
			_toast.visible = false
	if _tick >= 1.0:  # once a second, not per frame
		_tick = 0.0
		var before := charges
		refresh()
		if before != charges:
			charges_changed.emit(charges, MAX_CHARGES)
		_refresh_ui()


# --- charges and recharge ---------------------------------------------------

func now() -> float:
	return clock.call() if clock.is_valid() else Time.get_unix_time_from_system()


func seconds_until_next() -> float:
	if charges >= MAX_CHARGES:
		return 0.0
	return maxf(ready_at - now(), 0.0)


## Hand back every charge whose time has come (catches up after any amount of downtime).
func refresh() -> void:
	var current := now()
	if charges >= MAX_CHARGES:
		charges = MAX_CHARGES
		ready_at = 0.0
		return
	if ready_at > current + recharge_seconds + 1.0:
		ready_at = current + recharge_seconds  # clock set back or corrupt value: never wait longer than R
	var changed := false
	while charges < MAX_CHARGES and current >= ready_at:
		charges += 1
		changed = true
		ready_at += recharge_seconds
	if charges >= MAX_CHARGES:
		ready_at = 0.0
	if changed:
		save_state()


## Spend one charge (logic only). Returns false if none is available.
func use_charge() -> bool:
	refresh()
	if charges <= 0:
		return false
	if charges >= MAX_CHARGES:
		ready_at = now() + recharge_seconds  # nothing was recharging: start the timer
	charges -= 1
	save_state()
	charges_changed.emit(charges, MAX_CHARGES)
	return true


# --- persistence ------------------------------------------------------------

func save_state() -> void:
	var config := ConfigFile.new()
	config.set_value("teleport", "charges", charges)
	config.set_value("teleport", "ready_at", ready_at)
	config.save(save_path)


func load_state() -> void:
	charges = MAX_CHARGES
	ready_at = 0.0
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return  # no file yet (fresh install) or unreadable: start full
	# Each value is validated on its own: wrong types / NaN / inf are ignored, numbers are clamped.
	var stored_charges := _finite_number(config.get_value("teleport", "charges", MAX_CHARGES), MAX_CHARGES)
	var stored_ready := _finite_number(config.get_value("teleport", "ready_at", 0.0), 0.0)
	charges = clampi(int(stored_charges), 0, MAX_CHARGES)
	if charges >= MAX_CHARGES:
		ready_at = 0.0
		return
	if stored_ready <= 0.0:
		# Below the maximum but the timer is lost or garbage: a damaged file costs a full wait.
		ready_at = now() + recharge_seconds
		save_state()
		return
	ready_at = stored_ready
	refresh()  # also pulls a far-future (corrupt or clock-rewound) timer back to now + R


static func _finite_number(value: Variant, fallback: float) -> float:
	if (value is int or value is float) and is_finite(float(value)):
		return float(value)
	return fallback


# --- teleporting ------------------------------------------------------------

func can_teleport() -> bool:
	var player := get_parent() as Player
	if player == null or player.is_dead():
		return false
	refresh()
	return charges > 0


func try_teleport() -> bool:
	var player := get_parent() as Player
	if player == null or player.is_dead():
		return false
	refresh()
	if charges <= 0:
		var left := seconds_until_next()
		denied.emit(left)
		_show_denied(left)
		return false
	var origin := player.global_position
	var destination := pick_destination(player)
	if destination == Vector3.INF:
		_show_message("No safe landing here")  # nothing valid nearby: refuse, keep the charge
		return false
	if not use_charge():
		return false
	if _fx:
		_fx.play_at(0, origin)
	player.velocity = Vector3.ZERO
	player.global_position = destination
	if player.has_method("grant_invulnerability"):
		player.grant_invulnerability(INVULNERABLE_SECONDS)
	if _fx:
		_fx.play_at(1, destination)
		_fx.flash()
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play"):
		audio.play(&"teleport", -2.0, 0.03)
	teleported.emit(origin, destination)
	_refresh_ui()
	return true


## A random spot that is inside the arena, clear of obstacles and colliders, far from where the
## player stands and from live enemies. Rules relax after STRICT_TRIES; the best candidate is kept.
func pick_destination(player: Player) -> Vector3:
	var origin := player.global_position
	var enemy_positions: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy and not (enemy.has_method("is_dead") and enemy.is_dead()):
			enemy_positions.append(enemy.global_position)

	if _in_other_region():
		return _pick_local_destination(player, enemy_positions)

	var on_locked_beach := _on_locked_beach(origin)
	var best := Vector3.INF
	var best_score := -INF
	for attempt in MAX_TRIES:
		var candidate := Vector3(
				rng.randf_range(-ARENA_LIMIT, ARENA_LIMIT), 0.1, rng.randf_range(-ARENA_LIMIT, ARENA_LIMIT))
		if on_locked_beach:
			candidate = Vector3(
					rng.randf_range(BEACH_RECT.position.x, BEACH_RECT.end.x), 0.1,
					rng.randf_range(BEACH_RECT.position.y, BEACH_RECT.end.y))
		if not _clear_of_obstacles(candidate) or not _is_free(player, candidate):
			continue
		var score := _score(candidate, origin, enemy_positions)
		if score > best_score:
			best_score = score
			best = candidate
		if attempt < STRICT_TRIES and _meets_rules(candidate, origin, enemy_positions):
			return candidate
	if best != Vector3.INF:
		return best
	if on_locked_beach:
		return BEACH_FALLBACK
	for spot in SAFE_SPOTS:  # nothing found by chance: use the corner farthest from the player
		var corner := Vector3(spot.x, 0.1, spot.y)
		var score := _score(corner, origin, enemy_positions)
		if score > best_score:
			best_score = score
			best = corner
	return best


## The arena rectangle and its obstacles describe Outpost 17 only. Anywhere else the landing spot
## comes from the player's own surroundings (see _pick_local_destination).
func _in_other_region() -> bool:
	var regions := get_node_or_null("/root/RegionManager")
	if regions == null:
		return false
	return not String(regions.get("current_region_id")) in ["", "outpost_17"]


## A spot 8 to 18 m from the player that has solid ground within a step of their height, room for
## the capsule and no enemy close by. Returns Vector3.INF when there is none: the teleport is then
## refused and no charge is spent, instead of dropping the player into the sea or the void.
func _pick_local_destination(player: Player, enemies: Array[Vector3]) -> Vector3:
	var origin := player.global_position
	var best := Vector3.INF
	var best_score := -INF
	for attempt in MAX_TRIES:
		var angle := rng.randf() * TAU
		var distance := rng.randf_range(LOCAL_MIN, LOCAL_MAX)
		var flat := Vector2(origin.x, origin.z) + Vector2(cos(angle), sin(angle)) * distance
		var ground := _ground_height(player, flat, origin.y)
		if is_nan(ground) or absf(ground - origin.y) > GROUND_MAX_STEP:
			continue
		var candidate := Vector3(flat.x, ground + 0.1, flat.y)
		if not _is_free(player, candidate):
			continue
		var score := _score(candidate, origin, enemies)
		if score > best_score:
			best_score = score
			best = candidate
		if _meets_rules(candidate, origin, enemies):
			return candidate
	return best if best_score >= 0.5 else Vector3.INF


## Height of the solid ground under (x, z) near `reference_y`, or NAN if there is none.
func _ground_height(player: Player, flat: Vector2, reference_y: float) -> float:
	var world := player.get_world_3d()
	if world == null:
		return NAN
	var query := PhysicsRayQueryParameters3D.create(
			Vector3(flat.x, reference_y + GROUND_PROBE, flat.y), Vector3(flat.x, reference_y - GROUND_PROBE, flat.y), 1)
	var hit := world.direct_space_state.intersect_ray(query)
	return NAN if hit.is_empty() else float((hit["position"] as Vector3).y)


func _on_locked_beach(origin: Vector3) -> bool:
	if origin.z <= BEACH_EDGE_Z:
		return false
	var state := get_node_or_null("/root/WorldState")
	return state == null or not state.has_flag(&"power_on")


func _meets_rules(candidate: Vector3, origin: Vector3, enemies: Array[Vector3]) -> bool:
	if _flat_distance(candidate, origin) < MIN_MOVE:
		return false
	for enemy_position in enemies:
		if _flat_distance(candidate, enemy_position) < MIN_ENEMY_DISTANCE:
			return false
	return true


## Higher is better: the smaller of "how far from the player (capped at the minimum)" and
## "how far from the nearest enemy (capped)", so the farthest-from-trouble candidate wins.
func _score(candidate: Vector3, origin: Vector3, enemies: Array[Vector3]) -> float:
	var move_score := _flat_distance(candidate, origin) / MIN_MOVE
	var enemy_score := INF
	for enemy_position in enemies:
		enemy_score = minf(enemy_score, _flat_distance(candidate, enemy_position) / MIN_ENEMY_DISTANCE)
	return minf(move_score, enemy_score)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clear_of_obstacles(candidate: Vector3) -> bool:
	for obstacle in OBSTACLES:
		if Vector2(candidate.x, candidate.z).distance_to(obstacle) < OBSTACLE_CLEARANCE:
			return false
	return true


## Physics check with the player's capsule so we never land inside a collider (decor has none, but
## future props or a sleeping corpse might).
func _is_free(player: Player, candidate: Vector3) -> bool:
	var world := player.get_world_3d()
	if world == null:
		return true
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, candidate + Vector3(0.0, 0.95, 0.0))
	query.collision_mask = PLAYER_MASK
	query.exclude = [player.get_rid()]
	return world.direct_space_state.intersect_shape(query, 1).is_empty()


# --- UI ----------------------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 51
	add_child(_layer)
	_label = _make_label(18, 4)
	_toast = _make_label(18, 4)
	_toast.visible = false
	_toast.add_theme_color_override("font_color", Color(1.0, 0.6, 0.45))


func _make_label(font_size: int, outline: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", outline)
	_layer.add_child(label)
	return label


func _label_x() -> float:
	# The pause "||" button occupies x 16..72 at y 140 when touch controls are active.
	return 84.0 if TouchControls.touch_active else 16.0


func _refresh_ui() -> void:
	if _label == null:
		return
	var text := "Teleport %d/%d [T]" % [charges, MAX_CHARGES]
	if charges < MAX_CHARGES:
		text += "  next in %s" % format_time(seconds_until_next())
	_label.text = text
	_label.modulate.a = 0.5 if charges == 0 else 1.0
	_label.position = Vector2(_label_x(), 140.0)
	_toast.position = Vector2(_label_x(), 166.0)


func _show_message(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_time = 2.0


func _show_denied(seconds_left: float) -> void:
	if _toast == null:
		return
	_toast.text = "Teleport recharging %s" % format_time(seconds_left)
	_toast.visible = true
	_toast_time = 2.0
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var base_x := _label_x()
	_shake_tween = create_tween()
	for offset in [7.0, -7.0, 4.0, -4.0, 0.0]:
		_shake_tween.tween_property(_label, "position:x", base_x + offset, 0.04)


static func format_time(seconds: float) -> String:
	var total := ceili(maxf(seconds, 0.0))
	return "%02d:%02d" % [total / 60, total % 60]


# --- progression hook ---------------------------------------------------------

var _base_recharge: float = -1.0


## Technique and skills shorten the recharge by a multiplier (1.0 at level 1). Only the player's own
## ability listens, so standalone instances in tests keep their configured recharge time.
func _apply_progression_recharge() -> void:
	var progression := get_node_or_null("/root/Progression")
	if progression == null or not get_parent() is Player:
		return
	if _base_recharge < 0.0:
		_base_recharge = recharge_seconds
		progression.points_changed.connect(_apply_progression_recharge)
	recharge_seconds = _base_recharge * progression.teleport_recharge_multiplier()
