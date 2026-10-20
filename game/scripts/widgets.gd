class_name W
## Hand-drawn HUD widgets for the CIC flight-deck look: slanted tabs, keycaps with a heavy bottom edge,
## hazard stripes, annunciators, segment bars, a punched checklist card and an attitude ball.
## Anything not in the demo is drawn with a red X through it and does nothing.

const BG := Color("#070b10")
const PANEL := Color(0.047, 0.075, 0.102, 0.94)
const LINE := Color("#2a3946")
const TEXT := Color("#d2dbe0")
const MUTED := Color("#7d8f9a")
const FAINT := Color("#5d707c")
const PRI := Color("#f2a531")
const PRI_INK := Color("#140c00")
const SEC := Color("#6cc7e0")
const HOT := Color("#ff5a36")
const WARN := Color("#e8c547")     # degraded marks
const DIM := Color("#1b2731")
const PAPER := Color("#d9dedd")
const INK := Color("#1b2731")
const INK_HOT := Color("#b8361a")
const INK_DIM := Color("#6b7a82")
const SCREEN := Color("#04080b")
const KEY_BG := Color("#121b23")
const KEY_LINE := Color("#4a5d6b")
const GOOD := Color("#cfe3ea")
const BALL_SKY := Color("#1d3a4c")
const BALL_GND := Color("#4a2b16")

## HUD type: Saira (bold, semi-condensed) for labels and headings, Share Tech Mono for readouts. Both from the
## Google Fonts repository under the SIL Open Font License (licences beside them in fonts/).
static var FH: Font = _saira(700, 87.5)
static var FM: Font = load("res://fonts/ShareTechMono-Regular.ttf")

static func _saira(weight: float, width: float) -> Font:
	var ts := TextServerManager.get_primary_interface()
	var f := FontVariation.new()
	f.base_font = load("res://fonts/Saira-Variable.ttf")
	f.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): width}
	return f

static func hp(v: float) -> Color:
	return GOOD if v > 75 else (PRI if v > 45 else HOT)

static func draw_x(ci: CanvasItem, r: Rect2) -> void:
	var c := Color(HOT, 0.9)
	ci.draw_line(r.position + Vector2(3, 3), r.end - Vector2(3, 3), c, 2.0, true)
	ci.draw_line(Vector2(r.end.x - 3, r.position.y + 3), Vector2(r.position.x + 3, r.end.y - 3), c, 2.0, true)

static func text_c(ci: CanvasItem, font: Font, s: String, center: Vector2, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	ci.draw_string(font, Vector2(center.x - w * 0.5, center.y + size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

static func stripes(ci: CanvasItem, r: Rect2, a: Color, b: Color, step := 7.0) -> void:
	ci.draw_rect(r, b)
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var pts := PackedVector2Array()
		for p in [Vector2(x, r.end.y), Vector2(x + step, r.end.y), Vector2(x + step + r.size.y, r.position.y), Vector2(x + r.size.y, r.position.y)]:
			pts.append(Vector2(clamp(p.x, r.position.x, r.end.x), p.y))
		ci.draw_colored_polygon(pts, a)
		x += step * 2

## A clickable HUD control drawn by hand. kind: "tab" (slanted), "cap" (keycap), "arm", "plain".
class Btn extends Control:
	var kind := "cap"
	var text := ""
	var sub := ""
	var key := ""
	var active := false
	var locked := false
	var accent := PRI
	var font_size := 13
	var hazard := false
	var dashed := false
	var top := ""          # small key label above the main label (helm caps)
	var mark := 0          # the crew's mark on a target: 0 none, 1 degraded (amber tag), 2 killed (red X)
	signal pressed
	signal right_pressed

	func _init(k: String, t: String, size_px: Vector2, on_press: Callable = Callable()) -> void:
		kind = k
		text = t
		custom_minimum_size = size_px
		size = size_px
		mouse_filter = Control.MOUSE_FILTER_STOP
		if on_press.is_valid():
			pressed.connect(on_press)

	func set_state(on: bool) -> void:
		if on != active:
			active = on
			queue_redraw()

	func set_text(t: String, s: String = sub) -> void:
		if t != text or s != sub:
			text = t
			sub = s
			queue_redraw()

	func set_mark(m: int) -> void:
		if m != mark:
			mark = m
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if locked:
			return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			pressed.emit()
			accept_event()
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			right_pressed.emit()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var on := active and not locked
		var bg := accent if on else KEY_BG
		var fg := PRI_INK if on else (FAINT if locked else (MUTED if kind == "tab" else TEXT))
		if kind == "tab":
			var s := 9.0
			draw_colored_polygon(PackedVector2Array([Vector2(s, 0), Vector2(r.size.x, 0), Vector2(r.size.x - s, r.size.y), Vector2(0, r.size.y)]), bg)
		elif hazard:
			W.stripes(self, r, accent, BG, 8)
			draw_rect(Rect2(3, 3, r.size.x - 6, r.size.y - 6), BG)
			fg = TEXT
		else:
			draw_rect(r, bg)
			var edge := accent if on else KEY_LINE
			if dashed and not on:
				edge = Color(KEY_LINE, 0.5)
			draw_rect(Rect2(0.5, 0.5, r.size.x - 1, r.size.y - 1), edge, false, 1.0)
			draw_rect(Rect2(0, r.size.y - 4, r.size.x, 4), edge)
		var cx := r.size.x * 0.5
		var cy := r.size.y * 0.5 - (2.0 if kind != "tab" else 0.0)
		var label := text.to_upper()
		if key != "":
			# key badge, then the label
			var lw := W.FH.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var bw := maxf(17.0, W.FM.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6)
			var x0 := cx - (lw + bw + 7) * 0.5
			var br := Rect2(x0, cy - 8.5, bw, 17)
			draw_rect(br, PRI_INK if on else KEY_BG)
			draw_rect(Rect2(br.position.x + 0.5, br.position.y + 0.5, br.size.x - 1, br.size.y - 1), PRI_INK if on else KEY_LINE, false, 1.0)
			draw_rect(Rect2(br.position.x, br.end.y - 3, br.size.x, 3), PRI_INK if on else KEY_LINE)
			W.text_c(self, W.FM, key, br.get_center() - Vector2(0, 1), 10, PRI if on else TEXT)
			draw_string(W.FH, Vector2(x0 + bw + 7, cy + font_size * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)
		elif top != "" and sub != "":
			# Helm key, the order, and which thrusters do it. Three lines fit a 46 px cap.
			W.text_c(self, W.FM, top, Vector2(cx, 10), 10, PRI_INK if on else FAINT)
			W.text_c(self, W.FH, label, Vector2(cx, 24), font_size, fg)
			W.text_c(self, W.FM, sub, Vector2(cx, 36), 9, PRI_INK if on else FAINT)
		elif top != "":
			W.text_c(self, W.FM, top, Vector2(cx, cy - 8), 10, PRI_INK if on else FAINT)
			W.text_c(self, W.FH, label, Vector2(cx, cy + 7), font_size, fg)
		elif sub != "":
			W.text_c(self, W.FH, label, Vector2(cx, cy - 6), font_size, fg)
			W.text_c(self, W.FM, sub, Vector2(cx, cy + 9), 10, fg)
		else:
			W.text_c(self, W.FH, label, Vector2(cx, cy), font_size, fg)
		if locked:
			W.draw_x(self, r)
		if mark == 1:                      # degraded: amber frame and corner tag
			draw_rect(Rect2(1, 1, r.size.x - 2, r.size.y - 2), WARN, false, 2.0)
			draw_rect(Rect2(r.size.x - 26, 0, 26, 12), WARN)
			W.text_c(self, W.FM, "DEG", Vector2(r.size.x - 13, 5.5), 9, BG)
		elif mark == 2:                    # killed: the crew's red X
			W.draw_x(self, r)
			draw_rect(Rect2(r.size.x - 30, 0, 30, 12), HOT)
			W.text_c(self, W.FM, "KILL", Vector2(r.size.x - 15, 5.5), 9, BG)

## Section header: coloured title, a rule, and a faint hint on the right.
class Header extends Control:
	var title := ""
	var hint := ""
	var col := PRI
	func _init(t: String, c: Color = PRI, h: String = "", w := 260.0) -> void:
		title = t; col = c; hint = h
		custom_minimum_size = Vector2(w, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_hint(h: String) -> void:
		if h != hint: hint = h; queue_redraw()
	func _draw() -> void:
		var t := title.to_upper()
		draw_string(W.FH, Vector2(0, 17), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		var tw := W.FH.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var hw := W.FM.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x if hint != "" else 0.0
		draw_rect(Rect2(tw + 8, 11, size.x - tw - 16 - hw - (8 if hint != "" else 0), 2), LINE)
		if hint != "":
			draw_string(W.FM, Vector2(size.x - hw, 16), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, FAINT)

## Plain text in the HUD fonts.
class Txt extends Control:
	var text := ""
	var mono := true
	var fsize := 11
	var col := MUTED
	var align := HORIZONTAL_ALIGNMENT_LEFT
	func _init(t: String, s: int, c: Color, is_mono := true, w := 100.0, h := 0.0) -> void:
		text = t; fsize = s; col = c; mono = is_mono
		custom_minimum_size = Vector2(w, h if h > 0 else s + 5)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_text(t: String, c: Color = col) -> void:
		if t != text or c != col: text = t; col = c; queue_redraw()
	func _draw() -> void:
		var f := W.FM if mono else W.FH
		var y := fsize
		for line in text.split("\n"):
			draw_string(f, Vector2(0, y), line, align, size.x, fsize, col)
			y += int(fsize * 1.4)

## Sunken screen box with a value in it.
class Screen extends Control:
	var text := ""
	var col := PRI
	var fsize := 16
	var center := true
	func _init(t: String, size_px: Vector2, c: Color = PRI, s := 16) -> void:
		text = t; col = c; fsize = s
		custom_minimum_size = size_px; size = size_px
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_text(t: String, c: Color = col) -> void:
		if t != text or c != col: text = t; col = c; queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), SCREEN)
		draw_rect(Rect2(0, 0, size.x, 3), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(0.5, 0.5, size.x - 1, size.y - 1), LINE, false, 1.0)
		if text.contains("|"):
			# space-between layout: first part left, last part right, the rest centred
			var parts := text.split("|")
			var y := size.y * 0.5 + fsize * 0.36
			draw_string(W.FM, Vector2(9, y), parts[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
			var lw := W.FM.get_string_size(parts[parts.size() - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
			draw_string(W.FM, Vector2(size.x - 9 - lw, y), parts[parts.size() - 1], HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
			for i in range(1, parts.size() - 1):
				W.text_c(self, W.FM, parts[i], Vector2(size.x * i / (parts.size() - 1), size.y * 0.5), fsize, col)
		elif center:
			W.text_c(self, W.FM, text, size * 0.5, fsize, col)
		else:
			draw_string(W.FM, Vector2(9, size.y * 0.5 + fsize * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, fsize, col)

## Row of segments (hull, throttle, signature).
class Segs extends Control:
	var n := 20
	var on := 0
	var col := SEC
	var gap := 2.0
	signal clicked(index: int)
	func _init(count: int, size_px: Vector2, c: Color = SEC) -> void:
		n = count; col = c
		custom_minimum_size = size_px; size = size_px
	func set_on(k: int, c: Color = col) -> void:
		if k != on or c != col: on = k; col = c; queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(int(clamp(e.position.x / size.x * n, 0, n - 1)))
	func _draw() -> void:
		var w := (size.x - gap * (n - 1)) / n
		for k in n:
			draw_rect(Rect2(k * (w + gap), 0, w, size.y), col if k < on else DIM)

## Caution/warning annunciator cell: 'a' amber, 'r' red, 's' cyan, '' dark.
class Lamp extends Control:
	var text := ""
	var state := ""
	func _init(t: String, size_px: Vector2) -> void:
		text = t
		custom_minimum_size = size_px; size = size_px
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_lamp(s: String) -> void:
		if s != state: state = s; queue_redraw()
	func _draw() -> void:
		var bg := {"a": PRI, "r": HOT, "s": SEC}.get(state, KEY_BG) as Color
		if state != "":
			draw_rect(Rect2(-3, -3, size.x + 6, size.y + 6), Color(bg, 0.25))
		draw_rect(Rect2(Vector2.ZERO, size), bg)
		draw_rect(Rect2(0.5, 0.5, size.x - 1, size.y - 1), LINE, false, 1.0)
		W.text_c(self, W.FH, text.to_upper(), size * 0.5, 12, PRI_INK if state != "" else FAINT)

## Panel with cut corners and an accent bar along the top edge.
class Frame extends Control:
	var cuts := [0, 20, 20, 0]       # top-left, top-right, bottom-right, bottom-left
	var accent := PRI
	var accent_x := Vector2(0, 90)
	var fill := PANEL
	func _init(r: Rect2, c: Array, acc: Color, acc_x: Vector2, f: Color = PANEL) -> void:
		position = r.position; size = r.size; custom_minimum_size = r.size
		cuts = c; accent = acc; accent_x = acc_x; fill = f
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _poly() -> PackedVector2Array:
		var w := size.x
		var h := size.y
		var a: float = cuts[0]
		var b: float = cuts[1]
		var c: float = cuts[2]
		var d: float = cuts[3]
		return PackedVector2Array([Vector2(a, 0), Vector2(w - b, 0), Vector2(w, b), Vector2(w, h - c), Vector2(w - c, h), Vector2(d, h), Vector2(0, h - d), Vector2(0, a)])
	func _draw() -> void:
		var p := _poly()
		if fill.a > 0:
			draw_colored_polygon(p, fill)
		var q := p.duplicate()
		q.append(p[0])
		draw_polyline(q, LINE, 1.5)
		draw_line(Vector2(accent_x.x, 1.5), Vector2(accent_x.y, 1.5), accent, 3)

## Punched checklist card. Clicking a line emits line_clicked(index).
class Paper extends Control:
	var lines: Array = []   # [box, text, time, colour, big?]; a big line prints large and bold across the top
	var _rows: Array = []   # [top y, bottom y] of each line as drawn, for clicks
	signal line_clicked(index: int)
	func _init(size_px: Vector2) -> void:
		custom_minimum_size = size_px; size = size_px
		mouse_filter = Control.MOUSE_FILTER_STOP
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			for i in _rows.size():
				if e.position.y >= _rows[i][0] and e.position.y < _rows[i][1]:
					line_clicked.emit(i)
					return
	func set_lines(l: Array) -> void:
		if l == lines: return       # same text: keep the drawing (arrays compare by content)
		lines = l; queue_redraw()
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h - 5)])
		var k := 20
		for i in range(k, -1, -1):
			pts.append(Vector2(w * i / k, h if i % 2 == 1 else h - 5))
		draw_colored_polygon(pts, PAPER)
		_rows.clear()
		var y := 18.0
		for i in lines.size():
			var l: Array = lines[i]
			if l.size() > 4 and l[4]:
				# big bold line: shrink the type until it fits the paper
				var fs := 17
				while fs > 11 and W.FH.get_string_size(str(l[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > w - 14:
					fs -= 1
				draw_rect(Rect2(3, y - 15, w - 6, 26), Color(l[3], 0.12))
				draw_string(W.FH, Vector2(7, y + 3), str(l[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, l[3])
				_rows.append([y - 15, y + 11])
				y += 28
				continue
			draw_circle(Vector2(10, y - 4), 3.5, BG)
			draw_string(W.FM, Vector2(22, y), str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, l[3])
			draw_string(W.FH, Vector2(40, y), str(l[1]), HORIZONTAL_ALIGNMENT_LEFT, w - 100, 12, l[3])
			var tw := W.FM.get_string_size(str(l[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(W.FM, Vector2(w - 10 - tw, y), str(l[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(l[3], 0.7))
			_rows.append([y - 14, y + 4])
			y += 18

## Attitude ball: sky over ground, turned by the roll, the horizon shifted by pitch; a red marker for the target.
class Ball extends Control:
	var roll := 0.0
	var off_tgt := 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(104, 104); size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_att(r: float, o: float) -> void:
		# redrawn only when the picture would change (65 trig points and two arcs per redraw)
		if absf(r - roll) < 0.002 and absf(o - off_tgt) < 0.25: return
		roll = r; off_tgt = o; queue_redraw()
	func _draw() -> void:
		var c := Vector2(52, 52)
		var R := 42.0
		var pts_sky := PackedVector2Array()
		var pts_gnd := PackedVector2Array()
		var horizon := 6.0
		for i in 65:
			var a := TAU * i / 64
			var p := c + Vector2(cos(a), sin(a)) * R
			var local := (p - c).rotated(-roll)
			if local.y < horizon: pts_sky.append(p)
			else: pts_gnd.append(p)
		draw_circle(c, R, BALL_GND)
		# sky half: a half-disc turned by roll
		var sky := PackedVector2Array()
		for i in 33:
			var a := PI + PI * i / 32
			sky.append(c + Vector2(cos(a), sin(a)).rotated(roll) * R + Vector2(0, horizon).rotated(roll))
		draw_colored_polygon(sky, BALL_SKY)
		var hl := Vector2(R, 0).rotated(roll)
		var hc := c + Vector2(0, horizon).rotated(roll)
		draw_line(hc - hl, hc + hl, TEXT, 1.5)
		draw_arc(c, R, 0, TAU, 64, LINE, 2)
		draw_arc(c, 49, 0, TAU, 48, Color(PRI, 0.5), 1)
		draw_polyline(PackedVector2Array([c + Vector2(-19, 0), c + Vector2(-8, 0), c + Vector2(0, 6), c + Vector2(8, 0), c + Vector2(19, 0)]), PRI, 2.5)
		var m := c + Vector2(clamp(off_tgt * 2.0, -38, 38), -20)
		draw_colored_polygon(PackedVector2Array([m + Vector2(0, -5), m + Vector2(5, 0), m + Vector2(0, 5), m + Vector2(-5, 0)]), HOT)

## Ring gauge for heat.
class Ring extends Control:
	var value := 0.0
	func _init() -> void:
		custom_minimum_size = Vector2(78, 78); size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_value(v: float) -> void:
		if absf(v - value) > 0.2: value = v; queue_redraw()
	func _draw() -> void:
		var c := Vector2(39, 39)
		var segs := 20
		for k in segs:
			var a0 := -PI * 0.5 + TAU * k / segs + 0.04
			var a1 := -PI * 0.5 + TAU * (k + 1) / segs - 0.04
			var lit := float(k) / segs < value / 100.0
			var col := (HOT if value >= 80 else (PRI if value >= 50 else SEC)) if lit else DIM
			draw_arc(c, 32, a0, a1, 6, col, 8)
		W.text_c(self, W.FH, "%d" % int(value), c + Vector2(0, -2), 20, TEXT)
		W.text_c(self, W.FM, "HEAT", c + Vector2(0, 14), 8, FAINT)

## Weapon flag: amber when armed, hazard-striped when safe.
class Flag extends Control:
	var on := false
	func _init() -> void:
		custom_minimum_size = Vector2(20, 20); size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_on(v: bool) -> void:
		if v != on: on = v; queue_redraw()
	func _draw() -> void:
		var c := Vector2(10, 10)
		if on:
			draw_circle(c, 9, PRI)
		else:
			draw_circle(c, 9, BG)
			for k in range(-3, 4):
				var o := k * 4.5
				var a := Vector2(o - 9, 9).rotated(-PI / 4) + c
				var b := Vector2(o - 9, -9).rotated(-PI / 4) + c
				# clip the stripe to the disc by sampling along it
				var pts := PackedVector2Array()
				for t in 9:
					var p := a.lerp(b, t / 8.0)
					if p.distance_to(c) <= 8.5: pts.append(p)
				if pts.size() >= 2: draw_polyline(pts, PRI, 2.0)
		draw_arc(c, 9, 0, TAU, 32, LINE, 2.0, true)

## Guarded master-arm switch: guard flipped up when weapons are free, closed over the toggle when safe.
class Guard extends Control:
	var open := true
	signal pressed
	func _init() -> void:
		custom_minimum_size = Vector2(56, 56); size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
	func set_open(v: bool) -> void:
		if v != open: open = v; queue_redraw()
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(); accept_event()
	func _draw() -> void:
		draw_rect(Rect2(6, 14, 44, 38), SCREEN)
		draw_rect(Rect2(6.5, 14.5, 43, 37), LINE, false, 1.0)
		draw_rect(Rect2(23, 24 if open else 32, 10, 20 if open else 12), TEXT)
		var ang := -58.0 if open else 0.0
		draw_set_transform(Vector2(28, 14) if open else Vector2(28, 30), deg_to_rad(ang), Vector2.ONE)
		var r := Rect2(-22, 0 if open else -6, 44, 18)
		draw_rect(r, PRI)
		for k in 4:
			var x0 := r.position.x + 4 + k * 12
			draw_line(Vector2(x0, r.position.y), Vector2(x0 + 8, r.end.y), PRI_INK, 4)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

## One canvas item for a column of HUD captions. Each line keeps the font, size, colour and
## alignment it had as its own Txt; only the draw is shared.
class CapLine extends RefCounted:
	var board
	var i := 0
	func _init(b, idx: int) -> void:
		board = b
		i = idx
	func set_text(t: String, c: Variant = null) -> void:
		board.set_line(i, t, c)

class CapCol extends Control:
	var rows: Array = []
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size = Vector2(1440, 900)
	func line(at: Vector2, text: String, fsize: int, col: Color, mono: bool, width: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> CapLine:
		rows.append({"at": at, "text": text, "size": fsize, "col": col, "mono": mono, "width": width, "align": align})
		return CapLine.new(self, rows.size() - 1)
	func set_line(i: int, text: String, c: Variant = null) -> void:
		var row: Dictionary = rows[i]
		var col: Color = row["col"] if c == null else c
		if row["text"] == text and row["col"] == col:
			return
		row["text"] = text
		row["col"] = col
		queue_redraw()
	func _draw() -> void:
		# One pass per font. The lines do not overlap, and a run of the same font is one canvas draw
		# instead of a draw per caption.
		for mono in [true, false]:
			for row in rows:
				if bool(row["mono"]) != mono:
					continue
				var text: String = row["text"]
				if text == "":
					continue
				var f: Font = W.FM if mono else W.FH
				var y := float(row["size"])
				var base: Vector2 = row["at"]
				for bit in text.split("\n"):
					draw_string(f, base + Vector2(0, y), bit, row["align"], row["width"], row["size"], row["col"])
					y += int(float(row["size"]) * 1.4)
