# TDC Demo

The public playable demo of TDC: one battle above Mars, Earth against Mars, 2300.

The demo runs on its own simplified rules ("gamified" values: armour points, damage per shot, a 0-100 heat bar),
written in C++ and compiled into the game's engine (a GDExtension in the editor). It does not contain the TDC physics
engine or its data.

| Folder | What it is |
| --- | --- |
| `sim/` | The demo rules in plain C++ (no Godot), with tests |
| `extension/` | The bridge that exposes the rules to Godot (`DemoBattle`); built on `godot-cpp` as the GDExtension the editor loads |
| `modules/tdc_demo/` | The same bridge as a Godot engine module, built into the export templates so the game is one executable |
| `game/` | The Godot project: HUD, ship models, menus (GDScript, exported as compressed binary tokens) |
| `.github/workflows/build.yml` | Builds and tests on Windows and macOS; exports `TDC-Demo.exe` and a macOS test build (`TDC-Demo-macOS.zip`, not notarized) as downloadable artifacts |

## What is in the demo

- Your ship (Dagger: laser; Lance: laser and spinal coilgun) against a Mars frigate with a railgun.
- Fire control: weapons free or hold, auto or manual targeting of a system, presets (disable drive, blind, cook, disarm).
- Maneuver: burn toward, away, sideways or to match velocity, with throttle; face the enemy nose-on or side-on, and roll about the ship's axis either way (rolling side-on spreads the enemy beam over the hull).
- Heat: radiators extend (cool fast, can be shot off) or retract (safe, heat builds); at 100 weapons lock until below 70.
- Damage control: repair teams from the crew; each job's timer varies with the damage (0.7-1.4x its estimate) and
  each repeat patch on the same system takes longer.
- EO sensor window: a camera view of the target that sharpens with range and your sensors' health.
- Speeds: pause, 0.5x to 10x, and cruise (50x) while out of weapon range.
- Shown but locked: fleet battles, radar, lidar and IR, electronic warfare, going dark, the ship designer.

## Building

### Rules, tests and the editor

```
git submodule update --init
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build
```

This builds the rules tests and the GDExtension (godot-cpp's default `template_debug`, which suits the editor). The
extension lands in `game/bin/`; open `game/` in a stock Godot 4.5 or later (CI exports with 4.7). The editor loads the
extension through `game/tdc_demo.gdextension`; the export leaves both out.

### The exported game: one executable

Godot cannot load an extension library from inside the game's embedded `.pck`, so with an extension the exe needed a
`tdc_demo.dll` (or `libtdc_demo.dylib`) beside it. Instead, the export uses custom release templates: the Godot engine,
built from source with `modules/tdc_demo` compiled in. The module and the extension share one bridge source
(`extension/src/demo_battle.*`; `#ifdef GDEXTENSION` picks the headers), and register the same `DemoBattle` class and
methods, so the scripts work with either. `game/export_presets.cfg` points at the templates in `templates/` (beside
`game/`, not in git) and excludes `tdc_demo.gdextension` and `bin/`.

CI builds the templates on every push (`.github/workflows/build.yml`), from the source of the same Godot version it
exports with (`GODOT: 4.7-stable`; change it in both jobs to move to another version). The engine's objects are kept
in an SCons cache, so a push recompiles the module and relinks; only the first build on a branch, or a new Godot
version, compiles the engine (about an hour). CI then exports with the stock editor, checks that the Windows export is
one file, plays 300 frames of a battle headless in the exported game (`--bench`), and uploads the exe with
`SHA256.txt`.

To build the Windows template yourself (Python, `pip install scons`, Visual Studio with C++):

```
git clone --depth 1 --branch 4.7-stable https://github.com/godotengine/godot.git godot-src
cd godot-src
scons platform=windows target=template_release arch=x86_64 debug_symbols=no custom_modules=../modules
mkdir ..\templates
copy bin\godot.windows.template_release.x86_64.exe ..\templates\windows_release_x86_64.exe
```

For the Mac, build `platform=macos` for `arch=arm64` and `arch=x86_64`, join them with `lipo`, and zip them as
`macos_template.app` (the "Build the macOS release template" step in the workflow does exactly this). The templates
must be `target=template_release`: release engine code throughout, as with the extension (a debug godot-cpp in a
release engine corrupted the heap, v0.17.0).

A custom editor (`target=editor` with the same `custom_modules=../modules`) also has `DemoBattle` built in. If you use
one, delete `game/bin/` or `game/tdc_demo.gdextension` locally, or the extension registers the class a second time.

## Balance

Balanced so the player's decisions decide the fight. Over 720 battles (both ships, every start, every enemy captain):

| Player | Earth wins |
| --- | --- |
| Gives no orders at all | about 42 % |
| Holds the range at 125-145 km (outside the frigate's weapons) | about 72 % |
| AI flying the Earth ship (watch mode, labelled "aggressive Earth captain": closes to 20 km on auto fire) | about 21 % |

`idle_player_loses_more_than_it_wins` in `sim/tests/tests.cpp` keeps an idle player under 50 % and holding the range
at least 20 points ahead of it. Up to v0.11.1 the balance was tuned AI against AI, which let an idle player win 83 %.

## Ship models

Earth flies two hulls. The lasers-only Dagger is the Dagger concept model (`art/source/Dagger_Earth_Destroyer.blend`),
converted for the game by `art/import_dagger.py` (turns it to game axes, makes the radiator wings foldable, adds the
three laser barbettes, OMS blisters and coilgun, joins parts by material) and exported to `game/models/earth.glb`.
The Lance, the Earth ship that carries the spinal coilgun, is the Arbiter TDC v18f hull (`art/source/arbiter-TDC_v18f.glb`).
`art/prepare_arbiter.py` splits its static meshes into nose, body and aft for the armour view and writes
`game/models/arbiter.glb`; the 13 animation clips are left on their original nodes. The Mars ship is built in Blender
by `art/build_ships.py` (pure script, no hand modelling) and exported to `game/models/mars.glb`; `art/earth.blend` and
`art/mars.blend` are the Dagger and Mars models for editing by hand. Rebuild Mars with `blender --background --python
art/build_ships.py -- --blend` (or `python art/build_ships.py --blend` with the `bpy` package). The Dagger and Mars
are found by name (Turret0..2, Muzzle0..2, Rad*, OMS_*, Gun_Coil/Gun_Rail, Sys0..5, Nozzle; mesh names starting
N_/B_/A_ belong to the nose/body/aft sections), so keep those names if you edit a model by hand.

## Fonts

- [Saira](https://github.com/google/fonts/tree/main/ofl/saira) (headings and labels) and [Share Tech Mono](https://github.com/google/fonts/tree/main/ofl/sharetechmono) (readouts), from the Google Fonts repository under the SIL Open Font License 1.1; licences in `game/fonts/`.
