class_name CameraController
extends Node3D
## Look rig. Attach to CameraPivot; yaw/pitch rotate this node,
## so the player body itself never needs to turn with the camera.
## Mouse input on desktop, apply_look() for touch, add_trauma() for hit shake.

@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_deg: float = -70.0
@export var max_pitch_deg: float = 45.0
@export var shake_decay: float = 2.5
@export var max_shake_offset: float = 0.25

@onready var _spring_arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D

var _pitch: float = deg_to_rad(-15.0)
var _trauma: float = 0.0


func _ready() -> void:
	add_to_group("camera_controller")
	# Browsers refuse pointer lock without a user gesture, so on web the first click captures.
	if not OS.has_feature("web") and not TouchControls.is_mobile_platform():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rotation.x = _pitch
	var body := get_parent() as CollisionObject3D
	if body:
		_spring_arm.add_excluded_object(body.get_rid())


func apply_look(relative: Vector2, sensitivity: float) -> void:
	rotation.y -= relative.x * sensitivity
	_pitch = clampf(_pitch - relative.y * sensitivity,
			deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	rotation.x = _pitch


func add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	var power := _trauma * _trauma * max_shake_offset
	_camera.h_offset = randf_range(-1.0, 1.0) * power
	_camera.v_offset = randf_range(-1.0, 1.0) * power


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative, mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not TouchControls.is_mobile_platform():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
