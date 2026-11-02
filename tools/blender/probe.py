"""Dev tool: for several blade angles print hand position and blade direction at key frames (Blender, headless)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import char_lib as L  # noqa: E402
import char_designs as D  # noqa: E402
import anim_clips as A  # noqa: E402

name = "player"
fn, height, bulk = D.DESIGNS[name]
L.reset_scene()
b = L.Builder(name, height=height, bulk=bulk)
fn(b)
mesh_obj, arm = b.finish()
an = L.Animator(arm, b.s)
A.author_all(an)
scn = bpy.context.scene
FR = (("rest", 0.0), ("guard", 0.2), ("light_1", 0.35), ("light_3", 0.35), ("heavy", 0.17), ("heavy", 0.35),
      ("sprint_attack", 0.35), ("spin", 0.35))
angles = [float(a) for a in sys.argv[sys.argv.index("--") + 1:]] if "--" in sys.argv else [28.0]
for ang in angles:
    sw = L.add_preview_weapon(b, 0.9, angle=ang)
    out = []
    for clip, frac in FR:
        for tr in arm.animation_data.nla_tracks:
            tr.mute = (clip == "rest") or tr.name != clip
        if clip == "rest":
            for pb in arm.pose.bones:
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.location = (0, 0, 0)
            scn.frame_set(1)
        else:
            f0, f1 = an.actions[clip].frame_range
            scn.frame_set(int(round(f0 + (f1 - f0) * frac)))
        arm.update_tag()
        scn.frame_set(scn.frame_current + 1)
        scn.frame_set(scn.frame_current - 1)
        dg = bpy.context.evaluated_depsgraph_get()
        swe = sw.evaluated_get(dg)
        o = swe.matrix_world.translation
        d = ((swe.matrix_world @ Vector((0, 0, -1))) - o).normalized()
        out.append("%s@%.2f:f%+.2f/u%+.2f" % (clip, frac, d.y, d.z))
    print("PROBE angle=%+4.0f  " % ang + "  ".join(out))
    bpy.data.objects.remove(sw)
