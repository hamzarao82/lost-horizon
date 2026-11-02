"""Build one character: geometry -> rig -> 22 animation clips -> GLB (+ optional preview sheet)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
import char_lib as L  # noqa: E402
import char_designs as D  # noqa: E402
import anim_clips as A  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "characters")


def _args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    opts = {"render": None}
    for i, a in enumerate(argv):
        if a == "--render" and i + 1 < len(argv):
            opts["render"] = argv[i + 1]
    return opts


def run(name):
    opts = _args()
    fn, height, bulk = D.DESIGNS[name]
    L.reset_scene()
    b = L.Builder(name, height=height, bulk=bulk)
    fn(b)
    mesh_obj, arm = b.finish()
    an = L.Animator(arm, b.s)
    A.author_all(an)
    path = os.path.join(OUT_DIR, name + ".glb")
    L.export_glb(path, arm, mesh_obj)
    print("CHAR %s tris=%d size_kb=%d" % (name, b.tri_count(), os.path.getsize(path) // 1024))
    _write_socket(name, b)
    if opts["render"]:
        os.makedirs(opts["render"], exist_ok=True)
        L.render_sheet(b, an, os.path.join(opts["render"], name + ".png"), [
            (None, 0.0, "front"), (None, 0.0, "side"), ("light_1", 0.35, "three"), ("heavy", 0.35, "side"),
        ])
    return b, an


def _write_socket(name, b):
    """Merge this character's weapon-socket transform into assets/characters/sockets.json."""
    import json
    path = os.path.join(OUT_DIR, "sockets.json")
    data = {}
    if os.path.exists(path):
        with open(path) as f:
            data = json.load(f)
    data[name] = L.socket_info(b)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
