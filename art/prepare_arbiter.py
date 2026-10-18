"""Turn the authored Arbiter TDC v8 glTF into the Lance's runtime model.

The file is already in game axes (nose -Z, +Y up, +X starboard) and carries the
13 animations. This only splits the static root meshes into nose / body / aft
pieces so the armour view can tint them the same way it tints the Dagger
(mesh names starting N_ / B_ / A_). Animated nodes are not renamed and their
meshes are not rewritten, so every clip still finds its targets.

Cuts match the Dagger's section fractions on this hull: the armoured nose
(forward of z = -42) and the engineering aft (aft of z = 52).

Run:  python art/prepare_arbiter.py [src.glb] [dst.glb]
"""
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_DEFAULT = os.path.join(HERE, "source", "arbiter-TDC_v8.glb")
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


def main(src, dst):
    gltf, blob = load_glb(src)
    nodes = gltf["nodes"]
    anim = set()
    for a in gltf["animations"]:
        for ch in a["channels"]:
            anim.add(ch["target"]["node"])
    root = gltf["scenes"][gltf.get("scene", 0)]["nodes"][0]
    if anim & set(gltf["nodes"][root].get("children", [])):
        # a direct child being animated is fine; we only rewrite unanimated mesh children
        pass
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
    gltf["buffers"][0]["byteLength"] = len(blob) + ((4 - len(blob) % 4) % 4)
    save_glb(dst, gltf, blob)
    print("replaced %d static root meshes; section triangles %d" % (replaced, tris_out))
    print("wrote", dst, os.path.getsize(dst))
    # sanity: animations still name nodes that exist
    names = {n.get("name") for n in gltf["nodes"]}
    missing = []
    for a in gltf["animations"]:
        for ch in a["channels"]:
            nm = gltf["nodes"][ch["target"]["node"]].get("name")
            if nm not in names:
                missing.append(nm)
    print("animations", len(gltf["animations"]), "missing targets", missing)


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else SRC_DEFAULT
    dst = sys.argv[2] if len(sys.argv) > 2 else DST_DEFAULT
    main(src, dst)
