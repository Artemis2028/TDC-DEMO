# Performance audit (v0.16.1)

Written as options, before any of it was implemented. v0.17.0 took the same-picture items (the view chrome drawn once, the caption columns, the scope copy skipping hose bones) and code-review items 1–4 (the battle script split, one glow-cap list with the load-time guard kept, the coil scale set from a stored base, beam and armour section on the sim events). The GPU trades (MSAA, the shadow atlas, SSAO, backface culling, a cheaper glow, planet tessellation) and everything under "Not now" were not done. Clip-track stripping and the double-sided housing setup stayed. The rest of this note is the audit as it was written.

The Windows build the user is playing is vsync-capped at about 60 fps on a real GPU, and it feels fine. The mesh, the paints and the decals stay as they are. This note is where that frame can get cheaper without a new hull, ranked by how much a discrete GPU is likely to gain at the current view size. The cloud machine renders with llvmpipe, so its frame time (about 134 ms, ~7 fps) is not a GPU measurement and is not used as one. Draw calls, triangles, viewport sizes and script time do carry over. Millisecond figures below are judgments from those counts for a mid-range discrete GPU at 804×684, not timings.

Measured with Godot 4.7 Forward+, own-ship Lance, live battle at 2× (`--bench 40 --class 1 --speed 2` for the script split, then a shorter run for the scene breakdown). Default camera distance 320 m. Main view is the SubViewport at 804×684. No code in the game was changed for this pass.

## Where the 1,223 draws and 1.19M triangles go

`RENDER_TOTAL_DRAW_CALLS_IN_FRAME` is 1,223 and `RENDER_TOTAL_PRIMITIVES_IN_FRAME` is 1,190,123. `RENDER_TOTAL_OBJECTS_IN_FRAME` is 3,006. Those three monitors are sums across every viewport, including the HUD. Split by viewport on the same frame:

| Pass | Draws | Triangles | Objects |
|---|---:|---:|---:|
| Main view, colour | 363 | 479,259 | 363 |
| Main view, shadow | 378 | 691,351 | 378 |
| EO scope (88×88) | 44 | 13,590 | 44 |
| HUD canvas | 438 | 5,923 | 2,221 |
| **Total** | **1,223** | **1,190,123** | **3,006** |

The colour pass is one submission of the Lance plus the planet (authored Lance 447,743 triangles, planet sphere 37,248). It is not also counting a depth prepass. The shadow pass is about 1.4× that, which fits the hull landing in two of the four cascades at this camera distance, not all four. The old “drawn about eight times” picture (depth, colour, four cascades) is not what these counters show now.

The HUD is 438 of the 1,223 draws (36%). On llvmpipe the tactical plot, which keeps the HUD and the scope and stops the main view, drops the frame from 134 ms to 19 ms, so those canvas draws are not the frame. They still inflate the headline number.

Scene nodes: 839. Video memory with the Lance on screen: 1,003 MB, of which 764 MB is textures. With the main view stopped: 413 MB video, 189 MB textures. No orphan nodes.

### Lance, by part

Authored triangles of the visible meshes (one copy, not multiplied by passes). The file has 155 mesh instances, 387 surfaces, 107 materials, and no mesh is shared by two nodes.

| Part | Meshes | Surfaces | Triangles | Cast shadows | Transparent surfaces |
|---|---:|---:|---:|---:|---:|
| Hull (N/B/A hull and fittings) | 5 | 96 | 231,781 | 5 | 6 |
| Turrets, mirrors, rotary mounts | 42 | 140 | 123,798 | 21 | 6 |
| Coilgun | 28 | 31 | 49,016 | 1 | 26 |
| Radiator wings | 32 | 66 | 31,638 | 24 | 8 |
| Sensors | 2 | 8 | 7,980 | 2 | 0 |
| OMS / plumes | 18 | 18 | 3,194 | 0 | 16 |
| VLS lids and similar | 28 | 28 | 336 | 0 | 0 |

The single coilgun mesh that still casts a shadow is the barrel, `Coilgun_A093_Barrel_Recoil_Geo`, at 45,956 triangles. `B_hull` alone is 133,653. The three laser-head pitch meshes are about 21,000 each. Lids, point defence, ammo feeds, beams, glows, plumes and muzzles already have shadows off.

Flat paints are split across many surfaces of the same colour. `MAT_Panels_E6E8EA` is 44 surfaces, `MAT_Bronze_8C6A52` is 28, `MAT_Gunmetal` is 23, `MAT_Accent_1E2228` is 18. Ninety material slots are used. Eight materials are textured. The largest images are 4096×4096 (stencil PBR, stencil roughness, decal atlas) and 2048×2048 fabric (colour, normal, roughness). Desktop import does not compress them.

### Other views

Enemy view (camera on the Mars frigate): 585 draws, 94,725 triangles, script 0.51 ms. The main view submits 43 draws and 51,168 triangles there. The expensive frame is the Lance filling the view, not the Mars ship. Mars and the Dagger still have Godot mesh LODs on; the Lance has them off.

Tactical plot: main view submits nothing. What remains is 462 canvas draws and the scope at 39 draws / 13,580 triangles. llvmpipe frame 19 ms, which only says the main view was the CPU renderer's problem.

### Script time

Per frame on this machine, from the 40-frame bench. At ~7 fps every frame is also a sim step and a HUD refresh. At 60 fps the sim steps at 10 Hz and the HUD text at 15 Hz, so snap and HUD land on fewer frames. World updates every frame either way.

| Part | This machine | What it is |
|---|---:|---|
| Sim advance | 0.017 ms | 10 Hz battle step |
| Ship-state snap | 0.084 ms | two `get_ship` dictionaries and the shot list |
| Events and sound | 0.064 ms | |
| World | 0.532 ms | poses, aim, radiators, flex, and the scope model's pose |
| HUD | 0.235 ms | panels at 15 Hz, overlay every frame |
| **Script total** | **0.96 ms** | |

The simulation itself is not the frame. `get_ship` still allocates a dictionary and several packed arrays per call, once per ship per sim step. There is no per-frame leak (orphan count stays 0).

### What the frame is already doing

- Renderer: Forward+. Three directional lights in the battle world (sun, fill, Mars-shine). Only the sun shadows: 4 cascades, hard edges, cascades not blended, 16-bit depth, atlas 4096, max distance = camera distance + 260 m (580 m here).
- Main view: MSAA 4×, SSAO on (radius 3 m, intensity 2.5), glow on (threshold 1.6, intensity 0.5, mip levels 2–4 only), AgX. TAA off, screen-space AA off, 3D resolution scaling off.
- Occlusion culling off. Frustum culling is on; the Mars ship is not in the Lance view's 363 colour draws.
- One reflection probe on the Lance, captured once at spawn, shadows off, frozen so it does not recapture. Not in the per-frame draws.
- Scope: own world, no shadows, no glow, no SSAO, no MSAA, 88×88 at this range (the size moves from 12 to 192 with sensor quality). It stays live on the plot.
- 91 of 107 Lance materials are double-sided, on purpose, so a one-sided housing does not draw as an open shell. The laser balls are the exception and are single-sided.

## Ranked options

Impact is against the own-ship frame above (1,223 draws, 1.19M triangles). Milliseconds are estimates for a discrete GPU at 804×684. The mesh stays. Items that would need a new glb, fewer triangles, or a generated LOD are under "Not now".

### Same picture

These do not change the hull, the paints, or the shading.

#### 1. Draw the view chrome once

**Engine.** `_update_hud` calls `overlay.queue_redraw()` on every frame, before the 15 Hz gate. `_draw_overlay` then repaints the cut corners, the frame, the title and the help line along with the bracket, the range and the tracers. The bracket has to follow the camera. The frame does not.

- Draws: the HUD is 438 canvas draws. A static layer behind the moving one removes that chrome from the per-frame submit. Triangles: the 5,923 canvas primitives are already small next to the ship.
- Estimated time: under 0.5 ms. The plot (HUD on, main view off) is 19 ms on llvmpipe, so this is not the GPU frame.
- Risk: low. The title does change when the view switches to armour or to the enemy, so that layer has to invalidate on those events. The picture stays the same.

#### 2. Fewer controls for the same labels

**Engine.** The panels are custom-drawn `Control`s (`widgets.gd`). Each one is its own canvas item, which is why the HUD is 2,221 canvas objects. `Txt.set_text` and `Btn.set_state` already skip the redraw when the string or the flag has not changed. What they cannot do is merge neighbouring labels into one draw.

- Draws: a batched panel (one control per column instead of one per caption) could cut a large share of the 438. Triangles: unchanged in any way that matters.
- Estimated time: under 0.5 ms on a discrete GPU.
- Risk: low if the layout and the colours stay. This is a drawing change, not a data change.

#### 3. Pose the scope ship without the hose bones

**Engine.** `_update_world` runs `show_state`, `aim` and `aim_sensor` on the scope's copy of the enemy as well as on the two battle ships. `aim_sensor` calls `_aim_rotary`, which writes a skeleton pose for every ammo-feed bone on four rotary mounts. The scope is 88×88 with no shadows. A hose does not read at that size.

- Draws and triangles of the scope stay (44 draws, 13.6k triangles). Script: a slice of the 0.53 ms world update, which is three ships today.
- Estimated GPU time: none. Estimated script: on the order of 0.1 ms on this machine, less on a desktop CPU.
- Risk: the telescope's hoses stay at rest. At this resolution that is the same picture.

### Changes the picture

These are engine settings. They do not touch the glb. They do change edges, shadows or contact shading, which is why they are not in the list above.

#### 4. MSAA 4× down to 2×, or TAA instead

**Engine.** The main view is 804×684 with 4 samples, about 2.2 million colour samples, before SSAO and glow. This is the largest fill-rate lever in the frame.

- Draws: unchanged. Triangles: unchanged. Samples: 2.2M → 1.1M at 2×, or one sample plus a history buffer with TAA.
- Estimated GPU time: 1–4 ms.
- Risk: at 2× the hull's panel seams and the radiator grid break into dashes. That was checked side by side and is why 4× stayed. TAA is off today. It is cheaper than 4× and holds thin edges better than 2×, and it smears when the camera orbits.

#### 5. Shadow atlas 4096 → 2048

**Engine.** The shadow pass is 378 draws and 691k triangles into a 4096 atlas. At the default camera the ship only occupies about two of the four cascades, so the empty splits are not where the triangles go. The fill of a 4k depth atlas is.

- Draws and triangles: unchanged if the cascade count stays. Shadow pixels: about a quarter.
- Estimated GPU time: 0.5–2 ms.
- Risk: softer shadows and more acne on thin radiator wings and panel lips. Keep four cascades. Two cascades were tried; the wings leak light at close range.

#### 6. SSAO down, or off

**Engine.** A full-screen pass on the main view (quality default is medium). The scope already runs without it.

- Draws and triangles: unchanged.
- Estimated GPU time: 0.5–1.5 ms off, less than that if only the quality drops.
- Risk: the creases where housings, rings and pods meet the hull go flat. That contact is why it is on. Dropping quality is the smaller visual step.

#### 7. Backface culling on closed panels

**Engine, at prepare time.** Housings are forced double-sided so a shell with inward faces still reads as solid. That flag is set on almost every Lance material, including closed panel paints. Those panels pay a fragment shader for faces the camera cannot see. It does not add draws.

- Draws: unchanged. Triangles submitted: unchanged. Fragments on the closed hull: up to about half of them go away where the back face was shaded.
- Estimated GPU time: 0.5–1.5 ms while the hull fills the view. Little when zoomed out.
- Risk: any panel that was authored open, or with normals pointing inward, gets a hole. Round housings, sensor domes and rotary mounts should stay double-sided. The laser balls must stay single-sided; drawing both sides of the 0.3 mm inner shell z-fights. Needs a side-by-side on the hull, the gun barrel and the radiator edges.

#### 8. Glow, one step cheaper

**Engine.** Already limited to mip levels 2–4, threshold 1.6, intensity 0.5, so the plume and the aperture do not white out the frame. The scope has glow off.

- Draws and triangles: unchanged.
- Estimated GPU time: 0.2–0.6 ms if a level is dropped or the intensity is lowered.
- Risk: the aperture ring and a burn bloom less. Small next to MSAA and SSAO.

#### 9. Planet tessellation

**Engine.** The Mars sphere is 192×96, 37,248 triangles, shadows already off, and it is in the colour pass.

- Draws: unchanged (one). Triangles: about 30k fewer in the colour pass at 96×48.
- Estimated GPU time: a few tenths of a millisecond. The limb is large on screen, so this is fill more than vertices, and MSAA already covers that.
- Risk: facets on the limb if it goes too coarse.

### Small, or already settled

#### 10. Scope resolution or update rate

**Engine.** 44 draws, 13,590 triangles, 88×88, no MSAA, no SSAO, no glow, no shadows. About 6% of the 3D draws and 1% of the triangles, and about 1.4% of the main view's pixels.

- Halving the resolution, or updating at 30 Hz instead of every frame, saves a fraction of that.
- Estimated GPU time: under 0.3 ms for the whole scope, so the saving is smaller still.
- Risk: the telescope gets blockier or steps. It was just put back on a live update in every view, including the plot, because a stale target showed as garbage on a real GPU. Not a good trade.

#### 11. Forward+ vs Mobile

**Engine.** The battle world has three directional lights, one of them shadowed. Clustered lighting has little to chew on. The Mobile renderer would not remove MSAA, the shadow atlas, SSAO or the glow, which is where the frame goes. It can change specular, reflections and how many lights a single object can take.

- Draws and triangles: about the same.
- Estimated GPU time: small on a discrete GPU. More interesting on an integrated GPU, and unmeasured here.
- Risk: broad. The copper mirrors read the probe and the sky; Mobile's reflection path is not the same picture. Not the first thing to try.

#### 12. Occlusion and the frustum

**Already on, for the frustum.** The Mars ship does not show up in the Lance colour pass, so a second frustum check would not remove it. Occlusion culling is off, and there are no occluder meshes. In open space the only hidden work is fittings on the far side of the hull. Backface culling (item 7) is the direct way to stop shading those, and it can punch a hole in a shell that was relying on the back face. Building occluders would be a new mesh. It would not move this frame much.

#### 13. Per-frame allocations

**Engine, low.** The snap builds two ship dictionaries and the shot list per sim step, measured at 0.08 ms on this machine when every frame is a step. At 60 fps that is about one frame in six. World logic at 0.53 ms every frame is the script worth knowing about, and it is still under a millisecond on this slow CPU. Reusing the dictionaries would cut garbage, not the GPU frame.

## Not now

The current hull stays. These would need a new glb, fewer triangles, or a generated LOD, and each one shows.

- Merging or atlasing materials (`MAT_Panels_E6E8EA` is 44 surfaces on its own). Vertex-colour baking in `prepare_arbiter.py` would flatten paints that do not share a roughness.
- LOD or decimation on the barrel (45,956 triangles), `B_hull` (133,653) and the three laser heads (~21,000 each). Automatic LODs already ate thin rings and were turned off for the Lance.
- MultiMesh for lids, domes or radiator segments. The file instances nothing (155 meshes, 155 nodes). The radiators are 24 different shapes on `RadiatorDeploy`. A MultiMesh would freeze that clip.
- VRAM-compressing the 4096 stencil atlases. It would shrink the 764 MB of textures and it would soften the decals.

## What not to redo

Static fittings are already merged per section and material. Shadow edges are already hard, cascades already unblended, the planet already unshadowed, the unused gun already freed, the probe already captured once, the scope already unshadowed and small, glow already on three mip levels, and the HUD text already at 15 Hz. `Txt.set_text` and `Btn.set_state` already skip the redraw when nothing changed. `find_child` runs when a ship is built, not from `_process`.

## Code review

Read of the GDScript, the C++ bridge, `art/prepare_arbiter.py` and `.github/workflows/build.yml`. No code was changed. The sim (0.017 ms) belongs in C++. The gimbal and the HUD belong in GDScript: moving them would save a fraction of a millisecond and make the game harder to read. `get_ship`'s dictionary keys are already built once.

What is not wrong: node lookup in the frame loop. Every `find_child` in `ship_model.gd` is in `build` or `_build_arbiter` and the helpers it calls at load. The 15 Hz HUD formats strings it often does not need, then `set_text` throws the redraw away. That cost is inside the 0.24 ms HUD figure and it lands one frame in four at 60 fps.

### 1. `main.gd` is the whole game

**`game/scripts/main.gd`**, about 2,200 lines. `_build_world`, `_build_hud` (and `_build_left`, `_build_right`, `_build_bottom`), `_update_hud`, `_draw_overlay`, `_input`, the menu, the end screen and `_bench_step` are one script.

Why: a change to the overlay has to be read next to helm orders and the Windows shot harness (`--fx`, `--esc`, `--settings` inside `_process`).

Suggested: a battle host, a HUD script, and an overlay script, with the shot harness left at the edge of `_process`.

Gain: maintainability. No frame-time change.

Risk: the pieces share `S0`, `S1`, the camera and `battle`. A split that copies that state will drift. Keep one owner and pass it in.

### 2. Brightness is decided in two places, and one comment is stale

**`art/prepare_arbiter.py` `cap_emissive_strength`**, and **`ship_model.gd` `_tame_arbiter_emission`** plus **`_brighten_laser_beam`**.

Why: prepare already caps named strengths (plume 1.15, throat 1.35, aperture 1.7, and a default of 1.8 above 2). At load, `_tame_arbiter_emission` walks every surface again and recaps anything still over 1.7. `_brighten_laser_beam` then throws the beam material away and writes an unshaded additive colour. Its comment says the importer drops `KHR_materials_emissive_strength`. `_tame_arbiter_emission` says Godot honours it. Both cannot be the policy.

Suggested: one list, in prepare. Keep the runtime walk only as a guard that does not duplicate materials when the peak is already under the cap. Fix the beam comment. Leave `_brighten_laser_beam` in place until a shot shows the file's own beam is the one we want.

Gain: maintainability. The next hull will not be capped twice to two different numbers. No frame-time change (this is load).

Risk: deleting the beam override without a picture check makes the beams dim or hot. The aperture special case (peak 1.7, just over the bloom threshold) has to survive the merge.

### 3. The coil scale depends on seek running first

**`ship_model.gd` `_show_charge`.**

Why: after `AnimationPlayer.seek`, the code multiplies every `Coilgun_Coil_*` scale by 1.15. The seek writes the clip's scale, so today the 1.15 applies once per seek. The early-out (`absf(u - _charge_u) < 0.002`) is what stops it multiplying again on the same pose. If a later edit seeks less often, or seeks after the multiply, the discs grow every tick of an 18 s reload.

Suggested: set the scale from a stored base, or put the 1.15 in the material size and stop multiplying.

Gain: removes a footgun. The charge discs stay the size they are now.

Risk: low if the base scale is the one the clip just wrote. Getting that base wrong changes the charge glow.

### 4. The after-action report parses English

**`game/scripts/aar.gd` `_on_event`, `_check_call`, `_timeline`.**

Why: a burn-through is a beam or a round because the text begins with `"Beam"`. The section is whichever of "nose", "body", "aft" appears in `"the %s armour"`. A crew call is split on `": probable "`. The sim already knows the weapon, the section and the system. The sentences are also what the player reads, so a wording change for the HUD breaks the report.

Suggested: add those fields on the event in `DemoBattle::get_events` and keep the text for the log. `aar.record` is already cheap; it only samples on `SAMPLE_DT`. This is not a frame-time item.

Gain: the report stops depending on prose. `aar.gd` is 871 lines of that prose analysis and can then be split into "record" and "write up" without a behaviour change.

Risk: the new fields have to match the text the player already sees. Goldens hash the sim, not the report, so the battle hashes stay.

### 5. Two hulls share one `show_state`

**`ship_model.gd`**, about 1,400 lines. `build` branches to the Dagger/Mars glb or `_build_arbiter`. `show_state`, `aim` and `fire_gun` then branch again on `arbiter`.

Why: the Dagger path is still the lasers-only ship, so it is not dead code. The Arbiter path (clips, flex bones, reflection probe, emissive cap, double-sided housings) is most of the file, and a Dagger fix has to be read through it.

Suggested: an Arbiter script that `main.gd` still talks to through the same calls (`show_state`, `aim`, `aim_sensor`, `fire_gun`).

Gain: maintainability. No frame-time change.

Risk: the shared hot-spot, radiator glow and turret-dead tint live in `show_state` before the branch. Those stay in the base, or they get copied and then diverge.

### 6. The clip-track strip is still doing its job

**`ship_model.gd` `_clip_keeps` and `_isolate_clip_tracks`**, called from `_build_arbiter_anims`.

Why it looks like a leftover: it was added when drive clips wrote rest poses onto the turrets and the wings would not fold. Godot's glTF import still inserts a rest key for every animated node into every clip. Stripping is what keeps a burn from pinning the lasers.

Suggested: keep it. The fragile part is the needle list. `"Turret_"` also matches flex paths under `RotaryTurret_`, which the comment already warns about. `_bind_ammo_feeds` already errors if a non-turret clip still has a `Flex` or `RT0` track. Extend that check to a drive clip that still has a turret track, so a future import that renames a path fails at load.

Gain: the next hull fails loudly instead of freezing the guns. No frame-time change.

Risk: a needle that is too narrow drops a track the clip actually needs (a radiator segment, a coil). The check should refuse to start, not guess.

### 7. Double-sided is set in three places, and all three are still the look

**`prepare_arbiter.py`** (every material `doubleSided = true`, then `single_side_laser_apertures`), and **`ship_model.gd` `_double_side_housings`**.

Why: prepare turns the flag on for the whole file, then clones the laser-ball materials as single-sided so the 0.3 mm inner shell does not z-fight. The runtime walk forces turret, sensor and rotary housings again, and skips `Pitch_Geo` and `SecondaryMirrorFace`. On a file prepare already wrote, the runtime walk finds cull already disabled and does nothing. It is the guard for a drop-in that forgets the flag.

Suggested: do not delete it as a v8 leftover. Point the three sites at one comment that names the laser exception. Culling closed panel paints is item 7 in the performance list, and it changes the picture.

Gain: a later cleanup does not "simplify" the laser balls back to double-sided.

Risk of removing the runtime guard: a future hull with one-sided housings draws as an open shell. Risk of removing the prepare flag: the same, plus item 7's holes if it is done by accident.

### 8. The scope ship repeats the battle ship's pose work

**`main.gd` `_update_world`**, the block that copies the enemy onto `eo_model` and calls `show_state`, `aim` and `aim_sensor`.

Why: that is a third full pose, including `_aim_rotary`'s bone writes, for an 88×88 picture. It is the same work as item 3 in the performance list.

Suggested: a pose path that moves the hull and the turrets and skips the hose bones.

Gain: a slice of the 0.53 ms world update. The main view does not change.

Risk: the telescope's hoses stay at rest. At this size that is invisible. Skipping `show_state` entirely would also skip the scope's radiator fold and plume, which can be seen as a blob, so those stay.

### 9. `get_ship` still allocates the arrays

**`extension/src/demo_battle.cpp` `DemoBattle::get_ship`**, called from **`main.gd` `_snap`**.

Why: the keys are interned. The dictionary, the packed arrays and the repair records are new on every sim step (10 Hz). Measured at 0.08 ms on this machine when every frame is a step. At 60 fps that is about one frame in six.

Suggested: leave it. A reused dictionary is faster and it is easy to get wrong: `_snap` keeps the previous `S0` only long enough to copy heading and roll, but anything else that stored the dictionary would see it change under it.

Gain: a little less garbage. Not the GPU frame.

Risk: aliasing. Higher than the gain.

### 10. Names and clocks are written twice

**`main.gd` `_shown_ship_name`, `_clock`** and **`aar.gd` `_shown_ship_name`, `clock`.**

Why: the end screen and the report format the same ship name and the same `mm:ss` independently. They match today.

Suggested: one helper when the scripts are split. Not before.

Gain: small. Risk: low, and not worth a change on its own.

### The build

**`.github/workflows/build.yml`** is a straight line: CMake, ctest, download Godot 4.7 and the export templates, stamp `version.gd`, export, hash the exe. The fragile step is the string replace of `const BUILD := "dev"`. It matches that line once, and it fails closed if the line changes. Godot is downloaded on every run. That costs CI minutes, not frames. `prepare_arbiter.py` (about 1,000 lines) is the hull's import, run by hand before a glb lands in `game/models/`. It is not on this workflow, and it is not on the frame. Its size is the pipeline (split, merge, normals, emissive cap, contract check), already in functions. The duplication that matters is the emissive cap in item 2 above.
