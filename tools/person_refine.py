"""Refining the friends' low-poly person for the game: tools/art_pack.py refine-person.

Juan Salvo's model (the friends' snowfall_survivor.glb: eleven skinned parts on a 21-bone skeleton, 2,056 triangles of
boxes and prisms, one 512 px atlas of sixteen swatches, five clips) is brought up to the cast's fidelity without
changing what it is: the same parts, silhouette, colours, skeleton and clips.
  - its parts are welded and read back as the polygons they were modelled as (the coplanar triangles that share a swatch
    chart: a box's sides, a prism's caps), then Catmull-Clark subdivided: limbs, hood and coat rounded, hard edges kept
    where they belong (the coat's hem, the boot soles, the visor's rim and the face plate sharp; the backpack, harness,
    respirator, boots and rifle only bevelled; buttons, screws and laces left as they are); each rounded piece is then
    eased back out to the extents it had, so nothing comes loose at a joint or shrinks out of its harness;
  - each polygon's swatch chart is carried down exactly (its texture coordinates interpolated across it), and the skin
    weights with it, so the clips move it as before;
  - its normals are smooth across what was rounded and split where an edge stays hard;
  - per vertex, baked into its colours as the finish reads them (shaders/art_model.gdshader, the cloth branch): the
    occlusion of the whole figure (R), where mud and wet reach from the ground and gather in creases (G), the wear on
    its edges (B), and the folds where cloth bunches at the elbows, knees, waist and shoulders (A, under one half: the
    mark of a baked figure);
  - the atlas is redrawn at four times the size from the friends' own: each swatch its own colours, smoothed of its
    pixel noise, with the grain of what it is (twill, canvas, padded cloth, leather, rubber, wood, steel) and its seams
    and stitching where the friends drew them, and the face upscaled as drawn; its alpha names the material of each
    swatch for the finish;
  - a lighter copy (the far-off LOD): one level of subdivision instead of two on what is rounded, merged into one mesh
    on the same skin, carrying where each vertex stands at rest (CUSTOM0 through TEXCOORD_2 / TEXCOORD_3) as the game's
    merged figure does.
The skeleton, the skin's bind matrices, the clips and the scene's nodes are copied from the source as they are.
Needs numpy, scipy, trimesh (for the occlusion: creature_rig.ambient_occlusion) and Pillow."""

import io
import json
import struct
from collections import defaultdict

import numpy as np

# ------------------------------------------------------------------------------------------------ the source
CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8, 5122: np.int16, 5120: np.int8}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:4] != b"glTF":
        raise ValueError(f"{path} is not a GLB")
    jlen = struct.unpack("<I", data[12:16])[0]
    gltf = json.loads(data[20:20 + jlen].decode("utf-8"))
    rest = data[20 + jlen:]
    blen = struct.unpack("<I", rest[:4])[0]
    return gltf, rest[8:8 + blen]


def accessor(gltf, binary, i):
    a = gltf["accessors"][i]
    view = gltf["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    w = WIDTH[a["type"]]
    off = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", 0)
    if stride and stride != dt.itemsize * w:
        raw = np.frombuffer(binary, np.uint8, stride * (a["count"] - 1) + dt.itemsize * w, off)
        arr = np.stack([np.frombuffer(raw[k * stride:k * stride + dt.itemsize * w].tobytes(), dt) for k in range(a["count"])])
    else:
        arr = np.frombuffer(binary, dt, a["count"] * w, off).reshape(a["count"], w) if w > 1 else np.frombuffer(binary, dt, a["count"], off)
    if a.get("normalized"):
        arr = arr.astype(np.float32) / float(np.iinfo(dt).max)
    return np.array(arr)


def parts(gltf, binary):
    """Every mesh of the figure as {name, P, UV, joints, weights, tris} (its first primitive; the skinned parts are in
    the skin's bind space)."""
    out = []
    for m in gltf["meshes"]:
        p = m["primitives"][0]
        at = p["attributes"]
        out.append({"name": m["name"], "P": accessor(gltf, binary, at["POSITION"]).astype(np.float64),
                    "UV": accessor(gltf, binary, at["TEXCOORD_0"]).astype(np.float64),
                    "J": accessor(gltf, binary, at["JOINTS_0"]).astype(np.int64),
                    "W": accessor(gltf, binary, at["WEIGHTS_0"]).astype(np.float64),
                    "tris": accessor(gltf, binary, p["indices"]).astype(np.int64).reshape(-1, 3)})
    return out


# ------------------------------------------------------------------------------------------------ polygons
def weld(P, eps=1e-5):
    key = np.round(P / eps).astype(np.int64)
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    return first, inv.ravel()


def polygons(V, tris, uv_corner):
    """The polygons the triangles were made from: edge-connected coplanar triangles whose texture chart runs on across
    the shared edge (the same coordinates on both sides), read back as one polygon by its outline. Returns [(vertex loop,
    uv loop)]. Triangles that do not close into one simple outline stay triangles."""
    nt = len(tris)
    fn = np.cross(V[tris[:, 1]] - V[tris[:, 0]], V[tris[:, 2]] - V[tris[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    corner_uv = {}
    for t in range(nt):
        for k in range(3):
            corner_uv[(t, int(tris[t, k]))] = uv_corner[t, k]
    by_edge = defaultdict(list)
    for t in range(nt):
        for k in range(3):
            a, b = int(tris[t, k]), int(tris[t, (k + 1) % 3])
            by_edge[(min(a, b), max(a, b))].append(t)
    parent = list(range(nt))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for (a, b), ts in by_edge.items():
        if len(ts) != 2:
            continue
        t0, t1 = ts
        if float(fn[t0] @ fn[t1]) < 0.9995:
            continue
        if np.abs(corner_uv[(t0, a)] - corner_uv[(t1, a)]).max() > 1e-4 or np.abs(corner_uv[(t0, b)] - corner_uv[(t1, b)]).max() > 1e-4:
            continue
        parent[find(t0)] = find(t1)
    groups = defaultdict(list)
    for t in range(nt):
        groups[find(t)].append(t)
    out = []
    for ts in groups.values():
        loop = _outline(tris, ts)
        if loop is None:
            for t in ts:
                out.append((list(map(int, tris[t])), [corner_uv[(t, int(v))] for v in tris[t]]))
            continue
        uvs = []
        for v in loop:
            for t in ts:
                if (t, v) in corner_uv:
                    uvs.append(corner_uv[(t, v)])
                    break
        # collinear corners (a vertex on a straight side) are kept: they are shared with the next polygon
        out.append((loop, uvs))
    return out


def _outline(tris, ts):
    if len(ts) == 1:
        return list(map(int, tris[ts[0]]))
    count = defaultdict(int)
    directed = {}
    for t in ts:
        for k in range(3):
            a, b = int(tris[t, k]), int(tris[t, (k + 1) % 3])
            count[(min(a, b), max(a, b))] += 1
            directed[(a, b)] = True
    nxt = {}
    for (a, b) in directed:
        if count[(min(a, b), max(a, b))] == 1:
            if a in nxt:
                return None
            nxt[a] = b
    if not nxt:
        return None
    start = next(iter(nxt))
    loop = [start]
    while True:
        b = nxt.get(loop[-1])
        if b is None:
            return None
        if b == start:
            break
        if b in loop or len(loop) > len(nxt):
            return None
        loop.append(b)
    return loop if len(loop) == len(nxt) else None


# ------------------------------------------------------------------------------------------------ Catmull-Clark
INF = float("inf")


def edge_key(a, b):
    return (a, b) if a < b else (b, a)


def subdivide(V, W, faces, fuv, sharp, levels):
    """Catmull-Clark subdivision `levels` times. V (n, 3) positions, W (n, k) per-vertex data interpolated linearly
    (skin weights, rest data), faces [vertex loops], fuv [per-corner uv loops], sharp {edge: sharpness} (edges used by
    one face or by more than two are always sharp; a sharpness s keeps an edge sharp for s levels, a fraction blends).
    Returns V, W, faces (quads), fuv, sharp (what is left of it)."""
    for _ in range(levels):
        V, W, faces, fuv, sharp = _cc_step(V, W, faces, fuv, sharp)
    return V, W, faces, fuv, sharp


def _cc_step(V, W, faces, fuv, sharp):
    nv = len(V)
    edge_faces = defaultdict(list)
    for fi, f in enumerate(faces):
        k = len(f)
        for j in range(k):
            edge_faces[edge_key(f[j], f[(j + 1) % k])].append(fi)
    edges = list(edge_faces.keys())
    eidx = {e: i for i, e in enumerate(edges)}
    ne = len(edges)
    FP = np.array([V[f].mean(0) for f in faces])
    FW = np.array([W[f].mean(0) for f in faces])
    EP = np.zeros((ne, 3))
    EW = np.zeros((ne, W.shape[1]))
    es = np.zeros(ne)
    for i, (a, b) in enumerate(edges):
        fs = edge_faces[(a, b)]
        mid = (V[a] + V[b]) * 0.5
        s = INF if len(fs) != 2 else sharp.get((a, b), 0.0)
        es[i] = s
        if s >= 1.0:
            EP[i] = mid
        else:
            smooth = (V[a] + V[b] + FP[fs[0]] + FP[fs[1]]) * 0.25
            EP[i] = smooth + (mid - smooth) * s
        EW[i] = (W[a] + W[b]) * 0.5
    v_edges = defaultdict(list)
    v_faces = defaultdict(list)
    for i, (a, b) in enumerate(edges):
        v_edges[a].append(i)
        v_edges[b].append(i)
    for fi, f in enumerate(faces):
        for v in f:
            v_faces[v].append(fi)
    VP = V.copy()
    for v in range(nv):
        ie = v_edges.get(v)
        if not ie:
            continue
        creases = [i for i in ie if es[i] > 0.0]
        n = len(ie)
        Q = FP[v_faces[v]].mean(0)
        R = np.mean([(V[edges[i][0]] + V[edges[i][1]]) * 0.5 for i in ie], axis=0)
        smooth = (Q + 2.0 * R + (n - 3.0) * V[v]) / n
        if len(creases) < 2:
            VP[v] = smooth
            continue
        if len(creases) == 2:
            o = [edges[i][0] if edges[i][1] == v else edges[i][1] for i in creases]
            hard = (V[o[0]] + 6.0 * V[v] + V[o[1]]) / 8.0
        else:
            hard = V[v]
        s = min(1.0, float(np.mean([min(es[i], 1.0) for i in creases])))
        VP[v] = smooth + (hard - smooth) * s
    NV = np.concatenate([VP, EP, FP])
    NW = np.concatenate([W, EW, FW])
    nfaces, nfuv = [], []
    nsharp = {}
    for fi, f in enumerate(faces):
        k = len(f)
        uv = np.asarray(fuv[fi])
        uc = uv.mean(0)
        fpi = nv + ne + fi
        for j in range(k):
            a, b, z = f[j], f[(j + 1) % k], f[(j - 1) % k]
            e_next = nv + eidx[edge_key(a, b)]
            e_prev = nv + eidx[edge_key(z, a)]
            nfaces.append([a, e_next, fpi, e_prev])
            nfuv.append([uv[j], (uv[j] + uv[(j + 1) % k]) * 0.5, uc, (uv[j] + uv[(j - 1) % k]) * 0.5])
    for i, (a, b) in enumerate(edges):
        s = es[i]
        if s > 0.0 and len(edge_faces[(a, b)]) == 2:
            left = max(0.0, s - 1.0)
            if left > 0.0:
                nsharp[edge_key(a, nv + i)] = left
                nsharp[edge_key(b, nv + i)] = left
    return NV, NW, nfaces, nfuv, nsharp


# ------------------------------------------------------------------------------------------------ one part
# How each part is refined. Each piece of it (a connected component) is one of:
#   keep:  anything under `keep` metres across (buttons, screws, laces, slots, fingers): left exactly as it is;
#   flat:  pieces under `flat` metres thick (the face plate, the visor and its seals): left as they are, edges hard;
#   round: the part's big pieces when `round` (the limbs, the hood, the coat's body): Catmull-Clark `levels` times (full
#          model, lighter copy), every edge smooth but the hem (`hem`: the outline of what faces down stays sharp) and a
#          prism's ends (`caps`: eased by that sharpness), then drawn back out to the length it had along its own axis;
#   bevel: the rest (lapels, flaps, the backpack, straps, the boots, the respirator, the rifle): subdivided once with
#          every edge eased by `bevel` (a sharpness under 1: a chamfer, not a rounding), the soles' outline sharp;
#          kept as it is in the lighter copy.
RULES = {
    "Hood": {"levels": (2, 1), "round": True},
    "Coat": {"levels": (2, 1), "round": True, "hem": True, "small": 0.25, "bevel": 0.55},
    "Sleeves": {"levels": (2, 1), "round": True, "caps": 1.0},
    "Trousers": {"levels": (2, 1), "round": True, "caps": 1.0},
    "Gloves": {"levels": (1, 1), "round": True, "keep": 0.045},
    "Boots": {"bevel": 0.55, "hem": True, "keep": 0.03},
    "FaceAndVisor": {"flat": 0.03, "keep": 0.025},
    "Respirator": {"bevel": 0.6, "keep": 0.035},
    "Backpack": {"bevel": 0.45, "hem": True},
    "Harness": {"bevel": 0.5, "keep": 0.03},
    "CarriedProp": {"bevel": 0.6, "keep": 0.03},
}


def refine_part(part, lod=False):
    """One part refined by its rule: positions, skin weights (dense, one column per joint), faces (quads and the kept
    polygons), per-corner uvs, hard edges, and which piece each vertex came from."""
    rule = RULES.get(part["name"], {"bevel": 0.5})
    P, UV, J, Wt, tris = part["P"], part["UV"], part["J"], part["W"], part["tris"]
    first, inv = weld(P)
    V = P[first]
    nj = 21
    dense = np.zeros((len(P), nj))
    for k in range(4):
        np.add.at(dense, (np.arange(len(P)), J[:, k]), Wt[:, k])
    Wv = np.zeros((len(V), nj))
    np.add.at(Wv, inv, dense)
    Wv /= np.maximum(Wv.sum(1, keepdims=True), 1e-9)
    polys = polygons(V, inv[tris], UV[tris])
    faces = [p[0] for p in polys]
    fuv = [np.asarray(p[1]) for p in polys]
    comp = _components(len(V), faces)
    fcomp = [comp[f[0]] for f in faces]
    ncomp = int(comp.max()) + 1
    dims = np.array([V[comp == c].max(0) - V[comp == c].min(0) for c in range(ncomp)])
    mode = []
    for c in range(ncomp):
        d = dims[c]
        if d.max() < rule.get("keep", 0.0):
            mode.append("keep")
        elif d.min() < rule.get("flat", 0.0):
            mode.append("flat")
        elif rule.get("round") and d.max() >= rule.get("small", 0.0):
            mode.append("round")
        else:
            mode.append("bevel")
    levels = {"keep": 0, "flat": 0, "bevel": 0 if lod else 1, "round": rule.get("levels", (1, 1))[1 if lod else 0]}
    fn = [_poly_normal(V, f) for f in faces]
    edge_faces = defaultdict(list)
    for fi, f in enumerate(faces):
        for j in range(len(f)):
            edge_faces[edge_key(f[j], f[(j + 1) % len(f)])].append(fi)
    sharp = {}
    for e, fs in edge_faces.items():
        if len(fs) != 2:
            continue
        m = mode[fcomp[fs[0]]]
        n0, n1 = fn[fs[0]], fn[fs[1]]
        cosang = float(n0 @ n1)
        down = rule.get("hem") and min(n0[1], n1[1]) < -0.75 and max(n0[1], n1[1]) > -0.3
        if m in ("keep", "flat") or down:
            s = INF
        elif m == "bevel":
            s = rule.get("bevel", 0.5) if cosang < 0.95 else 0.0
        else:
            s = 0.0
            if rule.get("caps") and cosang < 0.2 and (len(faces[fs[0]]) > 4 or len(faces[fs[1]]) > 4):
                s = rule["caps"]
        if s > 0.0:
            sharp[e] = s
    extra = np.concatenate([Wv, comp[:, None].astype(float)], 1)
    outV, outX, outF, outUV, hard = [], [], [], [], set()
    base = 0
    for m in ("round", "bevel", "flat", "keep"):
        group = [i for i in range(len(faces)) if mode[fcomp[i]] == m]
        if not group:
            continue
        used = sorted({v for i in group for v in faces[i]})
        remap = {v: k for k, v in enumerate(used)}
        gs = {edge_key(remap[a], remap[b]): s for (a, b), s in sharp.items() if a in remap and b in remap}
        gV, gX, gF, gUV, gsharp = subdivide(V[used], extra[used], [[remap[v] for v in faces[i]] for i in group],
                                           [fuv[i] for i in group], gs, levels[m])
        if m == "round":
            gc = np.round(gX[:, -1]).astype(int)
            for c in set(gc.tolist()):
                sel = gc == c
                gV[sel] = _restore_length(V[comp == c], gV[sel])
        outV.append(gV)
        outX.append(gX)
        outF += [[base + v for v in f] for f in gF]
        outUV += gUV
        hard |= {edge_key(base + a, base + b) for (a, b), s in gsharp.items() if s >= 1.0}
        if levels[m] == 0:
            # an unsubdivided piece: its edges are as hard as they were drawn
            for f in gF:
                for j in range(len(f)):
                    hard.add(edge_key(base + f[j], base + f[(j + 1) % len(f)]))
        base += len(gV)
    NV = np.concatenate(outV)
    NX = np.concatenate(outX)
    return {"name": part["name"], "V": NV, "W": NX[:, :nj], "comp": np.round(NX[:, -1]).astype(int), "faces": outF, "fuv": outUV,
            "hard": hard, "modes": mode, "dims": dims}


def _components(n, faces):
    parent = list(range(n))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for f in faces:
        for v in f[1:]:
            parent[find(v)] = find(f[0])
    roots = {}
    comp = np.zeros(n, int)
    for v in range(n):
        r = find(v)
        comp[v] = roots.setdefault(r, len(roots))
    return comp


def _poly_normal(V, f):
    p = V[f]
    n = np.zeros(3)
    for j in range(len(f)):
        a, b = p[j], p[(j + 1) % len(f)]
        n += np.cross(a, b)
    ln = np.linalg.norm(n)
    return n / ln if ln > 1e-12 else np.array([0.0, 1.0, 0.0])


def _restore_length(before, after):
    """A rounded piece drawn back out along its own long axis to the length it had (its ends shrink most as they round:
    a sleeve would come away from the glove); its girth left as the rounding made it."""
    c0 = before.mean(0)
    _, sv, vt = np.linalg.svd(before - c0, full_matrices=False)
    axis = vt[0]
    if sv[0] < 1.25 * sv[1]:
        return after
    tb = (before - c0) @ axis
    ta = (after - c0) @ axis
    span_b = tb.max() - tb.min()
    span_a = max(ta.max() - ta.min(), 1e-9)
    k = min(span_b / span_a, 1.25)
    mid_a = (ta.max() + ta.min()) * 0.5
    mid_b = (tb.max() + tb.min()) * 0.5
    t_new = (ta - mid_a) * k + mid_b
    return after + np.outer(t_new - ta, axis)


# ------------------------------------------------------------------------------------------------ normals and output
def triangulate(part):
    """The refined part as output vertices (split where texture charts meet and where an edge stays hard) and
    triangles: P, N, UV, W (dense), comp, tris."""
    V, faces, fuv = part["V"], part["faces"], part["fuv"]
    hard = part["hard"]
    fn = []
    for f in faces:
        p = V[f]
        n = np.zeros(3)
        for j in range(len(f)):
            n += np.cross(p[j], p[(j + 1) % len(f)])
        fn.append(n * 0.5)
    fn = np.array(fn)
    unit = fn / np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    # corners joined round each vertex across soft edges: a normal per group
    corner_id = {}
    parent = []
    for fi, f in enumerate(faces):
        for v in f:
            corner_id[(fi, v)] = len(parent)
            parent.append(len(parent))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    edge_faces = defaultdict(list)
    for fi, f in enumerate(faces):
        for j in range(len(f)):
            edge_faces[edge_key(f[j], f[(j + 1) % len(f)])].append(fi)
    for e, fs in edge_faces.items():
        if len(fs) != 2:
            continue
        a, b = fs
        if e in hard and float(unit[a] @ unit[b]) < 0.94:
            continue
        if float(unit[a] @ unit[b]) < 0.2:
            continue
        for v in e:
            ra, rb = find(corner_id[(a, v)]), find(corner_id[(b, v)])
            if ra != rb:
                parent[ra] = rb
    gsum = defaultdict(lambda: np.zeros(3))
    for (fi, v), cid in corner_id.items():
        gsum[find(cid)] += fn[fi]
    out_index = {}
    P, N, UV, W, C, tris = [], [], [], [], [], []
    for fi, f in enumerate(faces):
        ids = []
        for j, v in enumerate(f):
            g = find(corner_id[(fi, v)])
            uv = fuv[fi][j]
            key = (v, g, round(float(uv[0]) * 65536), round(float(uv[1]) * 65536))
            k = out_index.get(key)
            if k is None:
                k = len(P)
                out_index[key] = k
                P.append(V[v])
                n = gsum[g]
                N.append(n / max(np.linalg.norm(n), 1e-12))
                UV.append(uv)
                W.append(part["W"][v])
                C.append(part["comp"][v])
            ids.append(k)
        for j in range(1, len(ids) - 1):
            tris.append((ids[0], ids[j], ids[j + 1]))
    return {"name": part["name"], "P": np.array(P), "N": np.array(N), "UV": np.array(UV), "W": np.array(W), "comp": np.array(C),
            "tris": np.array(tris, np.int64)}


# ------------------------------------------------------------------------------------------------ the bake
def rest_joints(gltf):
    """Each skin joint's head in the bind pose (metres), by joint index."""
    nodes = gltf["nodes"]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def world(i):
        t = np.array(nodes[i].get("translation", [0.0, 0.0, 0.0]))
        return t + (world(parent[i]) if i in parent else 0.0)
    joints = gltf["skins"][0]["joints"]
    return {nodes[j]["name"]: world(j) for j in joints}, [nodes[j]["name"] for j in joints]


def bake(figure, gltf, height):
    """Per output vertex of the whole figure (every part together, at rest): occlusion (R), mud and wet from the ground
    and in creases (G), wear on its edges (B) and the folds of its cloth (A, as 0.5 - fold / 2: a baked figure's mark).
    Returns one RGBA array per part."""
    import creature_rig
    allP = np.concatenate([p["P"] for p in figure])
    allN = np.concatenate([p["N"] for p in figure])
    offs = np.cumsum([0] + [len(p["P"]) for p in figure])
    allT = np.concatenate([p["tris"] + offs[i] for i, p in enumerate(figure)])
    ao = creature_rig.ambient_occlusion(allP, allN, allT, height, directions=96, res=448)
    # a little smoothing over each welded point (split vertices see the same light)
    _, inv = weld(allP, 1e-4)
    acc = np.bincount(inv, ao) / np.maximum(np.bincount(inv), 1)
    ao = 0.5 * ao + 0.5 * acc[inv]
    # convexity over each part's own surface (welded)
    edges = []
    for i, p in enumerate(figure):
        t = p["tris"] + offs[i]
        edges.append(np.concatenate([t[:, [0, 1]], t[:, [1, 2]], t[:, [2, 0]]]))
    E = np.unique(np.sort(inv[np.concatenate(edges)], 1), axis=0)
    E = E[E[:, 0] != E[:, 1]]
    first = np.zeros(inv.max() + 1, int)
    first[inv] = np.arange(len(inv))
    nW = np.zeros((inv.max() + 1, 3))
    np.add.at(nW, inv, allN)
    nW /= np.maximum(np.linalg.norm(nW, axis=1, keepdims=True), 1e-9)
    cvx = creature_rig.convexity(allP[first], nW, E, 2.5)[inv]
    y = allP[:, 1]
    # the occlusion as a share of what an open, upright surface sees (half its sky is the ground): 1 in the open, dark
    # only where something is in the way
    ao = np.clip(ao / 0.62, 0.0, 1.0) ** 0.85
    # mud: splashed up from the ground to the knees, thick on the boots, in patches; and a little in the deepest creases
    patch = _noise3(allP * 7.0, 11) * 0.6 + _noise3(allP * 19.0, 12) * 0.4
    splash = np.clip(1.0 - (y - 0.05) / 0.55, 0.0, 1.0) ** 1.6
    mud = np.clip(splash * (0.55 + 0.9 * (patch - 0.5)) + np.clip(-cvx - 0.25, 0, 1) * 0.3 + np.clip(0.5 - ao, 0, 1) * 0.2, 0.0, 1.0)
    # wear: the sharpest edges and ridges rubbed lighter (the swatches' own edges carry most of it)
    wear = np.clip((cvx - 0.3) / 0.5, 0.0, 1.0) * (0.5 + 0.7 * _noise3(allP * 23.0, 13))
    # folds: cloth bunched at the bends (elbows, knees, the backs of the knees, the waist, the shoulders, the armpits)
    heads, names = rest_joints(gltf)
    fold = np.zeros(len(allP))
    for name, k, r in (("Forearm_L", 1.0, 0.11), ("Forearm_R", 1.0, 0.11), ("Shin_L", 0.9, 0.12), ("Shin_R", 0.9, 0.12),
                       ("Spine", 0.55, 0.14), ("UpperArm_L", 0.6, 0.12), ("UpperArm_R", 0.6, 0.12), ("Hips", 0.35, 0.16),
                       ("Foot_L", 0.5, 0.08), ("Foot_R", 0.5, 0.08), ("Neck", 0.5, 0.09)):
        if name in heads:
            d = np.linalg.norm(allP - heads[name], axis=1)
            fold = np.maximum(fold, k * np.exp(-(d / r) ** 2))
    colours = np.stack([np.clip(ao, 0.0, 1.0), mud, wear, 0.5 - 0.5 * np.clip(fold, 0.0, 1.0)], 1)
    return [colours[offs[i]:offs[i + 1]] for i in range(len(figure))], ao


def _noise3(p, seed):
    """Smooth value noise in 3D (0..1), as the shader's."""
    rng = np.random.default_rng(seed)
    table = rng.random(4096)
    i = np.floor(p).astype(np.int64)
    f = p - i
    f = f * f * (3.0 - 2.0 * f)

    def h(dx, dy, dz):
        k = ((i[:, 0] + dx) * 73856093 ^ (i[:, 1] + dy) * 19349663 ^ (i[:, 2] + dz) * 83492791) & 4095
        return table[k]
    x00 = h(0, 0, 0) * (1 - f[:, 0]) + h(1, 0, 0) * f[:, 0]
    x10 = h(0, 1, 0) * (1 - f[:, 0]) + h(1, 1, 0) * f[:, 0]
    x01 = h(0, 0, 1) * (1 - f[:, 0]) + h(1, 0, 1) * f[:, 0]
    x11 = h(0, 1, 1) * (1 - f[:, 0]) + h(1, 1, 1) * f[:, 0]
    y0 = x00 * (1 - f[:, 1]) + x10 * f[:, 1]
    y1 = x01 * (1 - f[:, 1]) + x11 * f[:, 1]
    return y0 * (1 - f[:, 2]) + y1 * f[:, 2]


# ------------------------------------------------------------------------------------------------ the atlas
# The friends' atlas is a 4 x 4 grid of swatches, each polygon of the model mapped onto the whole of one. What each
# swatch is (column, row), for its grain and, in the atlas's alpha (k / 15), for the finish: 15 plain (no material:
# any other model), 14 twill, 13 canvas, 12 padded cloth, 11 leather, 10 rubber, 9 dark hard (blued steel, bakelite),
# 8 steel, 7 glass, 6 skin.
SWATCHES = {
    (0, 0): ("twill", 14),     # the coat and its sleeves
    (1, 0): ("twill", 14),     # the coat's collar, lapels, flaps and cuffs (and the rifle's grip)
    (2, 0): ("padded", 12),    # the hood, with its seam
    (3, 0): ("twill", 14),     # the trousers
    (0, 1): ("rubber", 10),    # the gloves' palms, the respirator
    (1, 1): ("leather", 11),   # the boots
    (2, 1): ("canvas", 13),    # the backpack
    (3, 1): ("webbing", 13),   # the harness, its stitching
    (0, 2): ("steel", 8),      # buckles, the rifle's barrel and butt plate
    (1, 2): ("hard", 9),       # fingers, screws, the respirator's canister, the rifle's action
    (2, 2): ("face", 6),       # the face as drawn
    (3, 2): ("glass", 7),      # the visor
    (0, 3): ("face", 6),       # the nose
    (1, 3): ("rubber", 10),    # soles, the filter's slots, the muzzle
    (2, 3): ("leather", 11),   # laces, buttons
    (3, 3): ("rubber", 10),    # the hood's rim and the visor's seals
}


def atlas(src_png, scale=4):
    """The friends' atlas redrawn `scale` times as large, as RGBA PNG bytes: each swatch its own colours and drawn lines,
    its pixel noise smoothed to a soft mottle, the grain of its material laid over at the new size, its edges worn as
    the edges of what it covers are, its saturation and brightness held to the squad's range (_night; the hood and its
    rim further, _deeper); the face resampled as a soft drawing (_upscale_drawing). Alpha: the swatch's material (SWATCHES)."""
    from PIL import Image, ImageFilter
    src = Image.open(src_png).convert("RGB")
    w, h = src.size
    tile = w // 4
    T = tile * scale
    out = np.zeros((h * scale, w * scale, 4), np.float32)
    rng = np.random.default_rng(1957)
    for (cx, cy), (kind, code) in SWATCHES.items():
        box = (cx * tile, cy * tile, (cx + 1) * tile, (cy + 1) * tile)
        sw = src.crop(box)
        arr = np.asarray(sw, np.float32) / 255.0
        if kind == "face":
            big = _upscale_drawing(sw, T)
        else:
            # the swatch's colour: its mean, a soft mottle from its own noise (blurred), and the lines drawn on it
            mean = arr.reshape(-1, 3).mean(0)
            lum = arr.mean(2)
            soft = np.asarray(Image.fromarray(np.uint8(np.clip(arr * 255, 0, 255))).filter(ImageFilter.GaussianBlur(tile / 22)).resize((T, T), Image.BICUBIC), np.float32) / 255.0
            # lines: what stands out of the swatch's own noise along a whole row or column (a seam, stitching)
            lines = _lines(lum, T)
            big = soft * (1.0 - 0.6 * lines[..., None]) + (mean * 0.45)[None, None, :] * 0.6 * lines[..., None]
            big = big * _grain(kind, T, rng)[..., None]
            big = _edges(big, kind, T, rng)
            big = _night(big)
            if (cx, cy) in DEEPER:
                big = _deeper(big, *DEEPER[(cx, cy)])
        out[cy * T:(cy + 1) * T, cx * T:(cx + 1) * T, :3] = np.clip(big, 0.0, 1.0)
        out[cy * T:(cy + 1) * T, cx * T:(cx + 1) * T, 3] = code / 15.0
    img = Image.fromarray(np.uint8(np.round(out * 255.0)), "RGBA")
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return buf.getvalue(), img


# The swatches that still stand out of the squad's dark clothes at night once in their range: the hood and its rim (and
# the visor's seals) taken down further to a dark slate blue, as dark as the squad's dark clothes, their hue kept:
# (saturation, brightness) kept.
DEEPER = {(2, 0): (0.62, 0.5), (3, 3): (0.65, 0.55)}


def _deeper(rgb, sat, val):
    import cv2
    hsv = cv2.cvtColor(np.clip(rgb, 0.0, 1.0).astype(np.float32), cv2.COLOR_RGB2HSV)
    hsv[..., 1] *= sat
    hsv[..., 2] *= val
    return cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)


def _night(rgb, sat_knee=0.42, val_knee=0.42):
    """A swatch's colour held to the squad's range under the night (their clothes are no brighter than about 0.42 and
    no more saturated than about 0.45, in sRGB): saturation and brightness above those eased back, its hue as it is.
    Most of the friends' swatches are within it already (the coat, the trousers, the boots, the backpack); the hood,
    its rim, the visor, the harness and the laces are brought in."""
    import cv2
    hsv = cv2.cvtColor(np.clip(rgb, 0.0, 1.0).astype(np.float32), cv2.COLOR_RGB2HSV)
    s, v = hsv[..., 1], hsv[..., 2]
    hsv[..., 1] = np.where(s > sat_knee, sat_knee + (s - sat_knee) * 0.35, s)
    hsv[..., 2] = np.where(v > val_knee, val_knee + (v - val_knee) * 0.4, v)
    return cv2.cvtColor(hsv, cv2.COLOR_HSV2RGB)


def _upscale_drawing(sw, size):
    """A drawing resampled to the new size as a soft drawing, not pixels: Lanczos, its source pixels' stair steps eased
    away (a blur about a source pixel wide), then a mild, broad sharpening of its lines. Their texture resampled, nothing
    redrawn."""
    from PIL import Image, ImageFilter
    k = size / sw.width
    big = sw.convert("RGB").resize((size, size), Image.LANCZOS)
    big = big.filter(ImageFilter.GaussianBlur(0.9 * k))
    big = big.filter(ImageFilter.UnsharpMask(radius=2.5 * k, percent=80, threshold=1))
    return np.asarray(big, np.float32) / 255.0


def _lines(lum, T):
    """Lines drawn across a swatch (a seam on the hood, stitching on the harness): rows or columns that stand apart from
    the swatch's mean all along their length, redrawn crisp at the new size (0..1)."""
    tile = lum.shape[0]
    out = np.zeros((T, T), np.float32)
    k = T / tile
    for axis in (0, 1):
        prof = lum.mean(axis=axis)
        base = np.median(prof)
        dev = prof - base
        sd = np.std(dev) + 1e-6
        for i in np.where(np.abs(dev) > max(3.0 * sd, 0.035))[0]:
            strength = min(1.0, abs(dev[i]) / 0.12)
            c = (i + 0.5) * k
            xs = np.arange(T, dtype=np.float32) + 0.5
            band = np.clip(1.0 - np.abs(xs - c) / (0.55 * k), 0.0, 1.0)
            if axis == 0:
                out = np.maximum(out, band[None, :] * strength)
            else:
                out = np.maximum(out, band[:, None] * strength)
    return out


def _grain(kind, T, rng):
    """The material's grain at the swatch's new size, about 1 (a multiplier)."""
    yy, xx = np.mgrid[0:T, 0:T].astype(np.float32)

    def fbm(scale, octaves=4):
        acc = np.zeros((T, T), np.float32)
        amp = 1.0
        tot = 0.0
        for o in range(octaves):
            n = max(2, int(scale * 2 ** o))
            g = rng.random((n + 1, n + 1)).astype(np.float32)
            gx = xx / T * n
            gy = yy / T * n
            i = np.floor(gx).astype(int)
            j = np.floor(gy).astype(int)
            fx = gx - i
            fy = gy - j
            fx = fx * fx * (3 - 2 * fx)
            fy = fy * fy * (3 - 2 * fy)
            v = (g[j, i] * (1 - fx) + g[j, i + 1] * fx) * (1 - fy) + (g[j + 1, i] * (1 - fx) + g[j + 1, i + 1] * fx) * fy
            acc += v * amp
            tot += amp
            amp *= 0.5
        return acc / tot - 0.5
    if kind == "twill":
        ribs = np.sin((xx + yy) * (2 * np.pi / 6.0)) * 0.5 + np.sin((xx - yy * 0.2) * (2 * np.pi / 3.1)) * 0.15
        return 1.0 + 0.035 * ribs + 0.10 * fbm(10) + 0.06 * fbm(40, 2)
    if kind in ("canvas", "webbing"):
        weave = np.sin(xx * (2 * np.pi / 4.0)) * np.sin(yy * (2 * np.pi / 4.0))
        return 1.0 + 0.05 * weave + 0.12 * fbm(8) + 0.05 * fbm(48, 2)
    if kind == "padded":
        return 1.0 + 0.10 * fbm(6) + 0.05 * fbm(60, 2)
    if kind == "leather":
        return 1.0 + 0.16 * fbm(5) + 0.07 * fbm(70, 2)
    if kind == "rubber":
        return 1.0 + 0.07 * fbm(6) + 0.04 * fbm(80, 2)
    if kind in ("steel", "hard"):
        return 1.0 + 0.08 * fbm(4) + 0.03 * fbm(90, 2)
    if kind == "glass":
        return 1.0 + 0.05 * fbm(3)
    return np.ones((T, T), np.float32)


def _edges(img, kind, T, rng):
    """The edges of a swatch are the edges of the boxes it covers: leather, canvas, rubber and steel rubbed lighter
    there (cloth is left alone: its swatch's edges are only where the friends' polygons met)."""
    yy, xx = np.mgrid[0:T, 0:T].astype(np.float32)
    d = np.minimum(np.minimum(xx, T - 1 - xx), np.minimum(yy, T - 1 - yy)) / T
    jitter = 0.012 * np.sin(xx * 0.11 + rng.random() * 6) * np.sin(yy * 0.07 + rng.random() * 6)
    band = np.clip(1.0 - (d + jitter) / 0.06, 0.0, 1.0) ** 1.5
    if kind in ("leather", "canvas", "webbing", "rubber", "steel", "hard"):
        lift = {"leather": 0.30, "canvas": 0.22, "webbing": 0.15, "rubber": 0.12, "steel": 0.25, "hard": 0.18}[kind]
        grey = img.mean(2, keepdims=True)
        worn = img * (1.0 + lift) * 0.75 + grey * (1.0 + lift) * 0.25
        return img + (worn - img) * band[..., None]
    return img


# ------------------------------------------------------------------------------------------------ writing
def write_glb(path, gltf, binary, figure, colours, image_png, image_name, lod=False, generator="tools/art_pack.py refine-person"):
    """The source's scene, skeleton, skin and clips as they are; its meshes replaced by the refined parts (or, for the
    lighter copy, by one mesh of them all, carrying each vertex's rest place in TEXCOORD_2 / TEXCOORD_3); its atlas by
    the new one (the lighter copy carries no atlas: the game dresses it in the full model's material)."""
    doc = json.loads(json.dumps(gltf))
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
        a = {"bufferView": len(views) - 1, "componentType": comp, "count": count, "type": kind}
        if mn is not None:
            a["min"], a["max"] = mn, mx
        if normalized:
            a["normalized"] = True
        accessors.append(a)
        return len(accessors) - 1

    def copy_accessor(i):
        a = gltf["accessors"][i]
        arr = accessor(gltf, binary, i)
        out = add(np.ascontiguousarray(arr).tobytes(), a["type"], a["componentType"], a["count"], None, a.get("min"), a.get("max"), a.get("normalized", False))
        return out
    # skins and clips: copied as they are
    for skin in doc.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = copy_accessor(skin["inverseBindMatrices"])
    for anim in doc.get("animations", []):
        for s in anim["samplers"]:
            s["input"] = copy_accessor(s["input"])
            s["output"] = copy_accessor(s["output"])

    def primitive(P, N, UV, Wd, C, tris, rest=None):
        P32 = np.ascontiguousarray(P, np.float32)
        at = {"POSITION": add(P32.tobytes(), "VEC3", 5126, len(P32), 34962, P32.min(0).tolist(), P32.max(0).tolist()),
              "NORMAL": add(np.ascontiguousarray(N, np.float32).tobytes(), "VEC3", 5126, len(P32), 34962),
              "TEXCOORD_0": add(np.ascontiguousarray(UV, np.float32).tobytes(), "VEC2", 5126, len(P32), 34962)}
        col = np.clip(np.round(C * 255.0), 0, 255).astype(np.uint8)
        at["COLOR_0"] = add(np.ascontiguousarray(col).tobytes(), "VEC4", 5121, len(P32), 34962, normalized=True)
        order = np.argsort(-Wd, axis=1)[:, :4]
        wv = np.take_along_axis(Wd, order, 1)
        wv = np.where(wv < 0.004, 0.0, wv)
        wv /= np.maximum(wv.sum(1, keepdims=True), 1e-9)
        order = np.where(wv > 0.0, order, 0)
        at["JOINTS_0"] = add(np.ascontiguousarray(order, np.uint8).tobytes(), "VEC4", 5121, len(P32), 34962)
        at["WEIGHTS_0"] = add(np.ascontiguousarray(wv, np.float32).tobytes(), "VEC4", 5126, len(P32), 34962)
        if rest is not None:
            at["TEXCOORD_2"] = add(np.ascontiguousarray(rest[:, :2], np.float32).tobytes(), "VEC2", 5126, len(P32), 34962)
            at["TEXCOORD_3"] = add(np.ascontiguousarray(rest[:, 2:], np.float32).tobytes(), "VEC2", 5126, len(P32), 34962)
        idx = np.ascontiguousarray(tris, np.uint32).ravel()
        return {"attributes": at, "indices": add(idx.tobytes(), "SCALAR", 5125, len(idx), 34963), "material": 0}
    if not lod:
        by_name = {p["name"]: (p, c) for p, c in zip(figure, colours)}
        for m in doc["meshes"]:
            p, c = by_name[m["name"]]
            m["primitives"] = [primitive(p["P"], p["N"], p["UV"], p["W"], c, p["tris"])]
    else:
        offs = np.cumsum([0] + [len(p["P"]) for p in figure])
        P = np.concatenate([p["P"] for p in figure])
        N = np.concatenate([p["N"] for p in figure])
        rest = np.concatenate([P, N[:, 1:2], np.zeros((len(P), 1))], 1)
        prim = primitive(P, N, np.concatenate([p["UV"] for p in figure]), np.concatenate([p["W"] for p in figure]),
                         np.concatenate(colours), np.concatenate([p["tris"] + offs[i] for i, p in enumerate(figure)]), rest[:, :4])
        doc["meshes"] = [{"name": "Body", "primitives": [prim]}]
        mesh_nodes = [i for i, n in enumerate(doc["nodes"]) if "mesh" in n]
        keep = mesh_nodes[0]
        doc["nodes"][keep]["mesh"] = 0
        doc["nodes"][keep]["name"] = "Body"
        # the other part nodes become empty (indices kept, so the skeleton's stay the same)
        for i in mesh_nodes[1:]:
            doc["nodes"][i].pop("mesh", None)
            doc["nodes"][i].pop("skin", None)
    # the atlas (the lighter copy has none: the game dresses it in the full model's material)
    if lod:
        for key in ("images", "textures", "samplers"):
            doc.pop(key, None)
        for m in doc.get("materials", []):
            m.get("pbrMetallicRoughness", {}).pop("baseColorTexture", None)
    else:
        while len(chunks) % 4:
            chunks.append(0)
        views.append({"buffer": 0, "byteOffset": len(chunks), "byteLength": len(image_png)})
        chunks.extend(image_png)
        doc["images"] = [{"name": image_name, "bufferView": len(views) - 1, "mimeType": "image/png"}]
        doc["samplers"] = [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}]
    doc["accessors"] = accessors
    doc["bufferViews"] = views
    while len(chunks) % 4:
        chunks.append(0)
    doc["buffers"] = [{"byteLength": len(chunks)}]
    doc["asset"] = dict(doc.get("asset", {}))
    doc["asset"]["generator"] = generator + (" (lighter copy)" if lod else "")
    js = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(chunks), 0x004E4942) + bytes(chunks)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


# ------------------------------------------------------------------------------------------------ the whole
def refine(src, dst, lod_path=None, atlas_out=None, scale=4, report=print):
    gltf, binary = read_glb(src)
    src_parts = parts(gltf, binary)
    before = sum(len(p["tris"]) for p in src_parts)
    image = gltf["images"][0]
    view = gltf["bufferViews"][image["bufferView"]]
    png = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
    tmp = io.BytesIO(png)
    atlas_png, atlas_img = atlas(tmp, scale)
    name = image.get("name", "Atlas").rstrip("0123456789") + str(atlas_img.size[0])
    if atlas_out:
        atlas_img.save(atlas_out)
    height = max(float(p["P"][:, 1].max()) for p in src_parts)
    out = {}
    for which in (["full", "lod"] if lod_path else ["full"]):
        figure = [triangulate(refine_part(p, lod=(which == "lod"))) for p in src_parts]
        colours, ao = bake(figure, gltf, height)
        write_glb(dst if which == "full" else lod_path, gltf, binary, figure, colours, atlas_png, name, lod=(which == "lod"))
        tris = sum(len(p["tris"]) for p in figure)
        out[which] = tris
        report(f"  {which}: {tris} triangles (from {before}), {sum(len(p['P']) for p in figure)} vertices -> {dst if which == 'full' else lod_path}")
        if which == "full":
            for p in figure:
                report(f"    {p['name']:13s} {len(p['tris']):5d} triangles")
    report(f"  atlas {atlas_img.size[0]} x {atlas_img.size[1]} ({len(atlas_png) // 1024} KB), named {name}")
    return out
