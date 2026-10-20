# Demo performance pass (October 2026)

What the demo costs per frame and what was done about it. These numbers come from `--bench`, which plays 300 frames
of a live battle after a 60-frame warm-up, prints the averages, and quits:

    godot --path game -- --bench 300 [--target] [--speed 0]

The cloud test machine renders on the CPU (llvmpipe), so its frame time says nothing about a real GPU. Draw calls,
primitives and script time do carry over.

| Measure (own-ship view)              | Before  | After   |
|--------------------------------------|---------|---------|
| 3D draw calls per frame              | 908     | 627     |
| 3D draw calls, enemy view            | 1131    | 606     |
| Triangles drawn per frame            | 517 k   | 371 k   |
| Triangles drawn, enemy view          | 246 k   | 103 k   |
| GDScript time per frame (worst case) | 1.36 ms | 0.86 ms |

The script figure is a worst case: the test machine runs at about 7 fps, so the 15 Hz HUD refresh happens every frame.
At 60 fps it runs one frame in four.

## Changes

- **Ship models:** static parts are merged by section and material when the models are built (`merge_static()` in
  `art/build_ships.py`). Mars ship: 195 to 38 objects. Earth ship: 72 to 45. Turret, radiator and gun parts stay on
  their moving pivots. Each object is drawn about 8 times a frame (depth, colour, 4 shadow cascades, sensor view),
  so this is the biggest single saving.
- **Shadows:** hard-edged, cascades not blended. This removes the soft-shadow search on every lit pixel and the
  second shadow sample in the blend zones. The 4 cascades stay, because with 2 the radiator wings leak light at close
  range. The planet no longer casts shadows.
- **EO sensor view:** was rendered at 15 Hz (see v0.13.1 below, which draws it every frame without a second shadow pass).
  Its size moves in 4 px steps and is set only when it changes, since each resize reallocates the image.
- **Ship materials:** one copy per source material and section instead of one per surface. Colours are written only
  when they change. Emission stays on, so the first armour view no longer compiles a new shader (a hitch).
- **The unused gun** is freed, not hidden.
- **Ship state:** read from the simulation once a frame (`_snap`) instead of about 18 times, and not at all while
  paused unless an order is given. Dictionary keys in the bridge are built once.
- **HUD:** text, lamps, panels and the damage-control card refresh at 15 Hz, or at once after a click or key. Only
  the 3D overlay, the alerts and the attitude ball redraw every frame. The nameplate, condition badge, scope labels,
  attitude ball and teletype redraw only when what they show changes.
- **Frame cap:** 120 fps, so a 144 to 240 Hz monitor doesn't run the GPU flat out. v0.13.1 turns vsync off when that
  cap is below the display refresh, because vsync and a lower cap drop frames on every other slot. v0.16.1 makes
  Unlimited actually uncapped (vsync off, no cap). VSync stays a separate switch and defaults to on.

Kept as is: 4x MSAA. At 2x the hull's panel seams break into dashes, checked side by side.

The simulation itself costs about 1 to 3 microseconds per tick, so it was left alone.

## Arbiter hull (v0.13.0)

The Lance is now drawn with the Arbiter TDC v8 model. Same measurement as above, 20 frames after a 60-frame warm-up, battle paused (`--bench 20 --speed 0`):

| View | Draw calls | Triangles | Script |
|---|---:|---:|---:|
| Dagger, own ship (class 0) | 626 | 370 k | 0.63 ms |
| Lance, own ship (class 1), as imported | 1242 | 468 k | 0.66 ms |
| Lance, enemy view (Mars) | 601 | 101 k | 0.68 ms |

The Dagger row matches the table above, and the enemy view matches the old Mars row, so the extra cost is the v8 hull. It is about twice the Dagger's draws because each surface is its own draw, and the hull is drawn again for the depth pass and for each of the four shadow cascades. The body alone was dozens of materials. The three laser heads, the rotary mounts, 24 radiator segments and 28 missile-cell lids each move on their own, so they cannot be joined without freezing a clip.

What could be joined was merged, and the same bench run again:

| View | Draw calls | Triangles | Script |
|---|---:|---:|---:|
| Dagger, own ship (class 0) | 626 | 370 k | 0.58 ms |
| Lance, own ship (class 1), after the merge | 1183 | 465 k | 1.63 ms |

Surfaces that already move together and share a look were combined (identical untextured materials on one mesh, and the loose static fittings on each section). Lids, point-defence, ammo feeds and the effect meshes no longer cast shadows. The glTF file dropped from 45 MB to 35 MB because the pre-split hull buffers were no longer referenced. Triangles barely moved: joining does not delete them. The Dagger is untouched. The Lance's remaining gap is the parts the clips actually move, plus paints that are genuinely different. The higher script time is the sensor aim and the charge seek, measured on llvmpipe.

## Live battle feel (v0.13.1)

The earlier tables are a paused battle. A paused battle never shows the 10 Hz stepping, the sensor hitch or a shader compile on the first shot. The same bench, own-ship Lance, battle running at 1× (`--bench 40 --class 1 --speed 2`), on llvmpipe:

| | Frame | Script | Draws | Triangles | Frame sd | Min | p95 | p99 | Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| v0.13.0 | 133.3 ms | 1.37 ms | 1197 | 467 k | — | — | — | — | — |
| v0.13.1 | 133.7 ms | 0.99 ms | 1190 | 657 k | 6.0 ms | 119 ms | 145 ms | 145 ms | 145 ms |

Of the script time, the world update (poses, aim, drive, charge) went from 0.83 ms to 0.49 ms. The charge clip is no longer seeked on frames where the cooldown has not moved.

The mean frame time did not move. On this CPU renderer a frame is about 7.5 fps and the cost is pixels: 4× MSAA, ambient occlusion, bloom and four shadow cascades. Triangles went up because mesh LODs are off for the Lance (they were collapsing thin rings and housings). Vertex work is not what this machine is waiting on, so the extra triangles did not add frame time. The measured window has no hitch: the slowest frame is 145 ms against a 134 ms mean.

What that mean cannot show, and what was making a smooth frame rate feel choppy:

- The sim steps at 10 Hz and the picture used to snap to the last step. Positions, headings, rolls and rounds now extrapolate across the step. The camera is still the mouse directly, with no added lag.
- The sensor feed was a second render of the whole scene, including the four shadow cascades, 15 times a second. On a fast GPU that is a periodic spike. It now renders every frame from its own world: one unshadowed copy of the enemy, the same lights, no cascade pass.
- Vsync stayed on under a 120 fps cap, so a 144 Hz display missed slots. A cap below the refresh now paces the frames with vsync off.
- The first shot and the first burn compiled effect shaders mid-fight. A throwaway view draws the Dagger, the Lance and the Mars frigate, with the plume, the coils and the beams, before the menu hands over. `--bench` and `--shot` skip that, so these numbers do not include it.
- Panel text stays at 15 Hz. The attitude ball, the overlay and the alerts were already every frame; the ball now follows the in-between heading.

Radiator segments stay separate meshes. There are 24 of them, each a different shape, each keyed by RadiatorDeploy, so one MultiMesh would freeze the deploy. The missile-cell lids are few draws and already cast no shadow. The four cascades stay: with two, the radiator wings leak light at close range.

## Arbiter TDC v11 (v0.14.0)

Same live bench as the table above (`--bench 40 --class 1 --speed 2`), on this machine, before and after the v11 hull. Both runs are llvmpipe, so the frame time is a CPU-renderer number, not the Windows GPU.

| | Frame | Script | Draws | Triangles | Frame sd | Min | p95 | p99 | Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| v0.13.2 (v8 hull) | 133.2 ms | 0.87 ms | 1192 | 657 k | 7.3 ms | 119 ms | 145 ms | 147 ms | 147 ms |
| v0.14.0 (v11 hull) | 133.3 ms | 0.88 ms | 1193 | 1,114 k | 6.5 ms | 119 ms | 144 ms | 148 ms | 148 ms |

Draws stay at 1,193. The triangle count is the authored mesh: 399,185 triangles in the file, and about 1.11 million primitives once the depth and shadow passes are counted. The mean frame did not move. Vertex work is still not what this renderer is waiting on.

## Arbiter TDC v17 (v0.15.0)

Same live bench (`--bench 40 --class 1 --speed 2`), on this machine, llvmpipe. The frame time is a CPU-renderer number, not the Windows GPU.

| | Frame | Script | Draws | Triangles | Frame sd | Min | p95 | p99 | Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| v0.14.0 (v11 hull) | 133.3 ms | 0.88 ms | 1193 | 1,114 k | 6.5 ms | 119 ms | 144 ms | 148 ms | 148 ms |
| v0.15.0 (v17 hull) | 133.4 ms | 0.72 ms | 1213 | 1,121 k | 4.8 ms | 119 ms | 139 ms | 144 ms | 144 ms |

The file itself is 417,764 triangles. Draws went up by 20, for the feed skins, the rotary domes and the decal surfaces. The mean frame did not move.

## Arbiter TDC v18d (v0.16.0)

Same live bench (`--bench 40 --class 1 --speed 2`), on this machine, llvmpipe. The frame time is a CPU-renderer number, not the Windows GPU. v0.15.1 and v0.15.2 did not change the hull, so the v0.15.2 row is the v0.15.0 measurement of that same v17 mesh.

| | Frame | Script | Draws | Triangles | Frame sd | Min | p95 | p99 | Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| v0.15.2 (v17 hull) | 133.4 ms | 0.72 ms | 1213 | 1,121 k | 4.8 ms | 119 ms | 139 ms | 144 ms | 144 ms |
| v0.16.0 (v18d hull) | 133.6 ms | 0.95 ms | 1223 | 1,190 k | 5.5 ms | 122 ms | 146 ms | 146 ms | 146 ms |

The file itself is 447,743 triangles. Draws went up by 10, for the secondary-mirror discs, the aperture glow rings and the single-sided copies of the laser-ball materials. The reflection probe is captured once at spawn and does not move, so it is not in the frame time. The mean frame did not move.

## Arbiter TDC v18f (v0.16.2)

Same live bench (`--bench 40 --class 1 --speed 2`), on this machine, llvmpipe. The frame time is a CPU-renderer number, not the Windows GPU. v0.16.1 did not change the hull, so its row is a same-day measurement of the v18d mesh.

| | Frame | Script | Draws | Triangles | Frame sd | Min | p95 | p99 | Max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| v0.16.1 (v18d hull) | 133.4 ms | 0.97 ms | 1223 | 1,190 k | 5.8 ms | 123 ms | 146 ms | 148 ms | 148 ms |
| v0.16.2 (v18f hull) | 133.2 ms | 1.01 ms | 1243 | 1,198 k | 7.0 ms | 118 ms | 145 ms | 149 ms | 149 ms |

The file itself is 450,653 triangles, 2,910 more than v18d. Draws went up by 20, for the four hex-tile meshes and their shadows. The housing stays in the section fittings, so it still casts a shadow. The mean frame did not move.

## HUD canvas (v0.17.0)

Same live bench (`--bench 40 --class 1 --speed 2`), on this machine, llvmpipe. The frame time is a CPU-renderer number, not the Windows GPU. The hull is the v18f mesh from v0.16.2. `canvas_draws` is the root viewport's canvas draw calls, which is the HUD. v0.16.2 did not print that counter; the before row is the same bench with only that print added, taken before this change.

| | Frame | Script | Draws | Canvas | Triangles | World | HUD |
|---|---:|---:|---:|---:|---:|---:|---:|
| v0.16.2 | 133.4 ms | 0.96 ms | 1243 | 438 | 1,198 k | 0.53 ms | 0.23 ms |
| v0.17.0 | 133.6 ms | 1.16 ms | 1228 | 423 | 1,198 k | 0.60 ms | 0.33 ms |

Canvas draws fell by 15. The caption columns are four controls, and each control draws one font and then the other, so a run of the same font is one draw. The view frame is drawn once and again only when its title changes; the bracket and the tracers still redraw every frame. That split does not remove the cached frame from the counter, because the canvas item is still submitted. The scope copy no longer poses the ammo-feed hoses. On this bench the world and HUD script times moved inside the spread of a 40-frame run (the same v0.16.2 code has measured 0.96 ms and 1.01 ms of script). The mean frame did not move. MSAA, the shadow atlas and SSAO were left as they were.
