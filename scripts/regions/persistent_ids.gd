class_name PersistentIds
extends RefCounted
## One-time ids per region (collectibles, caches, cleared encounters, unique rewards). The claimed set is
## saved with the region state, so reloading or revisiting can never hand out the same reward twice.
##
##   if PersistentIds.claim(&"dead_coast", &"cache_wreck_01"):
##       give_the_reward()


static func claim(region_id: StringName, id: StringName) -> bool:
	var manager := _manager()
	return manager != null and manager.claim(region_id, id)


static func is_claimed(region_id: StringName, id: StringName) -> bool:
	var manager := _manager()
	return manager != null and manager.is_claimed(region_id, id)


static func count(region_id: StringName) -> int:
	var manager := _manager()
	return manager.claimed_count(region_id) if manager != null else 0


static func _manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("RegionManager") if loop else null
