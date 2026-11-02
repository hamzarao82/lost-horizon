class_name ProceduralVisual
extends CharacterVisual
## Adapter over the code-built HumanoidRig. The rig animates itself from the body's state, so this
## class only decides whether it is shown. It is the fallback whenever a model is missing or broken.

var rig: HumanoidRig


func bind(new_body: CharacterBody3D) -> void:
	super.bind(new_body)
	if rig == null and new_body:
		var visual_root := new_body.get_node_or_null("VisualRoot")
		if visual_root:
			rig = visual_root.get_node_or_null("HumanoidRig") as HumanoidRig


func is_ready() -> bool:
	return rig != null


func set_active(active: bool) -> void:
	if rig:
		rig.set_active(active)
