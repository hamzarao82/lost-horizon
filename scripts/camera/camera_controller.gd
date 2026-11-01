class_name CameraController
extends Node3D
## Look rig. Attach to CameraPivot; yaw/pitch rotate this node,
## so the player body itself never needs to turn with the camera.
## Mouse input on desktop, apply_look() for touch, add_trauma() for hit shake,
## set_lock_target() to keep a locked-on enemy in view.

@export var mouse_sensitivity: float = 0.0025
@export var min_pitch_deg: float = -70.0
@export var max_pitch_deg: float = 45.0
@export var shake_decay: float = 2.5
@export var max_shake_offset: float = 0.25
@export var sprint_fov_boost: float = 8.0
@export var lag_strength: float = 0.02
@export var lock_yaw_speed: float = 5.0
@export var lock_pitch_deg: float = -18.0

@onready var _spring_arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D

var _pitch: float = deg_to_rad(-15.0)
var _trauma: float = 0.0
var _base_fov: float = 75.0
var _lag: Vector2 = Vector2.ZERO
var _lock_target: Node3D
var _player: Player


func _ready() -> void:
	add_to_group("camera_controller")
	# Browsers refuse pointer lock without a user gesture, so on web the first click captures.
	if not OS.has_feature("web") and not TouchControls.is_mobile_platform():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	rotation.x = _pitch
	_base_fov = _camera.fov
	_player = get_parent() as Player
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


func set_lock_target(target: Node3D) -> void:
	_lock_target = target


func clear_lock_target() -> void:
	_lock_target = null


func has_lock_target() -> bool:
	return _lock_target != null and is_instance_valid(_lock_target)


func _process(delta: float) -> void:
	_follow_lock_target(delta)
	_update_fov_and_lag(delta)
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	var power := _trauma * _trauma * max_shake_offset
	_camera.h_offset = randf_range(-1.0, 1.0) * power + _lag.x
	_camera.v_offset = randf_range(-1.0, 1.0) * power + _lag.y


func _follow_lock_target(delta: float) -> void:
	if _lock_target != null and not is_instance_valid(_lock_target):
		_lock_target = null
	if _lock_target == null:
		return
	var to := _lock_target.global_position - global_position
	if Vector2(to.x, to.z).length_squared() < 0.01:
		return
	var follow := 1.0 - exp(-lock_yaw_speed * delta)  # frame-rate independent easing
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), follow)
	_pitch = lerpf(_pitch, deg_to_rad(lock_pitch_deg), 1.0 - exp(-2.0 * delta))
	rotation.x = _pitch


func _update_fov_and_lag(delta: float) -> void:
	if _player == null:
		return
	var target_fov := _base_fov + (sprint_fov_boost if _player.is_sprinting() else 0.0)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-6.0 * delta))
	var local_velocity := Basis(Vector3.UP, global_rotation.y).inverse() * _player.velocity
	var wanted := Vector2(-local_velocity.x, local_velocity.y * 0.75) * lag_strength
	_lag = _lag.lerp(wanted.limit_length(0.35), 1.0 - exp(-5.0 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative, mouse_sensitivity)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not TouchControls.is_mobile_platform():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
