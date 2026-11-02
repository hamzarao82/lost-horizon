"""Shared library for generating the Lost Horizon characters in Blender (run with `blender --background --python`).

World convention while modelling (Blender): +Z up, character faces +Y, character's right side is +X.
The glTF exporter converts this to Y-up with the character facing -Z, which is what Godot expects.
All lengths are metres for a 1.80 m character; the Builder scales everything by height / 1.8.
Everything is deterministic: no randomness anywhere.
"""
import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix, Euler

FPS = 30

# name, head, tail, parent  (17 bones, exact names are part of the contract with the engine adapter)
BONE_DEFS = [
    ("Hips", (0, 0, 0.92), (0, 0, 1.02), None),
    ("Spine", (0, 0, 1.02), (0, 0, 1.16), "Hips"),
    ("Chest", (0, 0, 1.16), (0, 0, 1.42), "Spine"),
    ("Neck", (0, 0, 1.42), (0, 0, 1.52), "Chest"),
    ("Head", (0, 0, 1.52), (0, 0, 1.78), "Neck"),
    ("UpperArm_R", (0.20, 0, 1.40), (0.31, 0, 1.13), "Chest"),
    ("LowerArm_R", (0.31, 0, 1.13), (0.34, 0.10, 0.90), "UpperArm_R"),
    ("Hand_R", (0.34, 0.10, 0.90), (0.35, 0.17, 0.82), "LowerArm_R"),
    ("UpperArm_L", (-0.20, 0, 1.40), (-0.31, 0, 1.13), "Chest"),
    ("LowerArm_L", (-0.31, 0, 1.13), (-0.34, 0.10, 0.90), "UpperArm_L"),
    ("Hand_L", (-0.34, 0.10, 0.90), (-0.35, 0.17, 0.82), "LowerArm_L"),
    ("UpperLeg_R", (0.10, 0, 0.92), (0.10, 0, 0.50), "Hips"),
    ("LowerLeg_R", (0.10, 0, 0.50), (0.10, 0, 0.09), "UpperLeg_R"),
    ("Foot_R", (0.10, 0, 0.09), (0.10, 0.15, 0.04), "LowerLeg_R"),
    ("UpperLeg_L", (-0.10, 0, 0.92), (-0.10, 0, 0.50), "Hips"),
    ("LowerLeg_L", (-0.10, 0, 0.50), (-0.10, 0, 0.09), "UpperLeg_L"),
    ("Foot_L", (-0.10, 0, 0.09), (-0.10, 0.15, 0.04), "LowerLeg_L"),
]
BONE_NAMES = [b[0] for b in BONE_DEFS]

ALIAS = {
    "hips": "Hips", "spine": "Spine", "chest": "Chest", "neck": "Neck", "head": "Head",
    "ua_r": "UpperArm_R", "la_r": "LowerArm_R", "h_r": "Hand_R",
    "ua_l": "UpperArm_L", "la_l": "LowerArm_L", "h_l": "Hand_L",
    "ul_r": "UpperLeg_R", "ll_r": "LowerLeg_R", "f_r": "Foot_R",
    "ul_l": "UpperLeg_L", "ll_l": "LowerLeg_L", "f_l": "Foot_L",
}


def hexcol(h):
    """sRGB hex string -> linear RGB tuple (glTF vertex colours are linear)."""
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(math.pow(x, 2.2) for x in c)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scn = bpy.context.scene
    scn.render.fps = FPS
    scn.unit_settings.system = 'METRIC'


class Builder:
    def __init__(self, name, height=1.8, bulk=1.0):
        self.name = name
        self.height = height
        self.s = height / 1.8
        self.bulk = bulk
        self.bm = bmesh.new()
        self.deform = self.bm.verts.layers.deform.verify()
        self.col = self.bm.verts.layers.float_color.new("Col")
        self.claim = self.bm.verts.layers.int.new("claimed")  # 0 = not yet part of any part (bmesh wrappers are not stable, so no identity sets)
        self.gidx = {n: i for i, n in enumerate(BONE_NAMES)}
        self.mesh_obj = None
        self.arm = None

    # ---- internals -------------------------------------------------------------------
    def _paint(self, verts, bone, color, ao=True):
        zs = [v.co.z for v in verts]
        z0, z1 = min(zs), max(zs)
        rng = max(z1 - z0, 1e-5)
        for v in verts:
            k = 0.78 + 0.22 * ((v.co.z - z0) / rng) if ao else 1.0
            v[self.deform].clear()
            v[self.deform][self.gidx[bone]] = 1.0
            v[self.claim] = 1
            v[self.col] = (color[0] * k, color[1] * k, color[2] * k, 1.0)

    def _new_verts(self, before):
        return [v for v in self.bm.verts if v[self.claim] == 0]

    def _smooth(self, verts, smooth):
        for f in {f for v in verts for f in v.link_faces}:
            f.smooth = smooth

    # ---- primitives (lengths for a 1.8 m character; scaled here) ----------------------------
    def box(self, bone, center, size, color, bevel=0.012, rot=(0, 0, 0), bk=False, ao=True):
        """Bevelled box. bk=True multiplies the x/y thickness by the character's bulk."""
        before = None
        sx, sy, sz = size
        if bk:
            sx *= self.bulk
            sy *= self.bulk
        s = self.s
        rot_m = Euler([math.radians(a) for a in rot], 'XYZ').to_matrix().to_4x4()
        M = Matrix.Translation(Vector(center) * s) @ rot_m @ Matrix.Diagonal(Vector((sx * s, sy * s, sz * s, 1.0)))
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=M)
        if bevel > 0:
            edges = list({e for v in r['verts'] for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=edges, offset=min(bevel * s, 0.45 * min(sx, sy, sz) * s),
                            segments=1, affect='EDGES', clamp_overlap=True)
        verts = self._new_verts(before)
        self._smooth(verts, False)
        self._paint(verts, bone, color, ao)

    def limb(self, bone, p0, p1, r0, r1, color, sides=10, bk=True, ell=(1.0, 1.0), cap=True, ao=True):
        """Tapered cylinder from p0 (radius r0) to p1 (radius r1)."""
        before = None
        s = self.s
        a, b = Vector(p0) * s, Vector(p1) * s
        d = b - a
        length = d.length
        k = self.bulk if bk else 1.0
        rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        scale = Matrix.Diagonal(Vector((ell[0], ell[1], 1.0, 1.0)))
        M = Matrix.Translation((a + b) * 0.5) @ rot @ scale
        r = bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False, segments=sides,
                                  radius1=r0 * s * k, radius2=r1 * s * k, depth=length, matrix=M)
        verts = self._new_verts(before)
        self._smooth(verts, True)
        self._paint(verts, bone, color, ao)

    def sphere(self, bone, center, radii, color, subdiv=1, bk=False, ao=True, smooth=True):
        before = None
        s = self.s
        k = self.bulk if bk else 1.0
        M = Matrix.Translation(Vector(center) * s) @ Matrix.Diagonal(
            Vector((radii[0] * s * k, radii[1] * s * k, radii[2] * s, 1.0)))
        bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=1.0, matrix=M)
        verts = self._new_verts(before)
        self._smooth(verts, smooth)
        self._paint(verts, bone, color, ao)

    # ---- finishing ---------------------------------------------------------------------------
    def finish(self):
        mesh = bpy.data.meshes.new(self.name + "_mesh")
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new("Body", mesh)
        bpy.context.collection.objects.link(obj)
        for n in BONE_NAMES:
            obj.vertex_groups.new(name=n)
        mesh.color_attributes.active_color = mesh.color_attributes["Col"]
        mesh.color_attributes.render_color_index = mesh.color_attributes.find("Col")
        mat = bpy.data.materials.new("CharMat")
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.8
        bsdf.inputs["Metallic"].default_value = 0.0
        mesh.materials.append(mat)
        self.mesh_obj = obj

        arm_data = bpy.data.armatures.new("Armature")
        arm = bpy.data.objects.new("Armature", arm_data)
        bpy.context.collection.objects.link(arm)
        bpy.context.view_layer.objects.active = arm
        arm.select_set(True)
        bpy.ops.object.mode_set(mode='EDIT')
        s = self.s
        for name, head, tail, parent in BONE_DEFS:
            eb = arm_data.edit_bones.new(name)
            eb.head = Vector(head) * s
            eb.tail = Vector(tail) * s
            if parent:
                eb.parent = arm_data.edit_bones[parent]
        bpy.ops.object.mode_set(mode='OBJECT')
        obj.parent = arm
        mod = obj.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
        self.arm = arm
        return obj, arm

    def tri_count(self):
        me = self.mesh_obj.data
        me.calc_loop_triangles()
        return len(me.loop_triangles)


# ---- animation authoring --------------------------------------------------------------------------
def P(**kw):
    """Pose: bone alias -> (rx, ry, rz) degrees about armature axes; 'hips_loc' -> (x, y, z) metres."""
    return dict(kw)


def _ease(u, mode):
    u = max(0.0, min(1.0, u))
    if mode == 'lin':
        return u
    if mode == 'in':
        return u * u
    if mode == 'out':
        return 1.0 - (1.0 - u) * (1.0 - u)
    return u * u * (3.0 - 2.0 * u)


def blend_pose(a, b, u):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k), b.get(k)
        if k == 'hips_loc':
            va, vb = va or (0, 0, 0), vb or (0, 0, 0)
        else:
            va, vb = va or (0, 0, 0), vb or (0, 0, 0)
        out[k] = tuple(va[i] + (vb[i] - va[i]) * u for i in range(3))
    return out


def sample(keys, t):
    """keys: [(frac, pose[, ease])] sorted by frac. Returns the interpolated pose at fraction t."""
    if t <= keys[0][0]:
        return keys[0][1]
    for i in range(len(keys) - 1):
        f0, p0 = keys[i][0], keys[i][1]
        f1, p1 = keys[i + 1][0], keys[i + 1][1]
        mode = keys[i + 1][2] if len(keys[i + 1]) > 2 else 'smooth'
        if t <= f1:
            u = (t - f0) / max(f1 - f0, 1e-6)
            return blend_pose(p0, p1, _ease(u, mode))
    return keys[-1][1]


class Animator:
    def __init__(self, arm, scale):
        self.arm = arm
        self.s = scale
        self.actions = {}
        arm.animation_data_create()
        self.rest = {}
        for pb in arm.pose.bones:
            pb.rotation_mode = 'QUATERNION'
            self.rest[pb.name] = pb.bone.matrix_local.to_3x3()

    def _apply(self, pose, frame):
        for name in BONE_NAMES:
            pb = self.arm.pose.bones[name]
            eul = pose.get(name)
            if eul is None:
                for al, full in ALIAS.items():
                    if full == name and al in pose:
                        eul = pose[al]
            eul = eul or (0.0, 0.0, 0.0)
            R = self.rest[name]
            W = Euler([math.radians(a) for a in eul], 'XYZ').to_matrix()
            pb.rotation_quaternion = (R.inverted() @ W @ R).to_quaternion()
            pb.keyframe_insert('rotation_quaternion', frame=frame)
            if name == 'Hips':
                loc = Vector(pose.get('hips_loc', (0, 0, 0))) * self.s
                pb.location = self.rest[name].inverted() @ loc
                pb.keyframe_insert('location', frame=frame)

    def clip(self, name, duration, keys, loop=False):
        """Author one action at 30 fps. Looping clips must start and end on the same pose."""
        # normalise aliases up front
        norm = []
        for k in keys:
            pose = {}
            for key, val in k[1].items():
                pose[ALIAS.get(key, key)] = val
            norm.append((k[0], pose) + tuple(k[2:]))
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        self.arm.animation_data.action = act
        n = max(2, int(round(duration * FPS)))
        for f in range(n + 1):
            self._apply(sample(norm, f / n), 1 + f)
        self.actions[name] = act
        # park the action on its own NLA track so the exporter finds every clip by name
        track = self.arm.animation_data.nla_tracks.new()
        track.name = name
        strip = track.strips.new(name, 1, act)
        strip.name = name
        self.arm.animation_data.action = None
        return act


# ---- export / render -------------------------------------------------------------------------------
def export_glb(path, arm, mesh_obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    kwargs = dict(
        filepath=path, export_format='GLB', use_selection=True, export_apply=False,
        export_animations=True, export_animation_mode='NLA_TRACKS',
        export_force_sampling=True, export_frame_step=1,
        export_optimize_animation_size=False, export_skins=True,
        export_materials='EXPORT', export_image_format='NONE', export_yup=True,
        export_vertex_color='ACTIVE', export_active_vertex_color_when_no_material=True,
        export_normals=True, export_cameras=False, export_lights=False,
    )
    bpy.ops.export_scene.gltf(**kwargs)


def _world():
    w = bpy.data.worlds.new("W")
    w.color = (0.30, 0.34, 0.40)
    bpy.context.scene.world = w


def _camera(loc, target, ortho):
    cam_d = bpy.data.cameras.new("Cam")
    cam_d.type = 'ORTHO'
    cam_d.ortho_scale = ortho
    cam = bpy.data.objects.new("Cam", cam_d)
    bpy.context.collection.objects.link(cam)
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    return cam


def render_sheet(builder, anim, out_png, shots, weapon_len=0.9, pane=(380, 420), weapon=True):
    """shots: list of (clip or None, time fraction, view) ; view in front|side|three|back."""
    import numpy as np
    scn = bpy.context.scene
    scn.render.engine = 'BLENDER_WORKBENCH'
    scn.render.resolution_x, scn.render.resolution_y = pane
    scn.render.image_settings.file_format = 'PNG'
    scn.display.shading.light = 'STUDIO'
    scn.display.shading.color_type = 'VERTEX'
    scn.display.shading.show_shadows = True
    scn.display.shading.show_cavity = False
    scn.view_settings.view_transform = 'Standard'
    _world()
    s = builder.s
    mid = Vector((0, 0, 0.93 * s))
    views = {
        'front': Vector((0, 4.0, 0.93 * s)),
        'back': Vector((0, -4.0, 0.93 * s)),
        'side': Vector((4.0, 0, 0.93 * s)),
        'three': Vector((2.6, 2.9, 1.25 * s)),
    }
    ortho = 2.35 * s
    if weapon:
        add_preview_weapon(builder, 0.9)
    imgs = []
    tmp_dir = os.path.dirname(out_png)
    for idx, (clip, frac, view) in enumerate(shots):
        cam = _camera(views[view], mid, ortho)
        scn.camera = cam
        for tr in builder.arm.animation_data.nla_tracks:
            tr.mute = True
        builder.arm.animation_data.action = None
        if clip:
            act = anim.actions[clip]
            for tr in builder.arm.animation_data.nla_tracks:
                tr.mute = (tr.name != clip)
            f0, f1 = act.frame_range
            scn.frame_set(int(round(f0 + (f1 - f0) * frac)))
        else:
            for pb in builder.arm.pose.bones:
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.location = (0, 0, 0)
            scn.frame_set(1)
        bpy.context.view_layer.update()
        p = os.path.join(tmp_dir, "_pane%d.png" % idx)
        scn.render.filepath = p
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(p)
        w, h = img.size
        arr = np.array(img.pixels[:]).reshape(h, w, 4)
        imgs.append(arr)
        bpy.data.images.remove(img)
        os.remove(p)
        bpy.data.objects.remove(cam)
    sheet = np.concatenate(imgs, axis=1)
    h, w = sheet.shape[0], sheet.shape[1]
    out = bpy.data.images.new("sheet", w, h)
    out.pixels = sheet.flatten().tolist()
    out.filepath_raw = out_png
    out.file_format = 'PNG'
    out.save()


# ---- weapon socket -----------------------------------------------------------------------------------
BLADE_ANGLE_DEG = -30.0  # blade angle from the hand axis, about the hand bone local X (chosen with tools/blender/probe.py)


def socket_info(builder, angle=None):
    """Recommended in-hand transform of a weapon scene (grip at its origin, blade along its -Z) relative to
    the Hand_R bone, expressed in the bone's local frame. After the glTF import this is the local transform of
    a BoneAttachment3D child in Godot. Also returns the Hand_R rest basis in Godot model space (for verification).
    """
    arm = builder.arm
    bone = arm.data.bones["Hand_R"]
    Rb = bone.matrix_local.to_3x3()
    ang = math.radians(BLADE_ANGLE_DEG if angle is None else angle)
    d_bone = Vector((0.0, math.cos(ang), math.sin(ang)))  # blade direction in the bone-local frame
    up_bone = Rb.inverted() @ Vector((0, 0, 1))
    zw = -d_bone
    yw = (up_bone - up_bone.dot(zw) * zw).normalized()
    xw = yw.cross(zw).normalized()
    B = Matrix(((xw.x, yw.x, zw.x), (xw.y, yw.y, zw.y), (xw.z, yw.z, zw.z)))
    q = B.to_quaternion()
    C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))  # Blender (x, y, z) -> glTF/Godot (x, z, -y)
    rest_godot = C @ Rb
    return {
        "bone": "Hand_R",
        "offset_position": [0.0, 0.03 * builder.s, 0.0],
        "offset_quaternion_xyzw": [q.x, q.y, q.z, q.w],
        "offset_euler_deg_xyz": [math.degrees(a) for a in q.to_euler('XYZ')],
        "hand_r_rest_basis_godot_columns": [list(rest_godot.col[i]) for i in range(3)],
        "note": "Weapon scene: grip at origin, blade along -Z. Apply as BoneAttachment3D(bone_name=Hand_R) child "
                "transform = Transform3D(Basis(Quaternion(x,y,z,w)), offset_position).",
    }


def add_preview_weapon(builder, length=0.9, angle=None):
    """Preview-only sword (never exported) attached the way the engine will attach weapons."""
    info = socket_info(builder, angle)
    s = builder.s
    me = bpy.data.meshes.new("PreviewSword")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, 0, -length * 0.55 * s)) @ Matrix.Diagonal(
        Vector((0.05 * s, 0.014 * s, length * s * 0.9, 1))))
    bmesh.ops.create_cube(bm, size=1.0, matrix=Matrix.Translation((0, 0, -0.1 * s)) @ Matrix.Diagonal(
        Vector((0.16 * s, 0.03 * s, 0.03 * s, 1))))
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new("PreviewSword", me)
    bpy.context.collection.objects.link(obj)
    obj.parent = builder.arm
    obj.parent_type = 'BONE'
    obj.parent_bone = "Hand_R"
    blen = (builder.arm.data.bones["Hand_R"].tail_local - builder.arm.data.bones["Hand_R"].head_local).length
    q = info["offset_quaternion_xyzw"]
    from mathutils import Quaternion
    rot = Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4()
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = Matrix.Translation((0, -blen, 0)) @ Matrix.Translation(info["offset_position"]) @ rot
    mat = bpy.data.materials.new("PreviewSwordMat")
    mat.diffuse_color = (0.85, 0.88, 0.95, 1)
    me.materials.append(mat)
    return obj
