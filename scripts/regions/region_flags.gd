class_name RegionFlags
extends RefCounted
## WorldState flags stay global; this is the naming convention `<region_id>.<flag>` so regions never collide.


static func key(region_id: StringName, flag: StringName) -> StringName:
	return StringName("%s.%s" % [region_id, flag])


static func set_flag(region_id: StringName, flag: StringName, value: bool = true) -> void:
	var world := _world()
	if world != null:
		world.set_flag(key(region_id, flag), value)


static func has_flag(region_id: StringName, flag: StringName) -> bool:
	var world := _world()
	return world != null and world.has_flag(key(region_id, flag))


static func _world() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("WorldState") if loop else null
