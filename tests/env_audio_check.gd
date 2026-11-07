extends SceneTree
## Region environment presets and region ambience (headless):
##   godot --headless --path . -s tests/env_audio_check.gd
## Nothing here can judge how anything sounds or looks: it checks values, state machines and files.

const MAIN_SCENE: String = "res://scenes/main/Main.tscn"
const AudioScript = preload("res://scripts/audio/audio_manager.gd")
const NEW_FILES: Array[String] = ["ambience_coast", "ambience_jungle", "ambience_facility", "bird_flush", "metal_creak"]
const EPS: float = 0.00001

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


func _same(a: Variant, b: Variant) -> bool:
	if a is Color and b is Color:
		return absf(a.r - b.r) < EPS and absf(a.g - b.g) < EPS and absf(a.b - b.b) < EPS
	if a is bool or b is bool:
		return a == b
	return absf(float(a) - float(b)) < EPS


func _dict_same(a: Dictionary, b: Dictionary) -> String:
	for key in a:
		if not b.has(key):
			return "missing key %s" % key
		if not _same(a[key], b[key]):
			return "%s: %s vs %s" % [key, str(a[key]), str(b[key])]
	return ""


func _frames(count: int) -> void:
	for i in count:
		await process_frame


func _run() -> void:
	_check_presets()
	await _check_apply()
	await _check_crossfade()
	_check_files()
	print("env_audio_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- presets -------------------------------------------------------------------

func _check_presets() -> void:
	var presets := {}
	for id in EnvironmentPresets.IDS:
		var p := EnvironmentPresets.get_preset(id)
		_check(p != null and p.id == id, "preset '%s' loads with its own id" % String(id))
		presets[id] = p
	_check(EnvironmentPresets.get_preset(&"nope") == null, "unknown preset id returns null")

	var sky_tops := []
	for id in EnvironmentPresets.IDS:
		var p: EnvironmentPreset = presets[id]
		_check(p.sun_energy > 0.0 and p.ambient_energy > 0.0 and p.fog_density > 0.0 and p.shadow_distance > 0.0,
				"'%s' has positive energies, fog density and shadow distance" % String(id))
		sky_tops.append(p.sky_top)
	var distinct := true
	for i in sky_tops.size():
		for j in range(i + 1, sky_tops.size()):
			if _same(sky_tops[i], sky_tops[j]):
				distinct = false
	_check(distinct, "the four presets have distinct sky colours")

	# outpost_17 must equal the look authored in Main.tscn (the scene is instantiated, never added to the tree).
	var packed := load(MAIN_SCENE) as PackedScene
	var main := packed.instantiate()
	var world_env := main.get_node("WorldEnvironment") as WorldEnvironment
	var sun := main.get_node("DirectionalLight3D") as DirectionalLight3D
	var env := world_env.environment
	var sky := env.sky.sky_material as ProceduralSkyMaterial
	var authored := {
		"sky_top": sky.sky_top_color, "sky_horizon": sky.sky_horizon_color,
		"ground_bottom": sky.ground_bottom_color, "ground_horizon": sky.ground_horizon_color,
		"ambient_color": env.ambient_light_color, "ambient_energy": env.ambient_light_energy,
		"ambient_sky_contribution": env.ambient_light_sky_contribution,
		"fog_color": env.fog_light_color, "fog_density": env.fog_density, "fog_sky_affect": env.fog_sky_affect,
		"tonemap_exposure": env.tonemap_exposure, "glow_enabled": env.glow_enabled,
		"sun_color": sun.light_color, "sun_energy": sun.light_energy,
		"sun_pitch": sun.rotation_degrees.x, "sun_yaw": sun.rotation_degrees.y,
		"shadow_distance": sun.directional_shadow_max_distance,
	}
	var diff := _dict_same(authored, (presets[&"outpost_17"] as EnvironmentPreset).values())
	_check(diff == "", "outpost_17 equals the Main.tscn look%s" % ("" if diff == "" else " (" + diff + ")"))
	main.free()

	# Quality scaling: lite (web and mobile) turns glow off and caps shadows; full keeps the preset.
	var heavy := (presets[&"dead_coast"] as EnvironmentPreset).duplicate() as EnvironmentPreset
	heavy.glow_enabled = true
	heavy.shadow_distance = 90.0
	var lite_values := EnvironmentPresets.effective_values(heavy, true)
	var full_values := EnvironmentPresets.effective_values(heavy, false)
	_check(lite_values["glow_enabled"] == false, "lite: glow is off")
	_check(float(lite_values["shadow_distance"]) <= EnvironmentPresets.LITE_SHADOW_WEB, "lite: shadow distance capped at %d m or less" % int(EnvironmentPresets.LITE_SHADOW_WEB))
	_check(full_values["glow_enabled"] == true and is_equal_approx(float(full_values["shadow_distance"]), 90.0), "full quality keeps the preset's glow and shadow distance")
	_check(_same(lite_values["fog_density"], heavy.fog_density), "lite keeps the authored fog density (fog stays readable)")

	# Readability: Blackwood is the darkest but must stay above a floor (formula in environment_presets.gd).
	var out_l := EnvironmentPresets.readability_estimate(presets[&"outpost_17"])
	var bw_l := EnvironmentPresets.readability_estimate(presets[&"blackwood"])
	var dc_l := EnvironmentPresets.readability_estimate(presets[&"dead_coast"])
	print("  info readability estimate: outpost_17 %.3f, dead_coast %.3f, blackwood %.3f, research_complex %.3f" % [
			out_l, dc_l, bw_l, EnvironmentPresets.readability_estimate(presets[&"research_complex"])])
	_check(bw_l >= 0.12, "blackwood readability estimate is at least 0.12 (%.3f)" % bw_l)
	_check(bw_l >= 0.45 * out_l, "blackwood is at least 45%% as bright as Outpost 17 (%.2f)" % (bw_l / out_l))
	_check(bw_l < out_l, "blackwood is still the darker, moodier region")
	_check(dc_l > out_l, "dead coast is brighter than Outpost 17 (warm, open)")


# --- apply, tween, restore -------------------------------------------------------

func _check_apply() -> void:
	# A neutral scene with Main.tscn's environment and sun (the same two nodes RegionManager leaves in place).
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	var world_env := main.get_node("WorldEnvironment")
	var sun := main.get_node("DirectionalLight3D")
	main.remove_child(world_env)
	main.remove_child(sun)
	main.free()
	root.add_child(world_env)
	root.add_child(sun)
	await _frames(2)

	var original := EnvironmentPresets.read_current(self)
	_check(original.size() == 17, "read_current returns all 17 values (%d)" % original.size())

	_check(EnvironmentPresets.apply(&"nope", 0.0, 0, self) == false, "applying an unknown preset returns false")
	_check(_dict_same(original, EnvironmentPresets.read_current(self)) == "", "an unknown preset changes nothing")

	_check(EnvironmentPresets.apply(&"dead_coast", 0.0, 0, self), "dead_coast applies immediately")
	var coast := EnvironmentPresets.read_current(self)
	_check(not _same(coast["sky_top"], original["sky_top"]) and not _same(coast["sun_energy"], original["sun_energy"]), "the look really changed")
	_check(sun.get_meta("lh_base_shadow_distance", -1.0) == 55.0 or is_equal_approx(float(sun.get_meta("lh_base_shadow_distance", -1.0)), 55.0), "the sun's authored shadow distance meta follows the preset (Settings scales from it)")

	_check(EnvironmentPresets.apply(&"outpost_17", 0.0, 0, self), "outpost_17 applies immediately")
	var back := EnvironmentPresets.read_current(self)
	var d := _dict_same(original, back)
	_check(d == "", "returning to outpost_17 restores the original values exactly%s" % ("" if d == "" else " (" + d + ")"))

	# A real tween: mid-way values lie strictly between, the end is exact, and nothing runs afterwards.
	EnvironmentPresets.apply(&"dead_coast", 0.4, 0, self)
	await create_timer(0.18).timeout
	var mid := EnvironmentPresets.read_current(self)
	var e_lo := minf(float(original["sun_energy"]), float(coast["sun_energy"]))
	var e_hi := maxf(float(original["sun_energy"]), float(coast["sun_energy"]))
	_check(float(mid["sun_energy"]) > e_lo + EPS and float(mid["sun_energy"]) < e_hi - EPS, "mid-tween sun energy is between the two presets (%.3f)" % float(mid["sun_energy"]))
	await create_timer(0.5).timeout
	var end := EnvironmentPresets.read_current(self)
	d = _dict_same(coast, end)
	_check(d == "", "the tween ends exactly on the preset%s" % ("" if d == "" else " (" + d + ")"))
	_check(EnvironmentPresets._tween == null or not EnvironmentPresets._tween.is_valid(), "no tween is left running after it finishes")
	await _frames(5)
	_check(_dict_same(end, EnvironmentPresets.read_current(self)) == "", "values stay put afterwards (no per-frame work)")

	# A new apply during a tween takes over without jumping back to a stale start.
	EnvironmentPresets.apply(&"blackwood", 0.4, 0, self)
	await create_timer(0.1).timeout
	EnvironmentPresets.apply(&"outpost_17", 0.0, 0, self)
	await create_timer(0.5).timeout
	_check(_dict_same(original, EnvironmentPresets.read_current(self)) == "", "interrupting a tween with an immediate apply leaves the new preset in place")

	# Region hook: RegionManager._apply_presets drives both the environment and the ambience.
	var manager := root.get_node_or_null("RegionManager")
	var audio := root.get_node_or_null("AudioManager")
	_check(manager != null and manager.has_method("_apply_presets"), "RegionManager has the preset hook")
	if manager != null:
		manager.call("_apply_presets", RegionStore.load_data(&"blackwood"))
		await create_timer(2.3).timeout
		var bw := (EnvironmentPresets.get_preset(&"blackwood") as EnvironmentPreset).values()
		var applied := EnvironmentPresets.read_current(self)
		var lite := EnvironmentPresets.is_lite()
		var expect := EnvironmentPresets.effective_values(EnvironmentPresets.get_preset(&"blackwood"), lite)
		d = _dict_same(expect, applied)
		_check(d == "", "entering Blackwood applies its preset through the region hook%s" % ("" if d == "" else " (" + d + ")"))
		if audio != null:
			_check(audio.ambience_state()["region"] == &"blackwood", "...and switches the ambience to blackwood")
		manager.call("_apply_presets", RegionStore.load_data(&"outpost_17"))
		await create_timer(2.3).timeout
		d = _dict_same(original, EnvironmentPresets.read_current(self))
		_check(d == "", "leaving Blackwood for Outpost 17 restores the original look%s" % ("" if d == "" else " (" + d + ")"))
	world_env.queue_free()
	sun.queue_free()
	await _frames(2)


# --- ambience crossfade ------------------------------------------------------------

func _gains(audio: Node) -> Array:
	return audio.ambience_state()["gains"]


func _check_crossfade() -> void:
	var audio := root.get_node_or_null("AudioManager")
	_check(audio != null, "AudioManager exists")
	if audio == null:
		return
	audio.set_region_ambience(&"outpost", 0.0)
	var s: Dictionary = audio.ambience_state()
	_check(s["region"] == &"outpost" and s["streams"][s["active_slot"]] == &"ambience_loop", "Outpost 17 keeps its original loop")
	_check(is_equal_approx(float(s["gains"][s["active_slot"]]), 1.0), "the active slot is at full ambience level")

	audio.set_region_ambience(&"dead_coast", 0.0)
	s = audio.ambience_state()
	_check(s["streams"][s["active_slot"]] == &"ambience_coast" and is_equal_approx(float(s["gains"][s["active_slot"]]), 1.0), "an instant change puts the coast loop on at full level")
	_check(s["streams"][1 - int(s["active_slot"])] == &"" and is_equal_approx(float(s["gains"][1 - int(s["active_slot"])]), 0.0), "...and frees the other slot")

	var before: Dictionary = audio.ambience_state()
	audio.set_region_ambience(&"dead_coast", 1.0)
	_check(audio.ambience_state()["streams"] == before["streams"] and audio.ambience_state()["gains"] == before["gains"], "asking for the current region again changes nothing")
	audio.set_region_ambience(&"mars", 1.0)
	audio.set_region_ambience(&"", 1.0)
	_check(audio.ambience_state()["streams"] == before["streams"] and audio.ambience_state()["gains"] == before["gains"], "unknown and empty names are ignored")

	# A real 0.5 s fade: sample every frame. Equal-power gains: both loops are never at full volume together.
	audio.set_region_ambience(&"blackwood", 0.5)
	var samples: Array = []
	var loudest_pair := 0.0
	var max_db := -1000.0
	var t_end := Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var g := _gains(audio)
		samples.append(g.duplicate())
		loudest_pair = maxf(loudest_pair, minf(float(g[0]), float(g[1])))
		max_db = maxf(max_db, maxf(audio._ambience.volume_db, audio._ambience_b.volume_db))
	_check(samples.size() >= 5, "the fade was sampled over several frames (%d)" % samples.size())
	_check(loudest_pair <= 0.75, "both loops are never loud together (the quieter one peaks at %.2f of full)" % loudest_pair)
	_check(max_db <= AudioScript.AMBIENCE_DB + 0.01, "no loop exceeds the normal ambience level (%.1f dB)" % max_db)
	s = audio.ambience_state()
	var active := int(s["active_slot"])
	_check(s["streams"][active] == &"ambience_jungle" and is_equal_approx(float(s["gains"][active]), 1.0), "after the fade the jungle loop is at full level")
	_check(is_equal_approx(float(s["gains"][1 - active]), 0.0) and s["streams"][1 - active] == &"", "the outgoing loop is silent and released")
	_check(not bool(s["fading"]), "no fade is left running")

	# An interrupted fade continues from the current volumes (no pop).
	audio.set_region_ambience(&"dead_coast", 0.6)
	await create_timer(0.2).timeout
	var mid := _gains(audio).duplicate()
	audio.set_region_ambience(&"research_complex", 0.6)
	var after := _gains(audio)
	_check(absf(float(mid[0]) - float(after[0])) < 0.0001 and absf(float(mid[1]) - float(after[1])) < 0.0001, "starting a new fade mid-fade keeps both volumes where they were")
	await create_timer(0.9).timeout
	s = audio.ambience_state()
	active = int(s["active_slot"])
	_check(s["streams"][active] == &"ambience_facility" and is_equal_approx(float(s["gains"][active]), 1.0) and is_equal_approx(float(s["gains"][1 - active]), 0.0), "the interrupted chain settles on the facility loop alone")

	# Lazy web load: a late install of the Outpost loop must not start it once another region is active.
	audio._install_ambience()
	_check(audio._slot_player(0).stream == null or audio._slot_streams[0] != &"ambience_loop", "a late lazy install does not revive the Outpost loop in a released slot")

	# Mute and master volume are bus-level and untouched by the crossfade.
	audio.set_muted(true)
	audio.set_region_ambience(&"outpost", 0.0)
	_check(AudioServer.is_bus_mute(0), "muting stays in force across a region change")
	audio.set_muted(false)
	_check(not AudioServer.is_bus_mute(0), "unmuting works afterwards")
	audio.set_region_ambience(&"outpost", 0.0)
	_check(audio.ambience_state()["region"] == &"outpost", "state ends back on Outpost 17")


# --- files and references -------------------------------------------------------------
# The project imports WAVs as QOA, so sample-level checks read the source files (16-bit mono PCM, 44-byte header).

func _raw_samples(name: String) -> PackedInt32Array:
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/%s.wav" % name)
	var out := PackedInt32Array()
	if bytes.size() <= 44:
		return out
	var n := (bytes.size() - 44) / 2
	out.resize(n)
	for i in n:
		out[i] = bytes.decode_s16(44 + i * 2)
	return out


func _stream(name: String) -> AudioStreamWAV:
	var path := "res://assets/audio/%s.wav" % name
	if not ResourceLoader.exists(path):
		return null
	return load(path) as AudioStreamWAV


func _check_files() -> void:
	for name in NEW_FILES:
		var wav := _stream(name)
		_check(wav != null and wav.get_length() > 0.5, "%s.wav exists and loads" % name)
	var expect_len := {"ambience_coast": 8.0, "ambience_jungle": 8.0, "ambience_facility": 6.0}
	for name in expect_len:
		var samples := _raw_samples(name)
		var n := samples.size()
		_check(n > 0 and absf(float(n) / 22050.0 - float(expect_len[name])) < 0.01, "%s lasts %.0f s" % [name, expect_len[name]])
		if n < 2:
			continue
		# Seam: the jump from the last sample to the first is about one ordinary sample step.
		var total := 0.0
		for i in range(1, n):
			total += absf(float(samples[i] - samples[i - 1]))
		var mean_step := total / float(n - 1)
		var jump := absf(float(samples[0] - samples[n - 1]))
		_check(jump <= 6.0 * mean_step + 50.0, "%s loops without a seam (jump %d, typical step %.0f)" % [name, int(jump), mean_step])
		var peak := 0
		for s in samples:
			peak = maxi(peak, absi(s))
		_check(peak <= int(0.55 * 32767.0) and peak > 4000, "%s peak is a quiet bed level (%d of 32767)" % [name, peak])
	for name in ["bird_flush", "metal_creak"]:
		var samples := _raw_samples(name)
		var peak := 0
		for s in samples:
			peak = maxi(peak, absi(s))
		_check(float(samples.size()) / 22050.0 > 0.5, "%s is longer than half a second" % name)
		_check(peak <= int(0.62 * 32767.0) and peak > 4000, "%s peak level is sane (%d)" % [name, peak])

	# Loop end: AudioManager must loop the whole file. The old `data.size() / 2` was only right for raw PCM.
	var audio := root.get_node_or_null("AudioManager")
	if audio != null:
		for name in ["ambience_loop", "music_loop", "ambience_coast", "ambience_jungle", "ambience_facility"]:
			var wav := _stream(name)
			var frames := _raw_samples(name).size()
			var end: int = audio._loop_end_frames(wav)
			_check(end == frames, "%s loop end is the full length: %d of %d frames (old formula: %d)" % [name, end, frames, wav.data.size() / 2])

	# Every reference resolves: SFX names, region ambience names, region data and presets.
	var missing: Array[String] = []
	for sfx in AudioScript.SFX_NAMES:
		if not ResourceLoader.exists("res://assets/audio/%s.wav" % String(sfx)):
			missing.append(String(sfx))
	for key in AudioScript.REGION_AMBIENCE:
		if not ResourceLoader.exists("res://assets/audio/%s.wav" % String(AudioScript.REGION_AMBIENCE[key])):
			missing.append(String(AudioScript.REGION_AMBIENCE[key]))
	_check(missing.is_empty(), "every SFX and region ambience name has a file (missing: %s)" % str(missing))
	var bad_regions: Array[String] = []
	for id in EnvironmentPresets.IDS:
		var data := load("res://resources/regions/%s.tres" % String(id)) as RegionData
		if data == null or not AudioScript.REGION_AMBIENCE.has(data.ambience):
			bad_regions.append(String(id))
		var preset_id: StringName = data.environment_preset if data != null and data.environment_preset != &"" else (data.id if data != null else &"")
		if EnvironmentPresets.get_preset(preset_id) == null:
			bad_regions.append(String(id) + ":preset")
	_check(bad_regions.is_empty(), "every region maps to an ambience loop and a preset (bad: %s)" % str(bad_regions))
	_check(EnvironmentPresets.get_preset(&"outpost") == EnvironmentPresets.get_preset(&"outpost_17"), "the legacy name `outpost` resolves to the outpost_17 preset")

	var total_bytes := 0
	var dir := DirAccess.open("res://assets/audio/")
	for f in dir.get_files():
		if f.ends_with(".wav"):
			total_bytes += FileAccess.get_file_as_bytes("res://assets/audio/" + f).size()
	print("  info total audio: %.2f MB" % (float(total_bytes) / 1048576.0))
	_check(total_bytes < 3 * 1048576, "all audio together stays under 3 MB (%.2f MB)" % (float(total_bytes) / 1048576.0))
