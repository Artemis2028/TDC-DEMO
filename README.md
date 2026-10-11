# TDC Demo

The public playable demo of TDC: one battle at the Moon, Earth against Mars, 2300.

The demo runs on its own simplified rules ("gamified" values: armour points, damage per shot, a 0-100 heat bar),
written in C++ and compiled into a Godot extension. It does not contain the TDC physics engine or its data.

| Folder | What it is |
| --- | --- |
| `sim/` | The demo rules in plain C++ (no Godot), with tests |
| `extension/` | The Godot extension that exposes the rules (`DemoBattle`), built on `godot-cpp` |
| `game/` | The Godot project: HUD, ship models, menus (GDScript, exported as compressed binary tokens) |
| `.github/workflows/build.yml` | Builds and tests on Windows and exports `TDC-Demo.exe` as a downloadable artifact |

## What is in the demo

- Your ship (Dagger: laser; Lance: laser and spinal coilgun) against a Mars frigate with a railgun.
- Fire control: weapons free or hold, auto or manual targeting of a system, presets (disable drive, blind, cook, disarm).
- Maneuver: burn toward, away, sideways or to match velocity, with throttle; facing nose on, broadside roll or stern.
- Heat: radiators extend (cool fast, can be shot off) or retract (safe, heat builds); at 100 weapons lock until below 70.
- Damage control: repair teams from the crew; each job's timer varies with the damage (0.7-1.4x its estimate) and
  each repeat patch on the same system takes longer.
- EO sensor window: a camera view of the target that sharpens with range and your sensors' health.
- Speeds: pause, 0.5x to 10x, and cruise (50x) while out of weapon range.
- Shown but locked: fleet battles, radar, lidar and IR, electronic warfare, going dark, the ship designer.

## Building

```
git submodule update --init
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build
```

The extension lands in `game/bin/`; open `game/` in Godot 4.5 or later.

## Balance

AI against AI over 40 seeds: Dagger wins about 65 %, Lance about 65 %. `sim/tests/tests.cpp` keeps both above the frigate.

## Ship models

The Earth ship is Rafael's Dagger concept model (`art/source/Dagger_Earth_Destroyer.blend`), converted for the
game by `art/import_dagger.py` (turns it to game axes, makes the radiator wings foldable, adds the three laser
barbettes, OMS blisters and coilgun, joins parts by material). The Mars ship is built in Blender by `art/build_ships.py` (pure script, no hand modelling) and exported to
`game/models/earth.glb` and `game/models/mars.glb`; `art/earth.blend` and `art/mars.blend` are the same models for
editing by hand. Rebuild with `blender --background --python art/build_ships.py -- --blend` (or `python
art/build_ships.py --blend` with the `bpy` package). The game finds parts by name (Turret0..2, Muzzle0..2, Rad*,
OMS_*, Gun_Coil/Gun_Rail, Sys0..5, Nozzle; mesh names starting N_/B_/A_ belong to the nose/body/aft sections),
so keep those names if you edit a model by hand.
