"""Shared Blender helpers for the procedural, original low-poly props (weapons, armor, environment kit).

Run inside Blender:  blender --background --python <script.py>
Import from a script next to this file:

    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import props_lib as P

STABLE API (other tools import it, do not rename):
    new_scene()                                   empty metric scene
    box(name, size, loc=(0,0,0), rot=(0,0,0), color=None)
    cylinder(name, radius, depth, loc=(0,0,0), rot=(0,0,0), verts=8, radius2=None, color=None)
    mesh_from(name, verts, faces, loc=(0,0,0), rot=(0,0,0), color=None)
    loft(name, rings, tip=None, cap_start=True, loc=(0,0,0), rot=(0,0,0), color=None)
    bevel(obj, width)                              one-segment bevel of every edge
    paint(obj, rgba, srgb=True)                    vertex colour "Col" (linear floats stored)
    join(objs, name=None)                          merge objects into one
    finalize(obj)                                  flat shading + the shared material
    tri_count(obj)                                 triangle count after triangulation
    export_glb(path, objs=None)                    GLB, Y-up, vertex colours, one material

CONVENTIONS
    Blender is Z-up. glTF/Godot is Y-up with -Z forward. The exporter maps  Blender +Y -> Godot -Z
    (forward), Blender +Z -> Godot +Y (up), Blender +X -> Godot +X.  So a prop that should point
    "forward" in Godot is built pointing along Blender +Y.
    Every builder bakes loc/rot into the vertices, so objects keep an identity transform and the
    origin stays at the world origin (the grip centre for weapons).
    Colours are given as sRGB (0..1) and stored linear, because glTF vertex colours are linear.
"""
import math

import bmesh
import bpy
from mathutils import Euler, Vector

_MATERIAL_NAME = "props_vcol"


def new_scene():
    """Empty scene in metres with no leftover data."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    return scene


def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _material():
    mat = bpy.data.materials.get(_MATERIAL_NAME)
    if mat is None:
        mat = bpy.data.materials.new(_MATERIAL_NAME)
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (1.0, 1.0, 1.0, 1.0)
        bsdf.inputs["Metallic"].default_value = 0.0
        bsdf.inputs["Roughness"].default_value = 0.6
    return mat


def _make_object(name, bm, loc, rot, color):
    """Bake rotation + location into the vertices and create a linked object."""
    if rot != (0, 0, 0):
        bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Euler(rot).to_matrix(), verts=bm.verts)
    if loc != (0, 0, 0):
        bmesh.ops.translate(bm, vec=Vector(loc), verts=bm.verts)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    if color is not None:
        paint(obj, color)
    return obj


def box(name, size, loc=(0, 0, 0), rot=(0, 0, 0), color=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    return _make_object(name, bm, tuple(loc), tuple(rot), color)


def cylinder(name, radius, depth, loc=(0, 0, 0), rot=(0, 0, 0), verts=8, radius2=None, color=None):
    """Cylinder (or cone/frustum when radius2 is given) along Z, centred on its location."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=verts,
                          radius1=radius, radius2=radius if radius2 is None else radius2, depth=depth)
    return _make_object(name, bm, tuple(loc), tuple(rot), color)


def mesh_from(name, verts, faces, loc=(0, 0, 0), rot=(0, 0, 0), color=None):
    bm = bmesh.new()
    made = [bm.verts.new(Vector(v)) for v in verts]
    bm.verts.ensure_lookup_table()
    for f in faces:
        bm.faces.new([made[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _make_object(name, bm, tuple(loc), tuple(rot), color)


def loft(name, rings, tip=None, cap_start=True, loc=(0, 0, 0), rot=(0, 0, 0), color=None, cap_end=False):
    """Skin a list of rings (each a list of (x, y, z), same vertex count, in the same winding).

    tip: optional single point; the last ring is joined to it with a triangle fan.
    cap_start: close the first ring with one polygon.
    cap_end: close the last ring with one polygon (ignored when a tip is given).
    """
    count = len(rings[0])
    verts = [tuple(p) for ring in rings for p in ring]
    faces = []
    for r in range(len(rings) - 1):
        a = r * count
        b = (r + 1) * count
        for j in range(count):
            k = (j + 1) % count
            faces.append((a + j, a + k, b + k, b + j))
    if tip is not None:
        tip_i = len(verts)
        verts.append(tuple(tip))
        last = (len(rings) - 1) * count
        for j in range(count):
            faces.append((last + j, last + (j + 1) % count, tip_i))
    if cap_start:
        faces.append(tuple(reversed(range(count))))
    if cap_end and tip is None:
        last = (len(rings) - 1) * count
        faces.append(tuple(range(last, last + count)))
    return mesh_from(name, verts, faces, loc, rot, color)


def sphere(name, radius, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), segments=8, rings=5, color=None):
    """UV sphere (scaled into an ellipsoid when scale is not 1)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    for v in bm.verts:
        v.co.x *= scale[0]
        v.co.y *= scale[1]
        v.co.z *= scale[2]
    return _make_object(name, bm, tuple(loc), tuple(rot), color)


def bevel(obj, width):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=width, segments=1, affect="EDGES")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return obj


def paint(obj, rgba, srgb=True):
    """Fill the 'Col' vertex colour attribute with one colour. rgba is (r, g, b) or (r, g, b, a)."""
    if len(rgba) == 3:
        rgba = (rgba[0], rgba[1], rgba[2], 1.0)
    colour = tuple(_srgb_to_linear(c) for c in rgba[:3]) + (rgba[3],) if srgb else tuple(rgba)
    mesh = obj.data
    attr = mesh.color_attributes.get("Col")
    if attr is None:
        attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
    for item in attr.data:
        item.color = colour
    mesh.color_attributes.active_color = attr
    return obj


def join(objs, name=None):
    objs = list(objs)
    if len(objs) == 1:
        if name:
            objs[0].name = name
        return objs[0]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    result = bpy.context.view_layer.objects.active
    if name:
        result.name = name
        result.data.name = name
    return result


def finalize(obj):
    """Flat shading (crisp low-poly look) and the single shared material."""
    for poly in obj.data.polygons:
        poly.use_smooth = False
    obj.data.materials.clear()
    obj.data.materials.append(_material())
    if obj.data.color_attributes.get("Col") is not None:
        obj.data.color_attributes.active_color = obj.data.color_attributes.get("Col")
    return obj


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def export_glb(path, objs=None):
    """Export objects (default: everything) as one GLB."""
    import os

    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in (objs if objs is not None else bpy.context.scene.objects):
        if o.type == "MESH":
            o.select_set(True)
    kwargs = dict(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_texcoords=False,
        export_normals=True,
        export_extras=False,
    )
    try:
        bpy.ops.export_scene.gltf(export_vertex_color="ACTIVE", **kwargs)
    except TypeError:  # older exporter without the option
        bpy.ops.export_scene.gltf(**kwargs)
    return path
