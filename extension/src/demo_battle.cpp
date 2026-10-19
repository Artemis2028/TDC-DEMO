#include "demo_battle.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

// Dictionary keys built once: turning a C string into a Godot String on every key of every call was most of
// get_ship's cost (about 60 keys, read several times a frame).
#define KEY(name) ([]() -> const String& { static const String k(name); return k; }())

DemoBattle::DemoBattle() { start(1, 0); }

// scenario / personality: 0.. = that value (0 = head-on / brawler, the old battle), -1 = pick from the seed.
// Anything else out of range falls back to 0.
void DemoBattle::start(int64_t seed, int64_t ship_class, int64_t scenario, int64_t personality) {
    auto useed = static_cast<std::uint64_t>(seed);
    tdc::Scenario sc = scenario < 0 ? tdc::pick_scenario(useed)
        : (scenario < static_cast<int64_t>(tdc::Scenario::Count) ? static_cast<tdc::Scenario>(scenario) : tdc::Scenario::HeadOn);
    tdc::Personality pe = personality < 0 ? tdc::pick_personality(useed)
        : (personality < static_cast<int64_t>(tdc::Personality::Count) ? static_cast<tdc::Personality>(personality) : tdc::Personality::Brawler);
    b_ = std::make_unique<tdc::Battle>(useed, static_cast<int>(ship_class), 120e3, sc, pe);
}
int64_t DemoBattle::get_scenario() const { return static_cast<int64_t>(b_->scenario()); }
int64_t DemoBattle::get_personality() const { return static_cast<int64_t>(b_->personality()); }
void DemoBattle::advance(double s) { b_->advance(s); }
void DemoBattle::set_speed(int64_t i) { b_->set_speed(static_cast<int>(i)); }
int64_t DemoBattle::get_speed() const { return b_->speed_index(); }
double DemoBattle::get_time() const { return b_->time(); }
double DemoBattle::get_fraction() const { return b_->fraction(); }
String DemoBattle::get_drop_reason() const { return String::utf8(b_->drop_reason().c_str()); }
int64_t DemoBattle::get_winner() const { return b_->winner(); }
bool DemoBattle::get_cruise_allowed() const { return b_->cruise_allowed(); }

void DemoBattle::set_weapons_free(bool f) { b_->set_weapons_free(0, f); }
void DemoBattle::set_armed(bool laser, bool on) { b_->set_armed(0, laser, on); }
void DemoBattle::set_turret_armed(int64_t k, bool on) { b_->set_turret_armed(0, static_cast<int>(k), on); }
void DemoBattle::set_target_turret(int64_t k) { b_->set_target_turret(0, static_cast<int>(k)); }
void DemoBattle::set_fire_mode(int64_t m, int64_t t) { b_->set_fire_mode(0, static_cast<tdc::FireMode>(m), static_cast<tdc::Sys>(t)); }
void DemoBattle::set_facing(int64_t f) { b_->set_facing(0, static_cast<tdc::Facing>(f)); }
void DemoBattle::set_roll(int64_t dir) { b_->set_roll(0, static_cast<int>(dir)); }
void DemoBattle::set_mark(int64_t sys, int64_t turret, int64_t mark) {
    if (sys < 0 || sys >= tdc::kSys || mark < 0 || mark > 2) return;
    b_->set_mark(0, static_cast<tdc::Sys>(sys), static_cast<int>(turret), static_cast<tdc::Mark>(mark));
}
void DemoBattle::set_burn(int64_t burn, double th) { b_->set_burn(0, static_cast<tdc::Burn>(burn), th); }
void DemoBattle::set_oms_strafe(int64_t dir) { b_->set_oms_strafe(0, static_cast<int>(dir)); }
void DemoBattle::set_radiators(bool e) { b_->set_radiators(0, e); }
bool DemoBattle::order_repair(int64_t s) { return b_->order_repair(0, static_cast<tdc::Sys>(s)); }
void DemoBattle::set_auto_repair(bool on) { b_->set_auto_repair(0, on); }
void DemoBattle::set_player_ai(bool on) { b_->set_ai(0, on); }

int64_t DemoBattle::ship_count() const { return static_cast<int64_t>(b_->ships().size()); }

Dictionary DemoBattle::get_ship(int64_t i) const {
    const tdc::Ship& s = b_->ships()[static_cast<std::size_t>(i)];
    Dictionary d;
    d[KEY("name")] = String::utf8(s.name.c_str());
    d[KEY("faction")] = String::utf8(s.cls.faction.c_str());
    d[KEY("side")] = s.side;
    d[KEY("pos")] = Vector2(static_cast<real_t>(s.pos.x / 1000), static_cast<real_t>(s.pos.y / 1000));
    d[KEY("vel")] = Vector2(static_cast<real_t>(s.vel.x), static_cast<real_t>(s.vel.y));
    d[KEY("heading")] = s.heading;
    d[KEY("heat")] = s.heat;
    d[KEY("crew")] = s.crew; d[KEY("crew_max")] = s.cls.crew;
    d[KEY("ammo")] = s.ammo; d[KEY("ammo_max")] = s.cls.ammo;
    d[KEY("gun")] = static_cast<int>(s.cls.gun);
    d[KEY("gun_cooldown")] = s.gun_cooldown; d[KEY("gun_reload")] = s.cls.gun_reload;
    d[KEY("laser_range")] = s.cls.laser_range; d[KEY("gun_range")] = (s.cls.gun == tdc::GunKind::None) ? 0.0 : s.cls.gun_range;
    PackedFloat64Array health, armor, armor_max, st, st_max;
    for (double v : s.health) health.push_back(v);
    for (int k = 0; k < tdc::kSec; ++k) { armor.push_back(s.armor[k]); armor_max.push_back(s.cls.armor[k]); st.push_back(s.structure[k]); st_max.push_back(s.cls.structure[k]); }
    PackedFloat64Array worst;
    for (int k = 0; k < tdc::kSec; ++k) worst.push_back(s.worst_panel(k));
    d[KEY("armor_worst")] = worst;   // thinnest panel per section: where a breach shows
    // what this ship's crew believes about its enemy: estimated health (rounded to 10) and its own kill marks
    PackedFloat64Array est, test;
    PackedInt32Array mk, tmk;
    for (double v : s.est) est.push_back(v);
    for (double v : s.turret_est) test.push_back(v);
    for (auto m : s.mark) mk.push_back(static_cast<int>(m));
    for (auto m : s.turret_mark) tmk.push_back(static_cast<int>(m));
    d[KEY("est")] = est; d[KEY("turret_est")] = test; d[KEY("mark")] = mk; d[KEY("turret_mark")] = tmk;
    d[KEY("health")] = health; d[KEY("armor")] = armor; d[KEY("armor_max")] = armor_max; d[KEY("structure")] = st; d[KEY("structure_max")] = st_max;
    d[KEY("hull")] = s.hull_fraction();
    d[KEY("radiators_extended")] = s.radiators_extended;
    d[KEY("laser_firing")] = s.laser_firing;
    PackedFloat64Array thp;
    Array tarm, tfire, tbear, taim;
    int foe = static_cast<int>(i) == 0 ? 1 : 0;
    for (int k = 0; k < tdc::kTurrets; ++k) {
        std::size_t u = static_cast<std::size_t>(k);
        thp.push_back(s.turret_hp[u]); tarm.push_back(s.turret_armed[u]); tfire.push_back(s.turret_firing[u]);
        tbear.push_back(b_->turret_bears(static_cast<int>(i), k, foe));
        const tdc::Vec3& a = s.turret_aim[u];   // ship axes: x along the nose, y to the right, z to the top
        taim.push_back(Vector3(static_cast<real_t>(a.n), static_cast<real_t>(a.r), static_cast<real_t>(a.u)));
    }
    d[KEY("turret_hp")] = thp; d[KEY("turret_armed")] = tarm; d[KEY("turret_firing")] = tfire; d[KEY("turret_bears")] = tbear; d[KEY("turret_aim")] = taim;
    d[KEY("ai_lateral")] = s.ai_lateral;
    d[KEY("roll")] = s.roll; d[KEY("roll_dir")] = s.roll_dir;
    d[KEY("burning")] = s.main_firing;
    d[KEY("oms")] = Vector2(static_cast<real_t>(s.oms_fwd), static_cast<real_t>(s.oms_left));
    d[KEY("oms_strafe")] = s.oms_strafe;
    d[KEY("target_turret")] = s.target_turret;
    d[KEY("out")] = s.out; d[KEY("out_reason")] = String::utf8(s.out_reason.c_str());
    d[KEY("weapons_free")] = s.weapons_free; d[KEY("laser_armed")] = s.laser_armed(); d[KEY("gun_armed")] = s.gun_armed;
    d[KEY("dv_left")] = s.dv_left; d[KEY("dv_max")] = s.cls.delta_v; d[KEY("overheated")] = s.overheated;
    d[KEY("laser_dps")] = s.cls.laser_dps; d[KEY("gun_damage")] = s.cls.gun_damage; d[KEY("fire_mode")] = static_cast<int>(s.fire_mode); d[KEY("target_sys")] = static_cast<int>(s.target_sys);
    d[KEY("facing")] = static_cast<int>(s.facing); d[KEY("burn")] = static_cast<int>(s.burn); d[KEY("throttle")] = s.throttle;
    d[KEY("auto_repair")] = s.auto_repair; d[KEY("teams")] = s.repair_teams();
    Array reps;
    for (const auto& r : s.repairs) { Dictionary rd; rd[KEY("sys")] = static_cast<int>(r.sys); rd[KEY("left")] = r.left; rd[KEY("total")] = r.total; reps.push_back(rd); }
    d[KEY("repairs")] = reps;
    return d;
}

double DemoBattle::get_range_km() const { return b_->range(0, 1) / 1000; }
double DemoBattle::get_closing() const { return b_->closing(0, 1); }
double DemoBattle::get_sensor_quality() const { return b_->sensor_quality(0, 1); }
double DemoBattle::get_hit_chance() const { return b_->hit_chance(0, 1); }
int64_t DemoBattle::event_count() const { return static_cast<int64_t>(b_->events().size()); }

Array DemoBattle::get_events(int64_t from) const {
    Array a;
    const auto& ev = b_->events();
    for (std::size_t k = static_cast<std::size_t>(from < 0 ? 0 : from); k < ev.size(); ++k) {
        Dictionary d;
        d[KEY("time")] = ev[k].time; d[KEY("ship")] = ev[k].ship;
        d[KEY("kind")] = String::utf8(ev[k].kind.c_str()); d[KEY("text")] = String::utf8(ev[k].text.c_str());
        d[KEY("real")] = ev[k].real;
        a.push_back(d);
    }
    return a;
}

Array DemoBattle::get_shots() const {
    Array a;
    for (const auto& s : b_->shots()) {
        Dictionary d;
        d[KEY("pos")] = Vector2(static_cast<real_t>(s.pos.x / 1000), static_cast<real_t>(s.pos.y / 1000));
        d[KEY("vel")] = Vector2(static_cast<real_t>(s.vel.x), static_cast<real_t>(s.vel.y));
        d[KEY("kind")] = static_cast<int>(s.kind);
        d[KEY("shooter")] = s.shooter;
        a.push_back(d);
    }
    return a;
}

void DemoBattle::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "seed", "ship_class", "scenario", "personality"), &DemoBattle::start, DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("get_scenario"), &DemoBattle::get_scenario);
    ClassDB::bind_method(D_METHOD("get_personality"), &DemoBattle::get_personality);
    ClassDB::bind_method(D_METHOD("advance", "real_seconds"), &DemoBattle::advance);
    ClassDB::bind_method(D_METHOD("set_speed", "index"), &DemoBattle::set_speed);
    ClassDB::bind_method(D_METHOD("get_speed"), &DemoBattle::get_speed);
    ClassDB::bind_method(D_METHOD("get_time"), &DemoBattle::get_time);
    ClassDB::bind_method(D_METHOD("get_fraction"), &DemoBattle::get_fraction);
    ClassDB::bind_method(D_METHOD("get_drop_reason"), &DemoBattle::get_drop_reason);
    ClassDB::bind_method(D_METHOD("get_winner"), &DemoBattle::get_winner);
    ClassDB::bind_method(D_METHOD("get_cruise_allowed"), &DemoBattle::get_cruise_allowed);
    ClassDB::bind_method(D_METHOD("set_weapons_free", "free"), &DemoBattle::set_weapons_free);
    ClassDB::bind_method(D_METHOD("set_armed", "laser", "on"), &DemoBattle::set_armed);
    ClassDB::bind_method(D_METHOD("set_turret_armed", "turret", "on"), &DemoBattle::set_turret_armed);
    ClassDB::bind_method(D_METHOD("set_target_turret", "turret"), &DemoBattle::set_target_turret);
    ClassDB::bind_method(D_METHOD("set_fire_mode", "mode", "target_sys"), &DemoBattle::set_fire_mode);
    ClassDB::bind_method(D_METHOD("set_facing", "facing"), &DemoBattle::set_facing);
    ClassDB::bind_method(D_METHOD("set_roll", "dir"), &DemoBattle::set_roll);
    ClassDB::bind_method(D_METHOD("set_mark", "sys", "turret", "mark"), &DemoBattle::set_mark);
    ClassDB::bind_method(D_METHOD("set_burn", "burn", "throttle"), &DemoBattle::set_burn);
    ClassDB::bind_method(D_METHOD("set_oms_strafe", "dir"), &DemoBattle::set_oms_strafe);
    ClassDB::bind_method(D_METHOD("set_radiators", "extended"), &DemoBattle::set_radiators);
    ClassDB::bind_method(D_METHOD("order_repair", "sys"), &DemoBattle::order_repair);
    ClassDB::bind_method(D_METHOD("set_auto_repair", "on"), &DemoBattle::set_auto_repair);
    ClassDB::bind_method(D_METHOD("set_player_ai", "on"), &DemoBattle::set_player_ai);
    ClassDB::bind_method(D_METHOD("ship_count"), &DemoBattle::ship_count);
    ClassDB::bind_method(D_METHOD("get_ship", "index"), &DemoBattle::get_ship);
    ClassDB::bind_method(D_METHOD("get_range_km"), &DemoBattle::get_range_km);
    ClassDB::bind_method(D_METHOD("get_closing"), &DemoBattle::get_closing);
    ClassDB::bind_method(D_METHOD("get_sensor_quality"), &DemoBattle::get_sensor_quality);
    ClassDB::bind_method(D_METHOD("get_hit_chance"), &DemoBattle::get_hit_chance);
    ClassDB::bind_method(D_METHOD("get_events", "from"), &DemoBattle::get_events);
    ClassDB::bind_method(D_METHOD("event_count"), &DemoBattle::event_count);
    ClassDB::bind_method(D_METHOD("get_shots"), &DemoBattle::get_shots);
}
