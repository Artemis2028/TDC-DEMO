# Demo movement vs the framework: what the drives actually support

11 October 2026. The demo's ship movement is gamified and stays that way for now (owner's decision). This note records how far it is from what the framework's technology supports, so the full game does not inherit the demo numbers by accident.

## Demo values (sim/src/battle.cpp)

| Ship | Acceleration | Turn rate | Roll rate | OMS | Δv |
| --- | --- | --- | --- | --- | --- |
| Dagger (Earth) | 0.42 m/s² (0.043 g), constant | 0.12 rad/s (7°/s; 90° in ~13 s) | 0.35 rad/s (20°/s) | 0.12 m/s² | 1,800 m/s |
| Lance (Earth) | 0.36 m/s² (0.037 g) | 0.10 rad/s | 0.35 rad/s | 0.12 m/s² | 1,800 m/s |
| Mars frigate | 0.49 m/s² (0.050 g) | 0.14 rad/s | 0.35 rad/s | 0.12 m/s² | 1,500 m/s |

None of these come from thrust, mass, exhaust velocity or propellant. Acceleration does not change as propellant burns.

## What the framework supports

Dagger as specified in the framework (A-01, G3 drive): 2,500 t loaded / 1,000 t dry, 500 t drive, 10 GW jet power at 0.05 kg/kW, exhaust velocity 100 km/s geared down to 40 km/s. Thrust F = 2P / vₑ [P].

| Drive setting | Thrust | Loaded (2,500 t) | Half propellant (~1,750 t) | Near dry (1,000 t) | Δv |
| --- | --- | --- | --- | --- | --- |
| 100 km/s | 200 kN | 0.008 g (0.08 m/s²) | 0.012 g (0.11 m/s²) | 0.020 g (0.20 m/s²) | 92 km/s |
| 40 km/s (combat gearing) | 500 kN | 0.020 g (0.20 m/s²) | 0.029 g (0.29 m/s²) | 0.051 g (0.50 m/s²) | 37 km/s |

Findings:

- **Acceleration: close.** The demo's 0.42 m/s² is what the Dagger reaches near dry at combat gearing. A mid-mission fight at half propellant gives about 0.29 m/s², 30 % lower. Not too slow to play.
- **Δv: about 20× too small in the demo.** 1.8 km/s against 37 km/s geared down (92 km/s at 100 km/s). In the full game ships should essentially never run dry inside one engagement; the limits are heat, mission reserve and propellant mass.
- **Turning: the biggest cheat.** Hull as a uniform rod: I = mL²/12 = 2.5e6 kg × (194 m)² / 12 ≈ 7.8e9 kg·m². Using the demo's own OMS thrust (0.12 m/s² × 2,500 t = 300 kN over 8 pods, 37.5 kN each) at the pod stations (10 % and 76.5 % of length; arms ≈ 77 m and 51 m): torque ≈ 19 MN·m, angular acceleration ≈ 2.5e-3 rad/s². A bang-bang 90° turn takes t = 2√(θ/α) ≈ **50 s** (peak 3.6°/s), against ~13 s in the demo. The framework does not yet specify RCS/OMS thrust, so this is an estimate on the demo's pod force, not a framework figure. Reaction wheels or CMGs cannot do it: 1°/s on this hull is ~1.4e8 N·m·s of stored momentum.
- **Roll: fine.** About the long axis I ≈ ½ m r² ≈ 6e7 kg·m² for a ~7 m radius (more with radiator wings out); the same pods reach 20°/s in roughly 15 s. Roll should spin up and down rather than start instantly.
- **Mars frigate: not defined in the framework.** The only Mars combatant there is the Bulwark cruiser (6,000 t, 30 GW pulsed, 150 km/s: 0.0068 → 0.020 g; about 0.020 → 0.061 g geared to 50 km/s). A frigate needs its own row before the full game uses one, e.g. ~2,000 t with a ~10 GW pulsed drive, landing in the same 0.02–0.05 g band. New assumption, not yet in the ledger.

## For the full game

1. Acceleration from F / m with propellant drained at dm/dt = F / vₑ, so ships speed up through a battle; show acceleration at loaded and current mass (framework mass-basis convention).
2. Drive gearing as a player control: 40–120 km/s at fixed jet power (A-19), trading thrust for Δv and heat.
3. Δv from the rocket equation, Δv = vₑ ln(m / m_dry), with the reserve rule (10–20 % plus a combat allowance).
4. Turn and roll rates from hull inertia and RCS/OMS torque, with spin-up and stop phases; RCS thrust per pod needs a sourced value and a ledger ID.
5. A Mars frigate row in the worked-example ships under A-01.

Label the demo "gamified; ship performance not representative of the final simulation".
