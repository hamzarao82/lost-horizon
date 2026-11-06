class_name DeadCoastTerrain
extends RefCounted
## Height field, colours and meshes for the Dead Coast. Everything is expressed as
## (d, z): d = metres inland from the shoreline at that z, z = world z (north is negative).
## The shore bends with z and a bay (Smuggler's Cove) pushes it east, so the whole strip follows it.

const X_MIN: float = -90.0
const X_MAX: float = 110.0
const Z_MIN: float = -230.0
const Z_MAX: float = 32.0
const STEP: float = 4.0
const SEA_LEVEL: float = -0.55
const CLIFF_D0: float = 34.0
const CLIFF_D1: float = 40.0
const SHORE_WALL_D: float = -3.0

const SAND: Color = Color(0.7, 0.57, 0.38)
const SAND_DARK: Color = Color(0.55, 0.43, 0.29)
const WET_SAND: Color = Color(0.4, 0.32, 0.23)
const FOAM: Color = Color(0.72, 0.74, 0.7)
const CLIFF: Color = Color(0.5, 0.36, 0.27)
const CLIFF_TOP: Color = Color(0.4, 0.42, 0.26)
const POCKET: Color = Color(0.4, 0.37, 0.3)

# Watchpoint ramp: from A (south of the checkpoint gate) up to the plateau at B, in (d, z).
const RAMP_A: Vector2 = Vector2(16.0, -124.0)
const RAMP_B: Vector2 = Vector2(40.0, -140.0)
const RAMP_HALF_WIDTH: float = 4.0
const PLATEAU_HEIGHT: float = 10.0
const PLATEAU: Rect2 = Rect2(38.0, -172.0, 30.0, 40.0)  # d, z (position), size: d extent, z extent
# Hidden depot pocket and the cleft that leads to it.
const POCKET_RECT: Rect2 = Rect2(36.0, -202.0, 26.0, 26.0)
const POCKET_FLOOR: float = 1.0
const CLEFT_RECT: Rect2 = Rect2(22.0, -190.5, 16.0, 6.0)
# Checkpoint choke: rock raised from the cliff side so the gate spans the whole walkable corridor.
const CHOKE_Z0: float = -121.0
const CHOKE_Z1: float = -115.0
const CHOKE_D: float = 9.0

static var _noise: FastNoiseLite


static func _n(x: float, z: float) -> float:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 20261107
		_noise.frequency = 0.045
	return _noise.get_noise_2d(x, z)


static func shore_x(z: float) -> float:
	var bay := 24.0 * exp(-pow((z + 168.0) / 16.0, 2.0))
	return -14.0 + 6.0 * sin(z * 0.045) + bay


static func inland_distance(x: float, z: float) -> float:
	return x - shore_x(z)


static func _smooth(a: float, b: float, v: float) -> float:
	return smoothstep(a, b, v)


static func _in_rect(rect: Rect2, d: float, z: float, margin: float) -> float:
	## 1 inside the rect, fading to 0 over `margin` metres outside it.
	var dx := maxf(maxf(rect.position.x - d, d - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - z, z - rect.end.y), 0.0)
	var outside := sqrt(dx * dx + dz * dz)
	return 1.0 - clampf(outside / maxf(margin, 0.01), 0.0, 1.0)


static func _ramp_height(d: float, z: float) -> float:
	var ab := RAMP_B - RAMP_A
	var ap := Vector2(d, z) - RAMP_A
	var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := RAMP_A + ab * t
	var perp := Vector2(d, z).distance_to(closest)
	var fade := 1.0 - smoothstep(RAMP_HALF_WIDTH - 1.0, RAMP_HALF_WIDTH + 1.5, perp)
	return PLATEAU_HEIGHT * smoothstep(0.0, 1.0, t) * fade


static func height(x: float, z: float) -> float:
	var d := inland_distance(x, z)
	if d < 0.0:
		return maxf(d * 0.12, -6.0)
	var sand := 0.18 * minf(d / 6.0, 1.0) + _n(x, z) * 0.22
	var rise := 6.0 + 5.0 * clampf((-z - 60.0) / 80.0, 0.0, 1.0)
	var t := _smooth(CLIFF_D0, CLIFF_D1, d)
	var cliff := rise * t + t * _n(x * 2.1, z * 2.1) * 1.4
	var h := sand + cliff
	# Choke rock beside the checkpoint gate.
	if z < CHOKE_Z1 + 3.0 and z > CHOKE_Z0 - 3.0 and d > CHOKE_D - 1.5:
		var cz := _smooth(CHOKE_Z0 - 3.0, CHOKE_Z0, z) * (1.0 - _smooth(CHOKE_Z1, CHOKE_Z1 + 3.0, z))
		var cd := _smooth(CHOKE_D - 1.5, CHOKE_D + 1.5, d)
		h = maxf(h, 6.5 * cz * cd)
	# Watchpoint plateau and its ramp.
	var plateau := _in_rect(PLATEAU, d, z, 3.0)
	h = lerpf(h, PLATEAU_HEIGHT + _n(x * 1.5, z * 1.5) * 0.25, plateau)
	h = maxf(h, _ramp_height(d, z))
	# Depot pocket and cleft are carved down to a walkable floor.
	var carve := maxf(_in_rect(POCKET_RECT, d, z, 2.0), _in_rect(CLEFT_RECT, d, z, 1.5))
	var floor_h := lerpf(0.18, POCKET_FLOOR, _smooth(CLEFT_RECT.end.x - 2.0, POCKET_RECT.position.x + 2.0, d))
	h = lerpf(h, floor_h + _n(x, z) * 0.1, carve)
	return h


static func ground(d: float, z: float, lift: float = 0.0) -> Vector3:
	var x := shore_x(z) + d
	return Vector3(x, height(x, z) + lift, z)


static func color_at(x: float, z: float, h: float) -> Color:
	var d := inland_distance(x, z)
	var n := _n(x * 3.0, z * 3.0)
	if d < 0.0:
		return FOAM.lerp(WET_SAND, clampf(-d / 6.0, 0.0, 1.0)) if d > -4.5 else WET_SAND.darkened(0.35)
	if d < 2.5:
		return FOAM.lerp(WET_SAND, d / 2.5)
	var sand := SAND.lerp(SAND_DARK, clampf(0.5 + n * 1.3, 0.0, 1.0))
	if d < 8.0:
		sand = WET_SAND.lerp(sand, (d - 2.5) / 5.5)
	if _in_rect(POCKET_RECT, d, z, 1.0) > 0.5 or _in_rect(CLEFT_RECT, d, z, 0.5) > 0.5:
		return POCKET.lerp(SAND_DARK, 0.25 + n * 0.5)
	var rock := _smooth(0.5, 3.5, h)
	var top := CLIFF_TOP.lerp(CLIFF, clampf(0.4 + n, 0.0, 1.0))
	var cliff := CLIFF.lerp(CLIFF.darkened(0.25), clampf(0.5 + n * 1.5, 0.0, 1.0))
	var rocky := cliff.lerp(top, _smooth(8.5, 10.5, h) * 0.8)
	return sand.lerp(rocky, rock)


static func build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := int((X_MAX - X_MIN) / STEP)
	var nz := int((Z_MAX - Z_MIN) / STEP)
	for iz in nz:
		for ix in nx:
			var x0 := X_MIN + ix * STEP
			var z0 := Z_MIN + iz * STEP
			var p00 := _vertex(x0, z0)
			var p10 := _vertex(x0 + STEP, z0)
			var p01 := _vertex(x0, z0 + STEP)
			var p11 := _vertex(x0 + STEP, z0 + STEP)
			for tri in [[p00, p10, p11], [p00, p11, p01]]:
				for v: Array in tri:
					st.set_color(v[1])
					st.add_vertex(v[0])
	st.generate_normals()
	return st.commit()


static func _vertex(x: float, z: float) -> Array:
	var h := height(x, z)
	return [Vector3(x, h, z), color_at(x, z, h)]


## Collision-only ribbon along the shoreline: the sea floor drops away, so without it the player could wade out.
static func shore_wall_positions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var z := Z_MAX - 2.0
	while z > Z_MIN + 6.0:
		var a := Vector3(shore_x(z) + SHORE_WALL_D, 0.0, z)
		var b := Vector3(shore_x(z - 6.0) + SHORE_WALL_D, 0.0, z - 6.0)
		var mid := (a + b) * 0.5
		var dir := b - a
		out.append({"center": Vector3(mid.x, 2.0, mid.z), "length": dir.length() + 0.6, "yaw": atan2(-dir.x, -dir.z)})
		z -= 6.0
	return out
