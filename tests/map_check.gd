extends SceneTree
## World map (headless): MapData rules, the screen's data, discovery, markers, the world-to-canvas
## transform, redraw-on-demand, layout at three sizes and the pause-menu hook.
## godot --headless --path . -s tests/map_check.gd

const PLAYER_SCENE: String = "res://scenes/player/Player.tscn"
const SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(800, 360)]
const OUTPOST: StringName = &"outpost_17"
const COAST: StringName = &"dead_coast"
const WOOD: StringName = &"blackwood"
const COMPLEX: StringName = &"research_complex"

var _failures: int = 0
var _checks: int = 0
var _world: Node
var _regions: Node


func _initialize() -> void:
	HitStop.enabled = false
	Player.require_mouse_capture = false
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _frames(count: int = 3) -> void:
	for i in count:
		await process_frame


func _reset_state() -> void:
	_world.reset()
	_regions.reset()
	_regions.current_region_id = OUTPOST


func _run() -> void:
	_world = root.get_node_or_null("WorldState")
	_regions = root.get_node_or_null("RegionManager")
	_check(_world != null and _regions != null, "WorldState and RegionManager autoloads exist")
	_reset_state()
	_test_resources()
	_test_statuses()
	_test_discovery()
	_test_markers_and_transform()
	_test_builders()
	await _test_dead_coast_screen()
	await _test_screen()
	await _test_layout()
	await _test_real_save()
	await _test_pause_hook()
	_reset_state()
	print("map_check: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


# --- resources -----------------------------------------------------------------------------------

func _test_resources() -> void:
	print("-- resources")
	var expected := {OUTPOST: 6, COAST: 7, WOOD: 7, COMPLEX: 6}
	for id in RegionStore.IDS:
		var map := MapData.load_for(id)
		var data := RegionStore.load_data(id)
		_check(map.region_id == id, "%s map resource loads with the right id" % id)
		_check(map.landmarks.size() == int(expected[id]), "%s has %d landmarks (%d)" % [id, expected[id], map.landmarks.size()])
		var ids: Dictionary = {}
		var inside := 0
		for entry in map.entries():
			ids[entry["id"]] = true
			if data.map_extents.encloses(entry["rect"]) or (entry["rect"].size == Vector2.ZERO and data.map_extents.has_point(entry["rect"].position)):
				inside += 1
		_check(ids.size() == map.landmarks.size(), "%s landmark ids are unique" % id)
		_check(inside == map.landmarks.size(), "%s landmarks lie inside the region extents (%d of %d)" % [id, inside, map.landmarks.size()])
		_check(map.overview_pos.x >= 0.0 and map.overview_pos.x <= 1.0 and map.overview_pos.y >= 0.0 and map.overview_pos.y <= 1.0,
				"%s overview position is normalised" % id)
	# Outpost 17 areas are the real ones from the level, not copies that can drift
	var by_id: Dictionary = {}
	for entry in MapData.load_for(OUTPOST).entries():
		by_id[entry["id"]] = entry
	for area_id in Outpost17.AREAS:
		var real: Rect2 = Outpost17.AREAS[area_id]["rect"]
		_check(by_id.has(String(area_id)) and by_id[String(area_id)]["rect"] == real, "Outpost 17 map area %s matches Outpost17.AREAS" % area_id)
	# malformed content never crashes the map
	var broken := MapData.new()
	broken.region_id = &"broken"
	broken.landmarks = [1, "x", {}, {"id": "a"}, null]
	var entries := broken.entries()
	_check(entries.size() == 2 and entries[1]["id"] == "a", "malformed landmark entries are skipped or defaulted (%d kept)" % entries.size())
	_check(MapData.load_for(&"no_such_region").landmarks.is_empty(), "an unknown region loads as an empty map")


# --- overview statuses ----------------------------------------------------------------------------

func _status_of(id: StringName) -> StringName:
	return MapData.region_status(id)


func _test_statuses() -> void:
	print("-- region status")
	_reset_state()
	_check(_status_of(OUTPOST) == MapData.STATUS_CURRENT, "the region the player is in is current")
	_check(_status_of(COAST) == MapData.STATUS_LOCKED, "Dead Coast starts locked")
	_check(_status_of(WOOD) == MapData.STATUS_LOCKED and _status_of(COMPLEX) == MapData.STATUS_LOCKED, "Blackwood and the Research Complex start locked")
	var entries := MapData.overview_entries()
	_check(entries.size() == 4, "the overview lists the four regions")
	var coast_entry: Dictionary = entries[1]
	_check(coast_entry["id"] == COAST and coast_entry["locked"] and String(coast_entry["hint"]) != "", "a locked region shows an unlock hint (%s)" % coast_entry["hint"])
	_check(String(entries[0]["hint"]) == "", "an open region shows no hint")
	# unlocking is the campaign's job (CampaignFlow sets `<region>_unlocked`); the map only reads it
	_world.set_flag(CampaignFlow.unlock_flag(COAST))
	_check(_status_of(COAST) == MapData.STATUS_AVAILABLE, "an unlocked Dead Coast is available")
	_check(MapData.completion_flags(COAST).has(CampaignFlow.mission_flag(COAST, 3)), "Dead Coast completion includes its mission 3 flag from the campaign chain")
	CampaignFlow.mark_mission_complete(COAST, 3)
	_check(_status_of(COAST) == MapData.STATUS_COMPLETED, "mission 3 of Dead Coast marks it completed")
	# every alias the campaign accepts for the next unlock also counts as completion on the map
	for region in [COAST, WOOD]:
		var next: StringName = RegionStore.IDS[RegionStore.IDS.find(region) + 1]
		for alias in CampaignFlow.CHAIN[next]["aliases"]:
			_reset_state()
			_world.set_flag(CampaignFlow.unlock_flag(region))
			_world.set_flag(alias)
			_check(_status_of(region) == MapData.STATUS_COMPLETED, "the alias %s completes %s" % [alias, region])
	_reset_state()
	_world.set_flag(CampaignFlow.unlock_flag(COMPLEX))
	_check(_status_of(COMPLEX) == MapData.STATUS_AVAILABLE, "the last region is available once unlocked")
	_world.set_flag(CampaignFlow.mission_flag(COMPLEX, 4))
	_check(_status_of(COMPLEX) == MapData.STATUS_COMPLETED, "mission 4 completes the last region")
	_reset_state()
	_world.set_flag(CampaignFlow.unlock_flag(WOOD))
	RegionFlags.set_flag(WOOD, &"region_complete")
	_check(_status_of(WOOD) == MapData.STATUS_COMPLETED, "`<region>_region_complete` also marks a region completed")
	_reset_state()
	_world.set_flag(&"mission_first_signal_complete")
	_regions.current_region_id = COAST
	_check(_status_of(OUTPOST) == MapData.STATUS_COMPLETED, "Outpost 17 reads as completed after The First Signal when the player is elsewhere")
	_check(_status_of(COAST) == MapData.STATUS_CURRENT and _status_of(OUTPOST) != MapData.STATUS_CURRENT,
			"the current marker follows the player's region")
	_world.set_flag(CampaignFlow.unlock_flag(COAST))
	CampaignFlow.mark_mission_complete(COAST, 3)
	_check(MapData.overview_entries()[1]["completed"] and MapData.overview_entries()[1]["status"] == MapData.STATUS_CURRENT,
			"a current region can also be completed (separate flag)")
	_reset_state()


# --- discovery -----------------------------------------------------------------------------------

func _entry(entries: Array[Dictionary], id: String) -> Dictionary:
	for e in entries:
		if e["id"] == id:
			return e
	return {}


func _test_discovery() -> void:
	print("-- discovery")
	_reset_state()
	var map := MapData.load_for(OUTPOST)
	var entries := map.entries()
	_check(_entry(entries, "area_a_perimeter")["discovered"], "the arrival area is known from the start")
	var compound := _entry(entries, "area_b_compound")
	_check(not compound["discovered"] and compound["name"] == MapData.FOG_NAME, "an unvisited area is fog with its name hidden")
	_check(not _entry(entries, "checkpoint_gate")["discovered"], "a point of interest stays hidden until its area is found")
	var before := map.discovered_count()
	MapData.mark_discovered(OUTPOST, &"area_b_compound")
	compound = _entry(map.entries(), "area_b_compound")
	_check(compound["discovered"] and compound["name"] == "Military Compound", "entering an area reveals it and its name")
	_check(map.discovered_count() == before + 1, "exactly one more area is discovered")
	_check(String(MapData.discovery_flag(OUTPOST, &"area_b_compound")) == "outpost_17_discovered_area_b_compound", "discovery uses the region flag convention")
	# a dead coast discovery does not reveal an Outpost 17 area
	MapData.mark_discovered(COAST, &"area_c_research")
	_check(not _entry(map.entries(), "area_c_research")["discovered"], "discovery flags are per region")
	# the flag survives a WorldState save round trip
	var saved: Dictionary = _world.to_dict()
	_world.reset()
	_check(not _entry(map.entries(), "area_b_compound")["discovered"], "a reset forgets discoveries")
	_world.from_dict(saved)
	_check(_entry(map.entries(), "area_b_compound")["discovered"], "discoveries persist through a WorldState save round trip")
	# Every flag the map can set must survive a REAL WorldState save/load: WorldState keeps only [a-z0-9_] ids
	# of at most 48 characters, so a dotted or long id would silently vanish (this was a real bug once).
	var all_flags: Array[String] = []
	for rid in RegionStore.IDS:
		var rmap := MapData.load_for(rid)
		for lm in rmap.landmarks:
			var flag := String(lm.get("flag", ""))
			if flag != "":
				all_flags.append(flag)
		for lm in rmap.entries():
			all_flags.append(String(MapData.discovery_flag(rid, StringName(lm["id"]))))
	_world.reset()
	for flag in all_flags:
		_world.set_flag(StringName(flag))
	var snapshot: Dictionary = _world.to_dict()
	_world.reset()
	_world.from_dict(snapshot)
	var lost: Array[String] = []
	for flag in all_flags:
		if not _world.has_flag(StringName(flag)):
			lost.append(flag)
	_check(lost.is_empty(), "all %d map flags (landmark and discovery) survive a real WorldState round trip (lost: %s)" % [all_flags.size(), str(lost)])
	_check(all_flags.all(func(f: String) -> bool: return f.length() <= 48), "every map flag is at most 48 characters")
	_world.reset()
	_world.from_dict({"flags": ["dead_coast.discovered.x", "outpost_17_discovered_area_b_compound"]})
	_check(_world.has_flag(&"outpost_17_discovered_area_b_compound") and not _world.has_flag(&"dead_coast.discovered.x"),
			"underscore flags load back and a dotted one is dropped (why the convention uses underscores)")
	_world.from_dict(saved)
	MapData.mark_discovered(OUTPOST, &"")
	MapData.mark_discovered(&"", &"x")
	_check(true, "empty ids are ignored without error")
	_reset_state()


# --- markers and transform -------------------------------------------------------------------------

func _test_markers_and_transform() -> void:
	print("-- markers and transform")
	var hall := Vector3(0.0, 0.0, -77.0)
	var m: Variant = MapData.objective_marker(OUTPOST, OUTPOST, hall)
	_check(m is Vector2 and (m as Vector2).is_equal_approx(Vector2(0.0, -77.0)), "an objective inside the current region is marked at (x, z)")
	_check(MapData.objective_marker(COAST, OUTPOST, hall) == null, "the objective is not drawn on another region's map")
	_check(MapData.objective_marker(OUTPOST, OUTPOST, Vector3(500.0, 0.0, 0.0)) == null, "a target outside the region extents is not drawn")
	_check(MapData.objective_marker(OUTPOST, OUTPOST, null) == null and MapData.objective_marker(OUTPOST, OUTPOST, "x") == null,
			"no target and a wrong type give no marker")
	var ext := Rect2(-45.0, -95.0, 90.0, 180.0)
	var canvas := Vector2(800.0, 400.0)
	var c := MapData.to_canvas(ext.get_center(), ext, canvas)
	_check(c.is_equal_approx(canvas * 0.5), "the extents centre is drawn at the canvas centre")
	var r := MapData.rect_to_canvas(ext, ext, canvas)
	_check(Rect2(Vector2.ZERO, canvas).encloses(r), "the whole region fits the canvas at zoom 1")
	_check(is_equal_approx(r.size.x / r.size.y, ext.size.x / ext.size.y), "the transform keeps the aspect ratio")
	_check(is_equal_approx(r.get_center().x, canvas.x * 0.5) and is_equal_approx(r.get_center().y, canvas.y * 0.5), "the region is centred")
	_check(MapData.to_canvas(Vector2(0.0, -80.0), ext, canvas).y < MapData.to_canvas(Vector2(0.0, 60.0), ext, canvas).y, "north (negative z) is up")
	var a1 := MapData.to_canvas(Vector2(10.0, 10.0), ext, canvas, 1.0)
	var a2 := MapData.to_canvas(Vector2(10.0, 10.0), ext, canvas, 2.0)
	var mid := canvas * 0.5
	_check((a2 - mid).is_equal_approx((a1 - mid) * 2.0), "doubling the zoom doubles distances from the centre")
	var panned := MapData.to_canvas(Vector2(10.0, 10.0), ext, canvas, 1.0, Vector2(30.0, -20.0))
	_check((panned - a1).is_equal_approx(Vector2(30.0, -20.0)), "pan shifts every point by the same offset")
	_check(MapData.base_scale(ext, Vector2(10.0, 10.0)) > 0.0, "a tiny canvas still gives a positive scale")


# --- the real levels ---------------------------------------------------------------------------------

func _rect_close(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) < 0.05 and a.size.distance_to(b.size) < 0.05


func _test_builders() -> void:
	print("-- real levels")
	var coast_map := MapData.load_for(COAST)
	var coast_entries: Dictionary = {}
	for e in coast_map.entries():
		coast_entries[e["id"]] = e
	_check(coast_map.landmarks.size() == DeadCoast.AREAS.size(), "the Dead Coast map has one landmark per builder area (%d)" % DeadCoast.AREAS.size())
	var builder := DeadCoast.new()
	var drift := 0
	for area in DeadCoast.AREAS:
		var id := String(area["id"])
		if not coast_entries.has(id) or not _rect_close(coast_entries[id]["rect"], builder._area_rect(area)):
			drift += 1
	builder.free()
	_check(drift == 0, "Dead Coast map rects equal the builder's (drift %d; regenerate with tools/gen_map_data.gd)" % drift)
	var wood_map := MapData.load_for(WOOD)
	var wood_entries: Dictionary = {}
	for e in wood_map.entries():
		wood_entries[e["id"]] = e
	_check(wood_map.landmarks.size() == Blackwood.AREAS.size(), "the Blackwood map has one landmark per builder area (%d)" % Blackwood.AREAS.size())
	drift = 0
	for area in Blackwood.AREAS:
		var id := String(area["area"])
		if not wood_entries.has(id) or not _rect_close(wood_entries[id]["rect"], Blackwood.area_rect(area)):
			drift += 1
	_check(drift == 0, "Blackwood map rects equal the builder's (drift %d)" % drift)
	# names: the fog hides them, so compare through the raw landmark data
	var names_ok := true
	for raw in coast_map.landmarks:
		for area in DeadCoast.AREAS:
			if String(area["id"]) == String(raw["id"]) and String(area["name"]) != String(raw["name"]):
				names_ok = false
	for raw in wood_map.landmarks:
		for area in Blackwood.AREAS:
			if String(area["area"]) == String(raw["id"]) and String(area["label"]) != String(raw["name"]):
				names_ok = false
	_check(names_ok, "area names equal the builders' names")
	# extents hold every area and exit of the real levels
	for id in [COAST, WOOD]:
		var data := RegionStore.load_data(id)
		var map := MapData.load_for(id)
		var outside := 0
		for e in map.entries():
			if not data.map_extents.encloses(e["rect"]):
				outside += 1
		for ex in map.exits:
			if not data.map_extents.has_point(ex["pos"]):
				outside += 1
		_check(outside == 0 and map.exits.size() == 2, "%s extents hold every area and both exits (%d outside)" % [id, outside])
	# flag names line up with the ids the builders emit through WorldState.area_entered
	_check(String(MapData.discovery_flag(COAST, &"dc_cove")) == "dead_coast_discovered_dc_cove", "Dead Coast discovery flag uses the builder's area id")
	_check(String(MapData.discovery_flag(WOOD, &"blackwood_research_perimeter")) == "blackwood_discovered_research_perimeter",
			"the region prefix is dropped so the Blackwood flag stays within 48 characters")
	var too_long := 0
	for area in DeadCoast.AREAS:
		if String(MapData.discovery_flag(COAST, area["id"])).length() > MapData.MAX_FLAG_LENGTH:
			too_long += 1
	for area in Blackwood.AREAS:
		if String(MapData.discovery_flag(WOOD, area["area"])).length() > MapData.MAX_FLAG_LENGTH:
			too_long += 1
	_check(too_long == 0, "every builder area id gives a discovery flag of at most 48 characters (%d too long)" % too_long)
	# an over-long flag is refused instead of being silently lost on save
	_world.reset()
	MapData.mark_discovered(WOOD, StringName("x".repeat(60)))
	_check(_world.to_dict()["flags"].is_empty(), "an area id that would make an unsaveable flag is not recorded")
	_world.reset()


func _test_dead_coast_screen() -> void:
	print("-- Dead Coast detail")
	_reset_state()
	_regions.current_region_id = COAST
	var screen := MapScreen.new()
	root.add_child(screen)
	await _frames(2)
	screen.open()
	await _frames(3)
	_check(screen.detail_region == COAST and screen.canvas().landmarks.size() == 7, "the region view shows the seven Dead Coast areas")
	var known := 0
	for e in screen.detail_entries():
		if e["discovered"]:
			known += 1
	_check(known == 1 and screen.detail_entries()[0]["name"] == "Wreckage Beach", "only the arrival area is known on arrival")
	_world.emit_area_entered(&"dc_cove")
	_check(_entry(screen.detail_entries(), "dc_cove")["name"] == "Smuggler's Cove", "entering the cove reveals it through the builder's area id")
	var exits := screen.detail_exits()
	_check(exits.size() == 2 and exits[0]["label"] == "To Outpost 17" and exits[1]["label"] == "To Blackwood", "the real exits are drawn with their targets")
	_check(not exits[0]["locked"] and exits[1]["locked"], "the way back is open and Blackwood is locked until it is unlocked")
	_world.set_flag(CampaignFlow.unlock_flag(WOOD))
	_check(not screen.detail_exits()[1]["locked"], "unlocking Blackwood opens its exit marker")
	var arrival := DeadCoastTerrain.ground(14.0, 10.0)
	var canvas_pos: Vector2 = screen.canvas().world_to_canvas(Vector2(arrival.x, arrival.z))
	_check(Rect2(Vector2.ZERO, screen.canvas().size).has_point(canvas_pos), "the arrival point lies on the canvas with the real extents")
	var far := DeadCoastTerrain.ground(14.0, -224.0)
	canvas_pos = screen.canvas().world_to_canvas(Vector2(far.x, far.z))
	_check(Rect2(Vector2.ZERO, screen.canvas().size).has_point(canvas_pos), "so does the far exit, 245 m away")
	screen.close()
	screen.queue_free()
	await _frames(2)
	_reset_state()


# --- a real save and load ----------------------------------------------------------------------------

func _clean_save(sm: Node) -> void:
	sm.delete_save()
	for suffix in [".bak", ".tmp"]:
		var path: String = sm.save_path() + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _test_real_save() -> void:
	print("-- real save and load")
	var sm := root.get_node_or_null("SaveManager")
	var safe: bool = sm != null and sm.test_mode
	_check(safe, "SaveManager is in test mode (per-process file, never the player's save)")
	if not safe:
		return
	_reset_state()
	_clean_save(sm)
	var player := load(PLAYER_SCENE).instantiate() as Player
	root.add_child(player)
	await _frames(4)
	MapData.mark_discovered(OUTPOST, &"area_b_compound")
	MapData.mark_discovered(COAST, &"dc_cove")
	MapData.mark_discovered(WOOD, &"blackwood_research_perimeter")
	CampaignFlow.mark_mission_complete(COAST, 3)
	_check(sm.save_game("manual"), "the game saves")
	_world.reset()
	_check(not _world.has_flag(MapData.discovery_flag(COAST, &"dc_cove")), "flags are gone after a reset")
	_check(sm.load_game(), "the save loads")
	await _frames(6)
	_check(_entry(MapData.load_for(OUTPOST).entries(), "area_b_compound")["discovered"], "an Outpost 17 discovery survives a real save and load")
	_check(_entry(MapData.load_for(COAST).entries(), "dc_cove")["discovered"], "a Dead Coast discovery survives")
	var long_flag := String(MapData.discovery_flag(WOOD, &"blackwood_research_perimeter"))
	_check(_entry(MapData.load_for(WOOD).entries(), "blackwood_research_perimeter")["discovered"], "the long Blackwood id survives (flag is %d characters)" % long_flag.length())
	_check(MapData.is_completed(COAST), "a completion flag survives, so Dead Coast still reads as completed")
	_check(not _entry(MapData.load_for(COAST).entries(), "dc_depot")["discovered"], "areas never visited stay fog after the reload")
	player.queue_free()
	await _frames(2)
	_clean_save(sm)
	sm.reset_runtime_state()
	_reset_state()


# --- the screen ----------------------------------------------------------------------------------

func _test_screen() -> void:
	print("-- screen")
	_reset_state()
	var player := load(PLAYER_SCENE).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(10.0, 0.0, -20.0)
	player.rotation_degrees.y = 90.0
	await _frames(3)
	var screen := MapScreen.new()
	root.add_child(screen)
	await _frames(2)
	_check(not screen.is_open(), "the map starts closed")
	_check(screen.canvas() != null and screen.toolbar() != null, "canvas and toolbar exist")
	var pm: Variant = screen.player_marker()
	_check(pm is Vector2 and (pm as Vector2).is_equal_approx(Vector2(10.0, -20.0)), "the player marker is the player's (x, z)")
	var dir := screen.player_direction()
	_check(dir.is_equal_approx(Vector2(-1.0, 0.0)), "the facing arrow follows the player's yaw (%s)" % str(dir))
	screen.objective_source = func() -> Dictionary: return {"target": Vector3(0.0, 0.0, -46.0), "label": "Research Wing"}
	_check((screen.objective_marker() as Vector2).is_equal_approx(Vector2(0.0, -46.0)), "the objective marker shows for the current region")
	# discovery through the real WorldState signal
	_check(not _entry(screen.detail_entries(), "area_c_research")["discovered"], "the research area starts unexplored")
	_world.emit_area_entered(&"area_c_research")
	_check(_entry(screen.detail_entries(), "area_c_research")["discovered"], "WorldState.area_entered reveals the area on the map")
	screen.open()
	await _frames(3)
	_check(screen.is_open() and paused, "opening the map pauses the game")
	_check(not screen.is_overview() and screen.detail_region == OUTPOST, "it opens on the current region")
	var detail_count := screen.canvas().landmarks.size()
	_check(detail_count == 6, "the canvas holds the Outpost 17 landmarks (%d)" % detail_count)
	_check(screen.canvas().exits.size() == 1 and String(screen.canvas().exits[0]["label"]) == "To Dead Coast" and screen.canvas().exits[0]["locked"],
			"the exit to Dead Coast is drawn and locked")
	_check(screen.canvas().player_pos is Vector2 and screen.canvas().objective_pos is Vector2, "player and objective markers reach the canvas")
	_check(String(screen.status_text()).contains("places explored"), "the status line reports exploration (%s)" % screen.status_text())
	var inside := Rect2(Vector2.ZERO, screen.canvas().size).has_point(screen.canvas().world_to_canvas(pm))
	_check(inside, "the player marker lands inside the canvas")
	# switching levels
	screen.show_overview()
	await _frames(2)
	_check(screen.is_overview() and screen.canvas().regions.size() == 4, "the overview shows four regions")
	_check(screen.canvas().region_at(screen.canvas().node_position(Vector2(0.3, 0.66))) == OUTPOST, "clicking the Outpost 17 node finds it")
	screen.canvas().region_clicked.emit(COAST)
	_check(String(screen.status_text()).contains("Locked") and String(screen.status_text()).contains("Requires"),
			"selecting a locked region explains how to unlock it (%s)" % screen.status_text())
	screen.show_detail()
	_check(not screen.is_overview(), "back to the region view")
	# zoom and pan limits
	for i in 30:
		screen.canvas().zoom_by(2.0)
	_check(is_equal_approx(screen.canvas().zoom, MapCanvas.MAX_ZOOM), "zoom is capped at the maximum")
	for i in 30:
		screen.canvas().zoom_by(0.5)
	_check(is_equal_approx(screen.canvas().zoom, MapCanvas.MIN_ZOOM), "zoom is capped at the minimum")
	for i in 60:
		screen.canvas().pan_by(Vector2(500.0, 500.0))
	_check(absf(screen.canvas().pan.x) <= screen.canvas().size.x * 1.5 + 0.1, "pan is limited")
	screen.canvas().reset_view()
	_check(screen.canvas().pan == Vector2.ZERO and screen.canvas().zoom == 1.0, "Center resets pan and zoom")
	# redraw only on demand
	await _frames(4)
	var draws := [0]
	var counter := func() -> void: draws[0] += 1
	screen.canvas().draw.connect(counter)
	await _frames(30)
	_check(draws[0] == 0, "an idle open map is not redrawn every frame (%d draws in 30 frames)" % draws[0])
	_world.set_flag(&"some_flag")
	await _frames(3)
	_check(draws[0] >= 1, "a data signal redraws it")
	screen.canvas().draw.disconnect(counter)
	# closing restores the game
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	screen._input(key)
	await _frames(2)
	_check(not screen.is_open() and not paused, "pressing M closes the map and unpauses")
	screen.queue_free()
	player.queue_free()
	await _frames(2)
	_reset_state()


# --- layout --------------------------------------------------------------------------------------

func _all_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(child)
		_all_buttons(child, out)


func _test_layout() -> void:
	print("-- layout")
	_reset_state()
	var player := load(PLAYER_SCENE).instantiate() as Player
	root.add_child(player)
	await _frames(2)
	var screen := MapScreen.new()
	root.add_child(screen)
	await _frames(2)
	var scale_mode := root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	for size in SIZES:
		root.size = size
		await _frames(3)
		for overview in [false, true]:
			screen.open()
			await _frames(2)
			if overview:
				screen.show_overview()
			await _frames(3)
			var name := "%dx%d %s" % [size.x, size.y, "overview" if overview else "region"]
			var panel := screen.root_control().get_child(1).get_child(0) as Control
			var view := Rect2(Vector2.ZERO, Vector2(size))
			_check(view.encloses(panel.get_global_rect().grow(-0.5)), "%s: panel fits the screen" % name)
			var buttons: Array[Button] = []
			_all_buttons(screen.root_control(), buttons)
			var short := 0
			for button in buttons:
				if button.is_visible_in_tree() and button.size.y > 0.0 and button.get_global_rect().size.y < RpgUi.TOUCH_HEIGHT - 0.5:
					short += 1
			_check(short == 0, "%s: all buttons are at least 56 px tall (%d short)" % [name, short])
			var tool_buttons: Array[Button] = []
			for child in screen.toolbar().get_children():
				if child is Button:
					tool_buttons.append(child)
			var overlaps := 0
			for a in tool_buttons.size():
				for b in range(a + 1, tool_buttons.size()):
					if tool_buttons[a].get_global_rect().grow(-1.0).intersects(tool_buttons[b].get_global_rect().grow(-1.0)):
						overlaps += 1
			_check(overlaps == 0, "%s: toolbar buttons never overlap (%d)" % [name, overlaps])
			var canvas_rect := screen.canvas().get_global_rect()
			_check(canvas_rect.size.x > 300.0 and canvas_rect.size.y >= 150.0, "%s: the map canvas is usable (%dx%d)" % [name, canvas_rect.size.x, canvas_rect.size.y])
			_check(not screen.toolbar().get_global_rect().intersects(canvas_rect.grow(-1.0)), "%s: toolbar and canvas do not overlap" % name)
			screen.close()
			await _frames(2)
	root.size = SIZES[0]
	root.content_scale_mode = scale_mode
	screen.queue_free()
	player.queue_free()
	await _frames(2)
	_reset_state()


# --- pause menu hook ------------------------------------------------------------------------------

func _test_pause_hook() -> void:
	print("-- pause menu")
	_reset_state()
	var main := (load("res://scenes/main/Main.tscn") as PackedScene).instantiate()
	var wm := main.get_node_or_null("WaveManager")
	if wm:
		wm.autostart = false
	root.add_child(main)
	await _frames(4)
	var menu := main.get_node_or_null("PauseMenu") as PauseMenu
	_check(menu != null, "Main has a PauseMenu")
	if menu != null:
		var page: VBoxContainer = menu.get("_main_page")
		var labels: Array[String] = []
		for child in page.get_children():
			if child is Button:
				labels.append((child as Button).text)
		_check(labels.has("Map"), "the pause menu has a Map button")
		var map_screen: MapScreen = menu.get("_map_screen")
		_check(map_screen != null and not map_screen.is_open(), "the pause menu owns a closed map screen")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_M
		key.pressed = true
		menu._unhandled_input(key)
		await _frames(3)
		_check(map_screen.is_open() and paused, "pressing M in play opens the map")
		_check(not map_screen.is_overview() and map_screen.detail_region == MapData.current_region(), "it shows the player's region")
		map_screen.close()
		menu.close()
		await _frames(2)
		_check(not paused, "closing everything unpauses the game")
	main.queue_free()
	await _frames(3)
	_reset_state()
