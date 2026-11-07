class_name ResearchComplexKit
extends RefCounted
## Geometry kit for one Research Complex area. Every static box becomes part of ONE vertex-coloured
## mesh (solid) and ONE unshaded vertex-coloured mesh (glow: lamps, screens, warning strips), so an
## area costs about two draw calls however many props it has. Solid boxes also add a collision shape
## to one StaticBody3D. Placeholder art: Milestone 13 swaps an area's kit for real models without
## touching the gameplay components.

const FLOOR_THICKNESS: float = 0.4

var root: Node3D
var _solid := SurfaceTool.new()
var _glow := SurfaceTool.new()
var _body: StaticBody3D
var _solid_count: int = 0
var _glow_count: int = 0
var shape_count: int = 0

static var _solid_material: StandardMaterial3D
static var _glow_material: StandardMaterial3D


func _init(parent: Node3D, area_name: String) -> void:
	root = Node3D.new()
	root.name = "Area_" + area_name
	parent.add_child(root)
	_solid.begin(Mesh.PRIMITIVE_TRIANGLES)
	_glow.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body = StaticBody3D.new()
	_body.name = "Collision"
	_body.collision_layer = 1
	root.add_child(_body)


## A box centred on `center`. `solid` adds a collider; `rich` false skips the visual (invisible blocker).
func box(center: Vector3, size: Vector3, color: Color, solid: bool = true) -> void:
	_add_box(_solid, center, size, color)
	_solid_count += 1
	if solid:
		blocker(center, size)


## A collision-only box (invisible).
func blocker(center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = center
	_body.add_child(shape)
	shape_count += 1


## An unshaded, never-solid coloured box (lamps, screens, hazard and floor stripes, signs).
func glow(center: Vector3, size: Vector3, color: Color) -> void:
	_add_box(_glow, center, size, color)
	_glow_count += 1


## A floor slab whose top is at y = `top`.
func floor_rect(center_xz: Vector2, size_xz: Vector2, top: float, color: Color) -> void:
	box(Vector3(center_xz.x, top - FLOOR_THICKNESS * 0.5, center_xz.y), Vector3(size_xz.x, FLOOR_THICKNESS, size_xz.y), color)


## A wall along the X axis (z fixed) from x0 to x1, with door or arch gaps: each gap is {"x": centre, "w": width}.
func wall_x(z: float, x0: float, x1: float, height: float, color: Color, gaps: Array = [], thick: float = 0.8, base_y: float = 0.0) -> void:
	for seg in _segments(minf(x0, x1), maxf(x0, x1), gaps, "x"):
		var length: float = seg.y - seg.x
		if length > 0.05:
			box(Vector3((seg.x + seg.y) * 0.5, base_y + height * 0.5, z), Vector3(length, height, thick), color)


## A wall along the Z axis (x fixed) from z0 to z1, with gaps {"z": centre, "w": width}.
func wall_z(x: float, z0: float, z1: float, height: float, color: Color, gaps: Array = [], thick: float = 0.8, base_y: float = 0.0) -> void:
	for seg in _segments(minf(z0, z1), maxf(z0, z1), gaps, "z"):
		var length: float = seg.y - seg.x
		if length > 0.05:
			box(Vector3(x, base_y + height * 0.5, (seg.x + seg.y) * 0.5), Vector3(thick, height, length), color)


## A text sign (one Label3D). Faces +Z by default; `yaw` turns it.
func text_sign(text: String, pos: Vector3, color: Color = Color(0.95, 0.85, 0.3), pixel: float = 0.012, yaw: float = 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 8
	label.shaded = false
	label.position = pos
	label.rotation.y = yaw
	root.add_child(label)
	return label


## A ceiling-mounted or free-standing omni lamp (one real light per call: keep these few).
func light(pos: Vector3, color: Color, energy: float, range_m: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = pos
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = range_m
	lamp.shadow_enabled = false
	root.add_child(lamp)


## Builds the two meshes. Call once, after the last box.
func finish() -> void:
	if _solid_materials() == null:
		return
	if _solid_count > 0:
		_attach(_solid, "Solid", _solid_material, "solid")
	if _glow_count > 0:
		_attach(_glow, "Glow", _glow_material, "glow")


func stats() -> Dictionary:
	return {"solid_boxes": _solid_count, "glow_boxes": _glow_count, "shapes": shape_count}


func _attach(tool: SurfaceTool, node_name: String, material: StandardMaterial3D, _kind: String) -> void:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = tool.commit()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)


func _solid_materials() -> StandardMaterial3D:
	if _solid_material == null:
		_solid_material = StandardMaterial3D.new()
		_solid_material.vertex_color_use_as_albedo = true
		_solid_material.roughness = 0.9
		_glow_material = StandardMaterial3D.new()
		_glow_material.vertex_color_use_as_albedo = true
		_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _solid_material


## Splits [lo, hi] around the gaps; returns Vector2(start, end) pieces.
static func _segments(lo: float, hi: float, gaps: Array, key: String) -> Array[Vector2]:
	var cuts: Array[Vector2] = []
	for gap in gaps:
		var centre: float = float((gap as Dictionary).get(key, 0.0))
		var half: float = float((gap as Dictionary).get("w", 4.0)) * 0.5
		cuts.append(Vector2(centre - half, centre + half))
	cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var out: Array[Vector2] = []
	var cursor := lo
	for cut in cuts:
		if cut.x > cursor:
			out.append(Vector2(cursor, minf(cut.x, hi)))
		cursor = maxf(cursor, cut.y)
	if cursor < hi:
		out.append(Vector2(cursor, hi))
	return out


static func _add_box(tool: SurfaceTool, c: Vector3, s: Vector3, color: Color) -> void:
	var h := s * 0.5
	var corners: Array[Vector3] = [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	# face: 4 corner indices (counter-clockwise seen from outside) and its normal
	var faces: Array = [
		[[4, 5, 6, 7], Vector3.BACK], [[1, 0, 3, 2], Vector3.FORWARD],
		[[5, 1, 2, 6], Vector3.RIGHT], [[0, 4, 7, 3], Vector3.LEFT],
		[[7, 6, 2, 3], Vector3.UP], [[0, 1, 5, 4], Vector3.DOWN],
	]
	for face in faces:
		var idx: Array = face[0]
		var n: Vector3 = face[1]
		var shade := color * (0.82 + 0.18 * maxf(n.y, 0.0)) if n != Vector3.DOWN else color * 0.6
		shade.a = color.a
		for tri in [[0, 2, 1], [0, 3, 2]]:  # Godot's front faces are clockwise
			for i in tri:
				tool.set_color(shade)
				tool.set_normal(n)
				tool.add_vertex(corners[idx[i]])
