extends Node
## Autoload "Settings": persisted player options (audio, look sensitivity, quality preset).
## Saved to user://settings.cfg (IndexedDB on web). Values apply live to whatever is in the tree.

signal changed

enum Quality { LOW, MEDIUM, HIGH }

const MUSIC_BASE_DB: float = -14.0
const SAVE_DELAY: float = 0.5
const MIN_SENSITIVITY: float = 0.25
const MAX_SENSITIVITY: float = 3.0
## shadow_distance < 0 keeps the light's authored distance.
const PRESETS: Dictionary = {
	Quality.LOW: {"shadows": false, "shadow_distance": -1.0, "scale": 0.7},
	Quality.MEDIUM: {"shadows": true, "shadow_distance": 20.0, "scale": 0.85},
	Quality.HIGH: {"shadows": true, "shadow_distance": -1.0, "scale": 1.0},
}

var config_path: String = "user://settings.cfg"
var master_volume: float = 1.0
var music_volume: float = 1.0
var mouse_sensitivity: float = 1.0  # multiplier on the camera's authored value
var touch_sensitivity: float = 1.0  # multiplier on TouchControls' authored value
var quality: Quality = Quality.HIGH
var hit_stop: HitStop.Level = HitStop.Level.NORMAL  # impact slow-motion: Off / Light / Normal

var _save_timer: float = -1.0


## Desktop-browser default. See docs/WEB_QA.md for the measurement behind this value.
const WEB_DESKTOP_QUALITY: Quality = Quality.HIGH


static func default_quality() -> Quality:
	if TouchControls.is_mobile_platform():
		return Quality.LOW
	if OS.has_feature("web") and bool(JavaScriptBridge.eval("/Android|iPhone|iPad|Mobile/i.test(navigator.userAgent)")):
		return Quality.LOW
	if OS.has_feature("web"):
		return WEB_DESKTOP_QUALITY
	return Quality.HIGH


func _ready() -> void:
	GamepadBindings.apply()
	process_mode = Node.PROCESS_MODE_ALWAYS
	quality = default_quality()
	load_settings()
	get_tree().node_added.connect(_on_node_added)
	apply_all()


func _process(delta: float) -> void:
	if _save_timer >= 0.0:
		_save_timer -= delta
		if _save_timer < 0.0:
			save()


func _exit_tree() -> void:
	if _save_timer >= 0.0:
		save()


# --- setters (apply live, save shortly after) --------------------------------

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_touched()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_audio()
	_touched()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY)
	_for_each_node(get_tree().root, _apply_sensitivity)
	_touched()


func set_touch_sensitivity(value: float) -> void:
	touch_sensitivity = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY)
	_for_each_node(get_tree().root, _apply_sensitivity)
	_touched()


func set_quality(value: Quality) -> void:
	quality = value
	_apply_quality()
	_touched()


func set_hit_stop(value: HitStop.Level) -> void:
	hit_stop = value
	HitStop.level = value
	_touched()


func flush() -> void:
	if _save_timer >= 0.0:
		save()


# --- persistence -----------------------------------------------------------

func save() -> void:
	_save_timer = -1.0
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "master_volume", master_volume)
	cfg.set_value("settings", "music_volume", music_volume)
	cfg.set_value("settings", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("settings", "touch_sensitivity", touch_sensitivity)
	cfg.set_value("settings", "quality", int(quality))
	cfg.set_value("settings", "hit_stop", int(hit_stop))
	cfg.save(config_path)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(config_path) != OK:
		return
	master_volume = clampf(float(cfg.get_value("settings", "master_volume", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("settings", "music_volume", music_volume)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(cfg.get_value("settings", "mouse_sensitivity", mouse_sensitivity)),
			MIN_SENSITIVITY, MAX_SENSITIVITY)
	touch_sensitivity = clampf(float(cfg.get_value("settings", "touch_sensitivity", touch_sensitivity)),
			MIN_SENSITIVITY, MAX_SENSITIVITY)
	quality = clampi(int(cfg.get_value("settings", "quality", int(quality))), 0, Quality.HIGH) as Quality
	hit_stop = clampi(int(cfg.get_value("settings", "hit_stop", int(hit_stop))),
			HitStop.Level.OFF, HitStop.Level.NORMAL) as HitStop.Level


func apply_all() -> void:
	HitStop.level = hit_stop
	_apply_audio()
	_apply_quality()
	_for_each_node(get_tree().root, _apply_sensitivity)


# --- applying ----------------------------------------------------------------

func _touched() -> void:
	_save_timer = SAVE_DELAY
	changed.emit()


func _apply_audio() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("set_master_volume"):
		audio.call("set_master_volume", master_volume)
	else:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	if audio:
		var music := audio.get("_music") as AudioStreamPlayer
		if music:
			music.volume_db = -80.0 if music_volume <= 0.001 else MUSIC_BASE_DB + linear_to_db(music_volume)


func _apply_quality() -> void:
	var preset: Dictionary = PRESETS[quality]
	get_tree().root.scaling_3d_scale = preset["scale"]
	_for_each_node(get_tree().root, _apply_light)


func _apply_light(node: Node) -> void:
	var light := node as DirectionalLight3D
	if light == null:
		return
	if not light.has_meta("lh_base_shadow_distance"):
		light.set_meta("lh_base_shadow_enabled", light.shadow_enabled)
		light.set_meta("lh_base_shadow_distance", light.directional_shadow_max_distance)
	var preset: Dictionary = PRESETS[quality]
	light.shadow_enabled = bool(light.get_meta("lh_base_shadow_enabled")) and preset["shadows"]
	var distance: float = preset["shadow_distance"]
	var base_distance: float = light.get_meta("lh_base_shadow_distance")
	light.directional_shadow_max_distance = base_distance if distance < 0.0 else minf(distance, base_distance)


func _apply_sensitivity(node: Node) -> void:
	var camera := node as CameraController
	if camera:
		if not camera.has_meta("lh_base_sensitivity"):
			camera.set_meta("lh_base_sensitivity", camera.mouse_sensitivity)
		camera.mouse_sensitivity = float(camera.get_meta("lh_base_sensitivity")) * mouse_sensitivity
		return
	var touch := node as TouchControls
	if touch:
		if not touch.has_meta("lh_base_sensitivity"):
			touch.set_meta("lh_base_sensitivity", touch.look_sensitivity)
		touch.look_sensitivity = float(touch.get_meta("lh_base_sensitivity")) * touch_sensitivity


func _on_node_added(node: Node) -> void:
	_apply_light(node)
	_apply_sensitivity(node)


func _for_each_node(node: Node, action: Callable) -> void:
	action.call(node)
	for child in node.get_children():
		_for_each_node(child, action)
