#include "demo_battle.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

using namespace godot;

DemoBattle::DemoBattle() { start(1, 0); }

void DemoBattle::start(int64_t seed, int64_t ship_class) { b_ = std::make_unique<tdc::Battle>(static_cast<std::uint64_t>(seed), static_cast<int>(ship_class)); }
void DemoBattle::advance(double s) { b_->advance(s); }
void DemoBattle::set_speed(int64_t i) { b_->set_speed(static_cast<int>(i)); }
int64_t DemoBattle::get_speed() const { return b_->speed_index(); }
double DemoBattle::get_time() const { return b_->time(); }
String DemoBattle::get_drop_reason() const { return String::utf8(b_->drop_reason().c_str()); }
int64_t DemoBattle::get_winner() const { return b_->winner(); }
bool DemoBattle::get_cruise_allowed() const { return b_->cruise_allowed(); }

void DemoBattle::set_weapons_free(bool f) { b_->set_weapons_free(0, f); }
void DemoBattle::set_fire_mode(int64_t m, int64_t t) { b_->set_fire_mode(0, static_cast<tdc::FireMode>(m), static_cast<tdc::Sys>(t)); }
void DemoBattle::set_facing(int64_t f) { b_->set_facing(0, static_cast<tdc::Facing>(f)); }
void DemoBattle::set_burn(int64_t burn, double th) { b_->set_burn(0, static_cast<tdc::Burn>(burn), th); }
void DemoBattle::set_radiators(bool e) { b_->set_radiators(0, e); }
bool DemoBattle::order_repair(int64_t s) { return b_->order_repair(0, static_cast<tdc::Sys>(s)); }
void DemoBattle::set_auto_repair(bool on) { b_->set_auto_repair(0, on); }
void DemoBattle::set_player_ai(bool on) { b_->set_ai(0, on); }

int64_t DemoBattle::ship_count() const { return static_cast<int64_t>(b_->ships().size()); }

Dictionary DemoBattle::get_ship(int64_t i) const {
    const tdc::Ship& s = b_->ships()[static_cast<std::size_t>(i)];
    Dictionary d;
    d["name"] = String::utf8(s.name.c_str());
    d["faction"] = String::utf8(s.cls.faction.c_str());
    d["side"] = s.side;
    d["pos"] = Vector2(static_cast<real_t>(s.pos.x / 1000), static_cast<real_t>(s.pos.y / 1000));
    d["vel"] = Vector2(static_cast<real_t>(s.vel.x), static_cast<real_t>(s.vel.y));
    d["heading"] = s.heading;
    d["heat"] = s.heat;
    d["crew"] = s.crew; d["crew_max"] = s.cls.crew;
    d["ammo"] = s.ammo; d["ammo_max"] = s.cls.ammo;
    d["gun"] = static_cast<int>(s.cls.gun);
    d["gun_cooldown"] = s.gun_cooldown; d["gun_reload"] = s.cls.gun_reload;
    PackedFloat64Array health, armor, armor_max, st, st_max;
    for (double v : s.health) health.push_back(v);
    for (int k = 0; k < tdc::kSec; ++k) { armor.push_back(s.armor[k]); armor_max.push_back(s.cls.armor[k]); st.push_back(s.structure[k]); st_max.push_back(s.cls.structure[k]); }
    d["health"] = health; d["armor"] = armor; d["armor_max"] = armor_max; d["structure"] = st; d["structure_max"] = st_max;
    d["hull"] = s.hull_fraction();
    d["radiators_extended"] = s.radiators_extended;
    d["laser_firing"] = s.laser_firing;
    d["burning"] = s.burn != tdc::Burn::Off && s.alive_sys(tdc::Sys::Drive);
    d["out"] = s.out; d["out_reason"] = String::utf8(s.out_reason.c_str());
    d["weapons_free"] = s.weapons_free; d["fire_mode"] = static_cast<int>(s.fire_mode); d["target_sys"] = static_cast<int>(s.target_sys);
    d["facing"] = static_cast<int>(s.facing); d["burn"] = static_cast<int>(s.burn); d["throttle"] = s.throttle;
    d["auto_repair"] = s.auto_repair; d["teams"] = s.repair_teams();
    Array reps;
    for (const auto& r : s.repairs) { Dictionary rd; rd["sys"] = static_cast<int>(r.sys); rd["left"] = r.left; rd["total"] = r.total; reps.push_back(rd); }
    d["repairs"] = reps;
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
        d["time"] = ev[k].time; d["ship"] = ev[k].ship;
        d["kind"] = String::utf8(ev[k].kind.c_str()); d["text"] = String::utf8(ev[k].text.c_str());
        a.push_back(d);
    }
    return a;
}

Array DemoBattle::get_shots() const {
    Array a;
    for (const auto& s : b_->shots()) {
        Dictionary d;
        d["pos"] = Vector2(static_cast<real_t>(s.pos.x / 1000), static_cast<real_t>(s.pos.y / 1000));
        d["kind"] = static_cast<int>(s.kind);
        d["shooter"] = s.shooter;
        a.push_back(d);
    }
    return a;
}

void DemoBattle::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start", "seed", "ship_class"), &DemoBattle::start);
    ClassDB::bind_method(D_METHOD("advance", "real_seconds"), &DemoBattle::advance);
    ClassDB::bind_method(D_METHOD("set_speed", "index"), &DemoBattle::set_speed);
    ClassDB::bind_method(D_METHOD("get_speed"), &DemoBattle::get_speed);
    ClassDB::bind_method(D_METHOD("get_time"), &DemoBattle::get_time);
    ClassDB::bind_method(D_METHOD("get_drop_reason"), &DemoBattle::get_drop_reason);
    ClassDB::bind_method(D_METHOD("get_winner"), &DemoBattle::get_winner);
    ClassDB::bind_method(D_METHOD("get_cruise_allowed"), &DemoBattle::get_cruise_allowed);
    ClassDB::bind_method(D_METHOD("set_weapons_free", "free"), &DemoBattle::set_weapons_free);
    ClassDB::bind_method(D_METHOD("set_fire_mode", "mode", "target_sys"), &DemoBattle::set_fire_mode);
    ClassDB::bind_method(D_METHOD("set_facing", "facing"), &DemoBattle::set_facing);
    ClassDB::bind_method(D_METHOD("set_burn", "burn", "throttle"), &DemoBattle::set_burn);
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
