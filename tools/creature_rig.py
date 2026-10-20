"""Rigging a creature sculpt (a one-piece mesh with legs) for the game: tools/art_pack.py rig-creature.

A creature made as one closed sculpt (the friends' cascarudo: a beetle's shell, a head, and six limbs, the front pair big
claws) is given a skeleton and skin weights without changing a single vertex of it:
  - its limbs are found from the ground up: each cluster of vertices on the ground is a foot (or a claw's tip); the
    geodesic distance over the surface from it runs up the limb, and the limb ends where the surface opens out into the
    body (the cross-section of the distance bands grows and keeps growing);
  - the middle line of each limb (the centres of those bands) gives its joints: the hip where it meets the body, and the
    knee and ankle where it bends most (or at set shares of its length where it hardly bends);
  - every vertex is weighted along that distance (foot, shin, thigh, then the body), blending over a band at each joint
    so nothing tears; the body's vertices are shared between the body, the shell (the dome, for its breathing) and the
    head (the front, for its twitches);
  - per vertex, baked into its colours: ambient occlusion (the share of the sky and the ground's light it sees, crevices
    and the underside darker), convexity (edges and ridges lighter, cavities darker) and how much of it is leg or
    underside (R, G, B; A spare);
  - a lighter copy (the far-off LOD) is decimated from the same sculpt and takes its weights and colours from the
    nearest vertices of the full one: one skeleton for both.
Bones (no rotation at rest, so a turn of a bone is a turn in the model's own axes): root (on the ground under the
middle), body, shell and head; per limb <L|R><n>_coxa (hip to knee), _tibia (knee to ankle), _tarsus (ankle to the foot)
and _tip (the foot on the ground: no vertex on it, the game's reach target), n counted from the front.
Needs numpy, scipy and trimesh (fast_simplification for the LOD)."""

import json
import math
import os
import struct

import numpy as np


def load_mesh(src):
    """The sculpt's vertices, normals and triangles exactly as they are in the file (no welding or re-ordering)."""
    import trimesh
    scene = trimesh.load(src, force="scene", process=False)
    meshes = []
    for node in scene.graph.nodes_geometry:
        xf, name = scene.graph[node]
        g = scene.geometry[name]
        v = np.asarray(g.vertices, float) @ xf[:3, :3].T + xf[:3, 3]
        n = np.asarray(g.vertex_normals, float) @ xf[:3, :3].T
        meshes.append((v, n, np.asarray(g.faces, np.int64), getattr(g.visual, "material", None)))
    if len(meshes) != 1:
        raise SystemExit(f"{src}: rig-creature takes a model of one mesh (this one has {len(meshes)})")
    v, n, f, material = meshes[0]
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
    return v, n, f, material


def graph(v, f):
    """The surface as a graph: its edges, weighted by length."""
    from scipy.sparse import coo_matrix
    e = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e = np.unique(np.sort(e, axis=1), axis=0)
    w = np.linalg.norm(v[e[:, 0]] - v[e[:, 1]], axis=1)
    n = len(v)
    return coo_matrix((np.r_[w, w], (np.r_[e[:, 0], e[:, 1]], np.r_[e[:, 1], e[:, 0]])), shape=(n, n)).tocsr(), e


def find_feet(v, comp_main, height, forward):
    """Clusters of vertices on the ground: the feet and claw tips. Named by side (L: the creature's left) and counted
    from the front."""
    from scipy.cluster.hierarchy import fcluster, linkage
    low = np.where((v[:, 1] < 0.04 * height) & comp_main)[0]
    size = np.ptp(v[:, [0, 2]], axis=0).max()
    labels = fcluster(linkage(v[low][:, [0, 2]], "single"), 0.04 * size, "distance")
    feet = []
    for k in np.unique(labels):
        idx = low[labels == k]
        if len(idx) >= 4:
            feet.append(idx)
    # the creature's own frame: its front `forward` (the model's axis), its left
    fwd = np.array(forward, float)
    left = np.cross([0.0, 1.0, 0.0], fwd)  # facing fwd with y up: left = up x forward
    out = {"L": [], "R": []}
    for idx in feet:
        c = v[idx].mean(0)
        out["L" if c @ left > 0 else "R"].append((float(c @ fwd), idx))
    named = {}
    for side in ("L", "R"):
        for i, (_, idx) in enumerate(sorted(out[side], key=lambda t: -t[0])):
            named[f"{side}{i + 1}"] = idx
    return named


def limb(v, dist, band, grow=1.5, rise=9):
    """A limb from its foot's geodesic distances: the centres and spread of the distance bands, and where it meets the
    body: the first band from which the spread stays above `grow` times the limb's own (the median so far) for `rise`
    bands and goes on growing (a knee or a foot only bulges and narrows again)."""
    centres, spreads, ds = [], [], []
    top = np.nanmax(dist[np.isfinite(dist)])
    d = band
    while d < top:
        idx = np.where((dist > d - band) & (dist <= d))[0]
        if len(idx) < 3:
            d += band
            continue
        c = v[idx].mean(0)
        centres.append(c)
        spreads.append(np.percentile(np.linalg.norm(v[idx] - c, axis=1), 90))
        ds.append(d)
        d += band
    centres, spreads, ds = np.array(centres), np.array(spreads), np.array(ds)
    hip = len(ds) - 1
    for i in range(6, len(ds) - rise):
        own = np.median(spreads[2:i])
        ahead = spreads[i: i + rise]
        if ahead.min() >= grow * own and spreads[i + rise - 1] >= 1.35 * spreads[i]:
            hip = i
            break
    return centres, spreads, ds, hip


def joints_along(centres, ds, hip):
    """The knee and ankle on a limb's middle line: the two points that split it into the three straight pieces that
    follow it best (least squares over every split; each piece at least three bands long)."""
    pts = centres[: hip + 1]
    sm = np.array([pts[max(0, i - 1): i + 2].mean(0) for i in range(len(pts))])
    n = len(sm)

    def cost(i, j):
        a, b = sm[i], sm[j]
        seg = sm[i: j + 1]
        ab = b - a
        t = np.clip(((seg - a) @ ab) / max(ab @ ab, 1e-12), 0.0, 1.0)
        return float((np.linalg.norm(seg - (a + t[:, None] * ab), axis=1) ** 2).sum())

    best, knee, ankle = None, n // 2, max(1, n // 5)
    for a in range(3, n - 6):
        ca = cost(0, a)
        for k in range(a + 3, n - 3):
            c = ca + cost(a, k) + cost(k, n - 1)
            if best is None or c < best:
                best, knee, ankle = c, k, a
    return sm, knee, ankle


def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def ambient_occlusion(v, n, f, height, directions=96, res=384):
    """Per vertex, the share of the light from the sky and the ground it sees: rendered as depth maps of the surface
    from many directions (a dense sampling of its triangles), a vertex lit from a direction if nothing is in front of it.
    The ground (y = 0) blocks every direction from below."""
    import trimesh
    mesh = trimesh.Trimesh(v, f, process=False)
    pts, fi = trimesh.sample.sample_surface_even(mesh, 300000, seed=1957)
    rng = np.random.default_rng(7)
    dirs = rng.normal(size=(directions * 3, 3))
    dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
    dirs = dirs[dirs[:, 1] > -0.15][:directions]
    lit = np.zeros(len(v))
    weight = np.zeros(len(v))
    span = np.ptp(v, axis=0).max() * 1.1
    centre = (v.max(0) + v.min(0)) / 2
    bias = span / res * 1.5
    for d in dirs:
        # a frame looking along -d
        up = np.array([0.0, 1.0, 0.0]) if abs(d[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
        ax = np.cross(up, d)
        ax /= np.linalg.norm(ax)
        ay = np.cross(d, ax)
        def proj(p):
            q = p - centre
            u = ((q @ ax) / span + 0.5) * res
            w = ((q @ ay) / span + 0.5) * res
            return np.clip(u.astype(int), 0, res - 1), np.clip(w.astype(int), 0, res - 1), q @ d
        pu, pw, pz = proj(pts)
        zbuf = np.full((res, res), -np.inf)
        np.maximum.at(zbuf, (pw, pu), pz)
        # a little dilation: the samples leave gaps
        z2 = zbuf.copy()
        for sx, sy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            z2 = np.maximum(z2, np.roll(np.roll(zbuf, sx, 1), sy, 0))
        vu, vw, vz = proj(v + n * bias * 0.5)
        seen = vz >= z2[vw, vu] - bias
        cosn = np.clip(n @ d, 0.0, 1.0)
        # below the horizon the ground is in the way
        ground = 1.0 if d[1] >= 0 else max(0.0, 1.0 + d[1] * 6.0)
        lit += cosn * seen * ground
        weight += cosn
    ao = lit / np.maximum(weight, 1e-6)
    return ao


def convexity(v, n, edges, scale_edges):
    """Per vertex, how far it stands out of its neighbourhood along its normal (positive on edges and ridges, negative
    in creases), over one and two rings, in units of the local edge length; -1..1."""
    from scipy.sparse import coo_matrix
    nv = len(v)
    a = coo_matrix((np.ones(len(edges) * 2), (np.r_[edges[:, 0], edges[:, 1]], np.r_[edges[:, 1], edges[:, 0]])), shape=(nv, nv)).tocsr()
    deg = np.asarray(a.sum(1)).ravel()
    mean1 = (a @ v) / np.maximum(deg, 1)[:, None]
    a2 = (a @ a).tocsr()
    a2.data[:] = 1.0
    deg2 = np.asarray(a2.sum(1)).ravel()
    mean2 = (a2 @ v) / np.maximum(deg2, 1)[:, None]
    lens = np.linalg.norm(v[edges[:, 0]] - v[edges[:, 1]], axis=1)
    local = np.bincount(edges[:, 0], lens, nv) + np.bincount(edges[:, 1], lens, nv)
    local = local / np.maximum(np.bincount(edges[:, 0], minlength=nv) + np.bincount(edges[:, 1], minlength=nv), 1)
    c1 = np.einsum("ij,ij->i", v - mean1, n) / np.maximum(local, 1e-6)
    c2 = np.einsum("ij,ij->i", v - mean2, n) / np.maximum(local * 2.0, 1e-6)
    c = 0.5 * c1 + 0.5 * c2
    # a pass of smoothing, then squashed to -1..1
    c = 0.5 * c + 0.5 * (a @ c) / np.maximum(deg, 1)
    return np.tanh(c * scale_edges)


def rig(src, forward=(0.0, 0.0, -1.0), band_share=0.015, blend_share=0.035):
    """Everything worked out for a sculpt: the mesh, the bones and the per-vertex weights and colours."""
    from scipy.sparse.csgraph import connected_components, dijkstra
    from scipy.spatial import cKDTree
    v, n, f, material = load_mesh(src)
    height = float(np.ptp(v[:, 1]))
    length = float(np.ptp(v, axis=0).max())
    adj, edges = graph(v, f)
    ncomp, comp = connected_components(adj, directed=False)
    main = np.bincount(comp).argmax()
    in_main = comp == main
    feet = find_feet(v, in_main, height, forward)
    band = band_share * length
    blend = blend_share * length
    limbs = {}
    for name, idx in sorted(feet.items()):
        dist = dijkstra(adj, directed=False, indices=idx, min_only=True)
        centres, spreads, ds, hip = limb(v, dist, band)
        mid, knee, ankle = joints_along(centres, ds, hip)
        limbs[name] = {"dist": dist, "foot": idx, "mid": mid, "ds": ds, "hip": hip, "knee": knee, "ankle": ankle,
                       "d_hip": ds[hip], "d_knee": ds[knee], "d_ankle": ds[ankle]}
    # --- bones (positions in the model's space; no rotation at rest)
    fwd = np.array(forward, float)
    bones = [("root", None, np.array([0.0, 0.0, 0.0]))]
    core = v[in_main]
    body_c = np.array([0.0, float(np.percentile(core[:, 1], 55)), float(np.median(core[:, 2]))])
    bones.append(("body", "root", body_c))
    shell_c = body_c + np.array([0.0, 0.22 * height, 0.0])
    bones.append(("shell", "body", shell_c))
    # the head: the front of the body (not of its claws), below the shell's lip
    on_limb = np.zeros(len(v), bool)
    for L in limbs.values():
        on_limb |= L["dist"] < L["d_hip"]
    body_pts = v[in_main & ~on_limb]
    front_t = body_pts @ fwd
    front_pts = body_pts[(front_t > np.percentile(front_t, 96))]
    head_c = front_pts.mean(0)
    head_c[0] = 0.0
    head_c = head_c - fwd * 0.08 * length
    bones.append(("head", "body", head_c))
    for name, L in sorted(limbs.items()):
        mid = L["mid"]
        tip = v[L["foot"]].mean(0)
        tip[1] = 0.0
        bones.append((f"{name}_coxa", "body", mid[L["hip"]]))
        bones.append((f"{name}_tibia", f"{name}_coxa", mid[L["knee"]]))
        bones.append((f"{name}_tarsus", f"{name}_tibia", mid[L["ankle"]]))
        bones.append((f"{name}_tip", f"{name}_tarsus", tip))
    index = {b[0]: i for i, b in enumerate(bones)}
    # --- weights
    nb = len(bones)
    W = np.zeros((len(v), nb))
    limb_any = np.zeros(len(v))
    for name, L in limbs.items():
        d = L["dist"]
        d = np.where(np.isfinite(d), d, 1e9)
        dh, dk, da = L["d_hip"], L["d_knee"], L["d_ankle"]
        share = 1.0 - smooth((d - (dh - 1.5 * blend)) / (2.5 * blend))
        to_tibia = 1.0 - smooth((d - (dk - blend)) / (2.0 * blend))
        to_tarsus = 1.0 - smooth((d - (da - blend)) / (2.0 * blend))
        tars = to_tarsus
        tib = to_tibia * (1.0 - to_tarsus)
        cox = 1.0 - to_tibia
        W[:, index[f"{name}_coxa"]] += share * cox
        W[:, index[f"{name}_tibia"]] += share * tib
        W[:, index[f"{name}_tarsus"]] += share * tars
        limb_any = np.maximum(limb_any, share)
    rest = 1.0 - np.clip(limb_any, 0.0, 1.0)
    # the body's share: the dome to the shell, the front to the head, the rest to the body
    rel = v - body_c
    shell_w = smooth((v[:, 1] - (body_c[1] + 0.02 * height)) / (0.16 * height))
    head_t = (v - head_c) @ fwd
    head_w = smooth((head_t + 0.06 * length) / (0.1 * length)) * (1.0 - smooth((v[:, 1] - (head_c[1] + 0.12 * height)) / (0.1 * height)))
    head_w *= 1.0 - shell_w
    W[:, index["head"]] += rest * head_w
    W[:, index["shell"]] += rest * (1.0 - head_w) * shell_w
    W[:, index["body"]] += rest * (1.0 - head_w) * (1.0 - shell_w)
    # the bits off the main piece: as their nearest vertex on it
    off = np.where(~in_main)[0]
    if len(off):
        tree = cKDTree(v[in_main])
        _, near = tree.query(v[off])
        W[off] = W[np.where(in_main)[0][near]]
    joints, weights = top4(W)
    # --- colours: occlusion, convexity, how much leg or underside
    ao = ambient_occlusion(v, n, f, height)
    cv = convexity(v, n, edges, 1.6)
    under = np.clip(np.maximum(limb_any, smooth((-n[:, 1] - 0.1) / 0.6) * (1.0 - shell_w)), 0.0, 1.0)
    colours = np.stack([ao, cv * 0.5 + 0.5, under, np.ones(len(v))], 1)
    report = {name: {"hip": bones[index[f"{name}_coxa"]][2].round(3).tolist(), "knee": bones[index[f"{name}_tibia"]][2].round(3).tolist(),
                     "ankle": bones[index[f"{name}_tarsus"]][2].round(3).tolist(), "tip": bones[index[f"{name}_tip"]][2].round(3).tolist(),
                     "length": round(float(L["d_hip"]), 3), "vertices": int((np.asarray([L["dist"] < L["d_hip"]]).sum()))}
              for name, L in limbs.items()}
    return {"v": v, "n": n, "f": f, "material": material, "bones": bones, "joints": joints, "weights": weights,
            "colours": colours, "W": W, "report": report, "main": in_main}


def top4(W):
    """The four strongest influences per vertex, renormalised."""
    order = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, order, 1)
    w = np.where(w > 1e-4, w, 0.0)
    s = w.sum(1, keepdims=True)
    w = np.where(s > 0, w / np.maximum(s, 1e-9), np.array([1.0, 0, 0, 0]))
    order = np.where(s > 0, order, 0)
    return order.astype(np.uint8), w.astype(np.float32)


def transfer(rigged, v_low, n_low):
    """Weights and colours for a lighter copy of the same sculpt: from the nearest vertices of the full one that face the
    same way."""
    from scipy.spatial import cKDTree
    tree = cKDTree(rigged["v"])
    dist, near = tree.query(v_low, k=6)
    agree = np.einsum("ikj,ij->ik", rigged["n"][near], n_low)
    w = np.where(agree > 0.3, 1.0 / np.maximum(dist, 1e-6), 1e-6 / np.maximum(dist, 1e-6))
    w /= w.sum(1, keepdims=True)
    W = np.einsum("ik,ikj->ij", w, rigged["W"][near])
    colours = np.einsum("ik,ikj->ij", w, rigged["colours"][near])
    joints, weights = top4(W)
    return joints, weights, colours


def write_glb(path, rigged, v, n, f, joints, weights, colours, generator):
    """A skinned GLB: the bones as nodes under the root, one mesh with its colours and weights, one material."""
    bones = rigged["bones"]
    chunks = bytearray()
    views, accessors = [], []

    def add(data, kind, comp, count, target=None, mn=None, mx=None, normalized=False):
        while len(chunks) % 4:
            chunks.append(0)
        view = {"buffer": 0, "byteOffset": len(chunks), "byteLength": len(data)}
        if target:
            view["target"] = target
        chunks.extend(data)
        views.append(view)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": count, "type": kind}
        if mn is not None:
            acc["min"], acc["max"] = mn, mx
        if normalized:
            acc["normalized"] = True
        accessors.append(acc)
        return len(accessors) - 1

    pos = np.ascontiguousarray(v, np.float32)
    a_pos = add(pos.tobytes(), "VEC3", 5126, len(pos), 34962, pos.min(0).tolist(), pos.max(0).tolist())
    a_nor = add(np.ascontiguousarray(n, np.float32).tobytes(), "VEC3", 5126, len(pos), 34962)
    col = np.clip(np.round(colours * 255.0), 0, 255).astype(np.uint8)
    a_col = add(np.ascontiguousarray(col).tobytes(), "VEC4", 5121, len(pos), 34962, normalized=True)
    # where each vertex stands at rest, for patterns that stay put on a moving leg (no UVs of its own): x, y in the first
    # set of texture coordinates, z and the normal's y in the second, each as value / 4 + 0.5 (in 0..1)
    uv0 = np.ascontiguousarray(np.stack([v[:, 0] * 0.25 + 0.5, v[:, 1] * 0.25 + 0.5], 1), np.float32)
    uv1 = np.ascontiguousarray(np.stack([v[:, 2] * 0.25 + 0.5, n[:, 1] * 0.5 + 0.5], 1), np.float32)
    a_uv0 = add(uv0.tobytes(), "VEC2", 5126, len(pos), 34962)
    a_uv1 = add(uv1.tobytes(), "VEC2", 5126, len(pos), 34962)
    a_jnt = add(np.ascontiguousarray(joints, np.uint8).tobytes(), "VEC4", 5121, len(pos), 34962)
    # weights as bytes (normalised), summing to exactly 255: the rounding put on the largest
    wq = np.round(np.asarray(weights, float) * 255.0).astype(np.int32)
    big = np.argmax(wq, axis=1)
    wq[np.arange(len(wq)), big] += 255 - wq.sum(1)
    a_wgt = add(np.ascontiguousarray(np.clip(wq, 0, 255), np.uint8).tobytes(), "VEC4", 5121, len(pos), 34962, normalized=True)
    idx = np.ascontiguousarray(f, np.uint32).ravel()
    a_idx = add(idx.tobytes(), "SCALAR", 5125, len(idx), 34963)
    # the bones: translation-only nodes, each relative to its parent
    names = [b[0] for b in bones]
    pos_of = {b[0]: np.asarray(b[2], float) for b in bones}
    nodes = []
    for name, parent, at in bones:
        local = at - (pos_of[parent] if parent else 0.0)
        nodes.append({"name": name, "translation": [float(x) for x in local]})
    for i, (name, parent, _) in enumerate(bones):
        if parent:
            nodes[names.index(parent)].setdefault("children", []).append(i)
    ibm = np.zeros((len(bones), 16), np.float32)
    for i, (_, _, at) in enumerate(bones):
        m = np.eye(4, dtype=np.float32)
        m[:3, 3] = -np.asarray(at, np.float32)
        ibm[i] = m.T.ravel()  # column-major
    a_ibm = add(ibm.tobytes(), "MAT4", 5126, len(bones))
    mat = rigged["material"]
    base = [0.333, 0.412, 0.235, 1.0]
    rough, metal = 0.43, 0.18
    if mat is not None:
        base = [float(x) for x in np.asarray(getattr(mat, "baseColorFactor", None) if getattr(mat, "baseColorFactor", None) is not None else base, float).ravel()[:4]]
        if max(base) > 1.0:
            base = [x / 255.0 for x in base]
        rough = float(getattr(mat, "roughnessFactor", rough) or rough)
        metal = float(getattr(mat, "metallicFactor", metal) or metal)
    mesh_node = len(nodes)
    nodes.append({"name": "Cascarudo", "mesh": 0, "skin": 0})
    doc = {"asset": {"version": "2.0", "generator": generator},
           "scene": 0, "scenes": [{"nodes": [0, mesh_node]}], "nodes": nodes,
           "meshes": [{"name": "geometry_0", "primitives": [{"attributes": {"POSITION": a_pos, "NORMAL": a_nor, "COLOR_0": a_col, "TEXCOORD_0": a_uv0, "TEXCOORD_1": a_uv1,
                                                                             "JOINTS_0": a_jnt, "WEIGHTS_0": a_wgt},
                                                              "indices": a_idx, "material": 0}]}],
           "materials": [{"name": "Chitin", "pbrMetallicRoughness": {"baseColorFactor": base, "roughnessFactor": rough, "metallicFactor": metal}}],
           "skins": [{"joints": list(range(len(bones))), "inverseBindMatrices": a_ibm, "skeleton": 0}],
           "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": 0}]}
    while len(chunks) % 4:
        chunks.append(0)
    doc["buffers"][0]["byteLength"] = len(chunks)
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(chunks), 0x004E4942) + bytes(chunks)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def lighter(v, n, f, faces):
    """The sculpt decimated to about `faces` triangles (fast_simplification, as the decimate command), its normals
    smoothed."""
    import fast_simplification
    import trimesh
    ratio = 1.0 - min(1.0, faces / len(f))
    vl, fl = fast_simplification.simplify(np.asarray(v, np.float32), np.asarray(f, np.int32), target_reduction=ratio)
    m = trimesh.Trimesh(vl, fl, process=False)
    m.fix_normals()
    return np.asarray(m.vertices, float), np.asarray(m.vertex_normals, float), np.asarray(m.faces, np.int64)


def labels_preview(rigged):
    """Colours by the strongest bone (to look at the segmentation)."""
    rng = np.random.default_rng(3)
    palette = rng.uniform(0.2, 1.0, size=(len(rigged["bones"]), 3))
    palette[1] = [0.55, 0.55, 0.55]
    palette[2] = [0.85, 0.85, 0.7]
    palette[3] = [0.9, 0.4, 0.4]
    W = rigged["W"]
    c = W @ palette
    return np.concatenate([c, np.ones((len(c), 1))], 1)
