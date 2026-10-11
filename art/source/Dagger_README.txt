DAGGER — EARTH FUSION DESTROYER / 2300

Open Dagger_Earth_Destroyer.blend in Blender 4.3 or newer.
Scene units are meters; bow is negative X, magnetic nozzle is positive X.
The active camera is Hero three-quarter. True side and Bow axial inspection cameras are included.
Press Numpad 0 for camera view; Home frames visible objects in the viewport.
Collections separate hull/tanks, crew/shield, optics, drive, hot radiator wings,
service radiators, surface details and scene lighting.
Objects remain separate and editable. Wing and director root empties organize assemblies.
No folding or turret animation has been validated or authored.

Concept dimensions: approximately 180 m overall length; 18 m maximum hull diameter.
Armored tapered bow. Two side-mounted 12 m laser housings, each with a provisional
5 m aperture, centered at X=-65 m and Y=+/-13 m. Both share the existing 10 MW source.
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
200 kN at 100 km/s exhaust. Two side-mounted directors replace the former nose
turret. Optical routing, gimbal travel, pointing, redundancy and mass need
rebudgeting. Side mounting does not establish protection from enemy fire.

OMS v3: eight hemispherical pods with one recessed gimballed bell per pod.
Four pods at X=-22 m and four at X=+8 m, in diagonal positions around the
18 m hull. Stations are 30 m apart and sit between the radiator root regions.
Fairings have 2.5 m radius and blend into the hull with slim mounting flanges.
Each nozzle has an editable empty named OMS steerable nozzle | local X-Y tilt.
Rotate its LOCAL X/Y axes within a provisional combined 10 degree cone; local Z
is nominal exhaust. No animation is authored. The geometry supports six-axis
control with steering; the neutral radial directions alone do not. Thrust,
propellant, gimbal actuators, moving clearances and plume heating need validation.
The 10 MW source remains shared by the two side laser directors.

Missile doors indicate locations, not a resolved magazine capacity or mass allocation.
Surface materials describe appearance only; candidate material properties have
not been imported or independently verified.

build_dagger.py recreates the model and renders dagger_preview.png:
blender -b --python build_dagger.py
Rendering uses CPU Cycles, 48 samples, no denoiser dependency.
