class_name EliteBar
extends Node3D
## A small billboard health bar above an elite or stage boss. Shown once damaged, or when the player is close;
## hidden for the dead and for anything beyond FAR_DISTANCE.

const WIDTH: float = 1.3
const HEIGHT: float = 0.12
const NEAR_DISTANCE: float = 12.0
const FAR_DISTANCE: float = 40.0
const ELITE_MIN_HEALTH: float = 150.0

var _enemy: Enemy
var _health: HealthComponent
var _fill: MeshInstance3D
var _back: MeshInstance3D


static func is_elite(enemy: Enemy) -> bool:
	return enemy != null and (AIScheduler.is_boss(enemy) or enemy is EliteExperimentalSubject
			or enemy.hit_points >= ELITE_MIN_HEALTH)


## Pure visibility rule: dead or far = hidden; damaged = shown; full health = shown only when near.
static func should_show(health_fraction: float, distance: float, dead: bool) -> bool:
	if dead or distance > FAR_DISTANCE:
		return false
	return health_fraction < 0.999 or distance <= NEAR_DISTANCE


## Adds a bar to `enemy` once (no-op if it already has one, or it is not an elite).
static func attach(enemy: Enemy) -> EliteBar:
	if not is_elite(enemy):
		return null
	var existing := enemy.get_node_or_null("EliteBar") as EliteBar
	if existing != null:
		return existing
	var bar := EliteBar.new()
	bar.name = "EliteBar"
	enemy.add_child(bar)
	return bar


func _ready() -> void:
	_enemy = get_parent() as Enemy
	if _enemy != null:
		_health = _enemy.get_node_or_null("HealthComponent") as HealthComponent
		position = Vector3(0.0, 2.3 * _enemy.body_scale, 0.0)
	_back = _quad(Color(0.05, 0.02, 0.02, 0.8), 0.0)
	_fill = _quad(Color(0.85, 0.15, 0.12), 0.001)
	visible = false


func _quad(color: Color, z_offset: float) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(WIDTH, HEIGHT)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.position.z = z_offset
	add_child(node)
	return node


func _process(_delta: float) -> void:
	if _enemy == null or _health == null:
		return
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(global_position) if camera != null else 0.0
	var fraction := _health.health / _health.max_health if _health.max_health > 0.0 else 0.0
	visible = should_show(fraction, distance, _enemy.is_dead())
	if visible:
		fraction = clampf(fraction, 0.0, 1.0)
		_fill.scale.x = maxf(fraction, 0.001)
		_fill.position.x = -WIDTH * 0.5 * (1.0 - fraction)
