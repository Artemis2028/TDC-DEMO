class_name BattleHud
extends Node
const _ViewOverlay = preload("res://scripts/view_overlay.gd")
## The flight-deck panels: build, captions and the 15 Hz text refresh. The battle host owns the sim,
## the camera and the ships; this node only draws the panels and sends orders back through host.

var host

var overlay
var nameplate: Control
var cond_badge: Control
var clock_scr: W.Screen
var speed_btns: Array = []
var drop_txt: W.CapLine
var arm_rows: Array = []
var mode_btns: Array = []
var guard: W.Guard
var free_txt: W.CapLine
var free_sub: W.CapLine
var tgt_hdr: W.Header
var tgt_scr: W.Screen
var tgt_btns: Array = []
var helm_btns: Array = []
var drive_txt: W.CapLine
var thr_txt: W.CapLine
var thr_segs: W.Segs
var ignite: W.Btn
var dv_scr: Array = []
var fuel_txt: W.CapLine
var ball: W.Ball
var att_scr: W.Screen
var rwr_txt: W.CapLine
var view_btns: Array = []
var lamps: Array = []
var heat_rate_txt: W.CapLine
var ring: W.Ring
var heat_lines: Array = []
var rad_txt: W.CapLine
var rad_btns: Array = []
var dc_hdr: W.Header
var auto_btn: W.Btn
var paper: W.Paper
var eo_label_t1 := ""
var eo_label_t2 := ""
var scope_over: Control
var scope_foot_l: Control
var scope_foot_r: W.CapLine
var cap_top: W.CapCol
var cap_left: W.CapCol
var cap_right: W.CapCol
var cap_bottom: W.CapCol
var hud_wait := 0.0
var plate_hull := -1
var cond_shown := false
const HUD_HZ := 15.0

func build() -> void:
	_build_hud()

func update(delta: float) -> void:
	_update_hud(delta)

## Hover help: one or two plain sentences on what a control does and the reason behind it. Display-only widgets are
## switched from ignoring the mouse to passing it on, so they can show a tooltip without blocking clicks.
func _add_tooltips() -> void:
	var th := Theme.new()                # tooltips in the HUD's look rather than Godot's grey default
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.97)
	sb.border_color = W.SEC
	sb.set_border_width_all(1)
	sb.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", sb)
	th.set_font("font", "TooltipLabel", W.FM)
	th.set_font_size("font_size", "TooltipLabel", 12)
	th.set_color("font_color", "TooltipLabel", W.TEXT)
	host.hud.theme = th
	var tip := func(c: Control, t: String) -> void:
		c.tooltip_text = t
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE: c.mouse_filter = Control.MOUSE_FILTER_PASS
	tip.call(arm_rows[0][0], "The spinal gun. ARM lets fire control shoot it when the target is in arc and range.\nRounds take seconds to arrive: the hit chance falls with range and the target's manoeuvring.")
	for k in 3:
		tip.call(arm_rows[1 + k][0], "Laser turret %d. ARM lets it fire whenever the enemy is in its arc.\nThe number is the turret's condition; at 0 it is destroyed." % (k + 1))
	tip.call(mode_btns[0], "MANUAL: aim at the system you pick below and keep at it. Slightly lower hit chance.")
	tip.call(mode_btns[1], "PRESET: the picked system is a standing order; the buttons show what each aims for.")
	tip.call(mode_btns[2], "AUTO: fire control picks the target. It trusts your crew's kill marks, so a wrong mark wastes fire.")
	tip.call(guard, "Weapons safe / free (Space). Nothing fires while the guard is closed.")
	for i in tgt_btns.size():
		tip.call(tgt_btns[i], "Aim at the enemy's %s. The number is your crew's estimate (≈), not the truth.\nRight-click to mark it degraded or killed." % str(host.SYS_NAMES[int(host.TARGETS[i][0])]).to_lower())
	var helm_tips := ["Roll left (Q). Rolling turns fresh armour panels to the beam; press again to stop.",
		"Close range (W). The main drive, along the nose, when the nose is within 30° of the enemy: strong, and it adds heat. If the nose is farther off than that, the forward OMS pods push instead.",
		"Roll right (E). Rolling turns fresh armour panels to the beam; press again to stop.",
		"Match velocity with the enemy (X): burn until the range stops changing.",
		"OMS pods, push left (A): weak, but the nose stays on the enemy. During a closing burn it fires as well as the main drive, it does not replace it.",
		"Open range (S). The aft OMS pods. The main drive cannot push backward, so braking and opening the range is always the pods.",
		"OMS pods, push right (D): weak, but the nose stays on the enemy. During a closing burn it fires as well as the main drive, it does not replace it.",
		"Side-on / nose-on (T). Side-on brings every turret to bear but shows the enemy your long, thin side armour."]
	for i in helm_btns.size(): tip.call(helm_btns[i], helm_tips[i])
	tip.call(ignite, "Ignite / cut the drive (I) for the selected burn. Drive burns cost propellant (Δv) and heat.")
	for d in dv_scr: tip.call(d, "Δv remaining, m/s: every burn spends it. At zero you can't manoeuvre.")
	tip.call(ball, "Attitude: the marker is the enemy's bearing off your nose; the horizon tilts as you roll.")
	var lamp_tips := ["Weapons free: your guns may fire.", "Track: the sensors hold the enemy well enough to resolve its parts.",
		"Incoming: an enemy round is in flight toward you.", "Laser warning: an enemy beam is on your hull.",
		"Heat above 70. At 100 your weapons lock out.", "Lockout: weapons locked until heat falls below 70.",
		"Hull below 85 %.", "Drive damaged.", "Repair teams at work.", "Δv low: under 20 % propellant left.",
		"Radiators stowed: safe from hits but cooling slowly.", "Master alarm: something on this panel is red."]
	for i in lamps.size(): tip.call(lamps[i], lamp_tips[i])
	tip.call(ring, "Heat, 0 to 100. Lasers and the drive add it; radiators shed it.\nAt 100 your weapons lock out until it falls below 70.")
	tip.call(rad_btns[0], "Extend the radiators: fast cooling, but they are a large, fragile target.")
	tip.call(rad_btns[1], "Stow the radiators: safe from hits, slow cooling.")
	tip.call(auto_btn, "Auto repair: teams go to the worst damage themselves. Switch off to pick jobs by clicking the card.")
	tip.call(paper, "Damage control. Repairs in progress and damage to fix (click a line to send a team).\nCalls about the enemy are your crew's best guess: PROBABLE, and sometimes wrong.")
	# (no tooltip on the EO scope itself: clicks on it go to _unhandled_input to pick targets, and a tooltip
	# control there would swallow them; the footer label carries the hint instead)
	tip.call(scope_foot_l, "EO telescope: what your sensors actually see. Poor tracking shows as big pixels;\ncloser in it resolves the enemy's parts, which you can click to target.")
	for i in speed_btns.size() - 1: tip.call(speed_btns[i], "Time compression (P pauses, , and . step).")
	tip.call(speed_btns[-1], "Cruise and orbital transfers: not in this demo.\nThe demo battle starts close in, on a flat plane with no gravity. In the full game you plan\nthe transfer to the fight around a planet's gravity, and cruise through the long coast.")
	var view_tips := ["Look at your own ship.", "Look at the enemy as your EO sensors see it; click its parts to target them.",
		"Chase camera behind your ship (C).", "Tactical plot (V): ranges, velocities and the closest approach, top-down.",
		"Real colour.", "Armour view: each section tinted by its thinnest panel.", "", ""]
	for i in view_btns.size():
		if view_tips[i] != "": tip.call(view_btns[i], view_tips[i])

func _add(c: Control, pos: Vector2, parent: Control = null) -> Control:
	c.position = pos
	(parent if parent else host.hud).add_child(c)
	return c

func _btn(kind: String, text: String, pos: Vector2, sz: Vector2, cb: Callable = Callable(), parent: Control = null) -> W.Btn:
	var b := W.Btn.new(kind, text, sz, cb)
	_add(b, pos, parent)
	return b

func _locked(kind: String, text: String, pos: Vector2, sz: Vector2, parent: Control = null) -> W.Btn:
	var b := _btn(kind, text, pos, sz, Callable(), parent)
	b.locked = true
	b.tooltip_text = "Not in the demo. Support development on Patreon to unlock it sooner."
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b

func _painter(rect: Rect2, fn: Callable, parent: Control = null) -> Control:
	var c := Control.new()
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(fn.bind(c))
	_add(c, rect.position, parent)
	return c

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	host.hud = Control.new()
	host.hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(host.hud)
	cap_top = W.CapCol.new()
	cap_left = W.CapCol.new()
	cap_right = W.CapCol.new()
	cap_bottom = W.CapCol.new()
	_build_viewport()
	_build_top()
	_build_left()
	_build_right()
	_build_bottom()
	cap_top.line(Vector2(20, 20), "TDC DEMO · " + Version.text(), 10, W.FAINT, true, 300)
	for col in [cap_top, cap_left, cap_right, cap_bottom]:
		_add(col, Vector2.ZERO)
	_add_tooltips()

func _build_viewport() -> void:
	# The 3D view (its star sky is part of the 3D world), then the drawn overlay.
	var box := SubViewportContainer.new()
	box.position = host.VP.position
	box.size = host.VP.size
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.hud.add_child(box)
	host.view_vp = SubViewport.new()
	host.view_vp.size = Vector2i(host.VP.size)
	host.view_vp.transparent_bg = false
	host.view_vp.world_3d = host.get_world_3d()
	# 4x, not 2x: the hull's panel seams and radiator grid are thinner than a pixel at combat zoom, and at 2x they
	# break into dashes (checked side by side). The shadow and draw-call savings were kept instead.
	host.view_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(host.view_vp)
	host.cam = Camera3D.new()
	host.cam.fov = 46
	host.cam.near = 2.0
	host.cam.far = 6.0e6
	host.view_vp.add_child(host.cam)
	overlay = _ViewOverlay.new()
	overlay.host = host
	overlay.size = host.VP.size
	overlay.setup()
	_add(overlay, host.VP.position)
	host.tplot = TacticalPlot.new()            # over the 3D view and its overlay, under the alerts and time controls
	host.tplot.size = host.VP.size
	host.tplot.visible = false
	_add(host.tplot, host.VP.position)
	host.alerts = _painter(host.VP, host._draw_alerts)      # laser warning and hit callouts, on top of everything in the view
	# time compression, top right of the view
	var x = host.VP.end.x - 18 - host.SPEED_NAMES.size() * 44
	cap_top.line(Vector2(x - 42, host.VP.position.y + 22), "TIME", 10, W.FAINT, true, 40)
	for i in host.SPEED_NAMES.size():
		var idx: int = i
		if i == host.SPEED_NAMES.size() - 1:
			# Cruise belongs with orbital transfers, which the demo doesn't have: its battles start inside weapon range on
			# a flat, gravity-free plane. Shown crossed out, like the other features still to come.
			speed_btns.append(_locked("tab", host.SPEED_NAMES[i], Vector2(x + i * 44, host.VP.position.y + 16), Vector2(42, 26)))
		else:
			speed_btns.append(_btn("tab", host.SPEED_NAMES[i], Vector2(x + i * 44, host.VP.position.y + 16), Vector2(42, 26), func(): host.battle.set_speed(idx)))
	drop_txt = cap_top.line(Vector2(host.VP.end.x - 18 - 330, host.VP.position.y + 48), "", 10, W.PRI, true, 330, HORIZONTAL_ALIGNMENT_RIGHT)

func _build_top() -> void:
	# nameplate
	nameplate = _painter(Rect2(504, 0, 420, 62), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0.5, 0.5), Vector2(419.5, 0.5), Vector2(391.5, 61.5), Vector2(28.5, 61.5)]), W.PANEL)
		c.draw_polyline(PackedVector2Array([Vector2(0.5, 0.5), Vector2(419.5, 0.5), Vector2(391.5, 61.5), Vector2(28.5, 61.5), Vector2(0.5, 0.5)]), W.LINE, 1.0)
		c.draw_line(Vector2(150, 61), Vector2(270, 61), W.PRI, 3)
		if host.battle == null: return
		var own: Dictionary = host.S0
		# The coilgun ship keeps the mixed-case name. The Dagger's plate stays capitals, as before.
		var plate_name = host._own_name()
		if host.ship_class != 1: plate_name = plate_name.to_upper()
		W.text_c(c, W.FH, plate_name, Vector2(210, 15), 24, W.TEXT)
		var hullf: float = own["hull"]
		W.text_c(c, W.FM, "%s · HULL %d%%" % [host._own_class(), int(hullf * 100)], Vector2(210, 35), 11, W.MUTED)
		for k in 24:
			c.draw_rect(Rect2(210 - 24 * 11 * 0.5 + k * 11, 46, 9, 5), W.hp(hullf * 100) if float(k) / 24.0 < hullf else W.DIM))
	# condition badge and mission clock
	cond_badge = _painter(Rect2(1128, 12, 160, 30), func(c: Control):
		if host.battle == null: return
		var hot = not bool(host.battle.get_cruise_allowed())
		var col := W.HOT if hot else W.PRI
		var t := "CONDITION 1" if hot else "CONDITION 2"
		var tw := W.FH.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22
		var r := Rect2(160 - tw, 2, tw, 26)
		W.stripes(c, r, col, W.BG, 7)
		c.draw_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), W.BG)
		W.text_c(c, W.FH, t, r.get_center(), 14, col))
	cap_top.line(Vector2(1310, 6), "MISSION ELAPSED", 9, W.FAINT, true, 120)
	clock_scr = W.Screen.new("", Vector2(124, 28), W.PRI, 19)
	_add(clock_scr, Vector2(1300, 18))

func _build_left() -> void:
	_add(W.Frame.new(Rect2(16, 72, 288, 812), [0, 20, 0, 20], W.PRI, Vector2(0, 90)), Vector2(16, 72))
	var x := 30.0
	var y := 84.0
	# page tabs
	var t1 := _btn("tab", "Weapons", Vector2(x, y), Vector2(128, 32))
	t1.key = "1"; t1.active = true; t1.font_size = 14
	var t2 := _locked("tab", "EW", Vector2(x + 130, y), Vector2(128, 32))
	t2.key = "2"; t2.font_size = 14
	y += 44
	# armament
	_add(W.Header.new("Armament", W.PRI, "CB · FLAG · CTR", 260), Vector2(x, y))
	y += 31
	# rows: 0 the spinal gun, 1-3 the laser turrets, 4 the missile cells (not in the demo)
	for i in 5:
		var row_y := y + i * 38
		var arm := _btn("cap", "ARM", Vector2(x, row_y + 3), Vector2(44, 30))
		var flag := W.Flag.new()
		_add(flag, Vector2(x + 52, row_y + 8))
		var n := cap_left.line(Vector2(x + 80, row_y), "", 15, W.TEXT, false, 130)
		var s := cap_left.line(Vector2(x + 80, row_y + 19), "", 10, W.MUTED, true, 130)
		var c := W.Screen.new("--", Vector2(46, 24), W.PRI, 16)
		_add(c, Vector2(x + 214, row_y + 6))
		arm_rows.append([arm, flag, n, s, c])
	(arm_rows[0][0] as W.Btn).pressed.connect(func(): host.battle.set_armed(false, not bool(host.battle.get_ship(0)["gun_armed"])))
	for k in 3:
		var tk := k
		(arm_rows[1 + k][0] as W.Btn).pressed.connect(func(): host.battle.set_turret_armed(tk, not bool((host.battle.get_ship(0)["turret_armed"] as Array)[tk])))
	var vls: Array = arm_rows[4]
	(vls[0] as W.Btn).locked = true
	(vls[0] as W.Btn).text = "SAFE"
	vls[2].set_text("VLS ×12", W.FAINT)
	vls[3].set_text("not in demo", W.FAINT)
	(vls[4] as W.Screen).set_text("--", W.FAINT)
	y += 5 * 38 + 6
	# fire mode
	_add(W.Header.new("Fire mode", W.PRI, "", 260), Vector2(x, y))
	y += 31
	var mw := (260.0 - 4) / 3
	for m in [["F1", "Manual", 0], ["F2", "Preset", 1], ["F3", "Auto", 2]]:
		var mi: int = m[2]
		var b = _btn("tab", m[1], Vector2(x + mi * (mw + 2), y), Vector2(mw, 32), func(): host._set_mode(mi))
		b.key = m[0]; b.font_size = 12
		mode_btns.append(b)
	y += 39
	guard = W.Guard.new()
	guard.pressed.connect(host._toggle_free)
	_add(guard, Vector2(x, y))
	free_txt = cap_left.line(Vector2(x + 66, y + 10), "WEAPONS FREE", 18, W.PRI, false, 190)
	free_sub = cap_left.line(Vector2(x + 66, y + 34), "guard open · Space to safe", 10, W.MUTED, true, 190)
	y += 64
	# target select
	tgt_hdr = W.Header.new("Target select", W.PRI, "TRK --", 260)
	_add(tgt_hdr, Vector2(x, y))
	y += 31
	tgt_scr = W.Screen.new("", Vector2(260, 26), W.PRI, 13)
	_add(tgt_scr, Vector2(x, y))
	y += 33
	var cw3 := (260.0 - 8) / 3
	for i in host.TARGETS.size():
		var pos := Vector2(x + (i % 3) * (cw3 + 4), y + (i / 3) * 44)
		var si: int = host.TARGETS[i][0]
		var b = _btn("cap", host.TARGETS[i][2], pos, Vector2(cw3, 40), func(): host._pick_target(si))
		b.right_pressed.connect(func(): host._cycle_mark(si))   # right-click: unmarked -> degraded -> killed -> unmarked
		tgt_btns.append(b)
	y += 92
	var cw := (260.0 - 12) / 4
	# rotation / translation
	_add(W.Header.new("Rotation · translation", W.SEC, "", 260), Vector2(x, y))
	y += 31
	# Q / E roll about the ship's own axis (press again to stop); the nose stays where the facing order puts it.
	# T swings between nose-on (default) and side-on to the enemy.
	# Close range is the main drive (the nose cannot be pushed backward, so open range is the aft OMS).
	# A and D are the lateral pods and can stack on a closing burn. There is no separate OMS mode: the
	# order already picks the thruster, and the cap says which one.
	var helm := [["Q", "⟲ Roll", "roll-", ""], ["W", "Close", 1, "DRIVE"], ["E", "Roll ⟳", "roll+", ""], ["X", "Match", 5, ""],
		["A", "◀ Left", 3, "OMS"], ["S", "Open", 2, "OMS AFT"], ["D", "Right ▶", 4, "OMS"], ["T", "Side on", "side", ""]]
	for i in helm.size():
		var h: Array = helm[i]
		var act = h[2]
		var b = _btn("cap", h[1], Vector2(x + (i % 4) * (cw + 4), y + (i / 4) * 50), Vector2(cw, 46), func(): host._helm(act))
		b.top = h[0]
		b.sub = h[3]
		b.font_size = 11
		helm_btns.append(b)
	y += 104
	drive_txt = cap_left.line(Vector2(x, y), "", 10, W.MUTED, true, 180)
	thr_txt = cap_left.line(Vector2(x + 180, y), "", 10, W.TEXT, true, 80, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 17
	thr_segs = W.Segs.new(20, Vector2(260, 10), W.PRI)
	thr_segs.clicked.connect(func(k: int): host._set_throttle(maxf(0.1, (k + 1) / 20.0)))
	_add(thr_segs, Vector2(x, y))
	y += 18
	ignite = _btn("cap", "IGNITE", Vector2(x, y), Vector2(127, 42), host._toggle_ignite)
	ignite.hazard = true; ignite.font_size = 16
	var dark := _locked("cap", "GO DARK", Vector2(x + 133, y), Vector2(127, 42))
	dark.sub = "cut drive · sink heat"; dark.font_size = 15

func _build_bottom() -> void:
	var y := 768.0
	cap_bottom.line(Vector2(324, y + 14), "Δv REMAINING · M/S", 10, W.FAINT, true, 160)
	for i in 4:
		var d := W.Screen.new("0", Vector2(26, 38), W.PRI, 26)
		_add(d, Vector2(324 + i * 28, y + 33))
		dv_scr.append(d)
	fuel_txt = cap_bottom.line(Vector2(324, y + 76), "", 10, W.MUTED, true, 160)
	ball = W.Ball.new()
	_add(ball, Vector2(476, y + 6))
	cap_bottom.line(Vector2(604, y + 22), "ATTITUDE · Y / P / R", 10, W.FAINT, true, 170)
	att_scr = W.Screen.new("", Vector2(150, 34), W.TEXT, 19)
	_add(att_scr, Vector2(604, y + 40))
	rwr_txt = cap_bottom.line(Vector2(604, y + 80), "", 10, W.MUTED, true, 190)
	var vw := (268.0 - 9) / 4
	var views := [["Own", "own"], ["Enemy", "enemy"], ["Chase", "chase"], ["Plot", "plot"], ["Real", "real"], ["Armor", "armor"], ["Eclipse", ""], ["IR view", ""]]
	for i in views.size():
		var pos := Vector2(836 + (i % 4) * (vw + 3), y + 24 + (i / 4) * 33)
		var v: String = views[i][1]
		var b: W.Btn
		if v == "":
			b = _locked("tab", views[i][0], pos, Vector2(vw, 30))
		else:
			b = _btn("tab", views[i][0], pos, Vector2(vw, 30), func(): host._view(v))
		b.font_size = 12
		view_btns.append(b)

func _build_right() -> void:
	_add(W.Frame.new(Rect2(1128, 72, 296, 812), [20, 0, 0, 0], W.SEC, Vector2(200, 295)), Vector2(1128, 72))
	var x := 1142.0
	var y := 84.0
	# caution / warning
	_add(W.Header.new("Caution · warning", W.SEC, "", 268), Vector2(x, y))
	y += 30
	var names := ["Wpn free", "Track", "Incoming", "Laser warn", "Heat", "Lockout", "Hull", "Drive", "Repair", "Δv low", "Rad stow", "Master alm"]
	var lw := (268.0 - 6) / 3
	for i in names.size():
		var l := W.Lamp.new(names[i], Vector2(lw, 26))
		_add(l, Vector2(x + (i % 3) * (lw + 3), y + (i / 3) * 29))
		lamps.append(l)
	y += 4 * 29 + 9
	# heat
	cap_right.line(Vector2(x, y + 3), "HEAT", 18, W.HOT, false, 50)
	var ht := _btn("tab", "Thermal", Vector2(x + 50, y), Vector2(78, 26))
	ht.active = true; ht.font_size = 12
	var hs := _locked("tab", "Stealth", Vector2(x + 130, y), Vector2(78, 26))
	hs.font_size = 12
	heat_rate_txt = cap_right.line(Vector2(x + 210, y + 7), "", 10, W.FAINT, true, 58, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 33
	ring = W.Ring.new()
	_add(ring, Vector2(x, y))
	heat_lines.append(cap_right.line(Vector2(x + 90, y + 2), "", 22, W.PRI, false, 180))
	for k in 3:
		heat_lines.append(cap_right.line(Vector2(x + 90, y + 30 + k * 15), "", 11, W.TEXT, true, 180))
	y += 86
	cap_right.line(Vector2(x, y), "RADIATORS", 10, W.MUTED, true, 100)
	rad_txt = cap_right.line(Vector2(x + 100, y), "", 10, W.SEC, true, 168, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 17
	for k in 2:
		var ext := k == 0
		var b = _btn("tab", ["Extend", "Stow"][k], Vector2(x + k * 135, y), Vector2(133, 26), func(): host.battle.set_radiators(ext))
		b.font_size = 12; b.accent = W.SEC
		rad_btns.append(b)
	y += 38
	# damage control checklist
	dc_hdr = W.Header.new("Damage ctrl", W.MUTED, "", 212)
	_add(dc_hdr, Vector2(x, y))
	auto_btn = _btn("tab", "Auto", Vector2(x + 216, y - 2), Vector2(52, 24), func(): host.battle.set_auto_repair(not bool(host.battle.get_ship(0)["auto_repair"])))
	auto_btn.font_size = 11; auto_btn.accent = W.SEC
	auto_btn.tooltip_text = "Auto: repair teams take the worst damage first.\nClick a line on the card to send a team yourself."
	y += 30
	paper = W.Paper.new(Vector2(268, 104))
	paper.line_clicked.connect(host._on_dc_line)
	_add(paper, Vector2(x, y))
	y += 116
	# scope: EO only in the demo
	cap_right.line(Vector2(x, y + 4), "SCOPE", 18, W.PRI, false, 70)
	var sw := (268.0 - 72 - 8) / 5
	var sn := ["RDR", "LDR", "EO", "IR", "ESM"]
	for i in 5:
		var pos := Vector2(x + 72 + i * (sw + 2), y)
		var b: W.Btn
		if sn[i] == "EO":
			b = _btn("tab", "EO", pos, Vector2(sw, 28))
			b.active = true
		else:
			b = _locked("tab", sn[i], pos, Vector2(sw, 28))
		b.font_size = 12
	y += 34
	_painter(Rect2(x, y, 268, 268), func(c: Control):
		var p := PackedVector2Array([Vector2(13, 0), Vector2(268, 0), Vector2(268, 255), Vector2(255, 268), Vector2(0, 268), Vector2(0, 13)])
		c.draw_colored_polygon(p, W.KEY_BG)
		p.append(p[0])
		c.draw_polyline(p, W.LINE, 1.0))
	var eo := TextureRect.new()
	eo.texture = host.eo_vp.get_texture()
	eo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	eo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eo.stretch_mode = TextureRect.STRETCH_SCALE
	eo.size = Vector2(240, 240)
	eo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(eo, Vector2(x + 14, y + 14))
	host.scope_rect = Rect2(x + 14, y + 14, 240, 240)
	scope_over = _painter(Rect2(x + 14, y + 14, 240, 240), func(c: Control):
		c.draw_rect(Rect2(0.5, 0.5, 239, 239), W.LINE, false, 1.0)
		for corner in [[Vector2(4, 4), 1, 1], [Vector2(236, 4), -1, 1], [Vector2(4, 236), 1, -1], [Vector2(236, 236), -1, -1]]:
			var o: Vector2 = corner[0]
			c.draw_line(o, o + Vector2(11 * corner[1], 0), W.PRI, 2)
			c.draw_line(o, o + Vector2(0, 11 * corner[2]), W.PRI, 2)
		c.draw_string(W.FM, Vector2(10, 18), eo_label_t1, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, W.PRI)
		var tw := W.FM.get_string_size(eo_label_t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		c.draw_string(W.FM, Vector2(230 - tw, 230), eo_label_t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, W.MUTED))
	y += 274
	cap_right.line(Vector2(x, y), "EO TELESCOPE · 1.2 m", 10, W.MUTED, true, 160)
	scope_foot_l = Control.new()
	scope_foot_l.size = Vector2(160, 16)
	scope_foot_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(scope_foot_l, Vector2(x, y))
	scope_foot_r = cap_right.line(Vector2(x + 160, y), "", 10, W.SEC, true, 108, HORIZONTAL_ALIGNMENT_RIGHT)

## HUD refresh. Every frame: only what follows the 3D view or moves smoothly (the overlay, the alerts, the
## attitude ball). Everything else (panels, text, lamps, the teletype) refreshes at HUD_HZ, or at once after a
## click or key, since text that changes 60 times a second can't be read anyway and costs string building.
func _update_hud(delta: float) -> void:
	var own: Dictionary = host.S0
	var foe: Dictionary = host.S1
	# Typed, so the sim calls stay native calls. host is untyped (the scene script has no class_name).
	var battle: DemoBattle = host.battle
	overlay.request_frame()
	if host.lasing_or_popups(): host.alerts.queue_redraw()
	var rel: Vector2 = Vector2(foe["pos"]) - Vector2(own["pos"])
	var brg := rel.angle()
	var off = rad_to_deg(wrapf(brg - host.hdg_angle, -PI, PI))
	ball.set_att(host.roll_angle, off)
	hud_wait -= delta
	if hud_wait > 0.0 and not host.hud_dirty and host.shot_path == "": return
	hud_wait = 1.0 / HUD_HZ
	host.hud_dirty = false
	var health: PackedFloat64Array = own["health"]
	var fh: PackedFloat64Array = foe["health"]
	var q: float = battle.get_sensor_quality()
	var known := q > 0.3
	var t: float = battle.get_time()
	var hull_pct := int(float(own["hull"]) * 100)
	if hull_pct != plate_hull:
		plate_hull = hull_pct
		nameplate.queue_redraw()
	var cond = bool(battle.get_cruise_allowed())
	if cond != cond_shown:
		cond_shown = cond
		cond_badge.queue_redraw()
	clock_scr.set_text("%03d:%02d:%02d" % [int(t) / 3600, (int(t) / 60) % 60, int(t) % 60])
	for i in speed_btns.size():
		(speed_btns[i] as W.Btn).set_state(i == battle.get_speed())
	drop_txt.set_text(str(battle.get_drop_reason()).to_upper())

	# armament: row 0 the gun, row 1 the laser
	var gun: int = own["gun"]
	var r0: Array = arm_rows[0]
	var gb: W.Btn = r0[0]
	if gun == 0:
		(r0[1] as W.Flag).set_on(false)
		r0[2].set_text("No gun fitted", W.FAINT)
		r0[3].set_text("Lance only", W.FAINT)
		(r0[4] as W.Screen).set_text("--", W.FAINT)
		if not gb.locked or gb.text != "SAFE":
			gb.locked = true
			gb.text = "SAFE"
			gb.queue_redraw()
	else:
		var armed: bool = own["gun_armed"]
		gb.set_state(armed)
		gb.set_text("ARM" if armed else "SAFE")
		(r0[1] as W.Flag).set_on(armed)
		var gh := health[2]
		var name := "Spinal coilgun" if gun == 2 else "Railgun"
		r0[2].set_text(name, (W.PRI if armed else W.MUTED) if gh > 0 else W.HOT)
		var cd: float = own["gun_cooldown"]
		var sub := ""
		if gh <= 0: sub = "DESTROYED"
		elif cd > 0: sub = "RLD %02d s" % int(ceil(cd))
		elif battle.get_hit_chance() > 0: sub = "RDY · ▸ %s · %d%%" % [host.SYS_ABBR[int(own["target_sys"])], int(battle.get_hit_chance() * 100)]
		else: sub = "RDY · no arc/range"
		r0[3].set_text(sub, W.HOT if gh <= 0 else W.MUTED)
		(r0[4] as W.Screen).set_text("%02d" % int(own["ammo"]), W.PRI if armed else W.MUTED)
	# laser turrets: each its own row; the counter is the turret's condition
	var thp: PackedFloat64Array = own["turret_hp"]
	var tarm: Array = own["turret_armed"]
	var tfire: Array = own["turret_firing"]
	var tbear: Array = own["turret_bears"]
	for k in 3:
		var row: Array = arm_rows[1 + k]
		var armed_k: bool = tarm[k]
		var hp_k: float = thp[k]
		(row[0] as W.Btn).set_state(armed_k)
		(row[0] as W.Btn).set_text("ARM" if armed_k else "SAFE")
		(row[1] as W.Flag).set_on(armed_k)
		var col := W.HOT if hp_k <= 0 else (W.PRI if tfire[k] else (W.TEXT if armed_k else W.MUTED))
		row[2].set_text("Laser %d" % (k + 1), col)
		var st := "SAFE"
		if hp_k <= 0: st = "DESTROYED"
		elif bool(own["overheated"]) and armed_k: st = "LOCKOUT · HEAT"
		elif tfire[k]: st = "FIRING ▸ %s" % host.SYS_ABBR[int(own["target_sys"])]
		elif armed_k and not tbear[k]: st = "NO ARC · hull blocks"
		elif armed_k: st = "RDY · ⅓ power"
		row[3].set_text(st, W.HOT if hp_k <= 0 or st.begins_with("LOCKOUT") else W.MUTED)
		(row[4] as W.Screen).set_text("%d" % int(hp_k), W.hp(hp_k) if hp_k > 0 else W.HOT)

	# fire mode
	var mode: int = own["fire_mode"]
	var ui_mode = 2 if mode == 0 else (1 if host.preset_mode else 0)
	for i in 3:
		(mode_btns[i] as W.Btn).set_state(i == ui_mode)
	var free: bool = own["weapons_free"]
	guard.set_open(free)
	free_txt.set_text("WEAPONS FREE" if free else "WEAPONS SAFE", W.PRI if free else W.MUTED)
	free_sub.set_text("guard open · Space to safe" if free else "guard closed · Space to arm")

	# target select
	var ts: int = own["target_sys"]
	tgt_hdr.set_hint("TRK %d%%" % int(q * 100))
	var tt: int = own["target_turret"]
	var fthp: PackedFloat64Array = foe["turret_hp"]
	var tname: String = host.SYS_NAMES[ts].to_upper() + ((" %d" % (tt + 1)) if ts == 1 and tt >= 0 else "")
	# The enemy as our crew sees it: estimates (~, rounded to 10) and our own kill marks, never the truth.
	var est: PackedFloat64Array = own["est"]
	var test: PackedFloat64Array = own["turret_est"]
	var mk: PackedInt32Array = own["mark"]
	var tmk: PackedInt32Array = own["turret_mark"]
	var tval := test[tt] if ts == 1 and tt >= 0 else est[ts]
	tgt_scr.set_text("%s|▸ %s|%s" % [host._foe_name().replace("MRS ", ""), tname, ("≈%d%%" % int(tval)) if known else "??"])
	for i in host.TARGETS.size():
		var b: W.Btn = tgt_btns[i]
		var si: int = host.TARGETS[i][0]
		var hv: float = est[si]
		var v := ("≈%d" % int(hv)) if known else "??"
		var m: int = mk[si]
		if si == 1:
			var all_same := tmk[0] == tmk[1] and tmk[1] == tmk[2]
			m = tmk[tt] if ts == 1 and tt >= 0 else (tmk[0] if all_same else 0)
		if si == 1 and ts == 1 and int(own["fire_mode"]) == 1:
			v = ("ANY" if tt < 0 else "#%d" % (tt + 1)) + ((" · ≈%d" % int(test[tt] if tt >= 0 else hv)) if known else "")
		b.set_mark(m)
		if host.preset_mode:
			b.set_text(host.TARGETS[i][3], host.TARGETS[i][2])
		else:
			b.set_text(host.TARGETS[i][2], v)
		b.set_state(si == ts)
		var dash := not known
		if b.dashed != dash:
			b.dashed = dash
			b.modulate.a = 0.45 if dash else 1.0
			b.queue_redraw()

	# helm and drive
	var facing: int = own["facing"]
	var rolling: int = own["roll_dir"]
	var burn: int = own["burn"]
	var helm_act := [-1, 1, -3, 5, 3, 2, 4, -2]
	for i in helm_btns.size():
		var a: int = helm_act[i]
		var on := false
		if a == -1: on = rolling == -1
		elif a == -3: on = rolling == 1
		elif a == -2: on = facing == 1
		else: on = a == (burn if burn != 0 else host.sel_burn)
		if burn == 1 and a == 3 and int(own["oms_strafe"]) == 1: on = true
		if burn == 1 and a == 4 and int(own["oms_strafe"]) == -1: on = true
		(helm_btns[i] as W.Btn).set_state(on)
	var oms_on := (own["oms"] as Vector2).length() > 0.01
	if own["burning"] and oms_on: drive_txt.set_text("MAIN DRIVE + OMS", W.PRI)
	elif own["burning"]: drive_txt.set_text("MAIN DRIVE · BURNING", W.PRI)
	elif oms_on: drive_txt.set_text("OMS PODS · FIRING", W.SEC)
	else: drive_txt.set_text("MAIN DRIVE · IDLE", W.MUTED)
	thr_txt.set_text("THR %d%%" % int(round(host.throttle * 100)))
	thr_segs.set_on(int(round(host.throttle * 20)), W.PRI if burn != 0 else W.KEY_LINE)
	ignite.set_text("CUT DRIVE" if burn != 0 else "IGNITE")
	ignite.accent = W.HOT if burn != 0 else W.PRI

	# Δv and attitude
	var dv: float = own["dv_left"]
	var dv_s := "%04d" % clampi(int(dv), 0, 9999)
	for i in 4:
		(dv_scr[i] as W.Screen).set_text(dv_s[i], W.PRI if dv > 0.2 * float(own["dv_max"]) else W.HOT)
	fuel_txt.set_text("PROPELLANT %d%%" % int(100.0 * dv / maxf(1.0, float(own["dv_max"]))))
	var hdg := int(round(rad_to_deg(wrapf(float(own["heading"]), 0, TAU)))) % 360
	att_scr.set_text("%03d %+03d %+04d" % [hdg, 0, int(rad_to_deg(host.roll_angle))])
	if foe["laser_firing"]:
		rwr_txt.set_text("LASER WARNING · UNDER FIRE", W.HOT)
	else:
		rwr_txt.set_text("TGT BRG %03d · OFF NOSE %+d°" % [int(round(rad_to_deg(wrapf(brg, 0, TAU)))) % 360, int(off)], W.MUTED)
	var vstate = [not host.view_target and not host.tplot.visible, host.view_target and not host.tplot.visible, host.chase, host.tplot.visible, not host.armor_view, host.armor_view, false, false]
	for i in view_btns.size():
		(view_btns[i] as W.Btn).set_state(vstate[i])

	# caution / warning
	var heat: float = own["heat"]
	var incoming := false
	for s in host.SHOTS:
		if int(s["shooter"]) == 1: incoming = true
	var reps: Array = own["repairs"]
	var states := [
		"a" if free else "",
		"s" if known else "",
		"r" if incoming else "",
		"r" if foe["laser_firing"] else "",
		("r" if heat >= 90 else "a") if heat >= 70 else "",
		"r" if bool(own["overheated"]) else "",
		("r" if float(own["hull"]) < 0.5 else "a") if float(own["hull"]) < 0.85 else "",
		("r" if health[0] <= 0 else "a") if health[0] < 60 else "",
		"s" if reps.size() > 0 else "",
		"a" if dv < 0.2 * float(own["dv_max"]) else "",
		"a" if not bool(own["radiators_extended"]) else "",
		"",
	]
	var any_red := false
	for s in states:
		if s == "r": any_red = true
	states[11] = "r" if any_red else ""
	for i in lamps.size():
		(lamps[i] as W.Lamp).set_lamp(states[i])

	# heat
	ring.set_value(heat)
	heat_rate_txt.set_text("%+.1f/s" % host.heat_rate, W.HOT if host.heat_rate > 0.3 else W.FAINT)
	var big = heat_lines[0]
	if bool(own["overheated"]):
		big.set_text("LOCKOUT", W.HOT)
	elif host.heat_rate > 0.05:
		var s = (100.0 - heat) / host.heat_rate
		big.set_text("%d:%02d to lockout" % [int(s) / 60, int(s) % 60], W.PRI)
	else:
		big.set_text("STABLE", W.SEC)
	heat_lines[1].set_text("Heat %d / 100" % int(heat))
	heat_lines[2].set_text("Weapons lock at 100" if not bool(own["overheated"]) else "Locked until below 70", W.TEXT if not bool(own["overheated"]) else W.HOT)
	heat_lines[3].set_text("Laser & drive add heat", W.MUTED)
	var ext: bool = own["radiators_extended"]
	rad_txt.set_text("EXTENDED · fast cooling" if ext else "STOWED · safe from hits", W.SEC if ext else W.PRI)
	(rad_btns[0] as W.Btn).set_state(ext)
	(rad_btns[1] as W.Btn).set_state(not ext)

	# damage control card
	var teams: int = own["teams"]
	dc_hdr.set_hint("TEAMS %d/%d" % [teams - reps.size(), teams])
	auto_btn.set_state(own["auto_repair"])
	var pl: Array = []
	host.dc_line_sys.clear()
	var busy := {}
	# The laser is judged by its worst turret: that is the one a team works on.
	var worst_t := 0
	for k in 3:
		if thp[k] < thp[worst_t]: worst_t = k
	var need := health.duplicate()
	need[1] = thp[worst_t]
	var dc_name = host.SYS_NAMES.duplicate()
	dc_name[1] = "Laser %d" % (worst_t + 1)
	for r in reps:
		busy[int(r["sys"])] = true
		pl.append(["☐", "REPAIR %s" % str(dc_name[int(r["sys"])]).to_upper(), "%d s" % int(ceil(float(r["left"]))), W.INK])
		host.dc_line_sys.append(-1)
	var dmg: Array = []
	for i in 6:
		if i == 2 and gun == 0: continue
		if need[i] < 100 and not busy.has(i): dmg.append(i)
	dmg.sort_custom(func(a, b): return need[a] < need[b])
	for i in dmg:
		if pl.size() >= 5: break
		var hv: float = need[i]
		pl.append(["⚠" if hv < 45 else "▸", "%s %d%%  ▸ FIX" % [str(dc_name[i]).to_upper(), int(hv)], "", W.INK_HOT if hv < 45 else W.INK])
		host.dc_line_sys.append(i)
	if pl.is_empty():
		pl.append(["☒", "ALL SYSTEMS NOMINAL", "", W.INK])
		host.dc_line_sys.append(-1)
	# The newest call on the enemy prints big and bold at the top for 20 s of battle time; older ones as plain lines.
	var banner := -1
	for k in range(host.log_lines.size() - 1, -1, -1):
		if host.log_lines[k][2]:
			if battle.get_time() - float(host.log_lines[k][3]) < 20.0: banner = k
			break
	if banner >= 0:
		var bl: Array = host.log_lines[banner]
		var btxt := str(bl[0]).to_upper().replace(": ", " · ")
		pl.insert(0, ["◆", btxt, bl[1], W.INK_HOT, true])
		host.dc_line_sys.insert(0, -1)
	for k in range(host.log_lines.size() - 1, -1, -1):
		if pl.size() >= (4 if banner >= 0 else 5): break
		if k == banner: continue
		var l: Array = host.log_lines[k]
		var txt: String = host._teletype(str(l[0])) if l[2] else str(l[0]).to_upper()
		if txt.length() > 24: txt = txt.substr(0, 23) + "…"
		pl.append(["◆" if l[2] else "☒", txt, l[1], W.INK_HOT if l[2] else W.INK_DIM])
		host.dc_line_sys.append(-1)
	paper.set_lines(pl)

	# scope
	var l1 := "EO · VIS · TRK %d%%" % int(q * 100)
	var l2 := "components resolved" if q > 0.5 else ("outline only" if q > 0.25 else "point source")
	if l1 != eo_label_t1 or l2 != eo_label_t2:
		eo_label_t1 = l1
		eo_label_t2 = l2
		scope_over.queue_redraw()
	scope_foot_r.set_text("TRACK %d%%" % int(q * 100))
