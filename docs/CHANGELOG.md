# Demo changelog

The version is shown on the main menu (bottom right), in the HUD's top-left corner and in the window title. Each
CI build adds its run number and commit, e.g. "v0.8.0 · build 52 (68ab2ea)", so two downloads can always be told apart.

## v0.11.0
- **Tactical plot** (V, or the PLOT view button): a top-down picture of the engagement.
  - Range rings, both ships' velocities and the relative velocity.
  - Closest point of approach (CPA): distance and time, with the predicted track.
  - Both sides' weapon ranges, and the enemy's recent trail.
  - An uncertainty ellipse when your sensors track it poorly.
  - The 3D view stops rendering while the plot is up.
- **After-action report** (end screen): result, hull over time, a timeline of key moments, and a few findings backed
  by the battle's own numbers:
  - how armour posture mattered;
  - laser versus gun;
  - where you were hit;
  - how many of your crew's "probable" calls were right;
  - heat lockouts;
  - repair uptime.

  The report can be exported as text.
- **How to play:** a two-page briefing before the first battle, and from the menu.
- **Settings:** volume, window mode (windowed, fullscreen, borderless), frame-rate cap, fire-control lines, briefing.
  Saved between sessions.
- **Export logs** (Settings): writes the game logs, a system summary, this battle's events and the report to
  Documents/TDC Demo logs, with your user name scrubbed from paths, and opens the folder. Nothing is uploaded.
- **Tooltips** on the HUD's controls and lamps.

## v0.10.0
- Starting situations, picked on the main menu or at random:
  - head-on;
  - crossing (the frigate passes across your bow, drifting sideways);
  - stern chase (it comes up dead astern, before your turrets bear).
- Three enemy captains, never named during the fight:
  - a brawler that closes to knife range;
  - a kiter that holds about 45 km and backs off when you press;
  - a broadsider that rolls and turns side-on to bring every turret to bear.

  The crew calls out what it sees ("Enemy turning broadside", "Enemy opening the range"), and the end screen says
  which captain it was.
- Balance across all nine combinations (AI vs AI, 100 battles each): Earth wins 54-76 %, and every battle ends.
- Fire-control lines are drawn in one batch per line (they had been costing a draw command per dash).

## v0.9.0
- Lasers no longer draw a glowing beam: in vacuum a beam can't be seen from the side. What shows instead:
  - a hot spot where the beam lands, heating from dull red to white the longer it dwells and cooling once it stops;
  - a faint glow at each firing emitter;
  - thin dashed fire-control lines (a HUD aid, ours blue, theirs orange). B hides them for the realistic view.

## v0.8.0
- Version numbers in the game.
- Performance pass (docs/performance.md): merged ship meshes, cheaper shadows, sensor view and HUD at 15 Hz,
  frame rate capped at 120.
- Teletype crew calls in shorthand ("ENEMY SNS · PROB DSBL").

Earlier builds had no version number. Their main additions were laser beam-director heads, the HUD fonts, the
gamified-demo label, estimated enemy health with right-click kill marks, panelled armour, fallible enemy damage
reports, laser warning and hit callouts, coilgun firing effects and tracers, a deeper laser sound, and the fix for
the AMD crash.
