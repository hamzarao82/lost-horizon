class_name OpeningTimeline
extends RefCounted
## The twelve scenes of the opening cinematic, as data, so durations and camera framing can be tuned
## without touching the player script. Camera positions and look targets are LOCAL to the boat origin
## (the boat itself moves and rocks; the camera rig is parented so a moving boat still reads as "on board").
## `storm` is the intensity (0..1) this scene settles at; it is held constant through scene 1-4 duplicates
## of the same number and rises from scene 5 onward, so the climb is readable.

const SCENES: Array[Dictionary] = [
	{"id": &"aerial", "duration": 5.0, "cam_pos": Vector3(0.0, 9.0, 10.0), "cam_look": Vector3(0.0, 0.5, -6.0), "storm": 0.0},
	{"id": &"tracking", "duration": 5.0, "cam_pos": Vector3(3.2, 1.6, 0.4), "cam_look": Vector3(0.0, 1.1, -3.0), "storm": 0.0},
	{"id": &"bag_closeup", "duration": 4.0, "cam_pos": Vector3(0.35, 1.15, -1.55), "cam_look": Vector3(0.1, 0.95, -2.1), "storm": 0.0},
	{"id": &"face_closeup", "duration": 4.0, "cam_pos": Vector3(0.55, 1.75, -1.65), "cam_look": Vector3(0.0, 1.6, -2.6), "storm": 0.0},
	{"id": &"clouds_appear", "duration": 4.0, "cam_pos": Vector3(-3.2, 1.4, 3.4), "cam_look": Vector3(0.0, 1.0, -4.0), "storm": 0.15},
	{"id": &"storm_builds", "duration": 5.0, "cam_pos": Vector3(4.0, 2.4, 4.2), "cam_look": Vector3(0.0, 1.0, -2.6), "storm": 0.4},
	{"id": &"struggle_wheel", "duration": 5.0, "cam_pos": Vector3(0.9, 1.9, -0.9), "cam_look": Vector3(0.0, 1.25, -2.6), "storm": 0.55},
	{"id": &"waves_hit", "duration": 5.0, "cam_pos": Vector3(-2.6, 0.9, 2.6), "cam_look": Vector3(0.0, 0.9, -2.6), "storm": 0.7},
	{"id": &"overwhelmed", "duration": 5.0, "cam_pos": Vector3(0.0, 3.4, 5.2), "cam_look": Vector3(0.0, 0.2, -2.6), "storm": 0.9},
	{"id": &"thrown_overboard", "duration": 4.0, "cam_pos": Vector3(1.1, 0.4, -0.8), "cam_look": Vector3(0.0, 0.0, -1.6), "storm": 1.0},
	{"id": &"to_black", "duration": 1.5, "cam_pos": Vector3(0.0, 0.0, 0.0), "cam_look": Vector3(0.0, 0.0, -1.0), "storm": 1.0},
	{"id": &"ambience_crossfade", "duration": 3.0, "cam_pos": Vector3(0.0, 0.01, 0.0), "cam_look": Vector3(0.0, 0.0, -1.0), "storm": 1.0},
]


static func total_duration() -> float:
	var sum := 0.0
	for scene in SCENES:
		sum += float(scene["duration"])
	return sum


## The scene index active at `t` seconds into the timeline, and how far through it (0..1).
static func scene_at(t: float) -> Dictionary:
	var elapsed := 0.0
	for i in SCENES.size():
		var duration: float = SCENES[i]["duration"]
		if t < elapsed + duration or i == SCENES.size() - 1:
			var progress := clampf((t - elapsed) / maxf(duration, 0.001), 0.0, 1.0)
			return {"index": i, "scene": SCENES[i], "progress": progress}
		elapsed += duration
	return {"index": SCENES.size() - 1, "scene": SCENES[SCENES.size() - 1], "progress": 1.0}
