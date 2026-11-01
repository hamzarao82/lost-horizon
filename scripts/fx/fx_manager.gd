extends Node
## Autoload "Fx": pooled combat effects (hit sparks, damage numbers, dust, death bursts, ground
## rings, pickup shimmer). Everything is built once in _ready and reused: a hit only moves, recolors
## and restarts an existing node. CPUParticles3D only (Compatibility renderer, web, Android).
## Wires itself to gameplay through get_tree().node_added, so gameplay scenes need no effect code.

const MAX_NUMBERS: int = 16
const MAX_SPARKS: int = 8
const MAX_DUST: int = 4
const MAX_BURSTS: int = 3
const MAX_SHIMMERS: int = 6
const MAX_RINGS: int = 6

const SPARK_AMOUNT: int = 12
const DUST_AMOUNT: int = 8
const BURST_AMOUNT: int = 24
const SHIMMER_AMOUNT: int = 10

const HEAVY_DAMAGE: float = 20.0
const NUMBER_LIFETIME: float = 0.7
const RING_LIFETIME: float = 0.35
const RING_TEXTURE_SIZE: int = 64
const QUALITY_SCALES: Array[float] = [0.4, 0.7, 1.0]  # Settings.Quality LOW / MEDIUM / HIGH

const SPARK_LIGHT: Color = Color(1.0, 0.95, 0.7)
const SPARK_HEAVY: Color = Color(1.0, 0.55, 0.15)
const DUST_COLOR: Color = Color(0.78, 0.72, 0.62, 0.8)
const DODGE_DUST_COLOR: Color = Color(0.5, 0.75, 1.0, 0.8)
const WINDUP_RING_COLOR: Color = Color(1.0, 0.2, 0.1)
const NUMBER_LIGHT: Color = Color(1.0, 1.0, 1.0)
const NUMBER_HEAVY: Color = Color(1.0, 0.82, 0.2)
const NUMBER_KILL: Color = Color(1.0, 0.55, 0.15)
const NUMBER_HURT: Color = Color(1.0, 0.25, 0.25)
const NUMBER_HEAL: Color = Color(0.35, 1.0, 0.45)

## Scales particle counts: 0 disables particles and rings, numbers always stay.
var quality_scale: float = 1.0: set = set_quality_scale

var _clock: float = 0.0
var _busy_until: float = 0.0

var _particle_mesh: QuadMesh
var _particle_material: StandardMaterial3D
var _fade_ramp: Gradient
var _ring_texture: ImageTexture

var _sparks: Pool = Pool.new()
var _dust: Pool = Pool.new()
var _bursts: Pool = Pool.new()
var _shimmers: Pool = Pool.new()
var _rings: Pool = Pool.new()
var _numbers: Pool = Pool.new()
var _number_origin: PackedVector3Array = PackedVector3Array()
var _number_scale: PackedFloat32Array = PackedFloat32Array()
var _ring_radius: PackedFloat32Array = PackedFloat32Array()
var _ring_color: PackedColorArray = PackedColorArray()

var _player: Player
var _last_hp: float = 100.0
var _was_dodging: bool = false
var _was_on_floor: bool = true
var _fall_speed: float = 0.0


## Fixed-size reuse pool. take() returns an idle slot, or steals the one that started earliest.
class Pool:
	var nodes: Array[Node3D] = []
	var start: PackedFloat64Array = PackedFloat64Array()
	var life: PackedFloat32Array = PackedFloat32Array()
	var cursor: int = 0

	func add(node: Node3D) -> void:
		nodes.append(node)
		start.append(-1000.0)
		life.append(0.0)

	func size() -> int:
		return nodes.size()

	func take(now: float) -> int:
		var count := nodes.size()
		for step in count:
			var i := (cursor + step) % count
			if now >= start[i] + life[i]:
				cursor = (i + 1) % count
				return i
		var stolen := cursor
		cursor = (cursor + 1) % count
		return stolen

	func is_active(i: int, now: float) -> bool:
		return now < start[i] + life[i]

	func active_count(now: float) -> int:
		var total := 0
		for i in nodes.size():
			if now < start[i] + life[i]:
				total += 1
		return total


func _ready() -> void:
	_build_shared_resources()
	_build_pools()
	_refresh_quality()
	var settings := get_node_or_null("/root/Settings")
	if settings and settings.has_signal("changed"):
		settings.connect("changed", _refresh_quality)
	get_tree().node_added.connect(_on_node_added)


# --- public API ------------------------------------------------------------

func spark(position: Vector3, damage: float) -> void:
	if quality_scale <= 0.0:
		return
	var heavy := damage >= HEAVY_DAMAGE
	var i := _sparks.take(_clock)
	var p := _sparks.nodes[i] as CPUParticles3D
	p.initial_velocity_min = 3.0 if heavy else 2.0
	p.initial_velocity_max = 8.0 if heavy else 5.0
	p.color = SPARK_HEAVY if heavy else SPARK_LIGHT
	_fire(_sparks, i, position, p.lifetime)


func dust(position: Vector3, color: Color = DUST_COLOR) -> void:
	if quality_scale <= 0.0:
		return
	var i := _dust.take(_clock)
	var p := _dust.nodes[i] as CPUParticles3D
	p.color = color
	_fire(_dust, i, position, p.lifetime)


func death_burst(position: Vector3, color: Color) -> void:
	if quality_scale <= 0.0:
		return
	var i := _bursts.take(_clock)
	var p := _bursts.nodes[i] as CPUParticles3D
	p.color = color
	_fire(_bursts, i, position, p.lifetime)
	ring(Vector3(position.x, 0.0, position.z), 2.2, color, 0.5)


func shimmer(position: Vector3, color: Color) -> void:
	if quality_scale <= 0.0:
		return
	var i := _shimmers.take(_clock)
	var p := _shimmers.nodes[i] as CPUParticles3D
	p.color = color
	_fire(_shimmers, i, position, p.lifetime)


## Flat expanding ring on the ground; radius is in meters.
func ring(position: Vector3, radius: float, color: Color, life: float = RING_LIFETIME) -> void:
	if quality_scale <= 0.0:
		return
	var i := _rings.take(_clock)
	var sprite := _rings.nodes[i] as Sprite3D
	sprite.global_position = Vector3(position.x, 0.06, position.z)
	_ring_radius[i] = radius
	_ring_color[i] = color
	_rings.start[i] = _clock
	_rings.life[i] = life
	sprite.scale = Vector3.ONE * radius * 0.3
	sprite.modulate = Color(color, 0.9)
	sprite.visible = true
	_busy_until = maxf(_busy_until, _clock + life)


## Floating number at a world position. scale_factor > 1 makes it bigger.
func number(position: Vector3, text: String, color: Color, scale_factor: float = 1.0) -> void:
	var i := _numbers.take(_clock)
	var label := _numbers.nodes[i] as Label3D
	var spread := Vector3(randf_range(-0.55, 0.55), 0.0, randf_range(-0.3, 0.3))
	_number_origin[i] = position + spread
	_number_scale[i] = scale_factor
	label.text = text
	label.modulate = color
	label.global_position = _number_origin[i]
	label.scale = Vector3.ONE * scale_factor * 1.4
	label.visible = true
	_numbers.start[i] = _clock
	_numbers.life[i] = NUMBER_LIFETIME
	_busy_until = maxf(_busy_until, _clock + NUMBER_LIFETIME)


func damage_number(position: Vector3, amount: float, was_kill: bool = false) -> void:
	var heavy := amount >= HEAVY_DAMAGE
	var color := NUMBER_KILL if was_kill else (NUMBER_HEAVY if heavy else NUMBER_LIGHT)
	var size := 1.5 if was_kill else (1.25 if heavy else 1.0)
	number(position, str(roundi(amount)), color, size)


func active_count() -> int:
	var total := 0
	for pool in [_sparks, _dust, _bursts, _shimmers, _rings, _numbers]:
		total += (pool as Pool).active_count(_clock)
	return total


func pool_sizes() -> Dictionary:
	return {
		"sparks": _sparks.size(), "dust": _dust.size(), "bursts": _bursts.size(),
		"shimmers": _shimmers.size(), "rings": _rings.size(), "numbers": _numbers.size(),
	}


func set_quality_scale(value: float) -> void:
	quality_scale = clampf(value, 0.0, 1.0)
	if _sparks.size() == 0:
		return  # pools not built yet; _ready applies the scale
	_apply_particle_amounts()


# --- construction ----------------------------------------------------------

func _build_shared_resources() -> void:
	_particle_material = StandardMaterial3D.new()
	_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_particle_material.vertex_color_use_as_albedo = true
	_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_particle_material.billboard_keep_scale = true
	_particle_material.disable_fog = true
	_particle_mesh = QuadMesh.new()
	_particle_mesh.size = Vector2(0.12, 0.12)
	_particle_mesh.material = _particle_material
	_fade_ramp = Gradient.new()
	_fade_ramp.set_color(0, Color(1, 1, 1, 1))
	_fade_ramp.set_color(1, Color(1, 1, 1, 0))

	var image := Image.create(RING_TEXTURE_SIZE, RING_TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var half := RING_TEXTURE_SIZE * 0.5
	for y in RING_TEXTURE_SIZE:
		for x in RING_TEXTURE_SIZE:
			var d := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half  # 0 center, 1 edge
			var band := 1.0 - clampf(absf(d - 0.82) / 0.14, 0.0, 1.0)  # soft ring near the edge
			image.set_pixel(x, y, Color(1, 1, 1, band * band))
	_ring_texture = ImageTexture.create_from_image(image)


func _build_pools() -> void:
	for i in MAX_SPARKS:
		_sparks.add(_make_particles(SPARK_AMOUNT, 0.35, 2.0, 5.0, Vector3(0, -12, 0), 0.6, 1.2, 180.0))
	for i in MAX_DUST:
		_dust.add(_make_particles(DUST_AMOUNT, 0.5, 0.6, 1.8, Vector3(0, 0.6, 0), 1.5, 3.0, 90.0))
	for i in MAX_BURSTS:
		_bursts.add(_make_particles(BURST_AMOUNT, 0.6, 2.5, 6.0, Vector3(0, -6, 0), 1.0, 2.2, 90.0))
	for i in MAX_SHIMMERS:
		_shimmers.add(_make_particles(SHIMMER_AMOUNT, 0.6, 0.8, 2.2, Vector3(0, 1.2, 0), 0.6, 1.2, 60.0))

	for i in MAX_RINGS:
		var sprite := _make_ring_sprite()
		add_child(sprite)
		_rings.add(sprite)
		_ring_radius.append(1.0)
		_ring_color.append(Color.WHITE)

	for i in MAX_NUMBERS:
		var label := _make_number_label()
		add_child(label)
		_numbers.add(label)
		_number_origin.append(Vector3.ZERO)
		_number_scale.append(1.0)


func _make_ring_sprite() -> Sprite3D:
	var sprite := Sprite3D.new()
	sprite.texture = _ring_texture
	sprite.axis = Vector3.AXIS_Y
	sprite.pixel_size = 2.0 / RING_TEXTURE_SIZE  # scale 1 == radius 1 m
	sprite.shaded = false
	sprite.transparent = true
	sprite.double_sided = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.visible = false
	return sprite


func _make_number_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.pixel_size = 0.008
	label.font_size = 48
	label.outline_size = 12
	label.outline_modulate = Color.BLACK
	label.render_priority = 10
	label.outline_render_priority = 9
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.visible = false
	return label


## Fresh, unparented copies of every effect type (same meshes, materials and flags as the pools),
## for Warmup to draw once so their shaders and glyphs are ready before the first hit.
func make_warmup_nodes() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	var burst := _make_particles(SPARK_AMOUNT, 0.2, 2.0, 5.0, Vector3(0, -12, 0), 0.6, 1.2, 180.0)
	remove_child(burst)
	burst.emitting = true
	nodes.append(burst)
	var label := _make_number_label()
	label.text = "0123456789+-"  # rasterizes every glyph the damage numbers can use
	label.visible = true
	nodes.append(label)
	var ring := _make_ring_sprite()
	ring.visible = true
	nodes.append(ring)
	return nodes


func _make_particles(amount: int, lifetime: float, speed_min: float, speed_max: float,
		gravity: Vector3, size_min: float, size_max: float, spread: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false  # world-space: moving the emitter for the next burst leaves old sparks alone
	p.mesh = _particle_mesh
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = gravity
	p.scale_amount_min = size_min
	p.scale_amount_max = size_max
	p.color_ramp = _fade_ramp
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _fire(pool: Pool, i: int, position: Vector3, life: float) -> void:
	var p := pool.nodes[i] as CPUParticles3D
	p.global_position = position
	p.restart()
	p.emitting = true
	pool.start[i] = _clock
	pool.life[i] = life
	_busy_until = maxf(_busy_until, _clock + life)


# --- quality ---------------------------------------------------------------

func _refresh_quality() -> void:
	if not is_inside_tree():
		return  # Settings can emit changed while the tree is shutting down
	var settings := get_node_or_null("/root/Settings")
	if settings == null:
		return
	var level: Variant = settings.get("quality")
	if level is int:
		quality_scale = QUALITY_SCALES[clampi(level, 0, QUALITY_SCALES.size() - 1)]


func _apply_particle_amounts() -> void:
	# Changing amount reallocates the buffer, so this only runs when the quality setting changes.
	_set_amounts(_sparks, SPARK_AMOUNT)
	_set_amounts(_dust, DUST_AMOUNT)
	_set_amounts(_bursts, BURST_AMOUNT)
	_set_amounts(_shimmers, SHIMMER_AMOUNT)


func _set_amounts(pool: Pool, base: int) -> void:
	var wanted := maxi(2, roundi(base * quality_scale))
	for node in pool.nodes:
		var p := node as CPUParticles3D
		if p.amount != wanted:
			p.amount = wanted


# --- gameplay wiring -------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node is Enemy:
		var enemy := node as Enemy
		enemy.damaged.connect(_on_enemy_damaged)
		enemy.defeated.connect(_on_enemy_defeated.bind(enemy))
		enemy.swing_started.connect(_on_enemy_swing.bind(enemy))
		enemy.was_hit.connect(_on_enemy_was_hit.bind(enemy))
	elif node is Player:
		_hook_player(node as Player)
	elif node is Pickup:
		_hook_pickup(node as Pickup)


func _on_enemy_damaged(amount: float, position: Vector3, was_kill: bool) -> void:
	spark(position, amount)
	damage_number(position + Vector3(0, 0.6, 0), amount, was_kill)


func _on_enemy_defeated(enemy: Enemy) -> void:
	if is_instance_valid(enemy):
		death_burst(enemy.global_position + Vector3(0, 0.9, 0), enemy.body_color.lightened(0.2))


func _on_enemy_swing(enemy: Enemy) -> void:
	if is_instance_valid(enemy):
		ring(enemy.global_position, enemy.attack_range, WINDUP_RING_COLOR, 0.35)


func _on_enemy_was_hit(dodged: bool, enemy: Enemy) -> void:
	if dodged and is_instance_valid(enemy):
		dust(enemy.global_position + Vector3(0, 0.1, 0), DODGE_DUST_COLOR)


func _hook_player(player: Player) -> void:
	_player = player
	_was_dodging = false
	_was_on_floor = true
	_fall_speed = 0.0
	var health := player.get_node_or_null("HealthComponent") as HealthComponent
	if health == null:
		return
	_last_hp = health.max_health
	health.damaged.connect(_on_player_damaged)
	health.changed.connect(_on_player_health_changed)


func _on_player_damaged(amount: float) -> void:
	if is_instance_valid(_player):
		number(_player.global_position + Vector3(0, 2.2, 0), str(roundi(amount)), NUMBER_HURT, 1.2)


func _on_player_health_changed(current: float, _maximum: float) -> void:
	if current > _last_hp + 0.01 and is_instance_valid(_player):
		number(_player.global_position + Vector3(0, 2.2, 0), "+%d" % roundi(current - _last_hp), NUMBER_HEAL, 1.2)
	_last_hp = current


func _hook_pickup(pickup: Pickup) -> void:
	var color := Color.WHITE
	if pickup.item:
		color = pickup.item.color()
	shimmer(pickup.global_position + Vector3(0, 0.5, 0), color)
	pickup.tree_exiting.connect(_on_pickup_exiting.bind(pickup, color))


func _on_pickup_exiting(pickup: Pickup, color: Color) -> void:
	# Only flash when the player walked into it (not on expiry or scene teardown).
	if is_instance_valid(_player) and is_instance_valid(pickup) and pickup.is_inside_tree() \
			and _player.global_position.distance_to(pickup.global_position) < 2.5:
		shimmer(pickup.global_position + Vector3(0, 0.6, 0), color.lightened(0.4))


# --- per-frame -------------------------------------------------------------

func _process(delta: float) -> void:
	_clock += delta
	_poll_player()
	if _clock > _busy_until:
		return  # nothing animating
	for i in _numbers.size():
		if _numbers.is_active(i, _clock):
			_animate_number(i)
		else:
			(_numbers.nodes[i] as Label3D).visible = false
	for i in _rings.size():
		if _rings.is_active(i, _clock):
			_animate_ring(i)
		else:
			(_rings.nodes[i] as Sprite3D).visible = false


func _animate_number(i: int) -> void:
	var t := (_clock - _numbers.start[i]) / NUMBER_LIFETIME
	var label := _numbers.nodes[i] as Label3D
	var rise := 1.0 - pow(1.0 - t, 2.0)  # ease out
	label.global_position = _number_origin[i] + Vector3(0, rise * 1.1, 0)
	var pop := lerpf(1.4, 1.0, clampf(t * 8.0, 0.0, 1.0))  # quick pop in
	label.scale = Vector3.ONE * _number_scale[i] * pop
	var color := label.modulate
	color.a = 1.0 - smoothstep(0.55, 1.0, t)
	label.modulate = color


func _animate_ring(i: int) -> void:
	var t := (_clock - _rings.start[i]) / _rings.life[i]
	var sprite := _rings.nodes[i] as Sprite3D
	var grow := 1.0 - pow(1.0 - t, 2.0)
	sprite.scale = Vector3.ONE * _ring_radius[i] * lerpf(0.3, 1.0, grow)
	var color := _ring_color[i]
	color.a = 0.9 * (1.0 - t)
	sprite.modulate = color


func _poll_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dodging := _player.state == Player.State.DODGE
	if dodging and not _was_dodging:
		dust(_player.global_position + Vector3(0, 0.1, 0))
	_was_dodging = dodging
	var on_floor := _player.is_on_floor()
	if not on_floor:
		_fall_speed = _player.velocity.y
	elif not _was_on_floor and _fall_speed < -5.0:
		dust(_player.global_position + Vector3(0, 0.1, 0))
		_fall_speed = 0.0
	_was_on_floor = on_floor
