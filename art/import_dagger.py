"""Turn Rafael's Dagger concept model (art/source/Dagger_Earth_Destroyer.blend) into the game's Earth ship.

Run:  python art/import_dagger.py [--blend]     (needs the bpy package; or blender -b --python art/import_dagger.py)

The concept model keeps its hull, tanks, seams, missile doors, nose housing, radiator wings and drive. This script:
  * turns it to the game's axes (nose along +Y in Blender, which the glTF exporter makes -Z in Godot),
  * removes cameras and lights,
  * regroups each radiator wing under a RadPivot node whose local +X points outward, so the game can fold it,
  * keeps the nose housing as the sensor/optics head (no laser on the nose: it takes the enemy's fire),
  * adds the game's three laser barbettes amidships, the OMS blisters, the spinal coilgun and the named reference
    points the game looks for (see build_ships.py for the list),
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
LENGTH = 187.7               # the concept's overall length; ShipModel uses the same number


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

    # --- the game's parts, in game axes (nose +Y, +X right, +Z top)
    m_hull = bpy.data.materials["Pale aerospace protective panels"]     # the concept's own hull and marking paints
    m_gold = bpy.data.materials["Muted caution ochre"]
    m_dome = B.material("B_dome", (0.80, 0.82, 0.84), 0.25, 0.4)
    m_dark = B.material("emitter", (0.10, 0.11, 0.12), 0.4, 0.7)
    m_lens = B.material("lens", (0.35, 0.65, 1.0), 0.05, 0.0, emit=(0.35, 0.65, 1.0), emit_strength=4.0)
    m_noz = B.material("nozzle", (0.12, 0.12, 0.13), 0.4, 0.8)
    m_gun = B.material("B_gun", (0.60, 0.53, 0.40), 0.35, 0.7)

    # laser barbettes on the central tank, clear of the missile doors and radiator roots
    u = 5.0
    y0, hr = ours(-20), 9.0
    for k, a in enumerate(B.TURRET_ANGLES):
        out, _, _ = B.frame(y0, a)
        foot, bar_h = 0.62 * u, 0.34 * u
        core = 0.40 / 0.62

        def barbette(s, core=core, bar_h=bar_h):
            if s <= core:
                return bar_h
            t = (s - core) / (1 - core)
            return bar_h * (1 - t) ** 2 * (1 + 2 * t)
        B.hull_patch(f"B_barbette{k}", y0, a, hr, barbette, foot, m_hull, rings=48, seg=64, band=(0.69, 0.76, m_gold))
        piv = B.empty(f"Turret{k}", out * (hr + bar_h) + Vector((0, y0, 0)))
        B.sphere(f"B_dome{k}", (0, 0, 0), 0.3 * u, m_dome, piv, seg=64, rings=32)
        B.revolve(f"B_emitter{k}", B.fillet([(0.12 * u, 0.0), (0.12 * u, 0.14 * u), (0.48 * u, 0.14 * u), (0.48 * u, 0.11 * u),
                                              (0.4 * u, 0.095 * u)], 0.03 * u, 4), m_dark, piv, seg=40)
        B.revolve(f"Lens{k}", [(0.44 * u, 0.0), (0.44 * u, 0.095 * u)], m_lens, piv, seg=40)
        B.empty(f"Muzzle{k}", (0, 0.48 * u, 0), piv)

    # OMS blisters: forward on the crew shell, aft on the systems transition (between the service hatches)
    for (xc, rad, tag) in [(-70, 7.0, "F"), (40, 8.6, "A")]:
        yc = ours(xc)
        sec = "N" if tag == "F" else "B"
        for k in range(4):
            a = math.pi / 4 + k * math.pi / 2
            out, around, along = B.frame(yc, a)
            foot, hb, stretch = 2.2, 1.0, 1.8
            B.hull_patch(f"{sec}_oms{tag}{k}", yc, a, rad, lambda s, hb=hb: hb * (1 - s * s) ** 1.6, foot, m_hull,
                         rings=28, seg=56, stretch=stretch)
            top = out * (rad + hb) + Vector((0, yc, 0))
            B.cylinder(f"{sec}_port", top - out * 0.3, top + out * 0.05, 0.45, m_noz, seg=24)
            axd = along if tag == "F" else -along
            endp = out * (rad + hb * 0.55) + Vector((0, yc, 0)) + axd * foot * stretch * 0.55
            B.cylinder(f"{sec}_port", endp - axd * 0.25, endp + axd * 0.05, 0.35, m_noz, seg=24)
            B.empty(f"OMS_{tag}{k}", top + out * 0.05)
            B.empty(f"OMSAX_{tag}{k}", endp + axd * 0.05)

    # spinal coilgun along the lower left (the belly and top carry radiator panels at the crew section)
    ga = math.radians(225)
    gout = Vector((math.cos(ga), 0, math.sin(ga)))
    gr = 11.5
    coil = B.empty("Gun_Coil", (0, 0, 0))
    B.cylinder("B_coil_barrel", gout * gr + Vector((0, ours(-62), 0)), gout * gr + Vector((0, ours(8), 0)), 0.55, m_gun, coil, seg=32)
    x = -60.0
    while x < 6:
        B.torus("B_coil_stage", gout * gr + Vector((0, ours(x), 0)), (0, 1, 0), 1.0, 0.22, m_gun, coil, seg=40, seg2=10)
        x += 2.6
    for xp in (-55, -35, -15, 3):
        hull_r = 9.0 if xp > -55 else 8.1
        B.cylinder("B_pylon", gout * (hull_r - 0.3) + Vector((0, ours(xp), 0)), gout * gr + Vector((0, ours(xp), 0)), 0.28, m_gun, coil, seg=12)
    B.empty("Gun_Rail", (0, 0, 0))     # the Earth hull carries no railgun; the node keeps the game's lookup simple

    # reference points: Drive, Laser, Gun, Sensors, Radiators, Crew; and the drive exit
    for i, p in enumerate([(0, ours(70), 0), (0, y0, hr + 2.5), gout * gr + Vector((0, ours(-25), 0)),
                           (0, ours(-92), 0), (0, ours(25), 40.0), (0, ours(-73), 0)]):
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
