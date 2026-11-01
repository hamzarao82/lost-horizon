extends RefCounted
## Stand-in for res://scripts/core/warmup.gd used by tests/boot_check.gd.

static var ran: int = 0
static var frames: Array[int] = []  # process frame of each call


static func steps() -> Array[Callable]:
	var out: Array[Callable] = []
	for i in 3:
		out.append(_bump)
	return out


static func _bump() -> void:
	ran += 1
	frames.append(Engine.get_process_frames())
