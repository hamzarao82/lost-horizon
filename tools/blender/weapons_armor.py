"""Builds assets/armor/warden_plate.glb: a black and crimson cuirass with two pauldrons.

    blender --background --python tools/blender/weapons_armor.py

Origin = the Chest bone head of a 1.8 m humanoid in rest pose (about 1.35 m above the feet).
Godot axes after export: +Y up, front of the chest toward -Z (so it is built facing Blender +Y).
Vertex colours only, one material.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import props_lib as P  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "armor", "warden_plate.glb")

BLACK = (0.1, 0.1, 0.12)
STEEL = (0.2, 0.2, 0.23)
CRIMSON = (0.7, 0.05, 0.07)
SEGMENTS = 10


def torso_ring(z, rx, ry, front=1.12):
    """Elliptical cross-section at height z; the front (+Y) bulges for a breastplate."""
    pts = []
    for i in range(SEGMENTS):
        a = 2.0 * math.pi * i / SEGMENTS
        y = math.sin(a) * ry
        pts.append((math.cos(a) * rx, y * (front if y > 0 else 1.0), z))
    return pts


def build():
    P.new_scene()
    parts = []

    # cuirass shell: waist -> chest -> shoulders (open at both ends, like a real plate)
    levels = [(-0.40, 0.17, 0.105), (-0.22, 0.20, 0.12), (0.0, 0.225, 0.13), (0.11, 0.205, 0.115)]
    parts.append(P.loft("cuirass", [torso_ring(z, rx, ry) for z, rx, ry in levels], cap_start=False, color=BLACK))
    # inner lining so the open shell is not see-through from inside
    parts.append(P.loft("lining", [torso_ring(z, rx * 0.97, ry * 0.97, front=1.0) for z, rx, ry in reversed(levels)],
                        cap_start=False, color=(0.05, 0.03, 0.03)))
    # crimson trim: hem and neckline
    parts.append(P.loft("hem", [torso_ring(-0.405, 0.172, 0.108), torso_ring(-0.37, 0.175, 0.11)],
                        cap_start=False, color=CRIMSON))
    parts.append(P.loft("neck_trim", [torso_ring(0.1, 0.208, 0.118), torso_ring(0.125, 0.205, 0.116)],
                        cap_start=False, color=CRIMSON))
    # chest emblem (cross) and a sternum ridge
    parts.append(P.box("emblem_v", (0.034, 0.012, 0.17), loc=(0, 0.148, -0.05), color=CRIMSON))
    parts.append(P.box("emblem_h", (0.11, 0.012, 0.034), loc=(0, 0.148, -0.0), color=CRIMSON))
    parts.append(P.box("ridge", (0.03, 0.02, 0.3), loc=(0, 0.138, -0.18), color=STEEL))
    # gorget (neck guard)
    parts.append(P.cylinder("gorget", 0.1, 0.05, loc=(0, 0.0, 0.135), verts=SEGMENTS, radius2=0.085, color=BLACK))
    parts.append(P.cylinder("gorget_trim", 0.101, 0.012, loc=(0, 0.0, 0.158), verts=SEGMENTS, color=CRIMSON))

    # pauldrons
    for side, sx in (("l", -1.0), ("r", 1.0)):
        x = 0.245 * sx
        tilt = 0.35 * sx
        parts.append(P.sphere("pauldron_" + side, 0.1, loc=(x, 0.0, 0.07), rot=(0, tilt, 0),
                              scale=(1.0, 0.9, 0.55), segments=8, rings=5, color=BLACK))
        parts.append(P.sphere("pauldron_low_" + side, 0.105, loc=(x + 0.015 * sx, 0.0, 0.02), rot=(0, tilt, 0),
                              scale=(1.0, 0.85, 0.4), segments=8, rings=4, color=STEEL))
        parts.append(P.cylinder("pauldron_trim_" + side, 0.104, 0.012, loc=(x + 0.012 * sx, 0.0, 0.012),
                                rot=(0, tilt, 0), verts=SEGMENTS, color=CRIMSON))
        parts.append(P.cylinder("spike_" + side, 0.022, 0.09, loc=(x + 0.015 * sx, 0.0, 0.13), rot=(0, tilt, 0),
                                verts=5, radius2=0.004, color=(0.14, 0.14, 0.16)))
    obj = P.join(parts, "warden_plate")
    P.finalize(obj)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    P.export_glb(OUT, [obj])
    print("BUILT warden_plate tris=%d -> %s" % (P.tri_count(obj), OUT))


if __name__ == "__main__":
    build()
