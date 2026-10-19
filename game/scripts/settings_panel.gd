class_name SettingsPanel
extends Control
## The settings screen: a full-screen overlay with a panel in the middle. Changes apply as they are made and are
## saved at once. Esc or Close shuts it. Create it with SettingsPanel.create(self), then call open().

signal closed
## Called when "Export logs" is pressed; must return {file name: text} for the extra files (battle events etc.).
var extra_provider := Callable()
## The briefing that "How to play" opens. If left null, the panel makes its own.
var briefing: Briefing
## Optional: the Sfx node, so moving the volume slider plays a sample.
var sfx: Sfx

var _vol: HSlider
var _vol_txt: Label
var _win_btns: Array = []
var _fps_btns: Array = []
var _fc_btns: Array = []
var _beam_btns: Array = []
var _fpsread_btns: Array = []
var _status: Label

## Put a new panel on its own canvas layer above the menu (menu is layer 5) and return it. Hidden until open().
static func create(host: Node, layer := 6) -> SettingsPanel:
	var cl := CanvasLayer.new()
	cl.layer = layer
	host.add_child(cl)
	var p := SettingsPanel.new()
	cl.add_child(p)
	return p

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
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(640, 0)
	var sb := UI.box(UI.PANEL, UI.PRI, 1)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	pc.add_theme_stylebox_override("panel", sb)
	cc.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	pc.add_child(v)
	v.add_child(UI.label("Settings", 32, UI.PRI))

	v.add_child(UI.header("Sound"))
	var row := _row(v, "Master volume")
	_vol = HSlider.new()
	_vol.min_value = 0
	_vol.max_value = 100
	_vol.step = 1
	_vol.focus_mode = Control.FOCUS_NONE
	_vol.custom_minimum_size = Vector2(250, 26)
	_style_slider(_vol)
	_vol.value_changed.connect(_on_volume)
	_vol.drag_ended.connect(_on_volume_released)
	row.add_child(_vol)
	_vol_txt = UI.label("", 14, UI.TEXT)
	_vol_txt.custom_minimum_size.x = 64
	_vol_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_vol_txt)
	v.add_child(_note("0 % is silent. In a battle the M key also switches the sound effects off and on; it leaves this level alone."))

	v.add_child(UI.header("Display"))
	row = _row(v, "Window mode")
	for i in Settings.WINDOW_NAMES.size():
		var b := UI.button(Settings.WINDOW_NAMES[i], func(): _set_window(i), UI.PRI, 110)
		row.add_child(b)
		_win_btns.append(b)
	row = _row(v, "Frame-rate cap")
	for c in Settings.FPS_CAPS:
		var cap: int = c
		var b := UI.button("Unlimited" if cap == 0 else str(cap), func(): _set_fps(cap), UI.PRI, 80)
		row.add_child(b)
		_fps_btns.append(b)
	v.add_child(_note("Unlimited follows the display. A cap below the refresh rate turns vsync off, so the frames stay evenly spaced instead of missing every few."))

	v.add_child(UI.header("Game"))
	row = _row(v, "Fire-control lines at start")
	for on in [true, false]:
		var o: bool = on
		var b := UI.button("On" if o else "Off", func(): _set_fc(o), UI.PRI, 80)
		row.add_child(b)
		_fc_btns.append(b)
	v.add_child(_note("The B key switches them during a battle."))
	row = _row(v, "Visible laser beams")
	for on in [true, false]:
		var shown: bool = on
		var b := UI.button("On" if shown else "Off", func(): _set_beams(shown), UI.PRI, 80)
		row.add_child(b)
		_beam_btns.append(b)
	v.add_child(_note("Off is the physical default: nothing in vacuum scatters a beam, so you see the spot and the emitter. The L key switches the beams on during a battle. On shows the Lance's own beam meshes, and a simple beam on the Dagger and the Mars frigate."))
	row = _row(v, "Frame-time counter")
	for on in [true, false]:
		var shown: bool = on
		var b := UI.button("On" if shown else "Off", func(): _set_fps_read(shown), UI.PRI, 80)
		row.add_child(b)
		_fpsread_btns.append(b)
	v.add_child(_note("FPS, frame time and a 1% low. Off by default. F4 switches it during play."))
	var chk := Check.new("Show the how-to-play briefing when the game starts", Settings.show_briefing)
	chk.name = "BriefingCheck"
	chk.toggled.connect(func(on: bool): Settings.set_show_briefing(on))
	v.add_child(chk)

	v.add_child(UI.header("Help", UI.SEC))
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	row.add_child(UI.button("How to play", _on_how_to_play, UI.SEC, 150))
	row.add_child(UI.button("Export logs", _on_export, UI.SEC, 150))
	v.add_child(_note("Logs are saved on your PC (in Documents). The game never uploads anything."))
	_status = UI.label("", 12, UI.GOOD)
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status.custom_minimum_size.x = 580
	_status.visible = false
	v.add_child(_status)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(bottom)
	bottom.add_child(UI.button("Close", close, UI.PRI, 140))
	_refresh()

func open() -> void:
	_build()
	_status.visible = false
	(find_child("BriefingCheck", true, false) as Check).set_pressed_no_signal(Settings.show_briefing)
	_refresh()
	visible = true

func close() -> void:
	if not visible: return
	visible = false
	Settings.save()
	closed.emit()

# While open the panel owns the keyboard, so battle keys (Space, WASD...) never reach the game underneath.
func _input(e: InputEvent) -> void:
	if not visible: return
	if e is InputEventKey:
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE: close()
		get_viewport().set_input_as_handled()

func _row(parent: Control, label: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	var l := UI.label(label, 14, UI.TEXT)
	l.custom_minimum_size.x = 210
	r.add_child(l)
	parent.add_child(r)
	return r

func _note(t: String) -> Label:
	var l := UI.label(t, 12, UI.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 580
	return l

func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = UI.SCREEN
	track.border_color = UI.LINE
	track.set_border_width_all(1)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.PRI
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var img := Image.create(10, 22, false, Image.FORMAT_RGBA8)
	img.fill(UI.TEXT)
	var tex := ImageTexture.create_from_image(img)
	for n in ["grabber", "grabber_highlight", "grabber_disabled"]:
		s.add_theme_icon_override(n, tex)

func _refresh() -> void:
	_vol.set_value_no_signal(Settings.volume)
	_vol_txt.text = "MUTE" if Settings.volume == 0 else "%d %%" % Settings.volume
	for i in _win_btns.size(): UI.set_active(_win_btns[i], i == Settings.window_mode)
	for i in _fps_btns.size(): UI.set_active(_fps_btns[i], Settings.FPS_CAPS[i] == Settings.fps_cap)
	UI.set_active(_fc_btns[0], Settings.fc_lines)
	UI.set_active(_fc_btns[1], not Settings.fc_lines)
	UI.set_active(_beam_btns[0], Settings.laser_beams)
	UI.set_active(_beam_btns[1], not Settings.laser_beams)
	if not _fpsread_btns.is_empty():
		UI.set_active(_fpsread_btns[0], Settings.show_fps)
		UI.set_active(_fpsread_btns[1], not Settings.show_fps)

func _on_volume(v: float) -> void:
	Settings.set_volume(int(v), false)      # live; saved when the drag ends
	_refresh()

func _on_volume_released(_changed: bool) -> void:
	Settings.save()
	if sfx != null: sfx.play("hit", -2.0, 0.0)     # a sample at the new level

func _set_window(i: int) -> void:
	Settings.set_window_mode(i)
	_refresh()

func _set_fps(c: int) -> void:
	Settings.set_fps_cap(c)
	_refresh()

func _set_fc(on: bool) -> void:
	Settings.set_fc_lines(on)
	_refresh()

func _set_beams(on: bool) -> void:
	Settings.set_laser_beams(on)
	_refresh()

func _set_fps_read(on: bool) -> void:
	Settings.set_show_fps(on)
	_refresh()

func _on_how_to_play() -> void:
	if briefing == null:
		briefing = Briefing.create(self.get_parent().get_parent(), 7)
	briefing.open()

func _on_export() -> void:
	var extra: Dictionary = extra_provider.call() if extra_provider.is_valid() else {}
	var path := LogExport.export_logs(extra)
	_status.visible = true
	if path == "":
		_status.text = "Could not save the logs: " + LogExport.last_note
		_status.add_theme_color_override("font_color", UI.HOT)
	else:
		_status.text = "Saved to " + path + ("\n" + LogExport.last_note if LogExport.last_note != "" else "")
		_status.add_theme_color_override("font_color", UI.GOOD)
