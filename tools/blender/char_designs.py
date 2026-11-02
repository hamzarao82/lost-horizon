"""Geometry for the five Lost Horizon characters. All numbers are for a 1.8 m character (Builder scales).

Modelling convention: +Y is forward (the exporter turns this into Godot's -Z), +X is the character's right.
"""
from char_lib import Builder, hexcol

C = hexcol

SKIN = C('#e6b48f')
SKIN_DARK = C('#c28f6a')


def side(sg):
    return ("R", 1) if sg > 0 else ("L", -1)


def body(b, c):
    """Common human body. c supplies colours: pants boots shirt sleeve forearm glove belt skin."""
    for sg in (1, -1):
        n, sx = side(sg)
        x = 0.10 * sx
        # legs
        b.limb("UpperLeg_" + n, (x, 0, 0.93), (x, 0, 0.50), 0.090, 0.068, c['pants'])
        b.sphere("UpperLeg_" + n, (x, 0, 0.50), (0.069, 0.069, 0.069), c['pants'], bk=True)
        b.limb("LowerLeg_" + n, (x, 0, 0.50), (x, 0, 0.12), 0.066, 0.052, c['pants'])
        b.limb("LowerLeg_" + n, (x, 0, 0.23), (x, 0, 0.09), 0.064, 0.060, c['boots'], ao=False)
        b.box("Foot_" + n, (x, 0.05, 0.045), (0.108, 0.27, 0.09), c['boots'], bevel=0.016, bk=True)
        # arms
        sh, el, wr = (0.20 * sx, 0, 1.40), (0.31 * sx, 0, 1.13), (0.34 * sx, 0.10, 0.90)
        b.limb("UpperArm_" + n, sh, el, 0.056, 0.047, c['sleeve'])
        b.sphere("UpperArm_" + n, el, (0.049, 0.049, 0.049), c['sleeve'], bk=True)
        b.limb("LowerArm_" + n, el, wr, 0.047, 0.040, c['forearm'])
        b.box("Hand_" + n, (0.348 * sx, 0.135, 0.86), (0.078, 0.095, 0.115), c['glove'], bevel=0.012,
              rot=(-41, 0, 0))
        b.sphere("Chest", (0.205 * sx, 0, 1.385), (0.068, 0.068, 0.068), c['sleeve'], bk=True)
    # pelvis, belt, waist, chest
    b.box("Hips", (0, 0, 0.975), (0.315, 0.205, 0.15), c['pants'], bevel=0.02, bk=True)
    b.limb("Hips", (0, 0, 1.005), (0, 0, 1.065), 0.17, 0.17, c['belt'], sides=12, ell=(1.0, 0.70), ao=False)
    b.box("Spine", (0, 0, 1.105), (0.30, 0.19, 0.14), c['shirt'], bevel=0.02, bk=True)
    b.box("Chest", (0, 0, 1.30), (0.375, 0.225, 0.30), c['shirt'], bevel=0.03, bk=True)
    b.limb("Neck", (0, 0, 1.43), (0, 0, 1.55), 0.052, 0.046, c['skin'], bk=False)


def head(b, skin, hair=None, face=True):
    b.sphere("Head", (0, 0.005, 1.65), (0.095, 0.105, 0.115), skin, subdiv=2)
    b.sphere("Head", (0, 0.035, 1.585), (0.062, 0.062, 0.05), skin, subdiv=1)  # chin / jaw
    for sx in (1, -1):
        b.sphere("Head", (0.097 * sx, 0.0, 1.65), (0.02, 0.022, 0.032), skin)  # ears
    if face:
        dark = C('#1a1a1c')
        b.box("Head", (0, 0.108, 1.648), (0.024, 0.042, 0.046), SKIN_DARK, bevel=0.006)  # nose
        for sx in (1, -1):
            b.box("Head", (0.040 * sx, 0.099, 1.676), (0.028, 0.012, 0.015), dark, bevel=0.002, ao=False)  # eyes
            b.box("Head", (0.041 * sx, 0.101, 1.70), (0.044, 0.014, 0.012), hair or dark, bevel=0.003, ao=False)  # brows
        b.box("Head", (0, 0.1, 1.607), (0.05, 0.012, 0.008), C('#8a4a3c'), bevel=0.002, ao=False)  # mouth


# ------------------------------------------------------------------------------------------------
def build_player(b):
    c = dict(pants=C('#3b3e37'), boots=C('#4a3426'), shirt=C('#1b1e21'), sleeve=C('#1b1e21'),
             forearm=SKIN, glove=C('#26282b'), belt=C('#2a2b2d'), skin=SKIN)
    body(b, c)
    hair = C('#2a211c')
    head(b, SKIN, hair)
    # short dark hair
    b.sphere("Head", (0, -0.012, 1.69), (0.102, 0.110, 0.100), hair)
    b.box("Head", (0, 0.075, 1.738), (0.17, 0.05, 0.04), hair, bevel=0.012)
    for sx in (1, -1):
        b.box("Head", (0.096 * sx, 0.035, 1.665), (0.014, 0.05, 0.075), hair, bevel=0.004)
    # tactical vest + pouches + straps
    vest, vest_d = C('#8d7a55'), C('#6c5d42')
    b.box("Chest", (0, 0.003, 1.315), (0.41, 0.25, 0.28), vest, bevel=0.022)
    b.box("Chest", (0, 0.0, 1.10), (0.36, 0.22, 0.05), vest_d, bevel=0.01)
    for sx in (1, -1):
        b.box("Chest", (0.118 * sx, 0.0, 1.44), (0.075, 0.175, 0.045), vest, bevel=0.01)
    for px in (-0.105, 0.0, 0.105):
        b.box("Chest", (px, 0.142, 1.235), (0.085, 0.05, 0.095), vest_d, bevel=0.01)
    b.box("Chest", (-0.17, 0.12, 1.37), (0.05, 0.05, 0.10), C('#25272a'), bevel=0.008)  # radio
    b.box("Chest", (0.0, -0.14, 1.31), (0.28, 0.06, 0.22), vest_d, bevel=0.015)  # back panel
    # utility belt pouches, holster, thigh pocket
    for sx in (1, -1):
        b.box("Hips", (0.17 * sx, 0.05, 1.01), (0.06, 0.085, 0.10), C('#33352f'), bevel=0.01)
    b.box("Hips", (0, 0.105, 1.035), (0.05, 0.02, 0.04), C('#b9b9b9'), bevel=0.004)  # buckle
    b.box("UpperLeg_R", (0.18, 0.02, 0.82), (0.06, 0.12, 0.17), C('#1f2124'), bevel=0.012)
    b.box("UpperLeg_L", (-0.175, 0.04, 0.74), (0.055, 0.10, 0.11), C('#33352f'), bevel=0.01)
    # fingerless gloves: bare knuckles/fingertips
    for sx, n in ((1, "R"), (-1, "L")):
        b.box("Hand_" + n, (0.352 * sx, 0.165, 0.82), (0.06, 0.05, 0.05), SKIN_DARK, bevel=0.008, rot=(-41, 0, 0))


def build_soldier(b):
    c = dict(pants=C('#6b7050'), boots=C('#4a3a2a'), shirt=C('#8a8f62'), sleeve=C('#8a8f62'),
             forearm=C('#8a8f62'), glove=C('#3b3b34'), belt=C('#5a5238'), skin=SKIN)
    body(b, c)
    head(b, SKIN, face=False)
    helmet, plate, mask = C('#707650'), C('#2e3430'), C('#23262a')
    b.sphere("Head", (0, 0.0, 1.705), (0.118, 0.132, 0.10), helmet, subdiv=1)
    b.limb("Head", (0, 0.0, 1.712), (0, 0.0, 1.748), 0.125, 0.125, C('#d8d0a8'), sides=12, ell=(1.0, 1.13), bk=False, ao=False)  # pale helmet band
    b.box("Head", (0, 0.085, 1.745), (0.22, 0.07, 0.03), helmet, bevel=0.01)  # helmet brim
    b.box("Head", (0, 0.098, 1.645), (0.17, 0.05, 0.075), mask, bevel=0.012)  # visor mask
    b.box("Head", (0, 0.092, 1.595), (0.14, 0.05, 0.05), C('#3a3f35'), bevel=0.01)  # chin guard
    b.box("Head", (0.105, 0.0, 1.68), (0.025, 0.07, 0.07), C('#3a3f35'), bevel=0.005)
    b.box("Head", (-0.105, 0.0, 1.68), (0.025, 0.07, 0.07), C('#3a3f35'), bevel=0.005)
    # plate carrier, pouches
    b.box("Chest", (0, 0.004, 1.32), (0.405, 0.245, 0.29), plate, bevel=0.025)
    for px in (-0.09, 0.09):
        b.box("Chest", (px, 0.142, 1.24), (0.085, 0.05, 0.10), C('#454d40'), bevel=0.01)
    b.box("Chest", (0, 0.13, 1.40), (0.20, 0.03, 0.12), C('#404838'), bevel=0.01)
    for sx in (1, -1):
        b.box("Chest", (0.12 * sx, 0.0, 1.44), (0.07, 0.17, 0.04), plate, bevel=0.01)
        n = "R" if sx > 0 else "L"
        b.box("LowerLeg_" + n, (0.10 * sx, 0.07, 0.50), (0.11, 0.06, 0.12), C('#3a3d34'), bevel=0.015)  # knee pad
        b.box("LowerArm_" + n, (0.325 * sx, 0.05, 1.05), (0.075, 0.075, 0.09), C('#4a4d3f'), bevel=0.012)  # elbow pad
    b.box("UpperLeg_R", (0.18, 0.02, 0.80), (0.06, 0.12, 0.18), C('#3a3d34'), bevel=0.012)  # sidearm holster
    b.box("Hips", (0, 0.108, 1.04), (0.05, 0.02, 0.04), C('#9a9a9a'), bevel=0.004)


def build_heavy(b):
    steel, steel_d, trim = C('#6f8196'), C('#46515f'), C('#c8d0d8')
    c = dict(pants=C('#3a4452'), boots=C('#2e353f'), shirt=C('#3a4452'), sleeve=steel_d,
             forearm=steel_d, glove=C('#2e353f'), belt=C('#2c333d'), skin=SKIN_DARK)
    body(b, c)
    head(b, SKIN_DARK, face=False)
    # big helmet with a narrow visor slit
    b.sphere("Head", (0, 0.0, 1.69), (0.14, 0.15, 0.13), steel, subdiv=1)
    b.box("Head", (0, 0.135, 1.665), (0.20, 0.05, 0.16), steel_d, bevel=0.02)
    b.box("Head", (0, 0.16, 1.675), (0.15, 0.015, 0.025), C('#ff6a2a'), bevel=0.003, ao=False)
    b.box("Head", (0, 0.0, 1.80), (0.04, 0.2, 0.05), trim, bevel=0.008)  # crest
    # chest armour, plates
    b.box("Chest", (0, 0.01, 1.325), (0.46, 0.29, 0.34), steel, bevel=0.035)
    b.box("Chest", (0, 0.16, 1.33), (0.30, 0.04, 0.22), steel_d, bevel=0.015)
    b.box("Chest", (0, 0.178, 1.36), (0.07, 0.02, 0.10), trim, bevel=0.004)
    b.box("Spine", (0, 0.0, 1.10), (0.36, 0.23, 0.16), steel_d, bevel=0.02)
    b.box("Hips", (0, 0.11, 0.98), (0.25, 0.04, 0.16), steel, bevel=0.015)  # tasset
    for sx in (1, -1):
        n = "R" if sx > 0 else "L"
        b.sphere("UpperArm_" + n, (0.26 * sx, 0, 1.44), (0.115, 0.115, 0.095), steel, bk=True)  # pauldron
        b.box("UpperArm_" + n, (0.30 * sx, 0, 1.30), (0.07, 0.12, 0.17), steel_d, bevel=0.015)  # rerebrace
        b.limb("LowerArm_" + n, (0.32 * sx, 0.01, 1.10), (0.345 * sx, 0.09, 0.93), 0.062, 0.055, steel)  # vambrace
        b.box("LowerLeg_" + n, (0.10 * sx, 0.07, 0.50), (0.14, 0.07, 0.15), steel, bevel=0.02)
        b.limb("LowerLeg_" + n, (0.10 * sx, 0, 0.45), (0.10 * sx, 0, 0.14), 0.082, 0.066, steel_d)  # greave
        b.box("UpperLeg_" + n, (0.11 * sx, 0.07, 0.74), (0.13, 0.05, 0.22), steel_d, bevel=0.015)  # cuisse
    # big shield on the left forearm (skinned to LowerArm_L so it follows the guard pose)
    b.box("LowerArm_L", (-0.36, 0.20, 1.02), (0.40, 0.05, 0.64), steel, bevel=0.025)
    b.box("LowerArm_L", (-0.36, 0.228, 1.02), (0.30, 0.02, 0.52), steel_d, bevel=0.012)
    b.box("LowerArm_L", (-0.36, 0.245, 1.05), (0.10, 0.015, 0.14), C('#ee5a1c'), bevel=0.004, ao=False)
    b.box("LowerArm_L", (-0.36, 0.225, 1.02), (0.04, 0.01, 0.50), trim, bevel=0.003)


def build_elite(b):
    gear, cloth, purple, teal = C('#5a6072'), C('#40434f'), C('#27d1c0'), C('#35e8d4')  # 'purple' is now the teal accent
    c = dict(pants=C('#3a3d4a'), boots=C('#2a2c34'), shirt=cloth, sleeve=cloth, forearm=cloth,
             glove=C('#25272e'), belt=C('#1fb3a5'), skin=SKIN_DARK)
    body(b, c)
    head(b, SKIN_DARK, face=False)
    # hood, goggles, lower-face mask
    b.sphere("Head", (0, -0.012, 1.685), (0.118, 0.132, 0.125), cloth, subdiv=1)
    b.box("Head", (0, -0.11, 1.62), (0.14, 0.09, 0.20), cloth, bevel=0.02)  # hood tail
    b.box("Head", (0, 0.104, 1.672), (0.18, 0.035, 0.05), C('#1a1b20'), bevel=0.008)
    b.box("Head", (0, 0.122, 1.672), (0.15, 0.012, 0.03), teal, bevel=0.003, ao=False)  # lenses
    b.box("Head", (0, 0.075, 1.752), (0.20, 0.03, 0.022), purple, bevel=0.005, ao=False)  # teal hood trim
    b.box("Head", (0, 0.098, 1.61), (0.13, 0.05, 0.075), C('#2a2c33'), bevel=0.012)  # mask
    # light armour, purple accents
    b.box("Chest", (0, 0.004, 1.315), (0.35, 0.215, 0.24), gear, bevel=0.02)
    b.box("Chest", (0, 0.114, 1.34), (0.20, 0.02, 0.05), purple, bevel=0.004, ao=False)
    for sx in (1, -1):
        n = "R" if sx > 0 else "L"
        b.box("UpperArm_" + n, (0.27 * sx, 0, 1.40), (0.09, 0.14, 0.05), gear, bevel=0.01)  # shoulder plate
        b.box("UpperArm_" + n, (0.275 * sx, 0, 1.41), (0.092, 0.03, 0.052), purple, bevel=0.004, ao=False)
        b.box("LowerLeg_" + n, (0.10 * sx, 0.06, 0.50), (0.09, 0.05, 0.10), gear, bevel=0.012)
        b.box("Hips", (0.17 * sx, 0.04, 1.01), (0.055, 0.07, 0.09), gear, bevel=0.01)
    b.box("Hips", (0, 0.105, 1.035), (0.07, 0.02, 0.035), purple, bevel=0.004, ao=False)
    # rifle slung across the back (cosmetic)
    b.box("Chest", (0.06, -0.17, 1.27), (0.045, 0.065, 0.72), C('#30333c'), bevel=0.008, rot=(0, 22, 0))
    b.box("Chest", (0.015, -0.17, 1.44), (0.04, 0.05, 0.20), C('#3a3d48'), bevel=0.008, rot=(0, 22, 0))
    b.box("Chest", (0.10, -0.17, 1.05), (0.045, 0.10, 0.16), C('#30333c'), bevel=0.008, rot=(0, 22, 0))
    b.box("Chest", (0.07, -0.17, 1.30), (0.05, 0.07, 0.04), purple, bevel=0.004, rot=(0, 22, 0), ao=False)


def build_warden(b):
    black, crimson, crimson_d, steel = C('#1d1d21'), C('#b01c28'), C('#6e1019'), C('#5b6370')
    c = dict(pants=C('#1d1d21'), boots=C('#18181b'), shirt=C('#1d1d21'), sleeve=black,
             forearm=steel, glove=C('#18181b'), belt=crimson_d, skin=SKIN_DARK)
    body(b, c)
    head(b, SKIN_DARK, face=False)
    # horned helmet with face guard
    b.sphere("Head", (0, 0.0, 1.69), (0.13, 0.142, 0.135), black, subdiv=1)
    b.box("Head", (0, 0.12, 1.64), (0.19, 0.055, 0.16), steel, bevel=0.02)
    b.box("Head", (0, 0.152, 1.665), (0.13, 0.012, 0.022), C('#ff4a3a'), bevel=0.003, ao=False)  # glowing eye slit
    b.box("Head", (0, 0.0, 1.805), (0.035, 0.22, 0.04), crimson, bevel=0.008)  # crest
    for sx in (1, -1):
        b.limb("Head", (0.115 * sx, 0, 1.745), (0.19 * sx, 0.0, 1.81), 0.036, 0.024, C('#d8d2c4'), bk=False)
        b.limb("Head", (0.19 * sx, 0, 1.81), (0.215 * sx, 0.03, 1.90), 0.024, 0.008, C('#d8d2c4'), bk=False)
    # heavy chest plate with crimson trim
    b.box("Chest", (0, 0.012, 1.325), (0.50, 0.31, 0.35), black, bevel=0.04)
    b.box("Chest", (0, 0.172, 1.34), (0.34, 0.04, 0.24), crimson_d, bevel=0.015)
    b.box("Chest", (0, 0.192, 1.36), (0.12, 0.02, 0.14), crimson, bevel=0.005)
    b.box("Chest", (0, 0.0, 1.18), (0.46, 0.30, 0.05), crimson, bevel=0.01)
    b.box("Spine", (0, 0.0, 1.10), (0.38, 0.24, 0.16), steel, bevel=0.02)
    # pauldrons with spikes, gauntlets, greaves
    for sx in (1, -1):
        n = "R" if sx > 0 else "L"
        b.sphere("UpperArm_" + n, (0.29 * sx, 0, 1.45), (0.14, 0.14, 0.105), steel, bk=True)
        b.limb("UpperArm_" + n, (0.30 * sx, 0, 1.50), (0.34 * sx, 0, 1.64), 0.04, 0.008, steel, bk=False)  # spike
        b.box("UpperArm_" + n, (0.30 * sx, 0, 1.33), (0.075, 0.135, 0.17), steel, bevel=0.015)
        b.limb("LowerArm_" + n, (0.32 * sx, 0.01, 1.10), (0.35 * sx, 0.095, 0.92), 0.068, 0.060, black)
        b.box("LowerArm_" + n, (0.33 * sx, 0.05, 1.03), (0.04, 0.1, 0.10), crimson, bevel=0.008)
        b.box("LowerLeg_" + n, (0.10 * sx, 0.075, 0.50), (0.15, 0.08, 0.17), steel, bevel=0.02)
        b.limb("LowerLeg_" + n, (0.10 * sx, 0, 0.45), (0.10 * sx, 0, 0.14), 0.085, 0.068, steel)
        b.box("UpperLeg_" + n, (0.11 * sx, 0.075, 0.76), (0.14, 0.05, 0.24), black, bevel=0.015)
        b.box("UpperLeg_" + n, (0.11 * sx, 0.1, 0.76), (0.04, 0.02, 0.22), crimson, bevel=0.004, ao=False)
    # tassets and belt
    b.box("Hips", (0, 0.115, 0.95), (0.28, 0.045, 0.20), crimson_d, bevel=0.015)
    b.box("Hips", (0, 0.13, 0.95), (0.08, 0.02, 0.17), black, bevel=0.005)
    # cape: four skinned segments hanging from the shoulders
    for z, w, bone, col in ((1.40, 0.50, "Chest", crimson), (1.18, 0.54, "Chest", crimson),
                            (0.96, 0.52, "Spine", crimson_d), (0.74, 0.46, "Hips", crimson_d),
                            (0.54, 0.40, "Hips", crimson_d)):
        b.box(bone, (0, -0.19, z), (w, 0.03, 0.22), col, bevel=0.006)


DESIGNS = {
    # name: (builder fn, height, bulk)
    "player": (build_player, 1.80, 1.0),
    "soldier": (build_soldier, 1.78, 1.0),
    "heavy": (build_heavy, 1.95, 1.22),
    "elite": (build_elite, 1.82, 0.92),
    "warden": (build_warden, 2.10, 1.28),
}
