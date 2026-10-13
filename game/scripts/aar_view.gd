class_name AARView
extends Control
## Shows an AAR report: headline, hull chart, timeline, insights. About 700x560, scrolls, has Close and Export buttons.
## Content is built only when the view is shown (and only once per report); the chart redraws only when asked to.
##
##   var v := AARView.new(); parent.add_child(v); v.position = ...; v.show_report(aar); v.closed.connect(...)

signal closed

var _aar: AAR
var _dirty := false
var _body: VBoxContainer
var _status: Label

func _init() -> void:
	custom_minimum_size = Vector2(700, 560)
	size = Vector2(700, 560)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(_on_visibility)
	_build_frame()

func show_report(a: AAR) -> void:
	_aar = a
	_dirty = true
	_status.text = ""
	visible = true
	_on_visibility()

func _on_visibility() -> void:
	if visible and _dirty and _aar != null and _aar.done:
		_dirty = false
		_rebuild()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(W.PANEL, 1.0))
	draw_rect(Rect2(Vector2.ZERO, size), W.LINE, false, 1.5)

func _build_frame() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14; root.offset_top = 10; root.offset_right = -14; root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var title := _lab("AFTER-ACTION REPORT", 22, W.PRI, W.FH, false)
	root.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 5)
	scroll.add_child(_body)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	root.add_child(bar)
	bar.add_child(_button("Export as text", _on_export, W.SEC))
	_status = _lab("", 12, W.MUTED, W.FM, true)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	bar.add_child(_button("Close", _on_close, W.PRI))

func _on_close() -> void:
	visible = false
	closed.emit()

func _on_export() -> void:
	if _aar == null:
		return
	var p := _aar.export_text()
	_status.text = ("Saved: " + p) if p != "" else "Could not write the file."

func _button(text: String, cb: Callable, col: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 34)
	b.add_theme_font_override("font", W.FH)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", col)
	b.add_theme_color_override("font_hover_color", W.TEXT)
	b.add_theme_color_override("font_pressed_color", W.TEXT)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = W.KEY_BG if st == "normal" else W.DIM
		sb.border_color = col if st != "normal" else W.KEY_LINE
		sb.set_border_width_all(1)
		sb.set_content_margin_all(6)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b

func _lab(text: String, fsize: int, col: Color, font: Font, wrap: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _rule() -> Control:
	var r := ColorRect.new()
	r.color = W.LINE
	r.custom_minimum_size = Vector2(0, 1)
	return r

func _header(text: String) -> void:
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 8)
	_body.add_child(sp)
	_body.add_child(_lab(text, 17, W.SEC, W.FH, false))
	_body.add_child(_rule())

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var rep: Dictionary = _aar.report
	var hl: Array = rep["headline"]
	var won := _aar.winner == 0
	_body.add_child(_lab(str(hl[0]), 34, W.PRI if won else W.HOT, W.FH, false))
	for i in range(1, hl.size()):
		_body.add_child(_lab(str(hl[i]), 14, W.TEXT, W.FM, true))

	_header("HULL OVER TIME")
	var ch := Chart.new()
	ch.a = _aar
	ch.custom_minimum_size = Vector2(0, 170)
	ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(ch)

	_header("TIMELINE")
	for e in rep["timeline"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var col: Color = W.SEC if e["tone"] > 0 else (W.HOT if e["tone"] < 0 else W.TEXT)
		var ck := _lab(AAR.clock(e["t"]), 14, W.PRI, W.FM, false)
		ck.custom_minimum_size = Vector2(46, 0)
		row.add_child(ck)
		row.add_child(_lab(str(e["text"]), 14, col, W.FM, true))
		_body.add_child(row)

	_header("WHY IT WENT THAT WAY")
	var n := 0
	for ins in rep["insights"]:
		n += 1
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, 4)
		_body.add_child(sp)
		_body.add_child(_lab("%d. %s" % [n, ins["title"]], 16, W.PRI, W.FH, false))
		for l in ins["lines"]:
			var t := str(l)
			var lab := _lab(t, 13, W.TEXT if not t.begins_with("  ") else W.MUTED, W.FM, true)
			_body.add_child(lab)
	var sp2 := Control.new()
	sp2.custom_minimum_size = Vector2(0, 8)
	_body.add_child(sp2)
	for l in rep["notes"]:
		_body.add_child(_lab(str(l), 11, W.MUTED, W.FM, true))

## Hull fraction over time for both ships (solid), armour + hull (faint), with the turning point and the end marked.
class Chart extends Control:
	var a: AAR

	func _draw() -> void:
		if a == null:
			return
		var r := Rect2(38, 8, size.x - 50, size.y - 32)
		draw_rect(r, W.SCREEN)
		var tmax := 1.0
		if a.chart_t.size() > 0:
			tmax = maxf(1.0, a.chart_t[a.chart_t.size() - 1])
		for f: float in [0.0, 0.5, 1.0]:
			var y := r.end.y - f * r.size.y
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), W.LINE, 1.0)
			draw_string(W.FM, Vector2(2, y + 4), "%d%%" % int(f * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.MUTED)
		var step := 30.0
		for s: float in [30.0, 60.0, 120.0, 180.0, 300.0]:
			if tmax / s <= 8.0:
				step = s
				break
		var x := 0.0
		while x <= tmax + 0.01:
			var px := r.position.x + x / tmax * r.size.x
			draw_line(Vector2(px, r.end.y), Vector2(px, r.end.y + 4), W.MUTED, 1.0)
			draw_string(W.FM, Vector2(minf(px - 12, size.x - 36), r.end.y + 16), AAR.clock(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.MUTED)
			x += step
		if a.chart_t.size() < 2:
			draw_string(W.FM, r.position + Vector2(10, 20), "Not enough data.", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, W.MUTED)
			return
		_line(r, tmax, a.chart_i1, Color(W.HOT, 0.35), 1.0)
		_line(r, tmax, a.chart_i0, Color(W.SEC, 0.35), 1.0)
		_line(r, tmax, a.chart_h1, W.HOT, 2.0)
		_line(r, tmax, a.chart_h0, W.SEC, 2.0)
		if a.turning_t >= 0.0:
			var tx := r.position.x + a.turning_t / tmax * r.size.x
			draw_line(Vector2(tx, r.position.y), Vector2(tx, r.end.y), W.PRI, 1.0)
			draw_string(W.FM, Vector2(tx + 3, r.position.y + 11), "turning point", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.PRI)
		var ex := r.end.x - 1
		draw_line(Vector2(ex, r.position.y), Vector2(ex, r.end.y), W.TEXT, 1.0)
		# legend
		var lx := r.position.x + 8
		var ly := r.end.y - 8
		draw_line(Vector2(lx, ly), Vector2(lx + 18, ly), W.SEC, 2.0)
		draw_string(W.FM, Vector2(lx + 22, ly + 4), "you", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.TEXT)
		draw_line(Vector2(lx + 60, ly), Vector2(lx + 78, ly), W.HOT, 2.0)
		draw_string(W.FM, Vector2(lx + 82, ly + 4), "enemy", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.TEXT)
		draw_string(W.FM, Vector2(lx + 130, ly + 4), "solid: hull   faint: armour + hull", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.MUTED)

	func _line(r: Rect2, tmax: float, ys: PackedFloat32Array, col: Color, w: float) -> void:
		var pts := PackedVector2Array()
		for i in a.chart_t.size():
			pts.append(Vector2(r.position.x + a.chart_t[i] / tmax * r.size.x, r.end.y - clampf(ys[i], 0.0, 1.0) * r.size.y))
		draw_polyline(pts, col, w, true)
