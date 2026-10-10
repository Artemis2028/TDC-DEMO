// TDC demo battle rules. Simplified, "gamified" rules for the public demo: hit points, damage per shot and heat bars,
// not the physics engine. Deterministic: the same seed and the same commands give the same battle.
#pragma once
#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace tdc {

struct Vec2 {
    double x = 0, y = 0;
    Vec2 operator+(Vec2 o) const { return {x + o.x, y + o.y}; }
    Vec2 operator-(Vec2 o) const { return {x - o.x, y - o.y}; }
    Vec2 operator*(double k) const { return {x * k, y * k}; }
    double len() const;
    Vec2 norm() const;
};
double dot(Vec2 a, Vec2 b);

/// Ship systems. Each sits in one hull section and has 0-100 health.
enum class Sys : int { Drive, Laser, Gun, Sensors, Radiators, Crew, Count };
constexpr int kSys = static_cast<int>(Sys::Count);
enum class Section : int { Nose, Body, Aft, Count };
constexpr int kSec = static_cast<int>(Section::Count);

enum class GunKind : int { None, Railgun, Coilgun };
enum class Facing : int { Nose, Broadside, Away };
enum class FireMode : int { Auto, Manual };
enum class Burn : int { Off, Toward, Away, Left, Right, Stop };

const char* sys_name(Sys s);
const char* section_name(Section s);

/// Tunable numbers for one class of ship (demo balance, not physics).
struct ShipClass {
    std::string name, faction;
    double accel = 0.3;          // m/s^2 at full throttle with a healthy drive
    double turn_rate = 0.03;     // rad/s
    std::array<double, kSec> armor{};      // armour points per section
    std::array<double, kSec> structure{};  // structure points per section
    std::array<Section, kSys> placed{};    // which section each system sits in
    double laser_dps = 0;        // damage per second inside laser_range
    double laser_range = 0;      // m: full damage inside, falls as (range/R)^2 beyond
    double laser_heat = 0;       // heat per second while firing
    GunKind gun = GunKind::None;
    double gun_damage = 0, gun_reload = 0, gun_speed = 0, gun_range = 0, gun_heat = 0;
    int ammo = 0;
    double drive_heat = 0;       // heat per second at full throttle
    double cool_extended = 0, cool_retracted = 0;  // heat removed per second
    int crew = 0;
    std::array<double, kSys> repair_base{};        // seconds for a team to repair a badly damaged system
};

ShipClass dagger_class();
ShipClass lance_class();
ShipClass frigate_class();

struct Repair {
    Sys sys;
    double left;   // seconds remaining
    double total;
};

struct Ship {
    int id = 0;
    std::string name;
    int side = 0;
    bool player = false;
    bool ai_controlled = false;   // AI flies it (enemy ships; the player's ship in watch mode and tests)
    ShipClass cls;
    Vec2 pos, vel;
    double heading = 0;           // radians, direction the nose points
    std::array<double, kSys> health{};
    std::array<double, kSec> armor{}, structure{};
    double heat = 0;              // 0-100; weapons lock at 100
    int crew = 0;
    int ammo = 0;
    double gun_cooldown = 0;
    bool radiators_extended = true;
    // orders
    bool weapons_free = true;
    FireMode fire_mode = FireMode::Auto;
    Sys target_sys = Sys::Laser;
    Facing facing = Facing::Nose;
    Burn burn = Burn::Off;
    double throttle = 1.0;
    bool auto_repair = false;
    std::vector<Repair> repairs;
    std::array<int, kSys> patches{};   // completed repairs per system
    // state
    bool laser_firing = false;
    bool out = false;
    std::string out_reason;
    double disarmed_for = 0;
    bool overheated = false;      // set at 100 heat, cleared below 70: weapons locked meanwhile
    bool holding_heat = false;    // AI heat discipline: laser held between 90 and 60

    int repair_teams() const;     // teams available in total (from crew)
    bool alive_sys(Sys s) const { return health[static_cast<int>(s)] > 0; }
    double hull_fraction() const;
};

struct Shot {
    int shooter, target;
    Vec2 pos, vel;
    double damage;
    Sys aim;
    bool hit;
    double impact_time;
    GunKind kind;
};

struct Event {
    double time;
    int ship;
    std::string kind;   // fire, hit, miss, burn-through, disabled, repair, overheat, order, out
    std::string text;
};

/// The battle: fixed 0.1 s ticks; speed only sets how many ticks run per real second.
class Battle {
public:
    static constexpr double kDt = 0.1;
    static constexpr std::array<double, 7> kSpeeds{0, 0.5, 1, 2, 5, 10, 50};  // 50x = cruise

    Battle(std::uint64_t seed, int player_class, double start_range_m = 120e3);

    // time
    void advance(double real_seconds);  // runs whole ticks at the current speed
    void step();                        // one tick
    double time() const { return time_; }
    int speed_index() const { return speed_; }
    void set_speed(int index);
    bool cruise_allowed() const;        // false while any enemy is inside weapon range
    std::string drop_reason() const { return drop_reason_; }

    // player orders (ship 0 is the player's)
    void set_weapons_free(int ship, bool free);
    void set_fire_mode(int ship, FireMode m, Sys target);
    void set_facing(int ship, Facing f);
    void set_burn(int ship, Burn b, double throttle);
    void set_radiators(int ship, bool extended);
    bool order_repair(int ship, Sys s);   // false if no team is free or nothing to repair
    void set_auto_repair(int ship, bool on);
    void set_ai(int ship, bool on) { ships_[ship].ai_controlled = on; }

    // state
    const std::vector<Ship>& ships() const { return ships_; }
    const std::vector<Shot>& shots() const { return shots_; }
    const std::vector<Event>& events() const { return events_; }
    double range(int a, int b) const;
    double closing(int a, int b) const;
    double sensor_quality(int ship, int target) const;  // 0-1: EO track quality
    double hit_chance(int ship, int target) const;      // for the HUD
    int winner() const { return winner_; }              // -1 while fighting
    std::uint64_t state_hash() const;

private:
    void ai(Ship& s);
    void auto_repair(Ship& s);
    void move(Ship& s);
    void fire(Ship& s);
    void land_shots();
    void heat(Ship& s);
    void repairs(Ship& s);
    void check_out(Ship& s);
    void damage(Ship& t, Sys aim, double amount, bool laser, int from);
    Section hit_section(const Ship& t, Sys aim, const Ship& from) const;
    int enemy_of(const Ship& s) const;
    double rnd();
    void log(int ship, const char* kind, std::string text);

    std::vector<Ship> ships_;
    std::vector<Shot> shots_;
    std::vector<Event> events_;
    std::uint64_t rng_;
    double time_ = 0, carry_ = 0;
    int speed_ = 2;
    std::string drop_reason_;
    int winner_ = -1;
};

}  // namespace tdc
