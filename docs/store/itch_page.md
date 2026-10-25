# itch.io page draft (TDC Demo)

Paste each block into the matching itch.io field. Everything below is taken from the game as it is in v0.17.1; check
the numbers again if the balance changes.

## Project settings

| Field | Value |
| --- | --- |
| Title | TDC Demo |
| Project URL | `tdc-demo` (any free slug) |
| Short description or tagline | Hard sci-fi ship-to-ship combat, 2300. Hold the range, manage your heat, and keep your crew patching what the enemy breaks. |
| Classification | Games |
| Kind of project | Downloadable |
| Release status | In development |
| Pricing | No payments (or "Donate" with a $0 minimum, if you want tips beside Patreon) |
| Genre | Simulation (secondary: Strategy) |
| Tags (up to 10) | space, sci-fi, hard-science-fiction, tactical, simulation, spaceships, real-time, singleplayer, space-combat, godot |
| AI generation disclosure | Answer this honestly for code, art and text before publishing |
| Platforms | Windows |
| Community | Comments on (early feedback is the point of the demo) |
| Visibility | Restricted first (only people with the link), then Public once the page looks right |

## Uploads

- `TDC-Demo-windows.zip` from the CI run of the launch build on `main`: contains `TDC-Demo.exe`, `LICENSE.txt` and
  `SHA256.txt`. Mark it **Windows** and **Executable**.
- Optional: put the SHA-256 from `SHA256.txt` in the upload's display name or in the description, so players can check
  their download.

## Description

> **TDC Demo** is a free, playable slice of TDC, a hard sci-fi space combat game in development. It is one
> engagement: an Earth warship against a Mars frigate armed with a railgun.
>
> The demo's numbers (speeds, weapons, damage) are tuned for play. They are not the final simulation, which is built
> from engineering data and is still in development.
>
> ### Your ship
>
> - **Dagger**, a laser cruiser, or
> - **UEN Second Opinion**, a coil gun frigate with lasers and a spinal coilgun.
>
> ### What you do
>
> - **Fire control.** Weapons free or hold. Pick targets yourself or let the crew choose, or use presets: disable
>   the drive, blind the sensors, cook the ship, disarm it.
> - **Manoeuvre.** Burn toward, away, sideways or to match velocity. Face the enemy nose-on or side-on, and roll to
>   spread an incoming beam over your hull.
> - **Heat.** Extend your radiators to cool fast, but they can be shot off. Retract them and heat builds up. At 100,
>   your weapons lock until you cool below 70.
> - **Damage control.** Send repair teams from your crew. Every repair takes a different time, and each repeat patch
>   on the same system takes longer.
> - **Sensors.** A camera view of the target that sharpens with range and with the health of your sensors.
> - **Tactical plot.** A top-down view with range rings, closest approach, weapon ranges and your uncertainty about
>   where the enemy is.
> - **After-action report.** How the fight went, with findings drawn from the battle's own numbers. You can export it
>   as text.
>
> Your decisions decide the fight. A captain who gives no orders loses more often than not. One who holds the range
> wins most battles.
>
> ### Coming in the full game
>
> Fleet battles, radar, lidar and infrared sensors, electronic warfare, running dark, orbital transfers and a ship
> designer. They are shown, locked, in the demo.
>
> ### Support
>
> TDC is made by one developer. If you'd like to help, the game is on Patreon:
> https://www.patreon.com/c/BlackBody1

## Controls (description section or a screenshot caption)

> | Key | Action |
> | --- | --- |
> | W / S | Close range (main drive) / open range (aft thrusters) |
> | A / D / X | Strafe left / right, match velocity |
> | Q / E | Roll |
> | T | Nose-on or side-on |
> | I or Enter | Light or cut the drive |
> | Space | Weapons free or hold |
> | F1 / F2 / F3 | Fire mode |
> | P | Pause |
> | , / . | Slower / faster |
> | Tab | Your ship or the target |
> | V | Tactical plot |
> | C | Chase camera |
> | B | Fire-control lines |
> | L | Laser beams |
> | F | Frame-time counter |
> | M | Mute |
> | Esc | Pause to the menu (Esc again resumes) |
> | Right-drag, wheel | Orbit and zoom the camera |

## Install instructions (the "Install instructions" field)

> 1. Download and unzip `TDC-Demo-windows.zip`.
> 2. Run `TDC-Demo.exe`. Nothing is installed; delete the folder to remove the demo.
> 3. The demo is not code-signed yet, so Windows may show "Windows protected your PC". Click **More info**, then
>    **Run anyway**. To check that your copy is the one we published, compare its SHA-256 with the one in
>    `SHA256.txt` and on this page (`certutil -hashfile TDC-Demo.exe SHA256` in a command prompt).
>
> Settings has volume, window mode, a frame-rate cap and a frame-time counter. If something goes wrong, use
> **Settings → Export logs** and attach the folder it opens to a comment. Your user name is scrubbed from it and
> nothing is uploaded automatically.

## Minimum system requirements (description footer)

> - Windows 10 or 11, 64-bit
> - A graphics card with Vulkan or Direct3D 12 support
> - About 200 MB of disk space

These are the engine's requirements (Godot 4.7, Forward+ renderer), not a tested minimum. Replace them with the
lowest machine that has actually run the demo well once you know it.

## Screenshots and cover

- Cover image: 630 × 500 px (itch.io's recommended size). A close shot of UEN Second Opinion with the drive lit
  works well.
- 3 to 5 screenshots at 1920 × 1080: the 3D view mid-fight with beams on, the tactical plot, the damage-control card,
  the sensor camera, and the after-action report.
- Optional: a 30 to 60 second gameplay clip (YouTube or Vimeo link in the "Gameplay video" field).
