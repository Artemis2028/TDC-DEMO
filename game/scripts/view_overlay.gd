class_name ViewOverlay
extends Control
## The frame around the 3D view. The cut corners, the rule and the title are drawn once and again only
## when the title or the help line changes. The bracket, the tracers and the callouts redraw every frame.

var host
var live: Control
var _chrome_key := ""

func setup() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	live = Control.new()
	live.mouse_filter = Control.MOUSE_FILTER_IGNORE
	live.size = size
	live.draw.connect(_draw_live.bind(live))
	add_child(live)

## Queue the moving layer. The static layer is queued only when its text changed.
func request_frame() -> void:
	if host.battle == null:
		return
	# The plot sits over this frame at 96% opacity. Hiding the whole overlay (the cached chrome and the
	# live layer) is what the old single draw did by painting nothing, so the plot does not ghost the rule.
	var plot_up: bool = host.tplot != null and host.tplot.visible
	if visible == plot_up:
		visible = not plot_up
	var battle: DemoBattle = host.battle
	var q = float(battle.get_sensor_quality())
	var key = "%s|%s|%s|%s" % [host.view_target, host.armor_view, host._foe_name(), q > 0.3]
	if key != _chrome_key:
		_chrome_key = key
		queue_redraw()
	if plot_up:
		return
	live.queue_redraw()

func _draw() -> void:
	if host.battle == null:
		return
	# mask the cut corners and draw the frame
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(22, 0), Vector2(0, 22)]), W.BG)
	draw_colored_polygon(PackedVector2Array([Vector2(804, 662), Vector2(804, 684), Vector2(782, 684)]), W.BG)
	draw_polyline(PackedVector2Array([Vector2(22.5, 0.5), Vector2(803.5, 0.5), Vector2(803.5, 661.5), Vector2(781.5, 683.5), Vector2(0.5, 683.5), Vector2(0.5, 22.5), Vector2(22.5, 0.5)]), W.LINE, 1.5)
	draw_line(Vector2(22, 1), Vector2(120, 1), W.PRI, 3)
	draw_line(Vector2(1, 22), Vector2(1, 120), W.PRI, 3)
	draw_line(Vector2(803, 562), Vector2(803, 683), W.PRI, 3)
	draw_line(Vector2(782, 683), Vector2(684, 683), W.PRI, 3)
	# titles
	var title = ("TGT-1 · %s · EO RECON" % host._foe_name()) if host.view_target else ("OWN SHIP · %s" % ("ARMOR CONDITION" if host.armor_view else "REAL COLOR · SUNLIT"))
	draw_string(W.FH, Vector2(40, 38), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, W.TEXT)
	var sub = ("click a part to target it" if host.battle.get_sensor_quality() > 0.3 else "EO can't resolve parts yet: close the range") if host.view_target else "right-drag to orbit · wheel to zoom · C chase cam · Tab enemy view"
	draw_string(W.FM, Vector2(40, 56), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.MUTED)

func _draw_live(c: Control) -> void:
	if host.battle == null or host.tplot.visible: return       # the plot covers the view
	var own: Dictionary = host.S0
	var foe: Dictionary = host.S1
	var q: float = host.battle.get_sensor_quality()
	var known := q > 0.3
	_draw_tracers(c)
	_draw_beam_lines(c)
	var health: PackedFloat64Array = own["health"]
	var fh: PackedFloat64Array = foe["health"]
	if not host.view_target:
		# target bracket: where the enemy is, clamped to the view edge when off screen
		if host.cam.position.is_zero_approx(): return
		var fp: Vector3 = host.foe_model.position
		var p: Vector2 = host.cam.unproject_position(fp)
		var behind: bool = host.cam.is_position_behind(fp)
		var r := Rect2(150, 110, 804 - 300, 684 - 230)
		if behind:
			p = Vector2(804, 684) - p
		var clamped := not r.has_point(p) or behind
		p = Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
		var col := W.HOT
		for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var corner := p + s * 20
			c.draw_line(corner, corner - Vector2(s.x * 11, 0), col, 2)
			c.draw_line(corner, corner - Vector2(0, s.y * 11), col, 2)
		c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), col)
		W.text_c(c, W.FH, "TGT-1 · %s%s" % [host._foe_name(), "  · OFF VIEW" if clamped else ""], p + Vector2(0, 38), 17, col)
		host.bracket_pos = p
		W.text_c(c, W.FM, "%.1f km · closing %.2f km/s" % [host.battle.get_range_km(), host.battle.get_closing() / 1000.0], p + Vector2(0, 54), 11, W.MUTED)
		# callout: our most damaged system
		var worst := -1
		for i in 6:
			if i == 2 and int(own["gun"]) == 0: continue
			if health[i] < 100 and (worst < 0 or health[i] < health[worst]): worst = i
		if worst >= 0 and not host.cam.is_position_behind(host.own_model.sys_position(worst)):
			_callout(c, host.cam.unproject_position(host.own_model.sys_position(worst)), "%s · %d%%" % [host.SYS_NAMES[worst].to_upper(), int(health[worst])], W.hp(health[worst]))
	else:
		var ts: int = own["target_sys"]
		var tt: int = own["target_turret"]
		var fthp: PackedFloat64Array = foe["turret_hp"]
		# clickable component markers, once the EO can resolve the parts
		host.pick_points.clear()
		if known:
			for pp in host._foe_components():
				if host.cam.is_position_behind(pp[0]): continue
				var sp = host.cam.unproject_position(pp[0])
				host.pick_points.append([sp, pp[1], pp[2], pp[3]])
				var sel: bool = int(pp[1]) == ts and (int(pp[2]) < 0 or tt < 0 or int(pp[2]) == tt)
				var mc := W.PRI if sel else W.SEC
				c.draw_arc(sp, 9, 0, TAU, 20, Color(mc, 0.9), 1.5)
				c.draw_string(W.FM, sp + Vector2(12, -6), pp[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(mc, 0.9))
		var tpos: Vector3 = host.foe_model.turret_position(tt) if ts == 1 and tt >= 0 else host.foe_model.sys_position(ts)
		var oest: PackedFloat64Array = own["est"]
		var otest: PackedFloat64Array = own["turret_est"]
		var omk: PackedInt32Array = own["mark"]
		var tval: float = otest[tt] if ts == 1 and tt >= 0 else oest[ts]
		var tlab: String = host.SYS_NAMES[ts].to_upper() + ((" %d" % (tt + 1)) if ts == 1 and tt >= 0 else "")
		if not host.cam.is_position_behind(tpos):
			_callout(c, host.cam.unproject_position(tpos), "%s · %s" % [tlab, ("≈%d%%" % int(tval)) if known else "??"], W.PRI)
		# resolved components panel
		var pr := Rect2(40, 80, 210, 30 + 6 * 18)
		c.draw_rect(pr, W.PANEL)
		c.draw_rect(Rect2(pr.position + Vector2(0.5, 0.5), pr.size - Vector2(1, 1)), W.LINE, false, 1.0)
		c.draw_string(W.FH, pr.position + Vector2(10, 20), "RESOLVED COMPONENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, W.MUTED)
		for i in 6:
			var yy := pr.position.y + 40 + i * 18
			var res := q > 0.25 + i * 0.05
			var nm: String = str(host.SYS_NAMES[i]).to_upper()
			c.draw_string(W.FM, Vector2(pr.position.x + 10, yy), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, W.TEXT if res else W.FAINT)
			var v := ("≈%d%%" % int(oest[i])) if res else "??"
			if omk[i] == 2: v = "KILL " + v
			elif omk[i] == 1: v = "DEG " + v
			var vw := W.FM.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			c.draw_string(W.FM, Vector2(pr.end.x - 10 - vw, yy), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, W.hp(oest[i]) if res else W.FAINT)

func _callout(c: Control, p: Vector2, label: String, col: Color) -> void:
	var p2 := p + Vector2(-52, -54)
	var x3 := p2.x - 122
	if x3 < 30:
		p2 = p + Vector2(52, -54)
		x3 = p2.x + 122
	c.draw_arc(p, 4, 0, TAU, 16, col, 1.5)
	c.draw_line(p, p2, col, 1)
	c.draw_line(p2, Vector2(x3, p2.y), col, 1)
	var x := minf(x3, p2.x)
	c.draw_string(W.FH, Vector2(x, p2.y - 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

## Gun rounds as a glowing head with a short tail that travels with the round and fades behind it (a comet, not a
## beam): the tail runs back along the round's path for 300 m but never more than 60 px on screen. Drawn over the 3D
## view so a round reads at any zoom (not to scale: the slug is centimetres across).
func _draw_tracers(c: Control) -> void:
	for sv in host.shot_vis:
		var head: Vector3 = sv[0]
		var dir: Vector3 = sv[1]
		var col: Color = sv[2]
		if host.cam.is_position_behind(head): continue
		var hp = host.cam.unproject_position(head)
		var back := head - dir * 300.0
		if not host.cam.is_position_behind(back):
			var tail = host.cam.unproject_position(back) - hp
			if tail.length() > 60.0: tail = tail.normalized() * 60.0
			var n := 6
			for i in n:
				var a0 := float(i) / n
				var a1 := float(i + 1) / n
				var k := 1.0 - a0                                   # 1 at the head, fading toward the tail
				c.draw_line(hp + tail * a0, hp + tail * a1, Color(col, 0.9 * k * k), 0.8 + 2.6 * k, true)
		c.draw_circle(hp, 6.0, Color(col, 0.25))
		c.draw_circle(hp, 3.2, Color(col.lerp(Color.WHITE, 0.5), 0.85))
		c.draw_circle(hp, 1.6, Color.WHITE)

## Fire-control lines: a thin dashed line from each firing emitter to where its beam lands, in the HUD's side
## colours (ours blue, theirs orange). It is a display aid like a radar track line, not the beam: a laser in vacuum
## can't be seen from the side. B turns them off for the realistic view (spot and emitter glow only).
func _draw_beam_lines(c: Control) -> void:
	if not host.fc_lines or host.beam_vis.is_empty(): return
	var view = Rect2(Vector2(2, 2), host.VP.size - Vector2(4, 4))
	var to_cam: Transform3D = host.cam.global_transform.affine_inverse()
	var zn: float = -host.cam.near * 2.0
	for bv in host.beam_vis:
		var a: Vector3 = bv[0]
		var b: Vector3 = bv[1]
		var za := (to_cam * a).z
		var zb := (to_cam * b).z
		if za > zn and zb > zn: continue                   # both ends behind the camera
		if za > zn: a = a.lerp(b, (za - zn) / (za - zb))   # pull the end behind the camera up to just in front
		elif zb > zn: b = b.lerp(a, (zb - zn) / (zb - za))
		var seg = _clip(host.cam.unproject_position(a), host.cam.unproject_position(b), view)
		if seg.is_empty(): continue
		# Dashes built by hand and drawn in one call per line: draw_dashed_line issues a draw command per dash,
		# thousands a frame with three long lines on screen.
		var p0: Vector2 = seg[0]
		var p1: Vector2 = seg[1]
		var length := p0.distance_to(p1)
		var dir := (p1 - p0) / maxf(length, 0.001)
		var pts := PackedVector2Array()
		var d := 0.0
		while d < length:
			pts.append(p0 + dir * d)
			pts.append(p0 + dir * minf(d + 7.0, length))
			d += 14.0
		if pts.size() >= 2: c.draw_multiline(pts, bv[2], 1.5, false)

## The part of segment p-q inside rect r (Liang-Barsky), or [] if none of it is.
static func _clip(p: Vector2, q: Vector2, r: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := q - p
	for e in [[-d.x, p.x - r.position.x], [d.x, r.end.x - p.x], [-d.y, p.y - r.position.y], [d.y, r.end.y - p.y]]:
		var pp: float = e[0]
		var qq: float = e[1]
		if absf(pp) < 1e-9:
			if qq < 0.0: return []
			continue
		var t := qq / pp
		if pp < 0.0: t0 = maxf(t0, t)
		else: t1 = minf(t1, t)
		if t0 > t1: return []
	return [p + d * t0, p + d * t1]
