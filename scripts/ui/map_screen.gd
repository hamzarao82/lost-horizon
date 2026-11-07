class_name MapScreen
extends RpgScreen
## World map: an island overview of the four regions (current, available, locked, completed) and a
## top-down schematic of the region the player is in (explored areas, fog over the rest, the player,
## the objective compass target and the exits). MapData decides what is shown, MapCanvas draws it.
## Redraws only on open, on a data signal or on a pan or zoom; nothing runs per frame while closed.

const PAN_STEP: float = 48.0
const ZOOM_STEP: float = 1.25
const STICK_DEADZONE: float = 0.25
const STICK_SPEED: float = 480.0

var detail_region: StringName = &""
## Returns {"target": Vector3 or null, "label": String}; tests replace it.
var objective_source: Callable = Callable(self, "_pointer_target")

var _canvas: MapCanvas
var _toolbar: HFlowContainer
var _overview_button: Button
var _detail_button: Button
var _wired: bool = false


func _init() -> void:
	super._init()
	title_text = "Map"


func _ready() -> void:
	super._ready()
	set_process(false)
	var world := get_node_or_null("/root/WorldState")
	if world != null:
		world.area_entered.connect(_on_area_entered)  # discovery is recorded whether or not the map is open


func canvas() -> MapCanvas:
	return _canvas


func toolbar() -> Control:
	return _toolbar


func is_overview() -> bool:
	return _canvas != null and _canvas.mode == MapCanvas.Mode.OVERVIEW


# --- what the map shows (pure data, used by tests and by refresh) ----------------------------

func overview_entries() -> Array[Dictionary]:
	return MapData.overview_entries()


func detail_entries() -> Array[Dictionary]:
	return MapData.load_for(_detail_id()).entries()


func detail_exits() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data := RegionStore.load_data(_detail_id())
	if data == null:
		return out
	for key in data.exit_points:
		var raw: Variant = data.exit_points[key]
		if not (raw is Dictionary):
			continue
		var pos3: Variant = raw.get("position", null)
		if not (pos3 is Vector3):
			continue
		var pos := Vector2((pos3 as Vector3).x, (pos3 as Vector3).z)
		if not data.map_extents.has_point(pos):
			continue
		var target := StringName(raw.get("target_region", &""))
		var target_data := RegionStore.load_data(target)
		out.append({
			"pos": pos,
			"label": "To %s" % (target_data.display_name if target_data != null else String(target)),
			"locked": not MapData.is_unlocked(target),
		})
	return out


func player_marker() -> Variant:
	var player := _player()
	if player == null:
		return null
	return Vector2(player.global_position.x, player.global_position.z)


func player_direction() -> Vector2:
	var player := _player()
	if player == null:
		return Vector2.UP
	var forward := -player.global_transform.basis.z
	var flat := Vector2(forward.x, forward.z)
	return flat.normalized() if flat.length() > 0.001 else Vector2.UP


## Objective marker in map coordinates, only for the region being shown (see MapData.objective_marker).
func objective_marker() -> Variant:
	var source: Dictionary = objective_source.call()
	return MapData.objective_marker(_detail_id(), MapData.current_region(), source.get("target", null))


# --- screen ------------------------------------------------------------------------------------

func open() -> void:
	detail_region = MapData.current_region()
	super.open()
	show_detail()
	set_process(true)


func close() -> void:
	set_process(false)
	super.close()


func show_overview() -> void:
	_canvas.show_overview(overview_entries())
	_canvas.reset_view()
	_update_buttons()
	var done := 0
	for entry in overview_entries():
		if entry["completed"]:
			done += 1
	set_status("%d of %d regions completed. Select a region for details." % [done, RegionStore.IDS.size()])


func show_detail() -> void:
	detail_region = MapData.current_region()
	var data := RegionStore.load_data(detail_region)
	var extents := data.map_extents if data != null else Rect2(-50, -50, 100, 100)
	_canvas.show_detail(detail_region, extents, detail_entries(), detail_exits())
	_canvas.set_markers(player_marker(), player_direction(), objective_marker(), String(objective_source.call().get("label", "")))
	_canvas.reset_view()
	_update_buttons()
	var map := MapData.load_for(detail_region)
	var total := map.landmarks.size()
	set_status("%s: %d of %d places explored." % [data.display_name if data else String(detail_region), map.discovered_count(), total])


func refresh() -> void:
	if _canvas == null:
		return
	var keep_zoom := _canvas.zoom
	var keep_pan := _canvas.pan
	if is_overview():
		_canvas.show_overview(overview_entries())
	else:
		show_detail()
		_canvas.zoom = keep_zoom
		_canvas.pan = keep_pan
		_canvas.queue_redraw()


func _build_content() -> void:
	_toolbar = HFlowContainer.new()
	_toolbar.add_theme_constant_override("h_separation", 8)
	_toolbar.add_theme_constant_override("v_separation", 8)
	content.add_child(_toolbar)
	_overview_button = RpgUi.button("Overview", show_overview, 120.0)
	_toolbar.add_child(_overview_button)
	_detail_button = RpgUi.button("Region", show_detail, 110.0)
	_toolbar.add_child(_detail_button)
	_toolbar.add_child(RpgUi.button("Zoom +", func() -> void: _canvas.zoom_by(ZOOM_STEP), 96.0))
	_toolbar.add_child(RpgUi.button("Zoom -", func() -> void: _canvas.zoom_by(1.0 / ZOOM_STEP), 96.0))
	_toolbar.add_child(RpgUi.button("<", func() -> void: _canvas.pan_by(Vector2(PAN_STEP, 0.0)), RpgUi.TOUCH_HEIGHT))
	_toolbar.add_child(RpgUi.button("^", func() -> void: _canvas.pan_by(Vector2(0.0, PAN_STEP)), RpgUi.TOUCH_HEIGHT))
	_toolbar.add_child(RpgUi.button("v", func() -> void: _canvas.pan_by(Vector2(0.0, -PAN_STEP)), RpgUi.TOUCH_HEIGHT))
	_toolbar.add_child(RpgUi.button(">", func() -> void: _canvas.pan_by(Vector2(-PAN_STEP, 0.0)), RpgUi.TOUCH_HEIGHT))
	_toolbar.add_child(RpgUi.button("Center", func() -> void: _canvas.reset_view(), 100.0))

	_canvas = MapCanvas.new()
	_canvas.custom_minimum_size = Vector2(0.0, 260.0)
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.region_clicked.connect(_on_region_clicked)
	content.add_child(_canvas)


func _connect_sources() -> void:
	if _wired:
		return
	_wired = true
	var world := get_node_or_null("/root/WorldState")
	if world != null:
		world.flag_changed.connect(_on_dirty)
	var regions := get_node_or_null("/root/RegionManager")
	if regions != null:
		regions.region_changed.connect(_on_dirty)
	var quests := get_node_or_null("/root/QuestManager")
	if quests != null:
		quests.tracker_changed.connect(_on_dirty)


func _on_dirty(_a: Variant = null, _b: Variant = null) -> void:
	if _open:
		refresh()


func _on_area_entered(id: StringName) -> void:
	MapData.mark_discovered(MapData.current_region(), id)


func _on_region_clicked(id: StringName) -> void:
	for entry in overview_entries():
		if entry["id"] == id:
			var text: String = "%s: %s." % [entry["name"], String(entry["status"]).capitalize()]
			if entry["locked"] and String(entry["hint"]) != "":
				text += " Requires: %s." % entry["hint"]
			set_status(text)
			return


func _update_buttons() -> void:
	_overview_button.disabled = is_overview()
	_detail_button.disabled = not is_overview()


func _process(delta: float) -> void:
	if not _open or is_overview():
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() > STICK_DEADZONE:
		_canvas.pan_by(-stick * STICK_SPEED * delta)


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_M:
		close()
		get_viewport().set_input_as_handled()
		return
	super._input(event)


func _detail_id() -> StringName:
	return detail_region if detail_region != &"" else MapData.current_region()


func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D if is_inside_tree() else null


func _pointer_target() -> Dictionary:
	var pointer := get_tree().root.find_child("ObjectivePointer", true, false) if is_inside_tree() else null
	if pointer == null:
		return {"target": null, "label": ""}
	return {"target": pointer.get("target"), "label": String(pointer.get("label"))}
