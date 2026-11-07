class_name Projectile
extends Node3D
## A pooled, ray-stepped shot. It travels in a straight line, stops on the first world collider or on
## the player, and hits at most once. Damage goes through the target's own receive_hit(), the same call
## melee uses, so armor, resistances and dodge i-frames apply exactly once.

const SCENE: String = "res://scenes/combat/Projectile.tscn"
const LIVE_CAP: int = 12
const LIFETIME: float = 2.5
const WORLD_MASK: int = 1
const PLAYER_MASK: int = 2

static var _pool: Array[Projectile] = []
static var _live: int = 0
static var _scene: PackedScene

var attack: AttackData
var source: Node3D
var damage_scale: float = 1.0
var direction: Vector3 = Vector3.FORWARD
var speed: float = 18.0
## What ended the flight: "player", "world", "expired", or "" while flying. For tests and FX.
var ended_by: String = ""

var _age: float = 0.0
var _active: bool = false
var _query: PhysicsRayQueryParameters3D


static func live_count() -> int:
	return _live


static func pool_size() -> int:
	return _pool.size()


## Forgets every pooled shot (tests, scene reloads). Live shots are deactivated first.
static func reset_pool() -> void:
	for p in _pool:
		if is_instance_valid(p):
			p.deactivate()
			p.queue_free()
	_pool.clear()
	_live = 0


## Fires one shot. Returns null (and fires nothing) when the live cap is reached.
static func fire(parent: Node, origin: Vector3, aim: Vector3, shot: AttackData, owner_node: Node3D,
		velocity: float, scale: float = 1.0) -> Projectile:
	if _live >= LIVE_CAP or parent == null or shot == null:
		return null
	var p := _take(parent)
	if p == null:
		return null
	p.attack = shot
	p.source = owner_node
	p.damage_scale = scale
	p.speed = velocity
	p.direction = aim.normalized() if aim.length_squared() > 0.0001 else Vector3.FORWARD
	p.ended_by = ""
	p._age = 0.0
	var up := Vector3.FORWARD if absf(p.direction.dot(Vector3.UP)) > 0.99 else Vector3.UP  # looking_at fails when parallel
	p.global_transform = Transform3D(Basis.looking_at(p.direction, up), origin)
	p._activate()
	return p


static func _take(parent: Node) -> Projectile:
	var i := _pool.size() - 1
	while i >= 0:
		var p := _pool[i]
		if not is_instance_valid(p):
			_pool.remove_at(i)
		elif not p._active:
			if p.get_parent() != parent:
				if p.get_parent() != null:
					p.get_parent().remove_child(p)
				parent.add_child(p)
			return p
		i -= 1
	if _scene == null:
		_scene = load(SCENE) as PackedScene
	var fresh := _scene.instantiate() as Projectile
	fresh.visible = false
	parent.add_child(fresh)
	_pool.append(fresh)
	return fresh


func _ready() -> void:
	set_physics_process(false)
	top_level = true  # never inherits a moving parent's transform
	_query = PhysicsRayQueryParameters3D.new()
	_query.collision_mask = WORLD_MASK | PLAYER_MASK
	_query.collide_with_areas = false


func is_active() -> bool:
	return _active


func _activate() -> void:
	if not _active:
		_live += 1
	_active = true
	visible = true
	set_physics_process(true)


func deactivate() -> void:
	if _active:
		_live = maxi(_live - 1, 0)
	_active = false
	visible = false
	set_physics_process(false)


func _exit_tree() -> void:
	if _active:
		_live = maxi(_live - 1, 0)
		_active = false


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	if _age >= LIFETIME:
		ended_by = "expired"
		deactivate()
		return
	var from := global_position
	var to := from + direction * speed * delta
	_query.from = from
	_query.to = to
	if source is CollisionObject3D:
		_query.exclude = [(source as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if hit.is_empty():
		global_position = to
		return
	var collider := hit.get("collider") as Object
	global_position = hit.get("position", to)
	if collider != null and collider != source and collider.has_method("receive_hit"):
		ended_by = "player"
		# Knockback runs away from the shooter along the shot, not from the point of impact.
		collider.receive_hit(attack, global_position - direction * 1.5, damage_scale)
	else:
		ended_by = "world"
	deactivate()
