"""Builds the worn-gear models: assets/armor/combat_helmet.glb, tactical_gloves.glb, field_boots.glb.

    blender --background --python tools/blender/make_gear.py

Each model's origin is the head of the bone it is worn on (Head, Hand_R/Hand_L, Foot_R/Foot_L) of the
1.8 m player rig in rest pose. Godot axes after export: +Y up, front toward -Z (built facing Blender +Y).
Gloves and boots are symmetric about x, so one model serves both sides. Vertex colours, one material.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import props_lib as P  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "armor")

OLIVE = (0.16, 0.19, 0.12)
DARK = (0.07, 0.07, 0.08)
STEEL = (0.26, 0.27, 0.30)
LEATHER = (0.22, 0.14, 0.08)
STRAP = (0.05, 0.05, 0.06)


def export(parts, name):
    obj = P.join(parts, name)
    P.finalize(obj)
    path = os.path.join(OUT_DIR, name + ".glb")
    os.makedirs(OUT_DIR, exist_ok=True)
    P.export_glb(path, [obj])
    print("BUILT %s tris=%d -> %s" % (name, P.tri_count(obj), path))


def helmet():
    P.new_scene()
    parts = []
    # dome sits on the skull (head spans about 0 .. 0.24 above the Head bone)
    parts.append(P.sphere("dome", 0.135, loc=(0, -0.005, 0.135), scale=(1.0, 1.08, 0.78), segments=10, rings=6, color=OLIVE))
    # rim around the brow and the back of the head, leaving the face open
    parts.append(P.cylinder("rim", 0.14, 0.03, loc=(0, -0.005, 0.082), verts=10, color=DARK))
    # brow visor and a small steel plate on the front
    parts.append(P.box("visor", (0.2, 0.05, 0.016), loc=(0, 0.125, 0.105), rot=(-0.25, 0, 0), color=OLIVE))
    parts.append(P.box("badge", (0.05, 0.012, 0.04), loc=(0, 0.138, 0.155), color=STEEL))
    # chin strap bars at both sides
    for sx in (-1.0, 1.0):
        parts.append(P.box("strap", (0.012, 0.02, 0.1), loc=(0.125 * sx, 0.02, 0.03), color=STRAP))
    export(parts, "combat_helmet")


def gloves():
    P.new_scene()
    parts = []
    # fist block just below the wrist (hand extends down the bone: -Z in Blender before export)
    parts.append(P.box("fist", (0.09, 0.075, 0.095), loc=(0, 0.0, -0.075), color=LEATHER))
    # knuckle plate and cuff
    parts.append(P.box("knuckles", (0.095, 0.02, 0.04), loc=(0, 0.045, -0.095), color=STEEL))
    parts.append(P.cylinder("cuff", 0.052, 0.045, loc=(0, 0.0, -0.005), verts=8, color=DARK))
    export(parts, "tactical_gloves")


def boots():
    P.new_scene()
    parts = []
    # foot bone head is the ankle (about 0.09 above the ground); the toes point to +Y
    parts.append(P.box("sole", (0.1, 0.27, 0.035), loc=(0, 0.045, -0.075), color=DARK))
    parts.append(P.box("foot", (0.09, 0.24, 0.07), loc=(0, 0.05, -0.03), color=LEATHER))
    parts.append(P.cylinder("shaft", 0.062, 0.17, loc=(0, -0.015, 0.075), verts=8, color=LEATHER))
    parts.append(P.cylinder("cuff", 0.066, 0.025, loc=(0, -0.015, 0.165), verts=8, color=STRAP))
    parts.append(P.box("toe_cap", (0.09, 0.06, 0.05), loc=(0, 0.165, -0.04), color=STEEL))
    export(parts, "field_boots")


if __name__ == "__main__":
    helmet()
    gloves()
    boots()
