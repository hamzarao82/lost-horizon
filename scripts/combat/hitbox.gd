class_name Hitbox
extends Area3D
## Damage only happens while the hitbox is active, and at most once per target per activation.
## Targets implement receive_hit(attack, from_position) -> bool.

signal hit(body: Node3D, attack: AttackData)

var attack: AttackData
var source: Node3D

var _active: bool = false
var _already_hit: Array[Node3D] = []


func activate(new_attack: AttackData, new_source: Node3D) -> void:
	attack = new_attack
	source = new_source
	_already_hit.clear()
	_active = true
	monitoring = true


func deactivate() -> void:
	_active = false
	monitoring = false


func is_active() -> bool:
	return _active


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	for body in get_overlapping_bodies():
		if body == source or _already_hit.has(body) or not body.has_method("receive_hit"):
			continue
		_already_hit.append(body)
		if body.receive_hit(attack, source.global_position):
			hit.emit(body, attack)
