"""Dev tool: render all five characters side by side (front view, rest pose) to judge class colours.
blender --background --python tools/blender/lineup.py -- <out.png>"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
import char_lib as L  # noqa: E402
import char_designs as D  # noqa: E402

out = sys.argv[sys.argv.index("--") + 1]
L.reset_scene()
order = ["player", "soldier", "heavy", "elite", "warden"]
for i, name in enumerate(order):
    fn, height, bulk = D.DESIGNS[name]
    b = L.Builder(name, height=height, bulk=bulk)
    fn(b)
    mesh_obj, arm = b.finish()
    arm.location.x = (i - 2) * 1.25
    arm.rotation_mode = 'XYZ'
scn = bpy.context.scene
scn.render.engine = 'BLENDER_WORKBENCH'
scn.render.resolution_x, scn.render.resolution_y = 1500, 640
scn.display.shading.light = 'STUDIO'
scn.display.shading.color_type = 'VERTEX'
scn.view_settings.view_transform = 'Standard'
L._world()
cam = L._camera((0, 6.0, 1.12), (0, 0, 1.12), 2.4)
cam.data.ortho_scale = 7.2
scn.camera = cam
scn.render.filepath = out
bpy.ops.render.render(write_still=True)
