class_name Briefing
extends Control
## The "how to play" overlay: two pages of short callouts pointing at the real HUD areas, dismissed with "Got it".
## It draws its own faint outline of the three HUD regions, so it reads correctly over the live HUD or over the menu.
## Rects below match the HUD layout in main.gd (_build_left / _build_viewport / _build_right); if the HUD moves, edit
## PAGES. Create with Briefing.create(self), then open(). Shown before a session's first battle when Settings says so.

signal closed

const LEFT := Rect2(16, 72, 288, 812)       # weapons, fire mode, target select, helm
const VIEW := Rect2(312, 72, 804, 684)      # the 3D view
const RIGHT := Rect2(1128, 72, 296, 812)    # caution lamps, heat, damage control, scope
const BOX_W := 320.0

## Each callout: rect (what it points at), box (where its text sits), num (1-4 are the four ideas; 0 is a tip),
## title, text, accent. Positions are in the 1440x900 canvas.
const PAGES := [
	{"title": "1 of 2 · Fight your ship", "callouts": [
		{"rect": Rect2(24, 156, 272, 330), "box": Rect2(336, 150, BOX_W, 128), "num": 1, "accent": "pri",
		 "title": "Your lasers fire on their own",
		 "text": "Once weapons are free (Space) your armed lasers shoot at the target you picked, with no clicking. Space again makes them safe."},
		{"rect": Rect2(1136, 238, 280, 168), "box": Rect2(784, 244, BOX_W, 144), "num": 2, "accent": "hot",
		 "title": "Heat is the limit",
		 "text": "Lasers and the drive add heat. At 100 your weapons lock out. Extending the radiators cools you faster, but the enemy can shoot them."},
		{"rect": Rect2(24, 490, 272, 154), "box": Rect2(336, 470, BOX_W, 112), "num": 0, "accent": "pri",
		 "title": "Aim at a part",
		 "text": "Click an enemy part in the view, or a button here. Right-click a button to mark that system degraded or killed."},
		{"rect": Rect2(320, 80, 788, 668), "box": Rect2(480, 600, BOX_W, 140), "num": 0, "accent": "sec", "outline": true,
		 "title": "The 3D view",
		 "text": "Tab: enemy view. V: tactical plot, which shows each side's weapon range. Range is a weapon too. B hides the dashed laser lines. L draws the beams themselves (off by default; a real beam in vacuum is invisible). Settings sets both."},
	]},
	{"title": "2 of 2 · Read the enemy", "callouts": [
		{"rect": Rect2(1136, 440, 280, 114), "box": Rect2(784, 420, BOX_W, 156), "num": 3, "accent": "sec",
		 "title": "Your crew only estimates",
		 "text": "Calls about the enemy are marked probable and can be wrong. Judge it by what it does: does it close in, hold its range, turn side-on?"},
		{"rect": Rect2(24, 642, 272, 130), "box": Rect2(336, 588, BOX_W, 156), "num": 4, "accent": "sec",
		 "title": "Turn the armour to the beam",
		 "text": "Roll (Q / E) and side-on (T) change which armour the beam hits, so you can spread the damage. WASD burns, I lights the drive."},
		{"rect": Rect2(1148, 606, 256, 254), "box": Rect2(784, 640, BOX_W, 100), "num": 0, "accent": "sec",
		 "title": "EO scope",
		 "text": "A telescope close-up of your target."},
	]},
]

var _page := 0
var _stage: Control
var _badges: Control
var _boxes: Array = []
var _title: Label
var _sub: Label
var _back: Button
var _next: Button
var _check: Check
var _opened_once := false
static var _shown_this_session := false

## True when the briefing should appear before a battle: the setting is on and it has not yet been shown this session.
static func wanted() -> bool:
	return Settings.show_briefing and not _shown_this_session

## Put a new briefing on its own canvas layer (above the settings panel) and return it. Hidden until open().
static func create(host: Node, layer := 7) -> Briefing:
	var cl := CanvasLayer.new()
	cl.layer = layer
	host.add_child(cl)
	var b := Briefing.new()
	cl.add_child(b)
	return b

func _init() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var th := Theme.new()
	th.default_font = W.FH
	theme = th

var _built := false

func _ready() -> void:
	_build()

func _build() -> void:
	if _built: return
	_built = true
	var dim := ColorRect.new()
	dim.color = Color(0.016, 0.024, 0.035, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.draw.connect(_draw_stage)
	add_child(_stage)
	_title = UI.label("", 30, UI.PRI)
	_title.position = Vector2(336, 80)
	_title.size = Vector2(776, 40)
	add_child(_title)
	_sub = UI.label("A gamified demo: speeds, weapons and damage are tuned for play. You command the cruiser; the enemy is ahead.", 13, UI.MUTED)
	_sub.position = Vector2(336, 118)
	_sub.size = Vector2(776, 22)
	add_child(_sub)
	_badges = Control.new()           # last, so the numbers sit on top of the boxes and rects
	_badges.set_anchors_preset(Control.PRESET_FULL_RECT)
	_badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badges.draw.connect(_draw_badges)

	var got := UI.button("Got it", close, UI.PRI, 260)
	got.add_theme_font_size_override("font_size", 22)
	got.custom_minimum_size = Vector2(260, 56)
	UI.set_active(got, true)
	got.position = Vector2(590, 772)
	got.size = Vector2(260, 56)
	add_child(got)
	_back = UI.button("◂ Back", func(): _go(0), UI.SEC, 120)
	_back.position = Vector2(446, 782)
	_back.size = Vector2(120, 36)
	add_child(_back)
	_next = UI.button("Next ▸", func(): _go(1), UI.SEC, 120)
	_next.position = Vector2(874, 782)
	_next.size = Vector2(120, 36)
	add_child(_next)
	_check = Check.new("Don't show again", not Settings.show_briefing)
	_check.position = Vector2(620, 834)
	_check.size = Vector2(200, 28)
	_check.toggled.connect(func(on: bool): Settings.set_show_briefing(not on))
	add_child(_check)
	var foot := UI.label("Esc closes this · in battle, Esc pauses to the menu (Esc again resumes)", 13, UI.MUTED)
	foot.position = Vector2(440, 866)
	foot.size = Vector2(560, 20)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)
	add_child(_badges)
	_build_page()

func open(page := 0) -> void:
	_build()
	_shown_this_session = true
	_check.set_pressed_no_signal(not Settings.show_briefing)
	_page = clampi(page, 0, PAGES.size() - 1)
	_build_page()
	visible = true

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()

func _go(p: int) -> void:
	_build()
	_page = p
	_build_page()

# While open the briefing owns the keyboard (battle keys must not act under it). Esc dismisses it.
func _input(e: InputEvent) -> void:
	if not visible: return
	if e is InputEventKey:
		if e.pressed and not e.echo:
			match e.keycode:
				KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER: close()
				KEY_RIGHT: if _page < PAGES.size() - 1: _go(_page + 1)
				KEY_LEFT: if _page > 0: _go(_page - 1)
		get_viewport().set_input_as_handled()

func _accent(name: String) -> Color:
	return {"pri": UI.PRI, "sec": UI.SEC, "hot": UI.HOT}[name]

func _build_page() -> void:
	for b in _boxes: b.queue_free()
	_boxes.clear()
	var pg: Dictionary = PAGES[_page]
	_title.text = ("HOW TO PLAY · " + str(pg["title"])).to_upper()
	_back.visible = _page > 0
	_next.visible = _page < PAGES.size() - 1
	for c: Dictionary in pg["callouts"]:
		var col := _accent(c["accent"])
		var box: Rect2 = c["box"]
		var pc := PanelContainer.new()
		pc.position = box.position
		pc.size = Vector2(box.size.x, 0)
		pc.custom_minimum_size = Vector2(box.size.x, 0)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UI.box(Color(0.039, 0.063, 0.086, 0.98), col, 1)
		sb.content_margin_left = 36 if int(c["num"]) > 0 else 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		pc.add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 4)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := UI.label(c["title"], 16, col, true)
		var x := UI.label(c["text"], 14, UI.TEXT)
		x.add_theme_constant_override("line_spacing", -4)
		x.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		x.custom_minimum_size.x = box.size.x - sb.content_margin_left - 14
		v.add_child(t)
		v.add_child(x)
		pc.add_child(v)
		add_child(pc)
		move_child(pc, _badges.get_index())
		_boxes.append(pc)
	_stage.queue_redraw()
	_badges.queue_redraw()
	_redraw_after_layout.call_deferred()

func _redraw_after_layout() -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	_stage.queue_redraw()

## The nearest point of r to p.
static func _near(r: Rect2, p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))

func _draw_stage() -> void:
	# faint outline of the three HUD regions, so the pointers make sense over any background
	for rr in [[LEFT, ""], [VIEW, ""], [RIGHT, ""]]:
		_stage.draw_rect(rr[0], UI.LINE, false, 1.0)
		if rr[1] != "":
			var r: Rect2 = rr[0]
			_stage.draw_string(W.FM, r.position + Vector2(8, r.size.y - 6), rr[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UI.FAINT)
	for c: Dictionary in PAGES[_page]["callouts"]:
		var col := _accent(c["accent"])
		var r: Rect2 = c["rect"]
		var box := _box_rect(c)
		if c.get("outline", false):
			# the 3D view: a dashed frame and no leader
			var step := 14.0
			var x := r.position.x
			while x < r.end.x:
				_stage.draw_line(Vector2(x, r.position.y), Vector2(minf(x + 7, r.end.x), r.position.y), Color(col, 0.7), 1.5)
				_stage.draw_line(Vector2(x, r.end.y), Vector2(minf(x + 7, r.end.x), r.end.y), Color(col, 0.7), 1.5)
				x += step
			var y := r.position.y
			while y < r.end.y:
				_stage.draw_line(Vector2(r.position.x, y), Vector2(r.position.x, minf(y + 7, r.end.y)), Color(col, 0.7), 1.5)
				_stage.draw_line(Vector2(r.end.x, y), Vector2(r.end.x, minf(y + 7, r.end.y)), Color(col, 0.7), 1.5)
				y += step
			continue
		_stage.draw_rect(r, Color(col, 0.08))
		_stage.draw_rect(r, col, false, 2.0)
		# leader: from the box edge to the rect edge, nearest points to each other's centre
		var a := _near(box, r.get_center())
		var b := _near(r, box.get_center())
		_stage.draw_line(a, b, col, 2.0, true)
		_stage.draw_circle(b, 4.0, col)

func _draw_badges() -> void:
	for c: Dictionary in PAGES[_page]["callouts"]:
		var n := int(c["num"])
		if n == 0: continue
		var box: Rect2 = c["box"]
		var p := box.position + Vector2(18, 20)
		_badges.draw_circle(p, 13, _accent(c["accent"]))
		W.text_c(_badges, W.FH, str(n), p, 18, UI.PRI_INK)

## The callout's box as laid out: its position from PAGES, its height from the text it holds.
func _box_rect(c: Dictionary) -> Rect2:
	var box: Rect2 = c["box"]
	for pc: Control in _boxes:
		if pc.position == box.position:
			return Rect2(box.position, Vector2(box.size.x, maxf(pc.size.y, pc.get_combined_minimum_size().y)))
	return box
