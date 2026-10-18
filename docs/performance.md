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
- **EO sensor view:** rendered at 15 Hz instead of every frame, and only while the HUD is up. Its size moves in 4 px
  steps and is set only when it changes, since each resize reallocates the image.
- **Ship materials:** one copy per source material and section instead of one per surface. Colours are written only
  when they change. Emission stays on, so the first armour view no longer compiles a new shader (a hitch).
- **The unused gun** is freed, not hidden.
- **Ship state:** read from the simulation once a frame (`_snap`) instead of about 18 times, and not at all while
  paused unless an order is given. Dictionary keys in the bridge are built once.
- **HUD:** text, lamps, panels and the damage-control card refresh at 15 Hz, or at once after a click or key. Only
  the 3D overlay, the alerts and the attitude ball redraw every frame. The nameplate, condition badge, scope labels,
  attitude ball and teletype redraw only when what they show changes.
- **Frame cap:** 120 fps, so a 144 to 240 Hz monitor doesn't run the GPU flat out.

Kept as is: 4x MSAA. At 2x the hull's panel seams break into dashes, checked side by side.

The simulation itself costs about 1 to 3 microseconds per tick, so it was left alone.

## Arbiter hull (v0.13.0)

The Lance is now drawn with the Arbiter TDC v8 model. Same measurement as above, 20 frames after a 60-frame warm-up, battle paused (`--bench 20 --speed 0`):

| View | Draw calls | Triangles | Script |
|---|---:|---:|---:|
| Dagger, own ship (class 0) | 626 | 370 k | 0.63 ms |
| Lance, own ship (class 1) | 1242 | 468 k | 0.66 ms |
| Lance, enemy view (Mars) | 601 | 101 k | 0.68 ms |

The Dagger row matches the table above, and the enemy view matches the old Mars row, so the extra cost is the v8 hull. It is about twice the Dagger's draw calls because the body is 37 materials, the three laser heads and four rotary mounts stay separate meshes, and each radiator wing is 12 animated segments. Joining those the way `merge_static()` joined the Dagger would flatten either the paint or the clips. Coil glows, the muzzle flash, the OMS bells and the drive plume stay hidden until they fire, so they are not in the idle count.
