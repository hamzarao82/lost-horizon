"""Generates the Outpost 17 environment kit (assets/environments/kit/*.glb) and kit_manifest.json.

Run:  blender --background --python tools/blender/props_env_kit.py -- <project_root> [piece ...]
Everything is original, procedurally modelled low-poly geometry: no external assets, no licences.
Blender axes: +Z up, front faces +Y (becomes -Z in Godot), 1 unit = 1 m, origin at the base centre.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402
from env_lib import PAL, Piece, shade  # noqa: E402

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ROOT = args[0] if args else os.getcwd()
ONLY = set(args[1:])
OUT = os.path.join(ROOT, "assets", "environments", "kit")
os.makedirs(OUT, exist_ok=True)

PIECES = {}


def piece(fn):
    PIECES[fn.__name__] = fn
    return fn


# --- containers: 4.0 x 1.95 x 2.0 m; the arena obstacle is two of them side by side (4 x 4 x 2) ---------

def _container(name, color):
    P = Piece(name)
    L, W, H = 4.0, 1.95, 2.0
    dark = shade(color, 0.45)
    P.box((0, 0, 0.06), (L, W, 0.12), dark)
    P.box((0, 0, H - 0.05), (L, W, 0.10), dark)
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.box((sx * (L / 2 - 0.06), sy * (W / 2 - 0.06), H / 2), (0.12, 0.12, H), dark)
    P.box((0, 0, H / 2), (L - 0.2, W - 0.1, H - 0.2), color, jitter=0.03)
    n = 12
    for i in range(n):
        x = -L / 2 + 0.35 + i * (L - 0.7) / (n - 1)
        for sy in (-1, 1):
            P.box((x, sy * (W / 2 - 0.05), H / 2), (0.08, 0.06, H - 0.3), shade(color, 1.08 if i % 2 else 0.92), jitter=0.04)
    for sy in (-1, 1):  # door end (+X)
        P.box((L / 2 - 0.08, sy * 0.46, H / 2), (0.05, 0.9, H - 0.4), shade(color, 1.1), jitter=0.04)
    for y in (-0.62, -0.3, 0.3, 0.62):
        P.box((L / 2 - 0.03, y, H / 2), (0.04, 0.05, H - 0.45), PAL["steel"])
    P.box((L / 2 - 0.02, 0.0, H / 2), (0.05, 0.14, 0.2), PAL["dark_steel"])
    for i in range(6):  # rust and scuffs
        side = 1 if i % 2 == 0 else -1
        P.box((P.rng.uniform(-1.5, 1.5), side * (W / 2 - 0.015), P.rng.uniform(0.3, 1.6)),
              (P.rng.uniform(0.2, 0.5), 0.02, P.rng.uniform(0.15, 0.4)), PAL["rust"], jitter=0.1)
    return P


@piece
def container_red():
    return _container("container_red", PAL["red"])


@piece
def container_blue():
    return _container("container_blue", PAL["blue"])


@piece
def container_green():
    return _container("container_green", PAL["green"])


# --- watchtower ---------------------------------------------------------------------------------------------

@piece
def watchtower():
    P = Piece("watchtower")
    top = 6.5
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.cyl((sx * 1.2, sy * 1.2, 0), 0.16, 0.12, top, 5, PAL["wood_dark"])
    for z0, z1 in ((0.6, 3.4), (3.4, 6.2)):
        for (a, b) in (((-1.2, -1.2), (1.2, -1.2)), ((1.2, -1.2), (1.2, 1.2)), ((1.2, 1.2), (-1.2, 1.2)), ((-1.2, 1.2), (-1.2, -1.2))):
            P.beam((a[0], a[1], z0), (b[0], b[1], z1), 0.08, PAL["wood"])
    P.box((0, 0, top + 0.1), (3.4, 3.4, 0.2), PAL["wood"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.box((sx * 1.6, sy * 1.6, top + 0.65), (0.1, 0.1, 0.9), PAL["wood_dark"])
    for z in (top + 0.5, top + 1.0):
        P.box((0, 1.6, z), (3.3, 0.06, 0.07), PAL["wood"])
        P.box((0, -1.6, z), (3.3, 0.06, 0.07), PAL["wood"])
        P.box((1.6, 0, z), (0.06, 3.3, 0.07), PAL["wood"])
        P.box((-1.6, 0, z), (0.06, 3.3, 0.07), PAL["wood"])
    P.box((0, 0, top + 1.0), (2.6, 2.6, 1.6), PAL["khaki"])
    P.box((0, 1.31, top + 1.1), (1.8, 0.05, 0.5), PAL["glass"])
    P.box((1.31, 0, top + 1.1), (0.05, 1.2, 0.45), PAL["glass"])
    P.cyl((0, 0, top + 1.8), 2.4, 0.0, 1.3, 4, PAL["rust"], rot=(0, 0, math.pi / 4))
    for sy_x in (-0.4, 0.4):  # ladder on the back
        P.beam((sy_x, -1.45, 0.0), (sy_x, -1.45, top), 0.07, PAL["wood"])
    for i in range(13):
        z = 0.4 + i * 0.5
        P.box((0, -1.45, z), (0.8, 0.06, 0.05), PAL["wood_dark"])
    return P


# --- sandbags -----------------------------------------------------------------------------------------------

def _bag(P, x, y, z, along_x=True):
    size = (0.55, 0.34, 0.22) if along_x else (0.34, 0.55, 0.22)
    P.box((x, y, z), size, PAL["sandbag"], rot=(0, 0, P.rng.uniform(-0.06, 0.06)), jitter=0.07)


@piece
def sandbag_stack():
    P = Piece("sandbag_stack")
    for row, count in enumerate((4, 3, 2)):
        for col in range(count):
            x = (col - (count - 1) / 2) * 0.58
            for y in (-0.2, 0.2):
                _bag(P, x, y, 0.11 + row * 0.21)
    return P


@piece
def sandbag_corner():
    P = Piece("sandbag_corner")
    for row, count in enumerate((4, 3, 2)):
        for col in range(count):
            _bag(P, -0.9 + col * 0.58 + row * 0.2, 0.0, 0.11 + row * 0.21)
        for col in range(max(count - 1, 1)):
            _bag(P, -0.9 - 0.15, 0.5 + col * 0.58 + row * 0.2, 0.11 + row * 0.21, along_x=False)
    return P


# --- barricades -------------------------------------------------------------------------------------------

@piece
def barricade_concrete():
    P = Piece("barricade_concrete")
    prof = [(-0.35, 0.0), (0.35, 0.0), (0.35, 0.12), (0.2, 0.5), (0.12, 0.9), (-0.12, 0.9), (-0.2, 0.5), (-0.35, 0.12)]
    P.extrude([(-1.5, y, z) for (y, z) in prof], (3.0, 0, 0), PAL["concrete"], jitter=0.06)
    for x in (-1.0, 0.0, 1.0):
        P.box((x, 0.125, 0.55), (0.45, 0.02, 0.22), PAL["hazard"] if int(x) % 2 == 0 else PAL["black"], rot=(0, 0, 0))
    return P


def _hedgehog(P, cx, cy, s):
    c = (cx, cy, s)
    for d in ((1, 1, 1), (1, -1, 1), (-1, 1, 1)):
        P.beam((cx - s * d[0], cy - s * d[1], s - s * d[2] * 0.98), (cx + s * d[0], cy + s * d[1], s + s * d[2] * 0.98), 0.1, PAL["steel"])


@piece
def barricade_wire():
    P = Piece("barricade_wire")
    _hedgehog(P, -1.4, 0.0, 0.55)
    _hedgehog(P, 1.4, 0.0, 0.55)
    P.cyl((-1.4, 0.0, 0.42), 0.38, 0.38, 2.8, 12, PAL["dark_steel"], rot=(0, math.pi / 2, 0), jitter=0.12)
    for x in (-0.7, 0.7):
        P.cyl((x, 0, 0), 0.04, 0.03, 0.7, 4, PAL["wood_dark"])
    return P


# --- buildings ------------------------------------------------------------------------------------------------

def _gable(P, length, width, wall_h, rise, color, overhang=0.35):
    hw = width / 2 + overhang
    pts = [(-length / 2 - overhang, -hw, wall_h), (-length / 2 - overhang, hw, wall_h), (-length / 2 - overhang, 0, wall_h + rise)]
    P.extrude(pts, (length + overhang * 2, 0, 0), color, jitter=0.04)


def _hut(name, wall_color):
    P = Piece(name)
    L, W, H = 5.0, 3.6, 2.8
    P.box((0, 0, 0.15), (L + 0.2, W + 0.2, 0.3), PAL["concrete"])
    P.box((0, 0, 0.3 + (H - 0.3) / 2), (L, W, H - 0.3), wall_color, jitter=0.03)
    _gable(P, L, W, H, 1.2, PAL["rust"])
    P.box((0.0, W / 2 + 0.02, 1.25), (1.0, 0.1, 1.9), PAL["wood_dark"])
    P.box((1.6, W / 2 + 0.02, 1.6), (0.8, 0.1, 0.6), PAL["glass"])
    P.box((-1.6, W / 2 + 0.02, 1.6), (0.8, 0.1, 0.6), PAL["glass"])
    P.box((0.0, W / 2 + 0.3, 0.2), (1.4, 0.7, 0.14), PAL["concrete"])
    P.box((L / 2 + 0.02, 0.0, 1.6), (0.1, 0.8, 0.6), PAL["glass"])
    P.cyl((-1.8, -1.0, H), 0.12, 0.12, 0.9, 6, PAL["dark_steel"])
    return P


@piece
def hut_small():
    return _hut("hut_small", PAL["khaki"])


@piece
def hut_olive():
    return _hut("hut_olive", PAL["olive"])


@piece
def barracks():
    P = Piece("barracks")
    L, W, H = 14.0, 4.6, 3.0
    P.box((0, 0, 0.15), (L + 0.2, W + 0.2, 0.3), PAL["concrete"])
    P.box((0, 0, 0.3 + (H - 0.3) / 2), (L, W, H - 0.3), PAL["olive"], jitter=0.03)
    P.box((0, 0, H - 0.1), (L + 0.1, W + 0.1, 0.15), PAL["dark_steel"])
    _gable(P, L, W, H, 1.3, PAL["rust"], overhang=0.45)
    for i in range(5):
        x = -5.4 + i * 2.7
        if i == 2:
            continue
        P.box((x, W / 2 + 0.02, 1.8), (0.95, 0.1, 0.85), PAL["glass"])
        P.box((x, W / 2 + 0.05, 1.33), (1.15, 0.12, 0.08), PAL["concrete"])
    P.box((0, W / 2 + 0.02, 1.35), (1.2, 0.1, 2.0), PAL["wood_dark"])
    P.box((0, W / 2 + 0.6, 0.2), (2.4, 1.0, 0.16), PAL["concrete"])
    P.box((0, W / 2 + 0.55, 2.6), (2.6, 1.1, 0.1), PAL["rust"])
    for x in (-1.2, 1.2):
        P.box((x, W / 2 + 1.0, 1.3), (0.1, 0.1, 2.2), PAL["wood_dark"])
    for x in (-4.0, 3.5):
        P.cyl((x, -0.4, H + 0.1), 0.18, 0.18, 1.2, 6, PAL["dark_steel"])
        P.cyl((x, -0.4, H + 1.3), 0.26, 0.26, 0.1, 6, PAL["dark_steel"])
    for i in range(3):
        P.box((-L / 2 - 0.02, -1.0 + i * 1.0, 1.8), (0.1, 0.6, 0.6), PAL["glass"])
    return P


@piece
def warehouse():
    P = Piece("warehouse")
    L, W, H = 12.0, 8.0, 3.5
    P.box((0, 0, 0.12), (L + 0.2, W + 0.2, 0.24), PAL["concrete"])
    P.box((0, 0, 0.24 + (H - 0.24) / 2), (L, W, H - 0.24), PAL["steel"], jitter=0.03)
    ring = [(-L / 2 - 0.3, (W / 2 + 0.3) * math.cos(math.pi * i / 8), H + 1.9 * math.sin(math.pi * i / 8)) for i in range(9)]
    P.extrude(ring, (L + 0.6, 0, 0), PAL["dark_steel"], jitter=0.05)
    for i in range(14):
        x = -L / 2 + 0.4 + i * (L - 0.8) / 13
        P.box((x, W / 2 + 0.03, 1.9), (0.1, 0.06, 3.0), shade(PAL["steel"], 1.12 if i % 2 else 0.9), jitter=0.04)
    P.box((0, W / 2 + 0.04, 1.75), (4.6, 0.1, 3.3), PAL["dark_steel"])
    for x in (-2.35, 2.35):
        P.box((x, W / 2 + 0.07, 1.75), (0.14, 0.1, 3.4), PAL["rust"])
    P.box((0, W / 2 + 0.07, 3.45), (4.8, 0.1, 0.14), PAL["rust"])
    P.box((L / 2 + 0.03, -1.0, 1.4), (0.1, 1.0, 2.2), PAL["wood_dark"])
    P.box((-3.5, W / 2 + 0.03, 3.0), (1.3, 0.06, 0.6), PAL["glass"])
    P.box((3.5, W / 2 + 0.03, 3.0), (1.3, 0.06, 0.6), PAL["glass"])
    return P


# --- fences ---------------------------------------------------------------------------------------------------

@piece
def fence_section():
    P = Piece("fence_section")
    L = 6.0
    P.box((0, 0, 0.25), (L, 0.12, 0.5), PAL["dark_steel"])
    P.box((0, 0, 1.45), (L, 0.05, 1.9), PAL["steel"], jitter=0.03)
    n = 15
    for i in range(n):
        x = -L / 2 + 0.2 + i * (L - 0.4) / (n - 1)
        P.box((x, 0.04, 1.45), (0.08, 0.05, 1.9), shade(PAL["steel"], 1.15 if i % 2 else 0.88), jitter=0.04)
    for x in (-L / 2 + 0.06, 0.0, L / 2 - 0.06):
        P.box((x, 0, 1.3), (0.14, 0.14, 2.6), PAL["dark_steel"])
    P.box((0, 0, 2.45), (L, 0.1, 0.1), PAL["dark_steel"])
    for x in (-2.0, 2.0):
        P.beam((x, 0, 2.4), (x, 0.4, 2.8), 0.05, PAL["dark_steel"])
    return P


@piece
def fence_wire():
    P = Piece("fence_wire")
    L = 4.0
    for x in (-L / 2 + 0.05, 0.0, L / 2 - 0.05):
        P.box((x, 0, 1.0), (0.1, 0.1, 2.0), PAL["dark_steel"])
        P.beam((x, 0, 1.9), (x, 0.3, 2.2), 0.04, PAL["dark_steel"])
    P.box((0, 0, 1.95), (L, 0.05, 0.05), PAL["steel"])
    P.box((0, 0, 0.1), (L, 0.05, 0.05), PAL["steel"])
    for i in range(6):
        x0 = -L / 2 + i * (L / 6)
        P.beam((x0, 0, 0.1), (x0 + L / 6 * 2, 0, 1.95), 0.025, PAL["steel"])
        P.beam((x0 + L / 6 * 2 if x0 + L / 6 * 2 <= L / 2 else L / 2, 0, 0.1), (x0, 0, 1.95), 0.025, PAL["steel"])
    P.box((0, 0.28, 2.18), (L, 0.03, 0.03), PAL["dark_steel"])
    return P


# --- vegetation --------------------------------------------------------------------------------------------

def _palm(name, height, lean, fronds, seed):
    P = Piece(name, seed)
    pts = []
    for i in range(7):
        t = i / 6
        pts.append((lean * t * t * height * 0.35, lean * 0.4 * t * t * height * 0.2, t * height))
    for i in range(6):
        r0 = 0.30 - 0.16 * (i / 6)
        r1 = 0.30 - 0.16 * ((i + 1) / 6)
        P.frustum(pts[i], pts[i + 1], r0, r1, 6, PAL["trunk"] if i % 2 == 0 else shade(PAL["trunk"], 0.82), caps=False)
    top = pts[-1]
    P.seal()
    for k in range(fronds):
        a = P.rng.uniform(0, 0.8) + math.tau * k / fronds
        d = (math.cos(a), math.sin(a))
        s = (-math.sin(a), math.cos(a))
        length = P.rng.uniform(2.9, 3.7)
        sections = []
        for t, w in ((0.0, 0.06), (0.35, 0.5), (0.7, 0.42), (1.0, 0.0)):
            z = top[2] + length * (0.30 * t - 0.62 * t * t) + 0.1
            cx = top[0] + d[0] * length * t
            cy = top[1] + d[1] * length * t
            sections.append(((cx - s[0] * w, cy - s[1] * w, z), (cx + s[0] * w, cy + s[1] * w, z)))
        for i in range(3):
            (a0, a1), (b0, b1) = sections[i], sections[i + 1]
            col = PAL["leaf_dark"] if i == 0 else PAL["leaf_light"] if i == 1 else shade(PAL["leaf_light"], 0.9)
            if i < 2:
                P.sheet([a0, a1, b1, b0], col, jitter=0.08)
            else:
                P.sheet([a0, a1, b0], col, jitter=0.08)
    return P


@piece
def palm_a():
    return _palm("palm_a", 5.6, 0.7, 10, 11)


@piece
def palm_b():
    return _palm("palm_b", 6.5, -0.9, 11, 29)


@piece
def bush():
    P = Piece("bush")
    for (x, y, z, r) in ((0, 0, 0.45, 0.6), (0.5, 0.2, 0.35, 0.45), (-0.45, -0.1, 0.4, 0.5), (0.1, -0.5, 0.3, 0.4)):
        P.blob((x, y, z), (r, r, r * 0.8), PAL["leaf_dark"], wobble=0.12, jitter=0.12, top_light=0.35)
    return P


def _rocks(name, seed, big):
    P = Piece(name, seed)
    P.blob((0, 0, big * 0.4), (big, big * 0.85, big * 0.7), PAL["stone"], wobble=0.22, jitter=0.1)
    P.blob((big * 0.9, big * 0.3, big * 0.2), (big * 0.5, big * 0.45, big * 0.35), PAL["stone"], wobble=0.25, jitter=0.1)
    P.blob((-big * 0.7, -big * 0.5, big * 0.15), (big * 0.35, big * 0.3, big * 0.25), PAL["stone"], wobble=0.25, jitter=0.1)
    return P


@piece
def rocks_a():
    return _rocks("rocks_a", 3, 1.0)


@piece
def rocks_b():
    return _rocks("rocks_b", 8, 0.8)


@piece
def rocks_c():
    return _rocks("rocks_c", 13, 1.3)


# --- props ------------------------------------------------------------------------------------------------------

@piece
def crate():
    P = Piece("crate")
    P.box((0, 0, 0.5), (0.94, 0.94, 0.94), PAL["wood"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.box((sx * 0.45, sy * 0.45, 0.5), (0.1, 0.1, 1.0), PAL["wood_dark"])
    for z in (0.08, 0.92):
        P.box((0, 0, z), (1.0, 1.0, 0.08), PAL["wood_dark"])
    for sy in (-1, 1):
        P.beam((-0.4, sy * 0.48, 0.15), (0.4, sy * 0.48, 0.85), 0.07, PAL["wood_dark"])
    return P


@piece
def barrel():
    P = Piece("barrel")
    P.cyl((0, 0, 0), 0.38, 0.38, 0.95, 10, PAL["olive"])
    for z in (0.12, 0.47, 0.83):
        P.cyl((0, 0, z), 0.405, 0.405, 0.05, 10, PAL["dark_steel"], caps=False)
    P.cyl((0, 0, 0.93), 0.3, 0.3, 0.04, 10, PAL["dark_steel"])
    return P


@piece
def radio_mast():
    P = Piece("radio_mast")
    P.cyl((0, 0, 0), 0.16, 0.07, 13.0, 6, PAL["steel"])
    for h in (5.0, 8.5, 11.5):
        P.box((0, 0, h), (2.2 - h * 0.12, 0.07, 0.07), PAL["steel"])
    for a in (0.0, math.pi / 2, math.pi, math.pi * 1.5):
        P.beam((0, 0, 9.5), (math.cos(a) * 5.0, math.sin(a) * 5.0, 0.0), 0.03, PAL["dark_steel"])
    P.box((2.6, 1.0, 0.7), (2.0, 1.6, 1.4), PAL["olive"])
    P.box((2.6, 1.82, 0.85), (1.0, 0.04, 0.5), PAL["glass"])
    P.cyl((1.4, 0.0, 3.4), 0.9, 0.2, 0.45, 8, PAL["canvas"], rot=(0, 0.9, 0))
    return P


@piece
def truck_wreck():
    P = Piece("truck_wreck")
    P.box((0, 0, 0.95), (4.4, 2.0, 0.5), PAL["char"], jitter=0.1)
    P.box((1.6, 0, 1.75), (1.4, 1.9, 1.3), shade(PAL["char"], 1.2), jitter=0.1)
    P.box((1.6, 0.97, 1.9), (1.0, 0.04, 0.5), PAL["glass"])
    P.box((2.35, 0, 1.4), (0.2, 1.4, 0.6), PAL["rust"], jitter=0.12)
    P.box((-0.6, 0, 1.3), (2.8, 1.9, 0.12), shade(PAL["rust"], 0.8), jitter=0.12)
    for sy in (-1, 1):
        P.box((-0.6, sy * 0.92, 1.55), (2.8, 0.08, 0.5), PAL["char"], jitter=0.1)
    for x in (-1.5, 1.5):
        for sy in (-1, 1):
            P.cyl((x, sy * 1.0 - sy * 0.12, 0.5), 0.5, 0.5, 0.24, 8, PAL["black"], rot=(math.pi / 2, 0, 0), jitter=0.04)
    return P


@piece
def boat_wreck():
    P = Piece("boat_wreck")
    stations = []
    for i in range(9):
        x = -3.8 + 7.6 * i / 8
        hw = max(0.05, 1.3 * math.sqrt(max(0.0, 1 - (x / 3.8) ** 2)))
        rail = 1.0 + 0.4 * max(0.0, x / 3.8) ** 2
        stations.append((x, hw, rail))
    P.box((0, 0, 0.35), (6.0, 2.0, 0.1), PAL["wood_dark"])
    P.box((-0.6, 0, 1.0), (3.0, 1.9, 1.3), PAL["canvas"], jitter=0.04)
    P.box((-0.6, 0, 1.68), (3.2, 2.1, 0.12), PAL["rust"])
    P.box((3.4, 0, 0.85), (1.2, 1.2, 0.1), PAL["wood_dark"])
    P.beam((1.6, 0, 0.7), (3.2, 0, 4.6), 0.12, PAL["wood_dark"])
    P.seal()
    for i in range(8):
        (x0, hw0, r0), (x1, hw1, r1) = stations[i], stations[i + 1]
        for side in (-1, 1):
            rows = [(r0, r1), (0.35, 0.35), (0.1, 0.1)]
            pts_a = [(x0, side * hw0, r0), (x0, side * hw0 * 0.85, 0.35), (x0, 0.0, 0.1)]
            pts_b = [(x1, side * hw1, r1), (x1, side * hw1 * 0.85, 0.35), (x1, 0.0, 0.1)]
            for k in range(2):
                col = PAL["wood"] if (i + k) % 2 == 0 else PAL["wood_dark"]
                P.sheet([pts_a[k], pts_b[k], pts_b[k + 1], pts_a[k + 1]], col, jitter=0.08)
    P.sheet([(1.9, 0, 1.6), (3.2, 0, 4.5), (3.2, 0.1, 0.9)], PAL["canvas"], jitter=0.05)
    return P


@piece
def sign_outpost_17():
    P = Piece("sign_outpost_17")
    for x in (-1.7, 1.7):
        P.cyl((x, 0, 0), 0.12, 0.1, 4.4, 6, PAL["steel"])
    P.box((0, 0, 3.1), (3.4, 0.08, 2.2), PAL["banner"], jitter=0.03)
    P.box((0, 0.06, 4.25), (3.4, 0.1, 0.1), PAL["dark_steel"])
    P.box((0, 0.06, 1.98), (3.4, 0.1, 0.1), PAL["dark_steel"])
    y = 0.07
    # The front is seen from +Y with +X on the viewer's LEFT, so the digits are laid out mirrored in X.
    P.box((0.55, y, 3.1), (0.28, 0.06, 1.4), PAL["white"])            # 1
    P.beam((0.55, y, 3.8), (0.9, y, 3.4), 0.2, PAL["white"])
    P.box((-0.75, y, 3.7), (0.95, 0.06, 0.26), PAL["white"])           # 7
    P.beam((-1.2, y, 3.7), (-0.75, y, 2.4), 0.26, PAL["white"])
    return P


@piece
def tent():
    P = Piece("tent")
    prof = [(-1.1, 0.0), (1.1, 0.0), (0.0, 1.5)]
    P.extrude([(-1.5, y, z) for (y, z) in prof], (3.0, 0, 0), PAL["canvas"], jitter=0.06)
    P.box((0.0, 1.0, 0.7), (0.02, 0.02, 0.02), PAL["canvas"])
    for sx in (-1, 1):
        for sy in (-1, 1):
            P.beam((sx * 1.5, sy * 1.1, 0.0), (sx * 2.1, sy * 1.8, 0.0 + 0.05), 0.03, PAL["wood_dark"])
    P.box((1.51, 0.0, 0.45), (0.04, 0.5, 0.9), PAL["black"])
    return P


@piece
def generator():
    P = Piece("generator")
    P.box((0, 0, 0.5), (1.2, 0.7, 0.8), PAL["olive"])
    for sx in (-1, 1):
        P.box((sx * 0.55, 0, 0.1), (0.1, 0.8, 0.2), PAL["dark_steel"])
    P.cyl((-0.15, 0.0, 0.95), 0.18, 0.18, 0.7, 8, PAL["rust"], rot=(0, math.pi / 2, 0))
    P.cyl((0.45, -0.2, 0.9), 0.05, 0.05, 0.6, 6, PAL["dark_steel"])
    P.box((0.0, 0.36, 0.55), (0.9, 0.03, 0.4), PAL["dark_steel"])
    P.box((0.0, 0.38, 0.55), (0.3, 0.03, 0.15), PAL["hazard"])
    return P


def main():
    manifest = {"version": 1, "units": "metres", "front": "-Z", "pieces": []}
    for name, fn in PIECES.items():
        if ONLY and name not in ONLY:
            continue
        info = fn().export(OUT)
        info["bytes"] = os.path.getsize(os.path.join(OUT, name + ".glb"))
        manifest["pieces"].append(info)
        print("kit", name, info["tris"], "tris", info["size"], info["bytes"], "bytes")
    path = os.path.join(ROOT, "assets", "environments", "kit_manifest.json")
    if ONLY and os.path.exists(path):
        old = json.load(open(path))
        keep = [p for p in old["pieces"] if p["name"] not in ONLY]
        manifest["pieces"] = keep + manifest["pieces"]
    manifest["pieces"].sort(key=lambda p: p["name"])
    with open(path, "w") as fh:
        json.dump(manifest, fh, indent=1)


main()
