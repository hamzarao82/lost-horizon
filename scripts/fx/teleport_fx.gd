class_name TeleportFx
extends Node
## Two reusable teleport effects (departure and arrival): a cyan particle burst plus an expanding
## ring, and a brief screen flash. Everything is built once; playing one allocates nothing.
## CPU particles and a plain unshaded torus only, so it is cheap for the Compatibility renderer.

const RING_SECONDS: float = 0.35
const BURST_AMOUNT: int = 24
const COLOR: Color = Color(0.45, 0.9, 1.0)

var quality_scale: float = 1.0

var _bursts: Array[CPUParticles3D] = []
var _rings: Array[MeshInstance3D] = []
var _ring_tweens: Array[Tween] = []
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

	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(COLOR.r, COLOR.g, COLOR.b, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_flash_rect)


## slot 0 = departure, slot 1 = arrival.
func play_at(slot: int, world_position: Vector3) -> void:
	if slot < 0 or slot >= _bursts.size():
		return
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
