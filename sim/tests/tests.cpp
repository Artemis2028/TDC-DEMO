// Demo rules checks. Each test states the rule it holds the sim to.
#include "tdc/battle.hpp"

#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

using namespace tdc;

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("  FAIL %s:%d  %s\n", __FILE__, __LINE__, #cond); ++failures; } } while (0)

static std::vector<std::pair<const char*, std::function<void()>>>& registry() { static std::vector<std::pair<const char*, std::function<void()>>> r; return r; }
struct Reg { Reg(const char* n, std::function<void()> f) { registry().push_back({n, std::move(f)}); } };
#define TEST(name) static void name(); static Reg reg_##name(#name, name); static void name()

static Battle run(std::uint64_t seed, int cls, double seconds, std::function<void(Battle&)> each = nullptr) {
    Battle b(seed, cls);
    b.set_ai(0, true);   // AI flies the player's ship too
    while (b.time() < seconds && b.winner() < 0) { if (each) each(b); b.step(); }
    return b;
}

// Armour left on all of a section's panels together: a beam or round wears one panel, so section losses are summed.
static double panel_sum(const Ship& s, int sec) {
    double t = 0;
    for (double v : s.panels[static_cast<std::size_t>(sec)]) t += v;
    return t;
}

TEST(same_seed_same_battle) {
    // Determinism: identical seeds and orders give bit-identical states; different seeds differ once guns fire.
    auto a = run(7, 1, 300), b = run(7, 1, 300), c = run(8, 1, 300);
    CHECK(a.state_hash() == b.state_hash());
    CHECK(a.state_hash() != c.state_hash());
}

TEST(speed_does_not_change_the_battle) {
    // Speed only sets how many ticks run per real second.
    Battle slow(3, 0), fast(3, 0);
    slow.set_speed(2); fast.set_speed(5);
    while (fast.time() < 200) fast.advance(0.5);
    while (slow.time() < fast.time() - 1e-9) slow.advance(0.05);
    CHECK(std::fabs(slow.time() - fast.time()) < 1e-9);
    CHECK(slow.state_hash() == fast.state_hash());
}

TEST(laser_falls_off_with_range_squared) {
    // Inside laser range the nose armour burns at laser_dps x (0.5 + 0.5 EO quality); at twice the range, a quarter of that.
    for (double r : {100e3, 300e3}) {
        Battle b(1, 0, r);
        auto& me = const_cast<Ship&>(b.ships()[0]);
        auto& foe = const_cast<Ship&>(b.ships()[1]);
        foe.weapons_free = false; foe.burn = Burn::Off;
        // Turrets start on target (as after a few seconds of tracking), so all ten ticks below fire.
        for (int k = 0; k < kTurrets; ++k) me.turret_aim[static_cast<std::size_t>(k)] = b.turret_goal(0, k, 1);
        double q = b.sensor_quality(0, 1);
        double armor0 = panel_sum(foe, 0);
        for (int i = 0; i < 10; ++i) { foe.burn = Burn::Off; b.step(); }
        double fall = r <= me.cls.laser_range ? 1 : std::pow(me.cls.laser_range / r, 2);
        double expect = me.cls.laser_dps * fall * (0.5 + 0.5 * q) * 1.0;
        CHECK(std::fabs((armor0 - panel_sum(foe, 0)) - expect) < 0.02 * expect + 1e-9);
    }
}

TEST(heat_locks_weapons_until_cool) {
    // At 100 heat nothing fires until the radiators bring it below 70.
    Battle b(2, 0);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    me.heat = 100;
    me.radiators_extended = true;
    b.step();
    CHECK(!b.ships()[0].laser_firing);
    while (b.ships()[0].heat >= 70 && b.time() < 100) { b.step(); CHECK(!b.ships()[0].laser_firing); }
    b.step();
    CHECK(b.ships()[0].laser_firing);
}

TEST(repair_timer_varies_and_stays_in_bounds) {
    // A first repair takes base x (0.4 + 0.6 x damage) x (0.7..1.4); jobs on the same damage differ between seeds.
    std::vector<double> times;
    for (std::uint64_t seed = 1; seed <= 20; ++seed) {
        Battle b(seed, 0);
        auto& me = const_cast<Ship&>(b.ships()[0]);
        me.health[static_cast<int>(Sys::Sensors)] = 0;
        CHECK(b.order_repair(0, Sys::Sensors));
        double t = b.ships()[0].repairs[0].total;
        double base = me.cls.repair_base[static_cast<int>(Sys::Sensors)];
        CHECK(t >= base * 0.7 - 1e-9 && t <= base * 1.4 + 1e-9);
        times.push_back(t);
    }
    double lo = times[0], hi = times[0];
    for (double t : times) { lo = std::min(lo, t); hi = std::max(hi, t); }
    CHECK(hi - lo > 5);
}

TEST(repair_restores_to_sixty_and_teams_are_limited) {
    Battle b(4, 0);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    const_cast<Ship&>(b.ships()[1]).weapons_free = false;
    b.set_auto_repair(0, false);
    for (int s = 0; s < kSys; ++s) if (s != static_cast<int>(Sys::Gun)) me.health[s] = 10;
    me.turret_hp.fill(10);   // the Laser's health is the mean of its turrets
    int teams = me.repair_teams();   // 1 + 40/15 = 3
    CHECK(teams == 3);
    int ok = 0;
    for (Sys s : {Sys::Drive, Sys::Laser, Sys::Sensors, Sys::Radiators}) ok += b.order_repair(0, s);
    CHECK(ok == 3);
    while (!b.ships()[0].repairs.empty() && b.time() < 400) b.step();
    CHECK(b.ships()[0].health[static_cast<int>(Sys::Drive)] >= 60);
    CHECK(b.ships()[0].health[static_cast<int>(Sys::Radiators)] == 10);   // no team was free for it
}

TEST(cruise_only_out_of_weapon_range) {
    Battle near(1, 0, 120e3), far(1, 0, 600e3);
    near.set_speed(6); far.set_speed(6);
    CHECK(near.speed_index() == 5);
    CHECK(far.speed_index() == 6);
}

TEST(battles_end) {
    // AI against AI: every seed reaches a result within an hour of battle time, and neither side wins them all. The
    // balance target is no longer AI-vs-AI (see idle_player_loses_more_than_it_wins): the player's AI closes to 20 km
    // with auto fire control, which plays the Earth ships below their strength, so Earth wins only about a fifth.
    int earth = 0, mars = 0;
    for (std::uint64_t seed = 1; seed <= 10; ++seed)
        for (int cls : {0, 1}) {
            auto b = run(seed, cls, 3600);
            CHECK(b.winner() >= 0);
            (b.winner() == 0 ? earth : mars)++;
        }
    std::printf("  wins over 20 battles: player %d, frigate %d\n", earth, mars);
    CHECK(earth >= 2);
    CHECK(mars >= 2);
}

// ---------------------------------------------------------------- laser turrets

static Battle placed(double rel_bearing_deg, double roll = 0) {
    // Our ship at the origin pointing along +x, the enemy 100 km away at the given bearing (positive = to the left).
    Battle b(1, 0, 100e3);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    double a = rel_bearing_deg * 3.14159265358979323846 / 180;
    foe.pos = {100e3 * std::cos(a), 100e3 * std::sin(a)};
    me.heading = 0; me.roll = roll;
    // Turrets start already on target (as after a few seconds of tracking), so a single tick shows the beam.
    for (int k = 0; k < kTurrets; ++k) me.turret_aim[static_cast<std::size_t>(k)] = b.turret_goal(0, k, 1);
    return b;
}
static int bearing_count(const Battle& b) { int n = 0; for (int k = 0; k < kTurrets; ++k) n += b.turret_bears(0, k, 1); return n; }

TEST(turrets_all_bear_ahead_none_astern) {
    // Within 10 deg of the nose each turret's beam runs past the bow: all three bear. Within 10 deg of the stern the
    // drive is in the way: none bear. Just outside that, the turrets on the target's side bear again (they sit
    // between the radiator wings, so nothing else blocks them): 20 deg off the stern on the right, two do.
    for (double d : {0.0, 9.0, -9.0})
        CHECK(bearing_count(placed(d)) == 3);
    for (double d : {180.0, 175.0, -175.0})
        CHECK(bearing_count(placed(d)) == 0);
    CHECK(bearing_count(placed(-160.0)) == 2);
}

TEST(turrets_split_on_the_beam) {
    // Broadside with no roll: top-right (45 deg) and bottom-right (315) are 45 deg from the right side and bear on a
    // target there; top-left (135) is 135 deg from it, outside its 105 deg arc. On the left only top-left bears.
    Battle right = placed(-90), left = placed(90);
    CHECK(right.turret_bears(0, 0, 1) && !right.turret_bears(0, 1, 1) && right.turret_bears(0, 2, 1));
    CHECK(!left.turret_bears(0, 0, 1) && left.turret_bears(0, 1, 1) && !left.turret_bears(0, 2, 1));
}

TEST(rolling_brings_each_turret_round) {
    // Over a full roll each turret bears on a beam target for 210 of 360 degrees (its 105 deg half-arc each way),
    // and at least one turret always bears (3 x 210 deg covers the circle with overlap).
    for (int k = 0; k < kTurrets; ++k) {
        int on = 0, n = 3600;
        for (int i = 0; i < n; ++i) on += placed(90, 2 * 3.14159265358979323846 * i / n).turret_bears(0, k, 1);
        CHECK(std::fabs(on / double(n) - 210.0 / 360.0) < 0.002);
    }
    for (int i = 0; i < 360; ++i) CHECK(bearing_count(placed(90, 2 * 3.14159265358979323846 * i / 360)) >= 1);
}

TEST(turret_swings_at_30_deg_per_second) {
    // Stowed turrets point straight out, 90 deg from a target dead ahead. At 30 deg/s that is exactly 3.0 s of slew:
    // 3 deg per 0.1 s tick, so after 29 ticks each is still 3 deg off (over the 1 deg firing tolerance) and on the
    // 30th it is on target and fires. The target is 100 km off and motionless, so its bearing does not drift.
    Battle b = placed(0);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    foe.weapons_free = false; foe.burn = Burn::Off; foe.vel = {0, 0};
    me.vel = {0, 0};
    for (int k = 0; k < kTurrets; ++k)
        me.turret_aim[static_cast<std::size_t>(k)] = {0, std::cos(kTurretAngle[static_cast<std::size_t>(k)]), std::sin(kTurretAngle[static_cast<std::size_t>(k)])};
    for (int i = 0; i < 29; ++i) b.step();
    for (int k = 0; k < kTurrets; ++k) {
        CHECK(std::fabs(b.turret_error(0, k, 1) - 3 * 3.14159265358979323846 / 180) < 1e-9);
        CHECK(!b.ships()[0].turret_firing[static_cast<std::size_t>(k)]);
    }
    b.step();
    for (int k = 0; k < kTurrets; ++k) CHECK(b.ships()[0].turret_firing[static_cast<std::size_t>(k)]);
}

// Armour our beam takes off the enemy in one tick, with the enemy side-on or nose-on to us, rolling or not.
static double one_tick_burn(bool side_on, bool rolling) {
    Battle b = placed(0);                                   // enemy 100 km dead ahead, our turrets on target
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    foe.weapons_free = false; foe.burn = Burn::Off;
    foe.heading = side_on ? 3.14159265358979323846 / 2 : 3.14159265358979323846;   // we are abeam of it / ahead of it
    foe.facing = side_on ? Facing::Broadside : Facing::Nose;
    foe.ai_controlled = false;
    b.set_roll(1, rolling ? 1 : 0);
    int sec = side_on ? 1 : 0;
    double before = panel_sum(foe, sec);
    b.step();
    return before - panel_sum(b.ships()[1], sec);
}

TEST(rolling_spreads_the_beam_only_side_on) {
    // Side-on, a rolling target keeps turning the burn spot away: it takes 35 % of the beam. Nose-on the beam lands on
    // the nose cap, on the roll axis, so rolling changes nothing. Same geometry and sensor quality within each pair.
    double side = one_tick_burn(true, false), side_roll = one_tick_burn(true, true);
    double nose = one_tick_burn(false, false), nose_roll = one_tick_burn(false, true);
    CHECK(side > 0 && nose > 0);
    CHECK(std::fabs(side_roll - 0.35 * side) < 1e-9);
    CHECK(std::fabs(nose_roll - nose) < 1e-12);
}

TEST(rolling_keeps_the_nose_on_the_enemy) {
    // Rolling turns the ship about its own axis only: with the enemy dead ahead and the facing order "nose", the
    // heading stays on the enemy while the roll angle turns at 20 deg/s (0.35 rad/s: 3.5 rad in 10 s, wrapped).
    Battle b = placed(0);
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    foe.weapons_free = false; foe.burn = Burn::Off; foe.vel = {0, 0}; foe.ai_controlled = false;
    const_cast<Ship&>(b.ships()[0]).vel = {0, 0};
    b.set_roll(0, 1);
    for (int i = 0; i < 100; ++i) b.step();
    CHECK(std::fabs(b.ships()[0].heading) < 1e-12);
    CHECK(std::fabs(b.ships()[0].roll - (3.5 - 2 * 3.14159265358979323846)) < 1e-6);
}

TEST(turrets_hold_aim_through_a_broadside_roll) {
    // Rolling broadside turns the target around the ship's axis at the roll rate (20 deg/s), slower than the 30 deg/s
    // slew, so a turret keeps its aim; a turret coming into arc swings over before the one leaving drops out (the
    // arcs overlap). Over a full roll and a bit, some turret fires on every tick. Heat is held at zero so the
    // heat lock cannot interrupt the check.
    Battle b = placed(90);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    foe.weapons_free = false; foe.burn = Burn::Off; foe.vel = {0, 0};
    me.vel = {0, 0};
    b.set_facing(0, Facing::Broadside);
    b.set_roll(0, 1);
    double roll0 = me.roll;
    for (int i = 0; i < 200; ++i) {
        me.heat = 0;
        b.step();
        CHECK(b.ships()[0].laser_firing);
    }
    CHECK(std::fabs(b.ships()[0].roll - roll0) > 0.1);   // it really rolled
}

TEST(laser_power_is_shared_by_turrets) {
    // Nose on, all three turrets fire and together equal one laser_dps beam; on the beam, the bearing turrets give
    // their share: one of three on the left at no roll (top-left).
    for (double bearing : {0.0, 90.0}) {
        Battle b = placed(bearing);
        auto& foe = const_cast<Ship&>(b.ships()[1]);
        foe.weapons_free = false; foe.burn = Burn::Off;
        foe.heading = std::atan2(-foe.pos.y, -foe.pos.x);   // facing us: our beam lands on its nose armour
        double q = b.sensor_quality(0, 1);
        double before = panel_sum(foe, 0);
        b.step();
        double expect = b.ships()[0].cls.laser_dps * (bearing == 0 ? 1.0 : 1.0 / 3) * (0.5 + 0.5 * q) * Battle::kDt;
        CHECK(std::fabs((before - panel_sum(b.ships()[1], 0)) - expect) < 1e-9);
        int firing = 0;
        for (bool f : b.ships()[0].turret_firing) firing += f;
        CHECK(firing == (bearing == 0 ? 3 : 1));
    }
}

TEST(losing_a_turret_leaves_the_others) {
    // A knocked-out turret stops firing; the Laser system's health is the mean of the three, so the ship stays armed.
    Battle b = placed(0);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    const_cast<Ship&>(b.ships()[1]).weapons_free = false;
    me.turret_hp[1] = 0;
    b.set_armed(0, true, true);
    b.step();
    CHECK(b.ships()[0].turret_firing[0] && !b.ships()[0].turret_firing[1] && b.ships()[0].turret_firing[2]);
    me.turret_hp = {100, 0, 100};
    b.set_turret_armed(0, 2, false);
    b.step();
    CHECK(b.ships()[0].turret_firing[0] && !b.ships()[0].turret_firing[2]);   // safed turret holds fire
}

TEST(laser_repair_patches_the_worst_turret) {
    Battle b(5, 0);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    const_cast<Ship&>(b.ships()[1]).weapons_free = false;
    b.set_auto_repair(0, false);
    me.weapons_free = false;
    me.turret_hp = {80, 0, 40};
    CHECK(b.order_repair(0, Sys::Laser));
    while (!b.ships()[0].repairs.empty() && b.time() < 300) b.step();
    CHECK(b.ships()[0].turret_hp[0] == 80 && b.ships()[0].turret_hp[1] == 60 && b.ships()[0].turret_hp[2] == 40);
    // The next job goes to turret 3 (40 %), its first patch, so no 30 % slowdown yet even though turret 2 was patched:
    // base x (0.4 + 0.6 x damage) x (0.7..1.4).
    CHECK(b.order_repair(0, Sys::Laser));
    double t = b.ships()[0].repairs[0].total, base = me.cls.repair_base[static_cast<int>(Sys::Laser)];
    CHECK(t >= base * (0.4 + 0.6 * 0.6) * 0.7 - 1e-9 && t <= base * (0.4 + 0.6 * 0.6) * 1.4 + 1e-9);
}

// ---------------------------------------------------------------- manoeuvring

TEST(drive_pushes_along_the_nose_oms_does_the_rest) {
    // Nose on the enemy: closing uses the main drive (accel x throttle); a sideways or opening burn uses the OMS pods
    // at oms_accel and leaves the main drive dark, so the plume is only shown when it really fires.
    for (Burn bn : {Burn::Toward, Burn::Left, Burn::Away}) {
        Battle b(1, 0);
        auto& foe = const_cast<Ship&>(b.ships()[1]);
        foe.weapons_free = false; foe.ai_controlled = false;
        b.set_burn(0, bn, 1.0);
        b.step();
        const Ship& me = b.ships()[0];
        double a = me.vel.len() / Battle::kDt;
        bool main = bn == Burn::Toward;
        CHECK(me.main_firing == main);
        CHECK(std::fabs(a - (main ? me.cls.accel : me.cls.oms_accel)) < 1e-9);
        if (bn == Burn::Left) CHECK(std::fabs(me.oms_left - 1) < 1e-9 && std::fabs(me.oms_fwd) < 1e-9);
        if (bn == Burn::Away) CHECK(std::fabs(me.oms_fwd + 1) < 1e-9);
    }
}

TEST(picked_turret_is_hit_when_exposed) {
    // Aiming at a named enemy turret puts laser damage on it if it faces the shooter; nose on, all three do.
    Battle b = placed(0);
    auto& me = const_cast<Ship&>(b.ships()[0]);
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    foe.weapons_free = false;
    foe.heading = 3.14159265358979323846;
    foe.armor = {0, 0, 0};
    for (auto& sec : foe.panels) sec.fill(0);
    foe.structure[0] = 0;   // nose already shot through: the beam reaches the turrets amidships
    b.set_fire_mode(0, FireMode::Manual, Sys::Laser);
    b.set_target_turret(0, 2);
    for (int i = 0; i < 50; ++i) b.step();
    CHECK(foe.turret_hp[2] < 100 && foe.turret_hp[0] == 100 && foe.turret_hp[1] == 100);
    (void)me;
}

// ---------------------------------------------------------------- armour panels and damage assessment

TEST(a_beam_wears_only_the_panel_it_hits) {
    // Enemy side-on to us, its right side toward us, not rolling: our beam lands on its body's right panel (0) only;
    // the left panel (4) and the rest stay whole. Nose-on, the beam holds on the nose cap's centre panel only.
    for (bool side_on : {true, false}) {
        Battle b = placed(0);
        auto& foe = const_cast<Ship&>(b.ships()[1]);
        foe.weapons_free = false; foe.burn = Burn::Off; foe.ai_controlled = false; foe.vel = {0, 0};
        foe.heading = side_on ? -3.14159265358979323846 / 2 : 3.14159265358979323846;   // we are on its right / dead ahead
        foe.facing = side_on ? Facing::Broadside : Facing::Nose;
        const_cast<Ship&>(b.ships()[0]).vel = {0, 0};
        auto start = foe.panels;
        for (int i = 0; i < 20; ++i) b.step();
        int sec = side_on ? 1 : 0, hit = side_on ? 0 : kCentrePanel;
        for (int sct = 0; sct < kSec; ++sct)
            for (int pn = 0; pn < kPanels; ++pn) {
                double was = start[static_cast<std::size_t>(sct)][static_cast<std::size_t>(pn)];
                double now = b.ships()[1].panels[static_cast<std::size_t>(sct)][static_cast<std::size_t>(pn)];
                if (sct == sec && pn == hit) CHECK(now < was);
                else CHECK(now == was);
            }
    }
}

TEST(rolling_side_on_turns_fresh_panels_to_the_beam) {
    // Side-on and rolling at 20 deg/s, each 45 deg panel faces us for about 2.25 s: over 20 s of beam, at least five of
    // the body's eight panels have been burned, none of them all the way through (the roll also cuts the beam to 35 %).
    Battle b = placed(0);
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    foe.weapons_free = false; foe.burn = Burn::Off; foe.ai_controlled = false; foe.vel = {0, 0};
    foe.heading = -3.14159265358979323846 / 2;
    foe.facing = Facing::Broadside;
    const_cast<Ship&>(b.ships()[0]).vel = {0, 0};
    b.set_roll(1, 1);
    for (int i = 0; i < 200; ++i) { const_cast<Ship&>(b.ships()[0]).heat = 0; b.step(); }
    int worn = 0;
    for (int pn = 0; pn < 8; ++pn) {
        double v = b.ships()[1].panels[1][static_cast<std::size_t>(pn)];
        worn += v < b.ships()[1].cls.armor[1];
        CHECK(v > 0);
    }
    CHECK(worn >= 5);
}

TEST(enemy_kills_are_reported_as_probable_and_sometimes_wrongly) {
    // Over 40 AI battles, our crew reports some but not all of the enemy's real losses (30-90 % chance each, depending
    // on the EO track), always 2-8 s after the hit, and makes false calls too: every report reads "probable".
    int real = 0, called_real = 0, called_false = 0, bad_delay = 0, not_probable = 0;
    for (std::uint64_t seed = 1; seed <= 20; ++seed)
        for (int cls : {0, 1}) {
            auto b = run(seed, cls, 3600);
            for (const auto& e : b.events()) real += e.ship == 1 && e.kind == "disabled";
            for (const auto& a : b.reported_assessments()) {
                if (a.observer != 0) continue;
                (a.true_kill ? called_real : called_false)++;
                double d = a.due - a.made;
                bad_delay += d < 2.0 - 1e-9 || d > 8.0 + 1e-9;
                not_probable += a.text.find("probable") == std::string::npos;
            }
        }
    std::printf("  enemy losses %d, called %d, false calls %d\n", real, called_real, called_false);
    CHECK(real > 20);
    CHECK(called_real > 0.3 * real && called_real < 0.9 * real);
    CHECK(called_false > 0.05 * (called_real + called_false));
    CHECK(bad_delay == 0 && not_probable == 0);
}

TEST(assess_events_carry_the_reality_flag) {
    // The "assess" event's real flag (read by the after-action report, never shown in play) must equal the
    // assessment's true_kill, call for call, and no other kind of event may carry it.
    int assess = 0, real_n = 0, other_flagged = 0;
    for (std::uint64_t seed = 1; seed <= 6; ++seed) {
        auto b = run(seed, 0, 3600);
        std::vector<bool> ev_flags;
        for (const auto& e : b.events()) {
            if (e.kind == "assess") ev_flags.push_back(e.real); else other_flagged += e.real;
        }
        const auto& rep = b.reported_assessments();
        CHECK(ev_flags.size() == rep.size());
        // reported_ is filled in the same step order as the log
        for (std::size_t i = 0; i < rep.size() && i < ev_flags.size(); ++i) { CHECK(ev_flags[i] == rep[i].true_kill); real_n += rep[i].true_kill; }
        assess += static_cast<int>(rep.size());
    }
    CHECK(assess > 0 && real_n > 0 && real_n < assess);
    CHECK(other_flagged == 0);
}

TEST(enemy_health_is_an_estimate) {
    // Our crew's figures for the enemy are rounded to 10, within the read error of the truth (5 + 25 x (1 - track)
    // either way, plus 5 for the rounding), and held for 5 s between readings.
    Battle b = placed(0);
    auto& foe = const_cast<Ship&>(b.ships()[1]);
    foe.weapons_free = false; foe.burn = Burn::Off; foe.ai_controlled = false; foe.vel = {0, 0};
    const_cast<Ship&>(b.ships()[0]).weapons_free = false;   // nothing changes the truth while we look
    foe.health = {100, 70, 40, 90, 10, 55};
    double spread = 5.0 + 25.0 * (1.0 - b.sensor_quality(0, 1));
    b.step();
    auto first = b.ships()[0].est;
    for (int k = 0; k < kSys; ++k) {
        double e = first[static_cast<std::size_t>(k)];
        CHECK(std::fabs(e / 10.0 - std::round(e / 10.0)) < 1e-12);
        if (k != static_cast<int>(Sys::Gun)) CHECK(std::fabs(e - foe.health[static_cast<std::size_t>(k)]) <= spread + 5.0 + 1e-9);
    }
    for (int i = 0; i < 40; ++i) b.step();                       // 4 s later: same reading
    CHECK(b.ships()[0].est == first);
}

TEST(a_killed_mark_moves_auto_fire_control_on) {
    // Auto fire control goes for the enemy's lasers first. With all three turrets marked killed by our crew it moves on
    // to the gun, whether or not the marks are right (here they are wrong: the turrets are untouched).
    for (bool marked : {false, true}) {
        Battle b = placed(0);
        auto& foe = const_cast<Ship&>(b.ships()[1]);
        foe.weapons_free = false; foe.burn = Burn::Off; foe.ai_controlled = false;
        foe.heading = 3.14159265358979323846;
        for (auto& sec : foe.panels) sec.fill(0);
        foe.armor = {0, 0, 0};
        foe.structure[0] = 0;                                    // nose shot through: the beam reaches amidships
        if (marked) for (int k = 0; k < kTurrets; ++k) b.set_mark(0, Sys::Laser, k, Mark::Killed);
        for (int i = 0; i < 50; ++i) b.step();
        double turrets = foe.turret_hp[0] + foe.turret_hp[1] + foe.turret_hp[2];
        if (marked) CHECK(turrets == 300 && foe.health[static_cast<int>(Sys::Gun)] < 100);
        else CHECK(turrets < 300 && foe.health[static_cast<int>(Sys::Gun)] == 100);
    }
}

// ---------------------------------------------------------------- scenarios and personalities

static const double kPiT = 3.14159265358979323846;
static Battle& quiet(Battle& b) {
    // Both ships on weapons hold, the player's ship at rest and not flown by the AI: movement can be watched undisturbed.
    const_cast<Ship&>(b.ships()[0]).weapons_free = false;
    const_cast<Ship&>(b.ships()[1]).weapons_free = false;
    return b;
}
static std::string all_events(const Battle& b) { std::string t; for (const auto& e : b.events()) t += e.text + "\n"; return t; }

// Golden values first taken from the build before scenarios and personalities existed (state_hash then hashed only
// the physical state), and held through v0.11.1. Re-taken at v0.12.0, whose deliberate Earth laser retune changes
// every battle; the scenario code is unchanged, so they still pin HeadOn/Brawler against any accidental change. core_hash() is that same formula, so these compare directly; state_hash() now also mixes AI
// state (style, retreat/lateral flags, phase clock, broadside side) and is not comparable with them.
struct Golden { std::uint64_t seed; int cls; std::uint64_t hash; double t; int winner; };
static const Golden kGoldenRuns[] = {
    {1, 0, 0x8424a2da8ea2ce84ull, 1486.1, 0}, {1, 1, 0x86e1dbb7287299b8ull, 1597.6, 1},
    {2, 0, 0xda2658acd90af907ull, 1695.3, 1}, {2, 1, 0xcff6e44945d2a37aull, 994.8, 0},
    {3, 0, 0xf62a853abeb66721ull, 1933.9, 1}, {3, 1, 0x36db09bbb809a70eull, 982.9, 0},
};

TEST(headon_brawler_matches_the_pre_scenario_build) {
    // Whole AI-vs-AI battles, default arguments and explicit HeadOn/Brawler, against hashes from the old build.
    for (const Golden& g : kGoldenRuns)
        for (int explicit_args = 0; explicit_args < 2; ++explicit_args) {
            Battle b = explicit_args ? Battle(g.seed, g.cls, 120e3, Scenario::HeadOn, Personality::Brawler) : Battle(g.seed, g.cls);
            b.set_ai(0, true);
            while (b.time() < 3600 && b.winner() < 0) b.step();
            if (b.core_hash() != g.hash)
                std::printf("  golden seed %llu class %d: hash 0x%016llx, time %.1f, winner %d\n", static_cast<unsigned long long>(g.seed),
                            g.cls, static_cast<unsigned long long>(b.core_hash()), b.time(), b.winner());
            CHECK(b.core_hash() == g.hash);
            CHECK(std::fabs(b.time() - g.t) < 0.05 && b.winner() == g.winner);
        }
}

TEST(headon_brawler_matches_the_old_build_when_the_player_sideslips) {
    // The player burns left for 150 s (a sideways drift), then lets the AI fly. HeadOn and SternChase must not run the
    // Crossing scenario's drift-cancel logic, so this is the old behaviour exactly. Golden values as above (re-taken at v0.12.0).
    struct Slip { std::uint64_t seed; std::uint64_t hash; double t; int winner; };
    for (const Slip& g : {Slip{1, 0x8ab2f9687cc807d5ull, 1671.7, 1}, Slip{2, 0xfbd8157f10e651bdull, 1607.0, 1}}) {
        Battle b(g.seed, 0);
        b.set_burn(0, Burn::Left, 1);
        while (b.time() < 150) b.step();
        b.set_burn(0, Burn::Off, 1);
        b.set_ai(0, true);
        while (b.time() < 3600 && b.winner() < 0) b.step();
        if (b.core_hash() != g.hash)
            std::printf("  slip seed %llu: hash 0x%016llx, time %.1f, winner %d\n", static_cast<unsigned long long>(g.seed),
                        static_cast<unsigned long long>(b.core_hash()), b.time(), b.winner());
        CHECK(b.core_hash() == g.hash);
        CHECK(std::fabs(b.time() - g.t) < 0.05 && b.winner() == g.winner);
    }
}

TEST(headon_scenario_is_the_old_setup) {
    // Default arguments are HeadOn / Brawler and the setup is unchanged: both at rest, nose to nose, 120 km apart.
    Battle a(5, 0), b(5, 0, 120e3, Scenario::HeadOn, Personality::Brawler);
    CHECK(a.scenario() == Scenario::HeadOn && a.personality() == Personality::Brawler);
    CHECK(a.ships()[1].pos.x == 120e3 && a.ships()[1].pos.y == 0);
    CHECK(a.ships()[1].vel.len() == 0 && a.ships()[0].vel.len() == 0);
    CHECK(std::fabs(a.ships()[1].heading - kPiT) < 1e-12);
    for (int i = 0; i < 3000; ++i) { a.set_ai(0, true); b.set_ai(0, true); a.step(); b.step(); }
    CHECK(a.state_hash() == b.state_hash());
}

TEST(crossing_starts_mostly_sideways_to_the_line_of_sight) {
    // The frigate's velocity relative to the player is mostly perpendicular to the line of sight: at least 100 m/s
    // across and at most 40 m/s along (by construction exactly 40 m/s closing), which is under 40 % of the speed.
    int starboard = 0, port = 0;
    for (std::uint64_t seed = 1; seed <= 30; ++seed) {
        Battle b(seed, 0, 120e3, Scenario::Crossing);
        const Ship& p = b.ships()[0]; const Ship& f = b.ships()[1];
        Vec2 los = (f.pos - p.pos).norm();
        Vec2 rel = f.vel - p.vel;
        double along = dot(rel, los), across = std::fabs(rel.x * los.y - rel.y * los.x);
        CHECK(across >= 99.9 && across <= 160.1);
        CHECK(std::fabs(std::fabs(along) - 40.0) < 1e-6);
        CHECK(std::fabs(along) < 0.4 * rel.len());
        double ang = std::fabs(std::atan2(f.pos.y, f.pos.x)) * 180 / kPiT;
        CHECK(ang >= 19.99 && ang <= 40.01);   // off the bow
        CHECK(b.range(0, 1) > 90e3 && b.range(0, 1) < 120e3);
        // It crosses the bow: its sideways velocity points toward the player's axis, from the side it starts on.
        CHECK(f.pos.y * f.vel.y < 0);
        (f.pos.y < 0 ? starboard : port)++;
        CHECK(all_events(b).find(f.pos.y < 0 ? "starboard" : "port") != std::string::npos);
    }
    CHECK(starboard > 5 && port > 5);   // both sides occur
}

TEST(stern_chase_starts_with_the_player_blind_and_the_frigate_closing) {
    Battle b(3, 1, 120e3, Scenario::SternChase);
    const Ship& p = b.ships()[0]; const Ship& f = b.ships()[1];
    CHECK(f.pos.x < 0 && std::fabs(f.pos.y) < 1e-9);          // astern
    CHECK(b.closing(0, 1) >= 20 && b.closing(0, 1) <= 40);    // and closing
    for (int k = 0; k < kTurrets; ++k) CHECK(!b.turret_bears(0, k, 1));   // our nose points away: nothing bears on it
    CHECK(all_events(b).find("astern") != std::string::npos);
    // Flown by the AI, the player turns round and brings its turrets to bear within a minute.
    b.set_ai(0, true);
    bool bears = false;
    for (int i = 0; i < 600 && !bears; ++i) { b.step(); for (int k = 0; k < kTurrets; ++k) bears |= b.turret_bears(0, k, 1); }
    CHECK(bears);
    CHECK(b.time() < 60);                         // it happened within a minute
    while (b.time() < 90) b.step();
    CHECK(std::fabs(p.heading) > 2.8);            // the nose now points back along -x, toward the frigate
}

TEST(kiter_holds_its_standoff_while_the_player_sits_still) {
    // The player does nothing. A brawler would sit at 20 km; the kiter stops at 50 km instead and stays near it.
    for (Personality pe : {Personality::Brawler, Personality::Kiter}) {
        Battle b(4, 0, 120e3, Scenario::HeadOn, pe);
        quiet(b);
        double lo = 1e12, hi = 0;
        while (b.time() < 2400) {
            b.step();
            if (b.time() > 1500) { lo = std::min(lo, b.range(0, 1)); hi = std::max(hi, b.range(0, 1)); }
        }
        std::printf("  %s range over the last 900 s: %.1f - %.1f km\n", pe == Personality::Kiter ? "kiter" : "brawler", lo / 1e3, hi / 1e3);
        // The kiter's OMS fall-back overshoots a little inside its 50 km; the brawler's hold drifts a few km inside 20 km.
        if (pe == Personality::Kiter) CHECK(lo > 40e3 && hi < 55e3);
        else CHECK(lo > 12e3 && hi < 22e3);
    }
}

TEST(kiter_falls_back_when_the_player_closes_and_follows_when_it_opens) {
    // Player burns toward the frigate (pushing the range below the standoff): the kiter must open the range again
    // (its closing speed falls and it burns away); then the player stops and backs off: the kiter comes back in.
    Battle b(4, 0, 120e3, Scenario::HeadOn, Personality::Kiter);
    quiet(b);
    while (b.time() < 1200) b.step();                         // kiter now holding around 50 km
    CHECK(b.range(0, 1) < 60e3);
    double dv0 = b.ships()[1].dv_left;
    const_cast<Ship&>(b.ships()[0]).vel = {60, 0};            // the player lunges at it
    double rmin = 1e12;
    while (b.time() < 1500) { b.step(); rmin = std::min(rmin, b.range(0, 1)); }
    CHECK(b.ships()[1].dv_left < dv0 - 5);                    // it burned to get away
    CHECK(rmin > 25e3);                                       // and kept well clear of the brawler's 20 km
    const_cast<Ship&>(b.ships()[0]).vel = {-60, 0};           // the player runs
    Vec2 v0 = b.ships()[1].vel;
    while (b.time() < 2400) b.step();
    CHECK(b.ships()[1].vel.x < v0.x);                          // the kiter has gone after it (toward -x)
}

TEST(broadsider_turns_side_on_and_rolls_once_in_range) {
    Battle b(6, 0, 120e3, Scenario::HeadOn, Personality::Broadsider);
    quiet(b);
    const Ship& f = b.ships()[1];
    double reached = -1;
    for (int i = 0; i < 20000 && reached < 0; ++i) {
        b.step();
        CHECK((f.facing == Facing::Nose && f.roll_dir == 0) || b.range(0, 1) < 80e3);   // nose-on, not rolling while closing
        if (b.range(0, 1) < 40e3) reached = b.time();
    }
    CHECK(reached > 0);
    // From 30 s after reaching 40 km it turns side-on (square to the line of sight within 5 deg) and holds it for a
    // meaningful time (at least 8 s), rolling the whole time.
    double rolled = 0, prev_roll = f.roll, held = 0;
    bool nose_again = false, was_side = false;
    while (b.time() < reached + 400) {
        b.step();
        rolled += std::fabs(std::remainder(f.roll - prev_roll, 2 * kPiT)); prev_roll = f.roll;
        Vec2 to = (b.ships()[0].pos - f.pos).norm();
        double ang = std::fabs(std::fabs(std::remainder(f.heading - std::atan2(to.y, to.x), 2 * kPiT)) - kPiT / 2);
        if (b.time() < reached + 30) CHECK(f.facing == Facing::Nose);
        if (ang < 5 * kPiT / 180) { held += Battle::kDt; was_side = true; CHECK(f.roll_dir == 1); }
        if (was_side && f.facing == Facing::Nose) nose_again = true;
    }
    CHECK(was_side && held >= 8);
    CHECK(rolled > 0.35 * 300);       // 0.35 rad/s: well over 100 rad in 400 s means it rolled the whole time
    CHECK(nose_again);                // and went back nose-on for the railgun
}

TEST(brawler_behaviour_is_unchanged_in_the_default_setup) {
    // The player's own ship in watch mode is a brawler: it closes to 20 km nose-on and never rolls or turns away.
    Battle b(2, 0);
    quiet(b);
    b.set_ai(0, true);
    for (int i = 0; i < 20000; ++i) {
        b.step();
        CHECK(b.ships()[0].facing == Facing::Nose && b.ships()[0].roll_dir == 0);
        CHECK(b.ships()[1].facing == Facing::Nose && b.ships()[1].roll_dir == 0);
    }
    CHECK(b.range(0, 1) > 12e3 && b.range(0, 1) < 22e3);
    // And a full battle still matches the old build bit for bit (see headon_brawler_matches_the_pre_scenario_build).
    Battle g(1, 0);
    g.set_ai(0, true);
    while (g.time() < 3600 && g.winner() < 0) g.step();
    CHECK(g.core_hash() == 0x8424a2da8ea2ce84ull && std::fabs(g.time() - 1486.1) < 0.05);
}

TEST(crossing_drift_is_cancelled_then_the_range_closes) {
    // Weapons on hold, both ships AI-flown: the sideways speed across the line of sight falls under 25 m/s, then the
    // ships close to well inside their starting range.
    for (std::uint64_t seed : {1, 2, 3, 4}) {
        Battle b(seed, 0, 120e3, Scenario::Crossing);
        quiet(b);
        b.set_ai(0, true);
        const Ship& p = b.ships()[0]; const Ship& f = b.ships()[1];
        double settled = -1;
        bool lateral_flag = false;
        while (b.time() < 2400) {
            b.step();
            Vec2 los = (f.pos - p.pos).norm();
            Vec2 rel = f.vel - p.vel;
            lateral_flag |= f.ai_lateral;
            if (settled < 0 && std::fabs(rel.x * los.y - rel.y * los.x) < 25) settled = b.time();
        }
        CHECK(lateral_flag);                      // the AI really turned side-on to do it
        CHECK(settled > 0 && settled < 900);
        CHECK(b.range(0, 1) < 40e3);              // and then closed
        CHECK(!f.ai_lateral);                     // drift-cancel is over
    }
}

TEST(scenario_and_personality_runs_are_deterministic_and_distinct) {
    // Same seed, scenario and personality: bit-identical. Different personality or scenario: a different battle.
    std::vector<std::uint64_t> hashes;
    for (int sc = 0; sc < static_cast<int>(Scenario::Count); ++sc)
        for (int pe = 0; pe < static_cast<int>(Personality::Count); ++pe) {
            std::uint64_t h[2];
            for (int run_no = 0; run_no < 2; ++run_no) {
                // Weapons on hold, so every combination runs the full 2400 s and the personalities have time to show.
                Battle b(11, 1, 120e3, static_cast<Scenario>(sc), static_cast<Personality>(pe));
                quiet(b);
                b.set_ai(0, true);
                while (b.time() < 2400) b.step();
                h[run_no] = b.state_hash();
            }
            CHECK(h[0] == h[1]);
            hashes.push_back(h[0]);
        }
    for (std::size_t i = 0; i < hashes.size(); ++i)
        for (std::size_t j = i + 1; j < hashes.size(); ++j) CHECK(hashes[i] != hashes[j]);
}

TEST(picking_from_the_seed_is_stable_and_leaves_the_battle_alone) {
    int sc[3] = {0, 0, 0}, pe[3] = {0, 0, 0};
    for (std::uint64_t seed = 1; seed <= 300; ++seed) {
        CHECK(pick_scenario(seed) == pick_scenario(seed) && pick_personality(seed) == pick_personality(seed));
        sc[static_cast<int>(pick_scenario(seed))]++; pe[static_cast<int>(pick_personality(seed))]++;
    }
    for (int i = 0; i < 3; ++i) CHECK(sc[i] > 60 && pe[i] > 60);   // roughly a third each
    // Calling the pickers changes nothing about a battle built afterwards.
    Battle a(9, 0, 120e3, Scenario::Crossing, Personality::Kiter);
    (void)pick_scenario(9); (void)pick_personality(9);
    Battle b(9, 0, 120e3, Scenario::Crossing, Personality::Kiter);
    a.set_ai(0, true); b.set_ai(0, true);
    for (int i = 0; i < 2000; ++i) { a.step(); b.step(); }
    CHECK(a.state_hash() == b.state_hash());
}

TEST(opening_event_describes_the_situation_but_not_the_personality) {
    for (int sc = 0; sc < 3; ++sc)
        for (int pe = 0; pe < 3; ++pe) {
            Battle b(8, 0, 120e3, static_cast<Scenario>(sc), static_cast<Personality>(pe));
            b.set_ai(0, true);
            for (int i = 0; i < 6000; ++i) b.step();
            std::string t = all_events(b);
            for (const char* word : {"kiter", "Kiter", "brawl", "Brawl", "broadsider", "Broadsider", "personality", "standoff"})
                CHECK(t.find(word) == std::string::npos);
        }
    CHECK(all_events(Battle(8, 0, 120e3, Scenario::Crossing)).find("crossing from") != std::string::npos);
}

TEST(every_scenario_and_personality_ends) {
    for (int sc = 0; sc < 3; ++sc)
        for (int pe = 0; pe < 3; ++pe)
            for (std::uint64_t seed = 1; seed <= 4; ++seed) {
                Battle b(seed, static_cast<int>(seed % 2), 120e3, static_cast<Scenario>(sc), static_cast<Personality>(pe));
                b.set_ai(0, true);
                while (b.time() < 3600 && b.winner() < 0) b.step();
                CHECK(b.winner() >= 0);
            }
}

// ---------------------------------------------------------------- balance: the player's choices matter

// Every ship, start and enemy captain, `n` seeds each (720 battles at n = 40). `orders` runs every tick before the step.
// A battle still going after an hour counts as not won. A few wrecks slug it out past that (repairs keep bringing a
// shattered laser back), so up to 1 % may run long; the rest must end.
static double player_win_rate(int n, std::function<void(Battle&)> orders) {
    int won = 0, all = 0, long_runs = 0;
    for (int cls : {0, 1})
        for (int sc = 0; sc < static_cast<int>(Scenario::Count); ++sc)
            for (int pe = 0; pe < static_cast<int>(Personality::Count); ++pe)
                for (int s = 1; s <= n; ++s) {
                    Battle b(static_cast<std::uint64_t>(s) * 7919u + static_cast<std::uint64_t>(pe * 13 + sc * 101), cls, 120e3,
                             static_cast<Scenario>(sc), static_cast<Personality>(pe));
                    while (b.winner() < 0 && b.time() < 3600) { if (orders) orders(b); b.step(); }
                    long_runs += b.winner() < 0;
                    won += b.winner() == 0; ++all;
                }
    CHECK(long_runs <= all / 100);
    return static_cast<double>(won) / all;
}

TEST(idle_player_loses_more_than_it_wins) {
    // A player who gives no orders (weapons free, auto fire control and auto repair, as the battle starts) must lose
    // more often than not: the demo is about the player's decisions. v0.11.1 let an idle player win 83 %. Flying the
    // ship with one plain idea, holding the range at 125-145 km where the frigate's railgun (70 km) and laser (110 km)
    // can't answer the Earth laser (150 km), must beat sitting still clearly.
    double idle = player_win_rate(40, nullptr);
    double standoff = player_win_rate(40, [](Battle& b) {
        double r = b.range(0, 1), c = b.closing(0, 1);
        if (r < 125e3 && c > -5) b.set_burn(0, Burn::Away, 1);
        else if (r > 145e3 && c < 5) b.set_burn(0, Burn::Toward, 1);
        else if (b.ships()[0].burn != Burn::Off) b.set_burn(0, Burn::Off, 1);
    });
    std::printf("  player win rate over 720 battles each: idle %.0f %%, holding the range %.0f %%\n", idle * 100, standoff * 100);
    CHECK(idle < 0.5);
    CHECK(idle > 0.25);              // still winnable for a new player who fumbles
    CHECK(standoff > idle + 0.2);
}

int main() {
    for (auto& [name, fn] : registry()) { std::printf("%s\n", name); fn(); }
    std::printf(failures ? "%d FAILED\n" : "all passed\n", failures);
    return failures ? 1 : 0;
}
