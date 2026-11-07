class_name MapCanvas
extends Control
## Draws the world map: the island overview with the four regions, or a top-down schematic of one region.
## Presentation only: MapScreen hands it ready-made data (MapData decides what is shown) and it redraws
## only when told to (open, a signal, a pan or zoom), never per frame.

signal region_clicked(region_id: StringName)
signal view_changed

enum Mode { OVERVIEW, DETAIL }

const MARGIN: float = 28.0
const MIN_ZOOM: float = 0.6
const MAX_ZOOM: float = 4.0
const NODE_RADIUS: float = 22.0
## Stylised island outline, normalised 0..1 on the overview canvas.
const ISLAND: PackedVector2Array = [
	Vector2(0.06, 0.34), Vector2(0.12, 0.16), Vector2(0.30, 0.08), Vector2(0.50, 0.12), Vector2(0.68, 0.06),
	Vector2(0.88, 0.18), Vector2(0.95, 0.42), Vector2(0.90, 0.66), Vector2(0.78, 0.84), Vector2(0.56, 0.92),
	Vector2(0.34, 0.90), Vector2(0.16, 0.82), Vector2(0.08, 0.60),
]
const SEA: Color = Color(0.03, 0.07, 0.12, 1.0)
const LAND: Color = Color(0.11, 0.15, 0.13, 1.0)
const COAST: Color = Color(0.45, 0.62, 0.7, 0.8)
const AREA_FILL: Color = Color(0.17, 0.24, 0.31, 0.95)
const AREA_EDGE: Color = Color(0.62, 0.72, 0.84, 0.9)
const FOG_FILL: Color = Color(0.02, 0.03, 0.05, 0.92)
const FOG_EDGE: Color = Color(0.3, 0.34, 0.4, 0.7)
const LOCKED_COLOR: Color = Color(0.4, 0.42, 0.46, 1.0)
const PLAYER_COLOR: Color = Color(0.45, 0.9, 1.0)

var mode: int = Mode.OVERVIEW
var region_id: StringName = &""
var zoom: float = 1.0
var pan: Vector2 = Vector2.ZERO
# overview data: MapData.overview_entries()
var regions: Array[Dictionary] = []
# detail data
var extents: Rect2 = Rect2(-50.0, -50.0, 100.0, 100.0)
var landmarks: Array[Dictionary] = []
var exits: Array[Dictionary] = []      # {pos: Vector2, label: String, locked: bool}
var player_pos: Variant = null          # Vector2 (world x, z) or null
var player_dir: Vector2 = Vector2.UP
var objective_pos: Variant = null       # Vector2 or null
var objective_label: String = ""

var _dragging: bool = false


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP


func show_overview(entries: Array[Dictionary]) -> void:
	mode = Mode.OVERVIEW
	regions = entries
	queue_redraw()


func show_detail(id: StringName, map_extents: Rect2, items: Array[Dictionary], exit_items: Array[Dictionary]) -> void:
	mode = Mode.DETAIL
	region_id = id
	extents = map_extents
	landmarks = items
	exits = exit_items
	queue_redraw()


func set_markers(player: Variant, dir: Vector2, objective: Variant, label: String) -> void:
	player_pos = player
	player_dir = dir if dir.length() > 0.001 else Vector2.UP
	objective_pos = objective
	objective_label = label
	queue_redraw()


func reset_view() -> void:
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()
	view_changed.emit()


func zoom_by(factor: float) -> void:
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	queue_redraw()
	view_changed.emit()


func pan_by(delta: Vector2) -> void:
	var limit := size * 1.5
	pan = Vector2(clampf(pan.x + delta.x, -limit.x, limit.x), clampf(pan.y + delta.y, -limit.y, limit.y))
	queue_redraw()
	view_changed.emit()


## Canvas position of a world point in the current detail view.
func world_to_canvas(world: Vector2) -> Vector2:
	return MapData.to_canvas(world, extents, size, zoom, pan, MARGIN)


## Canvas position of an overview node (normalised 0..1 inside the margins).
func node_position(norm: Vector2) -> Vector2:
	var inner := Vector2(maxf(size.x - 2.0 * MARGIN, 1.0), maxf(size.y - 2.0 * MARGIN, 1.0))
	return Vector2(MARGIN, MARGIN) + norm * inner


func region_at(point: Vector2) -> StringName:
	for entry in regions:
		if node_position(entry["pos"]).distance_to(point) <= NODE_RADIUS * 1.6:
			return entry["id"]
	return &""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if mode == Mode.DETAIL and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.15)
		elif mode == Mode.DETAIL and button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.15)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed and mode == Mode.DETAIL
			if button.pressed and mode == Mode.OVERVIEW:
				var hit := region_at(button.position)
				if hit != &"":
					region_clicked.emit(hit)
	elif event is InputEventMouseMotion and _dragging:
		pan_by((event as InputEventMouseMotion).relative)


# --- drawing -------------------------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	if mode == Mode.OVERVIEW:
		_draw_overview()
	else:
		_draw_detail()


func _font() -> Font:
	return get_theme_default_font()


func _text(pos: Vector2, text: String, width: float, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font := _font()
	draw_string_outline(font, pos, text, align, width, font_size, 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, align, width, font_size, color)


func _draw_overview() -> void:
	var inner := PackedVector2Array()
	for p in ISLAND:
		inner.append(node_position(p))
	draw_colored_polygon(inner, LAND)
	var outline := inner.duplicate()
	outline.append(inner[0])
	draw_polyline(outline, COAST, 2.0, true)
	# the campaign route, in region order
	for i in range(regions.size() - 1):
		var a := node_position(regions[i]["pos"])
		var b := node_position(regions[i + 1]["pos"])
		var open: bool = not regions[i + 1]["locked"]
		var along := (b - a).normalized()
		# start and end at the circle edge, and keep clear of the label under each node
		var start := a + along * (NODE_RADIUS + 4.0)
		var end := b - along * (NODE_RADIUS + 4.0)
		draw_dashed_line(start, end, Color(0.8, 0.85, 0.9, 0.7) if open else LOCKED_COLOR, 2.0, 8.0)
	for entry in regions:
		_draw_region_node(entry)


func status_color(status: StringName, locked: bool) -> Color:
	if locked:
		return LOCKED_COLOR
	match status:
		MapData.STATUS_CURRENT:
			return HudTheme.GOLD
		MapData.STATUS_COMPLETED:
			return HudTheme.STAMINA
		MapData.STATUS_AVAILABLE:
			return HudTheme.ARMOR
	return HudTheme.TEXT_DIM


func _draw_region_node(entry: Dictionary) -> void:
	var center := node_position(entry["pos"])
	var color := status_color(entry["status"], entry["locked"])
	draw_circle(center, NODE_RADIUS, Color(0.05, 0.07, 0.1, 1.0))
	draw_arc(center, NODE_RADIUS, 0.0, TAU, 32, color, 3.0, true)
	if entry["status"] == MapData.STATUS_CURRENT:
		draw_arc(center, NODE_RADIUS + 6.0, 0.0, TAU, 32, HudTheme.GOLD, 2.0, true)
		draw_circle(center, 6.0, HudTheme.GOLD)
	elif entry["completed"]:
		draw_line(center + Vector2(-8, 0), center + Vector2(-2, 7), color, 3.0)
		draw_line(center + Vector2(-2, 7), center + Vector2(9, -7), color, 3.0)
	elif entry["locked"]:
		draw_rect(Rect2(center + Vector2(-7, -2), Vector2(14, 11)), color)
		draw_arc(center + Vector2(0, -2), 5.0, PI, TAU, 12, color, 2.0, true)
	var width := 340.0
	var label_pos := center + Vector2(-width * 0.5, NODE_RADIUS + 22.0)
	_text(label_pos, String(entry["name"]), width, 18, HudTheme.TEXT if not entry["locked"] else LOCKED_COLOR)
	var sub := ""
	match entry["status"]:
		MapData.STATUS_CURRENT:
			sub = "You are here"
		MapData.STATUS_COMPLETED:
			sub = "Completed"
		MapData.STATUS_AVAILABLE:
			sub = "Available"
	if entry["locked"]:
		sub = "LOCKED"
		if String(entry["hint"]) != "":
			sub += ": " + String(entry["hint"])
	_text(label_pos + Vector2(0, 18), sub, width, 14, color)


func _draw_detail() -> void:
	var ext := MapData.rect_to_canvas(extents, extents, size, zoom, pan, MARGIN)
	draw_rect(ext, Color(0.08, 0.11, 0.1, 1.0))
	draw_rect(ext, Color(1, 1, 1, 0.12), false, 1.0)
	for item in landmarks:
		_draw_landmark(item)
	for exit_item in exits:
		_draw_exit(exit_item)
	if objective_pos is Vector2:
		_draw_objective(world_to_canvas(objective_pos))
	if player_pos is Vector2:
		_draw_player(world_to_canvas(player_pos), player_dir)
	_draw_legend()


func _draw_landmark(item: Dictionary) -> void:
	var rect: Rect2 = item["rect"]
	var known: bool = item["discovered"]
	var kind: String = item["kind"]
	if rect.size == Vector2.ZERO:
		if not known:
			return  # a point of interest that has not been found stays off the map
		var p := world_to_canvas(rect.position)
		_draw_point_marker(p, kind)
		_text(p + Vector2(-80, 24), String(item["name"]), 160.0, 14, HudTheme.TEXT)
		return
	var canvas_rect := MapData.rect_to_canvas(rect, extents, size, zoom, pan, MARGIN)
	if known:
		draw_rect(canvas_rect, Color(0.3, 0.1, 0.1, 0.95) if kind == "arena" else AREA_FILL)
		draw_rect(canvas_rect, HudTheme.BOSS if kind == "arena" else AREA_EDGE, false, 2.0)
		if canvas_rect.size.x > 60.0 and canvas_rect.size.y > 22.0:
			# The name sits at the top of its area so a marker in the middle of the area never covers it.
			var fit := fit_name(String(item["name"]), canvas_rect.size.x - 8.0)
			var lines: Array = fit["lines"]
			for i in lines.size():
				_text(canvas_rect.position + Vector2(4.0, 16.0 + i * (int(fit["size"]) + 3.0)), String(lines[i]),
						canvas_rect.size.x - 8.0, int(fit["size"]), HudTheme.TEXT)
	else:
		draw_rect(canvas_rect, FOG_FILL)
		draw_rect(canvas_rect, FOG_EDGE, false, 1.0)
		if canvas_rect.size.x > 40.0 and canvas_rect.size.y > 22.0:
			_text(canvas_rect.position + Vector2(0, canvas_rect.size.y * 0.5 + 6.0), "?",
					canvas_rect.size.x, 18, Color(0.5, 0.55, 0.62))


func _draw_point_marker(p: Vector2, kind: String) -> void:
	var color := HudTheme.TELEPORT if kind == "checkpoint" else HudTheme.TEXT
	var points := PackedVector2Array([p + Vector2(0, -8), p + Vector2(8, 0), p + Vector2(0, 8), p + Vector2(-8, 0)])
	draw_colored_polygon(points, color)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(0, 0, 0, 0.8), 1.5)


func _draw_exit(item: Dictionary) -> void:
	var p := world_to_canvas(item["pos"])
	var locked: bool = item["locked"]
	var color := LOCKED_COLOR if locked else HudTheme.ARMOR
	var points := PackedVector2Array([p + Vector2(-9, 7), p + Vector2(9, 7), p + Vector2(0, -9)])
	draw_colored_polygon(points, color)
	var label := String(item["label"]) + (" (locked)" if locked else "")
	# Near the bottom edge the label goes above the marker so the legend strip never hides it.
	var below := p.y + 30.0 < size.y - MARGIN - 4.0
	_text(p + Vector2(-90.0, 26.0 if below else -16.0), label, 180.0, 14, color)


func _draw_objective(p: Vector2) -> void:
	var points := PackedVector2Array([p + Vector2(0, -11), p + Vector2(11, 0), p + Vector2(0, 11), p + Vector2(-11, 0)])
	draw_colored_polygon(points, HudTheme.GOLD)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(0, 0, 0, 0.9), 2.0)
	if objective_label != "":
		# beside the marker, below the area names (those sit at the top of their rects)
		_text(p + Vector2(16.0, 5.0), objective_label, 200.0, 14, HudTheme.GOLD, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_player(p: Vector2, dir: Vector2) -> void:
	var xform := Transform2D(dir.angle() + PI * 0.5, p)
	var points := PackedVector2Array([xform * Vector2(0, -11), xform * Vector2(8, 8), xform * Vector2(0, 4), xform * Vector2(-8, 8)])
	draw_colored_polygon(points, PLAYER_COLOR)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(0, 0, 0, 0.9), 2.0)


func _draw_legend() -> void:
	var y := size.y - MARGIN + 4.0
	draw_rect(Rect2(0, y - 6.0, size.x, MARGIN + 2.0), Color(0.02, 0.03, 0.05, 0.85))
	var x := 12.0
	var items: Array = [
		["You", PLAYER_COLOR], ["Objective", HudTheme.GOLD], ["Explored", AREA_EDGE],
		["Unexplored", FOG_EDGE], ["Exit", HudTheme.ARMOR],
	]
	for item in items:
		draw_rect(Rect2(Vector2(x, y + 2.0), Vector2(11, 11)), item[1])
		_text(Vector2(x + 16.0, y + 13.0), String(item[0]), 110.0, 13, HudTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT)
		x += 24.0 + 7.5 * String(item[0]).length() + 14.0


## Lines and font size that fit a name into `width`: one line, a smaller font, or two lines split at a space.
func fit_name(text: String, width: float) -> Dictionary:
	var font := _font()
	for size in [15, 13, 12]:
		if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			return {"lines": [text], "size": size}
	var words := text.split(" ")
	var best := text.length()
	var split_at := -1
	var running := 0
	for i in range(words.size() - 1):
		running += words[i].length() + (1 if i > 0 else 0)
		var imbalance := absi(running - (text.length() - running - 1))
		if imbalance < best:
			best = imbalance
			split_at = i
	if split_at < 0:
		return {"lines": [text], "size": 12}
	var first := " ".join(words.slice(0, split_at + 1))
	var second := " ".join(words.slice(split_at + 1))
	return {"lines": [first, second], "size": 12}
