class_name ResearchComplexZones
extends RefCounted
## Layout constants and the colour identity of each zone. Local coordinates: the player arrives at the
## south end (+z) and the facility runs north (-z). X runs east. Floors are at y = 0 except the
## underground exit (y = UNDER_Y).

const HALF_W: float = 30.0
const WALL_H: float = 4.4
const Z_SOUTH: float = 52.0      # perimeter fence, the road to Blackwood
const Z_A_B: float = -10.0       # admin facade (security door: admin credential)
const Z_B_C: float = -46.0       # medical door (medical credential)
const Z_C_D: float = -84.0       # containment door (medical credential)
const Z_D_E: float = -128.0      # laboratory door (lab credential)
const Z_END: float = -172.0      # back wall of the laboratory; the service hatch is in it
const UNDER_Y: float = -4.0
const UNDER_END_Z: float = -204.0
const HATCH_X: float = 6.0

## id, display name, centre z, length, y of the trigger centre
const AREAS: Array[Dictionary] = [
	{"id": &"rc_perimeter", "name": "Research Perimeter", "z": 21.0, "len": 62.0, "y": 3.0},
	{"id": &"rc_admin_wing", "name": "Administration Wing", "z": -28.0, "len": 36.0, "y": 3.0},
	{"id": &"rc_medical_wing", "name": "Medical Research Wing", "z": -65.0, "len": 38.0, "y": 3.0},
	{"id": &"rc_containment", "name": "Containment Sector", "z": -106.0, "len": 44.0, "y": 3.0},
	{"id": &"rc_lab", "name": "Central Research Laboratory", "z": -150.0, "len": 44.0, "y": 3.0},
	{"id": &"rc_underground", "name": "Underground Exit", "z": -190.0, "len": 28.0, "y": -2.0},
]

const GROUND: Color = Color(0.36, 0.33, 0.28)
const ASPHALT: Color = Color(0.2, 0.21, 0.23)
const CONCRETE: Color = Color(0.56, 0.56, 0.54)
const FENCE: Color = Color(0.42, 0.45, 0.47)
const HAZARD: Color = Color(0.92, 0.75, 0.1)
const METAL: Color = Color(0.3, 0.33, 0.36)
const WOOD: Color = Color(0.42, 0.32, 0.2)
const OLIVE: Color = Color(0.3, 0.36, 0.25)
const ADMIN_FLOOR: Color = Color(0.45, 0.46, 0.48)
const ADMIN_WALL: Color = Color(0.66, 0.68, 0.7)
const MEDICAL_FLOOR: Color = Color(0.68, 0.76, 0.72)
const MEDICAL_WALL: Color = Color(0.82, 0.9, 0.86)
const CELL_FLOOR: Color = Color(0.3, 0.19, 0.17)
const CELL_WALL: Color = Color(0.46, 0.3, 0.26)
const LAB_FLOOR: Color = Color(0.27, 0.3, 0.37)
const LAB_WALL: Color = Color(0.4, 0.45, 0.56)
const UNDER_FLOOR: Color = Color(0.2, 0.2, 0.22)
const UNDER_WALL: Color = Color(0.3, 0.3, 0.33)
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
