class_name EnvironmentPreset
extends Resource
## Sky, sun, fog, ambient and tonemap values for one region. Applied to the persistent WorldEnvironment and
## DirectionalLight3D by EnvironmentPresets; `outpost_17` is authored equal to the look in Main.tscn.

@export var id: StringName = &""
@export_group("Sky")
@export var sky_top: Color = Color(0.3, 0.5, 0.72)
@export var sky_horizon: Color = Color(0.8, 0.8, 0.74)
@export var ground_bottom: Color = Color(0.32, 0.27, 0.26)
@export var ground_horizon: Color = Color(0.78, 0.76, 0.68)
@export_group("Sun")
@export var sun_color: Color = Color(1.0, 0.88, 0.72)
@export var sun_energy: float = 1.1
## Degrees. Pitch is negative when the sun is above the horizon.
@export var sun_pitch: float = -24.0
@export var sun_yaw: float = -58.0
@export var shadow_distance: float = 40.0
@export_group("Ambient")
@export var ambient_color: Color = Color(0.55, 0.64, 0.74)
@export var ambient_energy: float = 0.55
@export var ambient_sky_contribution: float = 0.85
@export_group("Fog")
@export var fog_color: Color = Color(0.72, 0.78, 0.76)
@export var fog_density: float = 0.0065
@export var fog_sky_affect: float = 0.45
@export_group("Grade")
@export var tonemap_exposure: float = 0.85
@export var glow_enabled: bool = false


## Numeric view of the values that are tweened (colours as Color, the rest as floats).
func values() -> Dictionary:
	return {
		"sky_top": sky_top, "sky_horizon": sky_horizon, "ground_bottom": ground_bottom,
		"ground_horizon": ground_horizon, "sun_color": sun_color, "sun_energy": sun_energy,
		"sun_pitch": sun_pitch, "sun_yaw": sun_yaw, "shadow_distance": shadow_distance,
		"ambient_color": ambient_color, "ambient_energy": ambient_energy,
		"ambient_sky_contribution": ambient_sky_contribution, "fog_color": fog_color,
		"fog_density": fog_density, "fog_sky_affect": fog_sky_affect,
		"tonemap_exposure": tonemap_exposure, "glow_enabled": glow_enabled,
	}
