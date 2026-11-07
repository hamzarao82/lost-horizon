class_name IronFortressZones
extends RefCounted
## Layout constants and the colour identity of each zone. Local coordinates: the player arrives at the south
## end (+z) and the fortress runs north (-z). X runs east. All floors are at y = 0.

const HALF_W: float = 32.0
const WALL_H: float = 4.6
const Z_SOUTH: float = 54.0     # the road in from the Research Complex
const Z_A_B: float = -6.0       # main gate (credential: fortress gate)
const Z_B_C: float = -46.0      # barracks gate (credential: barracks)
const Z_C_D: float = -88.0      # command center door (credential: command key)
const Z_D_E: float = -130.0     # inner fortress door (credential: inner access)
const Z_E_F: float = -172.0     # control facility door (opens when the lockdown is lifted and the Captain is down)
const Z_END: float = -214.0

## id, display name, centre z, length
const AREAS: Array[Dictionary] = [
	{"id": &"if_approach", "name": "Fortress Approach", "z": 24.0, "len": 60.0},
	{"id": &"if_perimeter", "name": "Outer Defensive Perimeter", "z": -26.0, "len": 40.0},
	{"id": &"if_barracks", "name": "Military Barracks", "z": -67.0, "len": 42.0},
	{"id": &"if_command", "name": "Command Center", "z": -109.0, "len": 42.0},
	{"id": &"if_inner", "name": "Inner Fortress", "z": -151.0, "len": 42.0},
	{"id": &"if_control", "name": "Project Black Site Control Facility", "z": -193.0, "len": 42.0},
]

const GROUND: Color = Color(0.34, 0.33, 0.3)
const ASPHALT: Color = Color(0.19, 0.2, 0.22)
const CONCRETE: Color = Color(0.5, 0.5, 0.5)
const STEEL: Color = Color(0.36, 0.39, 0.42)
const FENCE: Color = Color(0.4, 0.43, 0.45)
const HAZARD: Color = Color(0.92, 0.75, 0.1)
const WOOD: Color = Color(0.4, 0.3, 0.19)
const OLIVE: Color = Color(0.3, 0.36, 0.24)
const SAND: Color = Color(0.5, 0.45, 0.3)
const BARRACKS_FLOOR: Color = Color(0.4, 0.38, 0.28)
const BARRACKS_WALL: Color = Color(0.58, 0.55, 0.4)
const COMMAND_FLOOR: Color = Color(0.22, 0.27, 0.36)
const COMMAND_WALL: Color = Color(0.34, 0.42, 0.56)
const INNER_FLOOR: Color = Color(0.2, 0.16, 0.17)
const INNER_WALL: Color = Color(0.36, 0.24, 0.24)
const CONTROL_FLOOR: Color = Color(0.4, 0.46, 0.44)
const CONTROL_WALL: Color = Color(0.52, 0.6, 0.57)
const SCREEN_BLUE: Color = Color(0.35, 0.8, 1.0)
const SCREEN_GREEN: Color = Color(0.4, 1.0, 0.6)
const LAMP_WARM: Color = Color(1.0, 0.9, 0.7)
const LAMP_RED: Color = Color(1.0, 0.25, 0.15)


static func area_rect(area: Dictionary) -> Rect2:
	return Rect2(-HALF_W, float(area["z"]) - float(area["len"]) * 0.5, HALF_W * 2.0, float(area["len"]))


## Display name of the area containing a position ("" outside all areas).
static func location_at(pos: Vector3) -> String:
	for area in AREAS:
		if area_rect(area).has_point(Vector2(pos.x, pos.z)):
			return String(area["name"])
	return ""
