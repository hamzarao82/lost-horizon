"""Preview sheets of the story clips: blender --background --python tools/blender/story_preview.py -- --render <dir>"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,F401
import char_lib as L  # noqa: E402
import char_designs as D  # noqa: E402
import anim_clips as A  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[argv.index("--render") + 1] if "--render" in argv else "story_preview"
os.makedirs(out, exist_ok=True)
fn, height, bulk = D.DESIGNS["player"]
L.reset_scene()
b = L.Builder("player", height=height, bulk=bulk)
fn(b)
mesh_obj, arm = b.finish()
an = L.Animator(arm, b.s)
A.author_all(an)
A.author_story(an)
sheets = {
    "lying": [("lying_idle", 0.0, "side"), ("wake", 0.3, "side"), ("wake", 0.55, "side"), ("wake", 1.0, "side")],
    "rise": [("sit_up", 0.5, "side"), ("sit_up", 1.0, "side"), ("stand_up", 0.3, "side"), ("stand_up", 0.62, "side")],
    "hurt": [("hold_side", 0.0, "three"), ("hold_side", 0.5, "front"), ("limp_walk", 0.25, "side"), ("limp_walk", 0.75, "side")],
    "hands": [("pickup", 0.28, "side"), ("pickup", 0.5, "side"), ("open_bag", 0.45, "three"), ("open_bag", 0.8, "three")],
}
for name, shots in sheets.items():
    L.render_sheet(b, an, os.path.join(out, name + ".png"), shots, weapon=False)
    print("SHEET", name)
