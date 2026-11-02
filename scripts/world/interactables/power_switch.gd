class_name PowerSwitch
extends Interactable
## One of the three power switches of the "Restore Outpost Power" puzzle. It only reports the press:
## the ORDER logic lives in the SequencePuzzle (a node in group `sequence_puzzle` with try_press(id)).
## If the puzzle rejects a press (returns false) every switch resets and flashes red.

var is_on: bool = false

var _lamp: MeshInstance3D
var _lever: MeshInstance3D

static var _mat_off: StandardMaterial3D
static var _mat_on: StandardMaterial3D
static var _mat_bad: StandardMaterial3D
static var _mat_body: StandardMaterial3D


func _ready() -> void:
	super._ready()
	add_to_group("power_switches")
	prompt_text = "Throw switch"
	interact_radius = maxf(interact_radius, 2.2)
	_build()
	var state := get_node_or_null("/root/WorldState")
	if state:
		state.flag_changed.connect(_on_flag_changed)
		if state.has_flag(&"comms_power_on"):
			set_on(true)


func _make_materials() -> void:
	if _mat_off != null:
		return
	_mat_off = _unshaded(Color(0.55, 0.45, 0.1))
	_mat_on = _unshaded(Color(0.25, 1.0, 0.45))
	_mat_bad = _unshaded(Color(1.0, 0.2, 0.15))
	_mat_body = StandardMaterial3D.new()
	_mat_body.albedo_color = Color(0.22, 0.24, 0.24)


func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _build() -> void:
	_make_materials()
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.7, 1.1, 0.35)
	base.mesh = base_mesh
	base.position = Vector3(0.0, 0.55, -0.05)
	base.material_override = _mat_body
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(base)
	_lever = MeshInstance3D.new()
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.1, 0.45, 0.1)
	_lever.mesh = lever_mesh
	_lever.position = Vector3(0.0, 0.7, 0.2)
	_lever.rotation_degrees.x = -35.0
	_lever.material_override = _mat_body
	_lever.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lever)
	_lamp = MeshInstance3D.new()
	var lamp_mesh := BoxMesh.new()
	lamp_mesh.size = Vector3(0.22, 0.12, 0.05)
	_lamp.mesh = lamp_mesh
	_lamp.position = Vector3(0.0, 0.98, 0.14)
	_lamp.material_override = _mat_off
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp)


func set_on(value: bool) -> void:
	is_on = value
	_lamp.material_override = _mat_on if value else _mat_off
	_lever.rotation_degrees.x = 35.0 if value else -35.0


func _on_flag_changed(id: StringName, value: bool) -> void:
	if id == &"comms_power_on" and value:
		set_on(true)


func _on_interact(_player: Node3D) -> void:
	# The puzzle node normally exists from the start (Outpost17 builds it); creating it here is a safety net
	# so the switches can never fall back to "any order works".
	var puzzle: Node = get_tree().get_first_node_in_group("sequence_puzzle")
	if puzzle == null or not puzzle.has_method("try_press"):
		puzzle = SequencePuzzle.ensure(self)
	var accepted: Variant = puzzle.call("try_press", interaction_id)
	if accepted is bool and not accepted:
		_reject()
		return
	set_on(true)


## Wrong order: everything resets with a red flash (never an error).
func _reject() -> void:
	for node in get_tree().get_nodes_in_group("power_switches"):
		var other := node as PowerSwitch
		if other != null:
			other.set_on(false)
	_lamp.material_override = _mat_bad
	var tween := create_tween()
	tween.tween_interval(0.5)
	tween.tween_callback(func() -> void: set_on(false))
