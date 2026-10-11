DAGGER — EARTH FUSION DESTROYER / 2300

Open Dagger_Earth_Destroyer.blend in Blender 4.3 or newer.
Scene units are meters; bow is negative X, magnetic nozzle is positive X.
The active camera is Hero three-quarter. True side and Bow axial inspection cameras are included.
Press Numpad 0 for camera view; Home frames visible objects in the viewport.
Collections separate hull/tanks, crew/shield, optics, drive, hot radiator wings,
service radiators, surface details and scene lighting.
Objects remain separate and editable. Wing and director root empties organize assemblies.
No folding or turret animation has been validated or authored.

Concept dimensions: approximately 187.7 m overall length with the enlarged
nose turret, 18 m maximum hull diameter. The prior hull/nozzle envelope was 180 m.
Four drive wings: each 100 m radial by 23.5839 m axial, total nominal
planform 9433.5476 m2; the small cassette gaps reduce actual fin surface slightly.
Long panel axes are perpendicular to the longitudinal hull X axis.
Roots at 9.5 m radius give an overall deployed extent of about 219 m.
Cold crew panels: two 40 m radial by 16.63125 m axial nominal planforms.
Hot service panels: two 40 m radial by 9.7 m axial nominal planforms.
Both smaller pairs now extend perpendicular to the hull, rooted at 9.5 m radius
near X = -42 m, separate from the main wings near X = +25 m.
Fin framing, view factors, mechanical load ratings and actual thermal performance
need engineering validation; this model is a visual blockout.

Framework reference: 2500 t loaded, 1000 t dry, 10 GW jet power,
200 kN at 100 km/s exhaust, one 10 MW laser source. The two former small side directors have been replaced
by one nose-mounted rounded 12 m turret housing with a provisional 5 m aperture.
Its optics, mass, gimbal loads and pointing performance need rebudgeting; the
earlier 1 m-aperture engagement figures no longer describe this turret.
These are fictional framework assumptions. A nose close-up camera is included.
Missile doors indicate locations, not a resolved magazine capacity or mass allocation.
Surface materials describe appearance only; candidate material properties have
not been imported or independently verified.

build_dagger.py recreates the model and renders dagger_preview.png:
blender -b --python build_dagger.py
Rendering uses CPU Cycles, 48 samples, no denoiser dependency.
