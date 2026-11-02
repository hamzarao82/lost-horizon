class_name ArenaDecor
extends Node3D
## Builds the island dressing around the test arena (Dead Coast beach + Outpost 17) at load.
## Everything is generated in code: a handful of merged, vertex-coloured meshes plus a water plane
## and a few cloud sprites, so the whole thing costs about four draw calls and no per-frame work
## beyond a water UV scroll and slow cloud drift. No decor has collision.

const SEED: int = 20261101
const TEX_SIZE: int = 128
const SEA_LEVEL: float = -1.0
const BEACH_START_Z: float = 78.0  # flat sand to here (the walkable beach), then it slopes down to the sea
const EDGE_DIST: float = 130.0     # island shore on the other three sides
const QUALITY_LOW: int = 0         # matches Settings.Quality
const QUALITY_MEDIUM: int = 1
const QUALITY_HIGH: int = 2

const SAND_LIGHT: Color = Color(0.80, 0.68, 0.48)
const SAND_DARK: Color = Color(0.62, 0.50, 0.35)
const WET_SAND: Color = Color(0.42, 0.34, 0.25)
const JUNGLE: Color = Color(0.36, 0.45, 0.24)
const WOOD: Color = Color(0.44, 0.31, 0.2)
const WOOD_DARK: Color = Color(0.3, 0.21, 0.14)
const CANVAS: Color = Color(0.82, 0.78, 0.66)
const KHAKI: Color = Color(0.58, 0.54, 0.38)
const OLIVE: Color = Color(0.32, 0.38, 0.27)
const RUST: Color = Color(0.5, 0.26, 0.17)
const STONE: Color = Color(0.36, 0.33, 0.30)

const METAL_SHADER: String = """
shader_type spatial;
// Corrugated painted metal: ribs along rib_dir, darker frame at the edges of the box.
uniform vec4 base_color : source_color = vec4(0.65, 0.15, 0.1, 1.0);
uniform vec3 half_extents = vec3(2.0, 1.0, 2.0);
uniform vec2 rib_dir = vec2(28.0, 28.0);
varying vec3 lpos;
void vertex() { lpos = VERTEX; }
void fragment() {
	float rib = 0.5 + 0.5 * sin(dot(lpos.xz, rib_dir));
	vec3 rel = abs(lpos) / half_extents;
	float edge = max(min(rel.x, rel.y), min(max(rel.x, rel.y), rel.z));  // median: near an edge of this face
	float frame = smoothstep(0.93, 0.985, edge);
	vec3 col = base_color.rgb * (0.68 + 0.32 * rib);
	col = mix(col, base_color.rgb * 0.42, frame);
	ALBEDO = col;
	ROUGHNESS = 0.7;
	METALLIC = 0.15;
}
"""

const WATER_SHADER: String = """
shader_type spatial;
// Flat sea: two scrolling noise layers blended between deep and shallow colour. Compatibility-safe.
uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 deep_color : source_color = vec4(0.07, 0.30, 0.40, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.30, 0.68, 0.70, 1.0);
uniform float speed = 0.012;
uniform float tiling = 140.0;
void fragment() {
	vec2 uv = UV * tiling;
	float t = TIME * speed;
	float a = texture(noise_tex, uv + vec2(t, t * 0.6)).r;
	float b = texture(noise_tex, uv * 0.63 - vec2(t * 0.8, -t)).r;
	float n = (a + b) * 0.5;
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.35, 0.68, n));
	ROUGHNESS = 0.22;
	SPECULAR = 0.8;
}
"""

signal build_finished

## When true, or under a headless display, the whole decor is built inside _ready() in a single frame
## (the pre-boot-screen behaviour). Otherwise it is built a stage per frame so Main never freezes.
static var build_synchronously: bool = false
## Tests only: build in stages even under the headless display (which otherwise forces sync mode).
static var force_staged: bool = false
## Benchmarks and tests: false forces the old code-built primitive decor instead of the modular kit.
static var allow_kit: bool = true

@export var quality_low: bool = false

var quality_level: int = QUALITY_HIGH
## True when the modular kit (assets/environments/kit) was used; false when a GLB was missing and the
## code-built primitive decor was used instead.
var kit_active: bool = false
var _kit_batches: Dictionary = {}
## Milliseconds spent in each stage of the most recent build (for docs/LOADING.md and the boot report).
var stage_ms: Array[float] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _built_level: int = -1
var _generated: Array[Node] = []
var _sand_tex: ImageTexture
var _rock_tex: ImageTexture
var _water_noise: ImageTexture
var _cloud_tex: GradientTexture2D
var _water_material: ShaderMaterial
var _clouds: Node3D
var _build_serial: int = 0
var _building: bool = false
var _stage_mark: int = 0


# --- builder -----------------------------------------------------------------

class Builder:
	extends RefCounted
	var st: SurfaceTool = SurfaceTool.new()
	var uv_scale: float = 0.0
	var tris: int = 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func _vertex(p: Vector3, n: Vector3, c: Color) -> void:
		st.set_normal(n)
		st.set_color(c)
		if uv_scale > 0.0:
			st.set_uv(Vector2(p.x, p.z) * uv_scale)
		st.add_vertex(p)

	## Winding is fixed up so the face always points along n (Godot front faces are clockwise).
	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		if (c - a).cross(b - a).dot(n) < 0.0:
			var tp := b
			b = c
			c = tp
			var tc := cb
			cb = cc
			cc = tc
		_vertex(a, n, ca)
		_vertex(b, n, cb)
		_vertex(c, n, cc)
		tris += 1

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, c_ab: Color, c_cd: Color = Color.TRANSPARENT) -> void:
		var top := c_ab if c_cd == Color.TRANSPARENT else c_cd
		tri(a, b, c, n, c_ab, c_ab, top)
		tri(a, c, d, n, c_ab, top, top)

	func box(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY) -> void:
		var half := size * 0.5
		var h: Array[float] = [half.x, half.y, half.z]
		var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
		for i in 3:
			var u: Vector3 = axes[(i + 1) % 3]
			var v: Vector3 = axes[(i + 2) % 3]
			var hu: float = h[(i + 1) % 3]
			var hv: float = h[(i + 2) % 3]
			for s in [-1.0, 1.0]:
				var n: Vector3 = axes[i] * float(s)
				var c0: Vector3 = n * h[i]
				var p0 := center + basis * (c0 - u * hu - v * hv)
				var p1 := center + basis * (c0 + u * hu - v * hv)
				var p2 := center + basis * (c0 + u * hu + v * hv)
				var p3 := center + basis * (c0 - u * hu + v * hv)
				quad(p0, p1, p2, p3, (basis * n).normalized(), color)

	## Frustum (or cone when r_top == 0) standing on `base`, axis along basis.y.
	func prism(base: Vector3, r_bottom: float, r_top: float, height: float, sides: int,
			color: Color, basis: Basis = Basis.IDENTITY, top_color: Color = Color.TRANSPARENT) -> void:
		var tcol := color if top_color == Color.TRANSPARENT else top_color
		var slope := (r_bottom - r_top) / maxf(height, 0.001)
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var mid := (a0 + a1) * 0.5
			var b0 := base + basis * Vector3(cos(a0) * r_bottom, 0.0, sin(a0) * r_bottom)
			var b1 := base + basis * Vector3(cos(a1) * r_bottom, 0.0, sin(a1) * r_bottom)
			var t0 := base + basis * Vector3(cos(a0) * r_top, height, sin(a0) * r_top)
			var t1 := base + basis * Vector3(cos(a1) * r_top, height, sin(a1) * r_top)
			var n := (basis * Vector3(cos(mid), slope, sin(mid))).normalized()
			quad(b0, b1, t1, t0, n, color, tcol)
			if r_top > 0.0:
				tri(t0, t1, base + basis * Vector3(0.0, height, 0.0), (basis * Vector3.UP).normalized(), tcol, tcol, tcol)

	## One palm leaf: widens to mid-length, then droops to a point. Drawn from both sides.
	func frond(base: Vector3, dir: Vector3, length: float, width: float, droop: float, c0: Color, c1: Color) -> void:
		var side := dir.cross(Vector3.UP).normalized()
		var mid := base + dir * length * 0.5 + Vector3.UP * length * 0.14
		var tip := base + dir * length + Vector3.DOWN * droop
		var bl := base - side * width * 0.12
		var br := base + side * width * 0.12
		var ml := mid - side * width * 0.5
		var mr := mid + side * width * 0.5
		for n in [Vector3.UP, Vector3.DOWN]:
			tri(bl, br, mr, n, c0, c0, c1)
			tri(bl, mr, ml, n, c0, c1, c1)
			tri(ml, mr, tip, n, c1, c1, c1)

	func finish() -> ArrayMesh:
		return st.commit()


# --- lifecycle ---------------------------------------------------------------

func _ready() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings:
		var level: Variant = settings.get("quality")
		if level != null:
			quality_level = int(level)
		if settings.has_signal("changed"):
			settings.connect("changed", _on_settings_changed)
	elif quality_low:
		quality_level = QUALITY_LOW
	_build()  # staged: returns at its first yield unless building synchronously


func set_quality(level: int) -> void:
	quality_level = level
	quality_low = level == QUALITY_LOW
	if is_inside_tree() and level != _built_level:
		_build()


func _on_settings_changed() -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings:
		var level: Variant = settings.get("quality")
		if level != null:
			set_quality(int(level))


func _process(delta: float) -> void:
	if _clouds:
		_clouds.rotation.y += delta * 0.004


func _hide_placeholder_visuals() -> void:
	var floor_mesh := get_node_or_null("../Floor/MeshInstance3D") as MeshInstance3D
	if floor_mesh:
		floor_mesh.visible = false
	var south := get_node_or_null("../WallS/MeshInstance3D") as MeshInstance3D
	if south:
		south.visible = false  # the sea is visible over the south edge; a rope fence replaces it


## True once every stage of the current build has run (the Boot screen waits for this).
func is_built() -> bool:
	return not _building and _built_level == quality_level


func _sync_mode() -> bool:
	if force_staged:
		return false
	return build_synchronously or DisplayServer.get_name() == "headless"


## Marks a stage boundary and, unless building synchronously, yields one frame so the frame that ran
## the stage can present. Returns true if this build was superseded or the node left the tree.
func _next_stage(serial: int) -> bool:
	var now := Time.get_ticks_usec()
	stage_ms.append((now - _stage_mark) / 1000.0)
	if not _sync_mode() and is_inside_tree():
		await get_tree().process_frame
	_stage_mark = Time.get_ticks_usec()
	return serial != _build_serial or not is_inside_tree()


func _build() -> void:
	_build_serial += 1
	var serial := _build_serial
	_building = true
	stage_ms.clear()
	_stage_mark = Time.get_ticks_usec()
	for node in _generated:
		if is_instance_valid(node):
			if node.get_parent() == self:
				remove_child(node)  # free the name now so the rebuilt nodes keep theirs
			node.queue_free()
	_generated.clear()
	_kit_batches.clear()
	_clouds = null
	set_process(false)
	_built_level = quality_level
	_rng.seed = SEED

	# Stages are sized to roughly a frame each; see docs/LOADING.md for the measured split.
	if await _make_textures(serial):
		return
	_style_obstacles()
	_add_terrain()
	_hide_placeholder_visuals()  # only now: until the sand exists the plain floor stays visible
	if await _next_stage(serial):
		return
	_add_water()
	if await _next_stage(serial):
		return
	if await _add_props(serial):
		return
	if quality_level != QUALITY_LOW:
		_add_clouds()
	set_process(_clouds != null)
	await _next_stage(serial)
	if serial != _build_serial:
		return
	_building = false
	build_finished.emit()


func _track(node: Node) -> void:
	add_child(node)
	_generated.append(node)


# --- textures and materials --------------------------------------------------

## One texture per stage (each costs ~25 ms on an integrated GPU laptop). Textures survive rebuilds.
## Returns true if the build was superseded part-way.
func _make_textures(serial: int) -> bool:
	if _sand_tex:
		return false
	_sand_tex = _noise_texture(11, 0.05, SAND_DARK, SAND_LIGHT, 0.08)
	if await _next_stage(serial):
		return true
	_rock_tex = _noise_texture(23, 0.09, Color(0.38, 0.35, 0.32), Color(0.66, 0.62, 0.56), 0.04)
	if await _next_stage(serial):
		return true
	_water_noise = _noise_texture(37, 0.04, Color(0.0, 0.0, 0.0), Color(1.0, 1.0, 1.0), 0.0)
	_make_cloud_texture()
	return await _next_stage(serial)


func _make_cloud_texture() -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 0.93, 0.84, 0.75), Color(1.0, 0.93, 0.84, 0.0)])
	_cloud_tex = GradientTexture2D.new()
	_cloud_tex.gradient = gradient
	_cloud_tex.fill = GradientTexture2D.FILL_RADIAL
	_cloud_tex.fill_from = Vector2(0.5, 0.5)
	_cloud_tex.fill_to = Vector2(1.0, 0.5)
	_cloud_tex.width = 64
	_cloud_tex.height = 64


func _noise_texture(noise_seed: int, frequency: float, dark: Color, light: Color, speckle: float) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_octaves = 3
	var src := noise.get_seamless_image(TEX_SIZE, TEX_SIZE)
	var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8)
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = noise_seed
	for y in TEX_SIZE:
		for x in TEX_SIZE:
			var col := dark.lerp(light, src.get_pixel(x, y).r)
			if speckle > 0.0 and local_rng.randf() < speckle:
				col = col.darkened(0.14)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _metal_material(color: Color, half_extents: Vector3, ribs: Vector2) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = METAL_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("half_extents", half_extents)
	material.set_shader_parameter("rib_dir", ribs)
	return material


func _style_obstacles() -> void:
	var box_extents := Vector3(2.0, 1.0, 2.0)
	if allow_kit and OutpostKit.has_piece("container_red") and OutpostKit.has_piece("container_blue"):
		# The kit draws two real containers over each 4 x 2 x 4 m collider; the plain boxes are hidden.
		_hide_node("../Box1/MeshInstance3D")
		_hide_node("../Box2/MeshInstance3D")
	else:
		_apply_material("../Box1/MeshInstance3D", _metal_material(Color(0.62, 0.17, 0.12), box_extents, Vector2(9.0, 9.0)))
		_apply_material("../Box2/MeshInstance3D", _metal_material(Color(0.14, 0.38, 0.5), box_extents, Vector2(9.0, 9.0)))
	_apply_material("../WallN/MeshInstance3D", _metal_material(Color(0.5, 0.42, 0.32), Vector3(30.0, 2.0, 0.5), Vector2(7.0, 0.0)))
	var rock := StandardMaterial3D.new()
	rock.albedo_texture = _rock_tex
	rock.albedo_color = Color(0.85, 0.8, 0.74)
	rock.uv1_triplanar = true
	rock.uv1_world_triplanar = true
	rock.uv1_scale = Vector3(0.22, 0.22, 0.22)
	rock.roughness = 1.0
	_apply_material("../WallE/MeshInstance3D", rock)
	_apply_material("../WallW/MeshInstance3D", rock)


func _apply_material(path: String, material: Material) -> void:
	var mesh := get_node_or_null(path) as MeshInstance3D
	if mesh:
		mesh.material_override = material


func _hide_node(path: String) -> void:
	var node := get_node_or_null(path) as Node3D
	if node:
		node.visible = false


# --- terrain and water -------------------------------------------------------

func _height(x: float, z: float) -> float:
	var beach := maxf(z - BEACH_START_Z, 0.0) * 0.12
	var edge := maxf(maxf(maxf(absf(x), -z) - EDGE_DIST, 0.0), 0.0) * 0.1
	return -(beach + edge)


func _terrain_color(x: float, z: float, h: float) -> Color:
	var jungle := 0.0
	if z < 30.0:
		jungle = smoothstep(0.0, 28.0, maxf(absf(x), absf(z)) - 34.0)  # jungle thickens away from the arena
	else:
		jungle = smoothstep(44.0, 70.0, absf(x))  # the walkable beach stays sand; only its flanks go green
	var col := SAND_LIGHT.lerp(JUNGLE, jungle * 0.85)
	var wet := smoothstep(-0.2, -0.9, h)
	return col.lerp(WET_SAND, wet)


func _add_terrain() -> void:
	var xs: Array[float] = [-170.0, -130.0, -80.0, -56.0, -44.0, -36.0, -30.0, -15.0, 0.0, 15.0, 30.0, 36.0, 44.0, 56.0, 80.0, 130.0, 170.0]
	var zs: Array[float] = [-170.0, -130.0, -80.0, -56.0, -44.0, -36.0, -30.0, -15.0, 0.0, 15.0, 30.0, 34.0, 46.0, 60.0, 72.0, 78.0, 84.0, 92.0, 100.0]
	var b := Builder.new()
	b.uv_scale = 0.07
	for zi in zs.size() - 1:
		for xi in xs.size() - 1:
			var x0 := xs[xi]
			var x1 := xs[xi + 1]
			var z0 := zs[zi]
			var z1 := zs[zi + 1]
			var p00 := Vector3(x0, _height(x0, z0), z0)
			var p10 := Vector3(x1, _height(x1, z0), z0)
			var p11 := Vector3(x1, _height(x1, z1), z1)
			var p01 := Vector3(x0, _height(x0, z1), z1)
			var c00 := _terrain_color(x0, z0, p00.y)
			var c10 := _terrain_color(x1, z0, p10.y)
			var c11 := _terrain_color(x1, z1, p11.y)
			var c01 := _terrain_color(x0, z1, p01.y)
			var n := (p11 - p00).cross(p10 - p00)
			if n.y < 0.0:
				n = -n
			n = n.normalized()
			b.tri(p00, p10, p11, Vector3.UP, c00, c10, c11)
			b.tri(p00, p11, p01, Vector3.UP, c00, c11, c01)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _sand_tex
	material.roughness = 1.0
	var node := MeshInstance3D.new()
	node.name = "Terrain"
	node.mesh = b.finish()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_track(node)


func _add_water() -> void:
	var shader := Shader.new()
	shader.code = WATER_SHADER
	_water_material = ShaderMaterial.new()
	_water_material.shader = shader
	_water_material.set_shader_parameter("noise_tex", _water_noise)
	_water_material.set_shader_parameter("speed", 0.0 if quality_level == QUALITY_LOW else 0.012)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400.0, 1400.0)
	var node := MeshInstance3D.new()
	node.name = "Sea"
	node.mesh = plane
	node.material_override = _water_material
	node.position = Vector3(0.0, SEA_LEVEL, 0.0)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_track(node)


# --- props -------------------------------------------------------------------

## Staged like _build(). Returns true if the build was superseded part-way.
func _add_props(serial: int) -> bool:
	var b := Builder.new()
	kit_active = allow_kit and OutpostKit.has_piece("palm_a") and OutpostKit.has_piece("container_red") \
			and OutpostKit.has_piece("watchtower")
	if kit_active:
		_kit_jungle()
	else:
		_add_palms(b)
		_add_rocks(b)
	if await _next_stage(serial):
		return true
	_add_rope_fence(b)
	if kit_active:
		_kit_beach(b)
	else:
		_add_wreck(b)
		_add_beach_clutter(b)
	if await _next_stage(serial):
		return true
	if kit_active:
		_kit_courtyard()
		_kit_outpost()
	else:
		_add_outpost(b)
	if await _next_stage(serial):
		return true
	if kit_active:
		_flush_kit_chunks()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	var node := MeshInstance3D.new()
	node.name = "Props"
	node.mesh = b.finish()
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_track(node)
	var sign_label := Label3D.new()
	sign_label.name = "OutpostSign"
	sign_label.text = "OUTPOST 17"
	sign_label.font_size = 96
	sign_label.pixel_size = 0.025
	sign_label.outline_size = 16
	sign_label.modulate = Color(0.95, 0.9, 0.75)
	sign_label.position = Vector3(0.0, 6.1, -35.7)
	_track(sign_label)
	return await _next_stage(serial)


func _palm_count() -> int:
	match quality_level:
		QUALITY_LOW:
			return 8
		QUALITY_MEDIUM:
			return 14
	return 20


func _palm_position() -> Vector3:
	# Outside the walls: east/west jungle edge, or the south beach. Never inside the outpost block.
	for attempt in 40:
		var x := _rng.randf_range(-70.0, 70.0)
		var z := _rng.randf_range(-70.0, 74.0)
		var inside_arena := absf(x) < 33.0 and z > -33.0 and z < 33.0
		var in_outpost := absf(x) < 36.0 and z < -33.0
		var on_wreck := Vector2(x, z).distance_to(Vector2(-12.0, 38.0)) < 9.0
		var in_water := _height(x, z) < -0.85
		if not inside_arena and not in_outpost and not on_wreck and not in_water:
			return Vector3(x, _height(x, z), z)
	return Vector3(45.0, 0.0, 10.0)


func _add_palms(b: Builder) -> void:
	for i in _palm_count():
		var pos := _palm_position()
		var h := _rng.randf_range(4.6, 6.6)
		var tilt := Basis(Vector3.BACK, _rng.randf_range(-0.2, 0.2)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.2, 0.2))
		b.prism(pos, 0.3, 0.14, h, 6, Color(0.42, 0.31, 0.2), tilt, Color(0.55, 0.43, 0.29))
		var crown := pos + tilt * Vector3(0.0, h, 0.0)
		var yaw0 := _rng.randf() * TAU
		for k in 7:
			var yaw := yaw0 + TAU * k / 7.0 + _rng.randf_range(-0.2, 0.2)
			var dir := Vector3(cos(yaw), 0.0, sin(yaw))
			b.frond(crown, dir, _rng.randf_range(2.3, 3.1), 1.0, _rng.randf_range(0.8, 1.3),
					Color(0.08, 0.24, 0.07), Color(0.2, 0.4, 0.1))


func _rock(b: Builder, pos: Vector3, radius: float, height: float) -> void:
	var tilt := Basis(Vector3.BACK, _rng.randf_range(-0.25, 0.25)) * Basis(Vector3.UP, _rng.randf() * TAU)
	var shade := _rng.randf_range(0.82, 1.1)
	b.prism(pos, radius, radius * 0.55, height, 5, STONE * shade, tilt, STONE.lightened(0.12) * shade)


func _add_rocks(b: Builder) -> void:
	# Jagged skyline on top of the east and west walls so they read as cliffs.
	for side in [-1.0, 1.0]:
		var z := -27.0
		while z <= 27.0:
			_rock(b, Vector3(30.0 * float(side) + _rng.randf_range(-0.3, 0.3), 3.6, z), _rng.randf_range(1.5, 2.2), _rng.randf_range(1.8, 3.0))
			z += _rng.randf_range(4.5, 7.0)
	var scattered := 16 if quality_level != QUALITY_LOW else 8
	for i in scattered:
		var pos := _palm_position()
		_rock(b, pos, _rng.randf_range(0.7, 1.6), _rng.randf_range(0.6, 1.4))


func _add_rope_fence(b: Builder) -> void:
	# Replaces the invisible south wall (collider at z = 30). The 8 m gap in the middle is the gate
	# (WorldGate draws its own posts and leaves), so no posts or ropes cross it.
	var x := -28.0
	while x <= 28.0:
		var in_gate := absf(x) <= 4.5
		if not in_gate:
			b.box(Vector3(x, 0.55, 30.0), Vector3(0.14, 1.1, 0.14), WOOD_DARK)
		if x < 28.0 and not (x >= -4.5 and x + 4.0 <= 4.5):
			b.box(Vector3(x + 2.0, 0.95, 30.0), Vector3(4.0, 0.04, 0.04), CANVAS)
			b.box(Vector3(x + 2.0, 0.55, 30.0), Vector3(4.0, 0.04, 0.04), CANVAS)
		x += 4.0
	# Visible edge of the walkable beach (matches the invisible colliders in WorldFlow).
	var edge := 42.0
	for side in [-1.0, 1.0]:
		var sx := edge * float(side)
		var run := 30.0
		while run <= 82.0:
			b.box(Vector3(sx, 0.55, run), Vector3(0.14, 1.1, 0.14), WOOD_DARK)
			if run < 82.0:
				b.box(Vector3(sx, 0.95, run + 2.0), Vector3(0.04, 0.04, 4.0), CANVAS)
			run += 4.0
		var stub := 32.0
		while stub <= edge:  # rope from the arena fence out to the beach edge, both sides of the gate
			b.box(Vector3(stub * float(side), 0.55, 30.0), Vector3(0.14, 1.1, 0.14), WOOD_DARK)
			b.box(Vector3((stub - 2.0) * float(side), 0.95, 30.0), Vector3(4.0, 0.04, 0.04), CANVAS)
			stub += 4.0
	var back := -42.0
	while back <= 42.0:
		b.box(Vector3(back, 0.55, 82.0), Vector3(0.14, 1.1, 0.14), WOOD_DARK)
		if back < 42.0:
			b.box(Vector3(back + 2.0, 0.95, 82.0), Vector3(4.0, 0.04, 0.04), CANVAS)
		back += 4.0


func _local_point(origin: Vector3, basis: Basis, local: Vector3) -> Vector3:
	return origin + basis * local


func _add_wreck(b: Builder) -> void:
	var origin := Vector3(-12.0, _height(-12.0, 38.0) + 0.35, 38.0)
	var basis := Basis(Vector3.UP, 0.5) * Basis(Vector3.BACK, 0.2) * Basis(Vector3.RIGHT, 0.06)
	b.box(origin, Vector3(7.6, 1.5, 2.8), WOOD, basis)
	b.box(_local_point(origin, basis, Vector3(3.9, 0.15, 0.0)), Vector3(1.4, 1.2, 2.0), WOOD_DARK, basis * Basis(Vector3.UP, 0.4))
	b.box(_local_point(origin, basis, Vector3(-0.6, 1.25, 0.0)), Vector3(3.0, 1.3, 2.2), CANVAS, basis)
	b.box(_local_point(origin, basis, Vector3(-0.6, 1.95, 0.0)), Vector3(3.2, 0.15, 2.4), RUST, basis)
	var mast_basis := basis * Basis(Vector3.BACK, -0.6)
	b.prism(_local_point(origin, basis, Vector3(1.6, 0.75, 0.0)), 0.12, 0.07, 5.0, 5, WOOD_DARK, mast_basis)
	var sail_a := _local_point(origin, basis, Vector3(1.9, 1.4, 0.0))
	var sail_b := _local_point(origin, basis, Vector3(4.2, 2.8, 0.0))
	var sail_c := _local_point(origin, basis, Vector3(4.2, 0.6, 0.6))
	for n in [Vector3.BACK, Vector3.FORWARD]:
		b.tri(sail_a, sail_b, sail_c, n, CANVAS, CANVAS.darkened(0.15), CANVAS.darkened(0.25))
	for i in 7:
		var plank_pos := origin + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-3.5, 3.5))
		plank_pos.y = _height(plank_pos.x, plank_pos.z) + 0.05
		b.box(plank_pos, Vector3(_rng.randf_range(1.2, 2.4), 0.08, 0.28), WOOD * _rng.randf_range(0.8, 1.1),
				Basis(Vector3.UP, _rng.randf() * TAU))


func _add_beach_clutter(b: Builder) -> void:
	var crate_spots: Array[Vector3] = [Vector3(5.0, 0.0, 38.0), Vector3(7.2, 0.0, 39.0), Vector3(-24.0, 0.0, 37.0)]
	for spot in crate_spots:
		var y := _height(spot.x, spot.z)
		b.box(Vector3(spot.x, y + 0.5, spot.z), Vector3(1.0, 1.0, 1.0), WOOD * _rng.randf_range(0.85, 1.1), Basis(Vector3.UP, _rng.randf() * TAU))
	b.box(Vector3(5.6, _height(5.6, 38.2) + 1.5, 38.2), Vector3(0.9, 0.9, 0.9), WOOD, Basis(Vector3.UP, 0.5))
	for i in 4:
		var bx := _rng.randf_range(-6.0, 12.0)
		var bz := _rng.randf_range(35.0, 40.0)
		b.prism(Vector3(bx, _height(bx, bz), bz), 0.4, 0.4, 0.9, 8, OLIVE)


func _add_outpost(b: Builder) -> void:
	# Barbed fence 6 m behind the north wall.
	var x := -34.0
	while x <= 34.0:
		b.box(Vector3(x, 0.95, -36.0), Vector3(0.12, 1.9, 0.12), WOOD_DARK)
		if x < 34.0:
			for y in [0.6, 1.1, 1.6]:
				b.box(Vector3(x + 1.5, float(y), -36.0), Vector3(3.0, 0.025, 0.025), Color(0.3, 0.3, 0.32))
		x += 3.0

	# Huts
	var huts: Array[Vector4] = [Vector4(-18.0, -44.0, 0.2, 0.0), Vector4(-5.0, -49.0, -0.1, 1.0), Vector4(10.0, -45.0, 0.15, 0.0), Vector4(23.0, -52.0, -0.25, 1.0)]
	for hut in huts:
		var pos := Vector3(hut.x, 0.0, hut.y)
		var yaw := Basis(Vector3.UP, hut.z)
		var wall_color := KHAKI if hut.w < 0.5 else OLIVE
		b.box(pos + Vector3(0.0, 1.4, 0.0), Vector3(5.0, 2.8, 3.6), wall_color, yaw)
		b.prism(pos + Vector3(0.0, 2.8, 0.0), 3.9, 0.0, 1.5, 4, RUST, yaw * Basis(Vector3.UP, PI * 0.25))
		b.box(pos + yaw * Vector3(0.0, 0.95, 1.82), Vector3(1.0, 1.9, 0.1), WOOD_DARK, yaw)
		b.box(pos + yaw * Vector3(1.6, 1.6, 1.82), Vector3(0.8, 0.6, 0.1), Color(0.2, 0.25, 0.28), yaw)

	# Watchtower
	var tower := Vector3(-28.0, 0.0, -40.0)
	for corner in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(1.2, 1.2), Vector2(-1.2, 1.2)]:
		b.prism(tower + Vector3(corner.x, 0.0, corner.y), 0.16, 0.12, 6.5, 5, WOOD_DARK)
	b.box(tower + Vector3(0.0, 6.55, 0.0), Vector3(3.4, 0.2, 3.4), WOOD)
	b.box(tower + Vector3(0.0, 7.45, 0.0), Vector3(2.6, 1.6, 2.6), KHAKI)
	b.box(tower + Vector3(0.0, 7.5, 1.31), Vector3(1.8, 0.5, 0.05), Color(0.12, 0.15, 0.17))
	b.prism(tower + Vector3(0.0, 8.25, 0.0), 2.4, 0.0, 1.3, 4, RUST, Basis(Vector3.UP, PI * 0.25))

	# Radio mast with a dish (the emergency radio from the opening)
	var mast := Vector3(16.0, 0.0, -40.0)
	b.prism(mast, 0.16, 0.07, 13.0, 6, Color(0.55, 0.55, 0.58))
	for h in [5.0, 8.5, 11.5]:
		b.box(mast + Vector3(0.0, float(h), 0.0), Vector3(2.2 - float(h) * 0.12, 0.07, 0.07), Color(0.5, 0.5, 0.52))
	b.box(mast + Vector3(2.6, 0.7, 1.0), Vector3(2.0, 1.4, 1.6), OLIVE)
	b.prism(mast + Vector3(1.4, 3.4, 0.0), 0.9, 0.2, 0.45, 8, CANVAS, Basis(Vector3.BACK, 0.9))

	# Burned-out truck
	var truck := Vector3(2.0, 0.0, -41.0)
	var tb := Basis(Vector3.UP, 0.7)
	b.box(truck + tb * Vector3(0.0, 0.95, 0.0), Vector3(4.4, 0.5, 2.0), Color(0.18, 0.17, 0.16), tb)
	b.box(truck + tb * Vector3(1.6, 1.55, 0.0), Vector3(1.4, 1.2, 1.9), Color(0.22, 0.21, 0.2), tb)
	b.box(truck + tb * Vector3(-0.6, 1.4, 0.0), Vector3(2.8, 0.1, 1.9), Color(0.25, 0.2, 0.17), tb)
	for wx in [-1.5, 1.5]:
		for wz in [-1.05, 1.05]:
			b.prism(truck + tb * Vector3(float(wx), 0.55, float(wz) - 0.12), 0.5, 0.5, 0.24, 8, Color(0.1, 0.1, 0.1), tb * Basis(Vector3.RIGHT, PI * 0.5))

	# Sandbags, barrels, crates scattered around the huts and tower
	var bag_color := Color(0.62, 0.56, 0.4)
	for row in 3:
		for col in 5 - row:
			b.box(Vector3(-24.0 + col * 1.05 + row * 0.52, 0.18 + row * 0.34, -34.4), Vector3(1.0, 0.34, 0.5), bag_color * _rng.randf_range(0.9, 1.05))
	for i in 7:
		var bx := _rng.randf_range(-26.0, 26.0)
		var bz := _rng.randf_range(-58.0, -38.0)
		b.prism(Vector3(bx, 0.0, bz), 0.4, 0.4, 0.95, 8, OLIVE if i % 2 == 0 else RUST)
	for i in 6:
		var cx := _rng.randf_range(-26.0, 26.0)
		var cz := _rng.randf_range(-58.0, -38.0)
		b.box(Vector3(cx, 0.5, cz), Vector3(1.0, 1.0, 1.0), WOOD * _rng.randf_range(0.85, 1.1), Basis(Vector3.UP, _rng.randf() * TAU))


# --- modular kit (assets/environments/kit) -------------------------------------
# Placement only: no collision is created here (the arena colliders live in Main.tscn / WorldFlow).
# Kit pieces face -Z; rotate by PI to face +Z (toward the arena from the north outpost).

## Per-chunk visibility range (m). 0 = always drawn. The chunks are merged meshes: one draw call each.
const KIT_CHUNK_RANGE: Dictionary = {"courtyard": 0.0, "beach": 170.0, "outpost": 190.0, "jungle": 210.0}


func _xf(pos: Vector3, yaw: float = 0.0, s: float = 1.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)


func _kit_batch(chunk: String) -> OutpostKit.Batch:
	if not _kit_batches.has(chunk):
		_kit_batches[chunk] = OutpostKit.Batch.new()
	return _kit_batches[chunk]


func _kit_add(chunk: String, piece: String, xform: Transform3D) -> void:
	_kit_batch(chunk).add(piece, xform)


func _flush_kit_chunks() -> void:
	for chunk in _kit_batches.keys():
		var mesh := (_kit_batches[chunk] as OutpostKit.Batch).finish()
		if mesh == null:
			continue
		var node := MeshInstance3D.new()
		node.name = "Kit_" + String(chunk)
		node.mesh = mesh
		node.material_override = OutpostKit.material()
		# Only the courtyard (the two containers the player fights next to) is worth a shadow pass.
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if chunk == "courtyard" \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = float(KIT_CHUNK_RANGE.get(chunk, 0.0))
		_track(node)
	_kit_batches.clear()


func _kit_jungle() -> void:
	for i in _palm_count():
		var pos := _palm_position()
		var tilt := Basis(Vector3.BACK, _rng.randf_range(-0.1, 0.1)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.1, 0.1))
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * tilt
		basis = basis.scaled(Vector3.ONE * _rng.randf_range(0.85, 1.25))
		_kit_add("jungle", "palm_a" if i % 2 == 0 else "palm_b", Transform3D(basis, pos))
	# Cliff skyline on top of the east and west walls (wall top is y = 4).
	for side in [-1.0, 1.0]:
		var z := -27.0
		while z <= 27.0:
			var piece: String = ["rocks_a", "rocks_b", "rocks_c"][_rng.randi() % 3]
			_kit_add("jungle", piece, _xf(Vector3(30.0 * float(side) + _rng.randf_range(-0.4, 0.4), 3.7, z),
					_rng.randf() * TAU, _rng.randf_range(1.4, 2.1)))
			z += _rng.randf_range(4.5, 7.0)
	for i in (16 if quality_level != QUALITY_LOW else 8):
		var pos := _palm_position()
		_kit_add("jungle", ["rocks_a", "rocks_b", "rocks_c"][_rng.randi() % 3], _xf(pos, _rng.randf() * TAU, _rng.randf_range(0.6, 1.2)))
	if quality_level != QUALITY_LOW:
		for i in (10 if quality_level == QUALITY_MEDIUM else 18):
			var pos := _palm_position()
			_kit_add("jungle", "bush", _xf(pos, _rng.randf() * TAU, _rng.randf_range(0.9, 1.5)))


func _kit_beach(b: Builder) -> void:
	# Shipwreck from the story: same spot and tilt as the old primitive wreck.
	var origin := Vector3(-12.0, _height(-12.0, 38.0), 38.0)
	var tilt := Basis(Vector3.UP, 0.5) * Basis(Vector3.BACK, 0.2) * Basis(Vector3.RIGHT, 0.06)
	_kit_add("beach", "boat_wreck", Transform3D(tilt, origin))
	for i in 7:  # scattered planks stay in the merged primitive mesh
		var plank_pos := origin + Vector3(_rng.randf_range(-6.0, 6.0), 0.0, _rng.randf_range(-3.5, 3.5))
		plank_pos.y = _height(plank_pos.x, plank_pos.z) + 0.05
		b.box(plank_pos, Vector3(_rng.randf_range(1.2, 2.4), 0.08, 0.28), WOOD * _rng.randf_range(0.8, 1.1),
				Basis(Vector3.UP, _rng.randf() * TAU))
	var crate_spots: Array[Vector3] = [Vector3(5.0, 0.0, 38.0), Vector3(7.2, 0.0, 39.0), Vector3(-24.0, 0.0, 37.0)]
	for spot in crate_spots:
		_kit_add("beach", "crate", _xf(Vector3(spot.x, _height(spot.x, spot.z), spot.z), _rng.randf() * TAU))
	_kit_add("beach", "crate", _xf(Vector3(5.6, _height(5.6, 38.2) + 1.0, 38.2), 0.5, 0.9))
	for i in 4:
		var bx := _rng.randf_range(-6.0, 12.0)
		var bz := _rng.randf_range(35.0, 40.0)
		_kit_add("beach", "barrel", _xf(Vector3(bx, _height(bx, bz), bz), _rng.randf() * TAU))


func _kit_courtyard() -> void:
	# Two containers side by side over each 4 x 2 x 4 m obstacle collider (the footprint matches exactly).
	for entry in [["../Box1", "container_red", 0.0], ["../Box2", "container_blue", PI]]:
		var box := get_node_or_null(entry[0]) as Node3D
		if box == null:
			continue
		var c := box.global_position
		for dz in [-1.0, 1.0]:
			_kit_add("courtyard", entry[1], _xf(Vector3(c.x, c.y - 1.0, c.z + float(dz)), float(entry[2])))
	if quality_level == QUALITY_LOW:
		return
	# Sandbag stacks hugging the inside of the north wall (decor only: the wall collider is the boundary).
	for x in [-18.0, -6.0, 9.0, 21.0]:
		_kit_add("courtyard", "sandbag_stack", _xf(Vector3(x, 0.0, -29.1), PI + _rng.randf_range(-0.08, 0.08)))


func _kit_outpost() -> void:
	# Everything here is behind the north wall (z < -33): scenery only, never reachable.
	var low := quality_level == QUALITY_LOW
	# Chain-link front fence 6 m behind the wall (replaces the old barbed boxes).
	var x := -34.0
	while x <= 34.0:
		_kit_add("outpost", "fence_wire", _xf(Vector3(x + 2.0, 0.0, -36.0), PI))
		x += 4.0
	# Enclosure: corrugated fence on both sides and the back.
	if not low:
		for z in [-39.0, -45.0, -51.0, -57.0, -63.0, -69.0]:
			_kit_add("outpost", "fence_section", _xf(Vector3(-34.0, 0.0, float(z)), PI * 0.5))
			_kit_add("outpost", "fence_section", _xf(Vector3(34.0, 0.0, float(z)), PI * 0.5))
		var fx := -33.0
		while fx <= 33.0:
			_kit_add("outpost", "fence_section", _xf(Vector3(fx, 0.0, -72.0), 0.0))
			fx += 6.0
	# Huts, as before, but with real roofs and doors facing the arena.
	var huts: Array[Vector4] = [Vector4(-18.0, -44.0, 0.2, 0.0), Vector4(-5.0, -49.0, -0.1, 1.0),
			Vector4(10.0, -45.0, 0.15, 0.0), Vector4(23.0, -52.0, -0.25, 1.0)]
	for hut in huts:
		_kit_add("outpost", "hut_small" if hut.w < 0.5 else "hut_olive", _xf(Vector3(hut.x, 0.0, hut.y), hut.z + PI))
	_kit_add("outpost", "watchtower", _xf(Vector3(-28.0, 0.0, -40.0), PI))
	_kit_add("outpost", "radio_mast", _xf(Vector3(16.0, 0.0, -40.0), PI * 0.5))
	_kit_add("outpost", "truck_wreck", _xf(Vector3(2.0, 0.0, -41.0), 0.7))
	_kit_add("outpost", "barracks", _xf(Vector3(-12.0, 0.0, -60.0), PI))
	_kit_add("outpost", "warehouse", _xf(Vector3(21.0, 0.0, -66.0), PI))
	_kit_add("outpost", "sign_outpost_17", _xf(Vector3(-14.0, 0.0, -37.4), PI))
	if low:
		return
	# Containers (one stack), tents, generator, barricades, sandbags, barrels and crates.
	_kit_add("outpost", "container_green", _xf(Vector3(-30.0, 0.0, -53.0), 0.1))
	_kit_add("outpost", "container_red", _xf(Vector3(-30.2, 2.0, -53.0), -0.05))
	_kit_add("outpost", "container_blue", _xf(Vector3(-29.0, 0.0, -58.5), 0.15))
	_kit_add("outpost", "container_green", _xf(Vector3(30.0, 0.0, -45.0), PI * 0.5 + 0.1))
	_kit_add("outpost", "tent", _xf(Vector3(28.0, 0.0, -58.0), 0.4))
	_kit_add("outpost", "tent", _xf(Vector3(-24.0, 0.0, -66.0), -0.5))
	_kit_add("outpost", "generator", _xf(Vector3(-2.0, 0.0, -38.6), PI))
	_kit_add("outpost", "barricade_concrete", _xf(Vector3(8.0, 0.0, -38.4), 0.0))
	_kit_add("outpost", "barricade_concrete", _xf(Vector3(12.5, 0.0, -38.4), 0.05))
	_kit_add("outpost", "barricade_wire", _xf(Vector3(-8.0, 0.0, -38.2), 0.0))
	_kit_add("outpost", "sandbag_corner", _xf(Vector3(-24.0, 0.0, -34.6), PI))
	_kit_add("outpost", "sandbag_stack", _xf(Vector3(-27.0, 0.0, -37.4), PI))
	_kit_add("outpost", "sandbag_stack", _xf(Vector3(24.5, 0.0, -34.8), PI))
	for i in 7:
		var bx := _rng.randf_range(-26.0, 26.0)
		var bz := _rng.randf_range(-58.0, -38.5)
		_kit_add("outpost", "barrel", _xf(Vector3(bx, 0.0, bz), _rng.randf() * TAU))
	for i in 6:
		var cx := _rng.randf_range(-26.0, 26.0)
		var cz := _rng.randf_range(-58.0, -38.5)
		_kit_add("outpost", "crate", _xf(Vector3(cx, 0.0, cz), _rng.randf() * TAU))


# --- clouds ------------------------------------------------------------------

func _add_clouds() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _cloud_tex
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = 9
	for i in 9:
		var angle := TAU * i / 9.0 + _rng.randf_range(-0.2, 0.2)
		var radius := _rng.randf_range(150.0, 230.0)
		var size := _rng.randf_range(70.0, 120.0)
		var xform := Transform3D(Basis.from_scale(Vector3(size, size * 0.32, 1.0)),
				Vector3(cos(angle) * radius, _rng.randf_range(22.0, 48.0), sin(angle) * radius))
		multimesh.set_instance_transform(i, xform)
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var holder := Node3D.new()
	holder.name = "Clouds"
	holder.add_child(node)
	_clouds = holder
	_track(holder)
