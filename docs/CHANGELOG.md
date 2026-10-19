# Demo changelog

The version is shown on the main menu (bottom right), in the HUD's top-left corner and in the window title. Each
CI build adds its run number and commit, e.g. "v0.8.0 · build 52 (68ab2ea)", so two downloads can always be told apart.

## v0.14.0
- The Lance is the Arbiter TDC v11 hull (`art/source/arbiter-TDC_v11.glb`, 40,927,736 bytes, SHA-256 `95cefa5402e785ae63ea9d458860a7d016ec62141048c5cd4d1f7189a78a0cd5`). The v8 source is gone. The 277 nodes, the 13 animation names and the 174 channels are unchanged, so the coilgun wave, the radiator seek, the aim snap and the clip-track strip from v0.13.2 still drive it. The Dagger and the Mars frigate are unchanged.
- The laser aperture sits inside the gold and blue lip ring, and the turret ball is part of `Turret_01_Pitch`, `Turret_02_Pitch` and `Turret_03_Pitch`, which are the nodes the aim code already turns. Base colours are the file's. Meshes that already have weighted normals are not re-smoothed. Mesh LODs stay off, and the turret and sensor shells stay double-sided.
- The fore-bottom OMS bell (A010) is shown when that pod fires. Its radial plume is authored at scale 0 and scaled up with the other bells. OMSBurn is still not the clip that runs.

## v0.13.2
- The coilgun wave and the barrel recoil play again. The charge seek had left the gun player at speed 0, so the firing clip never advanced. The coils are bright enough to bloom, and the bloom stays on the coil: the muzzle light is still the small one.
- Radiators fold and deploy with the panel, including while the drive is burning. Godot's importer had put a rest key for every animated part into every clip, so the drive clip was holding the wings open. Each clip now moves only its own nodes.
- Laser turrets and the sensor take the short arc and are already on the sim's aim at the first frame, so they do not unwind at spawn. A closing or opening burn no longer pins them: that was the same extra tracks, rewritten every frame the drive played.
- Close range and open range are labelled with the thruster that does the work. Close range is the main drive along the nose (the forward OMS only if the nose is more than 30° off the enemy). Open range is the aft OMS, because the main drive cannot push backward. Left and right stay the lateral pods and still stack on a closing burn. There is no separate OMS mode.
- Round housings are drawn double-sided, so a shell that was authored one-sided cannot show up open. The silhouette is still the low-poly mesh: a denser Arbiter can replace `art/source/arbiter-TDC_v8.glb` if it keeps the node names and the 13 animation names. `art/prepare_arbiter.py` checks that, smooths normals, and the import leaves mesh LODs off.

## v0.13.1
- The battle is drawn between the 10 Hz sim steps, so the hull, the enemy and rounds in flight no longer jump ten times a second when the frame rate is higher than the sim. Turret aim eases the same way. The attitude ball uses that in-between heading and roll.
- The sensor picture updates every frame. It is a second, unshadowed copy of the enemy, so the feed is not a second set of shadow cascades hitching the main view. Text on the panels stays at 15 Hz.
- A frame cap below the monitor's refresh turns vsync off. At or above the refresh, vsync stays on and the cap does not fight it. The first battle compiles the ship and effect shaders in a throwaway view, so the first shot or burn is not a compile hitch.
- Settings has a frame-time counter, off by default. F4 switches it during a battle. It shows FPS, frame time in ms, a 1% low and a short graph.
- The Lance's coil charge, muzzle flash and drive plume no longer bloom across the frame. Their lights are smaller and dimmer, and the imported emissive strengths (the throat was ×45, the strobes ×80) are capped. The ship and the HUD stay readable while the drive is burning.
- OMS pods can fire during a main-drive burn. A and D during a closing burn add a strafe instead of cutting the drive. There was no physical ban; one order used to be either the drive or the pods. A pure sideways or braking burn is still pods only. The AI and the recorded battles are unchanged (idle still about 42 %, holding the range about 72 %).
- The Lance's paints are the colours written in the material names (the file had left those factors white). Curved housings share normals across faces that meet more gently than 50°, and Godot no longer builds mesh LODs for this hull, which had been eating thin rings. The low-poly silhouette is the source mesh. The Dagger and the Mars frigate are unchanged.

## v0.13.0
- The Lance (laser and spinal coilgun) is drawn with the Arbiter TDC v8 hull. The Dagger keeps the previous Earth
  model, and the Mars frigate is unchanged. The v8 clips for the radiator wings, the main drive, the coilgun
  charge and firing, and the laser beams are driven from the battle. The sensor head tracks the enemy. The others
  stay in the file.
- The Lance's coilgun charges before it can fire. The first round waits 3 seconds (the charge clip's own length);
  every round after that still waits the 18 second reload. The charge lights play across whichever wait is running
  and finish as the gun becomes ready.
- Settings has "Visible laser beams", off by default, and L switches them during a battle the way B switches the
  dashed fire-control lines. On shows the Lance's beam meshes and a simple beam on the Dagger and the Mars frigate.
- The Lance's idle view is 1,183 draw calls, down from 1,242. Static fittings that share a look were merged, and
  lids, point-defence and effect meshes no longer cast shadows. The Dagger stays at 626. See docs/performance.md.

## v0.12.1
- **Esc pauses the battle.** Esc in battle opens the menu with the fight frozen underneath, and a **Resume battle**
  button (or Esc again) takes you back exactly where you left off. Before, the menu offered no way back and the
  laser and drive sounds kept playing, so it sounded as if the battle was still going.
- How to play: the 3D-view tip now says B hides the dashed laser lines (fire-control lines) and that Settings sets
  whether they start on. The menu's key list and the briefing footer say Esc pauses and resumes.
- The menu's watch-mode button says the AI flying Earth is an aggressive captain (it charges in and wins only about
  21 %), with a tooltip, so watching first doesn't suggest Earth is hopeless.
- Each CI build's download now includes `SHA256.txt` with the exe's hash (also shown on the run's summary page),
  so a VirusTotal scan can be matched to the exact file.

## v0.12.0
- **Balance: your decisions now decide the battle.** In v0.11.1 a player who gave no orders won 83 % of battles,
  more than the AI flying the same ship. Earth's lasers are weaker (Dagger 2.15 to 1.94, Lance 1.22 to 0.98), so over
  720 battles:
  - giving no orders wins about 42 %;
  - holding the range outside the frigate's weapons wins about 72 %;
  - watch mode's AI-flown Earth ship wins about 21 % (it closes to 20 km on auto fire).

  A new rules test keeps an idle player under 50 %.
- The Patreon button opens the Patreon page.
- How to play: the 3D-view tip now points at the tactical plot and its weapon ranges.
- The laser warning no longer covers the 3D view's hint line.
- The game's description says "above Mars", as the menu does.

## v0.11.1
- Cruise (CRZ) is crossed out as not in the demo. Battles start inside weapon range on a flat, gravity-free plane, so
  it could never engage. Its tooltip explains that cruise and orbital transfers come with the full game.
- The tactical plot is labelled as a relative-motion plot with a note that the demo has no gravity or orbits.
- The menu's coming-soon list now names orbital transfers.

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
