"""Turn Rafael's Dagger concept model (art/source/Dagger_Earth_Destroyer.blend) into the game's Earth ship.

Run:  python art/import_dagger.py [--blend]     (needs the bpy package; or blender -b --python art/import_dagger.py)

The concept model keeps its hull, tanks, seams, missile doors, nose housing, radiator wings and drive. This script:
  * turns it to the game's axes (nose along +Y in Blender, which the glTF exporter makes -Z in Godot),
  * removes cameras and lights,
  * regroups each radiator wing under a RadPivot node whose local +X points outward, so the game can fold it,
  * makes the two side laser housings turrets 0 (starboard) and 1 (port) and adds a copy on top as turret 2,
    matching the sim's turret angles (0, 180, 90 degrees),
  * names the eight OMS pod nozzles, adds the coilgun and the reference points the game looks for
    (see build_ships.py for the list),
  * prefixes hull meshes N_/B_/A_ by section and joins small parts by material so the game draws a few dozen
    meshes instead of ~500,
  * exports game/models/earth.glb (and art/earth.blend with --blend).
The Mars ship still comes from build_ships.py.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import build_ships as B  # noqa: E402

SRC = os.path.join(HERE, "source", "Dagger_Earth_Destroyer.blend")
NOSE_LENGTH = 20.0           # sloped bow, from the crew shell's front (concept x = -83) to the start of the tip cap
NOSE_BLUNT = 9.0             # the ogive is cut this far short of a point, leaving a wide rounded tip
NOSE_TIP_EXTRA = 1.0         # how far the rounded cap stands out
HOUSING_SCALE = 0.67         # laser housings at two thirds of the concept's size
LENGTH = 83.0 + NOSE_LENGTH + NOSE_TIP_EXTRA + 89.6   # tip to nozzle exit = 193.6 m; ShipModel uses the same number
_OLD_LENGTH = 180.0               # the concept's overall length; ShipModel uses the same number


def ours(x_concept):
    """Concept X (nose at -X) to the game's Y (nose at +Y)."""
    return -x_concept


def reparent_keep(ob, parent):
    mw = ob.matrix_world.copy()
    ob.parent = parent
    ob.matrix_world = mw


def descendants(ob):
    out = []
    for c in ob.children:
        out.append(c)
        out += descendants(c)
    return out


def main(save_blend):
    bpy.ops.wm.open_mainfile(filepath=SRC, load_ui=False, use_scripts=False)
    for ob in list(bpy.data.objects):
        if ob.type in ("CAMERA", "LIGHT"):
            bpy.data.objects.remove(ob, do_unlink=True)
    root = bpy.data.objects["DAGGER | 2300 Earth destroyer"]
    root.rotation_euler = (0, 0, -math.pi / 2)        # concept (x, y, z) -> (y, -x, z): nose to +Y, concept +Y to +X
    bpy.context.view_layer.update()
    col = bpy.context.scene.collection

    def new_empty(name, mw):
        e = bpy.data.objects.new(name, None)
        col.objects.link(e)
        e.matrix_world = mw
        return e

    def radial_frame(p):
        out = Vector((p.x, 0, p.z)).normalized()
        along = Vector((0, 1, 0))
        z = out.cross(along)
        m = Matrix((out, along, z)).transposed().to_4x4()
        m.translation = p
        return m

    # --- radiator wings: one pivot per wing at its root, local +X outward
    ri = 0
    for i in range(1, 5):
        old = bpy.data.objects[f"Drive wing {i} | root assembly"]
        piv = new_empty(f"RadPivot{ri}", radial_frame(old.matrix_world.translation.copy()))
        for c in list(old.children):
            reparent_keep(c, piv)
        bpy.data.objects.remove(old, do_unlink=True)
        ri += 1
    # service and crew panels: group their parts by the side they stand on
    groups = {}
    for ob in list(bpy.data.objects):
        if ob.name.startswith(("Cold crew", "Hot service")):
            p = ob.matrix_world.translation
            ang = round(math.degrees(math.atan2(p.z, p.x)) / 90) % 4
            groups.setdefault((ob.name.split()[0], ang), []).append(ob)
    for (label, ang), obs in sorted(groups.items()):
        a = math.radians(ang * 90)
        p = Vector((9.5 * math.cos(a), ours(-42), 9.5 * math.sin(a)))
        piv = new_empty(f"RadPivot{ri}", radial_frame(p))
        for ob in obs:
            reparent_keep(ob, piv)
        ri += 1

    # --- a sloped bow: a smooth blunted ogive in place of the concept's short blunt bow, in the hull's paint, with
    # panel seams continuing the hull's (rings every 4 m, lengthwise lines every 30 degrees).
    for name in ("Armored tapered bow", "Rounded armored bow cap"):
        bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
    # the crew shell's front collar would leave a raised ring where the bow joins: take it off so the skin runs on
    for ob in list(bpy.data.objects):
        if ob.name.startswith("Crew protective shell end collar") and ob.matrix_world.translation.y > ours(-80):
            bpy.data.objects.remove(ob, do_unlink=True)
    m_bow = bpy.data.materials["Pale aerospace protective panels"]
    m_seam = bpy.data.materials["Shadow-shield casing"]
    base, R, Lb = ours(-83.0), 7.0, NOSE_LENGTH
    full = Lb + NOSE_BLUNT                                # the ogive is cut short where its radius is NOSE_TIP_R
    rho = (R * R + full * full) / (2 * R)                 # tangent ogive: the sides meet the hull with no kink

    def radius(d):                                        # d: distance forward of the base
        x = full - d                                      # distance from the (cut-off) point
        return math.sqrt(max(rho * rho - (full - x) ** 2, 0.0)) + R - rho
    prof = [(base + Lb * i / 30, radius(Lb * i / 30)) for i in range(31)]
    tip_r = prof[-1][1]
    for i in range(1, 9):                                 # a flattened rounded cap closes the blunt tip
        a = math.pi / 2 * i / 8
        prof.append((base + Lb + tip_r * 0.45 * math.sin(a), tip_r * math.cos(a)))
    prof[-1] = (prof[-1][0], 0.0)
    bow = B.revolve("N_bow", prof, m_bow, seg=64)     # smooth, like the hull it grows from (no facet breaks)
    # seams: rings every 4 m (12-sided, to sit flat on the plates) and lines along the plate edges
    d = 4.0
    while d < Lb - 1.0:
        rr = radius(d) * 1.004
        B.revolve("N_bow_seam", [(base + d + 0.05, rr), (base + d - 0.05, rr)], m_seam, seg=96)
        d += 4.0
    for k in range(12):
        t = 2 * math.pi * k / 12
        for (y0, r0), (y1, r1) in zip(prof[:30], prof[1:31]):
            a = Vector((r0 * 1.003 * math.cos(t), y0, r0 * 1.003 * math.sin(t)))
            b = Vector((r1 * 1.003 * math.cos(t), y1, r1 * 1.003 * math.sin(t)))
            B.cylinder("N_bow_edge", a, b, 0.03, m_seam, seg=6)

    # --- the game's parts, in game axes (nose +Y, +X right, +Z top)
    m_gun = B.material("B_gun", (0.60, 0.53, 0.40), 0.35, 0.7)

    # laser turrets: the concept's starboard and port housings, plus a copy of the starboard one turned to the top.
    # Each rotating part (shell, rim, bezel, aperture) goes under a Turret pivot whose local +Y is the aperture's
    # outward direction; the bearing, cradle and trunnions stay fixed to the hull.
    def assembly(name):
        r = bpy.data.objects[name]
        return r, [r] + descendants(r)

    star_root, star = assembly("Starboard beam director | gimbal assembly")
    port_root, port = assembly("Port beam director | gimbal assembly")
    # smaller housings: two thirds of the concept's size, shrunk toward the point where each meets the hull
    for root_ob, parts in ((star_root, star), (port_root, port)):
        c = root_ob.matrix_world.translation.copy()
        out = Vector((c.x, 0, c.z)).normalized()
        hinge = Vector((0, c.y, 0)) + out * 7.0
        shrink = Matrix.Translation(hinge) @ Matrix.Scale(HOUSING_SCALE, 4) @ Matrix.Translation(-hinge)
        worlds = [shrink @ o.matrix_world for o in parts]
        for o, mw in zip(parts, worlds):
            o.matrix_world = mw
            bpy.context.view_layer.update()
    turn = Matrix.Rotation(-math.pi / 2, 4, "Y")       # +X (starboard) to +Z (top), about the ship's axis
    dors = []
    for ob in star:
        c = ob.copy()
        if ob.data is not None:
            c.data = ob.data.copy()
        col.objects.link(c)
        dors.append(c)
    remap = {o: c for o, c in zip(star, dors)}
    for o, c in zip(star, dors):
        mw = turn @ o.matrix_world
        c.parent = remap.get(o.parent)
        c.matrix_world = mw
    bpy.context.view_layer.update()
    rotating = ("housing", "aperture rim", "inner bezel", "optical aperture")
    for k, (root_ob, parts) in enumerate([(star_root, star), (port_root, port), (dors[0], dors)]):
        centre = root_ob.matrix_world.translation.copy()
        out = Vector((centre.x, 0, centre.z)).normalized()
        along = Vector((0, 1, 0))
        m = Matrix((out.cross(along), out, along)).transposed().to_4x4()
        m.translation = centre
        piv = new_empty(f"Turret{k}", m)
        for ob in parts:
            if ob.type == "MESH" and any(w in ob.name for w in rotating):
                reparent_keep(ob, piv)
                if "housing" in ob.name:
                    ob.name = f"B_dome{k}"
                elif "optical aperture" in ob.name:
                    ob.name = f"Lens{k}"
        muz = new_empty(f"Muzzle{k}", Matrix.Translation(centre + out * 5.3 * HOUSING_SCALE))
        reparent_keep(muz, piv)

    # OMS: the concept's eight half-ball pods, one gimballed bell each. Name each bell exit for the game's jets;
    # the bells point outward, so the same exit serves for fore/aft burns (the game cants the jet).
    for ob in list(bpy.data.objects):
        if ob.type == "EMPTY" and ob.name.startswith("OMS steerable nozzle"):
            p = ob.matrix_world.translation.copy()
            out = Vector((p.x, 0, p.z)).normalized()
            tag = "F" if p.y > 0 else "A"
            k = round((math.degrees(math.atan2(out.z, out.x)) - 45) / 90) % 4
            exitp = p + out * 1.5
            B.empty(f"OMS_{tag}{k}", exitp)
            B.empty(f"OMSAX_{tag}{k}", exitp)

    # spinal coilgun along the lower left, between the OMS pods and the belly radiator
    ga = math.radians(247.5)
    gout = Vector((math.cos(ga), 0, math.sin(ga)))
    gr = 13.0
    coil = B.empty("Gun_Coil", (0, 0, 0))
    B.cylinder("B_coil_barrel", gout * gr + Vector((0, ours(-58), 0)), gout * gr + Vector((0, ours(2), 0)), 0.55, m_gun, coil, seg=32)
    x = -56.0
    while x < 0:
        B.torus("B_coil_stage", gout * gr + Vector((0, ours(x), 0)), (0, 1, 0), 1.0, 0.22, m_gun, coil, seg=40, seg2=10)
        x += 2.6
    for xp in (-50, -35, -10, 0):
        B.cylinder("B_pylon", gout * 8.7 + Vector((0, ours(xp), 0)), gout * gr + Vector((0, ours(xp), 0)), 0.28, m_gun, coil, seg=12)
    B.empty("Gun_Rail", (0, 0, 0))     # the Earth hull carries no railgun; the node keeps the game's lookup simple

    # reference points: Drive, Laser, Gun, Sensors, Radiators, Crew; and the drive exit
    for i, p in enumerate([(0, ours(70), 0), (0, ours(-65), 7.0 + 6.0 * HOUSING_SCALE), gout * gr + Vector((0, ours(-25), 0)),
                           (0, ours(-83) + NOSE_LENGTH * 0.8, 0), (0, ours(25), 40.0), (0, ours(-73), 0)]):
        B.empty(f"Sys{i}", p)
    B.empty("Nozzle", (0, ours(89.6), 0))
    bpy.context.view_layer.update()

    # --- clean up for the game: apply modifiers, name by section, join small parts by material
    keep_parent = {o.name for o in bpy.data.objects if o.name.startswith(("Turret", "RadPivot", "Gun_"))}

    def holder(ob):
        p = ob.parent
        while p is not None:
            if p.name in keep_parent:
                return p
            p = p.parent
        return None

    for ob in list(bpy.data.objects):
        if ob.type == "MESH" and ob.modifiers:
            with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
                for m in list(ob.modifiers):
                    bpy.ops.object.modifier_apply(modifier=m.name)
    # Shading: the concept's cylinders share their rim vertices between the side and the end caps, so plain smooth
    # shading bends the side normals toward the caps and each section darkens toward its ends (very visible where the
    # bow joins the crew shell). Sharp edges wherever faces meet at more than 35 degrees keep sides and caps apart.
    for ob in bpy.data.objects:
        if ob.type == "MESH":
            ob.data.set_sharp_from_angle(angle=math.radians(35))
    groups = {}
    for ob in list(bpy.data.objects):
        if ob.type != "MESH":
            continue
        h = holder(ob)
        if h is not None and h.name.startswith("Turret"):
            continue                       # turret parts stay separate and named (the game finds Lens/dome by name)
        if h is None:
            y = ob.matrix_world.translation.y
            if ob.name.startswith(("N_", "B_", "A_")):
                sec = ob.name[0]
            else:
                sec = "N" if y > 63 else ("A" if y < -58 else "B")
            reparent_keep(ob, None)
            key = (sec, None, ob.data.materials[0].name if ob.data.materials else "")
        else:
            key = (None, h.name, ob.data.materials[0].name if ob.data.materials else "")
        if len(ob.data.materials) > 1:
            key = key + (ob.name,)         # multi-material parts (barbettes) stay whole
        groups.setdefault(key, []).append(ob)
    for key, obs in groups.items():
        sec, holder_name, matname = key[0], key[1], key[2]
        name = (f"{sec}_{matname}" if sec else f"Rad_{holder_name}_{matname}") if len(key) == 3 else obs[0].name
        if len(obs) > 1:
            with bpy.context.temp_override(active_object=obs[0], object=obs[0], selected_objects=obs, selected_editable_objects=obs):
                bpy.ops.object.join()
        obs[0].name = name.replace(" ", "_").replace("|", "").replace("/", "_")[:60]
    # the concept's root empty is no longer needed once everything hangs off world space or a pivot
    for ob in list(bpy.data.objects):
        if ob.type == "EMPTY" and not ob.children and not ob.name.startswith(("Turret", "Muzzle", "RadPivot", "Gun_", "Sys", "Nozzle", "OMS")):
            bpy.data.objects.remove(ob, do_unlink=True)
    meshes = sum(1 for o in bpy.data.objects if o.type == "MESH")
    print("meshes after joining:", meshes)

    out = os.path.join(B.OUT_DIR, "earth.glb")
    B.export(out, os.path.join(HERE, "earth.blend") if save_blend else None)
    print("wrote", out)


if __name__ == "__main__":
    main("--blend" in sys.argv)
