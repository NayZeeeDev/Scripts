"""
Decimate a mesh with Blender, keeping UVs and sharp edges.

    python decimate_blender.py in.npz out.npz <target_tris>

in.npz:  pos (N,3) float, uv (N,2) float, idx (M,) int
out.npz: pos, nrm, uv (K,...) and idx - one vertex per unique corner, ready
         for propkit.Mesh. Run with Blender's Python (the `bpy` module).
"""

import math
import sys

import bpy
import numpy as np


def main():
    src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
    d = np.load(src)
    pos, uv, idx = d["pos"], d["uv"], d["idx"].reshape(-1, 3)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    me = bpy.data.meshes.new("shoe")
    me.from_pydata(pos.tolist(), [], idx.tolist())
    uvl = me.uv_layers.new(name="uv")
    corner_vert = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", corner_vert)
    uvl.data.foreach_set("uv", uv[corner_vert].astype(np.float32).ravel())
    me.validate()
    ob = bpy.data.objects.new("shoe", me)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)

    # weld the per-UV-island duplicates so the decimator sees one surface;
    # UVs live on face corners, so the seams survive
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.00005)
    bpy.ops.object.mode_set(mode="OBJECT")

    # lock vertices on UV seams (and open edges): collapsing across a seam
    # drags texture from one island into another
    lv0 = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv0)
    luv = np.empty(len(me.loops) * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", luv)
    luv = np.round(luv.reshape(-1, 2), 5)
    first_uv = {}
    locked = set()
    for v, uvk in zip(lv0.tolist(), map(tuple, luv.tolist())):
        if v in first_uv and first_uv[v] != uvk:
            locked.add(v)
        first_uv.setdefault(v, uvk)
    edge_faces = {}
    for poly in me.polygons:
        for ek in poly.edge_keys:
            edge_faces[ek] = edge_faces.get(ek, 0) + 1
    for (a, b), n in edge_faces.items():
        if n == 1:
            locked.update((a, b))
    vg = ob.vertex_groups.new(name="free")
    vg.add([v for v in range(len(me.vertices)) if v not in locked], 1.0, "REPLACE")
    print(f"locked {len(locked)} of {len(me.vertices)} vertices on seams/edges")

    before = len(me.polygons)
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.vertex_group = "free"
    mod.decimate_type = "COLLAPSE"
    mod.ratio = min(1.0, target / max(1, before))
    mod.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    for m in list(ob.modifiers):          # bake the smooth-by-angle result
        bpy.ops.object.modifier_apply(modifier=m.name)
    me = ob.data
    me.calc_loop_triangles()
    print(f"decimated {before} -> {len(me.loop_triangles)} triangles")

    # one output vertex per unique (position, corner normal, uv)
    cn = np.array([c.vector[:] for c in me.corner_normals], dtype=np.float32)
    cuv = np.empty(len(me.loops) * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", cuv)
    cuv = cuv.reshape(-1, 2)
    vco = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", vco)
    vco = vco.reshape(-1, 3)
    lv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)

    tris = np.array([t.loops[:] for t in me.loop_triangles], dtype=np.int64)
    keys = np.concatenate([lv[:, None].astype(np.float64), np.round(cn, 4), np.round(cuv, 5)], axis=1)
    uniq, inverse = np.unique(keys, axis=0, return_inverse=True)
    first = np.zeros(len(uniq), dtype=np.int64)
    first[inverse[::-1]] = np.arange(len(inverse))[::-1]
    out_pos, out_nrm, out_uv = vco[lv[first]], cn[first], cuv[first]
    out_idx = inverse.ravel()[tris].ravel()
    np.savez(dst, pos=out_pos, nrm=out_nrm, uv=out_uv, idx=out_idx)
    print(f"wrote {len(out_pos)} vertices, {len(out_idx) // 3} triangles")


main()
