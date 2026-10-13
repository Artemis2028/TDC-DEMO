class_name TacticalPlot
extends Control
## Top-down tactical plot: the engagement geometry in our frame.
##
## Frame: our ship sits at the centre, the sim plane is drawn north-up (sim +y is up, +x is right, so heading
## angles read counter-clockwise like the sim). North-up was chosen over nose-up because our ship turns, rolls
## and broadsides all the time. In a nose-up plot the whole picture would spin with every turn, which makes
## the relative track (the thing that matters) hard to read, particularly under time compression.
## Here the geometry only moves when the relative motion changes and the nose tick shows where we point.
##
## The plot is purely a view: it takes the dictionaries that main.gd already holds and does no physics except
## the straight-line CPA (see cpa()).
##
## Units: positions km, velocities m/s, ranges km, times s of battle time.

const TRAIL_N := 150            # 5 min of battle time at one sample per TRAIL_DT
const TRAIL_DT := 2.0
const FIT := 0.7                # the enemy sits at about 70 % of the plot radius
const NICE_STEPS: Array = [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0]
const ARROW_TIMES: Array = [15.0, 30.0, 60.0, 120.0, 300.0, 600.0]
const LEG_H := 30.0             # legend strip at the bottom
const POOR_Q := 0.3             # below this the enemy is poorly tracked (matches the HUD)

# --- cached drawing resources -------------------------------------------------------------------------
var _fm: Font
var _fh: Font
var _col_grid := Color(W.LINE, 0.55)
var _col_grid_txt := Color(W.FAINT, 1.0)

# --- state (set by update_from) -----------------------------------------------------------------------
var _t := 0.0
var _q := 1.0
var _closing := 0.0
var _rel := Vector2.ZERO        # enemy position relative to us, km
var _vrel := Vector2.ZERO       # enemy velocity relative to us, m/s
var _v0 := Vector2.ZERO
var _v1 := Vector2.ZERO
var _h0 := 0.0
var _h1 := 0.0
var _burn0 := false
var _burn1 := false
var _beam0 := false
var _beam1 := false
var _rng: float = 0.0           # km
var _r_laser0 := 0.0            # weapon ranges, km (0 = not fitted / not exported)
var _r_gun0 := 0.0
var _r_laser1 := 0.0
var _r_gun1 := 0.0
var _cpa_t := 0.0               # s from now (<= 0: passed or no relative motion)
var _cpa_miss := 0.0            # km
var _cpa_valid := false         # approaching, with relative motion
var _extent := 0.0              # km at the plot radius (outer ring)
var _step := 0.0                # km per range ring

# --- trail ring buffer (fixed size, relative positions in km) -----------------------------------------
var _trail := PackedVector2Array()
var _trail_n := 0
var _trail_head := 0
var _next_sample := 0.0

# --- reusable draw buffers (no allocation in _draw) ---------------------------------------------------
var _dash := PackedVector2Array()
var _poly := PackedVector2Array()
var _tpts := PackedVector2Array()
var _tcol := PackedColorArray()
var _tri := PackedVector2Array()
var _layer: Control               # static layer (background, rings, compass, weapon envelopes), drawn behind us
var _skey_ext := -1.0             # what the static layer was last drawn for
var _skey_size := Vector2.ZERO
var _skey_rng := Vector4.ZERO
var _skey_ep := Vector2i(-99999, -99999)
var _ring_lbl := PackedStringArray()
var _s_off := ""
var _dirty := true
var _last_ms := 0
var _t_seen := -1.0
var _q_seen := -1.0
var prof_usec := 0                # accumulated _draw time of both layers, for the timing harness
var prof_n := 0
const MIN_MS := 66                # redraw at most ~15 Hz of real time


class StaticLayer extends Control:
	var plot: Control
	func _draw() -> void:
		var t0 := Time.get_ticks_usec()
		plot._draw_static(self)
		plot.prof_usec += Time.get_ticks_usec() - t0

# --- cached strings, rebuilt only when the rounded value changes --------------------------------------
var _s_cpa := ""
var _s_cpa_key := ""
var _s_leg := ""
var _s_leg_key := ""
var _s_arrow := ""
var _arrow_t := 60.0
var _s_scale := ""
var _s_cpa_lab := ""


func _init() -> void:
	_fm = W.FM
	_fh = W.FH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_trail.resize(TRAIL_N)
	_tpts.resize(TRAIL_N * 2)
	_tcol.resize(TRAIL_N)
	_poly.resize(33)
	_tri.resize(4)
	_layer = StaticLayer.new()
	_layer.plot = self
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.show_behind_parent = true
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_layer)
	visibility_changed.connect(_on_vis)
	resized.connect(func(): _dirty = true)


func _on_vis() -> void:
	if is_visible_in_tree():
		_dirty = true
		queue_redraw()


## Call at battle start.
func reset() -> void:
	_trail_n = 0
	_trail_head = 0
	_next_sample = 0.0
	_extent = 0.0
	_cpa_valid = false
	_s_cpa_key = ""
	_s_leg_key = ""
	_t = 0.0
	_t_seen = -1.0
	_skey_ext = -1.0
	_dirty = true
	if is_visible_in_tree():
		queue_redraw()
		_layer.queue_redraw()


## Closest point of approach for a straight-line relative track.
## r: relative position (km), v: relative velocity (km/s).
## Returns Vector2(t_cpa in s, miss in km). t_cpa <= 0 means the range is opening (CPA already passed), and
## the miss then equals the current range. Miss distance is |r x v| / |v| when approaching, from the minimum of
## |r + v t|^2 at t = -(r . v) / |v|^2.
static func cpa(r: Vector2, v: Vector2) -> Vector2:
	var vv := v.dot(v)
	if vv < 1e-12:
		return Vector2(-1.0, r.length())
	var t := -r.dot(v) / vv
	if t <= 0.0:
		return Vector2(t, r.length())
	return Vector2(t, (r + v * t).length())


## Feed the current frame. Cheap when hidden: only the trail is sampled so it is full when the plot opens.
func update_from(s0: Dictionary, s1: Dictionary, t: float, quality: float, closing: float) -> void:
	if t < _next_sample - TRAIL_DT - 0.5:   # battle time went backwards: new battle
		_trail_n = 0
		_trail_head = 0
		_next_sample = 0.0
	if t >= _next_sample:
		var rp: Vector2 = Vector2(s1["pos"]) - Vector2(s0["pos"])
		_trail[_trail_head] = rp
		_trail_head = (_trail_head + 1) % TRAIL_N
		_trail_n = mini(_trail_n + 1, TRAIL_N)
		_next_sample = t + TRAIL_DT   # one sample per step even if time compression jumped further
	if not is_visible_in_tree():
		return
	# Paused (battle time and quality unchanged): nothing moved. Otherwise at most ~15 Hz of real time.
	if not _dirty:
		if t == _t_seen and quality == _q_seen:
			return
		var now := Time.get_ticks_msec()
		if now - _last_ms < MIN_MS:
			return
		_last_ms = now
	else:
		_last_ms = Time.get_ticks_msec()
	_dirty = false
	_t_seen = t
	_q_seen = quality
	_t = t
	_q = quality
	_closing = closing

	var p0: Vector2 = s0["pos"]
	var p1: Vector2 = s1["pos"]
	_rel = p1 - p0
	_rng = _rel.length()
	_v0 = s0["vel"]
	_v1 = s1["vel"]
	_vrel = _v1 - _v0
	_h0 = float(s0["heading"])
	_h1 = float(s1["heading"])
	_burn0 = bool(s0.get("burning", false))
	_burn1 = bool(s1.get("burning", false))
	_beam0 = bool(s0.get("laser_firing", false))
	_beam1 = bool(s1.get("laser_firing", false))
	_r_laser0 = float(s0.get("laser_range", 0.0)) * 0.001
	_r_gun0 = float(s0.get("gun_range", 0.0)) * 0.001
	_r_laser1 = float(s1.get("laser_range", 0.0)) * 0.001
	_r_gun1 = float(s1.get("gun_range", 0.0)) * 0.001

	var c := cpa(_rel, _vrel * 0.001)
	_cpa_valid = c.x > 0.0
	_cpa_t = c.x
	_cpa_miss = c.y
	_update_scale()
	_update_strings()
	# Static layer: only when the scale, size, weapon ranges or (quantised to 3 px) enemy position changed.
	var ppk := _radius() / maxf(_extent, 0.001)
	var epq := Vector2i(int(_rel.x * ppk / 3.0), int(_rel.y * ppk / 3.0))
	var rk := Vector4(_r_laser0, _r_gun0, _r_laser1, _r_gun1)
	if _extent != _skey_ext or size != _skey_size or rk != _skey_rng or epq != _skey_ep:
		_skey_ext = _extent
		_skey_size = size
		_skey_rng = rk
		_skey_ep = epq
		_layer.queue_redraw()
	queue_redraw()


# --- scale, strings -----------------------------------------------------------------------------------

## Picks the outer ring from the nice steps so the enemy is near 70 % of the radius. Hysteresis keeps the
## scale from flickering: it only changes when the enemy passes 85 % of the radius or falls under 35 %.
func _update_scale() -> void:
	if _extent <= 0.0 or _rng > 0.85 * _extent or _rng < 0.35 * _extent:
		var need := maxf(_rng, 0.5) / FIT
		var found := false
		for st in NICE_STEPS:
			var n := ceili(need / float(st) - 1e-6)
			if n <= 5:
				_step = float(st)
				_extent = maxf(n, 1) * _step
				found = true
				break
		if not found:   # beyond 2500 km: five rings of a multiple of the largest step
			var big: float = NICE_STEPS[NICE_STEPS.size() - 1]
			_step = big * ceilf(need / 5.0 / big)
			_extent = 5.0 * _step
		_ring_lbl.resize(int(round(_extent / _step)))
		for i in _ring_lbl.size():
			_ring_lbl[i] = "%s km" % _fmt_km(float(i + 1) * _step)
		_s_scale = ""
	if _s_scale == "":
		_s_scale = "OUTER RING %s KM" % _fmt_km(_extent)


func _update_strings() -> void:
	# CPA header.
	var key := ""
	if _vrel.length() < 0.5:
		key = "still"
	elif not _cpa_valid:
		key = "open|%d" % int(_rng * 10.0)
	else:
		key = "%d|%d|%d" % [int(_cpa_miss * 10.0), int(_cpa_t), int(_q >= POOR_Q)]
	if key != _s_cpa_key:
		_s_cpa_key = key
		if key == "still":
			_s_cpa = "NO RELATIVE MOTION"
		elif not _cpa_valid:
			_s_cpa = "OPENING, CPA PASSED"
		else:
			_s_cpa = "CPA %s%.1f KM IN %s" % ["" if _q >= POOR_Q else "~", _cpa_miss, _fmt_time(_cpa_t)]
			_s_cpa_lab = "CPA %s%.1f km" % ["" if _q >= POOR_Q else "~", _cpa_miss]
	# Legend line.
	var vr := _vrel.length()
	var lk := "%d|%d|%d" % [int(vr), int(_closing), int(_rng * 10.0)]
	if lk != _s_leg_key:
		_s_leg_key = lk
		_s_leg = "REL SPEED %d M/S    CLOSING %+d M/S    RANGE %.1f KM" % [int(round(vr)), int(round(_closing)), _rng]
	# Arrow time scale: the shortest listed time whose arrow is at least 8 % of the radius, else the longest.
	var rpx := _radius()
	var ppk := rpx / maxf(_extent, 0.001)
	var chosen: float = ARROW_TIMES[ARROW_TIMES.size() - 1]
	for tt in ARROW_TIMES:
		if vr * float(tt) * 0.001 * ppk >= 0.08 * rpx:
			chosen = float(tt)
			break
	if chosen != _arrow_t or _s_arrow == "":
		_arrow_t = chosen
		_s_arrow = "ARROW = %s OF TRAVEL" % (("%d S" % int(chosen)) if chosen < 120.0 else ("%d MIN" % int(chosen / 60.0)))


static func _fmt_time(s: float) -> String:
	var n := int(round(s))
	if n >= 3600:
		return "%d:%02d:%02d" % [n / 3600, (n / 60) % 60, n % 60]
	return "%d:%02d" % [n / 60, n % 60]


static func _fmt_km(k: float) -> String:
	return ("%d" % int(round(k))) if absf(k - round(k)) < 0.01 else ("%.1f" % k)


# --- geometry helpers ---------------------------------------------------------------------------------

func _radius() -> float:
	return maxf(minf(size.x * 0.5, (size.y - LEG_H) * 0.5) - 14.0, 20.0)


func _centre() -> Vector2:
	return Vector2(size.x * 0.5, (size.y - LEG_H) * 0.5 + 6.0)


func _to_px(km: Vector2, c: Vector2, ppk: float) -> Vector2:
	return Vector2(c.x + km.x * ppk, c.y - km.y * ppk)   # sim +y is screen up


static func _dir(h: float) -> Vector2:
	return Vector2(cos(h), -sin(h))


## Dashed segment a->b into the shared buffer, drawn in one multiline call.
func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dash := 7.0, gap := 5.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 1.0:
		return
	var u := d / len
	var n := mini(int(len / (dash + gap)) + 1, 300)
	_dash.resize(n * 2)
	var k := 0
	for i in n:
		var s := float(i) * (dash + gap)
		_dash[k] = a + u * s
		_dash[k + 1] = a + u * minf(s + dash, len)
		k += 2
	draw_multiline(_dash, col, w, true)


## Dashed circle drawn on ci (static layer), one multiline call, no antialiasing.
func _dashed_circle(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float, duty: float) -> void:
	if r < 2.0:
		return
	var n := clampi(int(TAU * r / 22.0), 16, 96)
	_dash.resize(n * 2)
	var da := TAU / float(n)
	for i in n:
		var a0 := float(i) * da
		var a1 := a0 + da * duty
		_dash[i * 2] = c + Vector2(cos(a0), -sin(a0)) * r
		_dash[i * 2 + 1] = c + Vector2(cos(a1), -sin(a1)) * r
	ci.draw_multiline(_dash, col, w, false)


func _ring_visible(centre: Vector2, r: float, c: Vector2, rpx: float) -> bool:
	return absf(r - centre.distance_to(c)) <= rpx * 1.5 and r > 18.0


func _label_on_ring(ci: CanvasItem, centre: Vector2, r: float, ang: float, txt: String, col: Color) -> void:
	var p := centre + _dir(ang) * r
	if p.x < 40.0 or p.x > size.x - 80.0 or p.y < 24.0 or p.y > size.y - LEG_H - 4.0:
		return
	ci.draw_string(_fm, p + Vector2(4, -3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


func _ship_glyph(p: Vector2, h: float, col: Color) -> void:
	var u := _dir(h)
	var n := Vector2(-u.y, u.x)
	_tri.resize(3)
	_tri[0] = p + u * 9.0
	_tri[1] = p - u * 6.0 + n * 5.5
	_tri[2] = p - u * 6.0 - n * 5.5
	draw_colored_polygon(_tri, Color(col, 0.35))
	_tri.resize(4)
	_tri[3] = _tri[0]
	draw_polyline(_tri, col, 1.5, true)
	draw_line(p + u * 9.0, p + u * 24.0, col, 1.5, true)   # heading tick


func _arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 2.0:
		return
	var u := d / len
	var n := Vector2(-u.y, u.x)
	var hl := minf(9.0, len * 0.5)
	draw_line(a, b, col, w, true)
	draw_line(b, b - u * hl + n * hl * 0.5, col, w, true)
	draw_line(b, b - u * hl - n * hl * 0.5, col, w, true)


# --- static layer: redrawn only when scale, size, weapon ranges or the enemy's quantised position change ----

func _draw_static(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), Color(W.SCREEN, 0.96))
	if _extent <= 0.0:
		return
	var c := _centre()
	var rpx := _radius()
	var ppk := rpx / _extent
	var ep := _to_px(_rel, c, ppk)
	var nring := _ring_lbl.size()
	for i in nring:
		var rr := float(i + 1) * _step * ppk
		ci.draw_arc(c, rr, 0.0, TAU, 72, _col_grid, 1.0, false)
		var lp := c + Vector2(-0.7071, 0.7071) * rr
		ci.draw_string(_fm, lp + Vector2(-34, 12), _ring_lbl[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, _col_grid_txt)
	_dash.resize(4)
	_dash[0] = c + Vector2(-rpx, 0)
	_dash[1] = c + Vector2(rpx, 0)
	_dash[2] = c + Vector2(0, -rpx)
	_dash[3] = c + Vector2(0, rpx)
	ci.draw_multiline(_dash, Color(W.LINE, 0.4), 1.0)
	W.text_c(ci, _fm, "N", c + Vector2(0, -rpx - 8), 11, W.MUTED)
	W.text_c(ci, _fm, "E", c + Vector2(rpx + 8, 0), 11, W.FAINT)

	# Weapon envelopes: ours centred on us, the enemy's on the enemy. Laser long dashes, gun short dots.
	var off := ""
	var wcol0 := Color(W.SEC, 0.38)
	var wcol1 := Color(W.HOT, 0.38)
	var defs := [[_r_laser0, c, wcol0, 0.6, "OUR LASER", 0.6], [_r_gun0, c, wcol0, 0.18, "OUR GUN", 2.5],
		[_r_laser1, ep, wcol1, 0.6, "FOE LASER", 0.6], [_r_gun1, ep, wcol1, 0.18, "FOE GUN", 2.5]]
	for w in defs:
		var rk: float = w[0]
		if rk <= 0.0:
			continue
		var cen: Vector2 = w[1]
		var rp := rk * ppk
		var txt := "%s %s" % [w[4], _fmt_km(rk)]
		if not _ring_visible(cen, rp, c, rpx):
			off += (", " if off != "" else "") + txt
			continue
		_dashed_circle(ci, cen, rp, w[2], 1.2, w[3])
		_label_on_ring(ci, cen, rp, w[5], txt, Color(w[2], 0.85))

	# Key, bottom-right above the legend (top-centre belongs to the alert box).
	var rw := size.x - 14.0
	var y := size.y - LEG_H - 8.0
	ci.draw_string(_fm, Vector2(0, y), "THIN = OWN VELOCITY, BOLD = RELATIVE", HORIZONTAL_ALIGNMENT_RIGHT, rw, 10, W.FAINT)
	ci.draw_string(_fm, Vector2(0, y - 14), _s_scale, HORIZONTAL_ALIGNMENT_RIGHT, rw, 11, W.FAINT)
	ci.draw_string(_fm, Vector2(0, y - 28), "NORTH-UP, SIM FRAME, OUR SHIP AT CENTRE", HORIZONTAL_ALIGNMENT_RIGHT, rw, 11, W.FAINT)
	if off != "":
		ci.draw_string(_fm, Vector2(14, y), "OFF PLOT: " + off, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, W.FAINT)
	ci.draw_line(Vector2(10, size.y - LEG_H), Vector2(size.x - 10, size.y - LEG_H), W.LINE, 1.0)


# --- dynamic layer ------------------------------------------------------------------------------------

func _draw() -> void:
	if not is_visible_in_tree() or _extent <= 0.0:
		return
	var t0 := Time.get_ticks_usec()
	var c := _centre()
	var rpx := _radius()
	var ppk := rpx / _extent
	var ep := _to_px(_rel, c, ppk)
	var poor := _q < POOR_Q

	# Enemy relative trail, oldest to newest, fading (one batched call).
	if _trail_n > 1:
		_tpts.resize(_trail_n * 2)
		_tcol.resize(_trail_n)
		var k := 0
		for i in _trail_n:
			var idx := (_trail_head - _trail_n + i + TRAIL_N * 2) % TRAIL_N
			var p := _to_px(_trail[idx], c, ppk)
			var f := float(i + 1) / float(_trail_n)
			_tpts[k] = p + Vector2(-1.5, 0)
			_tpts[k + 1] = p + Vector2(1.5, 0)
			_tcol[i] = Color(W.HOT, 0.06 + 0.5 * f * f)
			k += 2
		draw_multiline_colors(_tpts, _tcol, 3.0)

	if _beam0:
		draw_line(c, ep, Color(W.SEC, 0.55), 1.0)
	if _beam1:
		draw_line(ep, c, Color(W.HOT, 0.55), 1.0)

	# CPA: predicted relative track, clipped to the plot circle, with the miss line from us.
	var vr_kms := _vrel * 0.001
	var cpa_col := Color(W.PRI, 0.9)
	if _cpa_valid:
		var t_end := _cpa_t
		var a := vr_kms.dot(vr_kms)
		var b := 2.0 * _rel.dot(vr_kms)
		var cc := _rel.dot(_rel) - _extent * _extent
		var disc := b * b - 4.0 * a * cc
		var clipped := false
		if disc > 0.0 and _rel.length() < _extent:
			var te := (-b + sqrt(disc)) / (2.0 * a)
			if te < t_end:
				t_end = te
				clipped = true
		var track_end := _rel + vr_kms * t_end
		_dashed(ep, _to_px(track_end, c, ppk), cpa_col, 1.4)
		if not clipped:
			var cp := _to_px(track_end, c, ppk)
			draw_line(c, cp, Color(W.PRI, 0.3), 1.0)
			draw_arc(cp, 5.0, 0.0, TAU, 12, cpa_col, 1.5)
			draw_line(cp + Vector2(-8, 0), cp + Vector2(8, 0), cpa_col, 1.5)
			draw_line(cp + Vector2(0, -8), cp + Vector2(0, 8), cpa_col, 1.5)
			draw_string(_fm, cp + Vector2(10, -8), _s_cpa_lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, cpa_col)

	# Velocity vectors on one time scale: absolute thin, relative bold.
	var vs := _arrow_t * 0.001 * ppk   # px per (m/s)
	_arrow(c, c + Vector2(_v0.x, -_v0.y) * vs, Color(W.SEC, 0.5), 1.0)
	_arrow(ep, ep + Vector2(_v1.x, -_v1.y) * vs, Color(W.HOT, 0.5), 1.0)
	_arrow(ep, ep + Vector2(_vrel.x, -_vrel.y) * vs, Color(W.PRI, 1.0), 2.5 if not poor else 1.5)

	# Ships.
	if _burn0:
		draw_line(c - _dir(_h0) * 6.0, c - _dir(_h0) * 15.0, Color(W.PRI, 0.9), 3.0)
	_ship_glyph(c, _h0, W.SEC)
	if poor:
		# Uncertainty ellipse, longer along the line of sight, growing as quality falls from POOR_Q to 0.
		var k := clampf((POOR_Q - _q) / POOR_Q, 0.0, 1.0)
		var a_km := maxf(_rng * (0.04 + 0.2 * k), 12.0 / ppk)
		var los := _rel.normalized() if _rng > 0.01 else Vector2.RIGHT
		var ax := Vector2(los.x, -los.y) * a_km * ppk
		var ay := Vector2(-ax.y, ax.x) * 0.55
		_poly.resize(32)
		for i in 32:
			var th := TAU * float(i) / 32.0
			_poly[i] = ep + ax * cos(th) + ay * sin(th)
		draw_colored_polygon(_poly, Color(W.HOT, 0.14 + 0.14 * k))
		_poly.resize(33)
		_poly[32] = _poly[0]
		draw_polyline(_poly, Color(W.HOT, 0.7), 1.2, true)
		draw_arc(ep, 4.0, 0.0, TAU, 10, Color(W.HOT, 0.9), 1.5)
		var u1 := _dir(_h1)
		draw_line(ep + u1 * 6.0, ep + u1 * 20.0, Color(W.HOT, 0.45), 1.5, true)
		draw_string(_fm, ep + Vector2(12, -10), "TRACK POOR · POSITION UNCERTAIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(W.HOT, 0.9))
	else:
		if _burn1:
			draw_line(ep - _dir(_h1) * 6.0, ep - _dir(_h1) * 15.0, Color(W.PRI, 0.9), 3.0)
		_ship_glyph(ep, _h1, W.HOT)

	# Text: header top-left, arrow scale top-right, legend bottom.
	draw_string(_fh, Vector2(14, 22), "TACTICAL PLOT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, W.MUTED)
	draw_string(_fm, Vector2(14, 42), _s_cpa, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, cpa_col if _cpa_valid else W.MUTED)
	# arrow scale: with the key, bottom-right (the top-right corner holds the time-compression buttons)
	draw_string(_fm, Vector2(0, size.y - LEG_H - 8.0 - 44.0), _s_arrow, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 14.0, 12, W.PRI)
	W.text_c(self, _fm, _s_leg, Vector2(size.x * 0.5, size.y - LEG_H * 0.5), 14, W.TEXT)
	prof_usec += Time.get_ticks_usec() - t0
	prof_n += 1
