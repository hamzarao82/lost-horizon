class_name ContainmentControl
extends Node3D
## Visual shell for a ContainmentOverride: a console with one emissive lamp that shows the state
## (red locked, amber window open, green released). It only listens to the puzzle's signals.

const COLORS: Array[Color] = [Color(0.9, 0.12, 0.1), Color(1.0, 0.65, 0.1), Color(0.3, 0.85, 0.35), Color(0.3, 0.85, 0.35)]

var puzzle: ContainmentOverride
var lamp_color: Color = COLORS[0]

var _lamp: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 1.1, 0.6)
	body.mesh = box
	body.position = Vector3(0.0, 0.55, 0.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.22, 0.25)
	body.material_override = dark
	add_child(body)
	_lamp = MeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.12
	bulb.height = 0.24
	_lamp.mesh = bulb
	_lamp.position = Vector3(0.0, 1.25, 0.0)
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_lamp.material_override = _material
	_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp)
	refresh()


func bind(target: ContainmentOverride) -> void:
	puzzle = target
	target.window_changed.connect(refresh)
	target.step_completed.connect(_on_step)
	target.step_failed.connect(_on_step)
	target.completed.connect(refresh)
	refresh()


func _on_step(_step: StringName, _extra: Variant = null) -> void:
	refresh()


func refresh() -> void:
	var status := puzzle.status() if puzzle != null else 0
	lamp_color = COLORS[clampi(status, 0, COLORS.size() - 1)]
	if _material != null:
		_material.albedo_color = lamp_color
		_material.emission = lamp_color
