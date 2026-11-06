"""Convert Poly Haven (CC0) glTF downloads into compact project GLBs.

Usage: blender -b -P tools/blender/import_polyhaven.py -- <src_root> <out_dir> <max_tex> id [id ...]
Each <src_root>/<id>/<id>.gltf is imported, textures are downscaled to <max_tex> px, the mesh is
re-based so the origin sits at the bottom centre (Godot placement convention), and a GLB is exported.
"""
import bpy, sys, os, mathutils

argv = sys.argv[sys.argv.index("--") + 1:]
src_root, out_dir, max_tex = argv[0], argv[1], int(argv[2])
for asset in argv[3:]:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src_root, asset, asset + ".gltf"))
    for img in bpy.data.images:
        if img.size[0] > max_tex or img.size[1] > max_tex:
            img.scale(min(img.size[0], max_tex), min(img.size[1], max_tex))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = mathutils.Vector((1e9, 1e9, 1e9)); hi = mathutils.Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            lo = mathutils.Vector(map(min, lo, w)); hi = mathutils.Vector(map(max, hi, w))
    shift = mathutils.Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))  # Blender Z is up
    for o in bpy.context.scene.objects:
        if o.parent is None:
            o.location -= shift
    tris = sum(len(o.data.polygons) for o in meshes)  # approximate (quads count 1)
    out = os.path.join(out_dir, asset.lower() + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_image_format="JPEG", export_jpeg_quality=85)
    print("PH_OK", asset, "size_m", [round(v, 2) for v in (hi - lo)], "polys", tris, "bytes", os.path.getsize(out))
