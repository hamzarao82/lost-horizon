class_name RegionLabel
extends RefCounted
## The region name a player is allowed to see. Outpost 17 shows as "The Perimeter" until the player has seen
## the compound's sign (WorldState flag `outpost_name_known`); every other region shows its own name.

const MASKED_ID: StringName = &"outpost_17"
const MASKED_NAME: String = "The Perimeter"
const KNOWN_FLAG: StringName = &"outpost_name_known"


static func name_known() -> bool:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return true
	var world := loop.root.get_node_or_null("WorldState")
	return world != null and world.has_method("has_flag") and world.has_flag(KNOWN_FLAG)


static func name_for(region_id: StringName, display_name: String, known: bool) -> String:
	if region_id == MASKED_ID and not known:
		return MASKED_NAME
	return display_name


## The live game's answer. `display_name` is the region data's own name.
static func visible_name(region_id: StringName, display_name: String = "") -> String:
	var shown := display_name if display_name != "" else String(region_id)
	return name_for(region_id, shown, name_known())


## Pure truth table for "the First Signal waits for the compound sign": only a windowed New Game that has not
## yet started the opening and does not know the name yet.
static func opening_pending_for(headless: bool, intro_already_done: bool, name_is_known: bool) -> bool:
	return not (headless or intro_already_done or name_is_known)
