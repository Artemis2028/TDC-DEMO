class_name AAR
extends RefCounted
## After-action report: records a battle cheaply, then explains why it went the way it did.
##
## Usage: var a := AAR.new(); a.record(S0, S1, t, range_km, new_events) every frame; a.finish(battle) once at the end;
## then a.report (structured), a.as_text() (plain text) and a.export_text() (writes a .txt, returns the path).
##
## Recording cost: events are folded into counters as they arrive (a few dictionary reads each). The ship states are
## sampled on battle time, once per SAMPLE_DT seconds, into one flat PackedFloat32Array (COLS floats per sample, about
## 100 bytes), so a ten-minute battle is about 150 samples. Between samples a frame costs one time comparison plus two
## range/first-damage checks.
##
## Everything in the report comes from those samples and the event log. Damage is measured in "points": 1 point is 1 %
## of a ship's total armour + structure when the battle began. Hull is the structure fraction the sim reports.
## Posture is the true geometry (angle between the ship's heading and the line to the other ship), not the order given.

const SAMPLE_DT := 4.0
const SYS_NAMES := ["Drive", "Laser", "Gun", "Sensors", "Radiators", "Crew"]
const SEC_NAMES := ["nose", "body", "aft"]
const SCEN_NAMES := ["Head-on", "Crossing", "Stern chase"]
const STYLE_NAMES := ["a brawler: closed to knife range and slugged it out",
	"a kiter: held the range and backed off when you pressed",
	"a broadsider: turned side-on to bring every turret to bear"]
const POSTURE := ["nose-on", "side-on", "tail-on"]
const MAX_STORED := 600

# Column layout of one sample.
const C_T := 0
const C_H0 := 1       # hull (structure) fraction, us / them
const C_H1 := 2
const C_I0 := 3       # armour + structure fraction of the starting total
const C_I1 := 4
const C_S0 := 5       # armour + structure per section (absolute), us: 5,6,7
const C_S1 := 8       # them: 8,9,10
const C_ASP0 := 11    # aspect angle in degrees, 0 = nose toward the other ship, 180 = tail
const C_ASP1 := 12
const C_OH0 := 13     # weapons locked out by heat (0/1)
const C_OH1 := 14
const C_LF0 := 15     # a laser is firing (0/1)
const C_LF1 := 16
const C_RAD0 := 17    # radiators extended (0/1)
const C_REP0 := 18    # repair jobs running on our ship
const C_NEEDY0 := 19  # something on our ship is below 50 % (0/1)
const C_TEAMS0 := 20  # repair teams our crew can field
const C_HEAT0 := 21
const C_HEAT1 := 22
const C_ERR := 23     # mean |our crew's estimate - true health| over the enemy's six systems
const C_DEADMARK := 24 # enemy systems/turrets our crew marked dead that were really alive
const C_RNG := 25     # range to the other ship, km
const COLS := 26

var _s := PackedFloat32Array()
var _n := 0
var _last := -1.0e9
var _evcount := 0
var _secmax := [PackedFloat64Array(), PackedFloat64Array()]   # per ship, per section, armour + structure at the start
var _totmax := [1.0, 1.0]
var _first_dmg := [-1.0, -1.0]      # first time each ship (index) took damage
var _ev: Array = []                 # significant events kept for the timeline
var _bt_seen := {}                  # first burn-through per ship/section/weapon already stored
var _bt := [{}, {}]                 # burn-through counts by ship hit: "beam nose" -> n
var _fired := [0, 0]                # gun rounds fired by ship
var _missed := [0, 0]               # gun rounds that missed ship
var _stopped := [0, 0]              # gun hits on ship stopped by armour
var _gunhit_t := [PackedFloat32Array(), PackedFloat32Array()]  # times of damaging gun hits on ship
var _lock_count := [0, 0]
var _calls: Array = []              # crew damage calls checked against the truth
var _min_range := 1.0e9
var _min_range_t := 0.0
var _final0: Dictionary = {}
var _final1: Dictionary = {}
var _absent := [false, false, false, false, false, false]   # systems our ship never had (health 0 at the start)

# Results (valid after finish()).
var done := false
var winner := -1
var duration := 0.0
var scenario := 0
var personality := 0
var report := {}                    # {headline: Array[String], timeline: Array[Dictionary], insights: Array[Dictionary], notes: Array[String]}
var turning_t := -1.0
var end_t := 0.0
## Chart series for the view: time (s), hull and armour+hull fractions for both ships.
var chart_t := PackedFloat32Array()
var chart_h0 := PackedFloat32Array()
var chart_h1 := PackedFloat32Array()
var chart_i0 := PackedFloat32Array()
var chart_i1 := PackedFloat32Array()

# ------------------------------------------------------------------ recording

## Called every frame with our ship (s0), the enemy (s1), battle time, range in km and the events logged since the last call.
func record(s0: Dictionary, s1: Dictionary, t: float, range_km: float, evs: Array = []) -> void:
	if done:
		return
	if _secmax[0].is_empty():
		_init_max(s0, s1)
	for e in evs:
		_on_event(e, s0, s1)
	_evcount += evs.size()
	if range_km < _min_range:
		_min_range = range_km
		_min_range_t = t
	if _first_dmg[0] < 0.0 or _first_dmg[1] < 0.0:
		_watch_first(s0, s1, t)
	if t - _last >= SAMPLE_DT:
		_sample(s0, s1, t)

## Called once when the battle is over: takes the last sample, reads any events not yet seen and builds the report.
func finish(battle: Object) -> void:
	if done:
		return
	var s0: Dictionary = battle.get_ship(0)
	var s1: Dictionary = battle.get_ship(1)
	var t: float = battle.get_time()
	if _secmax[0].is_empty():
		_init_max(s0, s1)
	for e in battle.get_events(_evcount):
		_on_event(e, s0, s1)
		_evcount += 1
	if t - _last > 0.01:
		_sample(s0, s1, t)
	_final0 = s0
	_final1 = s1
	winner = battle.get_winner()
	duration = t
	end_t = t
	scenario = battle.get_scenario()
	personality = battle.get_personality()
	done = true
	_build()

func _init_max(s0: Dictionary, s1: Dictionary) -> void:
	var ships := [s0, s1]
	for i in 2:
		var a: PackedFloat64Array = ships[i]["armor_max"]
		var st: PackedFloat64Array = ships[i]["structure_max"]
		var m := PackedFloat64Array()
		var tot := 0.0
		for k in 3:
			m.append(a[k] + st[k])
			tot += a[k] + st[k]
		_secmax[i] = m
		_totmax[i] = maxf(tot, 1.0)
	var h: PackedFloat64Array = s0["health"]
	for k in 6:
		_absent[k] = h[k] <= 0.0

func _integ(s: Dictionary, i: int) -> float:
	var a: PackedFloat64Array = s["armor"]
	var st: PackedFloat64Array = s["structure"]
	var tot := 0.0
	for k in 3:
		tot += a[k] + st[k]
	return tot / _totmax[i]

func _watch_first(s0: Dictionary, s1: Dictionary, t: float) -> void:
	if _first_dmg[0] < 0.0 and _integ(s0, 0) < 0.9999:
		_first_dmg[0] = t
	if _first_dmg[1] < 0.0 and _integ(s1, 1) < 0.9999:
		_first_dmg[1] = t

func _aspect(a: Dictionary, b: Dictionary) -> float:
	var d: Vector2 = Vector2(b["pos"]) - Vector2(a["pos"])
	return absf(rad_to_deg(angle_difference(float(a["heading"]), atan2(d.y, d.x))))

func _sample(s0: Dictionary, s1: Dictionary, t: float) -> void:
	_last = t
	var row := PackedFloat32Array()
	row.resize(COLS)
	row[C_T] = t
	row[C_H0] = float(s0["hull"])
	row[C_H1] = float(s1["hull"])
	row[C_I0] = _integ(s0, 0)
	row[C_I1] = _integ(s1, 1)
	var a0: PackedFloat64Array = s0["armor"]
	var t0: PackedFloat64Array = s0["structure"]
	var a1: PackedFloat64Array = s1["armor"]
	var t1: PackedFloat64Array = s1["structure"]
	for k in 3:
		row[C_S0 + k] = a0[k] + t0[k]
		row[C_S1 + k] = a1[k] + t1[k]
	row[C_ASP0] = _aspect(s0, s1)
	row[C_ASP1] = _aspect(s1, s0)
	row[C_OH0] = 1.0 if s0["overheated"] else 0.0
	row[C_OH1] = 1.0 if s1["overheated"] else 0.0
	row[C_LF0] = 1.0 if s0["laser_firing"] else 0.0
	row[C_LF1] = 1.0 if s1["laser_firing"] else 0.0
	row[C_RAD0] = 1.0 if s0["radiators_extended"] else 0.0
	row[C_REP0] = float((s0["repairs"] as Array).size())
	var h0: PackedFloat64Array = s0["health"]
	var th0: PackedFloat64Array = s0["turret_hp"]
	var needy := false
	for k in 6:
		needy = needy or (h0[k] < 50.0 and not _absent[k])
	if not _absent[1]:
		for v in th0:
			needy = needy or v < 50.0
	row[C_NEEDY0] = 1.0 if needy else 0.0
	row[C_TEAMS0] = float(s0["teams"])
	row[C_HEAT0] = float(s0["heat"])
	row[C_HEAT1] = float(s1["heat"])
	# our crew's picture of the enemy against the truth
	var est: PackedFloat64Array = s0["est"]
	var h1: PackedFloat64Array = s1["health"]
	var err := 0.0
	for k in 6:
		err += absf(est[k] - h1[k])
	row[C_ERR] = err / 6.0
	row[C_RNG] = (Vector2(s1["pos"]) - Vector2(s0["pos"])).length()
	var mk: PackedInt32Array = s0["mark"]
	var tmk: PackedInt32Array = s0["turret_mark"]
	var th1: PackedFloat64Array = s1["turret_hp"]
	var wrong := 0
	for k in 6:
		if mk[k] == 2 and h1[k] > 0.0:
			wrong += 1
	for k in tmk.size():
		if tmk[k] == 2 and k < th1.size() and th1[k] > 0.0:
			wrong += 1
	row[C_DEADMARK] = float(wrong)
	_s.append_array(row)
	_n += 1

func _first(ship: int, tm: float) -> void:
	if ship < 0 or ship > 1:
		return
	if _first_dmg[ship] < 0.0 or tm < _first_dmg[ship]:
		_first_dmg[ship] = tm

func _keep(e: Dictionary) -> void:
	if _ev.size() < MAX_STORED:
		_ev.append({"t": float(e["time"]), "ship": int(e["ship"]), "kind": str(e["kind"]), "text": str(e["text"])})

func _on_event(e: Dictionary, s0: Dictionary, s1: Dictionary) -> void:
	var k := str(e["kind"])
	var sh := int(e["ship"])
	var tm := float(e["time"])
	var tx := str(e["text"])
	match k:
		"fire":
			if sh == 0 or sh == 1:
				_fired[sh] += 1
		"miss":
			if sh == 0 or sh == 1:
				_missed[sh] += 1
		"hit":
			if sh == 0 or sh == 1:
				_first(sh, tm)
				if tx.contains("stopped by"):
					_stopped[sh] += 1
				# a round stopped by armour still wears the armour, so it counts as gun evidence either way
				_gunhit_t[sh].append(tm)
		"burn-through":
			if sh == 0 or sh == 1:
				_first(sh, tm)
				var weapon := "beam" if tx.begins_with("Beam") else "rounds"
				var sec := "body"
				for nm in SEC_NAMES:
					if tx.contains("the %s armour" % nm):
						sec = nm
				var key := "%s %s" % [weapon, sec]
				_bt[sh][key] = int(_bt[sh].get(key, 0)) + 1
				if weapon == "rounds":
					_gunhit_t[sh].append(tm)
				var seen_key := "%d %s" % [sh, key]
				if not _bt_seen.has(seen_key):
					_bt_seen[seen_key] = true
					_keep(e)
		"overheat":
			if sh == 0 or sh == 1:
				_lock_count[sh] += 1
			_keep(e)
		"disabled", "repair", "out":
			_keep(e)
		"assess":
			_keep(e)
			_check_call(sh, tm, tx, s0, s1, e.get("real", null))

## Checks one crew call ("Enemy drive: probable disable") against the target's true state at the moment it was made.
func _check_call(observer: int, tm: float, tx: String, s0: Dictionary, s1: Dictionary, real: Variant = null) -> void:
	if observer != 0 and observer != 1:
		return
	var truth: Dictionary = s1 if observer == 0 else s0
	var body := tx.trim_prefix("Enemy ")
	var parts := body.split(": probable ")
	if parts.size() < 2:
		return
	var name := parts[0].strip_edges()
	var kind := parts[1].strip_edges()
	var hp := -1.0
	if name.begins_with("laser turret "):
		var idx := int(name.get_slice(" ", 2)) - 1
		var th: PackedFloat64Array = truth["turret_hp"]
		if idx >= 0 and idx < th.size():
			hp = th[idx]
	else:
		var h: PackedFloat64Array = truth["health"]
		for i in 6:
			if SYS_NAMES[i].to_lower() == name:
				hp = h[i]
	if hp < 0.0:
		return
	_calls.append({"t": tm, "obs": observer, "name": name, "kind": kind, "ok": (bool(real) if real != null else hp <= 0.0), "hp": hp})

# ------------------------------------------------------------------ analysis

func _v(i: int, c: int) -> float:
	return _s[i * COLS + c]

func _dur(i: int) -> float:
	return _v(i + 1, C_T) - _v(i, C_T) if i + 1 < _n else 0.0

static func clock(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

static func _bucket(asp: float) -> int:
	return 0 if asp < 45.0 else (1 if asp < 135.0 else 2)

static func _pct(x: float, total: float) -> int:
	return int(round(100.0 * x / total)) if total > 1e-9 else 0

func _build() -> void:
	chart_t = PackedFloat32Array(); chart_h0 = PackedFloat32Array(); chart_h1 = PackedFloat32Array()
	chart_i0 = PackedFloat32Array(); chart_i1 = PackedFloat32Array()
	for i in _n:
		chart_t.append(_v(i, C_T)); chart_h0.append(_v(i, C_H0)); chart_h1.append(_v(i, C_H1))
		chart_i0.append(_v(i, C_I0)); chart_i1.append(_v(i, C_I1))
	var notes: Array = []
	var tl: Array = []          # candidates {t, text, tone, score}
	var ins: Array = []         # candidates {title, lines, score}

	# --- shared measures
	var drop0 := PackedFloat32Array()    # points lost per interval, us / them
	var drop1 := PackedFloat32Array()
	var sec_loss0 := [0.0, 0.0, 0.0]
	var sec_loss1 := [0.0, 0.0, 0.0]
	for i in _n - 1:
		drop0.append(maxf(0.0, _v(i, C_I0) - _v(i + 1, C_I0)) * 100.0)
		drop1.append(maxf(0.0, _v(i, C_I1) - _v(i + 1, C_I1)) * 100.0)
		for k in 3:
			sec_loss0[k] += maxf(0.0, _v(i, C_S0 + k) - _v(i + 1, C_S0 + k))
			sec_loss1[k] += maxf(0.0, _v(i, C_S1 + k) - _v(i + 1, C_S1 + k))
	var taken := 0.0
	var dealt := 0.0
	for d in drop0: taken += d
	for d in drop1: dealt += d

	var T := maxf(duration, 1.0)

	_timeline(tl, drop0, drop1)
	_ins_posture(ins, drop0, drop1, taken, dealt)
	_ins_weapons(ins, drop0, drop1, taken, dealt, T)
	_ins_sections(ins, sec_loss0, sec_loss1, taken)
	_ins_calls(ins)
	_ins_heat(ins, T)
	_ins_repair(ins, T)

	# --- pick
	tl.sort_custom(func(a, b): return a["score"] > b["score"])
	var picked := tl.slice(0, 15)
	picked.sort_custom(func(a, b): return a["t"] < b["t"])
	ins.sort_custom(func(a, b): return a["score"] > b["score"])
	var chosen := ins.slice(0, 5)
	chosen.sort_custom(func(a, b): return a["order"] < b["order"])

	notes.append("Samples every %d s of battle time; damage is split by the state at the start of each sample. Numbers are approximate to that step." % int(SAMPLE_DT))
	notes.append("1 point = 1% of a ship's armour + structure at the start. Laser hits are not logged one by one, so damage by weapon is inferred from when each weapon was firing or landing.")
	report = {"headline": _headline(), "timeline": picked, "insights": chosen, "notes": notes}

func _headline() -> Array:
	var won := winner == 0
	var lines: Array = []
	lines.append("BATTLE UNFINISHED" if winner < 0 else ("VICTORY" if won else "DEFEAT"))
	lines.append("Battle time %s" % clock(duration))
	lines.append("%s start" % SCEN_NAMES[clampi(scenario, 0, 2)])
	var style: String = STYLE_NAMES[clampi(personality, 0, 2)]
	if personality == 2:
		var side := 0.0
		var tot := 0.0
		for i in _n - 1:
			tot += _dur(i)
			if _bucket(_v(i, C_ASP1)) == 1:
				side += _dur(i)
		if tot > 0.0 and side / tot < 0.01:
			style += " (the fight ended before it turned side-on)"
	lines.append("Enemy captain was " + style)
	var loser: Dictionary = _final1 if won else _final0
	if winner >= 0:
		lines.append("%s is out of action: %s." % [str(loser["name"]), str(loser["out_reason"])])
	lines.append("Hull at the end: you %d%%, enemy %d%%. Crew: you %d of %d, enemy %d of %d." % [
		int(float(_final0["hull"]) * 100), int(float(_final1["hull"]) * 100),
		int(_final0["crew"]), int(_final0["crew_max"]), int(_final1["crew"]), int(_final1["crew_max"])])
	if _min_range < 1.0e8:
		lines.append("Closest approach %.1f km at %s." % [_min_range, clock(_min_range_t)])
	return lines

# ---- timeline

func _tl(list: Array, t: float, text: String, tone: int, score: float) -> void:
	list.append({"t": t, "text": text, "tone": tone, "score": score})

func _timeline(tl: Array, drop0: PackedFloat32Array, drop1: PackedFloat32Array) -> void:
	# first damage each way
	if _first_dmg[1] >= 0.0:
		_tl(tl, _first_dmg[1], "First damage on the enemy.", 1, 90)
	if _first_dmg[0] >= 0.0:
		_tl(tl, _first_dmg[0], "First damage on you.", -1, 90)
	var disabled_seen := {}
	var locks := [0, 0]
	var repairs := [0, 0]
	var good_call := false
	var bad_call := false
	for e in _ev:
		var sh: int = e["ship"]
		var t: float = e["t"]
		var tx: String = e["text"]
		match e["kind"]:
			"burn-through":
				var weapon := "beam" if tx.begins_with("Beam") else "rounds"
				var sec := "body"
				for nm in SEC_NAMES:
					if tx.contains("the %s armour" % nm):
						sec = nm
				if sh == 1:
					_tl(tl, t, "Your %s through the enemy's %s armour." % ["beam burns" if weapon == "beam" else "rounds burn", sec], 1, 75)
				else:
					_tl(tl, t, "Enemy %s through your %s armour." % ["beam burns" if weapon == "beam" else "rounds burn", sec], -1, 75)
			"disabled":
				var what := tx.get_slice(": ", 1) if tx.contains(": ") else tx
				what = what.substr(0, 1).to_lower() + what.substr(1)
				var dk := "%d %s" % [sh, what]
				var again: bool = disabled_seen.has(dk)
				disabled_seen[dk] = true
				var sc := 70.0 if (what.begins_with("drive") or what.begins_with("gun") or what.begins_with("crew")) else (40.0 if what.begins_with("laser turret") else 50.0)
				if again:
					sc *= 0.5
				var tail := " again" if again else ""
				if sh == 1:
					_tl(tl, t, "Enemy %s%s." % [what, tail], 1, sc)
				else:
					_tl(tl, t, "Your %s%s." % [what, tail], -1, sc)
			"overheat":
				if sh == 0 or sh == 1:
					locks[sh] += 1
					var first: bool = locks[sh] == 1
					var who := "You overheat" if sh == 0 else "Enemy overheats"
					_tl(tl, t, "%s: weapons locked%s." % [who, "" if first else " again (#%d)" % locks[sh]], -1 if sh == 0 else 1, 65.0 if first else 38.0)
			"repair":
				if tx.contains("patched") and (sh == 0 or sh == 1):
					repairs[sh] += 1
					var sysname := tx.get_slice(": ", 1).replace(" patched to 60 %", "").to_lower()
					var who2 := "Your repair team patches your %s" % sysname if sh == 0 else "Enemy repair team patches its %s" % sysname
					_tl(tl, t, who2 + " back to 60%.", 1 if sh == 0 else -1, 36.0 if repairs[sh] == 1 else 18.0)
			"out":
				if sh == 0 or sh == 1:
					var why := tx.get_slice(": ", 1) if tx.contains(": ") else ""
					_tl(tl, t, ("The enemy is out of action: %s." if sh == 1 else "You are out of action: %s.") % why, 1 if sh == 1 else -1, 100)
	# crew calls
	for c in _calls:
		if c["obs"] != 0:
			continue
		var verb := "destroyed" if c["kind"] == "destroy" else "disabled"
		if c["ok"]:
			if not good_call:
				good_call = true
				_tl(tl, c["t"], "Crew calls the enemy %s %s. Correct." % [c["name"], verb], 1, 30)
		elif not bad_call:
			bad_call = true
			var lag0 := _knocked_out_after(c)
			_tl(tl, c["t"], "Crew calls the enemy %s %s. Wrong: it was at %d%%%s." % [c["name"], verb, int(round(c["hp"])), "" if lag0 < 0.0 else ", and went out %d s later" % int(round(lag0))], -1, 58)
	# hull below half
	for who in 2:
		for i in _n:
			if _v(i, C_H0 if who == 0 else C_H1) < 0.5:
				_tl(tl, _v(i, C_T), ("Your hull falls below half." if who == 0 else "The enemy hull falls below half."), -1 if who == 0 else 1, 52)
				break
	# turning point (hull-fraction lead)
	turning_t = _turning(tl)
	# heaviest exchange: the most damage to one ship inside any ~20 s window
	var best := 0.0
	var bi := -1
	var bj := 0
	var bwho := 0
	for who in 2:
		var dr: PackedFloat32Array = drop0 if who == 0 else drop1
		for i in dr.size():
			var sum := 0.0
			var j := i
			while j < dr.size() and _v(j + 1, C_T) - _v(i, C_T) <= 20.0:
				sum += dr[j]
				j += 1
			if sum > best:
				best = sum; bi = i; bj = j; bwho = who
	if bi >= 0 and best >= 4.0:
		var span := "%s to %s" % [clock(_v(bi, C_T)), clock(_v(bj, C_T))]
		var secs := int(round(_v(bj, C_T) - _v(bi, C_T)))
		if bwho == 0:
			_tl(tl, _v(bi, C_T), "Heaviest blow: you lose %d points of armour and hull in %d s (%s)." % [int(round(best)), secs, span], -1, 60)
		else:
			_tl(tl, _v(bi, C_T), "Heaviest blow: the enemy loses %d points of armour and hull in %d s (%s)." % [int(round(best)), secs, span], 1, 60)

## Finds the moment the hull lead passed to the winner for good; returns its time, or -1 if there was none.
func _turning(tl: Array) -> float:
	if _n < 3 or winner < 0:
		return -1.0
	var db := 0.03
	var sgn := 1.0 if winner == 0 else -1.0
	var lead := PackedFloat32Array()
	for i in _n:
		lead.append((_v(i, C_H0) - _v(i, C_H1)) * sgn)
	var last_behind := -1
	for i in _n:
		if lead[i] < -db:
			last_behind = i
	if lead[_n - 1] <= 0.0:
		_tl(tl, end_t, "Decided on systems and crew, not hull: the winner ended with %d%% hull to the loser's %d%%." % [int(float((_final0 if winner == 0 else _final1)["hull"]) * 100), int(float((_final1 if winner == 0 else _final0)["hull"]) * 100)], 0, 45)
		return -1.0
	if last_behind < 0:
		return -1.0
	var k := last_behind + 1
	while k < _n and lead[k] < 0.0:
		k += 1
	if k >= _n:
		return -1.0
	var a := lead[k - 1]
	var b := lead[k]
	var f := clampf(-a / (b - a), 0.0, 1.0) if b > a else 1.0
	var t := lerpf(_v(k - 1, C_T), _v(k, C_T), f)
	_tl(tl, t, "Turning point: %s the hull lead for good." % ("you take" if winner == 0 else "the enemy takes"), 1 if winner == 0 else -1, 95)
	return t

# ---- insights

func _share_line(vals: Array, total: float) -> String:
	return "nose-on %d%%, side-on %d%%, tail-on %d%%" % [_pct(vals[0], total), _pct(vals[1], total), _pct(vals[2], total)]

## Like-for-like posture comparison: damage per minute of ENEMY LASER FIRE on us, inside one range band, and only when
## each posture has at least 60 s of such exposure in that band. Otherwise no ratio is claimed.
func _posture_compare(drop0: PackedFloat32Array) -> Array:
	var bands := [[0.0, 30.0, "under 30 km"], [30.0, 70.0, "30-70 km"], [70.0, 1.0e9, "over 70 km"]]
	var best := -1
	var best_exp := 0.0
	var ex: Array = []
	var dm: Array = []
	for bi in 3:
		var e := [0.0, 0.0, 0.0]
		var d := [0.0, 0.0, 0.0]
		for i in _n - 1:
			var r := _v(i, C_RNG)
			if r >= bands[bi][0] and r < bands[bi][1] and _v(i, C_LF1) > 0.5:
				var b := _bucket(_v(i, C_ASP0))
				e[b] += _dur(i)
				d[b] += drop0[i]
		ex.append(e); dm.append(d)
		var ok := 0
		var tot := 0.0
		for b in 3:
			if e[b] >= 60.0:
				ok += 1
				tot += e[b]
		if ok >= 2 and tot > best_exp:
			best = bi
			best_exp = tot
	if best < 0:
		return ["Not enough like-for-like exposure to compare postures (needs 60 s of enemy laser fire on you in each posture at the same range), so no ratio is claimed."]
	var rates: Array = []
	for b in 3:
		if ex[best][b] >= 60.0:
			rates.append({"b": b, "r": dm[best][b] / ex[best][b] * 60.0})
	rates.sort_custom(func(a, c): return a["r"] > c["r"])
	var hi: Dictionary = rates[0]
	var lo: Dictionary = rates[rates.size() - 1]
	var out: Array = []
	out.append("At %s, per minute of enemy laser fire on you: %s points." % [bands[best][2], ", ".join(rates.map(func(r): return "%s %.1f" % [POSTURE[r["b"]], r["r"]]))])
	if lo["r"] > 0.05 and hi["r"] / lo["r"] >= 1.5:
		out.append("In those like-for-like minutes, being %s hurt %.1fx more than being %s." % [POSTURE[hi["b"]], hi["r"] / lo["r"], POSTURE[lo["b"]]])
	else:
		out.append("In those like-for-like minutes posture made little difference.")
	return out

func _ins_posture(ins: Array, drop0: PackedFloat32Array, drop1: PackedFloat32Array, taken: float, dealt: float) -> void:
	if _n < 3:
		return
	var tm0 := [0.0, 0.0, 0.0]
	var dm0 := [0.0, 0.0, 0.0]
	var tm1 := [0.0, 0.0, 0.0]
	var dm1 := [0.0, 0.0, 0.0]
	var tt := 0.0
	for i in _n - 1:
		var d := _dur(i)
		tt += d
		var b0 := _bucket(_v(i, C_ASP0))
		var b1 := _bucket(_v(i, C_ASP1))
		tm0[b0] += d; dm0[b0] += drop0[i]
		tm1[b1] += d; dm1[b1] += drop1[i]
	if tt < 10.0:
		return
	var lines: Array = []
	lines.append("You showed: %s." % _share_line(tm0, tt))
	if taken >= 1.0:
		lines.append("Damage you took came in: %s (%d points)." % [_share_line(dm0, taken), int(round(taken))])
		lines.append_array(_posture_compare(drop0))
	else:
		lines.append("You took almost no damage.")
	lines.append("The enemy showed you: %s." % _share_line(tm1, tt))
	if dealt >= 1.0:
		lines.append("Damage you dealt came while it was: %s." % _share_line(dm1, dealt))
	ins.append({"title": "WHICH FACE YOU SHOWED", "lines": lines, "score": 70.0 + minf(taken, 30.0) * 0.3, "order": 0})

func _attrib(target: int, drop: PackedFloat32Array) -> Dictionary:
	# Split a ship's damage by what the shooter was doing in each sample step: laser firing, damaging gun hits landing, both, or neither seen.
	var shooter := 1 - target
	var lc: int = C_LF0 if shooter == 0 else C_LF1
	var hits: PackedFloat32Array = _gunhit_t[target]
	var out := {"laser": 0.0, "gun": 0.0, "both": 0.0, "unseen": 0.0}
	var p := 0
	for i in drop.size():
		var t0 := _v(i, C_T)
		var t1 := _v(i + 1, C_T)
		var g := false
		while p < hits.size() and hits[p] < t0:
			p += 1
		var q := p
		while q < hits.size() and hits[q] <= t1:
			g = true
			q += 1
		var l := _v(i, lc) > 0.5 or _v(i + 1, lc) > 0.5
		if drop[i] <= 0.0:
			continue
		var key := "both" if (g and l) else ("gun" if g else ("laser" if l else "unseen"))
		out[key] += drop[i]
	return out

func _attrib_line(a: Dictionary, total: float) -> String:
	var parts: Array = []
	for k in ["laser", "gun", "both", "unseen"]:
		if a[k] > 0.0:
			var label: String = {"laser": "laser only", "gun": "gun only", "both": "laser and gun together", "unseen": "unlogged"}[k]
			if _pct(a[k], total) > 0:
				parts.append("%s %d%%" % [label, _pct(a[k], total)])
	return ", ".join(parts)

func _ins_weapons(ins: Array, drop0: PackedFloat32Array, drop1: PackedFloat32Array, taken: float, dealt: float, T: float) -> void:
	if _n < 3:
		return
	var lines: Array = []
	lines.append("You dealt %d points and took %d." % [int(round(dealt)), int(round(taken))])
	if dealt >= 1.0:
		lines.append("Your damage: " + _attrib_line(_attrib(1, drop1), dealt) + ".")
	if taken >= 1.0:
		lines.append("Damage to you: " + _attrib_line(_attrib(0, drop0), taken) + ".")
	var lf0 := 0.0
	var lf1 := 0.0
	for i in _n - 1:
		lf0 += _v(i, C_LF0) * _dur(i)
		lf1 += _v(i, C_LF1) * _dur(i)
	lines.append("Laser firing: you %d%% of the fight, enemy %d%%." % [_pct(lf0, T), _pct(lf1, T)])
	if _fired[0] > 0:
		lines.append("Your gun: %d rounds fired, %d missed." % [_fired[0], _missed[1]])
	if _fired[1] > 0:
		lines.append("Enemy gun: %d rounds fired, %d missed." % [_fired[1], _missed[0]])
	if _stopped[0] + _stopped[1] > 0:
		lines.append("Armour stopped %d enemy rounds and %d of yours." % [_stopped[0], _stopped[1]])
	ins.append({"title": "WHAT DID THE DAMAGE", "lines": lines, "score": 65.0, "order": 1})

func _ins_sections(ins: Array, sl0: Array, sl1: Array, taken: float) -> void:
	if _n < 3 or taken < 1.0:
		return
	var tot0 := float(sl0[0] + sl0[1] + sl0[2])
	var tot1 := float(sl1[0] + sl1[1] + sl1[2])
	if tot0 <= 0.0:
		return
	var lines: Array = []
	var best := 0
	for k in 3:
		if sl0[k] > sl0[best]:
			best = k
	lines.append("Share of the damage you took: nose %d%%, body %d%%, aft %d%%." % [_pct(sl0[0], tot0), _pct(sl0[1], tot0), _pct(sl0[2], tot0)])
	lines.append("Hardest hit: your %s (%d%% of it)." % [SEC_NAMES[best], _pct(sl0[best], tot0)])
	var left: Array = []
	var last := _n - 1
	for k in 3:
		left.append(int(round(100.0 * _v(last, C_S0 + k) / maxf(_secmax[0][k], 1.0))))
	lines.append("Armour + structure left at the end: nose %d%%, body %d%%, aft %d%%." % left)
	var bts: Array = []
	for k in SEC_NAMES:
		var n := int(_bt[0].get("beam " + k, 0)) + int(_bt[0].get("rounds " + k, 0))
		bts.append("%s %d" % [k, n])
	var wp: PackedFloat64Array = _final0["armor_worst"]
	var am: PackedFloat64Array = _final0["armor_max"]
	lines.append("Thinnest armour panel left: nose %d%%, body %d%%, aft %d%% of new." % [int(round(100.0 * wp[0] / maxf(am[0], 1.0))), int(round(100.0 * wp[1] / maxf(am[1], 1.0))), int(round(100.0 * wp[2] / maxf(am[2], 1.0)))])
	lines.append("Burn-throughs into you: " + ", ".join(bts) + ".")
	if tot1 > 0.0:
		var eb := 0
		for k in 3:
			if sl1[k] > sl1[eb]:
				eb = k
		lines.append("You hurt the enemy most in its %s (%d%% of its damage)." % [SEC_NAMES[eb], _pct(sl1[eb], tot1)])
	ins.append({"title": "WHERE IT HIT YOU", "lines": lines, "score": 50.0 + _pct(sl0[best], tot0) * 0.1, "order": 2})

## Seconds until the called system really went out (within 15 s), or -1.
func _knocked_out_after(c: Dictionary) -> float:
	var want := (" " + str(c["name"]) + " knocked out").to_lower()
	for e in _ev:
		if e["kind"] == "disabled" and e["ship"] == 1 - int(c["obs"]) and e["t"] >= c["t"] and e["t"] - c["t"] <= 15.0 and (" " + str(e["text"]).to_lower()).contains(want):
			return e["t"] - c["t"]
	return -1.0

func _ins_calls(ins: Array) -> void:
	if _n < 2:
		return
	var mine: Array = _calls.filter(func(c): return c["obs"] == 0)
	var theirs: Array = _calls.filter(func(c): return c["obs"] == 1)
	var right := mine.filter(func(c): return c["ok"]).size()
	var wrong := mine.size() - right
	var lines: Array = []
	if mine.is_empty():
		lines.append("Your crew made no kill calls.")
	else:
		lines.append("Your crew called %d enemy %s out. The sim knows which calls described a real kill: %d right, %d wrong (%d%% right)." % [mine.size(), "system" if mine.size() == 1 else "systems", right, wrong, _pct(right, mine.size())])
		var shown := 0
		var early := 0
		for c in mine:
			if c["ok"]:
				continue
			var lag := _knocked_out_after(c)
			if lag >= 0.0:
				early += 1
			if shown < 4:
				shown += 1
				lines.append("  %s: enemy %s called %s; it was really at %d%%%s." % [clock(c["t"]), c["name"], "destroyed" if c["kind"] == "destroy" else "disabled", int(round(c["hp"])), "" if lag < 0.0 else ", and went out %d s later" % int(round(lag))])
		if early > 0:
			lines.append("  %d of the wrong calls came true within 15 s: early, not false." % early)
		if wrong > shown:
			lines.append("  ...and %d more wrong %s." % [wrong - shown, "call" if wrong - shown == 1 else "calls"])
	var err_sum := 0.0
	var err_max := 0.0
	var dead_t := 0.0
	var tt := 0.0
	for i in _n - 1:
		var d := _dur(i)
		tt += d
		err_sum += _v(i, C_ERR) * d
		err_max = maxf(err_max, _v(i, C_ERR))
		if _v(i, C_DEADMARK) > 0.5:
			dead_t += d
	if tt > 0.0:
		lines.append("Your picture of the enemy was off by %.0f points on average (worst %.0f)." % [err_sum / tt, err_max])
		if dead_t > 0.0:
			lines.append("A live enemy system sat marked dead for %d%% of the fight. Fire control believes the marks." % _pct(dead_t, tt))
	if not theirs.is_empty():
		var tr := theirs.filter(func(c): return c["ok"]).size()
		lines.append("The enemy crew made %d %s on you; %d %s right." % [theirs.size(), "call" if theirs.size() == 1 else "calls", tr, "was" if tr == 1 else "were"])
	ins.append({"title": "FOG OF WAR: CREW CALLS", "lines": lines, "score": (35.0 if mine.is_empty() else 55.0) + 8.0 * wrong, "order": 3})

func _ins_heat(ins: Array, T: float) -> void:
	if _n < 3:
		return
	var oh0 := 0.0
	var oh1 := 0.0
	var rad := 0.0
	var rad_in_lock := 0.0
	var pk0 := 0.0
	var pk1 := 0.0
	for i in _n - 1:
		var d := _dur(i)
		oh0 += _v(i, C_OH0) * d
		oh1 += _v(i, C_OH1) * d
		rad += _v(i, C_RAD0) * d
		rad_in_lock += _v(i, C_RAD0) * _v(i, C_OH0) * d
		pk0 = maxf(pk0, _v(i, C_HEAT0))
		pk1 = maxf(pk1, _v(i, C_HEAT1))
	var lines: Array = []
	if oh0 + oh1 <= 0.0 and _lock_count[0] + _lock_count[1] == 0:
		lines.append("Nobody was locked out by heat.")
	else:
		lines.append("Weapons locked by heat: you %s (%d%%, %d times), enemy %s (%d%%, %d times)." % [clock(oh0), _pct(oh0, T), _lock_count[0], clock(oh1), _pct(oh1, T), _lock_count[1]])
	lines.append("Peak heat: you %d, enemy %d. (Lock at 100, clears below 70.)" % [int(round(pk0)), int(round(pk1))])
	lines.append("Your radiators were extended %d%% of the fight." % _pct(rad, T))
	if oh0 > 0.0:
		lines.append("During your lockouts they were extended %d%% of the time." % _pct(rad_in_lock, oh0))
	ins.append({"title": "HEAT AND LOCKOUTS", "lines": lines, "score": 25.0 + minf(60.0, 200.0 * maxf(oh0, oh1) / T), "order": 4})

func _ins_repair(ins: Array, T: float) -> void:
	if _n < 3:
		return
	var needy := 0.0
	var working := 0.0
	var teams_start := _v(0, C_TEAMS0)
	for i in _n - 1:
		var d := _dur(i)
		if _v(i, C_NEEDY0) > 0.5:
			needy += d
			if _v(i, C_REP0) > 0.5:
				working += d
	var patched := 0
	var abandoned := 0
	for e in _ev:
		if e["kind"] == "repair" and e["ship"] == 0:
			if str(e["text"]).contains("patched"):
				patched += 1
			elif str(e["text"]).contains("abandoned"):
				abandoned += 1
	if needy < 8.0 and patched == 0:
		return
	var lines: Array = []
	lines.append("Something on your ship was below 50%% for %s (%d%% of the fight)." % [clock(needy), _pct(needy, T)])
	lines.append("A repair team was working for %d%% of that time." % _pct(working, needy))
	lines.append("%d %s finished (each lifts a system to 60%%)%s." % [patched, "patch" if patched == 1 else "patches", "; %d %s dropped when teams were lost" % [abandoned, "job" if abandoned == 1 else "jobs"] if abandoned > 0 else ""])
	lines.append("Teams available: %d at the start, %d at the end." % [int(teams_start), int(_v(_n - 1, C_TEAMS0))])
	ins.append({"title": "REPAIR TEAMS", "lines": lines, "score": 30.0 + (25.0 if needy / T > 0.2 else 0.0), "order": 5})

# ------------------------------------------------------------------ text output

## The whole report as plain text, for the log export.
func as_text() -> String:
	if not done:
		return "AFTER-ACTION REPORT: battle not finished.\n"
	var o := PackedStringArray()
	o.append("AFTER-ACTION REPORT")
	o.append("====================")
	for l in report["headline"]:
		o.append(str(l))
	o.append("")
	o.append("TIMELINE")
	o.append("--------")
	for e in report["timeline"]:
		o.append("%s  %s" % [clock(e["t"]), e["text"]])
	o.append("")
	o.append("WHY IT WENT THAT WAY")
	o.append("--------------------")
	var n := 0
	for ins in report["insights"]:
		n += 1
		o.append("%d. %s" % [n, ins["title"]])
		for l in ins["lines"]:
			o.append("   " + str(l))
		o.append("")
	o.append("HULL % BY TIME (you / enemy)")
	var next_t := 0.0
	for i in _n:
		if _v(i, C_T) >= next_t or i == _n - 1:
			o.append("  %s  %3d / %3d" % [clock(_v(i, C_T)), int(round(_v(i, C_H0) * 100)), int(round(_v(i, C_H1) * 100))])
			next_t = _v(i, C_T) + 30.0
	o.append("")
	for l in report["notes"]:
		o.append("Note: " + str(l))
	return "\n".join(o) + "\n"

## Writes as_text() to user://reports/aar_<datetime>.txt (under OS.get_user_data_dir()). Returns the path, or "" on failure.
func export_text() -> String:
	# Same folder logic as the log export (Documents/TDC Demo logs/<stamp>/, else user://), via LogExport.
	var dir: String = LogExport._make_folder()
	if dir == "":
		dir = OS.get_user_data_dir().path_join("reports")
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			return ""
	var dt := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := dir.path_join("aar_%s.txt" % dt)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(as_text())
	f.close()
	return path
