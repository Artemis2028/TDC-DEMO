#include "tdc/battle.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>

namespace tdc {

namespace {
constexpr double kPi = 3.14159265358979323846;
double clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
std::string fmt(const char* f, double a) { char b[64]; std::snprintf(b, sizeof b, f, a); return b; }
double wrap(double a) { while (a > kPi) a -= 2 * kPi; while (a < -kPi) a += 2 * kPi; return a; }
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
    c.accel = 0.30; c.turn_rate = 0.035;
    c.armor = {120, 40, 30}; c.structure = {160, 220, 160};
    c.placed = {Section::Aft, Section::Body, Section::Body, Section::Nose, Section::Body, Section::Body};
    c.laser_dps = 2.5; c.laser_range = 150e3; c.laser_heat = 2.2;
    c.drive_heat = 0.6; c.cool_extended = 2.7; c.cool_retracted = 0.6;
    c.crew = 40;
    c.repair_base = {60, 45, 50, 40, 35, 70};
    return c;
}

ShipClass dagger_class() { return base_earth("Dagger"); }

ShipClass lance_class() {
    ShipClass c = base_earth("Lance");
    c.accel = 0.26; c.turn_rate = 0.03;
    c.gun = GunKind::Coilgun;
    c.gun_damage = 46; c.gun_reload = 18; c.gun_speed = 12e3; c.gun_range = 100e3; c.gun_heat = 9;
    c.ammo = 60;
    c.laser_dps = 1.4;
    return c;
}

ShipClass frigate_class() {
    ShipClass c;
    c.name = "Mars frigate"; c.faction = "Mars";
    c.accel = 0.35; c.turn_rate = 0.04;
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
    s.crew = c.crew; s.ammo = c.ammo; s.dv_left = c.delta_v;
    if (c.gun == GunKind::None) s.health[static_cast<int>(Sys::Gun)] = 0;
    return s;
}

// ---------------------------------------------------------------- battle

Battle::Battle(std::uint64_t seed, int player_class, double start_range_m) : rng_(seed * 0x9E3779B97F4A7C15ull + 1) {
    ShipClass mine = player_class == 1 ? lance_class() : dagger_class();
    ships_.push_back(make_ship(0, mine, 0, true, {0, 0}, 0));
    ships_.push_back(make_ship(1, frigate_class(), 1, false, {start_range_m, 0}, kPi));
    ships_[0].auto_repair = true;   // the player can switch it off and pick jobs by hand
    ships_[1].auto_repair = true;
    ships_[1].ai_controlled = true;
    ships_[1].fire_mode = FireMode::Auto;
    log(0, "order", "Battle stations. Enemy frigate at " + fmt("%.0f km", start_range_m / 1000));
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
    (laser ? ships_[ship].laser_armed : ships_[ship].gun_armed) = on;
    log(ship, "order", std::string(laser ? "Laser " : "Gun ") + (on ? "armed" : "safed"));
}
void Battle::set_fire_mode(int ship, FireMode m, Sys target) {
    ships_[ship].fire_mode = m; ships_[ship].target_sys = target;
    log(ship, "order", m == FireMode::Auto ? "Fire control: auto" : std::string("Target: enemy ") + sys_name(target));
}
void Battle::set_facing(int ship, Facing f) {
    ships_[ship].facing = f;
    static const char* n[] = {"Nose to enemy", "Broadside, rolling", "Stern to enemy"};
    log(ship, "order", std::string("Facing: ") + n[static_cast<int>(f)]);
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
    if (sh.out || sh.health[i] >= 100 || (s == Sys::Gun && sh.cls.gun == GunKind::None)) return false;
    if (static_cast<int>(sh.repairs.size()) >= sh.repair_teams()) return false;
    for (const auto& r : sh.repairs) if (r.sys == s) return false;
    // Varying timer: worse damage takes longer, and every job runs 0.7-1.4x its estimate.
    // Each earlier patch on the same system makes the next one 30 % slower (less left to work with).
    double t = sh.cls.repair_base[i] * (0.4 + 0.6 * (1 - sh.health[i] / 100.0)) * (0.7 + 0.7 * rnd()) * (1 + 0.3 * sh.patches[i]);
    sh.repairs.push_back({s, t, t});
    log(ship, "repair", std::string("Repair team to ") + sys_name(s) + fmt(": about %.0f s", t));
    return true;
}

// ---------------------------------------------------------------- tick

void Battle::step() {
    if (winner_ >= 0) return;
    for (auto& s : ships_) if (!s.out && s.ai_controlled) ai(s);
    for (auto& s : ships_) if (!s.out) { if (s.auto_repair) auto_repair(s); move(s); fire(s); heat(s); repairs(s); }
    land_shots();
    for (auto& s : ships_) if (!s.out) check_out(s);
    time_ += kDt;
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
    // Close to 80 % of gun range (60 % of laser range without a gun), then hold the range.
    double hold = s.cls.gun != GunKind::None && s.alive_sys(Sys::Gun) && s.ammo > 0 ? 0.8 * s.cls.gun_range : 0.6 * s.cls.laser_range;
    Burn want = r > hold ? Burn::Toward : (closing(s.id, e) > 20 ? Burn::Stop : Burn::Off);
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
            if (!busy && s.health[k] < h && s.health[k] < 80) { h = s.health[k]; worst = k; }
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
    if (s.burn != Burn::Off && drive > 0) {
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
    if (dir.len() > 0) {
        double a = s.cls.accel * drive * s.throttle;
        s.dv_left = std::max(0.0, s.dv_left - a * kDt);
        s.vel = s.vel + dir * (a * kDt);
        s.heat += s.cls.drive_heat * s.throttle * kDt;
    }
    s.pos = s.pos + s.vel * kDt;
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
            if (t.alive_sys(pick) && !(pick == Sys::Gun && t.ammo <= 0)) { aim = pick; break; }
    if (aim == Sys::Radiators && !t.radiators_extended) aim = Sys::Count;   // nothing outside to hit
    bool rolling = s.facing == Facing::Broadside;

    if (s.laser_armed && s.alive_sys(Sys::Laser) && r <= 3 * s.cls.laser_range && !s.holding_heat) {
        double fall = r <= s.cls.laser_range ? 1.0 : (s.cls.laser_range / r) * (s.cls.laser_range / r);
        double dps = s.cls.laser_dps * fall * (s.health[static_cast<int>(Sys::Laser)] / 100.0) * (0.5 + 0.5 * q);
        if (rolling) dps *= 0.7;                                  // own hull blocks the turret part of each turn
        if (t.facing == Facing::Broadside) dps *= 0.35;           // the spot keeps turning away
        damage(t, aim, dps * kDt, true, s.id);
        s.heat += s.cls.laser_heat * kDt;
        s.laser_firing = true;
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
    double before = t.armor[k];
    double rem;
    if (laser) {
        // A beam has to burn the armour away before anything inside gets hurt.
        double used = std::min(t.armor[k], amount);
        t.armor[k] -= used;
        rem = amount - used;
    } else {
        // A round loses half its damage to the armour while there is armour, and wears it down.
        double absorbed = std::min(t.armor[k], amount * 0.5);
        t.armor[k] -= absorbed;
        rem = amount - absorbed;
    }
    if (before > 0 && t.armor[k] <= 0) log(t.id, "burn-through", std::string(laser ? "Beam" : "Rounds") + " through the " + section_name(entry) + " armour of " + t.name);
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
        t.health[v] = std::max(0.0, t.health[v] - rem * (laser ? 1.0 : 0.8));
        if (victim == Sys::Crew) {
            int lost = static_cast<int>(std::round(t.crew * (old - t.health[v]) / 100.0));
            t.crew = std::max(0, t.crew - std::max(lost, laser ? 0 : 1));
        }
        if (!laser) log(t.id, "hit", std::string("Hit on ") + t.name + ": " + sys_name(victim) + fmt(" at %.0f %%", t.health[v]));
        if (old > 0 && t.health[v] <= 0) log(t.id, "disabled", std::string(t.name) + ": " + sys_name(victim) + " knocked out");
        return;
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
            s.health[k] = std::max(s.health[k], 60.0);
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
        mix(s.crew); mix(s.ammo);
    }
    mix(time_);
    return h;
}

}  // namespace tdc
