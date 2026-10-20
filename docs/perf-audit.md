# Performance audit (v0.16.1)

Options only. Nothing here is implemented.

The Windows build the user is playing is vsync-capped at about 60 fps on a real GPU, and it feels fine. This note is where that frame can get cheaper, ranked by how much a discrete GPU is likely to gain at the current view size. The cloud machine renders with llvmpipe, so its frame time (about 134 ms, ~7 fps) is not a GPU measurement and is not used as one. Draw calls, triangles, viewport sizes and script time do carry over. Millisecond figures below are judgments from those counts for a mid-range discrete GPU at 804×684, not timings.

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

Impact is against the own-ship frame above (1,223 draws, 1.19M triangles). Milliseconds are estimates for a discrete GPU at 804×684.

### 1. MSAA 4× down to 2×, or TAA instead

**Engine.** The main view is 804×684 with 4 samples, about 2.2 million colour samples, before SSAO and glow. This is the largest fill-rate lever in the frame.

- Draws: unchanged. Triangles: unchanged. Samples: 2.2M → 1.1M at 2×, or one sample plus a history buffer with TAA.
- Estimated GPU time: 1–4 ms.
- Risk: at 2× the hull's panel seams and the radiator grid break into dashes. That was checked side by side and is why 4× stayed. TAA is off today. It is cheaper than 4× and holds thin edges better than 2×, and it smears when the camera orbits.

### 2. Shadow atlas 4096 → 2048

**Engine.** The shadow pass is 378 draws and 691k triangles into a 4096 atlas. At the default camera the ship only occupies about two of the four cascades, so the empty splits are not where the triangles go. The fill of a 4k depth atlas is.

- Draws and triangles: unchanged if the cascade count stays. Shadow pixels: about a quarter.
- Estimated GPU time: 0.5–2 ms.
- Risk: softer shadows and more acne on thin radiator wings and panel lips. Keep four cascades. Two cascades were tried; the wings leak light at close range.

### 3. SSAO down, or off

**Engine.** A full-screen pass on the main view (quality default is medium). The scope already runs without it.

- Draws and triangles: unchanged.
- Estimated GPU time: 0.5–1.5 ms off, less than that if only the quality drops.
- Risk: the creases where housings, rings and pods meet the hull go flat. That contact is why it is on. Dropping quality is the smaller visual step.

### 4. Backface culling on closed panels

**Engine, at prepare time.** Housings are forced double-sided so a shell with inward faces still reads as solid. That flag is set on almost every Lance material, including closed panel paints. Those panels pay a fragment shader for faces the camera cannot see. It does not add draws.

- Draws: unchanged. Triangles submitted: unchanged. Fragments on the closed hull: up to about half of them go away where the back face was shaded.
- Estimated GPU time: 0.5–1.5 ms while the hull fills the view. Little when zoomed out.
- Risk: any panel that was authored open, or with normals pointing inward, gets a hole. Round housings, sensor domes and rotary mounts should stay double-sided. The laser balls must stay single-sided; drawing both sides of the 0.3 mm inner shell z-fights. Needs a side-by-side on the hull, the gun barrel and the radiator edges.

### 5. Collapse flat-colour materials that share a mesh

**Engine at prepare time, or model-side if Bridge Bot atlases them.** The hull is 5 meshes and 96 surfaces. The turret group is 42 meshes and 140 surfaces. The same solid paint is repeated as its own surface (`MAT_Panels_E6E8EA` alone is 44). Static fittings are already merged per section and material. What is left is different materials on one mesh, and the same material on nodes that move separately.

A prepare-time bake can fold flat paints that share roughness and metal into one vertex-coloured material per static mesh. Textured materials (fabric, flags, stencil atlases, placards, radar tile) stay. An atlas from Bridge Bot is the same idea with sharper control of roughness.

- Draws: on the order of 150–250 fewer across colour and the occupied shadow cascades (colour is 363 today, most of them one surface each). Triangles: unchanged. Material changes fall with the draws; Godot 4 does not publish a material-change counter. Unique materials in the live scene: 250, almost all `StandardMaterial3D`.
- Estimated time: 0.3–1 ms of CPU submit. A discrete GPU that is fill-bound, which is the likely case at a locked 60, gains less than items 1–3.
- Risk: paints merged across a roughness or metal boundary look flatter. Vertex colour has to match the albedo. Animated nodes (turret gimbals, radiator segments, flex hoses, the barrel recoil) still cannot be joined to the hull.

### 6. Glow, one step cheaper

**Engine.** Already limited to mip levels 2–4, threshold 1.6, intensity 0.5, so the plume and the aperture do not white out the frame. The scope has glow off.

- Draws and triangles: unchanged.
- Estimated GPU time: 0.2–0.6 ms if a level is dropped or the intensity is lowered.
- Risk: the aperture ring and a burn bloom less. Small next to MSAA and SSAO.

### 7. Manual LOD on the barrel, the hull and the three laser heads

**Model-side.** Godot's automatic LODs are off on the Lance because they collapsed thin rings and housings. Mars still has them, which is part of why the enemy view submits 51k triangles instead of the Mars file's 128k.

Worth a real LOD, in order: the barrel (45,956), `B_hull` (133,653), the three pitch heads (~21,000 each). A half-detail step on those, used only when they are small in the frame, is on the order of 150–200k fewer triangles in the colour pass and again in each cascade that contains them. Call it 200–400k of the 1.19M when the camera is at 320 m or further.

- Estimated GPU time: under 1 ms on a discrete GPU, more on an integrated one. Vertex work is not what usually limits this view; the triangles are the headroom if the fill items above are kept.
- Risk: a generated LOD eats the panel seams and the mirror ring, which is the failure already seen. The LOD has to be authored, and the close camera (down to 60 m) has to stay on the full mesh.

### 8. Planet tessellation

**Engine.** The Mars sphere is 192×96, 37,248 triangles, shadows already off, and it is in the colour pass.

- Draws: unchanged (one). Triangles: about 30k fewer in the colour pass at 96×48.
- Estimated GPU time: a few tenths of a millisecond. The limb is large on screen, so this is fill more than vertices, and MSAA already covers that.
- Risk: facets on the limb if it goes too coarse.

### 9. Fewer HUD canvas draws

**Engine.** 438 canvas draws and 2,221 canvas objects, against 363 colour draws for the whole ship. The plot proves this is not the llvmpipe frame. It is still a third of the draw-call number, and the canvas renderer submits it every frame even though most labels change at 15 Hz.

- Draws: a batched overlay could cut most of the 438. Triangles: the 5,923 canvas primitives are noise next to the ship.
- Estimated time: under 0.5 ms on a discrete GPU.
- Risk: low if it is the same layout drawn by fewer controls.

### 10. Scope resolution or update rate

**Engine.** 44 draws, 13,590 triangles, 88×88, no MSAA, no SSAO, no glow, no shadows. About 6% of the 3D draws and 1% of the triangles, and about 1.4% of the main view's pixels.

- Halving the resolution, or updating at 30 Hz instead of every frame, saves a fraction of that.
- Estimated GPU time: under 0.3 ms for the whole scope, so the saving is smaller still.
- Risk: the telescope gets blockier or steps. It was just put back on a live update in every view, including the plot, because a stale target showed as garbage on a real GPU. Not a good trade.

### 11. MultiMesh for repeated greebles

**Model-side first.** The glb instances nothing: 155 meshes, 155 nodes, zero reused. The VLS lids are 28 separate meshes and 336 triangles, shadows already off. The four rotary domes are the same shape (~4,450 each) but stored as copies, and they yaw independently, so a MultiMesh would freeze them. Radiator segments are 24 different shapes driven by `RadiatorDeploy`; a MultiMesh would freeze the deploy. Hull tiles are unique triangles inside `B_hull`, not instances.

- Draws: about 28 fewer if the lids became one MultiMesh. Triangles: unchanged.
- Estimated time: negligible.
- Risk: lids that animate open would need to leave the MultiMesh. Bridge Bot would have to author real instances before this is worth doing.

### 12. Forward+ vs Mobile

**Engine.** The battle world has three directional lights, one of them shadowed. Clustered lighting has little to chew on. The Mobile renderer would not remove MSAA, the shadow atlas, SSAO or the glow, which is where the frame goes. It can change specular, reflections and how many lights a single object can take.

- Draws and triangles: about the same.
- Estimated GPU time: small on a discrete GPU. More interesting on an integrated GPU, and unmeasured here.
- Risk: broad. The copper mirrors read the probe and the sky; Mobile's reflection path is not the same picture. Not the first thing to try.

### 13. Occlusion and the frustum

**Already on, for the frustum.** The Mars ship does not show up in the Lance colour pass, so a second frustum check would not remove it. Occlusion culling is off, and there are no occluder meshes. In open space the only hidden work is fittings on the far side of the hull, and backface culling (item 4) is the direct way to stop shading those. Building occluders is model-side and would not move this frame much.

### 14. Per-frame allocations

**Engine, low.** The snap builds two ship dictionaries and the shot list per sim step, measured at 0.08 ms on this machine when every frame is a step. At 60 fps that is about one frame in six. World logic at 0.53 ms every frame is the script worth knowing about, and it is still under a millisecond on this slow CPU. Reusing the dictionaries would cut garbage, not the GPU frame.

## What not to redo

Static fittings are already merged per section and material. Shadow edges are already hard, cascades already unblended, the planet already unshadowed, the unused gun already freed, the probe already captured once, the scope already unshadowed and small, glow already on three mip levels, and the HUD text already at 15 Hz.
