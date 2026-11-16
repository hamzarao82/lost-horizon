class_name WorkerWalker
extends Node3D
## A visual-only figure that walks a path back and forth: a worker (hunched, maybe carrying a crate) or a
## guard (upright, rifle, slower). No physics, no AI, no collision: it only sells a place that is in use.
## It sleeps (hidden, not processed) beyond `view_distance` of the player so a far-away yard costs nothing.

@export var path: PackedVector3Array = PackedVector3Array()
@export var speed: float = 0.9
@export var guard: bool = false
@export var carrying: bool = false
@export var view_distance: float = 80.0
@export var pause_seconds: float = 1.6

var awake: bool = true

var _index: int = 0
var _dir: int = 1
var _wait: float = 0.0
var _check: float = 0.0
var _clock: float = 0.0
var _body: Node3D

static var _materials: Dictionary = {}


func _ready() -> void:
	if path.size() >= 1:
		position = path[0]
	if DisplayServer.get_name() == "headless":
		set_process(false)  # tests step it with advance()
		return
	_build()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_refresh_awake()
	if not awake or path.size() < 2:
		return
	_clock += delta
	if _wait > 0.0:
		_wait -= delta
		return
	var target := path[_index + _dir] if _index + _dir >= 0 and _index + _dir < path.size() else path[_index]
	var to := target - position
	to.y = 0.0
	var step := speed * delta
	if to.length() <= step:
		position = Vector3(target.x, position.y, target.z)
		_index += _dir
		if _index <= 0 or _index >= path.size() - 1:
			_dir = -_dir
			_wait = pause_seconds
		return
	var heading := to.normalized()
	position += heading * step
	rotation.y = atan2(heading.x, heading.z)
	if _body != null:
		_body.position.y = absf(sin(_clock * 6.0)) * 0.04 if not guard else 0.0


func _refresh_awake() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null
	if player == null:
		return
	awake = global_position.distance_to(player.global_position) <= view_distance
	visible = awake


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.95
		_materials[key] = m
	return _materials[key]


func _build() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	# The real soldier model on its running clip, slowed to a walk pace (the model set has no walk clip).
	var model := OpeningArt.character(OpeningArt.SOLDIER_MODEL, "run", Color(0.56, 0.7, 0.56) if guard else Color(0.86, 0.77, 0.62), clampf(speed * 0.3, 0.12, 0.6))
	if model != null:
		model.name = "SoldierModel"
		model.rotation.y = PI  # the model faces -Z; a walker moves toward +Z
		if not guard:
			model.scale = Vector3(1.0, 0.94, 1.0)  # a worker stoops a little
		_body.add_child(model)
		_add_props()
		return
	_build_capsule()


## Procedural fallback, used only if the model file is missing.
func _build_capsule() -> void:
	var torso := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.27
	capsule.height = 1.5
	capsule.radial_segments = 8
	capsule.rings = 2
	torso.mesh = capsule
	torso.material_override = _material(Color(0.19, 0.25, 0.2) if guard else Color(0.36, 0.31, 0.24))
	torso.position = Vector3(0.0, 0.85, 0.0)
	torso.rotation.x = 0.0 if guard else 0.24
	_body.add_child(torso)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.17
	sphere.height = 0.34
	sphere.radial_segments = 8
	sphere.rings = 4
	head.mesh = sphere
	head.material_override = _material(Color(0.55, 0.42, 0.33))
	head.position = Vector3(0.0, 1.72 if guard else 1.62, 0.0 if guard else 0.14)
	_body.add_child(head)
	_add_props()


## What a guard carries (a rifle) or a worker carries (a crate of stores). Built on top of either body.
func _add_props() -> void:
	if guard:
		var rifle := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.07, 0.08, 0.95)
		rifle.mesh = box
		rifle.material_override = _material(Color(0.1, 0.1, 0.1))
		rifle.position = Vector3(0.28, 1.1, 0.1)
		rifle.rotation.x = -0.35
		_body.add_child(rifle)
	elif carrying:
		var crate := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.5, 0.4, 0.42)
		crate.mesh = cbox
		crate.material_override = _material(ArenaDecor.WOOD)
		crate.position = Vector3(0.0, 1.02, 0.36)  # held at the chest, in front of the hands
		_body.add_child(crate)
