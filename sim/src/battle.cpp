#include "tdc/battle.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace tdc {

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr double kRollRate = 0.35;         // rad/s (20 deg/s) while rolling: slower than the turrets' 30 deg/s slew so they hold aim through the roll
static_assert(kRollRate < kTurretSlew, "turrets must out-turn the roll or they lose aim");
constexpr double kTurretFragility = 3.0;   // each turret holds a third of the laser: the three together are as tough as one
double clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
std::string fmt(const char* f, double a) { char b[64]; std::snprintf(b, sizeof b, f, a); return b; }
double wrap(double a) { while (a > kPi) a -= 2 * kPi; while (a < -kPi) a += 2 * kPi; return a; }
double dot3(Vec3 a, Vec3 b) { return a.n * b.n + a.r * b.r + a.u * b.u; }
Vec3 add3(Vec3 a, Vec3 b, double ka, double kb) { return {a.n * ka + b.n * kb, a.r * ka + b.r * kb, a.u * ka + b.u * kb}; }
Vec3 unit3(Vec3 a) { double l = std::sqrt(dot3(a, a)); return l > 0 ? Vec3{a.n / l, a.r / l, a.u / l} : a; }
double angle3(Vec3 a, Vec3 b) { double c = dot3(a, b); return std::acos(c > 1 ? 1 : (c < -1 ? -1 : c)); }
/// Turn unit vector a toward unit vector b by at most `step` radians along the great circle between them.
Vec3 turn_toward(Vec3 a, Vec3 b, double step) {
    double ang = angle3(a, b);
    if (ang <= step) return b;
    double sn = std::sin(ang);
    if (sn < 1e-9) return a;   // exactly opposite: no unique path (cannot happen inside a turret's arc)
    return unit3(add3(a, b, std::sin(ang - step) / sn, std::sin(step) / sn));
}
/// Stowed direction of turret k: straight out from the hull at its mounting angle.
Vec3 mount(int k) { double t = kTurretAngle[static_cast<std::size_t>(k)]; return {0, std::cos(t), std::sin(t)}; }
}  // namespace

double Vec2::len() const { return std::sqrt(x * x + y * y); }
Vec2 Vec2::norm() const { double l = len(); return l > 0 ? Vec2{x / l, y / l} : Vec2{1, 0}; }
double dot(Vec2 a, Vec2 b) { return a.x * b.x + a.y * b.y; }

const char* sys_name(Sys s) {
    static const char* n[] = {"Drive", "Laser", "Gun", "Sensors", "Radiators", "Crew"};
    return n[static_cast<int>(s)];
}
const char* section_name(Section s) {
    static const char* n[] = {"nose", "body", "aft"};
    return n[static_cast<int>(s)];
}

// ---------------------------------------------------------------- ship classes (demo balance)

static ShipClass base_earth(const char* name) {
    ShipClass c;
    c.name = name; c.faction = "Earth";
    // accel m/s^2 and turn_rate rad/s: demo handling, raised so ships answer the helm (0.30 and 0.035 felt sluggish).
    // The fastest ship stays inside the setting's 0.005-0.05 g combat-drive band (0.05 g = 0.49 m/s^2).
    c.accel = 0.42; c.turn_rate = 0.12;
    c.armor = {120, 40, 30}; c.structure = {160, 220, 160};
    c.placed = {Section::Aft, Section::Body, Section::Body, Section::Nose, Section::Body, Section::Body};
    // laser_dps: demo balance, set so each Earth ship wins about 65 % of AI-vs-AI battles (100-seed sweeps with the AI
    // closing to 20 km, armour panels and fire control that believes the crew's kill marks: Dagger 2.15 -> 68 %,
    // Lance 1.22 -> 67 %). Balance tips sharply around these values. Not physical.
    c.laser_dps = 2.15; c.laser_range = 150e3; c.laser_heat = 2.2;
    c.drive_heat = 0.6; c.cool_extended = 2.7; c.cool_retracted = 0.6;
    c.crew = 40;
    c.repair_base = {60, 45, 50, 40, 35, 70};
    return c;
}

ShipClass dagger_class() { return base_earth("Dagger"); }

ShipClass lance_class() {
    ShipClass c = base_earth("Lance");
    c.accel = 0.36; c.turn_rate = 0.10;
    c.gun = GunKind::Coilgun;
    c.gun_damage = 46; c.gun_reload = 18; c.gun_speed = 12e3; c.gun_range = 100e3; c.gun_heat = 9;
    c.ammo = 60;
    c.laser_dps = 1.22;
    return c;
}

ShipClass frigate_class() {
    ShipClass c;
    c.name = "Mars frigate"; c.faction = "Mars";
    c.accel = 0.49; c.turn_rate = 0.14;
    c.armor = {80, 30, 30}; c.structure = {150, 200, 150};
    c.placed = {Section::Aft, Section::Body, Section::Body, Section::Nose, Section::Body, Section::Body};
    c.laser_dps = 0.9; c.laser_range = 110e3; c.laser_heat = 1.0;
    c.gun = GunKind::Railgun;
    c.gun_damage = 24; c.gun_reload = 10; c.gun_speed = 6e3; c.gun_range = 70e3; c.gun_heat = 3;
    c.ammo = 150;
    c.drive_heat = 0.5; c.cool_extended = 2.0; c.cool_retracted = 0.6;
    c.crew = 30;
    c.delta_v = 1500;
    c.repair_base = {55, 45, 45, 40, 35, 70};
    return c;
}

double Ship::repair_need(Sys s) const {
    if (s != Sys::Laser) return health[static_cast<int>(s)];
    return std::min({turret_hp[0], turret_hp[1], turret_hp[2]});
}

const char* panel_name(int panel) {
    static const char* n[] = {"right", "upper right", "top", "upper left", "left", "lower left", "bottom", "lower right", "centre"};
    return n[panel];
}

// A section's armour figure is the mean of its panels: eight around the hull, plus the centre on the nose and stern.
static void sync_armor(Ship& s) {
    for (int k = 0; k < kSec; ++k) {
        int n = k == static_cast<int>(Section::Body) ? kPanels - 1 : kPanels;
        double sum = 0;
        for (int i = 0; i < n; ++i) sum += s.panels[static_cast<std::size_t>(k)][static_cast<std::size_t>(i)];
        s.armor[static_cast<std::size_t>(k)] = sum / n;
    }
}

double Ship::worst_panel(int sec) const {
    int n = sec == static_cast<int>(Section::Body) ? kPanels - 1 : kPanels;
    double w = panels[static_cast<std::size_t>(sec)][0];
    for (int i = 1; i < n; ++i) w = std::min(w, panels[static_cast<std::size_t>(sec)][static_cast<std::size_t>(i)]);
    return w;
}

static void sync_laser(Ship& s) {
    s.health[static_cast<int>(Sys::Laser)] = (s.turret_hp[0] + s.turret_hp[1] + s.turret_hp[2]) / kTurrets;
}

int Ship::repair_teams() const { return crew <= 0 ? 0 : 1 + crew / 15; }
double Ship::hull_fraction() const {
    double now = 0, full = 0;
    for (int k = 0; k < kSec; ++k) { now += structure[k]; full += cls.structure[k]; }
    return full > 0 ? now / full : 0;
}

static Ship make_ship(int id, const ShipClass& c, int side, bool player, Vec2 pos, double heading) {
    Ship s;
    s.id = id; s.name = c.name; s.side = side; s.player = player; s.cls = c;
    s.pos = pos; s.heading = heading;
    s.health.fill(100);
    s.armor = c.armor; s.structure = c.structure;
    for (int k = 0; k < kSec; ++k) s.panels[static_cast<std::size_t>(k)].fill(c.armor[static_cast<std::size_t>(k)]);
    s.crew = c.crew; s.ammo = c.ammo; s.dv_left = c.delta_v;
    if (c.gun == GunKind::None) s.health[static_cast<int>(Sys::Gun)] = 0;
    for (int k = 0; k < kTurrets; ++k) s.turret_aim[static_cast<std::size_t>(k)] = mount(k);
    return s;
}

// ---------------------------------------------------------------- battle

Battle::Battle(std::uint64_t seed, int player_class, double start_range_m)
    : rng_(seed * 0x9E3779B97F4A7C15ull + 1), est_rng_(seed * 0xD1B54A32D192ED03ull + 7) {
    ShipClass mine = player_class == 1 ? lance_class() : dagger_class();
    ships_.push_back(make_ship(0, mine, 0, true, {0, 0}, 0));
    ships_.push_back(make_ship(1, frigate_class(), 1, false, {start_range_m, 0}, kPi));
    ships_[0].auto_repair = true;   // the player can switch it off and pick jobs by hand
    ships_[1].auto_repair = true;
    ships_[1].ai_controlled = true;
    ships_[1].fire_mode = FireMode::Auto;
    log(0, "order", "Battle stations. Enemy frigate at " + fmt("%.0f km", start_range_m / 1000));
}

double Battle::est_rnd() {
    est_rng_ ^= est_rng_ >> 12; est_rng_ ^= est_rng_ << 25; est_rng_ ^= est_rng_ >> 27;
    return static_cast<double>((est_rng_ * 2685821657736338717ull) >> 11) * (1.0 / 9007199254740992.0);
}

double Battle::rnd() {
    rng_ ^= rng_ >> 12; rng_ ^= rng_ << 25; rng_ ^= rng_ >> 27;
    return static_cast<double>((rng_ * 2685821657736338717ull) >> 11) * (1.0 / 9007199254740992.0);
}

void Battle::log(int ship, const char* kind, std::string text) { events_.push_back({time_, ship, kind, std::move(text)}); }

double Battle::range(int a, int b) const { return (ships_[b].pos - ships_[a].pos).len(); }
double Battle::closing(int a, int b) const {
    Vec2 u = (ships_[b].pos - ships_[a].pos).norm();
    return -dot(ships_[b].vel - ships_[a].vel, u);
}
int Battle::enemy_of(const Ship& s) const {
    for (const auto& o : ships_) if (o.side != s.side && !o.out) return o.id;
    return -1;
}

double Battle::sensor_quality(int ship, int target) const {
    // EO track quality: falls with range, scales with the sensors' health.
    const Ship& s = ships_[ship];
    double r = range(ship, target);
    double q = clamp01(1.25 - r / 200e3);
    return q * (0.25 + 0.75 * s.health[static_cast<int>(Sys::Sensors)] / 100.0);
}

double Battle::hit_chance(int ship, int target) const {
    const Ship& s = ships_[ship];
    if (s.cls.gun == GunKind::None) return 0;
    double r = range(ship, target);
    if (r > s.cls.gun_range) return 0;
    double base = s.cls.gun == GunKind::Coilgun ? 0.9 : 0.85;
    double p = base * (1 - 0.6 * (r / s.cls.gun_range) * (r / s.cls.gun_range)) * (0.4 + 0.6 * sensor_quality(ship, target));
    if (ships_[target].burn != Burn::Off) p *= 0.8;          // a burning target is harder to lead
    if (s.fire_mode == FireMode::Manual) p *= 0.85;           // aiming for one system, not the centre of mass
    return clamp01(p);
}

bool Battle::cruise_allowed() const {
    for (const auto& a : ships_)
        for (const auto& b : ships_) {
            if (a.side == b.side || a.out || b.out) continue;
            double reach = std::max(a.cls.laser_range, a.cls.gun_range);
            if (range(a.id, b.id) <= reach) return false;
        }
    return true;
}

void Battle::set_speed(int index) {
    index = std::clamp(index, 0, static_cast<int>(kSpeeds.size()) - 1);
    if (index == static_cast<int>(kSpeeds.size()) - 1 && !cruise_allowed()) { drop_reason_ = "Enemy in weapon range: combat speeds only"; index--; }
    else drop_reason_.clear();
    speed_ = index;
}

void Battle::advance(double real_seconds) {
    if (winner_ >= 0 || speed_ == 0 || real_seconds <= 0) return;
    carry_ += real_seconds * kSpeeds[speed_];
    int n = 0;
    while (carry_ >= kDt && n < 2000 && winner_ < 0) {
        if (speed_ == static_cast<int>(kSpeeds.size()) - 1 && !cruise_allowed()) {
            speed_ = 2; carry_ = 0; drop_reason_ = "Enemy in weapon range";
            log(0, "order", "Dropping to combat speed: enemy in weapon range");
            break;
        }
        step();
        carry_ -= kDt; ++n;
    }
    if (n >= 2000) carry_ = 0;
}

// ---------------------------------------------------------------- orders

void Battle::set_weapons_free(int ship, bool free) {
    ships_[ship].weapons_free = free;
    log(ship, "order", free ? "Weapons free" : "Weapons hold");
}
void Battle::set_armed(int ship, bool laser, bool on) {
    if (laser) ships_[ship].turret_armed.fill(on);
    else ships_[ship].gun_armed = on;
    log(ship, "order", std::string(laser ? "Lasers " : "Gun ") + (on ? "armed" : "safed"));
}
void Battle::set_turret_armed(int ship, int turret, bool on) {
    if (turret < 0 || turret >= kTurrets) return;
    ships_[ship].turret_armed[static_cast<std::size_t>(turret)] = on;
    log(ship, "order", fmt("Laser turret %.0f ", turret + 1) + (on ? "armed" : "safed"));
}

void Battle::set_target_turret(int ship, int turret) {
    ships_[ship].target_turret = turret < 0 || turret >= kTurrets ? -1 : turret;
}

bool Battle::turret_bears(int ship, int turret, int target) const {
    // The target lies in the battle plane. Seen from the ship it is ahead or astern by cos(rel) and off to the left or
    // right; no turret sees it dead astern (the drive is in the way), every turret sees it close ahead (the
    // beam clears the bow lengthwise), and otherwise a turret sees it if the side it is on lies within its arc. Rolling the ship turns every turret's outward direction by the roll angle.
    const Ship& s = ships_[ship];
    const Ship& t = ships_[target];
    double rel = wrap(std::atan2(t.pos.y - s.pos.y, t.pos.x - s.pos.x) - s.heading);
    if (std::cos(rel) <= -std::cos(kAftBlind)) return false;
    if (std::cos(rel) >= std::cos(kAxialClear)) return true;
    double side = std::sin(rel) > 0 ? kPi : 0.0;                 // left of the ship is 180 deg around the axis
    double out = kTurretAngle[static_cast<std::size_t>(turret)] + s.roll;
    return std::cos(out - side) >= std::cos(kTurretHalfArc);
}
namespace {
/// Direction from ship s to ship t in s's own axes. The target lies in the battle plane at relative bearing rel; its
/// sideways part points to the ship's right (0) or left (180 deg) around the axis, which the roll turns by -roll.
Vec3 target_dir(const Ship& s, const Ship& t) {
    double rel = std::atan2(t.pos.y - s.pos.y, t.pos.x - s.pos.x) - s.heading;
    double lat = std::fabs(std::sin(rel));
    double around = (std::sin(rel) > 0 ? kPi : 0.0) - s.roll;
    return {std::cos(rel), lat * std::cos(around), lat * std::sin(around)};
}
}  // namespace

Vec3 Battle::turret_goal(int ship, int turret, int target) const {
    const Ship& s = ships_[ship];
    std::size_t u = static_cast<std::size_t>(turret);
    if (target < 0 || !s.turret_armed[u]) return mount(turret);
    Vec3 t = target_dir(s, ships_[target]);
    if (turret_bears(ship, turret, target)) return t;
    // Out of arc: dead astern the turret stows; otherwise it waits at the edge of its arc nearest the target, so
    // it is already on target when the roll or a turn brings the target round.
    if (t.n <= -std::cos(kAftBlind)) return mount(turret);
    Vec3 m = mount(turret);
    double ang = angle3(m, t);
    return ang <= kTurretHalfArc ? t : turn_toward(m, t, kTurretHalfArc);
}

double Battle::turret_error(int ship, int turret, int target) const {
    return angle3(ships_[ship].turret_aim[static_cast<std::size_t>(turret)], target_dir(ships_[ship], ships_[target]));
}

void Battle::slew(Ship& s) {
    // Each working turret swings toward its goal at up to kTurretSlew; a knocked-out turret stays where it froze.
    int e = enemy_of(s);
    for (int k = 0; k < kTurrets; ++k) {
        std::size_t u = static_cast<std::size_t>(k);
        if (s.turret_hp[u] <= 0) continue;
        s.turret_aim[u] = turn_toward(s.turret_aim[u], turret_goal(s.id, k, e), kTurretSlew * kDt);
    }
}

void Battle::set_fire_mode(int ship, FireMode m, Sys target) {
    ships_[ship].fire_mode = m; ships_[ship].target_sys = target;
    log(ship, "order", m == FireMode::Auto ? "Fire control: auto" : std::string("Target: enemy ") + sys_name(target));
}
void Battle::set_facing(int ship, Facing f) {
    ships_[ship].facing = f;
    static const char* n[] = {"Nose to enemy", "Side to enemy", "Stern to enemy"};
    log(ship, "order", std::string("Facing: ") + n[static_cast<int>(f)]);
}
void Battle::set_roll(int ship, int dir) {
    dir = dir > 0 ? 1 : (dir < 0 ? -1 : 0);
    if (ships_[ship].roll_dir == dir) return;
    ships_[ship].roll_dir = dir;
    log(ship, "order", dir == 0 ? "Roll stopped" : "Rolling");
}
void Battle::set_burn(int ship, Burn b, double throttle) {
    ships_[ship].burn = b; ships_[ship].throttle = clamp01(throttle);
    static const char* n[] = {"Drive off", "Burn toward enemy", "Burn away", "Burn left", "Burn right", "Kill relative velocity"};
    log(ship, "order", n[static_cast<int>(b)]);
}
void Battle::set_radiators(int ship, bool extended) {
    ships_[ship].radiators_extended = extended;
    log(ship, "order", extended ? "Radiators extended" : "Radiators retracted");
}
void Battle::set_auto_repair(int ship, bool on) { ships_[ship].auto_repair = on; }

bool Battle::order_repair(int ship, Sys s) {
    Ship& sh = ships_[ship];
    int i = static_cast<int>(s);
    if (sh.out || sh.repair_need(s) >= 100 || (s == Sys::Gun && sh.cls.gun == GunKind::None)) return false;
    if (static_cast<int>(sh.repairs.size()) >= sh.repair_teams()) return false;
    for (const auto& r : sh.repairs) if (r.sys == s) return false;
    // Varying timer: worse damage takes longer, and every job runs 0.7-1.4x its estimate.
    // Each earlier patch on the same system makes the next one 30 % slower (less left to work with).
    // A laser job works on the worst turret alone. Each turret is a whole laser with its own optics and mount, so the
    // job takes as long as the old single-laser job did (demo balance: shorter turret jobs tipped AI battles 70/30
    // the other way in an 80-battle sweep). Slowdown from earlier patches counts per turret.
    int patches = sh.patches[i];
    if (s == Sys::Laser) {
        auto worst = std::min_element(sh.turret_hp.begin(), sh.turret_hp.end()) - sh.turret_hp.begin();
        patches = sh.turret_patches[static_cast<std::size_t>(worst)];
    }
    double t = sh.cls.repair_base[i] * (0.4 + 0.6 * (1 - sh.repair_need(s) / 100.0)) * (0.7 + 0.7 * rnd()) * (1 + 0.3 * patches);
    sh.repairs.push_back({s, t, t});
    log(ship, "repair", std::string("Repair team to ") + sys_name(s) + fmt(": about %.0f s", t));
    return true;
}

// ---------------------------------------------------------------- tick

void Battle::step() {
    if (winner_ >= 0) return;
    for (auto& s : ships_) if (!s.out && s.ai_controlled) ai(s);
    for (auto& s : ships_) if (!s.out) { if (s.auto_repair) auto_repair(s); update_estimates(s); move(s); slew(s); fire(s); heat(s); repairs(s); }
    land_shots();
    for (auto& s : ships_) if (!s.out) check_out(s);
    time_ += kDt;
    release_assessments();
    int alive0 = 0, alive1 = 0;
    for (const auto& s : ships_) if (!s.out) (s.side == 0 ? alive0 : alive1)++;
    if (alive0 == 0 || alive1 == 0) {
        winner_ = alive1 == 0 ? 0 : 1;
        log(-1, "out", winner_ == 0 ? "Victory: the enemy is out of action" : "Defeat: your ship is out of action");
    }
}

void Battle::ai(Ship& s) {
    int e = enemy_of(s);
    if (e < 0) return;
    double r = range(s.id, e);
    // Demo AI: press the attack. Close to 20 km, inside every weapon's full-power range, then hold there, so a fight
    // never stalls at long range with both sides' repairs keeping up. (A smarter AI comes later.)
    // Approach no faster than the OMS pods can brake from (the nose stays on the enemy, so braking is off the drive
    // axis): closing speed v with v^2 = 2 a d over the distance d left to the hold range, using 70 % of the pods'
    // acceleration as margin, capped at 150 m/s. Burn toward when slower than that, brake when faster.
    constexpr double kHold = 20e3;
    double c = closing(s.id, e);
    double want_c = r > kHold ? std::min(150.0, std::sqrt(2.0 * 0.7 * s.cls.oms_accel * (r - kHold))) : 0.0;
    Burn want = c < want_c - 5.0 ? Burn::Toward : (c > want_c + 5.0 ? Burn::Away : Burn::Off);
    if (want != s.burn) { s.burn = want; s.throttle = 1; }
    // Radiators out once heat builds, folded away only when nearly cold (they are a target while out).
    if (s.heat > 25) s.radiators_extended = true;
    else if (s.heat < 8) s.radiators_extended = false;
}

void Battle::auto_repair(Ship& s) {
    // Worst system first, as many jobs as there are free teams.
    while (static_cast<int>(s.repairs.size()) < s.repair_teams()) {
        int worst = -1; double h = 100;
        for (int k = 0; k < kSys; ++k) {
            if (k == static_cast<int>(Sys::Gun) && s.cls.gun == GunKind::None) continue;
            bool busy = false;
            for (const auto& rp : s.repairs) busy |= static_cast<int>(rp.sys) == k;
            double need = s.repair_need(static_cast<Sys>(k));
            if (!busy && need < h && need < 80) { h = need; worst = k; }
        }
        if (worst < 0 || !order_repair(s.id, static_cast<Sys>(worst))) break;
    }
}

void Battle::move(Ship& s) {
    int e = enemy_of(s);
    Vec2 to = e >= 0 ? (ships_[e].pos - s.pos).norm() : Vec2{1, 0};
    // Where the nose should point: facing order, or the burn direction while burning.
    double want = std::atan2(to.y, to.x);
    if (s.facing == Facing::Broadside) want += kPi / 2;
    if (s.facing == Facing::Away) want += kPi;
    Vec2 dir{0, 0};
    double drive = s.health[static_cast<int>(Sys::Drive)] / 100.0;
    if (s.burn != Burn::Off) {
        switch (s.burn) {
            case Burn::Toward: dir = to; break;
            case Burn::Away: dir = to * -1; break;
            case Burn::Left: dir = {-to.y, to.x}; break;
            case Burn::Right: dir = {to.y, -to.x}; break;
            case Burn::Stop: {
                Vec2 rel = e >= 0 ? s.vel - ships_[e].vel : s.vel;
                if (rel.len() < 0.5) { s.burn = Burn::Off; log(s.id, "order", "Relative velocity matched: drive off"); }
                else dir = rel.norm() * -1;
                break;
            }
            default: break;
        }
    }
    double turn = s.cls.turn_rate * (0.3 + 0.7 * drive) * kDt;
    double d = wrap(want - s.heading);
    s.heading = wrap(s.heading + std::clamp(d, -turn, turn));
    if (dir.len() > 0 && s.dv_left <= 0) {
        dir = {0, 0};
        if (s.burn != Burn::Off) { s.burn = Burn::Off; log(s.id, "order", s.name + ": propellant exhausted, drive off"); }
    }
    // The main drive only pushes along the nose. A burn within 30 deg of the nose uses it; anything else (sideways,
    // or backwards while the nose stays on the enemy) uses the OMS pods: far weaker, but the ship keeps its facing.
    s.main_firing = false;
    s.oms_fwd = s.oms_left = 0;
    if (dir.len() > 0) {
        Vec2 nose{std::cos(s.heading), std::sin(s.heading)};
        Vec2 left{-nose.y, nose.x};
        double a;
        if (dot(dir, nose) >= std::cos(kPi / 6) && drive > 0) {
            a = s.cls.accel * drive * s.throttle;
            s.heat += s.cls.drive_heat * s.throttle * kDt;
            s.main_firing = true;
        } else {
            a = s.cls.oms_accel * s.throttle;
            s.heat += s.cls.oms_heat * s.throttle * kDt;
            s.oms_fwd = dot(dir, nose);
            s.oms_left = dot(dir, left);
        }
        s.dv_left = std::max(0.0, s.dv_left - a * kDt);
        s.vel = s.vel + dir * (a * kDt);
    }
    s.pos = s.pos + s.vel * kDt;
    // Rolling turns the ship about its own axis only: the nose stays where the facing order points it.
    s.roll = wrap(s.roll + s.roll_dir * kRollRate * kDt);
}

Section Battle::hit_section(const Ship& t, Sys aim, const Ship& from) const {
    // Aimed shots go to the section holding the chosen system; otherwise the section facing the shooter.
    if (aim != Sys::Count) return t.cls.placed[static_cast<int>(aim)];
    Vec2 to = (from.pos - t.pos).norm();
    double rel = std::fabs(wrap(std::atan2(to.y, to.x) - t.heading));
    if (rel < kPi / 4) return Section::Nose;
    if (rel > 3 * kPi / 4) return Section::Aft;
    return Section::Body;
}

int Battle::hit_panel(const Ship& t, Section sec, const Ship& from, bool gun) {
    // Which panel the shot lands on. The shooter lies in the battle plane at relative bearing rel from the target; its
    // side of the hull is 0 deg (right) or 180 deg (left) around the axis, turned by the target's roll. Straight down the
    // nose or stern axis (within 10 deg) a beam holds on the centre of the cap; rounds land there 60 % of the time and
    // otherwise on a random ring panel. Off the axis, rounds scatter one panel either way half the time.
    double rel = wrap(std::atan2(from.pos.y - t.pos.y, from.pos.x - t.pos.x) - t.heading);
    bool end_on = sec != Section::Body && std::fabs(std::sin(rel)) < std::sin(0.17453292519943295);
    if (end_on) {
        if (!gun) return kCentrePanel;
        if (rnd() < 0.6) return kCentrePanel;
        return static_cast<int>(rnd() * 8) % 8;
    }
    double around = (std::sin(rel) > 0 ? kPi : 0.0) - t.roll;
    double a = around + kPi / 8;
    a -= 2 * kPi * std::floor(a / (2 * kPi));
    int panel = static_cast<int>(a / (kPi / 4)) % 8;
    if (gun) {
        double r = rnd();
        if (r < 0.25) panel = (panel + 7) % 8;
        else if (r > 0.75) panel = (panel + 1) % 8;
    }
    return panel;
}

void Battle::fire(Ship& s) {
    s.laser_firing = false;
    int e = enemy_of(s);
    if (s.heat >= 100) s.overheated = true;
    if (s.heat < 70) s.overheated = false;
    if (e < 0 || !s.weapons_free || s.overheated) return;
    if (s.ai_controlled) {
        if (s.heat > 90) s.holding_heat = true;
        if (s.heat < 60) s.holding_heat = false;
    } else s.holding_heat = false;
    Ship& t = ships_[e];
    double r = range(s.id, e);
    double q = sensor_quality(s.id, e);
    Sys aim = s.fire_mode == FireMode::Manual ? s.target_sys : Sys::Count;
    if (s.fire_mode == FireMode::Auto)
        // Auto fire control goes for whatever can still shoot back, then the drive, then the crew.
        for (Sys pick : {Sys::Laser, Sys::Gun, Sys::Drive, Sys::Crew})
            if (believed_alive(s, t, pick)) { aim = pick; break; }
    if (aim == Sys::Radiators && !t.radiators_extended) aim = Sys::Count;   // nothing outside to hit
    s.turret_firing.fill(false);
    if (r <= 3 * s.cls.laser_range && !s.holding_heat) {
        // The ship's laser power is shared by its three turrets: each gets a third, so all three bearing (nose or
        // stern on) match one full-power laser, and a broadside brings one or two. Heat follows the power used.
        double fall = r <= s.cls.laser_range ? 1.0 : (s.cls.laser_range / r) * (s.cls.laser_range / r);
        double dps = 0;
        for (int k = 0; k < kTurrets; ++k) {
            std::size_t u = static_cast<std::size_t>(k);
            if (!s.turret_armed[u] || s.turret_hp[u] <= 0 || !turret_bears(s.id, k, e)) continue;
            if (turret_error(s.id, k, e) > kOnTarget) continue;   // still swinging onto the target
            dps += s.cls.laser_dps / kTurrets * (s.turret_hp[u] / 100.0);
            s.heat += s.cls.laser_heat / kTurrets * kDt;
            s.turret_firing[u] = true;
            s.laser_firing = true;
        }
        dps *= fall * (0.5 + 0.5 * q);
        // A target rolling with its side to us keeps turning the burn spot away: 35 % of the beam stays on one
        // patch. Nose-on, the beam lands on the nose cap on the roll axis, so rolling does not move the spot.
        if (t.roll_dir != 0 && hit_section(t, Sys::Count, s) == Section::Body) dps *= 0.35;
        if (dps > 0) damage(t, aim, dps * kDt, true, s.id);
    }
    s.gun_cooldown = std::max(0.0, s.gun_cooldown - kDt);
    bool gun_bears = std::fabs(wrap(std::atan2(t.pos.y - s.pos.y, t.pos.x - s.pos.x) - s.heading)) < 0.05;
    if (s.gun_armed && s.alive_sys(Sys::Gun) && s.ammo > 0 && s.gun_cooldown <= 0 && r <= s.cls.gun_range && gun_bears) {
        double p = hit_chance(s.id, e);
        bool hit = rnd() < p;
        double speed = s.cls.gun_speed + std::max(0.0, closing(s.id, e));
        double flight = r / speed;
        Vec2 dir = (t.pos - s.pos).norm();
        shots_.push_back({s.id, e, s.pos, s.vel + dir * s.cls.gun_speed, s.cls.gun_damage, aim, hit, time_ + flight, s.cls.gun});
        s.ammo--; s.gun_cooldown = s.cls.gun_reload; s.heat += s.cls.gun_heat;
        log(s.id, "fire", std::string(s.cls.gun == GunKind::Coilgun ? "Coilgun" : "Railgun") + fmt(" fired: %.1f s flight", flight) + fmt(", %.0f %% to hit", p * 100));
    }
}

void Battle::land_shots() {
    for (std::size_t i = 0; i < shots_.size();) {
        Shot& sh = shots_[i];
        sh.pos = sh.pos + sh.vel * kDt;
        if (time_ + kDt >= sh.impact_time) {
            Ship& t = ships_[sh.target];
            if (!t.out) {
                if (sh.hit) damage(t, sh.aim, sh.damage, false, sh.shooter);
                else log(t.id, "miss", std::string(sh.kind == GunKind::Coilgun ? "Coilgun" : "Railgun") + " round missed " + t.name);
            }
            shots_.erase(shots_.begin() + static_cast<long>(i));
        } else ++i;
    }
}

void Battle::damage(Ship& t, Sys aim, double amount, bool laser, int from) {
    // Damage enters through the section facing the shooter and works inward: the outer armour first, then the section's
    // structure and systems; once a section's structure is gone, what is left carries on into the next section.
    Section entry = hit_section(t, Sys::Count, ships_[from]);
    int k = static_cast<int>(entry);
    int pi = hit_panel(t, entry, ships_[from], !laser);
    double& panel = t.panels[static_cast<std::size_t>(k)][static_cast<std::size_t>(pi)];
    double before = panel;
    double rem;
    if (laser) {
        // A beam has to burn the panel away before anything inside gets hurt.
        double used = std::min(panel, amount);
        panel -= used;
        rem = amount - used;
    } else {
        // A round loses half its damage to the panel while there is armour, and wears it down.
        double absorbed = std::min(panel, amount * 0.5);
        panel -= absorbed;
        rem = amount - absorbed;
    }
    sync_armor(t);
    if (before > 0 && panel <= 0) {
        log(t.id, "burn-through", std::string(laser ? "Beam" : "Rounds") + " through the " + section_name(entry) + " armour (" + panel_name(pi) + ") of " + t.name);
        // The flash of a breach can look like a kill: a chance of a false call on a system in that section.
        std::vector<int> inside;
        for (int s = 0; s < kSys; ++s) if (t.cls.placed[s] == entry && t.health[s] > 0) inside.push_back(s);
        if (!inside.empty()) assess(from, t, static_cast<Sys>(inside[static_cast<std::size_t>(rnd() * inside.size()) % inside.size()]), -1, false);
    }
    if (rem <= 0) {
        if (!laser) log(t.id, "hit", std::string("Hit on the ") + section_name(entry) + " of " + t.name + ": stopped by the armour");
        return;
    }
    std::vector<Section> path;
    if (entry == Section::Nose) path = {Section::Nose, Section::Body, Section::Aft};
    else if (entry == Section::Aft) path = {Section::Aft, Section::Body, Section::Nose};
    else path = {Section::Body};
    bool aimed = aim != Sys::Count && t.health[static_cast<int>(aim)] > 0;
    for (std::size_t p = 0; p < path.size() && rem > 0; ++p) {
        Section sec = path[p];
        int si = static_cast<int>(sec);
        if (t.structure[si] > 0) t.structure[si] = std::max(0.0, t.structure[si] - 0.5 * rem);
        bool aim_here = aimed && t.cls.placed[static_cast<int>(aim)] == sec;
        bool aim_deeper = false;
        for (std::size_t q = p + 1; q < path.size(); ++q) aim_deeper |= aimed && t.cls.placed[static_cast<int>(aim)] == path[q];
        if (aim_deeper && t.structure[si] <= 0) continue;          // an aimed shot carries on toward its system
        Sys victim = Sys::Count;
        if (aim_here) victim = aim;
        else {
            std::vector<Sys> here;
            for (int s = 0; s < kSys; ++s)
                if (t.cls.placed[s] == sec && t.health[s] > 0 && !(s == static_cast<int>(Sys::Radiators) && !t.radiators_extended)) here.push_back(static_cast<Sys>(s));
            if (!here.empty()) victim = here[static_cast<std::size_t>(rnd() * here.size()) % here.size()];
        }
        if (victim == Sys::Count) {
            if (t.structure[si] <= 0) continue;                    // nothing left here: on into the next section
            if (!laser) log(t.id, "hit", std::string("Hit on the ") + section_name(sec) + " of " + t.name);
            return;
        }
        int v = static_cast<int>(victim);
        double old = t.health[v];
        if (victim == Sys::Laser) {
            // One turret takes the hit: one of those facing the shooter (they are the ones exposed), else any.
            std::vector<int> exposed, alive;
            for (int k = 0; k < kTurrets; ++k) {
                if (t.turret_hp[static_cast<std::size_t>(k)] <= 0) continue;
                alive.push_back(k);
                if (turret_bears(t.id, k, from)) exposed.push_back(k);
            }
            const std::vector<int>& pool = exposed.empty() ? alive : exposed;
            int k = pool[static_cast<std::size_t>(rnd() * pool.size()) % pool.size()];
            // A turret picked by the shooter is hit if the shooter can see it (it faces the shooter).
            int want = ships_[from].target_turret;
            if (aim == Sys::Laser && want >= 0)
                for (int e : exposed) if (e == want) k = want;
            double& hp = t.turret_hp[static_cast<std::size_t>(k)];
            double was = hp;
            hp = std::max(0.0, hp - rem * kTurretFragility * (laser ? 1.0 : 0.8));
            sync_laser(t);
            if (!laser) log(t.id, "hit", std::string("Hit on ") + t.name + fmt(": laser turret %.0f", k + 1) + fmt(" at %.0f %%", hp));
            if (was > 0 && hp <= 0) {
                log(t.id, "disabled", t.name + fmt(": laser turret %.0f knocked out", k + 1));
                assess(from, t, Sys::Laser, k, true);
            } else if (!laser || (was > 50 && hp <= 50)) assess(from, t, Sys::Laser, k, false);
            return;
        }
        t.health[v] = std::max(0.0, t.health[v] - rem * (laser ? 1.0 : 0.8));
        if (victim == Sys::Crew) {
            int lost = static_cast<int>(std::round(t.crew * (old - t.health[v]) / 100.0));
            t.crew = std::max(0, t.crew - std::max(lost, laser ? 0 : 1));
        }
        if (!laser) log(t.id, "hit", std::string("Hit on ") + t.name + ": " + sys_name(victim) + fmt(" at %.0f %%", t.health[v]));
        if (old > 0 && t.health[v] <= 0) {
            log(t.id, "disabled", std::string(t.name) + ": " + sys_name(victim) + " knocked out");
            assess(from, t, victim, -1, true);
        } else if (!laser || (old > 50 && t.health[v] <= 50)) assess(from, t, victim, -1, false);
        return;
    }
}

// ---------------------------------------------------------------- estimates and marks

void Battle::update_estimates(Ship& s) {
    // Every 5 s the crew reads the enemy's state off the EO track: the true health plus an error that grows as the
    // track gets worse (spread +/-5 % with a perfect track, +/-30 % with none), rounded to 10. Uses its own random
    // stream, so the estimates never change how the battle goes. Demo rules (assumption, not a sensor model).
    if (time_ + 1e-9 < s.est_due) return;
    s.est_due = time_ + 5.0;
    int e = enemy_of(s);
    if (e < 0) return;
    const Ship& t = ships_[e];
    double spread = 5.0 + 25.0 * (1.0 - sensor_quality(s.id, e));
    auto read = [&](double truth) {
        double v = truth + spread * (2.0 * est_rnd() - 1.0);
        return std::clamp(std::round(v / 10.0) * 10.0, 0.0, 100.0);
    };
    for (int k = 0; k < kSys; ++k) s.est[static_cast<std::size_t>(k)] = read(t.health[static_cast<std::size_t>(k)]);
    for (int k = 0; k < kTurrets; ++k) s.turret_est[static_cast<std::size_t>(k)] = read(t.turret_hp[static_cast<std::size_t>(k)]);
    if (t.cls.gun == GunKind::None) s.est[static_cast<int>(Sys::Gun)] = 0;   // plainly no gun to see
    // The computer flying the player's ship takes a kill mark off again when the estimate shows the part working
    // (repaired, or a false call); a human player decides that for themselves.
    if (s.player && s.ai_controlled) {
        for (int k = 0; k < kSys; ++k)
            if (s.mark[static_cast<std::size_t>(k)] == Mark::Killed && s.est[static_cast<std::size_t>(k)] >= 40) s.mark[static_cast<std::size_t>(k)] = Mark::None;
        for (int k = 0; k < kTurrets; ++k)
            if (s.turret_mark[static_cast<std::size_t>(k)] == Mark::Killed && s.turret_est[static_cast<std::size_t>(k)] >= 40) s.turret_mark[static_cast<std::size_t>(k)] = Mark::None;
    }
}

void Battle::set_mark(int ship, Sys sys, int turret, Mark m) {
    Ship& s = ships_[ship];
    if (sys == Sys::Laser && turret >= 0 && turret < kTurrets) s.turret_mark[static_cast<std::size_t>(turret)] = m;
    else if (sys != Sys::Count) s.mark[static_cast<int>(sys)] = m;
}

bool Battle::believed_alive(const Ship& s, const Ship& t, Sys sys) const {
    // The AI's fire control knows the truth (demo simplification); the player's believes its crew's marks.
    if (!s.player) return t.alive_sys(sys) && !(sys == Sys::Gun && t.ammo <= 0);
    if (s.mark[static_cast<int>(sys)] == Mark::Killed) return false;
    if (sys == Sys::Laser) {
        for (Mark m : s.turret_mark) if (m != Mark::Killed) return true;
        return false;
    }
    if (sys == Sys::Gun && t.cls.gun == GunKind::None) return false;
    return true;
}

// ---------------------------------------------------------------- damage assessment

void Battle::assess(int observer, const Ship& target, Sys sys, int turret, bool real) {
    // The crew only sees the enemy through the EO track. A real kill is noticed with a chance that grows with track
    // quality (30 % with no track to 90 % with a perfect one), and only after watching for 2-8 s. Damage that killed
    // nothing (a round strike, an armour burn-through, a system burned past half) is sometimes called a kill anyway:
    // 2 % of the time with a perfect track, 20 % with none (about one report in seven is wrong in AI battles).
    // Demo rules (assumption, not a sensor model).
    double q = sensor_quality(observer, target.id);
    double p = real ? 0.3 + 0.6 * q : 0.02 + 0.18 * (1.0 - q);
    if (rnd() >= p) return;
    bool destroyed = turret >= 0;   // a turret is wrecked; a system is put out of action
    std::string name = destroyed ? fmt("laser turret %.0f", turret + 1) : sys_name(sys);
    for (auto& ch : name) ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    pending_.push_back({time_, time_ + 2.0 + 6.0 * rnd(), observer,
                        "Enemy " + name + (destroyed ? ": probable destroy" : ": probable disable"), real, sys, turret});
}

void Battle::release_assessments() {
    for (std::size_t i = 0; i < pending_.size();) {
        if (pending_[i].due <= time_ + 1e-9) {
            const Assessment& a = pending_[i];
            log(a.observer, "assess", a.text);
            // When the computer flies the player's ship (balance runs, watch mode) it trusts its crew like a sensible
            // player: a called kill gets marked killed. A human player makes the marks themselves.
            Ship& o = ships_[static_cast<std::size_t>(a.observer)];
            if (o.player && o.ai_controlled) set_mark(o.id, a.sys, a.turret, Mark::Killed);
            reported_.push_back(a);
            pending_.erase(pending_.begin() + static_cast<std::ptrdiff_t>(i));
        } else ++i;
    }
}

void Battle::heat(Ship& s) {
    double cool = (s.radiators_extended ? s.cls.cool_extended : s.cls.cool_retracted) * (0.2 + 0.8 * s.health[static_cast<int>(Sys::Radiators)] / 100.0);
    double before = s.heat;
    s.heat = std::max(0.0, s.heat - cool * kDt);
    if (s.heat > 100) {
        // Past the limit the cabin cooks: crew slowly lose effectiveness.
        if (rnd() < 0.02) { s.crew = std::max(0, s.crew - 1); }
        s.heat = std::min(s.heat, 130.0);
    }
    if (before < 100 && s.heat >= 100) log(s.id, "overheat", s.name + ": overheating, weapons locked until heat drops below 70");
}

void Battle::repairs(Ship& s) {
    // Teams lost with the crew drop their jobs, newest first.
    while (static_cast<int>(s.repairs.size()) > s.repair_teams()) {
        log(s.id, "repair", std::string("Repair of ") + sys_name(s.repairs.back().sys) + " abandoned: team lost");
        s.repairs.pop_back();
    }
    for (std::size_t i = 0; i < s.repairs.size();) {
        Repair& r = s.repairs[i];
        r.left -= kDt;
        if (r.left <= 0) {
            int k = static_cast<int>(r.sys);
            if (r.sys == Sys::Laser) {
                // The worst turret is the one the team was working on.
                auto worst = std::min_element(s.turret_hp.begin(), s.turret_hp.end());
                *worst = std::max(*worst, 60.0);
                s.turret_patches[static_cast<std::size_t>(worst - s.turret_hp.begin())]++;
                sync_laser(s);
            } else s.health[k] = std::max(s.health[k], 60.0);
            s.patches[k]++;
            log(s.id, "repair", s.name + ": " + sys_name(r.sys) + " patched to 60 %");
            s.repairs.erase(s.repairs.begin() + static_cast<long>(i));
        } else ++i;
    }
}

void Battle::check_out(Ship& s) {
    std::string why;
    if (s.crew <= 0) why = "crew lost";
    else if (s.hull_fraction() <= 0.05) why = "hull broken";
    bool armed = s.alive_sys(Sys::Laser) || (s.alive_sys(Sys::Gun) && s.ammo > 0);
    bool fixing = false;
    for (const auto& r : s.repairs) fixing |= r.sys == Sys::Laser || r.sys == Sys::Gun;
    s.disarmed_for = armed || fixing ? 0 : s.disarmed_for + kDt;
    if (why.empty() && s.disarmed_for >= 30) why = "no working weapons";
    if (!why.empty()) {
        s.out = true; s.out_reason = why;
        log(s.id, "out", s.name + " is out of action: " + why);
    }
}

std::uint64_t Battle::state_hash() const {
    std::uint64_t h = 1469598103934665603ull;
    auto mix = [&](double v) { std::uint64_t b; static_assert(sizeof b == sizeof v); std::memcpy(&b, &v, sizeof b); h = (h ^ b) * 1099511628211ull; };
    for (const auto& s : ships_) {
        mix(s.pos.x); mix(s.pos.y); mix(s.vel.x); mix(s.vel.y); mix(s.heading); mix(s.heat);
        for (double v : s.health) mix(v);
        for (double v : s.armor) mix(v);
        for (const auto& sec : s.panels) for (double v : sec) mix(v);
        for (double v : s.turret_hp) mix(v);
        for (const Vec3& a : s.turret_aim) { mix(a.n); mix(a.r); mix(a.u); }
        mix(s.roll); mix(s.roll_dir); mix(s.crew); mix(s.ammo);
    }
    mix(time_);
    return h;
}

}  // namespace tdc
