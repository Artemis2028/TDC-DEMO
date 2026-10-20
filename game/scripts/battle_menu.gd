class_name BattleMenu
extends Node
## The opening menu and the victory / defeat card. The battle host owns the sim; this node shows and hides the screens.

var host
var resume_btn: Button
var scen_btns: Array = []

func build() -> void:
	_build_menu()

func build_end() -> void:
	_build_end()

func show() -> void:
	_show_menu()

func show_end() -> void:
	_show_end()

func resume() -> void:
	_resume()

# ------------------------------------------------------------------ menus

func _overlay() -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var c := ColorRect.new()
	c.color = Color(0.016, 0.024, 0.035, 0.94)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var th := Theme.new()
	th.default_font = W.FH
	c.theme = th
	layer.add_child(c)
	return c

func _build_menu() -> void:
	host.menu = _overlay()
	var v := VBoxContainer.new()
	v.position = Vector2(520, 36)
	v.size = Vector2(400, 580)
	v.add_theme_constant_override("separation", 10)
	host.menu.add_child(v)
	var t := UI.label("TDC", 64, UI.PRI)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := UI.label("Earth and Mars, 2300. One battle above Mars.", 15, UI.MUTED)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	# The demo's numbers are tuned for play, not taken from the game's physics (docs/movement_vs_framework.md).
	var note := UI.label("GAMIFIED DEMO · ship performance, weapons and damage are tuned for play and are not representative of the final simulation", 12, UI.PRI)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 400
	v.add_child(note)
	# Esc in battle pauses it under the menu; this takes the player back. Esc on the menu does the same.
	resume_btn = UI.button("Resume battle  (Esc)", _resume, UI.PRI, 400)
	UI.set_active(resume_btn, true)
	resume_btn.visible = false
	v.add_child(resume_btn)
	# Starting situation: random by default, so each battle can open differently. The enemy captain's style is never
	# chosen or shown here; the player reads it from how the frigate moves (and the end screen tells).
	v.add_child(UI.header("Starting situation"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	scen_btns.clear()
	for i in host.SCEN_NAMES.size():
		var si: int = i - 1
		var b = UI.button(host.SCEN_NAMES[i], func(): _pick_scenario(si), UI.PRI, 97)
		row.add_child(b)
		scen_btns.append(b)
	v.add_child(row)
	_pick_scenario(host.scenario_pick)
	v.add_child(UI.header("Choose your ship"))
	v.add_child(UI.button("Dagger · laser cruiser", func(): host._start(0), UI.PRI, 400))
	v.add_child(UI.button("UEN Second Opinion · Coil Gun Frigate", func(): host._start(1), UI.PRI, 400))
	# The AI flying Earth here charges in (closes to 20 km on auto fire) and wins only ~21 %, so say so: a player
	# who watches first should not conclude Earth is hopeless.
	var wb = UI.button("Watch an AI battle · aggressive Earth captain", host._watch_ai, UI.SEC, 400)
	wb.tooltip_text = "The AI flies UEN Second Opinion aggressively: it charges to 20 km on auto fire and loses more often than not.\nA careful captain who holds the range does much better."
	v.add_child(wb)
	v.add_child(UI.header("Coming soon", UI.FAINT))
	v.add_child(UI.locked("Ship designer", 400))
	v.add_child(UI.locked("Orbital transfers · fleets · missiles · EW", 400))
	v.add_child(UI.button("Support development on Patreon", host._open_patreon, UI.HOT, 400))
	var ver := UI.label(Version.text(), 12, UI.FAINT)
	ver.position = Vector2(1440 - 16 - 400, 900 - 30)
	ver.size = Vector2(400, 20)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	host.menu.add_child(ver)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	row2.add_child(UI.button("How to play", func(): host.briefing.open(), UI.SEC, 132))
	row2.add_child(UI.button("Settings", func(): host.settings_panel.open(), UI.SEC, 132))
	row2.add_child(UI.button("Quit", func(): get_tree().quit(), UI.MUTED, 128))
	v.add_child(row2)
	var keys := UI.label("Space weapons safe/free · P pause · , . time · Q/E roll left/right (again to stop) · T side-on / nose-on · WASD/X burn direction · I ignite · F1-F3 fire mode · Tab enemy view · C chase cam · V tactical plot · B hide/show laser lines · L show laser beams · Right-drag orbit · Wheel zoom · M mute · Click an enemy part to target it · Right-click a target button to mark it degraded / killed · Esc pause / resume", 12, UI.FAINT)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size.x = 400
	v.add_child(keys)

## Menu: which starting situation the next battle uses (-1 random, else a Scenario index).
func _pick_scenario(si: int) -> void:
	host.scenario_pick = si
	for i in scen_btns.size():
		UI.set_active(scen_btns[i], i - 1 == si)

func _show_menu() -> void:
	# Leaving a live battle: it waits frozen under the menu (only state "battle" advances it) and can be resumed.
	host.resumable = host.state == "battle" and host.battle != null and host.battle.get_winner() < 0
	resume_btn.visible = host.resumable
	if host.sfx: host.sfx.stop_loops()        # the loops are only driven in battle; left alone they would hum on
	host.was_lasing = false
	host.state = "menu"
	host.menu.visible = true
	host.end_screen.visible = false
	host.hud.visible = false
	if host.battle == null:
		host.battle = DemoBattle.new()
		host.battle.start(1, 0)
		host.battle.set_player_ai(true)
		host.battle.set_speed(3)
		host._spawn_models()

## Back to the battle Esc left, exactly as it was (its clock did not run while the menu was up).
func _resume() -> void:
	if not host.resumable or host.battle == null or host.battle.get_winner() >= 0: return
	host.resumable = false
	resume_btn.visible = false
	host.state = "battle"
	host.menu.visible = false
	host.hud.visible = true
	host.hud_dirty = true
	host.snap_dirty = true

func _build_end() -> void:
	host.end_screen = _overlay()
	host.end_screen.visible = false

func _show_end() -> void:
	for c in host.end_screen.get_children(): c.queue_free()
	host.end_screen.visible = true
	var v := VBoxContainer.new()
	v.position = Vector2(470, 220)
	v.size = Vector2(500, 460)
	v.add_theme_constant_override("separation", 12)
	host.end_screen.add_child(v)
	var won = host.battle.get_winner() == 0
	var t := UI.label("VICTORY" if won else "DEFEAT", 56, UI.PRI if won else UI.HOT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var own: Dictionary = host.battle.get_ship(0)
	var foe: Dictionary = host.battle.get_ship(1)
	var loser: Dictionary = foe if won else own
	var lines_out := [
		"Battle time %s" % host._clock(host.battle.get_time()),
		"%s: %s" % [host._shown_ship_name(loser), loser["out_reason"]],
		"Your hull %d%%, crew %d of %d" % [int(float(own["hull"]) * 100), own["crew"], own["crew_max"]],
		"Enemy hull %d%%, crew %d of %d" % [int(float(foe["hull"]) * 100), foe["crew"], foe["crew_max"]],
		"%s start · the enemy captain was %s" % [str(host.SCEN_NAMES[host.battle.get_scenario() + 1]), host._style_text()],
	]
	for s in lines_out:
		var l := UI.label(s, 16, UI.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	host.aar_view = null                  # the old one was freed with the end screen's children
	v.add_child(UI.button("After-action report", host._open_aar, UI.SEC, 500))
	v.add_child(UI.button("Fight again", func(): host._start(host.ship_class), UI.PRI, 500))
	v.add_child(UI.button("Main menu", func(): _show_menu(), UI.SEC, 500))
	v.add_child(UI.button("Support development on Patreon", host._open_patreon, UI.HOT, 500))
