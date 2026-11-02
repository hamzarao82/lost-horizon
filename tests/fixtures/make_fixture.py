"""Builds a tiny throwaway humanoid GLB that follows the Milestone 002 art contract.

Run:  blender --background --python tests/fixtures/make_fixture.py -- <output.glb>

Contract (what the real character files must also satisfy):
  * one armature with the bones listed in BONES, 1.8 m tall, feet at z = 0 (Blender), facing +Y in Blender
    (which glTF/Godot turn into -Z, the Godot forward direction)
  * one mesh skinned to it with a vertex-colour attribute
  * 30 fps in-place clips named in CLIPS
This fixture only exists so the adapter can be tested before the art arrives. It is not shipped.
"""
import math
import sys

import bpy

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "humanoid_fixture.glb"

# name, parent, head (x, y, z), tail
BONES = [
    ("Hips", None, (0, 0, 0.90), (0, 0, 1.00)),
    ("Spine", "Hips", (0, 0, 1.00), (0, 0, 1.15)),
    ("Chest", "Spine", (0, 0, 1.15), (0, 0, 1.40)),
    ("Neck", "Chest", (0, 0, 1.40), (0, 0, 1.50)),
    ("Head", "Neck", (0, 0, 1.50), (0, 0, 1.75)),
    ("UpperArm_L", "Chest", (-0.22, 0, 1.38), (-0.22, 0, 1.12)),
    ("LowerArm_L", "UpperArm_L", (-0.22, 0, 1.12), (-0.22, 0, 0.90)),
    ("Hand_L", "LowerArm_L", (-0.22, 0, 0.90), (-0.22, 0, 0.82)),
    ("UpperArm_R", "Chest", (0.22, 0, 1.38), (0.22, 0, 1.12)),
    ("LowerArm_R", "UpperArm_R", (0.22, 0, 1.12), (0.22, 0, 0.90)),
    ("Hand_R", "LowerArm_R", (0.22, 0, 0.90), (0.22, 0, 0.82)),
    ("UpperLeg_L", "Hips", (-0.1, 0, 0.90), (-0.1, 0, 0.48)),
    ("LowerLeg_L", "UpperLeg_L", (-0.1, 0, 0.48), (-0.1, 0, 0.08)),
    ("Foot_L", "LowerLeg_L", (-0.1, 0, 0.08), (-0.1, 0.15, 0.0)),
    ("UpperLeg_R", "Hips", (0.1, 0, 0.90), (0.1, 0, 0.48)),
    ("LowerLeg_R", "UpperLeg_R", (0.1, 0, 0.48), (0.1, 0, 0.08)),
    ("Foot_R", "LowerLeg_R", (0.1, 0, 0.08), (0.1, 0.15, 0.0)),
]

# clip: (frames at 30 fps, loop, bone swung, axis, angle in degrees)
CLIPS = {
    "idle": (60, True, "Chest", 0, 3), "walk": (30, True, "UpperLeg_L", 0, 30),
    "run": (24, True, "UpperLeg_L", 0, 45), "sprint": (20, True, "UpperLeg_L", 0, 55),
    "jump_start": (12, False, "Hips", 0, -10), "fall": (30, True, "Hips", 0, 5),
    "land": (12, False, "Hips", 0, 15), "light_1": (24, False, "UpperArm_R", 0, -100),
    "light_2": (24, False, "UpperArm_R", 1, 100), "light_3": (30, False, "UpperArm_R", 0, -120),
    "heavy": (36, False, "UpperArm_R", 0, -160), "sprint_attack": (28, False, "UpperArm_R", 0, -90),
    "air_attack": (26, False, "UpperArm_R", 0, -130), "spin": (40, False, "Hips", 2, 360),
    "dodge": (24, False, "Hips", 0, 80), "hit": (14, False, "Chest", 0, 25),
    "death": (40, False, "Hips", 0, -85), "guard": (40, True, "UpperArm_R", 0, -30),
    "slam": (50, False, "UpperArm_R", 0, -150), "flurry": (24, False, "UpperArm_R", 1, 90),
    "shockwave_cast": (40, False, "UpperArm_R", 0, -110), "roar": (45, False, "Head", 0, -25),
}

PIECES = [  # name, bone, center, size (x, y, z), colour
    ("hips", "Hips", (0, 0, 0.95), (0.34, 0.2, 0.16), (0.2, 0.2, 0.25)),
    ("chest", "Chest", (0, 0, 1.25), (0.42, 0.24, 0.40), (0.25, 0.3, 0.2)),
    ("head", "Head", (0, 0, 1.62), (0.22, 0.22, 0.26), (0.85, 0.65, 0.5)),
    ("nose", "Head", (0, 0.13, 1.60), (0.06, 0.08, 0.06), (0.9, 0.2, 0.2)),  # +Y in Blender = Godot -Z
    ("arm_l", "UpperArm_L", (-0.22, 0, 1.12), (0.1, 0.1, 0.5), (0.25, 0.3, 0.2)),
    ("arm_r", "UpperArm_R", (0.22, 0, 1.12), (0.1, 0.1, 0.5), (0.25, 0.3, 0.2)),
    ("leg_l", "UpperLeg_L", (-0.1, 0, 0.48), (0.14, 0.14, 0.9), (0.15, 0.15, 0.2)),
    ("leg_r", "UpperLeg_R", (0.1, 0, 0.48), (0.14, 0.14, 0.9), (0.15, 0.15, 0.2)),
]


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30

    arm_data = bpy.data.armatures.new("Armature")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    for name, parent, head, tail in BONES:
        bone = arm_data.edit_bones.new(name)
        bone.head, bone.tail = head, tail
        if parent:
            bone.parent = arm_data.edit_bones[parent]
            bone.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")

    material = bpy.data.materials.new("CharacterMaterial")
    objs = []
    for name, bone, center, size, color in PIECES:
        bpy.ops.mesh.primitive_cube_add(size=1, location=center)
        obj = bpy.context.active_object
        obj.name = name
        obj.scale = size
        bpy.ops.object.transform_apply(location=True, scale=True)
        group = obj.vertex_groups.new(name=bone)
        group.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
        attr = obj.data.color_attributes.new("Col", "BYTE_COLOR", "POINT")
        for i in range(len(obj.data.vertices)):
            attr.data[i].color = (*color, 1.0)
        obj.data.materials.append(material)
        objs.append(obj)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objs:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.active_object
    body.name = "Body"
    body.parent = arm_obj
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj

    arm_obj.animation_data_create()
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    for clip, (frames, loop, bone_name, axis, degrees) in CLIPS.items():
        action = bpy.data.actions.new(clip)
        action.use_fake_user = True
        arm_obj.animation_data.action = action
        pose_bone = arm_obj.pose.bones[bone_name]
        pose_bone.rotation_mode = "XYZ"
        for frame, factor in ((1, 0.0), (1 + frames // 2, 1.0), (1 + frames, 0.0 if loop else 0.6)):
            pose_bone.rotation_euler = [0.0, 0.0, 0.0]
            pose_bone.rotation_euler[axis] = math.radians(degrees) * factor
            pose_bone.keyframe_insert("rotation_euler", frame=frame)
        # make every clip a few keys on Hips too so root tracks exist
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_obj.animation_data.action = None

    bpy.ops.export_scene.gltf(
        filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
        export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
        export_vertex_color="ACTIVE", export_active_vertex_color_when_no_material=True,
        export_frame_range=False, export_force_sampling=True, export_optimize_animation_size=True,
    )
    print("FIXTURE_DONE", OUT)


main()
