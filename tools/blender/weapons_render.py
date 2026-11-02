"""Renders a contact sheet of the weapon and armor GLBs (front view + three-quarter view).

    blender --background --python tools/blender/weapons_render.py -- <output_dir>

Imports the exported GLBs (so it also proves they load), stands each weapon upright with the pommel on
the floor line, and uses the Workbench engine with vertex-colour shading (cheap, no GPU features needed).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ITEMS = ["improvised_blade", "combat_knife", "iron_sword", "military_machete", "katana", "tactical_sword",
         "claymore", "warden_blade"]
OUT_DIR = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else os.path.join(ROOT, "build")
SPACING = 0.42


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def world_bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for corner in o.bound_box:
            p = o.matrix_world @ Vector(corner)
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    return lo, hi


def place(objs, x, rot_x=0.0, rot_z=0.0, floor=True):
    """Parent to an empty so rotation/placement is simple, then stand it up and set it on the floor line."""
    root = bpy.data.objects.new("root", None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        if o.parent is None:
            o.parent = root
    root.rotation_euler = (rot_x, 0.0, rot_z)
    bpy.context.view_layer.update()
    lo, hi = world_bounds(objs)
    root.location = (x - (lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z if floor else 0.0)
    bpy.context.view_layer.update()
    return root


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 780
    scene.render.image_settings.file_format = "PNG"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "VERTEX"
    shading.show_object_outline = True
    world = bpy.data.worlds.new("w")
    world.color = (0.16, 0.18, 0.2)
    scene.world = world
    return scene


def add_camera(name, loc, target, ortho_scale):
    cam_data = bpy.data.cameras.new(name)
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho_scale
    cam = bpy.data.objects.new(name, cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = loc
    aim = bpy.data.objects.new(name + "_aim", None)
    aim.location = target
    bpy.context.scene.collection.objects.link(aim)
    track = cam.constraints.new("TRACK_TO")
    track.target = aim
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"
    return cam


def main():
    scene = setup_scene()
    os.makedirs(OUT_DIR, exist_ok=True)
    x = 0.0
    for item in ITEMS:
        objs = import_glb(os.path.join(ROOT, "assets", "weapons", item + ".glb"))
        # blade (+Y after import) -> up (+Z): rotate +90 degrees about X
        place(objs, x, rot_x=math.pi / 2.0)
        x += SPACING
    plate = import_glb(os.path.join(ROOT, "assets", "armor", "warden_plate.glb"))
    place(plate, x + 0.15, rot_z=math.pi, floor=True)  # front (+Y) toward the camera at -Y
    centre_x = (x + 0.1) * 0.5
    width = x + 1.0
    height_mid = 0.78
    shots = {
        "front": ((centre_x, -6.0, height_mid), (centre_x, 0.0, height_mid)),
        "three_quarter": ((centre_x - 3.4, -4.6, height_mid + 1.4), (centre_x, 0.0, height_mid)),
    }
    for name, (loc, target) in shots.items():
        cam = add_camera("cam_" + name, loc, target, width)
        scene.camera = cam
        scene.render.filepath = os.path.join(OUT_DIR, "weapons_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("RENDERED", scene.render.filepath)


if __name__ == "__main__":
    main()
