"""Turn the authored Arbiter glTF into the Lance's runtime model.

The file is already in game axes (nose -Z, +Y up, +X starboard) and carries the
13 animations. Static root meshes are split into nose / body / aft so the armour
view can tint them (mesh names starting N_ / B_ / A_). Surfaces that share a
mesh and a visual material are then joined, and the non-hull static root parts
are joined per section. Animated nodes are not renamed, so every clip still
finds its targets.

Cuts match the Dagger's section fractions on this hull: the armoured nose
(forward of z = -42) and the engineering aft (aft of z = 52).

Run:  python art/prepare_arbiter.py [src.glb] [dst.glb]

A denser hull drops in as the source glb. Keep the node names the game looks up
(turret yaw/pitch, sensor yaw/pitch, coil glows, radiator geos, the OMS plume
nodes including OMS_A010_Fore_Bottom_Plume_Radial, the drive plume, the rotary
ammo-feed flex bones RT0N_Flex_00..07 and the rotary dome geos) and the 13
animation names below. Do not rename them and do not subdivide here: the
silhouette comes from the file. A base colour the file already set (anything
other than default white) is left alone; only a material still at the glTF
default is filled from the colour in its name. Emissive strength is capped.
Meshes whose normals already leave the face (weighted normals) are left as
authored; face-flat meshes are still smoothed across gentle edges. The script
refuses to write a file that dropped an animation, a required node, or a skin
joint. Godot imports with mesh LODs off and embedded images as Basis Universal
(game/models/arbiter.glb.import); it also inserts a rest track for every
animated node into every clip, which the game strips. TurretTrack's flex
channels stay on that clip only.
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DEFAULT = os.path.join(HERE, "source", "arbiter-TDC_v18d.glb")
DST_DEFAULT = os.path.join(HERE, "..", "game", "models", "arbiter.glb")

# World Z of the section planes (authored metres, nose at -Z).
NOSE_Z = -42.0
AFT_Z = 52.0
SECS = ("N", "B", "A")

CT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
FLOAT = 5126
UINT = 5125


def load_glb(path):
    with open(path, "rb") as f:
        data = f.read()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise SystemExit("not a glb: %s" % path)
    off = 12
    gltf = None
    blob = b""
    while off + 8 <= len(data):
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            gltf = json.loads(chunk)
        elif ctype == 0x004E4942:
            blob = chunk
    return gltf, bytearray(blob)


def save_glb(path, gltf, blob):
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_pad = (4 - len(blob) % 4) % 4
    blob = bytes(blob) + b"\x00" * bin_pad
    total = 12 + 8 + len(js) + 8 + len(blob)
    out = bytearray()
    out += struct.pack("<III", 0x46546C67, 2, total)
    out += struct.pack("<II", len(js), 0x4E4F534A)
    out += js
    out += struct.pack("<II", len(blob), 0x004E4942)
    out += blob
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(out)


def read_acc(gltf, blob, idx):
    acc = gltf["accessors"][idx]
    bv = gltf["bufferViews"][acc["bufferView"]]
    comp = CT_SIZE[acc["componentType"]]
    n = TYPE_N[acc["type"]]
    stride = bv.get("byteStride", comp * n)
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = {5126: "f", 5123: "H", 5125: "I", 5121: "B", 5120: "b", 5122: "h"}[acc["componentType"]]
    out = []
    for i in range(acc["count"]):
        vals = struct.unpack_from("<" + fmt * n, blob, start + i * stride)
        out.append(vals if n > 1 else vals[0])
    return out


def qrot(q, v):
    x, y, z, w = q
    tx = 2 * (y * v[2] - z * v[1])
    ty = 2 * (z * v[0] - x * v[2])
    tz = 2 * (x * v[1] - y * v[0])
    return (
        v[0] + w * tx + (y * tz - z * ty),
        v[1] + w * ty + (z * tx - x * tz),
        v[2] + w * tz + (x * ty - y * tx),
    )


def node_matrix(n):
    """3x3 rotation (columns) and translation. Scale is folded into the columns."""
    if "matrix" in n:
        m = n["matrix"]
        rot = ((m[0], m[1], m[2]), (m[4], m[5], m[6]), (m[8], m[9], m[10]))
        return rot, (m[12], m[13], m[14])
    t = tuple(n.get("translation", (0, 0, 0)))
    q = tuple(n.get("rotation", (0, 0, 0, 1)))
    s = tuple(n.get("scale", (1, 1, 1)))
    x = qrot(q, (s[0], 0, 0))
    y = qrot(q, (0, s[1], 0))
    z = qrot(q, (0, 0, s[2]))
    return (x, y, z), t


def apply(rot, t, p):
    return (
        t[0] + rot[0][0] * p[0] + rot[1][0] * p[1] + rot[2][0] * p[2],
        t[1] + rot[0][1] * p[0] + rot[1][1] * p[1] + rot[2][1] * p[2],
        t[2] + rot[0][2] * p[0] + rot[1][2] * p[1] + rot[2][2] * p[2],
    )


def section_of(z):
    if z < NOSE_Z:
        return 0
    if z > AFT_Z:
        return 2
    return 1


def append_view(gltf, blob, data, target):
    """Append a tightly packed buffer view and accessor. data is bytes. Returns accessor index."""
    # pad to the component alignment (4)
    while len(blob) % 4:
        blob.append(0)
    offset = len(blob)
    blob.extend(data)
    bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
    if target:
        bv["target"] = target
    gltf["bufferViews"].append(bv)
    return len(gltf["bufferViews"]) - 1


def write_vec(gltf, blob, values, ncomp, target):
    raw = bytearray()
    for v in values:
        if ncomp == 1:
            raw += struct.pack("<f", v)
        else:
            raw += struct.pack("<" + "f" * ncomp, *v[:ncomp])
    bvi = append_view(gltf, blob, raw, target)
    acc = {
        "bufferView": bvi,
        "componentType": FLOAT,
        "count": len(values),
        "type": {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[ncomp],
    }
    if ncomp == 3 and values:
        xs = [v[0] for v in values]
        ys = [v[1] for v in values]
        zs = [v[2] for v in values]
        acc["min"] = [min(xs), min(ys), min(zs)]
        acc["max"] = [max(xs), max(ys), max(zs)]
    gltf["accessors"].append(acc)
    return len(gltf["accessors"]) - 1


def write_indices(gltf, blob, indices):
    raw = struct.pack("<%dI" % len(indices), *indices)
    bvi = append_view(gltf, blob, raw, 34963)
    gltf["accessors"].append({
        "bufferView": bvi,
        "componentType": UINT,
        "count": len(indices),
        "type": "SCALAR",
    })
    return len(gltf["accessors"]) - 1


def split_node(gltf, blob, node_index):
    """Replace one static mesh node with up to three section nodes. Returns new node indices."""
    node = gltf["nodes"][node_index]
    mesh = gltf["meshes"][node["mesh"]]
    rot, trans = node_matrix(node)
    # bucket key -> {"idx": [], "attrs": {name: [values]}}
    buckets = {}
    for prim in mesh["primitives"]:
        attrs = {}
        for name, ai in prim["attributes"].items():
            attrs[name] = read_acc(gltf, blob, ai)
        pos = attrs["POSITION"]
        if "indices" in prim:
            indices = read_acc(gltf, blob, prim["indices"])
        else:
            indices = list(range(len(pos)))
        mat = prim.get("material")
        sig = tuple(sorted(prim["attributes"]))
        for t in range(0, len(indices) - 2, 3):
            tri = indices[t:t + 3]
            cz = 0.0
            for vi in tri:
                cz += apply(rot, trans, pos[vi])[2]
            sec = section_of(cz / 3.0)
            key = (sec, mat, sig)
            b = buckets.get(key)
            if b is None:
                b = {"idx": [], "remap": {}, "attrs": {a: [] for a in attrs}}
                buckets[key] = b
            for vi in tri:
                mk = vi
                if mk not in b["remap"]:
                    b["remap"][mk] = len(b["attrs"]["POSITION"])
                    for a, arr in attrs.items():
                        b["attrs"][a].append(arr[vi])
                b["idx"].append(b["remap"][mk])
    if not buckets:
        return []
    made = []
    by_sec = {0: [], 1: [], 2: []}
    for key, b in buckets.items():
        by_sec[key[0]].append((key, b))
    base = node.get("name", "part")
    if base == "Hull":
        base = "hull"
    for sec, items in by_sec.items():
        if not items:
            continue
        prims = []
        for (sec_i, mat, sig), b in items:
            prim = {"attributes": {}, "mode": 4}
            if mat is not None:
                prim["material"] = mat
            for name, vals in b["attrs"].items():
                ncomp = len(vals[0]) if isinstance(vals[0], tuple) else 1
                target = 34962
                prim["attributes"][name] = write_vec(gltf, blob, vals, ncomp, target)
            prim["indices"] = write_indices(gltf, blob, b["idx"])
            prims.append(prim)
        gltf["meshes"].append({"name": "%s_%s" % (SECS[sec], base), "primitives": prims})
        new = {"name": "%s_%s" % (SECS[sec], base), "mesh": len(gltf["meshes"]) - 1}
        for field in ("translation", "rotation", "scale", "matrix"):
            if field in node:
                new[field] = node[field]
        gltf["nodes"].append(new)
        made.append(len(gltf["nodes"]) - 1)
    return made


def material_fp(gltf, mi):
    """What Godot actually draws. Names differ; identical factors batch as one material.
    Anisotropy is ignored because the importer drops that extension."""
    if mi is None:
        return None
    m = gltf["materials"][mi]
    p = m.get("pbrMetallicRoughness", {})
    tex = []

    def walk(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if isinstance(v, dict) and "index" in v and "texture" in k.lower():
                    tex.append((k, v["index"]))
                else:
                    walk(v)
        elif isinstance(o, list):
            for v in o:
                walk(v)

    walk(m)
    bc = tuple(round(float(x), 5) for x in p.get("baseColorFactor", [1, 1, 1, 1]))
    em = tuple(round(float(x), 5) for x in m.get("emissiveFactor", [0, 0, 0]))
    return (
        bc,
        round(float(p.get("metallicFactor", 1.0)), 5),
        round(float(p.get("roughnessFactor", 1.0)), 5),
        em,
        m.get("alphaMode", "OPAQUE"),
        tuple(sorted(tex)),
    )


def _srgb_hex(text):
    """Last 6-digit hex in a material name, as linear RGB. Artists put the paint in the name
    and left baseColorFactor at the glTF default, so Godot drew those surfaces white."""
    import re
    hits = re.findall(r"(?<![0-9A-Fa-f])([0-9A-Fa-f]{6})(?![0-9A-Fa-f])", text)
    if not hits:
        return None
    h = hits[-1]
    out = []
    for i in range(3):
        c = int(h[i * 2:i * 2 + 2], 16) / 255.0
        if c <= 0.04045:
            out.append(c / 12.92)
        else:
            out.append(((c + 0.055) / 1.055) ** 2.4)
    return out


# Paints whose names carry no hex. Values are sRGB hex, converted on use.
_NAMED_PAINT = {
    "MAT_Gunmetal": "5A616C",
    "MAT_DriveRing_BrightMetal": "C6C9CF",
    "MAT_Recess_Dark": "14161A",
    "MAT_RadarDome_LightGrey": "C4C7CB",
    "MAT_Cable_Black": "161616",
    "MAT_DarkComposite_ESM": "2C3034",
    "MAT_HazardStripes_Face": "C9962A",
    "MAT_HazardTape_XY": "C9962A",
    "MAT_HazardTape_XZ": "C9962A",
    "MAT_HazardEdge_Cyl": "1A1C1E",
    "MAT_NavLight_Red": "8A1A16",
    "MAT_NavLight_Green": "1A6A28",
    "MAT_Strobe_White": "E6E8EA",
}


def paint_named_colors(gltf):
    """Give untextured materials the colour written in their name. A factor that is already
    set (and not the default white) is the artist's, so it stays."""
    painted = 0
    for m in gltf["materials"]:
        p = m.setdefault("pbrMetallicRoughness", {})
        if "baseColorTexture" in p:
            continue
        bc = p.get("baseColorFactor")
        if bc is not None and not all(abs(float(bc[i]) - 1.0) < 1e-4 for i in range(3)):
            continue
        name = m.get("name", "")
        rgb = _srgb_hex(name)
        if rgb is None:
            base = name.split(".")[0]
            if base in _NAMED_PAINT:
                rgb = _srgb_hex(_NAMED_PAINT[base])
        if rgb is None and name.startswith("PDL"):
            rgb = _srgb_hex("1A1020")
        if rgb is None:
            continue
        alpha = float(bc[3]) if bc is not None and len(bc) > 3 else 1.0
        p["baseColorFactor"] = [rgb[0], rgb[1], rgb[2], alpha]
        painted += 1
    return painted


# Authored KHR_materials_emissive_strength runs from 5 (plume) to 150 (projectile). Godot
# multiplies emission by it, and the glow threshold is 1.6, so the throat (×45) and the
# plume core wash the frame out. Cap the multiplier; the colour stays the artist's.
_EMISSIVE_CAP = {
    "MAT_FX_CoilGlow": 1.35,
    "MAT_FX_MuzzleFlare": 1.6,
    "MAT_FX_MuzzleFlash": 2.0,
    "MAT_FX_Projectile": 1.5,
    "MAT_FX_TracerTail": 1.5,
    "MAT_FX_TracerHot": 1.5,
    "MAT_FX_DrivePlume": 1.15,
    "MAT_FX_DriveCore": 1.45,
    "MAT_DriveThroat_Emissive_BFD8FF": 1.35,
    "MAT_NavLight_Red": 1.8,
    "MAT_NavLight_Green": 1.8,
    "MAT_Strobe_White": 1.8,
    "MAT_FX_LaserBeam": 1.8,
    "MAT_FX_LaserGlow": 1.4,
    "MAT_FX_OMSGas": 1.45,
    "MAT_ArmedRing_Teal_7FD1C7.001": 1.8,
    # Just over the glow threshold (1.6) so the aperture ring blooms, and under the
    # old coil-gun wash. The runtime tamer leaves a peak of 1.7 alone.
    "MAT_FEL_ApertureGlow_White": 1.7,
}


def cap_emissive_strength(gltf):
    capped = 0
    for m in gltf["materials"]:
        ext = m.get("extensions") or {}
        kh = ext.get("KHR_materials_emissive_strength")
        if not kh:
            continue
        strength = float(kh.get("emissiveStrength", 1.0))
        name = m.get("name", "")
        limit = _EMISSIVE_CAP.get(name)
        if limit is None and strength > 2.0:
            limit = 1.8
        if limit is None or strength <= limit:
            continue
        kh["emissiveStrength"] = limit
        capped += 1
    return capped


def _write_normals(gltf, blob, acc_i, normals):
    acc = gltf["accessors"][acc_i]
    bv = gltf["bufferViews"][acc["bufferView"]]
    stride = bv.get("byteStride", 12)
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    mn = [1e9, 1e9, 1e9]
    mx = [-1e9, -1e9, -1e9]
    for i, v in enumerate(normals):
        struct.pack_into("<fff", blob, start + i * stride, v[0], v[1], v[2])
        for k in range(3):
            if v[k] < mn[k]:
                mn[k] = v[k]
            if v[k] > mx[k]:
                mx[k] = v[k]
    acc["min"] = mn
    acc["max"] = mx


def _authored_is_weighted(gltf, blob, loaded):
    """True when normals already tilt off their faces. A crease average would replace that
    weighting. A face-flat export matches the face on essentially every corner."""
    import math
    off = 0
    total = 0
    for p, pos, idx in loaded:
        nrm = read_acc(gltf, blob, p["attributes"]["NORMAL"])
        for f in range(0, len(idx) - 2, 3):
            i0, i1, i2 = int(idx[f]), int(idx[f + 1]), int(idx[f + 2])
            a, b, c = pos[i0], pos[i1], pos[i2]
            e1 = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            e2 = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            fn = (
                e1[1] * e2[2] - e1[2] * e2[1],
                e1[2] * e2[0] - e1[0] * e2[2],
                e1[0] * e2[1] - e1[1] * e2[0],
            )
            ln = math.sqrt(fn[0] * fn[0] + fn[1] * fn[1] + fn[2] * fn[2])
            if ln < 1e-12:
                continue
            fn = (fn[0] / ln, fn[1] / ln, fn[2] / ln)
            for corner in (i0, i1, i2):
                nv = nrm[corner]
                ln2 = math.sqrt(nv[0] * nv[0] + nv[1] * nv[1] + nv[2] * nv[2]) or 1.0
                d = (nv[0] * fn[0] + nv[1] * fn[1] + nv[2] * fn[2]) / ln2
                total += 1
                if d < 0.995:
                    off += 1
    return total > 0 and off / total > 0.04


def smooth_curved_normals(gltf, blob, crease_deg=50.0):
    """Face-flat meshes shade cylinders as facets. Average corners that share a position
    when the faces meet more gently than crease_deg. A mesh whose normals already leave
    the face is left as authored. Hard panel edges stay split. Effect meshes are left
    alone. Returns (smoothed, kept)."""
    import math
    cos_lim = math.cos(math.radians(crease_deg))
    fx_bits = ("MAT_FX_", "Plume", "Muzzle", "Projectile", "Tracer", "OMSGas", "LaserBeam", "LaserGlow")
    smoothed = 0
    kept = 0
    for mesh in gltf["meshes"]:
        prims = mesh["primitives"]
        names = []
        skip = False
        for p in prims:
            mi = p.get("material")
            if mi is None:
                continue
            nm = gltf["materials"][mi].get("name", "")
            names.append(nm)
            if any(b in nm for b in fx_bits):
                skip = True
        if skip or not prims:
            continue
        loaded = []
        ok = True
        for p in prims:
            attrs = p.get("attributes", {})
            if "POSITION" not in attrs or "NORMAL" not in attrs:
                ok = False
                break
            pos = read_acc(gltf, blob, attrs["POSITION"])
            if "indices" in p:
                idx = list(read_acc(gltf, blob, p["indices"]))
            else:
                idx = list(range(len(pos)))
            loaded.append((p, pos, idx))
        if not ok:
            continue
        if _authored_is_weighted(gltf, blob, loaded):
            kept += 1
            continue
        groups = {}
        face_of = []  # per prim: list of (i0,i1,i2,fn) aligned so corners can look up
        for pi, (p, pos, idx) in enumerate(loaded):
            faces = []
            for f in range(0, len(idx) - 2, 3):
                i0, i1, i2 = int(idx[f]), int(idx[f + 1]), int(idx[f + 2])
                a, b, c = pos[i0], pos[i1], pos[i2]
                e1 = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
                e2 = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
                fn = (
                    e1[1] * e2[2] - e1[2] * e2[1],
                    e1[2] * e2[0] - e1[0] * e2[2],
                    e1[0] * e2[1] - e1[1] * e2[0],
                )
                ln = math.sqrt(fn[0] * fn[0] + fn[1] * fn[1] + fn[2] * fn[2])
                fn = (fn[0] / ln, fn[1] / ln, fn[2] / ln) if ln > 1e-12 else (0.0, 1.0, 0.0)
                faces.append(fn)
                for corner in (i0, i1, i2):
                    q = pos[corner]
                    key = (round(q[0], 4), round(q[1], 4), round(q[2], 4))
                    groups.setdefault(key, []).append((pi, corner, fn))
            face_of.append(faces)
        out = [[None] * len(pos) for (_, pos, _) in loaded]
        for items in groups.values():
            # One normal per corner index. Reference is the mean of the faces that already share it.
            by_corner = {}
            for pi, corner, fn in items:
                by_corner.setdefault((pi, corner), []).append(fn)
            for (pi, corner), fns in by_corner.items():
                ref = [0.0, 0.0, 0.0]
                for fn in fns:
                    ref[0] += fn[0]
                    ref[1] += fn[1]
                    ref[2] += fn[2]
                ln = math.sqrt(ref[0] * ref[0] + ref[1] * ref[1] + ref[2] * ref[2])
                if ln < 1e-8:
                    continue
                ref = (ref[0] / ln, ref[1] / ln, ref[2] / ln)
                accn = [0.0, 0.0, 0.0]
                for _pi, _c, fn in items:
                    d = ref[0] * fn[0] + ref[1] * fn[1] + ref[2] * fn[2]
                    if d >= cos_lim:
                        accn[0] += fn[0]
                        accn[1] += fn[1]
                        accn[2] += fn[2]
                ln = math.sqrt(accn[0] * accn[0] + accn[1] * accn[1] + accn[2] * accn[2])
                out[pi][corner] = (accn[0] / ln, accn[1] / ln, accn[2] / ln) if ln > 1e-8 else ref
        for (p, pos, _idx), normals in zip(loaded, out):
            # Corners a degenerate face never touched keep the authored normal.
            authored = read_acc(gltf, blob, p["attributes"]["NORMAL"])
            packed = []
            for i, n in enumerate(normals):
                packed.append(n if n is not None else authored[i])
            _write_normals(gltf, blob, p["attributes"]["NORMAL"], packed)
        smoothed += 1
    return smoothed, kept


def canonical_materials(gltf):
    """First material index for each visual fingerprint."""
    first = {}
    out = {}
    for i in range(len(gltf["materials"])):
        f = material_fp(gltf, i)
        if f not in first:
            first[f] = i
        out[i] = first[f]
    return out


def _tri_count(gltf, prim):
    if "indices" in prim:
        return gltf["accessors"][prim["indices"]]["count"] // 3
    return gltf["accessors"][prim["attributes"]["POSITION"]]["count"] // 3


def concat_prims(gltf, blob, prims, mat, textured):
    positions = []
    normals = []
    uvs = []
    indices = []
    for prim in prims:
        attrs = {k: read_acc(gltf, blob, ai) for k, ai in prim["attributes"].items()}
        pos = attrs["POSITION"]
        nrm = attrs.get("NORMAL")
        uv = attrs.get("TEXCOORD_0")
        if "indices" in prim:
            idx = read_acc(gltf, blob, prim["indices"])
        else:
            idx = list(range(len(pos)))
        base = len(positions)
        positions.extend(pos)
        normals.extend(nrm if nrm else [(0.0, 1.0, 0.0)] * len(pos))
        if textured:
            uvs.extend(uv if uv else [(0.0, 0.0)] * len(pos))
        indices.extend(base + i for i in idx)
    out = {"attributes": {}, "mode": 4}
    if mat is not None:
        out["material"] = mat
    out["attributes"]["POSITION"] = write_vec(gltf, blob, positions, 3, 34962)
    out["attributes"]["NORMAL"] = write_vec(gltf, blob, normals, 3, 34962)
    if textured:
        out["attributes"]["TEXCOORD_0"] = write_vec(gltf, blob, uvs, 2, 34962)
    out["indices"] = write_indices(gltf, blob, indices)
    return out


def merge_mesh_prims(gltf, blob, node_ids, canon):
    """One primitive per visual material on each mesh. Animated nodes are untouched as nodes;
    only surfaces that already share a mesh (and therefore move together) are joined."""
    seen = set()
    before = 0
    after = 0
    for ni in node_ids:
        n = gltf["nodes"][ni]
        if "mesh" not in n:
            continue
        mi = n["mesh"]
        if mi in seen:
            continue
        seen.add(mi)
        mesh = gltf["meshes"][mi]
        groups = {}
        order = []
        for prim in mesh["primitives"]:
            before += 1
            src = prim.get("material")
            c = canon.get(src, src)
            textured = bool(material_fp(gltf, c)[-1]) if c is not None else False
            key = (c, textured)
            if key not in groups:
                groups[key] = []
                order.append(key)
            groups[key].append(prim)
        new_prims = []
        for key in order:
            c, textured = key
            prims = groups[key]
            if len(prims) == 1:
                prims[0]["material"] = c
                new_prims.append(prims[0])
            else:
                new_prims.append(concat_prims(gltf, blob, prims, c, textured))
        mesh["primitives"] = new_prims
        after += len(new_prims)
    return before, after


def merge_fittings(gltf, blob, root):
    """Join static root meshes that are not the pressure hull and share a section and a material.
    Root children here are at identity, so vertices already share a space. Hull nodes stay, so the
    hot-spot box does not grow to include the point-defence lattice."""
    nodes = gltf["nodes"]
    canon_groups = {}
    order = []
    kept = []
    dropped = 0
    for ci in list(nodes[root].get("children", [])):
        n = nodes[ci]
        name = n.get("name", "")
        if "mesh" not in n or name in ("N_hull", "B_hull", "A_hull") or n.get("children"):
            kept.append(ci)
            continue
        sec = name[0] if name[:2] in ("N_", "B_", "A_") else "B"
        for prim in gltf["meshes"][n["mesh"]]["primitives"]:
            mat = prim.get("material")
            key = (sec, mat)
            if key not in canon_groups:
                canon_groups[key] = []
                order.append(key)
            canon_groups[key].append(prim)
        dropped += 1
    by_sec = {s: [] for s in SECS}
    for key in order:
        sec, mat = key
        prims = canon_groups[key]
        textured = bool(material_fp(gltf, mat)[-1]) if mat is not None else False
        if len(prims) == 1:
            by_sec[sec].append(prims[0])
        else:
            by_sec[sec].append(concat_prims(gltf, blob, prims, mat, textured))
    for sec in SECS:
        prims = by_sec[sec]
        if not prims:
            continue
        gltf["meshes"].append({"name": "%s_fittings" % sec, "primitives": prims})
        gltf["nodes"].append({"name": "%s_fittings" % sec, "mesh": len(gltf["meshes"]) - 1})
        kept.append(len(gltf["nodes"]) - 1)
    nodes[root]["children"] = kept
    return dropped


def reachable(gltf):
    nodes = gltf["nodes"]
    root = gltf["scenes"][gltf.get("scene", 0)]["nodes"][0]
    seen = set()

    def walk(i):
        if i in seen:
            return
        seen.add(i)
        for c in nodes[i].get("children", []):
            walk(c)

    walk(root)
    return seen


def prune_unreachable(gltf):
    """Drop nodes the scene does not draw. Animation targets are all in the scene; indices are remapped."""
    nodes = gltf["nodes"]
    reach = reachable(gltf)
    for a in gltf["animations"]:
        for ch in a["channels"]:
            ni = ch["target"]["node"]
            if ni not in reach:
                raise SystemExit("animation target left the scene: %s" % nodes[ni].get("name"))
    keep = [i for i in range(len(nodes)) if i in reach]
    mp = {old: new for new, old in enumerate(keep)}
    new_nodes = []
    for old in keep:
        n = dict(nodes[old])
        if "children" in n:
            n["children"] = [mp[c] for c in n["children"] if c in mp]
        new_nodes.append(n)
    gltf["nodes"] = new_nodes
    scene = gltf["scenes"][gltf.get("scene", 0)]
    scene["nodes"] = [mp[i] for i in scene["nodes"]]
    for a in gltf["animations"]:
        for ch in a["channels"]:
            ch["target"]["node"] = mp[ch["target"]["node"]]
    # Skins point at joint nodes by index. Remap them with the nodes or the hose
    # deforms off the wrong bone after fittings are pruned.
    for sk in gltf.get("skins", []):
        for j in sk.get("joints", []):
            if j not in mp:
                raise SystemExit("skin joint left the scene: %s" % nodes[j].get("name"))
        sk["joints"] = [mp[j] for j in sk["joints"]]
        if "skeleton" in sk:
            if sk["skeleton"] not in mp:
                raise SystemExit("skin skeleton left the scene")
            sk["skeleton"] = mp[sk["skeleton"]]
    return len(nodes) - len(new_nodes)


def compact_buffers(gltf, blob):
    """Keep buffer bytes that a live mesh, an animation or an image still points at."""
    used_mesh = set()
    for n in gltf["nodes"]:
        if "mesh" in n:
            used_mesh.add(n["mesh"])
    keep_m = sorted(used_mesh)
    mm = {old: new for new, old in enumerate(keep_m)}
    gltf["meshes"] = [gltf["meshes"][i] for i in keep_m]
    for n in gltf["nodes"]:
        if "mesh" in n:
            n["mesh"] = mm[n["mesh"]]
    used_a = set()
    for mesh in gltf["meshes"]:
        for p in mesh["primitives"]:
            for ai in p["attributes"].values():
                used_a.add(ai)
            if "indices" in p:
                used_a.add(p["indices"])
    for a in gltf["animations"]:
        for s in a["samplers"]:
            used_a.add(s["input"])
            used_a.add(s["output"])
    for sk in gltf.get("skins", []):
        if "inverseBindMatrices" in sk:
            used_a.add(sk["inverseBindMatrices"])
    keep_a = sorted(used_a)
    am = {old: new for new, old in enumerate(keep_a)}
    new_accessors = []
    for old in keep_a:
        acc = dict(gltf["accessors"][old])
        new_accessors.append(acc)
    for mesh in gltf["meshes"]:
        for p in mesh["primitives"]:
            p["attributes"] = {k: am[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = am[p["indices"]]
    for a in gltf["animations"]:
        for s in a["samplers"]:
            s["input"] = am[s["input"]]
            s["output"] = am[s["output"]]
    for sk in gltf.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = am[sk["inverseBindMatrices"]]
    used_v = set()
    for acc in new_accessors:
        if "bufferView" in acc:
            used_v.add(acc["bufferView"])
    for im in gltf.get("images", []):
        if "bufferView" in im:
            used_v.add(im["bufferView"])
    keep_v = sorted(used_v)
    vm = {old: new for new, old in enumerate(keep_v)}
    new_blob = bytearray()
    new_views = []
    for old in keep_v:
        bv = dict(gltf["bufferViews"][old])
        start = bv.get("byteOffset", 0)
        length = bv["byteLength"]
        while len(new_blob) % 4:
            new_blob.append(0)
        bv["byteOffset"] = len(new_blob)
        new_blob.extend(blob[start:start + length])
        new_views.append(bv)
    for acc in new_accessors:
        if "bufferView" in acc:
            acc["bufferView"] = vm[acc["bufferView"]]
    for im in gltf.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = vm[im["bufferView"]]
    gltf["accessors"] = new_accessors
    gltf["bufferViews"] = new_views
    gltf["buffers"][0]["byteLength"] = len(new_blob) + ((4 - len(new_blob) % 4) % 4)
    return new_blob


# Names the game binds. A replacement glb that renames these will load and then
# silently lose the turret, the sensor, the gun or the wings.
REQUIRED_ANIMS = (
    "CoilgunFire", "CoilgunCharge",
    "MainDriveIdle", "MainDriveLow", "MainDriveMedium", "MainDriveFull",
    "OMSBurn", "RadiatorStow", "RadiatorDeploy",
    "TurretTrack", "SensorTrack", "LaserFire", "VLSDoorOpen",
)
REQUIRED_NODES = (
    "Turret_01_Yaw", "Turret_01_Pitch", "Turret_01_LaserBeam",
    "Turret_02_Yaw", "Turret_02_Pitch", "Turret_02_LaserBeam",
    "Turret_03_Yaw", "Turret_03_Pitch", "Turret_03_LaserBeam",
    "Sensor_01_Yaw", "Sensor_01_Pitch",
    "Coilgun_A093_Barrel_Recoil", "Coilgun_MuzzleFlash", "Coilgun_MuzzleFlare",
    "Coilgun_Projectile", "MainDrive_A001-A004_Plume", "Target_Track_Point",
)
# Ammo-feed hoses. Eight bones per rotary turret, skinned, posed from TurretTrack.
# The game does not play that clip; it aims the turret and derives the bones from
# the same angles, so a drop-in that renames a bone freezes the hose.
FLEX_NODES = tuple(
    "RT%02d_Flex_%02d" % (turret, seg)
    for turret in range(1, 5)
    for seg in range(8)
)
# Domes sit on the pitch node, so they turn with the head. A dome left on the base
# would stay behind when the turret aims.
DOME_NODES = tuple("RotaryTurret_%02d_Dome_Geo" % turret for turret in range(1, 5))
# The game scales these itself. OMSBurn is not played. A010's radial is part of
# that set: a drop-in that omits it would hide the fore-bottom bell with no error.
OMS_PLUME_NODES = tuple(
    "%s_Plume_%s" % (station, kind)
    for station in (
        "OMS_A006_Aft_Bottom", "OMS_A007_Aft_Port", "OMS_A008_Aft_Stbd", "OMS_A009_Aft_Top",
        "OMS_A010_Fore_Bottom", "OMS_A011_Fore_Port", "OMS_A012_Fore_Stbd", "OMS_A013_Fore_Top",
    )
    for kind in ("Radial", "TangentA", "TangentB")
)


def check_contract(gltf):
    nodes = gltf["nodes"]
    names = {n.get("name") for n in nodes}
    anims = {a.get("name") for a in gltf.get("animations", [])}
    missing_n = [n for n in REQUIRED_NODES if n not in names]
    missing_n += [n for n in OMS_PLUME_NODES if n not in names]
    missing_n += [n for n in FLEX_NODES if n not in names]
    missing_n += [n for n in DOME_NODES if n not in names]
    missing_a = [a for a in REQUIRED_ANIMS if a not in anims]
    coils = [n for n in names if n and n.startswith("Coilgun_Coil_") and n.endswith("_Glow")]
    rads = [n for n in names if n and n.startswith("Radiator_") and n.endswith("_Geo")]
    if not coils:
        missing_n.append("Coilgun_Coil_*_Glow")
    if len(rads) < 8:
        missing_n.append("Radiator_*_Geo (found %d)" % len(rads))
    if len(nodes) < 331:
        missing_n.append("node count %d, v18d hull has 331" % len(nodes))
    channels = sum(len(a.get("channels", [])) for a in gltf.get("animations", []))
    if channels != 270:
        missing_n.append("channel count %d, v18d hull has 270" % channels)
    if nodes[gltf["scenes"][gltf.get("scene", 0)]["nodes"][0]].get("name") != "arbiter-TDC":
        missing_n.append("root is not arbiter-TDC")
    parent = {}
    for n in nodes:
        for c in n.get("children", []):
            parent[c] = n.get("name")
    name_i = {n.get("name"): i for i, n in enumerate(nodes)}
    # v18d adds the secondary-mirror disc and the aperture glow on each laser head.
    # They have to stay on the pitch node the aim code already turns.
    for turret in (1, 2, 3):
        for kind in ("SecondaryMirrorFace_Geo", "ApertureGlowRing_Geo"):
            nm = "Turret_%02d_%s" % (turret, kind)
            want = "Turret_%02d_Pitch" % turret
            if nm not in name_i:
                missing_n.append(nm)
                continue
            if parent.get(name_i[nm]) != want:
                missing_n.append("%s parent is %s, want %s" % (nm, parent.get(name_i[nm]), want))
    for dome in DOME_NODES:
        turret = dome.split("_")[1]
        want = "RotaryTurret_%s_Pitch" % turret
        if dome in name_i and parent.get(name_i[dome]) != want:
            missing_n.append("%s parent is %s, want %s" % (dome, parent.get(name_i[dome]), want))
    tt = next((a for a in gltf.get("animations", []) if a.get("name") == "TurretTrack"), None)
    if tt is not None:
        targeted = {nodes[ch["target"]["node"]].get("name") for ch in tt["channels"]}
        flex_missing = [n for n in FLEX_NODES if n not in targeted]
        if flex_missing:
            missing_n.append("TurretTrack missing flex %s" % flex_missing)
    skins = gltf.get("skins", [])
    joint_names = []
    for sk in skins:
        joint_names.extend(nodes[j].get("name") for j in sk.get("joints", []))
    flex_unskinned = [n for n in FLEX_NODES if n not in joint_names]
    if flex_unskinned:
        missing_n.append("flex bones not in a skin %s" % flex_unskinned)
    if missing_n or missing_a:
        raise SystemExit("replacement glb is missing nodes %s animations %s" % (missing_n, missing_a))
    # Housings stay double-sided: a one-sided shell looks open. The laser balls are the
    # exception, applied after the mesh merge (single_side_laser_apertures).
    for m in gltf["materials"]:
        m["doubleSided"] = True
        if m.get("name") in (
            "MAT_FEL_PrimaryMirror_TRUE.001",
            "MAT_FEL_SecondaryMirror.001",
            "MAT_FEL_BowlLiner_PolishedCopper.001",
        ):
            m.setdefault("pbrMetallicRoughness", {})["metallicFactor"] = 1.0
    return len(coils), len(rads)


# The closed laser balls, the bowls and the mirrors face outward. v18d also added a reversed
# twin 0.3 mm behind interior faces that used to show through the lip. Double-sided drawing
# puts those two surfaces on top of each other. These meshes are single-sided; every other
# housing stays double-sided. The clone happens after materials are merged, because the
# merge fingerprints on colour and would fold a single-sided copy back into the shared one.
_APERTURE_SINGLE = (
    "Turret_01_Pitch_Geo", "Turret_02_Pitch_Geo", "Turret_03_Pitch_Geo",
    "Turret_01_SecondaryMirrorFace_Geo", "Turret_02_SecondaryMirrorFace_Geo",
    "Turret_03_SecondaryMirrorFace_Geo",
    "Turret_01_ApertureGlowRing_Geo", "Turret_02_ApertureGlowRing_Geo",
    "Turret_03_ApertureGlowRing_Geo",
)


def single_side_laser_apertures(gltf):
    clones = {}

    def single(mi):
        if mi not in clones:
            src = gltf["materials"][mi]
            dup = json.loads(json.dumps(src))
            dup["doubleSided"] = False
            dup["name"] = src.get("name", "mat") + ".__cullback"
            clones[mi] = len(gltf["materials"])
            gltf["materials"].append(dup)
        return clones[mi]

    for n in gltf["nodes"]:
        if n.get("name") not in _APERTURE_SINGLE or "mesh" not in n:
            continue
        for prim in gltf["meshes"][n["mesh"]]["primitives"]:
            if "material" in prim:
                prim["material"] = single(prim["material"])
    return len(clones)


def main(src, dst):
    gltf, blob = load_glb(src)
    coils, rads = check_contract(gltf)
    painted = paint_named_colors(gltf)
    capped = cap_emissive_strength(gltf)
    nodes = gltf["nodes"]
    anim = set()
    for a in gltf["animations"]:
        for ch in a["channels"]:
            anim.add(ch["target"]["node"])
    root = gltf["scenes"][gltf.get("scene", 0)]["nodes"][0]
    children = list(nodes[root].get("children", []))
    new_children = []
    replaced = 0
    tris_out = 0
    for ci in children:
        n = nodes[ci]
        if "mesh" not in n or ci in anim or n.get("children"):
            new_children.append(ci)
            continue
        made = split_node(gltf, blob, ci)
        if not made:
            new_children.append(ci)
            continue
        new_children.extend(made)
        replaced += 1
        for ni in made:
            mesh = gltf["meshes"][nodes[ni]["mesh"]]
            for p in mesh["primitives"]:
                tris_out += gltf["accessors"][p["indices"]]["count"] // 3
    nodes[root]["children"] = new_children
    live = reachable(gltf)
    canon = canonical_materials(gltf)
    before, after = merge_mesh_prims(gltf, blob, live, canon)
    dropped = merge_fittings(gltf, blob, root)
    smoothed, kept_normals = smooth_curved_normals(gltf, blob)
    gone = prune_unreachable(gltf)
    blob = compact_buffers(gltf, blob)
    sided = single_side_laser_apertures(gltf)
    save_glb(dst, gltf, blob)
    # Surfaces Godot will draw: one per primitive on a scene mesh.
    prims = 0
    tris = 0
    for n in gltf["nodes"]:
        if "mesh" not in n:
            continue
        for p in gltf["meshes"][n["mesh"]]["primitives"]:
            prims += 1
            tris += _tri_count(gltf, p)
    names = [n.get("name") for n in gltf["nodes"]]
    missing = []
    for a in gltf["animations"]:
        for ch in a["channels"]:
            nm = gltf["nodes"][ch["target"]["node"]].get("name")
            if nm not in names:
                missing.append((a["name"], nm))
    print("painted %d materials still at default white; capped %d emissive strengths; smoothed %d flat meshes, left %d with weighted normals" % (painted, capped, smoothed, kept_normals))
    print("replaced %d static root meshes; section triangles %d" % (replaced, tris_out))
    print("primitives %d -> %d on live meshes; fittings absorbed %d nodes; pruned %d" % (before, after, dropped, gone))
    print("scene primitives", prims, "triangles", tris)
    print("animations", len(gltf["animations"]), "missing targets", missing, "coils", coils, "radiator geos", rads)
    print("nodes", len(gltf["nodes"]), "skins", len(gltf.get("skins", [])), "aperture materials single-sided", sided)
    print("wrote", dst, os.path.getsize(dst))


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else SRC_DEFAULT
    dst = sys.argv[2] if len(sys.argv) > 2 else DST_DEFAULT
    main(src, dst)
