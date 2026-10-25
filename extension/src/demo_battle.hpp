#pragma once
// One bridge, two builds. godot-cpp defines GDEXTENSION: that is the extension the editor loads (game/bin/). Without
// it this file is compiled into the engine by the module in modules/tdc_demo, which is how the exported game gets it.
#ifdef GDEXTENSION
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#else
#include "core/object/class_db.h"
#include "core/object/ref_counted.h"
#include "core/variant/variant.h"
#endif
#include <memory>

#include "tdc/battle.hpp"

namespace godot {

/// The demo battle as Godot sees it: orders in, state out. All rules live in the compiled sim.
class DemoBattle : public RefCounted {
    GDCLASS(DemoBattle, RefCounted)
    std::unique_ptr<tdc::Battle> b_;

protected:
    static void _bind_methods();

public:
    DemoBattle();
    /// scenario 0 head-on, 1 crossing, 2 stern chase; personality 0 brawler, 1 kiter, 2 broadsider; -1 picks from the seed.
    void start(int64_t seed, int64_t ship_class, int64_t scenario = 0, int64_t personality = 0);
    int64_t get_scenario() const;
    int64_t get_personality() const;
    void advance(double real_seconds);
    void set_speed(int64_t index);
    int64_t get_speed() const;
    double get_time() const;
    double get_fraction() const;
    String get_drop_reason() const;
    int64_t get_winner() const;
    bool get_cruise_allowed() const;

    void set_weapons_free(bool free);
    void set_armed(bool laser, bool on);
    void set_turret_armed(int64_t turret, bool on);
    void set_target_turret(int64_t turret);
    void set_fire_mode(int64_t mode, int64_t target_sys);
    void set_facing(int64_t facing);
    void set_roll(int64_t dir);
    void set_mark(int64_t sys, int64_t turret, int64_t mark);
    void set_burn(int64_t burn, double throttle);
    void set_oms_strafe(int64_t dir);
    void set_radiators(bool extended);
    bool order_repair(int64_t sys);
    void set_auto_repair(bool on);
    void set_player_ai(bool on);

    int64_t ship_count() const;
    Dictionary get_ship(int64_t i) const;
    double get_range_km() const;
    double get_closing() const;
    double get_sensor_quality() const;
    double get_hit_chance() const;
    Array get_events(int64_t from) const;
    int64_t event_count() const;
    Array get_shots() const;
};

}  // namespace godot
