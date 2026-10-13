"""Build the TDC demo ship models in Blender and export them as glTF for Godot.

Run headless:   blender --background --python art/build_ships.py
or with the bpy module:   python art/build_ships.py

Everything is generated from numbers here (no hand modelling), so the models stay in step with the game rules:
turret angles and OMS stations match the sim and ship_model.gd. Open the exported .glb (or save a .blend with
--blend) in Blender to tweak by hand.

Axes: the ship's axis is Blender +Y with the nose at +Y; +X is the ship's right, +Z its top. The glTF exporter turns
that into Godot's convention (nose along -Z, +X right, +Y up).

Named nodes the game looks for:
  Turret0..2 (pivot, emitter along local +Y)  Muzzle0..2      RadPivot*/Rad* (panel grows along local +X)
  OMS_F0..3, OMS_A0..3 (radial nozzles)       OMSAX_F*, OMSAX_A* (axial nozzles)
  Gun_Coil, Gun_Rail                          Sys0..5          Nozzle (main drive exit)
  Mesh names start N_, B_ or A_ for the nose, body and aft sections (armour view tints them).
Before export, static parts are joined by section and material (merge_static) to keep draw calls down.
"""
import math
import os
import re
import sys

import bpy  # noqa: F401  (must come first: it makes bmesh and mathutils importable)
import bmesh
from mathutils import Matrix, Vector

TAU = 2 * math.pi
TURRET_ANGLES = [math.radians(45), math.radians(135), math.radians(315)]     # must match kTurretAngle in the sim
OMS_FWD, OMS_AFT = 0.10, 0.765                                           # must match ship_model.gd
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "game", "models")


# ---------------------------------------------------------------- scene and materials

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def lin(c):
    """Colours here are written as on screen (sRGB); Blender and glTF want linear values."""
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def material(name, color, rough=0.45, metal=0.3, emit=None, emit_strength=0.0):
    color = lin(color)
    emit = lin(emit) if emit else None
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color, 1.0)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit:
        p.inputs["Emission Color"].default_value = (*emit, 1.0)
        p.inputs["Emission Strength"].default_value = emit_strength
    return m


def mesh_object(name, verts, faces, mat, parent=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    if smooth:
        for poly in me.polygons:
            poly.use_smooth = True
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


def empty(name, loc, parent=None):
    ob = bpy.data.objects.new(name, None)
    ob.empty_display_size = 0.5
    ob.location = loc
    bpy.context.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    return ob


# ---------------------------------------------------------------- geometry helpers

def fillet(points, radius, steps=6):
    """Round every interior corner of a 2D polyline [(a, b), ...] with a quadratic arc of up to `radius`."""
    out = [points[0]]
    for i in range(1, len(points) - 1):
        a, b, c = (Vector(points[i - 1]), Vector(points[i]), Vector(points[i + 1]))
        d1, d2 = (a - b), (c - b)
        if d1.length < 1e-9 or d2.length < 1e-9:
            continue
        t = min(radius, d1.length * 0.45, d2.length * 0.45)
        p0, p2 = b + d1.normalized() * t, b + d2.normalized() * t
        for k in range(steps + 1):
            s = k / steps
            q = p0 * (1 - s) ** 2 + b * 2 * s * (1 - s) + p2 * s ** 2
            out.append((q.x, q.y))
    out.append(points[-1])
    return out


def revolve(name, profile, mat, parent=None, seg=72, axis_y=True):
    """Surface of revolution about the Blender Y axis from (y, radius) points; closed where the radius is 0."""
    verts, faces = [], []
    n = len(profile)
    for (y, r) in profile:
        for k in range(seg):
            t = TAU * k / seg
            verts.append((r * math.cos(t), y, r * math.sin(t)))
    for i in range(n - 1):
        for k in range(seg):
            a = i * seg + k
            b = i * seg + (k + 1) % seg
            faces.append((a, b, b + seg, a + seg))
    ob = mesh_object(name, verts, faces, mat, parent)
    weld(ob)
    return ob


def weld(ob, dist=1e-4):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def frame(y, angle):
    """Unit vectors at a point on the hull: radial out, around the hull, and along the axis (nose)."""
    out = Vector((math.cos(angle), 0, math.sin(angle)))
    around = Vector((-math.sin(angle), 0, math.cos(angle)))
    return out, around, Vector((0, 1, 0))


def hull_patch(name, y0, angle0, hull_r, profile_fn, foot, mat, parent=None, rings=24, seg=48, stretch=1.0, band=None):
    """A smooth bump that grows out of the hull cylinder: height profile_fn(rho / foot) at distance rho from its
    centre, wrapped onto the curved hull so its edge melts into the skin with no seam."""
    verts, faces = [], []
    for i in range(rings + 1):
        rho = foot * i / rings
        h = profile_fn(i / rings)
        for k in range(seg):
            phi = TAU * k / seg
            du, dw = rho * math.sin(phi) * stretch, rho * math.cos(phi)       # along the axis (stretched), around the hull
            th = angle0 + dw / hull_r
            rr = hull_r + h - 0.02
            verts.append((rr * math.cos(th), y0 + du, rr * math.sin(th)))
    marked = []
    for i in range(rings):
        for k in range(seg):
            a, b = i * seg + k, i * seg + (k + 1) % seg
            faces.append((a, a + seg, b + seg, b))
            marked.append(band is not None and band[0] <= (i + 0.5) / rings <= band[1])
    ob = mesh_object(name, verts, faces, mat, parent)
    if band is not None:                       # a painted marking ring: faces between two radii get the band material
        ob.data.materials.append(band[2])
        for poly, m in zip(ob.data.polygons, marked):
            poly.material_index = 1 if m else 0
    weld(ob)
    return ob


def track(d):
    """Rotation taking local +Z onto direction d."""
    d = Vector(d).normalized()
    return d.to_track_quat("Z", "X" if abs(d.z) > 0.99 else "Y")


def cylinder(name, a, b, radius, mat, parent=None, seg=24, cap=True):
    """A round rod from a to b."""
    a, b = Vector(a), Vector(b)
    d = b - a
    q = track(d)
    verts, faces = [], []
    for z in (0.0, d.length):
        for k in range(seg):
            t = TAU * k / seg
            verts.append(Vector((radius * math.cos(t), radius * math.sin(t), z)))
    for k in range(seg):
        k2 = (k + 1) % seg
        faces.append((k, k2, seg + k2, seg + k))
    if cap:
        faces.append(tuple(range(seg - 1, -1, -1)))
        faces.append(tuple(range(seg, 2 * seg)))
    verts = [a + q @ v for v in verts]
    return mesh_object(name, verts, faces, mat, parent)


def torus(name, center, axis, major, minor, mat, parent=None, seg=48, seg2=12):
    q = track(axis)
    verts, faces = [], []
    for i in range(seg):
        u = TAU * i / seg
        for j in range(seg2):
            v = TAU * j / seg2
            p = Vector(((major + minor * math.cos(v)) * math.cos(u), (major + minor * math.cos(v)) * math.sin(u), minor * math.sin(v)))
            verts.append(Vector(center) + q @ p)
    for i in range(seg):
        for j in range(seg2):
            a = i * seg2 + j
            b = ((i + 1) % seg) * seg2 + j
            c = ((i + 1) % seg) * seg2 + (j + 1) % seg2
            d = i * seg2 + (j + 1) % seg2
            faces.append((a, b, c, d))
    return mesh_object(name, verts, faces, mat, parent)


def box(name, size, mat, parent=None, bevel=0.0):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0, calc_uvs=True)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    if parent:
        ob.parent = parent
    if bevel > 0:
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = "ANGLE"
    return ob


def beam_director(k, piv, R, m_shell, m_mirror, m_dark, m_rim, axle_out=None):
    """Laser turret head: a beam director pointing along the pivot's local +Y. A closed, round housing (a sphere of
    radius R) with its front cut flat; the aperture sits in that flat face, with a slightly concave primary mirror
    set back inside and a small secondary mirror held on the beam axis by three spider vanes. Stub axles along local
    Z reach the gimbal's trunnions (out to axle_out, default just outside the sphere). Returns the muzzle point
    (centre of the front face, local). Names the game relies on: B_dome{k} (housing; scorched when knocked out)
    and Lens{k} (primary mirror)."""
    front = 0.6 * R                                  # the flat face: the sphere is cut here, 0.8 R across
    cut = math.sqrt(R * R - front * front)
    ap = 0.66 * R                                    # aperture radius
    depth = front - 0.32 * R                         # primary mirror set back from the face
    shell = []
    t0 = math.acos(front / R)
    for i in range(25):                              # round back, from the rear pole to the cut
        t = math.pi - (math.pi - t0) * i / 24
        shell.append((R * math.cos(t), R * math.sin(t)))
    shell += [(front, ap + 0.03 * R), (front - 0.02 * R, ap), (depth - 0.02 * R, ap)]
    revolve(f"B_dome{k}", shell, m_shell, piv, seg=72)
    torus(f"B_rim{k}", (0, front, 0), (0, 1, 0), (ap + cut) / 2, 0.03 * R, m_rim, piv, seg=72, seg2=10)
    revolve(f"Lens{k}", [(depth - 0.07 * R, 0.0), (depth - 0.03 * R, 0.45 * ap), (depth, ap)], m_mirror, piv, seg=72)
    sec_y = front - 0.08 * R
    revolve(f"B_secondary{k}", [(sec_y - 0.06 * R, 0.0), (sec_y - 0.06 * R, 0.15 * R), (sec_y, 0.15 * R), (sec_y, 0.0)], m_dark, piv, seg=32)
    for i in range(3):
        t = math.radians(90 + 120 * i)
        d = Vector((math.cos(t), 0, math.sin(t)))
        cylinder(f"B_spider{k}_{i}", d * 0.14 * R + Vector((0, sec_y - 0.03 * R, 0)), d * ap + Vector((0, sec_y - 0.03 * R, 0)), 0.016 * R, m_dark, piv, seg=8)
    reach = axle_out if axle_out is not None else 1.06 * R
    for side in (-1, 1):
        cylinder(f"B_axle{k}_{side}", Vector((0, 0, side * 0.9 * R)), Vector((0, 0, side * reach)), 0.14 * R, m_dark, piv, seg=24)
    return Vector((0, front, 0))


def sphere(name, center, radius, mat, parent=None, seg=48, rings=24):
    verts, faces = [], []
    for i in range(rings + 1):
        v = math.pi * i / rings
        for k in range(seg):
            u = TAU * k / seg
            verts.append((radius * math.sin(v) * math.cos(u), radius * math.sin(v) * math.sin(u), radius * math.cos(v)))
    for i in range(rings):
        for k in range(seg):
            a, b = i * seg + k, i * seg + (k + 1) % seg
            faces.append((a, b, b + seg, a + seg))
    ob = mesh_object(name, verts, faces, mat, parent)
    weld(ob)
    ob.location = center
    return ob


# ---------------------------------------------------------------- the ship

def build(mars: bool):
    reset()
    L = 130.0 if mars else 160.0
    r = 0.026 * L
    yz = lambda x: L / 2 - x * L                 # fraction from the nose -> Blender Y
    hull_col = (0.66, 0.54, 0.44) if mars else (0.60, 0.63, 0.67)
    m_hull = [material(f"{s}_hull", hull_col, 0.5, 0.12) for s in ("N", "B", "A")]
    m_band = material("band", (0.10, 0.11, 0.13), 0.6, 0.4)
    m_dark = material("dark", (0.16, 0.17, 0.19), 0.5, 0.5)
    m_win = material("window", (0.05, 0.06, 0.08), 0.15, 0.2)
    m_truss = material("truss", (0.28, 0.29, 0.31), 0.45, 0.7)
    m_gold = material("marking", (0.86, 0.68, 0.16), 0.4, 0.2)
    m_dome = material("B_dome", (0.80, 0.82, 0.84) if not mars else (0.76, 0.66, 0.56), 0.25, 0.4)
    lens_c = (0.35, 0.65, 1.0) if not mars else (1.0, 0.55, 0.3)
    m_lens = material("lens", lens_c, 0.05, 0.0, emit=lens_c, emit_strength=4.0)
    m_mirror = material("mirror", (0.04, 0.045, 0.055), 0.04, 1.0, emit=lens_c, emit_strength=0.25)
    m_gun = material("B_gun", (0.60, 0.53, 0.40), 0.35, 0.7)
    m_noz = material("nozzle", (0.12, 0.12, 0.13), 0.4, 0.8)
    m_bell = material("A_bell", (0.35, 0.33, 0.32), 0.3, 0.9)
    m_rad = {
        "light": material("radiator_light", (0.78, 0.80, 0.82), 0.6, 0.15),
        "dark": material("radiator_dark", (0.06, 0.065, 0.075), 0.55, 0.2),
        "bronze": material("radiator_bronze", (0.50, 0.30, 0.18) if mars else (0.42, 0.33, 0.22), 0.5, 0.4),
    }

    # --- hull: nose bulb, then pressure modules and tanks on a thin spine, all one smooth profile per section
    spine = 0.8 * r

    def module(a, b, rad):
        e = 0.014 * L
        return [(yz(a), spine), (yz(a) - e * 0.25, rad * 0.9), (yz(a) - e, rad), (yz(b) + e, rad), (yz(b) + e * 0.25, rad * 0.9), (yz(b), spine)]

    nose = [(yz(0.0), 0.0), (yz(0.004), 0.55 * r), (yz(0.014), 0.86 * r), (yz(0.026), r), (yz(0.038), 0.86 * r), (yz(0.046), 0.5 * r)]
    nose += [(yz(0.05), 0.45 * r), (yz(0.06), spine)] + module(0.06, 0.17, r)[1:]
    revolve("N_hull", fillet(nose, 0.35 * r), m_hull[0])
    body = [(yz(0.17), spine)]
    for (a, b, k) in [(0.185, 0.31, 1.0), (0.325, 0.45, 1.0), (0.465, 0.62, 1.1), (0.632, 0.80, 1.2)]:
        body += module(a, b, r * k)
    body.append((yz(0.80), spine))
    revolve("B_hull", fillet(body, 0.3 * r), m_hull[1])
    aft = [(yz(0.80), 0.55 * r), (yz(0.955), 0.55 * r), (yz(0.958), 0.62 * r), (yz(0.966), 1.12 * r), (yz(0.975), 1.15 * r),
           (yz(0.983), 0.72 * r), (yz(0.99), 0.9 * r), (yz(1.0), 1.25 * r)]
    revolve("A_core", fillet(aft, 0.12 * r, 4), m_hull[2])
    revolve("A_bell", [(yz(0.985), 0.74 * r), (yz(1.0), 1.22 * r), (yz(1.0) - 0.01, 1.18 * r), (yz(0.987), 0.7 * r)], m_bell)

    # dark seams at each module's ends and a few window rows
    for (a, b, k) in [(0.06, 0.17, 1.0), (0.185, 0.31, 1.0), (0.325, 0.45, 1.0), (0.465, 0.62, 1.1), (0.632, 0.80, 1.2)]:
        for x in (a + 0.02, b - 0.02):
            sec = "N" if b <= 0.17 else "B"
            revolve(f"{sec}_seam", [(yz(x) + 0.12, r * k * 1.003), (yz(x) - 0.12, r * k * 1.003)], m_band, seg=96)
    for (x, ang, n) in [(0.11, 0.0, 3), (0.25, 0.0, 4), (0.38, 0.0, 4), (0.53, 0.0, 5), (0.70, math.pi, 4)]:
        rad = r * (1.2 if x > 0.62 else (1.1 if x > 0.465 else 1.0))
        for i in range(n):
            w = box(f"B_win", (0.28, 0.55, 0.32), m_win)
            th = ang + 0.0
            w.location = ((rad + 0.02) * math.cos(th), yz(x) - i * 1.4, (rad + 0.02) * math.sin(th))

    # --- open truss around the reactor core
    tr = 1.35 * r
    ya, yb = yz(0.80), yz(0.955)
    nlong, frames = 8, 5
    for k in range(nlong):
        t = TAU * k / nlong
        p = Vector((tr * math.cos(t), 0, tr * math.sin(t)))
        cylinder("A_truss", p + Vector((0, ya, 0)), p + Vector((0, yb, 0)), 0.11, m_truss, seg=10)
    for f in range(frames + 1):
        y = ya + (yb - ya) * f / frames
        torus("A_truss", (0, y, 0), (0, 1, 0), tr, 0.1, m_truss, seg=48, seg2=8)
        if f < frames:
            y2 = ya + (yb - ya) * (f + 1) / frames
            for k in range(nlong):
                t0, t1 = TAU * k / nlong, TAU * (k + 1) / nlong
                s = (k + f) % 2 == 0
                p0 = Vector((tr * math.cos(t0), y if s else y2, tr * math.sin(t0)))
                p1 = Vector((tr * math.cos(t1), y2 if s else y, tr * math.sin(t1)))
                cylinder("A_truss", p0, p1, 0.07, m_truss, seg=8)
    # struts joining the truss to the hull
    for k in range(4):
        t = TAU * k / 4 + math.pi / 4
        cylinder("A_truss", (1.15 * r * math.cos(t), ya + 0.5, 1.15 * r * math.sin(t)), (tr * math.cos(t), ya - 1.0, tr * math.sin(t)), 0.15, m_truss, seg=10)

    # --- radiators: pairs of panels in planes containing the axis (x, angle, span, width, kind)
    rads = [(0.22, 0.0, 0.17, 0.07, "light"), (0.27, math.pi / 2, 0.14, 0.035, "dark"),
            (0.57, math.pi / 2, 0.40, 0.085, "dark"), (0.66, math.pi / 2 + 0.95, 0.30, 0.09, "bronze")]
    ri = 0
    for (x, ang, span, width, kind) in rads:
        for side in (0, 1):
            a = ang + side * math.pi
            piv = empty(f"RadPivot{ri}", (0, yz(x), 0))
            piv.rotation_euler = (0, -a, 0)        # turn local +X out to angle a (Blender rotates X toward -Z about +Y)
            panel = box(f"Rad{ri}_{kind}", (span * L, width * L, 0.35), m_rad[kind], piv, bevel=0.05)
            # move the mesh so its origin is the inner edge: scaling local X folds it against the hull
            for v in panel.data.vertices:
                v.co.x += span * L / 2 + 0.8 * r
            ri += 1

    # --- laser turrets: barbette rising smoothly out of the hull, marking ring, rotating dome with an emitter
    hr = r * 1.0
    for k, a in enumerate(TURRET_ANGLES):
        y0 = yz(0.40)
        out, _, _ = frame(y0, a)
        foot = 0.62 * r
        bar_h = 0.34 * r

        def barbette(s):                      # s: 0 at the centre, 1 at the foot
            core = 0.40 / 0.62                # flat-topped drum out to here, then a smooth fillet down to the skin
            if s <= core:
                return bar_h
            u = (s - core) / (1 - core)
            return bar_h * (1 - u) ** 2 * (1 + 2 * u) * (1 - u * 0.0)   # smoothstep-like fall, tangent to the hull
        hull_patch(f"B_barbette{k}", y0, a, hr, barbette, foot, m_hull[1], rings=48, seg=64, band=(0.69, 0.76, m_gold))
        # two-axis gimbal: the fork turns about the mount axis (TurretBase, local +Y outward), the dome and emitter
        # tilt on the fork's pins (Turret, about its local Z = along the ship)
        base = empty(f"TurretBase{k}", out * (hr + bar_h) + Vector((0, y0, 0)))
        along = Vector((0, 1, 0))
        base.rotation_euler = Matrix((out.cross(along), out, along)).transposed().to_euler()
        for side in (-1, 1):
            box(f"B_fork{k}_{side}", (0.14 * r, 0.30 * r, 0.07 * r), m_dark, base, bevel=0.02).location = (0, 0.02 * r, side * 0.335 * r)
            cylinder(f"B_pin{k}_{side}", Vector((0, 0, side * 0.29 * r)), Vector((0, 0, side * 0.38 * r)), 0.07 * r, m_gold, seg=24, parent=base)
        piv = empty(f"Turret{k}", (0, 0, 0), base)
        muzzle = beam_director(k, piv, 0.26 * r, m_dome, m_mirror, m_dark, m_gold, axle_out=0.31 * r)
        empty(f"Muzzle{k}", muzzle, piv)

    # --- OMS: low blisters that melt into the hull at a forward and an aft station
    for (st, tag) in [(OMS_FWD, "F"), (OMS_AFT, "A")]:
        y0 = yz(st)
        rad = r * (1.0 if st < 0.17 else 1.2)
        sec = "N" if tag == "F" else "B"
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            out, around, along = frame(y0, a)
            foot = 0.45 * r
            hb = 0.2 * r
            stretch = 1.8                     # a low teardrop fairing, longer along the hull than across it
            hull_patch(f"{sec}_oms{tag}{k}", y0, a, rad, lambda s: hb * (1 - s * s) ** 1.6, foot, m_hull[0 if tag == "F" else 1], rings=28, seg=56, stretch=stretch)
            # nozzle ports, flush: a dark disc on top facing out, one on the end facing along the axis
            top = out * (rad + hb) + Vector((0, y0, 0))
            cylinder(f"{sec}_port", top - out * 0.08, top + out * 0.02, 0.09 * r, m_noz, seg=24)
            axd = along if tag == "F" else -along
            endp = out * (rad + hb * 0.55) + Vector((0, y0, 0)) + axd * foot * stretch * 0.55
            cylinder(f"{sec}_port", endp - axd * 0.08, endp + axd * 0.02, 0.07 * r, m_noz, seg=24)
            empty(f"OMS_{tag}{k}", top + out * 0.02)
            empty(f"OMSAX_{tag}{k}", endp + axd * 0.02)

    # --- spinal guns under the belly, muzzle just aft of the sensor bulb
    gy = -1.45 * r
    coil = empty("Gun_Coil", (0, 0, 0))
    cylinder("B_coil_barrel", (0, yz(0.07), gy), (0, yz(0.74), gy), 0.17 * r, m_gun, coil, seg=32)
    x = 0.09
    while x < 0.72:
        torus("B_coil_stage", (0, yz(x), gy), (0, 1, 0), 0.3 * r, 0.06 * r, m_gun, coil, seg=40, seg2=10)
        x += 0.035
    rail = empty("Gun_Rail", (0, 0, 0))
    for sx in (-0.22, 0.22):
        b = box("B_rail", (0.09 * r, (0.70 - 0.08) * L / 2, 0.09 * r), m_gun, rail, bevel=0.03)
        b.location = (sx * r, (yz(0.08) + yz(0.70)) / 2, gy)
    # barrel ends, for the firing effect: breech aft, muzzle forward (both guns share the line)
    empty("Gun_Breech", (0, yz(0.74), gy))
    empty("Gun_Muzzle", (0, yz(0.07), gy))
    for g in (coil, rail):
        for xp in (0.2, 0.35, 0.5, 0.65):
            cylinder("B_pylon", (0, yz(xp), -0.9 * r), (0, yz(xp), gy), 0.08 * r, m_gun, g, seg=12)

    # --- reference points for the game
    for i, p in enumerate([(0, yz(0.97), 0), (0, yz(0.40), 1.5 * r), (0, yz(0.40), gy), (0, yz(0.02), 0),
                           (0, yz(0.57), 4.0 * r), (0, yz(0.25), 0)]):
        empty(f"Sys{i}", p)
    empty("Nozzle", (0, yz(1.0), 0))

    # smooth the low-poly helpers
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            for poly in ob.data.polygons:
                poly.use_smooth = True
            if ob.name.startswith(("Rad", "B_rail", "B_win")):
                for poly in ob.data.polygons:
                    poly.use_smooth = False
    return L


# Parts the game moves, toggles or finds by name (ship_model.gd): never merged into anything.
KEEP_SUBTREES = ("RadPivot",)                           # radiator wings fold and glow: all under them stays as is
KEEP_NAMES = ("Lens", "B_dome", "Muzzle", "Gun_Breech", "Gun_Muzzle", "OMS_", "OMSAX_", "Nozzle", "Sys")
GUN_HOLDERS = ("Gun_Coil", "Gun_Rail")                  # one gun is freed whole at runtime: merge only within it
TURRET_PIVOT = re.compile(r"^(TurretBase|Turret)(\d+)$")  # gimbal pivots: merge only their direct children


def merge_static():
    """Join the static mesh parts into one object per (section, material) to cut draw calls.

    Godot draws every surface of every MeshInstance separately in each pass (depth prepass, opaque, two shadow
    cascades, the EO sensor view), so a ship of ~200 small parts cost ~850 draw calls a frame. The game only cares
    about the section prefix (N_/B_/A_: the armour view tints by section) and the material of each surface, so parts
    that share both can be one mesh. Joined objects are named <section>_hull_<material>. Parts that move stay with
    what moves them: a spinal gun's parts join under their gun node (<section>_coil_/_rail_...), and a turret's
    parts join under their own gimbal pivot (<section>mount<k>_... under TurretBase<k>, <section>head<k>_... under
    Turret<k>; parts without a section prefix keep none, so the armour view still leaves them untinted). Lens<k>,
    B_dome<k> and Muzzle<k> stay their own nodes (the game hides the lens and scorches the dome of a dead turret),
    and radiator wings are left alone. A part with several materials joins the group of its first material and
    brings its other surfaces along. Joining keeps world positions, the active part's parent, and normals
    (vertices of different parts are not welded)."""
    def holder(ob):
        """Where a part may be merged: None (hull), a gun or turret pivot name, or "keep" (leave it alone)."""
        if ob.parent is not None and TURRET_PIVOT.match(ob.parent.name):
            return ob.parent.name
        p = ob.parent
        while p is not None:
            if p.name.startswith(KEEP_SUBTREES) or TURRET_PIVOT.match(p.name):
                return "keep"                           # nested deeper inside a pivot: not expected, leave it
            if p.name in GUN_HOLDERS:
                return p.name
            p = p.parent
        return None

    groups = {}
    for ob in list(bpy.data.objects):
        if ob.type != "MESH" or ob.children or not ob.data.materials or ob.name.startswith(KEEP_NAMES):
            continue
        h = holder(ob)
        if h == "keep":
            continue
        sec = ob.name[:2] if ob.name[:2] in ("N_", "B_", "A_") else ""
        if sec == "" and not (h and TURRET_PIVOT.match(h)):
            continue                                    # unsectioned hull parts are not tinted: leave them as they are
        groups.setdefault((h, sec, ob.data.materials[0].name), []).append(ob)
    for (h, sec, mat), obs in groups.items():
        if len(obs) < 2:
            continue
        for ob in obs:                                  # join drops the modifiers (bevels) of all but one: apply them
            if ob.modifiers:
                with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
                    for m in list(ob.modifiers):
                        bpy.ops.object.modifier_apply(modifier=m.name)
        with bpy.context.temp_override(active_object=obs[0], object=obs[0], selected_objects=obs, selected_editable_objects=obs):
            bpy.ops.object.join()
        t = TURRET_PIVOT.match(h) if h else None
        part = "hull" if h is None else (("mount" if t.group(1) == "TurretBase" else "head") + t.group(2) if t else h[4:].lower())
        obs[0].name = f"{sec}{part}_{mat}".replace(" ", "_").replace("|", "").replace("/", "_")[:60]
        obs[0].data.name = obs[0].name


def export(path, blend=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    merge_static()
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True,
                              export_extras=False, export_cameras=False, export_lights=False)
    if blend:
        bpy.ops.wm.save_as_mainfile(filepath=blend)


if __name__ == "__main__":
    save_blend = "--blend" in sys.argv
    # The Earth ship now comes from the Dagger concept model (art/import_dagger.py); pass --earth to rebuild the
    # generated Earth hull from this script instead.
    ships = (("earth", False), ("mars", True)) if "--earth" in sys.argv else (("mars", True),)
    for name, mars in ships:
        build(mars)
        export(os.path.join(OUT_DIR, f"{name}.glb"),
               os.path.join(os.path.dirname(os.path.abspath(__file__)), f"{name}.blend") if save_blend else None)
        print("wrote", name)
