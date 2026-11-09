extends SceneTree
## The objective arrow's screen direction must follow the camera heading only.
## godot --headless --path . -s tests/pointer_direction_check.gd

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.001


func _run() -> void:
	var level := Basis.IDENTITY  # camera looking along -z
	_check(_near(ObjectivePointer.screen_direction(level, Vector2(0.0, -10.0)).normalized(), Vector2(0.0, -1.0)), "a target straight ahead is up")
	_check(_near(ObjectivePointer.screen_direction(level, Vector2(10.0, 0.0)).normalized(), Vector2(1.0, 0.0)), "a target to the right is right")
	_check(_near(ObjectivePointer.screen_direction(level, Vector2(-10.0, 0.0)).normalized(), Vector2(-1.0, 0.0)), "a target to the left is left")
	_check(_near(ObjectivePointer.screen_direction(level, Vector2(0.0, 10.0)).normalized(), Vector2(0.0, 1.0)), "a target behind is down")

	# A third-person camera tilts down 30 degrees: the answer must not change.
	var pitched := Basis(Vector3.RIGHT, deg_to_rad(-30.0))
	for offset in [Vector2(0.0, -6.0), Vector2(4.0, -3.0), Vector2(-7.0, 2.0), Vector2(1.0, 20.0)]:
		var flat := ObjectivePointer.screen_direction(level, offset)
		var tilted := ObjectivePointer.screen_direction(pitched, offset)
		_check(_near(flat, tilted), "a 30 degree downward tilt does not bend the arrow for %s" % str(offset))

	# The camera turns 90 degrees to the right (yaw -90): what was ahead (-z) is now to the left.
	var turned := Basis(Vector3.UP, deg_to_rad(-90.0))
	_check(_near(ObjectivePointer.screen_direction(turned, Vector2(0.0, -10.0)).normalized(), Vector2(-1.0, 0.0)), "after turning right, the old forward is on the left")
	_check(_near(ObjectivePointer.screen_direction(turned, Vector2(10.0, 0.0)).normalized(), Vector2(0.0, -1.0)), "after turning right, a target on the old right is ahead")

	# Yaw and tilt together.
	var both := Basis(Vector3.UP, deg_to_rad(40.0)) * Basis(Vector3.RIGHT, deg_to_rad(-25.0))
	var yaw_only := Basis(Vector3.UP, deg_to_rad(40.0))
	_check(_near(ObjectivePointer.screen_direction(both, Vector2(3.0, -8.0)), ObjectivePointer.screen_direction(yaw_only, Vector2(3.0, -8.0))), "yaw plus tilt equals yaw alone")

	# Looking straight down must not produce nonsense.
	var down := Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	var straight := ObjectivePointer.screen_direction(down, Vector2(5.0, -5.0))
	_check(is_finite(straight.x) and is_finite(straight.y), "looking straight down gives a finite direction")
	print("pointer_direction_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
