"""All animation clips (names and durations are part of the contract with the engine adapter).

Poses are FK rotations in degrees about armature axes (+X right, +Y forward, +Z up):
  rx > 0 swings a down-pointing limb FORWARD (raises arms/thighs forward); a spine with rx > 0 leans BACK.
  ry < 0 swings a right limb OUTWARD (abduction); rz > 0 turns the torso LEFT (counter-clockwise from above).
Every attack clip has its strike (peak of the swing) at 35% of the clip length.
"""
import math
from char_lib import P

G = P(hips_loc=(0, 0, -0.05), ul_r=(12, 0, -6), ul_l=(-8, 0, 6), ll_r=(-26, 0, 0), ll_l=(-16, 0, 0),
      spine=(-6, 0, 0), chest=(-2, 0, -10), head=(4, 0, 10),
      ua_r=(58, 12, 0), la_r=(78, 0, 0), ua_l=(48, -14, 0), la_l=(72, 0, 0))

IDLE_A = P(hips_loc=(0, 0, 0.0), ua_r=(4, 4, 0), la_r=(14, 0, 0), ua_l=(4, -4, 0), la_l=(14, 0, 0),
           ul_r=(1, 0, -1), ul_l=(-1, 0, 1), ll_r=(-3, 0, 0), ll_l=(-3, 0, 0))
IDLE_B = P(hips_loc=(0, 0, -0.012), ua_r=(7, 5, 0), la_r=(18, 0, 0), ua_l=(7, -5, 0), la_l=(18, 0, 0),
           ul_r=(2, 0, -1), ul_l=(-2, 0, 1), ll_r=(-5, 0, 0), ll_l=(-5, 0, 0), spine=(-1.5, 0, 0),
           chest=(1.5, 0, 0), head=(-2, 0, 0))


def _cycle(period_keys, leg, knee, arm, elbow, bob, lean, twist, n=12):
    keys = []
    for i in range(n + 1):
        t = i / n
        ph = 2 * math.pi * t
        s, c = math.sin(ph), math.cos(ph)
        keys.append((t, P(
            hips_loc=(0, 0, -bob * 0.5 * (1 - math.cos(2 * ph))),
            ul_r=(leg * s, 0, -2), ul_l=(-leg * s, 0, 2),
            ll_r=(-(8 + knee * max(0.0, c)), 0, 0), ll_l=(-(8 + knee * max(0.0, -c)), 0, 0),
            ua_r=(-arm * s, 4, 0), ua_l=(arm * s, -4, 0),
            la_r=(elbow + 0.25 * arm * (1 - s), 0, 0), la_l=(elbow + 0.25 * arm * (1 + s), 0, 0),
            spine=(-lean, 0, 0), chest=(0, 0, twist * s), head=(lean * 0.5, 0, -twist * s * 0.5),
        ), 'lin'))
    return keys


def _atk(wind, strike, follow, wind_t=0.17, follow_t=0.55, pre=None):
    return [(0.0, pre or G), (wind_t, wind), (0.35, strike, 'in'), (follow_t, follow, 'out'), (1.0, G)]


def author_all(an):
    """an: char_lib.Animator"""
    # ---------------- locomotion ----------------
    an.clip("idle", 2.0, [(0.0, IDLE_A), (0.5, IDLE_B), (1.0, IDLE_A)], loop=True)
    an.clip("walk", 1.0, _cycle(None, leg=26, knee=38, arm=20, elbow=18, bob=0.03, lean=3, twist=7), loop=True)
    an.clip("run", 0.7, _cycle(None, leg=44, knee=70, arm=46, elbow=82, bob=0.05, lean=12, twist=10), loop=True)
    an.clip("sprint", 0.55, _cycle(None, leg=56, knee=88, arm=58, elbow=92, bob=0.065, lean=24, twist=12), loop=True)

    # ---------------- air ----------------
    crouch = P(hips_loc=(0, 0, -0.20), ul_r=(40, 0, -4), ul_l=(40, 0, 4), ll_r=(-75, 0, 0), ll_l=(-75, 0, 0),
               spine=(-18, 0, 0), ua_r=(-30, 0, 0), ua_l=(-30, 0, 0), la_r=(25, 0, 0), la_l=(25, 0, 0))
    launch = P(hips_loc=(0, 0, 0.03), ul_r=(-6, 0, -3), ul_l=(-6, 0, 3), ll_r=(-6, 0, 0), ll_l=(-6, 0, 0),
               spine=(4, 0, 0), ua_r=(70, -25, 0), ua_l=(70, 25, 0), la_r=(20, 0, 0), la_l=(20, 0, 0))
    an.clip("jump_start", 0.3, [(0.0, IDLE_A), (0.4, crouch), (1.0, launch, 'out')])
    fall_a = P(hips_loc=(0, 0, 0), ul_r=(22, 0, -8), ul_l=(-10, 0, 8), ll_r=(-40, 0, 0), ll_l=(-28, 0, 0),
               ua_r=(25, -52, 0), ua_l=(25, 52, 0), la_r=(25, 0, 0), la_l=(25, 0, 0), spine=(2, 0, 0))
    fall_b = P(hips_loc=(0, 0, 0.012), ul_r=(14, 0, -8), ul_l=(-4, 0, 8), ll_r=(-32, 0, 0), ll_l=(-36, 0, 0),
               ua_r=(32, -58, 0), ua_l=(32, 58, 0), la_r=(32, 0, 0), la_l=(32, 0, 0), spine=(4, 0, 0))
    an.clip("fall", 0.6, [(0.0, fall_a), (0.5, fall_b), (1.0, fall_a)], loop=True)
    land_low = P(hips_loc=(0, 0, -0.26), ul_r=(48, 0, -5), ul_l=(48, 0, 5), ll_r=(-88, 0, 0), ll_l=(-88, 0, 0),
                 spine=(-24, 0, 0), ua_r=(34, -12, 0), ua_l=(34, 12, 0), la_r=(34, 0, 0), la_l=(34, 0, 0))
    an.clip("land", 0.3, [(0.0, fall_a), (0.35, land_low, 'out'), (1.0, IDLE_A)])

    # ---------------- enemy stance ----------------
    g_a = G
    g_b = P(**{**G, 'hips_loc': (0, 0, -0.065), 'chest': (-1, 0, -9), 'ua_r': (60, 12, 0), 'ua_l': (50, -14, 0)})
    an.clip("guard", 1.0, [(0.0, g_a), (0.5, g_b), (1.0, g_a)], loop=True)

    # ---------------- attacks (strike at 35%) ----------------
    lunge_l = dict(ul_l=(32, 0, 6), ll_l=(-34, 0, 0), ul_r=(-24, 0, -4), ll_r=(-28, 0, 0))
    lunge_r = dict(ul_r=(32, 0, -6), ll_r=(-34, 0, 0), ul_l=(-24, 0, 4), ll_l=(-28, 0, 0))
    an.clip("light_1", 0.5, _atk(
        P(hips_loc=(0, -0.02, -0.08), chest=(0, 0, -38), spine=(-4, 0, -12), head=(0, 0, 20),
          ua_r=(125, 14, 30), la_r=(66, 0, 0), ua_l=(40, -15, 0), la_l=(75, 0, 0),
          ul_r=(-8, 0, -4), ll_r=(-30, 0, 0), ul_l=(10, 0, 6), ll_l=(-20, 0, 0)),
        P(hips_loc=(0, 0.08, -0.14), chest=(8, 0, 46), spine=(-6, 0, 14), head=(0, 0, -32),
          ua_r=(72, -26, -22), la_r=(12, 0, 0), ua_l=(-25, 20, 0), la_l=(50, 0, 0), **lunge_l),
        P(hips_loc=(0, 0.10, -0.15), chest=(10, 0, 56), spine=(-6, 0, 16), head=(0, 0, -36),
          ua_r=(56, -34, -30), la_r=(10, 0, 0), ua_l=(-30, 22, 0), la_l=(45, 0, 0), **lunge_l)))
    an.clip("light_2", 0.5, _atk(
        P(hips_loc=(0, -0.02, -0.08), chest=(0, 0, 36), spine=(-4, 0, 12), head=(0, 0, -20),
          ua_r=(62, -48, 34), la_r=(40, 0, 0), ua_l=(30, 10, 0), la_l=(80, 0, 0),
          ul_r=(10, 0, -6), ll_r=(-20, 0, 0), ul_l=(-8, 0, 4), ll_l=(-30, 0, 0)),
        P(hips_loc=(0, 0.08, -0.14), chest=(6, 0, -44), spine=(-6, 0, -14), head=(0, 0, 30),
          ua_r=(84, 30, 24), la_r=(8, 0, 0), ua_l=(-20, -10, 0), la_l=(50, 0, 0), **lunge_r),
        P(hips_loc=(0, 0.10, -0.15), chest=(8, 0, -54), spine=(-6, 0, -16), head=(0, 0, 34),
          ua_r=(74, 40, 30), la_r=(8, 0, 0), ua_l=(-25, -10, 0), la_l=(45, 0, 0), **lunge_r)))
    an.clip("light_3", 0.6, _atk(
        P(hips_loc=(0, -0.03, -0.10), chest=(0, 0, -22), spine=(2, 0, -6), head=(0, 0, 12),
          ua_r=(-28, 8, -10), la_r=(112, 0, 0), ua_l=(48, -12, 0), la_l=(72, 0, 0),
          ul_r=(-10, 0, -4), ll_r=(-34, 0, 0), ul_l=(12, 0, 6), ll_l=(-22, 0, 0)),
        P(hips_loc=(0, 0.14, -0.18), chest=(0, 0, 16), spine=(-16, 0, 6), head=(6, 0, -14),
          ua_r=(88, 4, 0), la_r=(0, 0, 0), ua_l=(-18, 14, 0), la_l=(48, 0, 0),
          ul_l=(40, 0, 6), ll_l=(-40, 0, 0), ul_r=(-28, 0, -4), ll_r=(-30, 0, 0)),
        P(hips_loc=(0, 0.15, -0.19), chest=(0, 0, 20), spine=(-18, 0, 8), head=(6, 0, -16),
          ua_r=(84, 6, 0), la_r=(2, 0, 0), ua_l=(-20, 14, 0), la_l=(45, 0, 0),
          ul_l=(42, 0, 6), ll_l=(-42, 0, 0), ul_r=(-30, 0, -4), ll_r=(-32, 0, 0)), wind_t=0.2))
    an.clip("heavy", 0.8, _atk(
        P(hips_loc=(0, -0.02, -0.12), spine=(24, 0, 0), chest=(6, 0, -6), head=(8, 0, 0),
          ua_r=(168, 8, 0), la_r=(86, 0, 0), ua_l=(150, -8, 0), la_l=(82, 0, 0),
          ul_r=(-14, 0, -5), ll_r=(-34, 0, 0), ul_l=(8, 0, 5), ll_l=(-24, 0, 0)),
        P(hips_loc=(0, 0.14, -0.24), spine=(-40, 0, 0), chest=(-6, 0, 4), head=(-8, 0, 0),
          ua_r=(46, 0, 0), la_r=(8, 0, 0), ua_l=(40, 0, 0), la_l=(12, 0, 0),
          ul_l=(38, 0, 5), ll_l=(-46, 0, 0), ul_r=(-26, 0, -5), ll_r=(-36, 0, 0)),
        P(hips_loc=(0, 0.15, -0.25), spine=(-42, 0, 0), chest=(-6, 0, 4), head=(-8, 0, 0),
          ua_r=(40, 0, 0), la_r=(6, 0, 0), ua_l=(36, 0, 0), la_l=(10, 0, 0),
          ul_l=(40, 0, 5), ll_l=(-48, 0, 0), ul_r=(-28, 0, -5), ll_r=(-38, 0, 0)), wind_t=0.22, follow_t=0.6))
    an.clip("sprint_attack", 0.6, _atk(
        P(hips_loc=(0, 0.0, -0.10), spine=(-22, 0, 0), chest=(0, 0, -28), head=(10, 0, 18),
          ua_r=(-22, 8, 0), la_r=(34, 0, 0), ua_l=(30, -10, 0), la_l=(70, 0, 0),
          ul_r=(42, 0, -3), ll_r=(-50, 0, 0), ul_l=(-36, 0, 3), ll_l=(-30, 0, 0)),
        P(hips_loc=(0, 0.16, -0.20), spine=(-30, 0, 6), chest=(6, 0, 36), head=(10, 0, -24),
          ua_r=(82, -22, -26), la_r=(10, 0, 0), ua_l=(-30, 16, 0), la_l=(42, 0, 0),
          ul_l=(48, 0, 4), ll_l=(-50, 0, 0), ul_r=(-44, 0, -4), ll_r=(-62, 0, 0)),
        P(hips_loc=(0, 0.18, -0.20), spine=(-32, 0, 6), chest=(8, 0, 44), head=(10, 0, -28),
          ua_r=(68, -30, -30), la_r=(10, 0, 0), ua_l=(-32, 16, 0), la_l=(40, 0, 0),
          ul_l=(50, 0, 4), ll_l=(-52, 0, 0), ul_r=(-46, 0, -4), ll_r=(-64, 0, 0))))
    an.clip("air_attack", 0.5, _atk(
        P(hips_loc=(0, 0, 0.04), spine=(14, 0, 0), ul_r=(48, 0, -5), ul_l=(48, 0, 5), ll_r=(-72, 0, 0),
          ll_l=(-72, 0, 0), ua_r=(150, 8, 0), la_r=(54, 0, 0), ua_l=(62, -18, 0), la_l=(60, 0, 0)),
        P(hips_loc=(0, 0.06, -0.02), spine=(-34, 0, 0), ul_r=(10, 0, -4), ul_l=(22, 0, 4), ll_r=(-14, 0, 0),
          ll_l=(-24, 0, 0), ua_r=(58, 0, 0), la_r=(6, 0, 0), ua_l=(38, -8, 0), la_l=(30, 0, 0)),
        P(hips_loc=(0, 0.07, -0.02), spine=(-36, 0, 0), ul_r=(8, 0, -4), ul_l=(20, 0, 4), ll_r=(-12, 0, 0),
          ll_l=(-22, 0, 0), ua_r=(54, 0, 0), la_r=(6, 0, 0), ua_l=(36, -8, 0), la_l=(28, 0, 0)), wind_t=0.2))

    spin_arm = dict(ua_r=(0, -86, 0), la_r=(4, 0, 0), ua_l=(0, 86, 0), la_l=(4, 0, 0))
    low = dict(ul_r=(26, 0, -14), ul_l=(26, 0, 14), ll_r=(-48, 0, 0), ll_l=(-48, 0, 0), spine=(-8, 0, 0))
    an.clip("spin", 0.7, [
        (0.0, G),
        (0.15, P(hips_loc=(0, 0, -0.16), chest=(0, 0, 0), **{**low, **spin_arm}) | {'hips': (0, 0, -50)}),
        (0.35, P(hips_loc=(0, 0, -0.18), **{**low, **spin_arm}) | {'hips': (0, 0, 120)}, 'in'),
        (0.65, P(hips_loc=(0, 0, -0.18), **{**low, **spin_arm}) | {'hips': (0, 0, 250)}, 'lin'),
        (0.85, P(hips_loc=(0, 0, -0.12), **{**low, **spin_arm}) | {'hips': (0, 0, 360)}, 'out'),
        (1.0, G)])

    tuck = dict(ul_r=(92, 0, -4), ul_l=(92, 0, 4), ll_r=(-118, 0, 0), ll_l=(-118, 0, 0),
                ua_r=(66, 10, 0), ua_l=(66, -10, 0), la_r=(110, 0, 0), la_l=(110, 0, 0), spine=(-34, 0, 0),
                head=(-20, 0, 0))
    an.clip("dodge", 0.5, [
        (0.0, G),
        (0.14, P(hips_loc=(0, 0.05, -0.22), **tuck)),
        (0.5, P(hips_loc=(0, 0.2, -0.50), **tuck) | {'hips': (-180, 0, 0)}, 'lin'),
        (0.82, P(hips_loc=(0, 0.35, -0.42), **tuck) | {'hips': (-340, 0, 0)}, 'lin'),
        (1.0, P(hips_loc=(0, 0.38, -0.14), spine=(-12, 0, 0), ul_r=(30, 0, -4), ul_l=(30, 0, 4),
                ll_r=(-50, 0, 0), ll_l=(-50, 0, 0), ua_r=(40, 0, 0), ua_l=(40, 0, 0), la_r=(60, 0, 0),
                la_l=(60, 0, 0)) | {'hips': (-360, 0, 0)}, 'out')])

    hit_pose = P(hips_loc=(0, -0.05, -0.05), spine=(24, 0, 4), chest=(10, 0, 6), head=(20, 0, -8),
                 ua_r=(34, -26, 0), ua_l=(34, 26, 0), la_r=(46, 0, 0), la_l=(46, 0, 0),
                 ul_r=(-12, 0, -4), ul_l=(10, 0, 4), ll_r=(-18, 0, 0), ll_l=(-18, 0, 0))
    an.clip("hit", 0.35, [(0.0, G), (0.25, hit_pose, 'out'), (1.0, G)])

    dead_a = P(hips_loc=(0, -0.10, -0.46), spine=(18, 0, 0), chest=(10, 0, 0), head=(20, 0, 8),
               ua_r=(20, -40, 0), ua_l=(30, 36, 0), la_r=(30, 0, 0), la_l=(24, 0, 0),
               ul_r=(30, 0, -8), ul_l=(10, 0, 8), ll_r=(-40, 0, 0), ll_l=(-30, 0, 0)) | {'hips': (45, 0, 0)}
    dead_b = P(hips_loc=(0, -0.28, -0.80), spine=(6, 0, 0), chest=(4, 0, 0), head=(14, 0, 10),
               ua_r=(12, -55, 0), ua_l=(14, 48, 0), la_r=(12, 0, 0), la_l=(18, 0, 0),
               ul_r=(8, 0, -10), ul_l=(4, 0, 12), ll_r=(-10, 0, 0), ll_l=(-16, 0, 0)) | {'hips': (88, 0, 0)}
    an.clip("death", 1.2, [(0.0, G), (0.12, hit_pose, 'out'), (0.42, dead_a, 'in'), (0.7, dead_b, 'out'),
                           (1.0, dead_b)])

    # ---------------- boss clips ----------------
    two_hand_up = dict(ua_r=(176, 6, 0), la_r=(96, 0, 0), ua_l=(170, -6, 0), la_l=(94, 0, 0))
    an.clip("slam", 1.2, [
        (0.0, G),
        (0.20, P(hips_loc=(0, -0.03, -0.12), spine=(30, 0, 0), chest=(6, 0, -6), head=(10, 0, 0),
                 ul_r=(-14, 0, -5), ll_r=(-34, 0, 0), ul_l=(8, 0, 5), ll_l=(-24, 0, 0), **two_hand_up)),
        (0.35, P(hips_loc=(0, 0.16, -0.30), spine=(-44, 0, 0), chest=(-6, 0, 4), head=(-10, 0, 0),
                 ua_r=(38, 0, 0), la_r=(6, 0, 0), ua_l=(34, 0, 0), la_l=(8, 0, 0),
                 ul_l=(40, 0, 5), ll_l=(-50, 0, 0), ul_r=(-28, 0, -5), ll_r=(-38, 0, 0)), 'in'),
        (0.62, P(hips_loc=(0, 0.17, -0.31), spine=(-46, 0, 0), ua_r=(34, 0, 0), la_r=(6, 0, 0), ua_l=(30, 0, 0),
                 la_l=(8, 0, 0), ul_l=(42, 0, 5), ll_l=(-52, 0, 0), ul_r=(-30, 0, -5), ll_r=(-40, 0, 0)), 'out'),
        (1.0, G)])
    an.clip("flurry", 0.8, [
        (0.0, G),
        (0.15, P(hips_loc=(0, -0.02, -0.10), chest=(0, 0, -40), spine=(-4, 0, -12), head=(0, 0, 22),
                 ua_r=(120, 14, 30), la_r=(66, 0, 0), ua_l=(40, -15, 0), la_l=(75, 0, 0),
                 ul_r=(-8, 0, -4), ll_r=(-30, 0, 0), ul_l=(10, 0, 6), ll_l=(-20, 0, 0))),
        (0.35, P(hips_loc=(0, 0.10, -0.15), chest=(8, 0, 48), spine=(-6, 0, 14), head=(0, 0, -32),
                 ua_r=(74, -26, -22), la_r=(12, 0, 0), ua_l=(-25, 20, 0), la_l=(50, 0, 0), **lunge_l), 'in'),
        (0.52, P(hips_loc=(0, 0.06, -0.12), chest=(0, 0, 36), spine=(-4, 0, 10), head=(0, 0, -16),
                 ua_r=(64, -46, 34), la_r=(40, 0, 0), ua_l=(30, 10, 0), la_l=(80, 0, 0),
                 ul_r=(10, 0, -6), ll_r=(-20, 0, 0), ul_l=(-6, 0, 4), ll_l=(-30, 0, 0)), 'out'),
        (0.7, P(hips_loc=(0, 0.14, -0.16), chest=(6, 0, -46), spine=(-8, 0, -14), head=(0, 0, 32),
                ua_r=(86, 30, 24), la_r=(8, 0, 0), ua_l=(-20, -10, 0), la_l=(50, 0, 0), **lunge_r), 'in'),
        (1.0, G)])
    an.clip("shockwave_cast", 1.0, [
        (0.0, G),
        (0.2, P(hips_loc=(0, -0.02, -0.12), spine=(24, 0, 0), head=(8, 0, 0), ua_r=(172, 4, 0), la_r=(88, 0, 0),
                ua_l=(60, -20, 0), la_l=(90, 0, 0), ul_r=(-12, 0, -5), ll_r=(-34, 0, 0), ul_l=(6, 0, 5),
                ll_l=(-24, 0, 0))),
        (0.35, P(hips_loc=(0, 0.14, -0.34), spine=(-38, 0, 0), head=(-10, 0, 0), ua_r=(26, 0, 0), la_r=(4, 0, 0),
                 ua_l=(34, 20, 0), la_l=(30, 0, 0), ul_l=(40, 0, 5), ll_l=(-52, 0, 0), ul_r=(-26, 0, -5),
                 ll_r=(-40, 0, 0)), 'in'),
        (0.7, P(hips_loc=(0, 0.14, -0.34), spine=(-38, 0, 0), head=(-10, 0, 0), ua_r=(26, 0, 0), la_r=(4, 0, 0),
                ua_l=(34, 20, 0), la_l=(30, 0, 0), ul_l=(40, 0, 5), ll_l=(-52, 0, 0), ul_r=(-26, 0, -5),
                ll_r=(-40, 0, 0)), 'lin'),
        (1.0, G)])
    roar = P(hips_loc=(0, -0.02, 0.0), spine=(20, 0, 0), chest=(10, 0, 0), head=(30, 0, 0),
             ua_r=(18, -76, 0), ua_l=(18, 76, 0), la_r=(24, 0, 0), la_l=(24, 0, 0),
             ul_r=(8, 0, -8), ul_l=(8, 0, 8), ll_r=(-12, 0, 0), ll_l=(-12, 0, 0))
    an.clip("roar", 1.5, [(0.0, G), (0.35, roar, 'out'), (0.7, roar, 'lin'), (1.0, G)])


CLIP_SPECS = {  # name: nominal length in seconds
    "idle": 2.0, "walk": 1.0, "run": 0.7, "sprint": 0.55, "jump_start": 0.3, "fall": 0.6, "land": 0.3,
    "light_1": 0.5, "light_2": 0.5, "light_3": 0.6, "heavy": 0.8, "sprint_attack": 0.6, "air_attack": 0.5,
    "spin": 0.7, "dodge": 0.5, "hit": 0.35, "death": 1.2, "guard": 1.0,
    "slam": 1.2, "flurry": 0.8, "shockwave_cast": 1.0, "roar": 1.5,
}
