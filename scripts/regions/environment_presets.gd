class_name EnvironmentPresets
extends RefCounted
## Applies an EnvironmentPreset to the persistent WorldEnvironment and DirectionalLight3D (both stay in
## the tree across region travel). One tween per change; nothing runs per frame once it ends.
## Called by RegionManager when a region becomes current; `outpost_17` equals the authored Main.tscn look.

const DIR: String = "res://resources/regions/env/"
const IDS: Array[StringName] = [&"outpost_17", &"dead_coast", &"blackwood", &"research_complex"]
const DEFAULT_TWEEN: float = 1.5
## Web and mobile: no glow and a shorter shadow range (docs/PERFORMANCE_BUDGET.md: web sun <= 30 m).
const LITE_SHADOW_WEB: float = 30.0
const LITE_SHADOW_MOBILE: float = 25.0
## Distance used by the readability estimate below.
const VIEW_DISTANCE: float = 15.0

static var current_id: StringName = &""
static var _cache: Dictionary = {}
static var _tween: Tween


## outpost_17.tres names its preset `outpost` (the audio name); both resolve to the same look.
const ALIASES: Dictionary = {&"outpost": &"outpost_17"}


static func get_preset(id: StringName) -> EnvironmentPreset:
	id = ALIASES.get(id, id)
	if _cache.has(id):
		return _cache[id]
	var path := "%s%s.tres" % [DIR, String(id)]
	var preset: EnvironmentPreset = null
	if ResourceLoader.exists(path):
		preset = load(path) as EnvironmentPreset
	_cache[id] = preset
	return preset


static func is_lite() -> bool:
	return OS.has_feature("web") or OS.has_feature("mobile")


## The values that are actually applied: the preset with the platform limits folded in.
static func effective_values(preset: EnvironmentPreset, lite: bool) -> Dictionary:
	var v := preset.values()
	if lite:
		v["glow_enabled"] = false
		var cap := LITE_SHADOW_WEB if OS.has_feature("web") else LITE_SHADOW_MOBILE
		v["shadow_distance"] = minf(float(v["shadow_distance"]), cap)
	return v


## Applies `preset_id`. lite_override: -1 platform default, 0 full, 1 lite. Returns false if nothing was applied
## (unknown preset, or no WorldEnvironment in the tree).
static func apply(preset_id: StringName, tween_seconds: float = DEFAULT_TWEEN, lite_override: int = -1, tree: SceneTree = null) -> bool:
	var preset := get_preset(preset_id)
	if preset == null:
		push_warning("EnvironmentPresets: unknown preset '%s'" % String(preset_id))
		return false
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var targets := find_targets(tree)
	if targets.is_empty():
		return false
	var lite := is_lite() if lite_override < 0 else lite_override == 1
	var to := effective_values(preset, lite)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	current_id = preset.id
	if tween_seconds <= 0.0:
		_blend(targets, to, to, 1.0)
		return true
	var from := read_current(tree)
	_tween = tree.create_tween()
	_tween.tween_method(func(t: float) -> void: _blend(targets, from, to, t), 0.0, 1.0, tween_seconds)
	return true


## The first WorldEnvironment with a procedural sky, plus the first DirectionalLight3D.
static func find_targets(tree: SceneTree) -> Dictionary:
	var out := {}
	for node in tree.root.find_children("*", "WorldEnvironment", true, false):
		var world_env := node as WorldEnvironment
		if world_env.environment == null or world_env.environment.sky == null:
			continue
		var sky_mat := world_env.environment.sky.sky_material as ProceduralSkyMaterial
		if sky_mat == null:
			continue
		out["env"] = world_env.environment
		out["sky"] = sky_mat
		break
	if out.is_empty():
		return out
	for node in tree.root.find_children("*", "DirectionalLight3D", true, false):
		out["sun"] = node
		break
	return out


static func read_current(tree: SceneTree) -> Dictionary:
	var t := find_targets(tree)
	if t.is_empty():
		return {}
	var env: Environment = t["env"]
	var sky: ProceduralSkyMaterial = t["sky"]
	var v := {
		"sky_top": sky.sky_top_color, "sky_horizon": sky.sky_horizon_color,
		"ground_bottom": sky.ground_bottom_color, "ground_horizon": sky.ground_horizon_color,
		"ambient_color": env.ambient_light_color, "ambient_energy": env.ambient_light_energy,
		"ambient_sky_contribution": env.ambient_light_sky_contribution,
		"fog_color": env.fog_light_color, "fog_density": env.fog_density,
		"fog_sky_affect": env.fog_sky_affect, "tonemap_exposure": env.tonemap_exposure,
		"glow_enabled": env.glow_enabled,
	}
	var sun := t.get("sun") as DirectionalLight3D
	if sun != null:
		v["sun_color"] = sun.light_color
		v["sun_energy"] = sun.light_energy
		v["sun_pitch"] = sun.rotation_degrees.x
		v["sun_yaw"] = sun.rotation_degrees.y
		v["shadow_distance"] = _base_shadow_distance(sun)
	return v


static func _base_shadow_distance(sun: DirectionalLight3D) -> float:
	if sun.has_meta("lh_base_shadow_distance"):
		return float(sun.get_meta("lh_base_shadow_distance"))
	return sun.directional_shadow_max_distance


static func _blend(targets: Dictionary, from: Dictionary, to: Dictionary, t: float) -> void:
	var env := targets.get("env") as Environment
	var sky := targets.get("sky") as ProceduralSkyMaterial
	if not is_instance_valid(env) or not is_instance_valid(sky):
		return
	var v := to if t >= 1.0 else _lerp_values(from, to, t)
	sky.sky_top_color = v["sky_top"]
	sky.sky_horizon_color = v["sky_horizon"]
	sky.ground_bottom_color = v["ground_bottom"]
	sky.ground_horizon_color = v["ground_horizon"]
	env.ambient_light_color = v["ambient_color"]
	env.ambient_light_energy = v["ambient_energy"]
	env.ambient_light_sky_contribution = v["ambient_sky_contribution"]
	env.fog_light_color = v["fog_color"]
	env.fog_density = v["fog_density"]
	env.fog_sky_affect = v["fog_sky_affect"]
	env.tonemap_exposure = v["tonemap_exposure"]
	env.glow_enabled = v["glow_enabled"]
	# The sun belongs to a scene that can be freed mid-tween; casting a freed object is a script error.
	var sun_node: Variant = targets.get("sun")
	var sun: DirectionalLight3D = sun_node if is_instance_valid(sun_node) else null
	if sun != null and v.has("sun_color"):
		sun.light_color = v["sun_color"]
		sun.light_energy = v["sun_energy"]
		sun.rotation_degrees = Vector3(v["sun_pitch"], v["sun_yaw"], sun.rotation_degrees.z)
		sun.directional_shadow_max_distance = v["shadow_distance"]
		if t >= 1.0:
			# Settings scales the light's authored distance per quality preset: hand it the new authored value.
			sun.set_meta("lh_base_shadow_distance", float(v["shadow_distance"]))
			var settings := sun.get_node_or_null("/root/Settings")
			if settings != null and settings.has_method("_apply_light"):
				settings.call("_apply_light", sun)


static func _lerp_values(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in to:
		var a: Variant = from.get(key, to[key])
		var b: Variant = to[key]
		if b is Color:
			out[key] = (a as Color).lerp(b, t)
		elif b is bool:
			out[key] = a if t < 1.0 else b
		elif key == "sun_yaw":
			out[key] = rad_to_deg(lerp_angle(deg_to_rad(float(a)), deg_to_rad(float(b)), t))
		else:
			out[key] = lerpf(float(a), float(b), t)
	return out


static func luminance(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Relative brightness of a mid-grey (0.5 albedo) surface seen through 15 m of fog. A comparison number for the
## readability test, NOT a render: surface = 0.5 * (ambient + sun * sin(elevation)); fog adds a grey-lit fog colour.
static func readability_estimate(preset: EnvironmentPreset) -> float:
	var elevation := clampf(-preset.sun_pitch, 0.0, 90.0)
	var sun_term := preset.sun_energy * luminance(preset.sun_color) * sin(deg_to_rad(elevation))
	var surface := 0.5 * (preset.ambient_energy * luminance(preset.ambient_color) + sun_term)
	var transmit := exp(-preset.fog_density * VIEW_DISTANCE)
	var fog_in := 0.5 * luminance(preset.fog_color)
	return preset.tonemap_exposure * (surface * transmit + fog_in * (1.0 - transmit))
