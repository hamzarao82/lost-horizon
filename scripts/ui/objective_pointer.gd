class_name ObjectivePointer
extends CanvasLayer
## A small compass arrow at the edge of the view pointing to where the CURRENT quest objective is,
## with the distance ("Radio 42 m"). Hidden when the objective has no place, or when the target is
## on screen and closer than 6 m. Placement avoids the HUD bands and the touch buttons.

const LABELS: Dictionary = {
	&"area_a_perimeter": "Perimeter", &"area_b_compound": "Compound", &"area_c_research": "Research wing",
	&"area_d_command": "Command", &"radio": "Radio", &"checkpoint_desk": "Checkpoint",
	&"military_terminal": "Terminal", &"security_panel": "Panel", &"log_missing_security": "Missing log",
	&"power_switch_a": "Switch A", &"power_switch_b": "Switch B", &"power_switch_c": "Switch C",
	&"card_reader_c": "Card reader", &"command_terminal": "Terminal",
}
const HIDE_WITHIN: float = 6.0
const REFRESH_SECONDS: float = 0.25
const SIZE: Vector2 = Vector2(84.0, 52.0)
const MIN_RADIUS: float = 140.0

var target: Variant = null        # Vector3 or null
var label: String = ""

var _control: Control
var _refresh: float = 0.0
var _screen_pos: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.UP
var _distance: float = 0.0
var _visible_now: bool = false


func _ready() -> void:
	layer = 49  # under the HUD (50), above the 3D view
	add_to_group("objective_pointer")
	_control = Control.new()
	_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control.draw.connect(_draw_pointer)
	add_child(_control)


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_SECONDS
		_resolve_target()
	_update_screen()


# --- what the pointer points at ----------------------------------------------

## The first unfinished, non-optional objective of the active quest (same rule as the HUD tracker).
func current_objective() -> ObjectiveData:
	var quests := get_node_or_null("/root/QuestManager")
	if quests == null:
		return null
	for quest_id in quests.active.keys():
		var quest: QuestData = quests.get_quest(quest_id)
		if quest == null:
			continue
		var state: Dictionary = quests.active[quest_id]
		for index in quest.objectives.size():
			var objective: ObjectiveData = quest.objectives[index]
			if not state["done"][index] and not objective.optional:
				return objective
	return null


func _resolve_target() -> void:
	target = null
	label = ""
	var objective := current_objective()
	if objective == null:
		return
	match objective.type:
		ObjectiveData.Type.ENTER_AREA:
			for area_id in objective.targets:
				# Aim at the real trigger volume when it exists (that is where "entering" happens),
				# otherwise at the middle of the area.
				var trigger := get_tree().root.find_child("Trigger_" + String(area_id), true, false) as Node3D
				if trigger != null:
					target = Vector3(trigger.global_position.x, 0.0, trigger.global_position.z)
					label = LABELS.get(StringName(area_id), "Area")
					return
				var rect := _area_rect(StringName(area_id))
				if rect.size != Vector2.ZERO:
					target = Vector3(rect.get_center().x, 0.0, rect.get_center().y)
					label = LABELS.get(StringName(area_id), "Area")
					return
		ObjectiveData.Type.INTERACT, ObjectiveData.Type.DISCOVER:
			for id in objective.targets:
				if _point_at_interactable(StringName(id)):
					return
		ObjectiveData.Type.KILL_COUNT:
			_point_at_nearest_enemy()
		ObjectiveData.Type.FLAG:
			_resolve_flag_target(objective)


func _resolve_flag_target(objective: ObjectiveData) -> void:
	for flag in objective.targets:
		match String(flag):
			"has_access_card":
				if not _point_at_pickup("Keycard", "Access card"):
					_point_at_nearest_enemy()
			"comms_power_on":
				_point_at_power_step()
			"next_location_unlocked":
				_point_at_interactable(&"military_terminal")
			_:
				continue
		return


func _point_at_power_step() -> void:
	var world := get_node_or_null("/root/WorldState")
	if world != null and not world.has_flag(&"panel_inspected"):
		_point_at_interactable(&"security_panel")
		return
	var puzzle := get_tree().get_first_node_in_group("sequence_puzzle")
	if puzzle != null and puzzle.data != null:
		var step: int = puzzle.current_step()
		if step < puzzle.data.order.size():
			_point_at_interactable(StringName(puzzle.data.order[step]))


func _point_at_interactable(id: StringName) -> bool:
	for node in get_tree().get_nodes_in_group("interactables"):
		var item := node as Interactable
		if item != null and item.interaction_id == id and item.is_available():
			target = item.global_position
			label = LABELS.get(id, String(id).capitalize())
			return true
	return false


func _point_at_pickup(class_name_to_find: String, text: String) -> bool:
	for node in get_tree().root.find_children("*", class_name_to_find, true, false):
		var spatial := node as Node3D
		if spatial != null:
			target = spatial.global_position
			label = text
			return true
	return false


func _point_at_nearest_enemy() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or (enemy.has_method("is_dead") and enemy.is_dead()):
			continue
		var d := player.global_position.distance_to(enemy.global_position) if player else 0.0
		if d < best:
			best = d
			target = enemy.global_position
			label = "Enemy"


func _area_rect(area_id: StringName) -> Rect2:
	var areas: Dictionary = Outpost17.AREAS
	if areas.has(area_id):
		return areas[area_id]["rect"]
	return Rect2()


# --- where it is drawn ---------------------------------------------------------

func _update_screen() -> void:
	var camera := get_viewport().get_camera_3d()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if target == null or camera == null or player == null:
		_set_visible(false)
		return
	var world_target: Vector3 = target
	var flat := Vector2(world_target.x - player.global_position.x, world_target.z - player.global_position.z)
	_distance = flat.length()
	var viewport := get_viewport().get_visible_rect().size
	var on_screen := not camera.is_position_behind(world_target) \
			and Rect2(Vector2(80.0, 80.0), viewport - Vector2(160.0, 160.0)).has_point(camera.unproject_position(world_target))
	if on_screen and _distance < HIDE_WITHIN:
		_set_visible(false)
		return
	var local := camera.global_transform.affine_inverse() * world_target
	_direction = Vector2(local.x, local.z)  # camera forward (-z) is screen up
	_screen_pos = place(_direction, viewport, TouchControls.touch_active)
	_set_visible(true)


func _set_visible(value: bool) -> void:
	_visible_now = value
	if _control != null:
		_control.visible = value
		_control.queue_redraw()


## Pure placement: where the pointer sits for a direction (screen y grows downward) so that it keeps off
## the HUD bands and the touch buttons. Public so a test can check it.
static func place(direction: Vector2, viewport: Vector2, touch: bool) -> Vector2:
	var center := viewport * 0.5
	var dir := direction.normalized() if direction.length() > 0.001 else Vector2.UP
	var pos := center + Vector2(dir.x * viewport.x * 0.34, dir.y * viewport.y * 0.30)
	var rects := avoid_rects(viewport, touch)
	for step in 40:
		var box := Rect2(pos - SIZE * 0.5, SIZE)
		var clear := true
		for rect in rects:
			if box.intersects(rect):
				clear = false
				break
		if clear or (pos - center).length() <= MIN_RADIUS:
			break
		pos = center + (pos - center) * 0.95  # slide toward the middle until clear
	return pos


## The screen areas the HUD uses, for a viewport size (matches the layout in hud.gd).
static func avoid_rects(viewport: Vector2, touch: bool) -> Array[Rect2]:
	var rects: Array[Rect2] = [
		Rect2(0.0, 80.0, 300.0, 110.0),                              # bars, teleport label
		Rect2(0.0, 190.0, 440.0, 100.0),                             # quest tracker
		Rect2(viewport.x - 400.0, 0.0, 400.0, 125.0),                # equipment panel
		Rect2(viewport.x * 0.5 - 300.0, 0.0, 600.0, 175.0),          # wave label, boss bar, banners
		Rect2(viewport.x * 0.5 - 380.0, viewport.y - 200.0, 760.0, 200.0),  # subtitles, toast, prompt
	]
	if touch:
		rects.append(Rect2(viewport.x - 440.0, viewport.y - 330.0, 440.0, 330.0))  # touch buttons
	return rects


func _draw_pointer() -> void:
	if not _visible_now:
		return
	var dir := _direction.normalized() if _direction.length() > 0.001 else Vector2.UP
	var side := Vector2(-dir.y, dir.x)
	var tip := _screen_pos + dir * 18.0
	var points := PackedVector2Array([tip, _screen_pos - dir * 10.0 + side * 13.0, _screen_pos - dir * 10.0 - side * 13.0])
	_control.draw_colored_polygon(points, Color(0.95, 0.8, 0.25, 0.92))
	_control.draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[0]]), Color(0.1, 0.08, 0.02, 0.95), 2.0)
	var font := ThemeDB.fallback_font
	var text := "%s %d m" % [label, roundi(_distance)]
	var text_pos := _screen_pos + Vector2(-70.0, 34.0 if dir.y < 0.5 else -26.0)
	_control.draw_string_outline(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16, 4, Color.BLACK)
	_control.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 16, Color(1.0, 0.95, 0.75))
