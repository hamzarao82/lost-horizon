extends SceneTree
## Headless check for the pause menu and Settings autoload:
##   godot --headless --path . -s tests/menu_check.gd
## Exits non-zero on failure. Uses a temporary settings file and restores all values.

const TEMP_CONFIG: String = "user://settings_menu_check.cfg"

var _failures: int = 0
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	var settings := root.get_node_or_null("/root/Settings")
	_check(settings != null, "Settings autoload is registered")
	if settings == null:
		quit(1)
		return
	_check(InputMap.has_action("pause"), "pause input action exists")

	# Save / load round trip with temporary values
	var original := [settings.config_path, settings.master_volume, settings.music_volume,
			settings.mouse_sensitivity, settings.touch_sensitivity, settings.quality]
	settings.config_path = TEMP_CONFIG
	settings.master_volume = 0.4
	settings.music_volume = 0.2
	settings.mouse_sensitivity = 1.75
	settings.touch_sensitivity = 0.5
	settings.quality = 1
	settings.save()
	settings.master_volume = 1.0
	settings.music_volume = 1.0
	settings.mouse_sensitivity = 1.0
	settings.touch_sensitivity = 1.0
	settings.quality = 2
	settings.load_settings()
	_check(is_equal_approx(settings.master_volume, 0.4) and is_equal_approx(settings.music_volume, 0.2),
			"audio volumes survive save/load")
	_check(is_equal_approx(settings.mouse_sensitivity, 1.75) and is_equal_approx(settings.touch_sensitivity, 0.5),
			"sensitivities survive save/load")
	_check(int(settings.quality) == 1, "quality survives save/load")
	settings.set_mouse_sensitivity(99.0)
	_check(is_equal_approx(settings.mouse_sensitivity, settings.MAX_SENSITIVITY), "sensitivity is clamped")

	# Pause menu, camera sensitivity and quality presets inside the real scene
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(3)

	var menu := main.get_node_or_null("PauseMenu") as PauseMenu
	_check(menu != null, "Main has a PauseMenu")
	if menu:
		_check(not paused and not menu.is_open(), "game starts unpaused")
		menu.toggle()
		_check(paused and menu.is_open(), "toggle pauses the tree")
		var time_scale := Engine.time_scale
		_check(is_equal_approx(time_scale, 1.0), "pausing leaves Engine.time_scale alone")
		menu.toggle()
		_check(not paused and not menu.is_open(), "toggle again resumes")

	var camera := get_first_node_in_group("camera_controller") as CameraController
	var light := main.get_node("DirectionalLight3D") as DirectionalLight3D
	settings.set_mouse_sensitivity(2.0)
	_check(camera != null and is_equal_approx(camera.mouse_sensitivity, 0.0025 * 2.0), "mouse sensitivity multiplier reaches the camera")
	settings.set_mouse_sensitivity(1.0)
	_check(is_equal_approx(camera.mouse_sensitivity, 0.0025), "multiplier 1.0 restores the authored value")

	settings.set_quality(0)
	_check(not light.shadow_enabled and is_equal_approx(root.scaling_3d_scale, 0.7), "Low: shadows off, render scale 0.7")
	settings.set_quality(1)
	_check(light.shadow_enabled and is_equal_approx(light.directional_shadow_max_distance, 20.0)
			and is_equal_approx(root.scaling_3d_scale, 0.85), "Medium: 20 m shadows, render scale 0.85")
	settings.set_quality(2)
	_check(light.shadow_enabled and is_equal_approx(light.directional_shadow_max_distance, 40.0)
			and is_equal_approx(root.scaling_3d_scale, 1.0), "High: authored shadows, full scale")

	main.queue_free()
	await _frames(3)
	_check(not paused, "tree is not left paused after the scene is freed")

	# Clean up the temp file and restore the real settings
	var absolute := ProjectSettings.globalize_path(TEMP_CONFIG)
	if FileAccess.file_exists(TEMP_CONFIG):
		DirAccess.remove_absolute(absolute)
	settings.config_path = original[0]
	settings.master_volume = original[1]
	settings.music_volume = original[2]
	settings.mouse_sensitivity = original[3]
	settings.touch_sensitivity = original[4]
	settings.quality = original[5]
	settings.apply_all()
	settings._save_timer = -1.0  # do not write the temporary values to the real file

	print("\n%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
