"""Preview sheets of the combo clips (with the sword drawn):
blender --background --python tools/blender/combo_preview.py -- --render <dir>"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,F401
import char_lib as L  # noqa: E402
import char_designs as D  # noqa: E402
import anim_clips as A  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[argv.index("--render") + 1] if "--render" in argv else "combo_preview"
os.makedirs(out, exist_ok=True)
fn, height, bulk = D.DESIGNS["player"]
L.reset_scene()
b = L.Builder("player", height=height, bulk=bulk)
fn(b)
mesh_obj, arm = b.finish()
an = L.Animator(arm, b.s)
A.author_all(an)
A.author_story(an)
A.author_combo(an)
sheets = {
    "light_chain_a": [("light_2", 0.35, "three"), ("light_3", 0.35, "three"), ("light_4", 0.2, "three"), ("light_4", 0.35, "three")],
    "light_chain_b": [("light_4", 0.55, "side"), ("light_5", 0.24, "three"), ("light_5", 0.35, "three"), ("light_5", 0.62, "three")],
    "heavy_chain_a": [("heavy", 0.22, "side"), ("heavy", 0.35, "side"), ("heavy_2", 0.24, "three"), ("heavy_2", 0.35, "three")],
    "heavy_chain_b": [("heavy_2", 0.62, "three"), ("heavy_3", 0.28, "side"), ("heavy_3", 0.35, "side"), ("heavy_3", 0.65, "side")],
}
for name, shots in sheets.items():
    L.render_sheet(b, an, os.path.join(out, name + ".png"), shots, weapon=True)
    print("SHEET", name)
