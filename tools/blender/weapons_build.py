"""Builds the 8 original low-poly weapon models as GLB files.

    blender --background --python tools/blender/weapons_build.py

Output: assets/weapons/<item_id>.glb  (one mesh, one material, vertex colours only)

Conventions (see props_lib.py): built along Blender +Y (= Godot -Z, forward). Origin is the CENTRE OF THE
GRIP. The blade is a thin plate: width along X (edges point sideways, which is what a horizontal slash needs),
thickness along Z (up). Single-edge blades have the spine on -X and the edge on +X.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import props_lib as P  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "weapons")
HALF_PI = math.pi / 2.0

STEEL = (0.62, 0.64, 0.67)
DARK = (0.09, 0.09, 0.1)


def along_y(name, radius, length, y, color, verts=8, radius2=None):
    """Cylinder lying along Y, spanning y .. y+length. radius is the end at +Y... (symmetric by default)."""
    return P.cylinder(name, radius, length, loc=(0, y + length * 0.5, 0), rot=(HALF_PI, 0, 0), verts=verts,
                      radius2=radius2, color=color)


def ring_verts(y, xl, xr, ht, kind):
    """Cross-section of a blade at height y. xl = spine side (-X), xr = edge side (+X)."""
    if kind == "diamond":  # double edged: points at both sides, ridge along the middle
        xm = (xl + xr) * 0.5
        return [(xr, y, 0.0), (xm, y, ht), (xl, y, 0.0), (xm, y, -ht)]
    if kind == "single":  # one edge (+X), thick flat spine (-X)
        return [(xr, y, 0.0), (xr - (xr - xl) * 0.55, y, ht), (xl, y, ht * 0.7),
                (xl, y, -ht * 0.7), (xr - (xr - xl) * 0.55, y, -ht)]
    raise ValueError(kind)


def blade(name, y0, length, stations, kind, color, curve=0.0, tip=None, cap_end=False):
    """Loft a blade. stations: [(frac, xl, xr, ht)], frac 0..1 along length. curve bends the blade
    sideways (positive = toward +X) quadratically. tip: (x, z) point at frac 1.0, or None."""
    rings = []
    for frac, xl, xr, ht in stations:
        off = curve * frac * frac
        rings.append(ring_verts(y0 + frac * length, xl + off, xr + off, ht, kind))
    tip_point = None
    if tip is not None:
        tip_point = (tip[0] + curve, y0 + length, tip[1])
    return P.loft(name, rings, tip=tip_point, cap_start=True, color=color, cap_end=cap_end)


def wraps(prefix, y_start, y_end, count, radius, color, length=0.012):
    """Evenly spaced thin bands around the grip."""
    parts = []
    for i in range(count):
        y = y_start + (y_end - y_start) * (i + 0.5) / count - length * 0.5
        parts.append(along_y("%s_%d" % (prefix, i), radius, length, y, color, verts=8))
    return parts


def build(spec):
    P.new_scene()
    g, pommel, gt = spec["grip"], spec["pommel"], spec["guard_t"]
    back = g * 0.5 + pommel
    front_tip = spec["L"] - back
    y_guard = g * 0.5
    y_blade = y_guard + gt + spec.get("collar", 0.0)
    blade_len = front_tip - y_blade
    parts = []

    # grip with wraps
    parts.append(along_y("grip", spec["grip_r"], g, -g * 0.5, spec["grip_color"], verts=8))
    parts += wraps("wrap", -g * 0.5 + 0.01, g * 0.5 - 0.01, spec["wraps"], spec["grip_r"] + 0.003,
                   spec["wrap_color"], length=spec.get("wrap_len", 0.012))
    parts += spec["extras"](g, pommel, gt, y_blade, blade_len)
    parts += spec["blade_fn"](y_blade, blade_len)

    obj = P.join(parts, spec["id"])
    P.finalize(obj)
    path = os.path.join(OUT, spec["id"] + ".glb")
    P.export_glb(path, [obj])
    print("BUILT %-18s L=%.3f tris=%d -> %s" % (spec["id"], spec["L"], P.tri_count(obj), path))
    return obj


# ----------------------------------------------------------------------------- per weapon pieces

def improvised(y0, length):
    # crooked sharpened scrap: a rusty base section and a brighter, slightly bent tip section
    rust = blade("rust", y0, length * 0.55,
                 [(0.0, -0.034, 0.034, 0.007), (0.5, -0.034, 0.036, 0.006), (1.0, -0.03, 0.03, 0.006)],
                 "diamond", (0.42, 0.27, 0.18), curve=0.012)
    steel = P.loft("steel_tip", [ring_verts(y0 + length * 0.55, -0.018, 0.042, 0.006, "diamond"),
                                 ring_verts(y0 + length * 0.85, -0.004, 0.04, 0.005, "diamond")],
                   tip=(0.026, y0 + length, 0.0), cap_start=True, color=(0.55, 0.52, 0.48))
    return [rust, steel]


def improvised_extras(g, p, gt, y_blade, blade_len):
    bolt = P.box("bolt", (0.07, gt, 0.02), loc=(0, g * 0.5 + gt * 0.5, 0), rot=(0, 0, 0.18), color=(0.35, 0.22, 0.14))
    knob = along_y("knob", 0.022, p, -g * 0.5 - p, (0.3, 0.2, 0.14), verts=6)
    return [bolt, knob]


def knife_blade(y0, length):
    b = blade("blade", y0, length,
              [(0.0, -0.014, 0.016, 0.0035), (0.55, -0.014, 0.02, 0.0035), (0.85, -0.012, 0.016, 0.003)],
              "single", (0.1, 0.1, 0.12), tip=(-0.002, 0.0))
    edge = P.box("edge", (0.004, length * 0.78, 0.0025), loc=(0.019, y0 + length * 0.42, 0), color=(0.55, 0.57, 0.6))
    return [b, edge]


def knife_extras(g, p, gt, y_blade, blade_len):
    guard = P.box("guard", (0.052, gt, 0.03), loc=(0, g * 0.5 + gt * 0.5, 0), color=(0.5, 0.52, 0.55))
    cap = along_y("cap", 0.018, p, -g * 0.5 - p, (0.5, 0.52, 0.55), verts=6)
    return [guard, cap]


def iron_blade(y0, length):
    return [blade("blade", y0, length,
                  [(0.0, -0.027, 0.027, 0.006), (0.55, -0.025, 0.025, 0.006), (0.9, -0.019, 0.019, 0.005)],
                  "diamond", (0.6, 0.62, 0.65), tip=(0.0, 0.0))]


def iron_extras(g, p, gt, y_blade, blade_len):
    guard = P.box("guard", (0.2, gt, 0.032), loc=(0, g * 0.5 + gt * 0.5, 0), color=(0.3, 0.3, 0.33))
    cap_l = P.box("cap_l", (0.02, gt * 1.2, 0.04), loc=(-0.1, g * 0.5 + gt * 0.5, 0), color=(0.3, 0.3, 0.33))
    cap_r = P.box("cap_r", (0.02, gt * 1.2, 0.04), loc=(0.1, g * 0.5 + gt * 0.5, 0), color=(0.3, 0.3, 0.33))
    disc = along_y("pommel", 0.03, p, -g * 0.5 - p, (0.3, 0.3, 0.33), verts=8)
    return [guard, cap_l, cap_r, disc]


def machete_blade(y0, length):
    return [blade("blade", y0, length,
                  [(0.0, -0.025, 0.025, 0.0045), (0.35, -0.025, 0.032, 0.0045), (0.7, -0.025, 0.05, 0.0045),
                   (0.93, -0.022, 0.044, 0.004)],
                  "single", (0.3, 0.34, 0.27), curve=-0.035, tip=(0.03, 0.0))]


def machete_extras(g, p, gt, y_blade, blade_len):
    hump = P.box("guard", (0.065, gt, 0.045), loc=(0.01, g * 0.5 + gt * 0.5, 0), color=(0.1, 0.12, 0.08))
    block = along_y("pommel", 0.025, p, -g * 0.5 - p, (0.1, 0.12, 0.08), verts=6)
    return [hump, block]


def katana_blade(y0, length):
    b = blade("blade", y0, length,
              [(0.0, -0.0095, 0.0175, 0.0042), (0.6, -0.0085, 0.0165, 0.0038), (0.9, -0.007, 0.014, 0.0034)],
              "single", (0.82, 0.85, 0.9), curve=-0.034, tip=(0.004, 0.0))
    return [b]


def katana_extras(g, p, gt, y_blade, blade_len):
    tsuba = along_y("tsuba", 0.045, gt, g * 0.5, (0.5, 0.4, 0.18), verts=10)
    habaki = P.box("habaki", (0.022, 0.03, 0.011), loc=(0.004, g * 0.5 + gt + 0.015, 0), color=(0.72, 0.6, 0.27))
    kashira = along_y("kashira", 0.017, p, -g * 0.5 - p, (0.5, 0.4, 0.18), verts=8)
    return [tsuba, habaki, kashira]


def tactical_blade(y0, length):
    b = blade("blade", y0, length,
              [(0.0, -0.028, 0.028, 0.008), (0.7, -0.027, 0.027, 0.007), (0.93, -0.02, 0.02, 0.006)],
              "diamond", (0.1, 0.1, 0.12), tip=(0.0, 0.0))
    rails = [P.box("rail_%d" % i, (0.014, 0.07, 0.008), loc=(0, y0 + length * f, 0.0125), color=(0.38, 0.38, 0.4))
             for i, f in enumerate((0.2, 0.42, 0.64))]
    return [b] + rails


def tactical_extras(g, p, gt, y_blade, blade_len):
    y = g * 0.5 + gt * 0.5
    centre = P.box("guard", (0.08, gt, 0.045), loc=(0, y, 0), color=(0.13, 0.13, 0.15))
    left = P.box("wing_l", (0.07, gt * 0.8, 0.03), loc=(-0.07, y, 0), rot=(0, 0, 0.3), color=(0.13, 0.13, 0.15))
    right = P.box("wing_r", (0.07, gt * 0.8, 0.03), loc=(0.07, y, 0), rot=(0, 0, -0.3), color=(0.13, 0.13, 0.15))
    block = P.box("pommel", (0.045, p, 0.045), loc=(0, -g * 0.5 - p * 0.5, 0), color=(0.13, 0.13, 0.15))
    accent = P.box("accent", (0.047, p * 0.4, 0.047), loc=(0, -g * 0.5 - p * 0.5, 0), color=(0.15, 0.32, 0.6))
    return [centre, left, right, block, accent]


def claymore_blade(y0, length):
    b = blade("blade", y0, length,
              [(0.0, -0.042, 0.042, 0.009), (0.55, -0.04, 0.04, 0.009), (0.85, -0.03, 0.03, 0.008),
               (0.95, -0.02, 0.02, 0.006)], "diamond", (0.66, 0.68, 0.72), tip=(0.0, 0.0))
    fuller = P.box("fuller", (0.012, length * 0.6, 0.0035), loc=(0, y0 + length * 0.35, 0.0095), color=(0.4, 0.42, 0.46))
    fuller_b = P.box("fuller_b", (0.012, length * 0.6, 0.0035), loc=(0, y0 + length * 0.35, -0.0095), color=(0.4, 0.42, 0.46))
    return [b, fuller, fuller_b]


def claymore_extras(g, p, gt, y_blade, blade_len):
    y = g * 0.5 + gt * 0.5
    bar = P.box("guard", (0.3, gt, 0.035), loc=(0, y, 0), color=(0.3, 0.2, 0.1))
    left = P.box("quill_l", (0.09, gt * 1.1, 0.032), loc=(-0.17, y + 0.012, 0), rot=(0, 0, 0.5), color=(0.3, 0.2, 0.1))
    right = P.box("quill_r", (0.09, gt * 1.1, 0.032), loc=(0.17, y + 0.012, 0), rot=(0, 0, -0.5), color=(0.3, 0.2, 0.1))
    ball = along_y("pommel", 0.045, p, -g * 0.5 - p, (0.45, 0.44, 0.42), verts=8)
    return [bar, left, right, ball]


CRIMSON = (0.72, 0.06, 0.07)
WARDEN_STEEL = (0.07, 0.07, 0.08)


def warden_blade(y0, length):
    # slab cleaver: wide, straight edge on +X, thick spine on -X, chamfered tip
    slab = blade("slab", y0, length,
                 [(0.0, -0.15, 0.15, 0.02), (0.9, -0.15, 0.15, 0.02), (1.0, -0.075, 0.15, 0.02)],
                 "single", WARDEN_STEEL, cap_end=True)
    parts = [slab]
    for sign, z in (("t", 0.0215), ("b", -0.0215)):
        parts.append(P.box("inlay_" + sign, (0.035, length * 0.6, 0.004), loc=(0.02, y0 + length * 0.45, z), color=CRIMSON))
    parts.append(P.box("edge_glow", (0.012, length * 0.86, 0.01), loc=(0.146, y0 + length * 0.45, 0), color=(0.85, 0.1, 0.08)))
    for i, f in enumerate((0.25, 0.5, 0.75)):
        spike = P.cylinder("spike_%d" % i, 0.026, 0.085, loc=(-0.15 - 0.03, y0 + length * f, 0), rot=(0, -HALF_PI, 0),
                           verts=4, radius2=0.004, color=(0.12, 0.12, 0.13))
        # cone created along Z: radius1 at -Z; after the rotation about Y the wide end sits at -X? flip so the tip points -X
        parts.append(spike)
    return parts


def warden_extras(g, p, gt, y_blade, blade_len):
    y = g * 0.5 + gt * 0.5
    bar = P.box("guard", (0.22, gt, 0.05), loc=(0, y, 0), color=WARDEN_STEEL)
    cap_l = P.box("cap_l", (0.03, gt * 1.1, 0.056), loc=(-0.11, y, 0), color=CRIMSON)
    cap_r = P.box("cap_r", (0.03, gt * 1.1, 0.056), loc=(0.11, y, 0), color=CRIMSON)
    spike = P.cylinder("pommel_spike", 0.03, p, loc=(0, -g * 0.5 - p * 0.5, 0), rot=(HALF_PI, 0, 0), verts=6,
                       radius2=0.005, color=(0.12, 0.12, 0.13))
    chain = [along_y("chain_%d" % i, 0.034, 0.016, -g * 0.5 + 0.02 + i * (g - 0.05) / 4.0, (0.33, 0.33, 0.35), verts=6)
             for i in range(5)]
    return [bar, cap_l, cap_r, spike] + chain


SPECS = [
    dict(id="improvised_blade", L=0.75, grip=0.20, pommel=0.03, guard_t=0.015, grip_r=0.016, wraps=4,
         grip_color=(0.3, 0.2, 0.13), wrap_color=(0.5, 0.42, 0.3), extras=improvised_extras, blade_fn=improvised),
    dict(id="combat_knife", L=0.38, grip=0.12, pommel=0.02, guard_t=0.015, grip_r=0.014, wraps=3,
         grip_color=(0.08, 0.08, 0.09), wrap_color=(0.16, 0.16, 0.18), extras=knife_extras, blade_fn=knife_blade),
    dict(id="iron_sword", L=0.95, grip=0.16, pommel=0.035, guard_t=0.03, grip_r=0.017, wraps=3,
         grip_color=(0.3, 0.19, 0.1), wrap_color=(0.2, 0.12, 0.07), extras=iron_extras, blade_fn=iron_blade),
    dict(id="military_machete", L=0.72, grip=0.14, pommel=0.03, guard_t=0.02, grip_r=0.017, wraps=3,
         grip_color=(0.2, 0.26, 0.15), wrap_color=(0.1, 0.13, 0.08), extras=machete_extras, blade_fn=machete_blade),
    dict(id="katana", L=1.05, grip=0.26, pommel=0.018, guard_t=0.012, collar=0.03, grip_r=0.0155, wraps=6,
         grip_color=(0.08, 0.09, 0.14), wrap_color=(0.88, 0.88, 0.85), extras=katana_extras, blade_fn=katana_blade,
         wrap_len=0.02),
    dict(id="tactical_sword", L=0.92, grip=0.17, pommel=0.03, guard_t=0.03, grip_r=0.018, wraps=3,
         grip_color=(0.07, 0.07, 0.08), wrap_color=(0.15, 0.32, 0.6), extras=tactical_extras, blade_fn=tactical_blade),
    dict(id="claymore", L=1.45, grip=0.30, pommel=0.05, guard_t=0.035, grip_r=0.019, wraps=5,
         grip_color=(0.25, 0.16, 0.09), wrap_color=(0.16, 0.1, 0.06), extras=claymore_extras, blade_fn=claymore_blade),
    dict(id="warden_blade", L=1.25, grip=0.24, pommel=0.06, guard_t=0.05, grip_r=0.026, wraps=0,
         grip_color=(0.07, 0.06, 0.07), wrap_color=(0.3, 0.3, 0.32), extras=warden_extras, blade_fn=warden_blade),
]

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for s in SPECS:
        build(s)
