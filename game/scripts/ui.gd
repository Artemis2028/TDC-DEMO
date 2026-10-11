class_name UI
## Look and small widget helpers for the CIC skin: dark panels, amber for fire control, cyan for sensors.

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
const SCREEN := Color("#04080b")
const KEY_BG := Color("#121b23")
const KEY_LINE := Color("#4a5d6b")
const GOOD := Color("#7fd1a0")

static func box(bg: Color, line: Color = LINE, width: int = 1, cut: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(width)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	if cut > 0:
		s.corner_detail = 1
		s.corner_radius_top_left = cut
		s.corner_radius_bottom_right = cut
	return s

static func label(text: String, size: int = 13, color: Color = TEXT, caps: bool = false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if caps else text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func header(text: String, color: Color = PRI) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := label(text, 16, color, true)
	h.add_child(l)
	var rule := ColorRect.new()
	rule.color = LINE
	rule.custom_minimum_size = Vector2(0, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rule)
	return h

static func button(text: String, on_press: Callable, accent: Color = PRI, min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 34)
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", PRI_INK)
	b.add_theme_color_override("font_disabled_color", FAINT)
	b.add_theme_stylebox_override("normal", box(KEY_BG, KEY_LINE))
	b.add_theme_stylebox_override("hover", box(KEY_BG, accent))
	b.add_theme_stylebox_override("pressed", box(accent, accent))
	b.add_theme_stylebox_override("disabled", box(SCREEN, LINE))
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b

## A selected-looking button (used for the active choice in a segmented row).
static func set_active(b: Button, on: bool, accent: Color = PRI) -> void:
	if on:
		b.add_theme_stylebox_override("normal", box(accent, accent))
		b.add_theme_color_override("font_color", PRI_INK)
	else:
		b.add_theme_stylebox_override("normal", box(KEY_BG, KEY_LINE))
		b.add_theme_color_override("font_color", TEXT)

## A locked feature: crossed out, disabled, with a "coming soon" tooltip.
static func locked(text: String, min_w: int = 0) -> Button:
	var b := button(text, Callable(), FAINT, min_w)
	b.disabled = true
	b.tooltip_text = "Coming soon. Support development on Patreon to unlock it sooner."
	var x := Control.new()
	x.mouse_filter = Control.MOUSE_FILTER_IGNORE
	x.set_anchors_preset(Control.PRESET_FULL_RECT)
	x.draw.connect(func(): W.draw_x(x, Rect2(Vector2.ZERO, x.size)))
	b.add_child(x)
	return b

static func bar(width: int = 120, height: int = 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = Vector2(width, height)
	p.show_percentage = false
	p.max_value = 100
	var bg := StyleBoxFlat.new()
	bg.bg_color = SCREEN
	bg.border_color = LINE
	bg.set_border_width_all(1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = SEC
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fg)
	return p

static func bar_color(p: ProgressBar, c: Color) -> void:
	var fg := p.get_theme_stylebox("fill") as StyleBoxFlat
	if fg.bg_color != c:
		var n := fg.duplicate() as StyleBoxFlat
		n.bg_color = c
		p.add_theme_stylebox_override("fill", n)

static func panel(rect: Rect2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = rect.position
	p.size = rect.size
	p.custom_minimum_size = rect.size
	var s := box(PANEL, LINE, 1, 0)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", s)
	return p

static func health_color(v: float) -> Color:
	if v <= 0: return HOT
	if v < 50: return PRI
	return SEC
