class_name HitStop
extends RefCounted
## Brief global slow-down on impact. Real-time timer so it always recovers.

static var enabled: bool = true


static func reset() -> void:
	Engine.time_scale = 1.0


static func trigger(seconds: float) -> void:
	if not enabled or seconds <= 0.0 or Engine.time_scale < 1.0:
		return
	Engine.time_scale = 0.05
	var tree := Engine.get_main_loop() as SceneTree
	await tree.create_timer(seconds, true, false, true).timeout
	Engine.time_scale = 1.0
