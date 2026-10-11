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
        double q = b.sensor_quality(0, 1);
        double armor0 = foe.armor[0];
        for (int i = 0; i < 10; ++i) { foe.burn = Burn::Off; b.step(); }
        double fall = r <= me.cls.laser_range ? 1 : std::pow(me.cls.laser_range / r, 2);
        double expect = me.cls.laser_dps * fall * (0.5 + 0.5 * q) * 1.0;
        CHECK(std::fabs((armor0 - foe.armor[0]) - expect) < 0.02 * expect + 1e-9);
    }
}

TEST(broadside_roll_cuts_laser_damage) {
    // A target rolling broadside takes 35 % of the beam.
    Battle a(1, 0), b(1, 0);
    for (auto* x : {&a, &b}) const_cast<Ship&>(x->ships()[1]).weapons_free = false;
    const_cast<Ship&>(b.ships()[1]).facing = Facing::Broadside;
    a.step(); b.step();
    double da = 120 - a.ships()[1].armor[0], db_body = 30 - b.ships()[1].armor[1];
    double db_nose = 80 - b.ships()[1].armor[0];
    CHECK(db_nose + db_body > 0);
    CHECK(std::fabs((db_nose + db_body) - 0.35 * (80 - a.ships()[1].armor[0])) < 1e-6 || std::fabs((db_nose + db_body) / (80 - a.ships()[1].armor[0]) - 0.35) < 1e-6);
    (void)da;
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
    // AI against AI: every seed reaches a result within an hour of battle time, and neither ship wins them all
    // (demo balance target: each player ship wins roughly 55-75 % of AI-flown battles).
    int earth = 0, mars = 0;
    for (std::uint64_t seed = 1; seed <= 10; ++seed)
        for (int cls : {0, 1}) {
            auto b = run(seed, cls, 3600);
            CHECK(b.winner() >= 0);
            (b.winner() == 0 ? earth : mars)++;
        }
    std::printf("  wins over 20 battles: player %d, frigate %d\n", earth, mars);
    CHECK(earth > mars);
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
    return b;
}
static int bearing_count(const Battle& b) { int n = 0; for (int k = 0; k < kTurrets; ++k) n += b.turret_bears(0, k, 1); return n; }

TEST(turrets_all_bear_near_the_axis) {
    // Within 10 deg of the nose or the stern each turret's beam runs past the hull lengthwise: all three bear.
    for (double d : {0.0, 9.0, -9.0, 175.0, 180.0})
        CHECK(bearing_count(placed(d)) == 3);
}

TEST(turrets_split_on_the_beam) {
    // Broadside with no roll: turrets at 45 and 290 deg face right (within 105 deg of 0 deg), the one at 165 faces left
    // (290 deg is 110 deg from the left side, just outside its arc).
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

TEST(laser_power_is_shared_by_turrets) {
    // Nose on, all three turrets fire and together equal one laser_dps beam; on the beam, the bearing turrets give
    // their share: one of three on the left at no roll.
    for (double bearing : {0.0, 90.0}) {
        Battle b = placed(bearing);
        auto& foe = const_cast<Ship&>(b.ships()[1]);
        foe.weapons_free = false; foe.burn = Burn::Off;
        foe.heading = std::atan2(-foe.pos.y, -foe.pos.x);   // facing us: our beam lands on its nose armour
        double q = b.sensor_quality(0, 1);
        double before = foe.armor[0];
        b.step();
        double expect = b.ships()[0].cls.laser_dps * (bearing == 0 ? 1.0 : 1.0 / 3) * (0.5 + 0.5 * q) * Battle::kDt;
        CHECK(std::fabs((before - b.ships()[1].armor[0]) - expect) < 1e-9);
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

int main() {
    for (auto& [name, fn] : registry()) { std::printf("%s\n", name); fn(); }
    std::printf(failures ? "%d FAILED\n" : "all passed\n", failures);
    return failures ? 1 : 0;
}
