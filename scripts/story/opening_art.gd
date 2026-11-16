class_name OpeningArt
extends RefCounted
## Procedural art for the opening arc, shared by the cinematic, the beach approach and the payment prop so one
## look is used everywhere and tests can build it without a window: a tapered speedboat, the real character
## models with a looping clip and a tint, a smooth earth embankment mesh, and a cheap animated ocean shader.
## Everything here is visual only: no collision, no gameplay state.

const PLAYER_MODEL: String = "res://assets/characters/player.glb"
const SOLDIER_MODEL: String = "res://assets/characters/soldier.glb"

const HULL_CREAM: Color = Color(0.86, 0.82, 0.72)
const HULL_STRIPE: Color = Color(0.62, 0.16, 0.12)
const DECK_COLOR: Color = Color(0.36, 0.4, 0.44)
const DARK_METAL: Color = Color(0.13, 0.14, 0.16)

## Half-width of the deck at each z (bow at -z). The keel is narrower, so the hull tapers in both views.
const HULL_OUTLINE: Array[Vector2] = [
	Vector2(0.95, 2.3), Vector2(1.05, 1.0), Vector2(1.02, -1.0), Vector2(0.62, -2.3), Vector2(0.0, -3.3),
]
const DECK_Y: float = 0.3
const KEEL_Y: float = -0.7
const KEEL_SCALE: float = 0.5


# --- characters ------------------------------------------------------------------

## The real rigged model, vertex-coloured, tinted, looping `clip`. Null when the file is missing so callers can
## keep their fallback. The model faces -Z, feet at y = 0, about 1.8 m tall.
static func character(path: String, clip: String, tint: Color = Color.WHITE, speed: float = 1.0) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	if model == null:
		return null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var source := mi.get_active_material(surface) as BaseMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as BaseMaterial3D
			material.vertex_color_use_as_albedo = true
			material.albedo_color = tint
			mi.set_surface_override_material(surface, material)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var anim := players.front() as AnimationPlayer
		var clip_name := _resolve_clip(anim, clip)
		if clip_name != "":
			anim.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR
			anim.speed_scale = speed
			anim.autoplay = clip_name  # starts when the model enters the tree
	return model


static func _resolve_clip(anim: AnimationPlayer, clip: String) -> String:
	for candidate in anim.get_animation_list():
		var short := String(candidate).get_slice("|", String(candidate).get_slice_count("|") - 1)
		if short.to_lower() == clip.to_lower():
			return String(candidate)
	return ""


static func clip_playing(model: Node) -> String:
	for node in model.find_children("*", "AnimationPlayer", true, false):
		return String((node as AnimationPlayer).autoplay)
	return ""


# --- the speedboat -----------------------------------------------------------------

static func material(vertex_colors: bool = true, roughness: float = 0.55, metallic: float = 0.05) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = vertex_colors
	m.roughness = roughness
	m.metallic = metallic
	return m


static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## The hull as one vertex-coloured mesh: cream sides with a red waterline stripe, a grey deck, a pointed bow.
static func hull_mesh() -> ArrayMesh:
	var b := ArenaDecor.Builder.new()
	var n := HULL_OUTLINE.size()
	for side: float in [-1.0, 1.0]:
		for i in n - 1:
			var wa: float = HULL_OUTLINE[i].x
			var za: float = HULL_OUTLINE[i].y
			var wb: float = HULL_OUTLINE[i + 1].x
			var zb: float = HULL_OUTLINE[i + 1].y
			var d0 := Vector3(side * wa, DECK_Y, za)
			var d1 := Vector3(side * wb, DECK_Y, zb)
			var k1 := Vector3(side * wb * KEEL_SCALE, KEEL_Y, zb)
			var k0 := Vector3(side * wa * KEEL_SCALE, KEEL_Y, za)
			var normal := (d1 - d0).cross(k0 - d0).normalized()
			if normal.x * side < 0.0:
				normal = -normal
			b.quad(d0, d1, k1, k0, normal, HULL_CREAM, HULL_STRIPE)
			# The deck strip between this side's edge and the centre line.
			var c0 := Vector3(0.0, DECK_Y + 0.02, za)
			var c1 := Vector3(0.0, DECK_Y + 0.02, zb)
			b.quad(d0 + Vector3(0, 0.02, 0), d1 + Vector3(0, 0.02, 0), c1, c0, Vector3.UP, DECK_COLOR)
	# The transom (stern face).
	var s: Vector2 = HULL_OUTLINE[0]
	b.quad(Vector3(-s.x, DECK_Y, s.y), Vector3(s.x, DECK_Y, s.y), Vector3(s.x * KEEL_SCALE, KEEL_Y, s.y),
			Vector3(-s.x * KEEL_SCALE, KEEL_Y, s.y), Vector3(0, 0, 1), HULL_CREAM, HULL_STRIPE)
	# A raised gunwale along each side.
	for side: float in [-1.0, 1.0]:
		for i in n - 1:
			var a := Vector3(side * HULL_OUTLINE[i].x, DECK_Y + 0.12, HULL_OUTLINE[i].y)
			var c := Vector3(side * HULL_OUTLINE[i + 1].x, DECK_Y + 0.12, HULL_OUTLINE[i + 1].y)
			b.quad(a, c, c + Vector3(0, -0.12, 0), a + Vector3(0, -0.12, 0), Vector3(side, 0, 0), HULL_CREAM.lightened(0.1))
			b.quad(a, c, c + Vector3(-side * 0.08, 0, 0), a + Vector3(-side * 0.08, 0, 0), Vector3.UP, DECK_COLOR.lightened(0.15))
	return b.finish()


static func boat() -> Node3D:
	var root := Node3D.new()
	root.name = "SpeedBoat"
	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = hull_mesh()
	hull.material_override = material(true, 0.45, 0.1)
	root.add_child(hull)

	# Console, bench, engine and wheel in one mesh.
	var b := ArenaDecor.Builder.new()
	b.box(Vector3(0.0, DECK_Y + 0.28, -0.75), Vector3(1.1, 0.55, 0.45), DARK_METAL.lightened(0.06))  # console
	b.box(Vector3(0.0, DECK_Y + 0.58, -0.75), Vector3(1.0, 0.04, 0.36), Color(0.2, 0.22, 0.25))
	b.box(Vector3(0.0, DECK_Y + 0.2, 1.35), Vector3(1.6, 0.4, 0.5), Color(0.28, 0.3, 0.34))  # bench
	b.box(Vector3(0.0, DECK_Y + 0.42, 1.55), Vector3(1.6, 0.34, 0.12), Color(0.34, 0.36, 0.4))  # bench back
	b.box(Vector3(0.0, DECK_Y + 0.35, 2.55), Vector3(0.7, 0.7, 0.55), DARK_METAL)  # outboard motor
	b.box(Vector3(0.0, DECK_Y - 0.15, 2.7), Vector3(0.24, 0.9, 0.3), DARK_METAL.lightened(0.04))  # leg
	b.prism(Vector3(0.0, KEEL_Y + 0.05, 2.85), 0.18, 0.18, 0.04, 8, Color(0.5, 0.5, 0.52))  # prop disc
	for side: float in [-1.0, 1.0]:  # cleats
		b.box(Vector3(side * 0.7, DECK_Y + 0.2, -2.0), Vector3(0.1, 0.1, 0.2), Color(0.7, 0.7, 0.72))
	var fittings := MeshInstance3D.new()
	fittings.name = "Fittings"
	fittings.mesh = b.finish()
	fittings.material_override = material(true, 0.6, 0.15)
	root.add_child(fittings)

	var wheel := MeshInstance3D.new()
	wheel.name = "Wheel"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.11
	torus.outer_radius = 0.16
	torus.rings = 12
	torus.ring_segments = 6
	wheel.mesh = torus
	wheel.material_override = material(false, 0.5, 0.2)
	wheel.position = Vector3(0.0, DECK_Y + 0.8, -0.62)
	wheel.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	root.add_child(wheel)

	var glass := MeshInstance3D.new()
	glass.name = "Windshield"
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(1.55, 0.62, 0.05)
	glass.mesh = glass_mesh
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.62, 0.8, 0.9, 0.35)
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness = 0.1
	glass.material_override = glass_mat
	glass.position = Vector3(0.0, DECK_Y + 0.95, -1.05)
	glass.rotation_degrees = Vector3(-24.0, 0.0, 0.0)
	root.add_child(glass)
	var frame := ArenaDecor.Builder.new()
	for side: float in [-0.78, 0.78]:
		frame.box(Vector3(side, DECK_Y + 0.92, -1.05), Vector3(0.05, 0.7, 0.06), DARK_METAL, Basis(Vector3.RIGHT, deg_to_rad(-24.0)))
	frame.box(Vector3(0.0, DECK_Y + 1.25, -1.17), Vector3(1.6, 0.05, 0.06), DARK_METAL, Basis(Vector3.RIGHT, deg_to_rad(-24.0)))
	var frame_node := MeshInstance3D.new()
	frame_node.name = "WindshieldFrame"
	frame_node.mesh = frame.finish()
	frame_node.material_override = material(true, 0.5, 0.3)
	root.add_child(frame_node)

	# Running lights: red to port, green to starboard, plus one real light for the glow on the deck.
	for entry: Array in [[-1.0, Color(1.0, 0.1, 0.1)], [1.0, Color(0.15, 1.0, 0.3)]]:
		var lamp := MeshInstance3D.new()
		lamp.name = "RunningLightPort" if float(entry[0]) < 0.0 else "RunningLightStarboard"
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		sphere.radial_segments = 6
		sphere.rings = 3
		lamp.mesh = sphere
		lamp.material_override = emissive(entry[1], 2.0)
		lamp.position = Vector3(float(entry[0]) * 0.8, DECK_Y + 0.35, -1.9)
		root.add_child(lamp)
	var nav_light := OmniLight3D.new()
	nav_light.name = "NavLight"
	nav_light.light_color = Color(0.3, 1.0, 0.4)
	nav_light.light_energy = 0.6
	nav_light.omni_range = 2.0
	nav_light.position = Vector3(0.9, DECK_Y + 0.4, -1.9)
	root.add_child(nav_light)

	root.add_child(wake_spray())
	return root


## White spray kicked up behind the motor. A small particle count: it is only ever on screen for 50 seconds.
static func wake_spray() -> CPUParticles3D:
	var spray := CPUParticles3D.new()
	spray.name = "WakeSpray"
	spray.amount = 36
	spray.lifetime = 0.9
	spray.direction = Vector3(0.0, 0.5, 1.0)
	spray.spread = 28.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 4.0
	spray.gravity = Vector3(0.0, -6.0, 0.0)
	spray.color = Color(0.9, 0.95, 1.0, 0.65)
	var puff := SphereMesh.new()
	puff.radius = 0.07
	puff.height = 0.14
	puff.radial_segments = 4
	puff.rings = 2
	spray.mesh = puff
	spray.position = Vector3(0.0, KEEL_Y + 0.2, 3.0)
	return spray


# --- ocean ---------------------------------------------------------------------------

const OCEAN_SHADER: String = """
shader_type spatial;
uniform vec3 deep_color : source_color = vec3(0.05, 0.10, 0.15);
uniform vec3 foam_color : source_color = vec3(0.78, 0.84, 0.9);
uniform float storm = 0.0;
varying float h;
float wave(vec2 p, float t) {
	return sin(p.x * 0.35 + t * 1.3) * 0.5 + sin(p.y * 0.28 - t * 1.7) * 0.35 + sin((p.x + p.y) * 0.6 + t * 2.3) * 0.15;
}
void vertex() {
	vec2 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float amp = 0.08 + storm * 0.55;
	h = wave(p, TIME);
	VERTEX.y += h * amp;
	float e = 0.5;
	float hx = wave(p + vec2(e, 0.0), TIME) - h;
	float hz = wave(p + vec2(0.0, e), TIME) - h;
	NORMAL = normalize(vec3(-hx * amp / e, 1.0, -hz * amp / e));
}
void fragment() {
	float foam = clamp(smoothstep(0.55, 0.95, h) * (0.2 + storm), 0.0, 1.0);
	ALBEDO = mix(deep_color, foam_color, foam);
	ROUGHNESS = mix(0.25, 0.8, foam);
	METALLIC = 0.1;
}
"""

const OCEAN_GRID_SIZE: float = 140.0
const OCEAN_GRID_CELLS: int = 47  # 48 x 48 quads


## The animated wave grid. Used only above the LOW quality preset; LOW keeps the flat plane.
static func ocean_grid() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "WaveGrid"
	var plane := PlaneMesh.new()
	plane.size = Vector2(OCEAN_GRID_SIZE, OCEAN_GRID_SIZE)
	plane.subdivide_width = OCEAN_GRID_CELLS
	plane.subdivide_depth = OCEAN_GRID_CELLS
	node.mesh = plane
	var shader := Shader.new()
	shader.code = OCEAN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


# --- the earth embankment ---------------------------------------------------------------

const BERM_BATTER: float = 1.2  # visual run of each side slope outside the collision box

static func _hash(ix: int, iz: int, seed_value: int) -> float:
	var h: int = (ix * 73856093) ^ (iz * 19349663) ^ (seed_value * 83492791)
	h = h & 0x7fffffff
	return float(h % 1000) / 1000.0


## A smooth, noisy embankment between x0 and x1 whose crown follows [z0, z1] at `height`. The slopes run out
## by BERM_BATTER on each side; vertex colours go sand -> earth/scrub -> rock with height. Visual only.
static func berm_mesh(x0: float, x1: float, z0: float, z1: float, height: float, seed_value: int = 1) -> ArrayMesh:
	var nx: int = maxi(2, int(ceil((x1 - x0) / 1.5)))
	var profile_z: Array[float] = [z0 - BERM_BATTER, z0 - BERM_BATTER * 0.5, z0, (z0 + z1) * 0.5, z1, z1 + BERM_BATTER * 0.5, z1 + BERM_BATTER]
	var profile_h: Array[float] = [0.0, 0.5, 0.96, 1.0, 0.96, 0.5, 0.0]
	var nz: int = profile_z.size()
	var grid: Array = []
	for ix in nx + 1:
		var column: Array[Vector3] = []
		var x := lerpf(x0, x1, float(ix) / float(nx))
		for iz in nz:
			var noise := (_hash(ix, iz, seed_value) - 0.5) * 0.5
			var y: float = profile_h[iz] * height
			if iz > 0 and iz < nz - 1:
				y += noise * minf(1.0, height * 0.25) * (1.0 if iz != 3 else 1.4)
			y = maxf(y, 0.0)
			var zj: float = profile_z[iz]
			if ix > 0 and ix < nx and iz > 0 and iz < nz - 1:
				zj += (_hash(iz, ix, seed_value + 7) - 0.5) * 0.3
			column.append(Vector3(x, y, zj))
		grid.append(column)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ix in nx:
		for iz in nz - 1:
			var p00: Vector3 = grid[ix][iz]
			var p10: Vector3 = grid[ix + 1][iz]
			var p11: Vector3 = grid[ix + 1][iz + 1]
			var p01: Vector3 = grid[ix][iz + 1]
			for tri_pts: Array in [[p00, p10, p11], [p00, p11, p01]]:
				var normal: Vector3 = ((tri_pts[1] as Vector3) - (tri_pts[0] as Vector3)).cross((tri_pts[2] as Vector3) - (tri_pts[0] as Vector3)).normalized()
				if normal.y < 0.0:
					normal = -normal
				for k in 3:
					var p: Vector3 = tri_pts[k]
					st.set_normal(normal)
					st.set_color(_berm_color(p.y / maxf(height, 0.01), _hash(int(p.x * 3.0), int(p.z * 3.0), seed_value)))
					st.add_vertex(p)
	# Vertical end caps so a segment beside a gap is closed instead of showing its inside.
	for ix: int in [0, nx]:
		var cap_normal := Vector3(-1.0 if ix == 0 else 1.0, 0.0, 0.0)
		for iz in nz - 1:
			var a: Vector3 = grid[ix][iz]
			var b: Vector3 = grid[ix][iz + 1]
			var a0 := Vector3(a.x, 0.0, a.z)
			var b0 := Vector3(b.x, 0.0, b.z)
			for tri_pts: Array in [[a0, a, b], [a0, b, b0]]:
				var pts: Array = tri_pts
				var normal: Vector3 = ((pts[1] as Vector3) - (pts[0] as Vector3)).cross((pts[2] as Vector3) - (pts[0] as Vector3)).normalized()
				if normal.dot(cap_normal) > 0.0:  # Godot front faces are clockwise: the right-hand normal points away
					pts = [pts[0], pts[2], pts[1]]
				for k in 3:
					st.set_normal(cap_normal)
					st.set_color(_berm_color(0.3, 0.2))
					st.add_vertex(pts[k] as Vector3)
	return st.commit()


static func _berm_color(fraction: float, noise: float) -> Color:
	var sand := Color(0.4, 0.33, 0.22)
	var earth := Color(0.27, 0.21, 0.14)
	var scrub := Color(0.2, 0.3, 0.14)
	var rock := Color(0.38, 0.36, 0.33)
	if fraction < 0.18:
		return sand.lerp(earth, fraction / 0.18)
	if fraction < 0.7:
		return earth.lerp(scrub, clampf(noise * 1.2, 0.0, 1.0))
	return scrub.lerp(rock, clampf((fraction - 0.7) / 0.3 + noise * 0.4, 0.0, 1.0))
