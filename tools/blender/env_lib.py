"""Helpers for building the Outpost 17 environment kit in Blender (run headless).

Coordinates inside Blender: +Z up, X length, and the FRONT of every piece faces +Y.
The glTF exporter converts Blender +Y to glTF -Z, so in Godot the front faces -Z and +Y stays up.
Every piece is a single mesh with one shared vertex-colour material (COLOR_0), origin at the base centre.
"""
import math
import random
import bpy
import bmesh
from mathutils import Vector, Matrix, Euler

# Palette in sRGB; converted to linear when painted (Godot reads vertex colours as linear).
PAL = {
    "olive": (0.32, 0.38, 0.27), "khaki": (0.58, 0.54, 0.38), "rust": (0.50, 0.26, 0.17),
    "steel": (0.45, 0.47, 0.50), "dark_steel": (0.22, 0.24, 0.27), "wood": (0.44, 0.31, 0.20),
    "wood_dark": (0.30, 0.21, 0.14), "canvas": (0.82, 0.78, 0.66), "sandbag": (0.62, 0.56, 0.40),
    "concrete": (0.55, 0.54, 0.50), "red": (0.58, 0.14, 0.10), "blue": (0.12, 0.33, 0.48),
    "green": (0.27, 0.35, 0.24), "trunk": (0.42, 0.31, 0.20), "leaf_dark": (0.08, 0.24, 0.07),
    "leaf_light": (0.20, 0.40, 0.10), "stone": (0.36, 0.33, 0.30), "char": (0.18, 0.17, 0.16),
    "white": (0.90, 0.88, 0.80), "banner": (0.60, 0.10, 0.10), "black": (0.07, 0.07, 0.08),
    "glass": (0.12, 0.17, 0.20), "hazard": (0.85, 0.65, 0.12),
}


def lin(c):
    # Godot treats vertex colours as linear albedo, and the existing arena decor feeds its palette in
    # unconverted (so it reads bright and warm). Keep the kit on the same convention.
    return tuple(c[:3])


def _srgb_to_linear(c):
    return tuple((x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c[:3])


def shade(c, k):
    return tuple(min(1.0, max(0.0, x * k)) for x in c[:3])


_MAT = None


def kit_material():
    global _MAT
    if _MAT is None:
        mat = bpy.data.materials.new("kit_vertex_color")
        mat.use_nodes = True
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.9
        bsdf.inputs["Metallic"].default_value = 0.0
        _MAT = mat
    return _MAT


class Piece:
    def __init__(self, name, seed=None):
        self.name = name
        self.bm = bmesh.new()
        self.cl = self.bm.loops.layers.float_color.new("Col")
        self.rng = random.Random(seed if seed is not None else sum(ord(ch) * (i + 1) for i, ch in enumerate(name)))
        self.sealed = False

    # -- painting ------------------------------------------------------------
    def _faces_of(self, verts):
        faces = set()
        for v in verts:
            faces.update(v.link_faces)
        return faces

    def _paint(self, faces, color, jitter=0.05, grime=True):
        base = lin(color)
        for f in faces:
            k = 1.0 + self.rng.uniform(-jitter, jitter)
            for loop in f.loops:
                z = loop.vert.co.z
                g = 1.0 - (max(0.0, 0.7 - z) / 0.7) * 0.25 if grime else 1.0
                loop[self.cl] = (min(1.0, base[0] * k * g), min(1.0, base[1] * k * g), min(1.0, base[2] * k * g), 1.0)

    # -- primitives ----------------------------------------------------------
    def box(self, c, s, color, rot=(0, 0, 0), jitter=0.05):
        m = Matrix.Translation(Vector(c)) @ Euler(rot, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((s[0], s[1], s[2], 1.0))
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._paint(self._faces_of(r["verts"]), color, jitter)

    def beam(self, p0, p1, th, color, jitter=0.05):
        p0 = Vector(p0)
        p1 = Vector(p1)
        d = p1 - p0
        length = d.length
        if length < 1e-6:
            return
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((th, th, length, 1.0))
        r = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)
        self._paint(self._faces_of(r["verts"]), color, jitter)

    def frustum(self, p0, p1, r0, r1, sides, color, caps=True, jitter=0.05):
        p0 = Vector(p0)
        p1 = Vector(p1)
        d = p1 - p0
        length = d.length
        if length < 1e-6:
            return
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        m = Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4()
        r = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=sides,
                                  radius1=r0, radius2=r1, depth=length, matrix=m)
        self._paint(self._faces_of(r["verts"]), color, jitter)

    def cyl(self, base, r0, r1, h, sides, color, rot=(0, 0, 0), caps=True, jitter=0.05):
        p0 = Vector(base)
        p1 = p0 + Euler(rot, "XYZ").to_matrix() @ Vector((0, 0, h))
        self.frustum(p0, p1, r0, r1, sides, color, caps, jitter)

    def blob(self, c, radii, color, rot=(0, 0, 0), wobble=0.18, jitter=0.1, top_light=0.12):
        m = Matrix.Translation(Vector(c)) @ Euler(rot, "XYZ").to_matrix().to_4x4() @ Matrix.Diagonal((radii[0], radii[1], radii[2], 1.0))
        r = bmesh.ops.create_icosphere(self.bm, subdivisions=2, radius=1.0, matrix=m)
        for v in r["verts"]:
            v.co += Vector((self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(-1, 1))) * wobble * min(radii)
        faces = self._faces_of(r["verts"])
        self._paint(faces, color, jitter)
        base = lin(color)
        for f in faces:
            if f.calc_center_median().z > c[2] + radii[2] * 0.25:
                for loop in f.loops:
                    cur = loop[self.cl]
                    loop[self.cl] = (min(1.0, cur[0] * (1 + top_light)), min(1.0, cur[1] * (1 + top_light)), min(1.0, cur[2] * (1 + top_light)), 1.0)

    def extrude(self, loop_pts, offset, color, jitter=0.05):
        """Closed prism: a convex polygon (list of 3D points) swept by `offset`."""
        v0 = [self.bm.verts.new(Vector(p)) for p in loop_pts]
        v1 = [self.bm.verts.new(Vector(p) + Vector(offset)) for p in loop_pts]
        n = len(loop_pts)
        faces = []
        for i in range(n):
            j = (i + 1) % n
            faces.append(self.bm.faces.new((v0[i], v0[j], v1[j], v1[i])))
        faces.append(self.bm.faces.new(v0[::-1]))
        faces.append(self.bm.faces.new(v1))
        self._paint(faces, color, jitter)

    # -- open sheets (added AFTER seal(); drawn from both sides) -----------------
    def seal(self):
        """Fix the outward normals of everything built so far (closed solids). Call before sheets."""
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces[:])
        self.sealed = True

    def sheet(self, pts, color, jitter=0.05, both=True, shade_back=0.8):
        pts = [Vector(p) for p in pts]
        verts = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(verts)
        self._paint([f], color, jitter)
        if both:
            verts2 = [self.bm.verts.new(p) for p in pts[::-1]]
            f2 = self.bm.faces.new(verts2)
            self._paint([f2], shade(color, shade_back), jitter)

    # -- export ----------------------------------------------------------------
    def export(self, outdir):
        if not self.sealed:
            self.seal()
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces[:])
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        attr = me.color_attributes["Col"]
        me.color_attributes.active_color = attr
        me.color_attributes.render_color_index = 0
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.collection.objects.link(ob)
        me.materials.append(kit_material())
        tris = len(me.polygons)
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        path = f"{outdir}/{self.name}.glb"
        bpy.ops.export_scene.gltf(
            filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
            export_materials="EXPORT", export_image_format="NONE", export_cameras=False, export_lights=False,
            export_animations=False, export_extras=False,
            export_vertex_color="ACTIVE", export_all_vertex_colors=False)
        bpy.data.objects.remove(ob)
        bpy.data.meshes.remove(me)
        return {
            "name": self.name,
            "tris": tris,
            # Godot axes: x stays x, glTF y = Blender z (up), glTF z = -Blender y.
            "size": [round(max(xs) - min(xs), 3), round(max(zs) - min(zs), 3), round(max(ys) - min(ys), 3)],
            "min": [round(min(xs), 3), round(min(zs), 3), round(-max(ys), 3)],
            "max": [round(max(xs), 3), round(max(zs), 3), round(-min(ys), 3)],
        }
