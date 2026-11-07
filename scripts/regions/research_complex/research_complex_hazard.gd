class_name ResearchComplexHazard
extends Area3D
## An electrified floor strip in the Containment Sector. A fixed 1.5 s cycle:
## SAFE (green lamp, 0.6 s) -> WARN (amber lamp, 0.5 s) -> ACTIVE (red lamp, 0.4 s, damages once).
## Damage only ever happens in ACTIVE, which is always preceded by the amber warning, and a dodge
## (invulnerable) avoids it like any other hit. It never damages twice in one active window.

enum Phase { SAFE, WARN, ACTIVE }

const SAFE_TIME: float = 0.6
const WARN_TIME: float = 0.5
const ACTIVE_TIME: float = 0.4
const CYCLE: float = SAFE_TIME + WARN_TIME + ACTIVE_TIME  # 1.5 s
const COLORS: Array[Color] = [Color(0.25, 0.85, 0.35), Color(1.0, 0.7, 0.1), Color(1.0, 0.15, 0.1)]

@export var size: Vector3 = Vector3(8.0, 1.5, 2.0)
@export var damage: float = 12.0
## Seconds into the cycle at start (so neighbouring strips are not in step).
@export var offset: float = 0.0

var phase: Phase = Phase.SAFE
var hits: int = 0

var _clock: float = 0.0
var _hit_this_window: bool = false
var _lamp: MeshInstance3D
var _lamp_material: StandardMaterial3D
var _attack: AttackData


func _ready() -> void:
	add_to_group("facility_hazards")
	collision_layer = 0
	collision_mask = 2  # the player layer, as AreaTrigger uses
	monitoring = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(shape)
	_attack = AttackData.new()
	_attack.id = &"floor_arc"
	_attack.damage = damage
	_attack.stamina_cost = 0.0
	_attack.knockback = 2.0
	_attack.stagger_time = 0.2
	_attack.hit_stop = 0.0
	_attack.shake = 0.3
	_lamp_material = StandardMaterial3D.new()
	_lamp_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lamp = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, 0.06, size.z)
	_lamp.mesh = mesh
	_lamp.material_override = _lamp_material
	_lamp.position = Vector3(0.0, 0.04, 0.0)
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp)
	_clock = fposmod(offset, CYCLE)
	_set_phase(_phase_at(_clock))


func _physics_process(delta: float) -> void:
	advance(delta)


## Moves the cycle forward (tests call this directly). Applies damage at most once per active window.
func advance(delta: float) -> void:
	_clock = fposmod(_clock + delta, CYCLE)
	var next := _phase_at(_clock)
	if next != phase:
		_set_phase(next)
	if phase == Phase.ACTIVE and not _hit_this_window:
		for body in get_overlapping_bodies():
			if body is Player:
				hurt(body)
				_hit_this_window = true  # one attempt per active window, even if the player was dodging


## Damages `body` through its normal hit path. Returns true when a hit landed.
func hurt(body: Node3D) -> bool:
	if phase != Phase.ACTIVE or not body.has_method("receive_hit"):
		return false
	hits += 1
	return bool(body.call("receive_hit", _attack, global_position + Vector3(0.0, 0.0, 1.0)))


static func _phase_at(clock: float) -> Phase:
	if clock < SAFE_TIME:
		return Phase.SAFE
	if clock < SAFE_TIME + WARN_TIME:
		return Phase.WARN
	return Phase.ACTIVE


func _set_phase(next: Phase) -> void:
	phase = next
	if next != Phase.ACTIVE:
		_hit_this_window = false
	if _lamp_material != null:
		_lamp_material.albedo_color = COLORS[int(next)]
