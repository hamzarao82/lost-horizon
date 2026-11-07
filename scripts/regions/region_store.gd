class_name RegionStore
extends RefCounted
## Static helpers for region data and save-section validation. Kept apart from the RegionManager autoload
## (an autoload and a class_name cannot share a name) so SaveManager and tests can use them without a scene.

const IDS: Array[StringName] = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex", &"iron_fortress"]
const DIR: String = "res://resources/regions/"
const OUTPOST_ID: StringName = &"outpost_17"
const MAX_ID_LENGTH: int = 64
const MAX_CLAIMED: int = 500
const MAX_CUSTOM_JSON: int = 20000
const POSITION_LIMIT: float = 2000.0

static var _cache: Dictionary = {}


static func is_known(id: Variant) -> bool:
	return (id is String or id is StringName) and IDS.has(StringName(id))


static func load_data(id: StringName) -> RegionData:
	if not is_known(id):
		return null
	if not _cache.has(id):
		_cache[id] = load("%s%s.tres" % [DIR, String(id)]) as RegionData
	return _cache[id]


static func default_section() -> Dictionary:
	return {"current": String(OUTPOST_ID), "states": {}, "unlocked": [String(OUTPOST_ID)]}


## Normalises the `regions` save section: unknown regions are dropped, types fixed, sizes bounded.
## Anything unusable falls back to "in Outpost 17, nothing unlocked, nothing claimed".
static func sanitize(raw: Variant) -> Dictionary:
	var out := default_section()
	if not raw is Dictionary:
		return out
	var data: Dictionary = raw
	var current := str(data.get("current", ""))
	if is_known(current):
		out["current"] = current
	var unlocked: Array = out["unlocked"]
	var unlocked_raw: Variant = data.get("unlocked", [])
	if unlocked_raw is Array:
		for id in unlocked_raw:
			if (id is String) and is_known(id) and not unlocked.has(id):
				unlocked.append(id)
	var states_out: Dictionary = out["states"]
	var states_raw: Variant = data.get("states", {})
	if states_raw is Dictionary:
		for key in states_raw:
			if not is_known(key) or not states_raw[key] is Dictionary:
				continue
			states_out[String(key)] = _sanitize_state(states_raw[key])
	var pos: Variant = _position(data.get("position", null))
	if pos != null and out["current"] != String(OUTPOST_ID):
		var v: Vector3 = pos
		out["position"] = [v.x, v.y, v.z]
	if out["current"] != String(OUTPOST_ID) and not unlocked.has(out["current"]):
		out["current"] = String(OUTPOST_ID)  # saved inside a region it never unlocked: start in Outpost 17
		out.erase("position")
	return out


static func _sanitize_state(raw: Dictionary) -> Dictionary:
	var ids := {}
	var ids_raw: Variant = raw.get("ids", {})
	if ids_raw is Dictionary:
		for key in ids_raw:
			if ids.size() >= MAX_CLAIMED:
				break
			var s := str(key)
			if s.length() > 0 and s.length() <= MAX_ID_LENGTH:
				ids[s] = true
	var custom: Dictionary = {}
	var custom_raw: Variant = raw.get("custom", {})
	if custom_raw is Dictionary and JSON.stringify(custom_raw).length() <= MAX_CUSTOM_JSON:
		custom = (custom_raw as Dictionary).duplicate(true)
	return {"ids": ids, "custom": custom}


static func _position(raw: Variant) -> Variant:
	if raw is Array and (raw as Array).size() == 3:
		var a: Array = raw
		for v in a:
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				return null
		return Vector3(clampf(float(a[0]), -POSITION_LIMIT, POSITION_LIMIT),
				clampf(float(a[1]), -POSITION_LIMIT, POSITION_LIMIT),
				clampf(float(a[2]), -POSITION_LIMIT, POSITION_LIMIT))
	return null
