class_name MapData
extends Resource
## Map content of one region: the landmark list the world map draws, plus the pure helpers that decide
## what is shown (access status, discovery, objective marker, world-to-canvas transform). No drawing here.
##
## landmarks: Array of Dictionary
##   id    String   unique inside the region; for areas it is the same id the area trigger emits
##   name  String   shown once discovered
##   rect  Rect2    world (x, z) rectangle; size (0, 0) means a point marker
##   kind  String   "area", "arena", "checkpoint" or "landmark"
##   flag  String   WorldState flag that reveals it; "" means always known
## exits: Array of Dictionary {pos: Vector2 (x, z), label: String, target: String region id}. When present they
## replace the exits of RegionData (which still describe the stub regions); when empty the RegionData exits are used.
##
## Discovery flags are `<region_id>_discovered_<area slug>`: underscores only and at most 48 characters, because
## WorldState silently drops any other saved flag (see RegionFlags). The slug is the area id with a leading
## `<region_id>_` removed, so `blackwood_research_perimeter` does not push the flag over the limit.
## Dead Coast and Blackwood are generated from the builders' own area tables by tools/gen_map_data.gd (a test
## fails when they drift). The Research Complex list is still a PROVISIONAL placeholder: that level does not exist.
##
## A region counts as completed when the flags that unlock the NEXT region in CampaignFlow.CHAIN are set (its
## `after` flag or any alias), so the map and the campaign can never disagree; the last region uses its own
## mission 4 or `<region>_region_complete` flag, and `<region>_region_complete` / `<region>_completed` always count.

const DIR: String = "res://resources/regions/maps/"
const STATUS_CURRENT: StringName = &"current"
const STATUS_LOCKED: StringName = &"locked"
const STATUS_COMPLETED: StringName = &"completed"
const STATUS_AVAILABLE: StringName = &"available"
const FOG_NAME: String = "Unexplored"
## WorldState keeps saved flags only when they are [a-z0-9_] and at most this long.
const MAX_FLAG_LENGTH: int = 48
const LAST_REGION_MISSION: int = 4

static var _cache: Dictionary = {}

@export var region_id: StringName = &""
## Where the region sits on the overview map, 0..1 on each axis.
@export var overview_pos: Vector2 = Vector2(0.5, 0.5)
## Shown on the overview while the region is locked.
@export var unlock_hint: String = ""
@export var landmarks: Array = []
@export var exits: Array = []


static func load_for(id: StringName) -> MapData:
	if _cache.has(id):
		return _cache[id]
	var path := "%s%s.tres" % [DIR, id]
	var data: MapData = null
	if ResourceLoader.exists(path):
		data = load(path) as MapData
	if data == null:
		data = MapData.new()
		data.region_id = id
	_cache[id] = data
	return data


static func clear_cache() -> void:
	_cache.clear()


# --- discovery ---------------------------------------------------------------------------------

## The area id without a leading `<region>_` (the flag already names the region).
static func area_slug(region: StringName, area_id: StringName) -> String:
	var slug := String(area_id)
	var prefix := String(region) + "_"
	if slug.begins_with(prefix) and slug.length() > prefix.length():
		slug = slug.substr(prefix.length())
	return slug


static func discovery_flag(region: StringName, area_id: StringName) -> StringName:
	return RegionFlags.key(region, StringName("discovered_%s" % area_slug(region, area_id)))


static func mark_discovered(region: StringName, area_id: StringName) -> void:
	if region == &"" or area_id == &"":
		return
	var flag := discovery_flag(region, area_id)
	if String(flag).length() > MAX_FLAG_LENGTH:
		push_warning("MapData: discovery flag '%s' is longer than %d characters and would not survive a save" % [flag, MAX_FLAG_LENGTH])
		return
	var world := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("WorldState") if Engine.get_main_loop() else null
	if world != null:
		world.set_flag(flag)


static func is_flag_set(flag: String) -> bool:
	if flag == "":
		return true
	var loop := Engine.get_main_loop() as SceneTree
	var world := loop.root.get_node_or_null("WorldState") if loop else null
	return world != null and world.has_flag(StringName(flag))


## Landmarks ready to draw. Undiscovered ones keep their rect (drawn as fog) but lose their name.
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw in landmarks:
		if not (raw is Dictionary):
			continue
		var item: Dictionary = raw
		var known := is_flag_set(String(item.get("flag", "")))
		out.append({
			"id": String(item.get("id", "")),
			"name": String(item.get("name", "")) if known else FOG_NAME,
			"rect": item.get("rect", Rect2()),
			"kind": String(item.get("kind", "area")),
			"discovered": known,
		})
	return out


func discovered_count() -> int:
	var count := 0
	for entry in entries():
		if entry["discovered"]:
			count += 1
	return count


# --- regions overview ---------------------------------------------------------------------------

static func _region_manager() -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	return loop.root.get_node_or_null("RegionManager") if loop else null


static func current_region() -> StringName:
	var manager := _region_manager()
	if manager != null:
		return manager.current_region_id
	return RegionStore.OUTPOST_ID


## Every flag that marks `region` as finished (see the header).
static func completion_flags(region: StringName) -> Array[StringName]:
	var out: Array[StringName] = [RegionFlags.key(region, &"region_complete"), RegionFlags.key(region, &"completed")]
	var index := RegionStore.IDS.find(region)
	var next: StringName = RegionStore.IDS[index + 1] if index >= 0 and index + 1 < RegionStore.IDS.size() else &""
	if next != &"" and CampaignFlow.CHAIN.has(next):
		var rule: Dictionary = CampaignFlow.CHAIN[next]
		out.append(rule["after"])
		for alias in rule["aliases"]:
			out.append(alias)
	elif next == &"":
		out.append(CampaignFlow.mission_flag(region, LAST_REGION_MISSION))
	return out


static func is_completed(region: StringName) -> bool:
	var loop := Engine.get_main_loop() as SceneTree
	var world := loop.root.get_node_or_null("WorldState") if loop else null
	if world == null:
		return false
	for flag in completion_flags(region):
		if world.has_flag(flag):
			return true
	return false


static func is_unlocked(region: StringName) -> bool:
	var manager := _region_manager()
	if manager == null:
		return region == RegionStore.OUTPOST_ID
	return manager.is_unlocked(region)


## One of current / locked / completed / available. The region the player stands in is always "current".
static func region_status(region: StringName) -> StringName:
	if region == current_region():
		return STATUS_CURRENT
	if not is_unlocked(region):
		return STATUS_LOCKED
	if is_completed(region):
		return STATUS_COMPLETED
	return STATUS_AVAILABLE


static func overview_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in RegionStore.IDS:
		var data := RegionStore.load_data(id)
		var map := load_for(id)
		var locked := not is_unlocked(id)
		out.append({
			"id": id,
			"name": data.display_name if data != null else String(id),
			"status": region_status(id),
			"completed": is_completed(id),
			"locked": locked,
			"pos": map.overview_pos,
			"hint": map.unlock_hint if locked else "",
		})
	return out


# --- transform and markers ----------------------------------------------------------------------

## Pixels per world unit that fit `extents` into `canvas` with a margin, before zoom.
static func base_scale(extents: Rect2, canvas: Vector2, margin: float = 24.0) -> float:
	var avail := Vector2(maxf(canvas.x - 2.0 * margin, 1.0), maxf(canvas.y - 2.0 * margin, 1.0))
	return minf(avail.x / maxf(extents.size.x, 0.001), avail.y / maxf(extents.size.y, 0.001))


## World (x, z) to canvas pixels: north (negative z) is up; the extents centre sits at the canvas centre plus pan.
static func to_canvas(world: Vector2, extents: Rect2, canvas: Vector2, zoom: float = 1.0,
		pan: Vector2 = Vector2.ZERO, margin: float = 24.0) -> Vector2:
	var scale := base_scale(extents, canvas, margin) * zoom
	return canvas * 0.5 + pan + (world - extents.get_center()) * scale


static func rect_to_canvas(rect: Rect2, extents: Rect2, canvas: Vector2, zoom: float = 1.0,
		pan: Vector2 = Vector2.ZERO, margin: float = 24.0) -> Rect2:
	var a := to_canvas(rect.position, extents, canvas, zoom, pan, margin)
	var b := to_canvas(rect.end, extents, canvas, zoom, pan, margin)
	return Rect2(a, b - a)


## The objective compass target as a map position, only while the region being drawn is the one the
## player is in and the target lies inside that region's extents; otherwise null.
static func objective_marker(region: StringName, current: StringName, target: Variant) -> Variant:
	if region != current or not (target is Vector3):
		return null
	var data := RegionStore.load_data(region)
	var flat := Vector2((target as Vector3).x, (target as Vector3).z)
	if data == null or not data.map_extents.has_point(flat):
		return null
	return flat
