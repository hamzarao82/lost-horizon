class_name TeleportFx
extends Node
## Two reusable teleport effects (departure and arrival): a cyan particle burst plus an expanding
## ring, and a brief screen flash. Everything is built once; playing one allocates nothing.
## CPU particles and a plain unshaded torus only, so it is cheap for the Compatibility renderer.

const RING_SECONDS: float = 0.35
const BURST_AMOUNT: int = 24
const COLOR: Color = Color(0.45, 0.9, 1.0)
const COLUMN_SECONDS: float = 0.4
const STREAK_SECONDS: float = 0.25
const AFTERIMAGE_SECONDS: float = 0.25
const MAX_AFTERIMAGES: int = 3
const STREAK_MAX_AGE_MSEC: int = 1500   # a departure older than this is not paired with an arrival
const STREAK_MIN_LENGTH: float = 0.5

## Quality thresholds (Fx.quality_scale): column and streak need > 0, 3 afterimages need >= 0.7, 2 need > 0.
var quality_scale: float = 1.0

var _bursts: Array[CPUParticles3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_tweens: Array[Tween] = []
var _columns: Array[MeshInstance3D] = []
var _column_tweens: Array[Tween] = [null, null]
var _afterimages: Array[MeshInstance3D] = []
var _afterimage_tweens: Array[Tween] = []
var _streak: MeshInstance3D
var _streak_tween: Tween
var _departure: Vector3 = Vector3.ZERO
var _departure_msec: int = -1000000
var _flash_rect: ColorRect
var _flash_tween: Tween


func _ready() -> void:
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.88
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 6
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, 0.8)

	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.14, 0.14)
	var spark_material := StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_material.vertex_color_use_as_albedo = true
	spark_material.albedo_color = COLOR

	for i in 2:
		var burst := CPUParticles3D.new()
		burst.top_level = true
		burst.emitting = false
		burst.one_shot = true
		burst.explosiveness = 0.95
		burst.amount = BURST_AMOUNT
		burst.lifetime = 0.55
		burst.local_coords = false
		burst.mesh = spark_mesh
		burst.material_override = spark_material
		burst.direction = Vector3.UP
		burst.spread = 55.0
		burst.initial_velocity_min = 2.5
		burst.initial_velocity_max = 5.5
		burst.gravity = Vector3(0.0, -2.0, 0.0)
		burst.scale_amount_min = 0.7
		burst.scale_amount_max = 1.4
		add_child(burst)
		_bursts.append(burst)

		var ring := MeshInstance3D.new()
		ring.top_level = true
		ring.mesh = ring_mesh
		ring.material_override = ring_material.duplicate()
		ring.visible = false
		add_child(ring)
		_rings.append(ring)
		_ring_tweens.append(null)

	_build_trail_parts()

	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash_rect)


## Light column (one per slot), three translucent afterimages and a streak between the two points.
## All built once; playing one only moves, recolors and tweens them. Plain unshaded alpha meshes.
func _build_trail_parts() -> void:
	var column_mesh := CylinderMesh.new()
	column_mesh.top_radius = 0.45
	column_mesh.bottom_radius = 0.45
	column_mesh.height = 3.2
	column_mesh.radial_segments = 10
	column_mesh.rings = 1
	for i in 2:
		var column := _make_ghost(column_mesh, 0.5)
		(column.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
		_columns.append(column)

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 1.8
	body_mesh.radial_segments = 8
	body_mesh.rings = 2
	for i in MAX_AFTERIMAGES:
		_afterimages.append(_make_ghost(body_mesh, 0.4))
		_afterimage_tweens.append(null)

	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.16, 0.16, 1.0)  # scaled along z to the travelled distance
	_streak = _make_ghost(streak_mesh, 0.6)


func _make_ghost(mesh: Mesh, alpha: float) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(COLOR.r, COLOR.g, COLOR.b, alpha)
	material.disable_fog = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var instance := MeshInstance3D.new()
	instance.top_level = true
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = false
	add_child(instance)
	return instance


func afterimage_count() -> int:
	if quality_scale <= 0.0:
		return 0
	return MAX_AFTERIMAGES if quality_scale >= 0.7 else MAX_AFTERIMAGES - 1


func _fade_out(instance: MeshInstance3D, seconds: float, end_scale: Vector3, from_alpha: float) -> Tween:
	var material := instance.material_override as StandardMaterial3D
	material.albedo_color.a = from_alpha
	instance.visible = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(material, "albedo_color:a", 0.0, seconds)
	tween.tween_property(instance, "scale", end_scale, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func() -> void: instance.visible = false)
	return tween


func _play_column(slot: int, world_position: Vector3) -> void:
	var column := _columns[slot]
	if _column_tweens[slot] != null and _column_tweens[slot].is_valid():
		_column_tweens[slot].kill()
	if quality_scale <= 0.0:
		column.visible = false
		return
	column.global_position = world_position + Vector3(0.0, 1.6, 0.0)
	if slot == 0:
		# Departure: the column stretches up and thins out, like the body being pulled away.
		column.scale = Vector3.ONE
		_column_tweens[slot] = _fade_out(column, COLUMN_SECONDS, Vector3(0.1, 1.5, 0.1), 0.55)
	else:
		# Arrival: a thin column swells to full width as the body lands, then fades.
		column.scale = Vector3(0.2, 1.0, 0.2)
		_column_tweens[slot] = _fade_out(column, COLUMN_SECONDS, Vector3(1.2, 1.0, 1.2), 0.6)


func _play_afterimages(world_position: Vector3) -> void:
	var wanted := afterimage_count()
	for i in MAX_AFTERIMAGES:
		var image := _afterimages[i]
		if _afterimage_tweens[i] != null and _afterimage_tweens[i].is_valid():
			_afterimage_tweens[i].kill()
		if i >= wanted:
			image.visible = false
			continue
		image.global_position = world_position + Vector3((i - 1) * 0.24, 0.9, 0.0)
		image.scale = Vector3.ONE
		_afterimage_tweens[i] = _fade_out(image, AFTERIMAGE_SECONDS, Vector3(0.65, 1.15, 0.65), 0.42 - i * 0.08)


func _play_streak(arrival: Vector3) -> void:
	if quality_scale <= 0.0 or Time.get_ticks_msec() - _departure_msec > STREAK_MAX_AGE_MSEC:
		return
	var from_point := _departure + Vector3(0.0, 0.9, 0.0)
	var to_point := arrival + Vector3(0.0, 0.9, 0.0)
	var length := from_point.distance_to(to_point)
	if length < STREAK_MIN_LENGTH:
		return
	if _streak_tween != null and _streak_tween.is_valid():
		_streak_tween.kill()
	var direction := (to_point - from_point) / length
	_streak.global_position = (from_point + to_point) * 0.5
	if absf(direction.dot(Vector3.UP)) < 0.99:
		_streak.look_at(to_point, Vector3.UP)  # the box's z axis now runs from departure to arrival
	_streak.scale = Vector3(1.0, 1.0, length)
	_streak_tween = _fade_out(_streak, STREAK_SECONDS, Vector3(0.15, 0.15, length), 0.6)


## slot 0 = departure, slot 1 = arrival.
func play_at(slot: int, world_position: Vector3) -> void:
	if slot < 0 or slot >= _bursts.size():
		return
	_play_column(slot, world_position)
	if slot == 0:
		_departure = world_position
		_departure_msec = Time.get_ticks_msec()
		_play_afterimages(world_position)
	else:
		_play_streak(world_position)
	var burst := _bursts[slot]
	burst.global_position = world_position + Vector3(0.0, 0.2, 0.0)
	burst.amount = maxi(int(BURST_AMOUNT * quality_scale), 1)
	burst.emitting = false
	if quality_scale > 0.0:
		burst.restart()
		burst.emitting = true

	var ring := _rings[slot]
	ring.global_position = world_position + Vector3(0.0, 0.08, 0.0)
	ring.scale = Vector3(0.3, 1.0, 0.3)
	ring.visible = true
	var material := ring.material_override as StandardMaterial3D
	material.albedo_color.a = 0.8
	if _ring_tweens[slot] != null and _ring_tweens[slot].is_valid():
		_ring_tweens[slot].kill()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.2, 1.0, 3.2), RING_SECONDS)
	tween.tween_property(material, "albedo_color:a", 0.0, RING_SECONDS)
	tween.chain().tween_callback(func() -> void: ring.visible = false)
	_ring_tweens[slot] = tween


func flash(strength: float = 0.4) -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_rect.color.a = strength
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_rect, "color:a", 0.0, 0.28)
