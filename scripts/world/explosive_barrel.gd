class_name ExplosiveBarrel
extends StaticBody3D
## A one-shot explosive barrel. Any player hit (it implements receive_hit like an enemy) lights the fuse;
## after FUSE_SECONDS it blows, hurting every enemy and the player inside `radius` with falloff, and
## lighting neighbouring barrels. The destroyed state is saved through PersistentIds when a region id is
## set, so a reload or revisit never brings it back. See docs/AI_SCHEDULER.md.

signal ignited
signal exploded(victims: int)

const FUSE_SECONDS: float = 1.2
const MIN_FALLOFF: float = 0.25
const FUSE_COLOR: Color = Color(1.0, 0.25, 0.1)
const BODY_COLOR: Color = Color(0.55, 0.12, 0.1)

@export var radius: float = 4.5
@export var damage: float = 45.0
@export var knockback: float = 9.0
## Region and id used to remember that this barrel was destroyed. Empty region = not persisted.
@export var region_id: StringName = &""
@export var barrel_id: StringName = &""

var is_lit: bool = false
var is_spent: bool = false
var fuse_left: float = 0.0

var _material: StandardMaterial3D
var _ring: MeshInstance3D


func _ready() -> void:
	add_to_group("explosive_barrels")
	collision_layer = 4  # solid to both sides, and found by the player's weapon hitbox
	collision_mask = 0
	if _persisted() and PersistentIds.is_claimed(region_id, _claim_id()):
		is_spent = true
		queue_free()
		return
	_build_visual()
	set_process(false)


## Fraction of full damage at `distance`: 1 at the centre, MIN_FALLOFF at the edge, 0 outside the radius.
static func falloff(distance: float, blast_radius: float) -> float:
	if distance > blast_radius or blast_radius <= 0.0:
		return 0.0
	return lerpf(1.0, MIN_FALLOFF, clampf(distance / blast_radius, 0.0, 1.0))


func receive_hit(_attack: AttackData, _from_position: Vector3, _damage_scale: float = 1.0) -> bool:
	if is_spent or is_lit:
		return false
	light()
	return true


func light() -> void:
	if is_spent or is_lit:
		return
	is_lit = true
	fuse_left = FUSE_SECONDS
	_material.albedo_color = FUSE_COLOR
	_ring.visible = true
	ignited.emit()
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## Steps the fuse (the tests call this directly instead of waiting for real time).
func advance(delta: float) -> void:
	if not is_lit or is_spent:
		return
	fuse_left -= delta
	var blink := 0.5 + 0.5 * sin(fuse_left * 24.0)
	_material.albedo_color = BODY_COLOR.lerp(FUSE_COLOR, blink)
	if fuse_left <= 0.0:
		explode()


func explode() -> int:
	if is_spent:
		return 0
	is_spent = true
	is_lit = false
	set_process(false)
	var victims := 0
	var blast := _blast_attack()
	for node in get_tree().get_nodes_in_group("enemies"):
		victims += _damage(node as Node3D, blast)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	victims += _damage(player, blast)
	for node in get_tree().get_nodes_in_group("explosive_barrels"):
		var other := node as ExplosiveBarrel
		if other != null and other != self and not other.is_spent \
				and other.global_position.distance_to(global_position) <= radius:
			other.light()
	if _persisted():
		PersistentIds.claim(region_id, _claim_id())
	exploded.emit(victims)
	collision_layer = 0
	queue_free()
	return victims


func _damage(target: Node3D, blast: AttackData) -> int:
	if target == null or not target.has_method("receive_hit"):
		return 0
	var scale := falloff(target.global_position.distance_to(global_position), radius)
	if scale <= 0.0:
		return 0
	return 1 if target.receive_hit(blast, global_position, scale) else 0


func _blast_attack() -> AttackData:
	var blast := AttackData.new()
	blast.id = &"barrel_blast"
	blast.damage = damage
	blast.knockback = knockback
	blast.stagger_time = 0.4
	blast.shake = 0.6
	return blast


func _persisted() -> bool:
	return region_id != &"" and barrel_id != &""


func _claim_id() -> StringName:
	return StringName("barrel_" + String(barrel_id))


func _build_visual() -> void:
	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = 0.45
	cyl_shape.height = 1.1
	shape.shape = cyl_shape
	shape.position.y = 0.55
	add_child(shape)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.45
	cyl.height = 1.1
	body.mesh = cyl
	body.position.y = 0.55
	_material = StandardMaterial3D.new()
	_material.albedo_color = BODY_COLOR
	body.material_override = _material
	add_child(body)
	# Blast-radius warning ring, visible only while the fuse burns.
	_ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.02
	_ring.mesh = disc
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(1.0, 0.2, 0.1, 0.25)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = ring_material
	_ring.position.y = 0.03
	_ring.visible = false
	add_child(_ring)
