extends Node3D
## TDC demo: one battle at the Moon. All rules run in the compiled DemoBattle; this script only draws and sends orders.

const PATREON_URL := ""   # set before release
const SPEED_NAMES := ["PAUSE", "0.5×", "1×", "2×", "5×", "10×", "CRUISE"]
const SYS_NAMES := ["Drive", "Laser", "Gun", "Sensors", "Radiators", "Crew"]
const PRESETS := [["Disable drive", 0], ["Blind", 3], ["Cook", 4], ["Disarm", 1]]
const MOON_R := 1737.4e3

var battle: DemoBattle
var ship_class := 0
var state := "menu"
var ev_index := 0
var log_lines: Array[String] = []

# 3D
var cam: Camera3D
var own_model: ShipModel
var foe_model: ShipModel
var moon: MeshInstance3D
var lines: ImmediateMesh
var line_mat: StandardMaterial3D
var foe_marker: Label3D
var yaw := 0.6
var pitch := 0.25
var dist := 300.0
var dragging := false
var view_target := false   # false: own ship, true: the enemy as your EO sees it
var chase := false
var roll_angle := 0.0
var foe_roll := 0.0

# EO sensor window
var eo_vp: SubViewport
var eo_cam: Camera3D
var eo_rect: TextureRect
var eo_info: Label

# HUD widgets
var hud: Control
var menu: Control
var end_screen: Control
var nameplate: Label
var nameplate_sub: Label
var hull_segs: Array[ColorRect] = []
var clock_lbl: Label
var speed_btns: Array[Button] = []
var drop_lbl: Label
var free_btn: Button
var arm_rows := {}
var mode_btns: Array[Button] = []
var target_btns: Array[Button] = []
var preset_btns: Array[Button] = []
var burn_btns: Array[Button] = []
var facing_btns: Array[Button] = []
var throttle: HSlider
var heat_bar: ProgressBar
var heat_lbl: Label
var rad_btn: Button
var sys_rows: Array = []
var teams_lbl: Label
var auto_rep_btn: Button
var log_lbl: Label
var vp_title: Label
var vp_sub: Label
var view_btns: Array[Button] = []
var armor_view := false

# capture mode: --shot path --at seconds [--class n] [--target] [--armor] [--menu]
var shot_path := ""
var shot_at := 0.0
var shot_frames := 0

func _ready() -> void:
	_build_world()
	_build_hud()
	_build_menu()
	_build_end()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--shot": shot_path = args[i + 1]
			"--at": shot_at = float(args[i + 1])
			"--class": ship_class = int(args[i + 1])
			"--target": view_target = true
			"--armor": armor_view = true
	if shot_path != "" and not args.has("--menu"):
		_start(ship_class, true)
		while battle.get_time() < shot_at and battle.get_winner() < 0:
			battle.advance(1.0)
		battle.set_speed(0)
		_drain_events()
	elif shot_path == "":
		_show_menu()
	else:
		_show_menu()

# ------------------------------------------------------------------ world

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.4)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.7
	sun.light_color = Color(1, 0.97, 0.92)
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-1, -0.5, -0.4), Vector3.UP)
	cam = Camera3D.new()
	cam.fov = 50
	cam.near = 1.0
	cam.far = 5.0e6
	add_child(cam)
	moon = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = MOON_R
	sm.height = MOON_R * 2
	sm.radial_segments = 128
	sm.rings = 64
	moon.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.2, 0.19, 0.18)
	mm.roughness = 1.0
	moon.material_override = mm
	add_child(moon)
	lines = ImmediateMesh.new()
	line_mat = StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.vertex_color_use_as_albedo = true
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var li := MeshInstance3D.new()
	li.mesh = lines
	li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	li.layers = 2          # beams and round streaks are HUD overlays, not something the EO camera sees
	add_child(li)
	foe_marker = Label3D.new()
	foe_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	foe_marker.fixed_size = true
	foe_marker.pixel_size = 0.0011
	foe_marker.font_size = 30
	foe_marker.outline_size = 6
	foe_marker.no_depth_test = true
	foe_marker.modulate = UI.HOT
	foe_marker.layers = 2          # HUD-only: the EO camera must not see it
	add_child(foe_marker)
	# EO sensor: a camera of its own, rendered small and blown up, so poor quality shows as big pixels.
	eo_vp = SubViewport.new()
	eo_vp.size = Vector2i(64, 64)
	eo_vp.world_3d = get_world_3d()
	eo_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	eo_cam = Camera3D.new()
	eo_cam.fov = 2.0
	eo_cam.near = 10.0
	eo_cam.far = 5.0e6
	eo_cam.cull_mask = 1
	eo_vp.add_child(eo_cam)
	add_child(eo_vp)

func _spawn_models() -> void:
	for m in [own_model, foe_model]:
		if m: m.queue_free()
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	own_model = ShipModel.new()
	own_model.build(false, int(own["gun"]) != 0)
	add_child(own_model)
	foe_model = ShipModel.new()
	foe_model.build(true, int(foe["gun"]) != 0)
	add_child(foe_model)

# ------------------------------------------------------------------ battle flow

func _start(cls: int, quiet := false) -> void:
	ship_class = cls
	battle = DemoBattle.new()
	battle.start(int(Time.get_unix_time_from_system()) if shot_path == "" else 7, cls)
	battle.set_speed(2)
	ev_index = 0
	log_lines.clear()
	_spawn_models()
	state = "battle"
	menu.visible = false
	end_screen.visible = false
	hud.visible = true

func _drain_events() -> void:
	for e in battle.get_events(ev_index):
		if e["kind"] == "fire":
			continue
		var t: float = e["time"]
		log_lines.append("%s  %s" % [_clock(t), e["text"]])
	ev_index = battle.event_count()
	while log_lines.size() > 5:
		log_lines.pop_front()

func _process(delta: float) -> void:
	if state == "battle" and battle:
		battle.advance(delta)
		_drain_events()
		if battle.get_winner() >= 0 and not end_screen.visible:
			_show_end()
	if battle:
		_update_world(delta)
		_update_hud()
	if shot_path != "":
		shot_frames += 1
		if shot_frames == 40:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			get_tree().quit()

func _sim_to_world(p: Vector2, origin: Vector2) -> Vector3:
	# Sim plane (km) to world (m): sim x -> X, sim y -> -Z, around a floating origin.
	var d := (p - origin) * 1000.0
	return Vector3(d.x, 0, -d.y)

func _update_world(delta: float) -> void:
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	var focus: Vector2 = foe["pos"] if view_target else own["pos"]
	own_model.position = _sim_to_world(own["pos"], focus)
	foe_model.position = _sim_to_world(foe["pos"], focus)
	if int(own["facing"]) == 1: roll_angle += delta * 0.6 * battle_speed()
	if int(foe["facing"]) == 1: foe_roll += delta * 0.6 * battle_speed()
	own_model.rotation = Vector3(0, float(own["heading"]) - PI / 2, roll_angle)
	foe_model.rotation = Vector3(0, float(foe["heading"]) - PI / 2, foe_roll)
	own_model.view_mode = 1 if armor_view else 0
	foe_model.view_mode = 1 if armor_view and view_target and battle.get_sensor_quality() > 0.5 else 0
	own_model.show_state(own, delta)
	foe_model.show_state(foe, delta)
	# The Moon sits below the battle (100 km orbit).
	moon.position = Vector3(0, -(MOON_R + 100e3), 0)
	# Camera.
	var target_node: Node3D = foe_model if view_target else own_model
	var up := Vector3.UP
	var off: Vector3
	if chase and not view_target:
		var back := own_model.global_transform.basis.z.normalized()
		off = back * dist * 0.9 + up * dist * 0.25
	else:
		off = Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * dist
	cam.position = target_node.position + off
	cam.look_at(target_node.position, up)
	# Enemy marker when looking at our own ship.
	foe_marker.visible = not view_target
	foe_marker.position = foe_model.position
	foe_marker.text = "◆ %s · %.1f km" % [str(foe["name"]).to_upper(), battle.get_range_km()]
	# Beams and rounds.
	lines.clear_surfaces()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	var any := false
	if own["laser_firing"]:
		_seg(own_model.position + Vector3(0, 6, 0), foe_model.position, Color(0.55, 0.85, 1.0, 0.9)); any = true
	if foe["laser_firing"]:
		_seg(foe_model.position, own_model.position, Color(1.0, 0.45, 0.25, 0.9)); any = true
	for s in battle.get_shots():
		var p := _sim_to_world(s["pos"], focus)
		var dir := (foe_model.position - own_model.position).normalized() if int(s["shooter"]) == 0 else (own_model.position - foe_model.position).normalized()
		_seg(p - dir * 400.0, p, Color(1.6, 1.3, 0.6, 1)); any = true
	lines.surface_end()
	if not any: lines.clear_surfaces()
	# EO camera: from our ship toward the enemy, field of view just wider than the enemy.
	var q: float = battle.get_sensor_quality()
	var res := int(clamp(12 + 180 * q * q, 12, 192))
	eo_vp.size = Vector2i(res, res)
	# A long lens is a camera placed close along the same line of sight: same picture, no tiny field of view.
	# Frame the target by its apparent size: a ship seen nose-on is only its width across.
	var los := (foe_model.position - own_model.position).normalized()
	var axis := -foe_model.global_transform.basis.z.normalized()
	var across: float = foe_model.length * sqrt(max(0.0, 1.0 - pow(los.dot(axis), 2))) + foe_model.length * 0.25
	var half: float = max(12.0, across * 0.65)
	eo_cam.fov = 4.0
	eo_cam.position = foe_model.position - los * (half / tan(deg_to_rad(2.0)))
	eo_cam.look_at(foe_model.position, Vector3.UP)

func _seg(a: Vector3, b: Vector3, c: Color) -> void:
	lines.surface_set_color(c)
	lines.surface_add_vertex(a)
	lines.surface_set_color(c)
	lines.surface_add_vertex(b)

func battle_speed() -> float:
	return [0.0, 0.5, 1.0, 2.0, 5.0, 10.0, 50.0][battle.get_speed()]

static func _clock(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)

	# Frame around the centre view.
	var frame := Control.new()
	frame.position = Vector2(312, 72)
	frame.size = Vector2(804, 684)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(func():
		var pts := PackedVector2Array([Vector2(22, 0), Vector2(804, 0), Vector2(804, 662), Vector2(782, 684), Vector2(0, 684), Vector2(0, 22), Vector2(22, 0)])
		frame.draw_polyline(pts, UI.LINE, 1.5)
		frame.draw_line(Vector2(22, 1), Vector2(120, 1), UI.PRI, 3)
		frame.draw_line(Vector2(1, 22), Vector2(1, 120), UI.PRI, 3)
		frame.draw_line(Vector2(803, 562), Vector2(803, 662), UI.PRI, 3))
	hud.add_child(frame)
	vp_title = UI.label("OWN SHIP", 16, UI.TEXT, true)
	vp_title.position = Vector2(352, 92)
	hud.add_child(vp_title)
	vp_sub = UI.label("", 11, UI.MUTED)
	vp_sub.position = Vector2(352, 114)
	hud.add_child(vp_sub)
	var vrow := HBoxContainer.new()
	vrow.position = Vector2(700, 86)
	vrow.add_theme_constant_override("separation", 2)
	for t in [["Own ship", func(): view_target = false], ["Target", func(): view_target = true], ["Real", func(): armor_view = false], ["Armor", func(): armor_view = true], ["Chase cam", func(): chase = not chase]]:
		var b := UI.button(t[0], t[1], UI.SEC, 60)
		b.custom_minimum_size.y = 28
		vrow.add_child(b)
		view_btns.append(b)
	hud.add_child(vrow)

	# Top left: game mark and ship tab.
	var tl := HBoxContainer.new()
	tl.position = Vector2(16, 12)
	tl.add_theme_constant_override("separation", 10)
	var mark := UI.label("TDC", 22, UI.PRI)
	tl.add_child(mark)
	var tab := UI.button("1  YOUR SHIP", Callable(), UI.PRI, 140)
	UI.set_active(tab, true)
	tl.add_child(tab)
	tl.add_child(UI.locked("2  FLEET", 90))
	hud.add_child(tl)

	# Top centre: nameplate and hull bar.
	var np := VBoxContainer.new()
	np.position = Vector2(504, 6)
	np.size = Vector2(420, 60)
	np.alignment = BoxContainer.ALIGNMENT_CENTER
	np.add_theme_constant_override("separation", 1)
	nameplate = UI.label("", 24, UI.TEXT, true)
	nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	np.add_child(nameplate)
	nameplate_sub = UI.label("", 11, UI.MUTED)
	nameplate_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	np.add_child(nameplate_sub)
	var segs := HBoxContainer.new()
	segs.alignment = BoxContainer.ALIGNMENT_CENTER
	segs.add_theme_constant_override("separation", 2)
	for i in 24:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(9, 5)
		segs.add_child(r)
		hull_segs.append(r)
	np.add_child(segs)
	hud.add_child(np)

	# Top right: time and speed.
	var tr := VBoxContainer.new()
	tr.position = Vector2(1000, 8)
	tr.size = Vector2(424, 60)
	tr.alignment = BoxContainer.ALIGNMENT_END
	clock_lbl = UI.label("", 20, UI.PRI)
	clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tr.add_child(clock_lbl)
	var sp := HBoxContainer.new()
	sp.alignment = BoxContainer.ALIGNMENT_END
	sp.add_theme_constant_override("separation", 2)
	for i in SPEED_NAMES.size():
		var idx := i
		var b := UI.button(SPEED_NAMES[i], func(): battle.set_speed(idx), UI.SEC, 44)
		b.custom_minimum_size.y = 26
		sp.add_child(b)
		speed_btns.append(b)
	tr.add_child(sp)
	hud.add_child(tr)
	drop_lbl = UI.label("", 12, UI.PRI)
	drop_lbl.position = Vector2(1128, 66)
	drop_lbl.size = Vector2(296, 16)
	drop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(drop_lbl)

	_build_left()
	_build_right()
	_build_bottom()

func _build_left() -> void:
	var p := UI.panel(Rect2(16, 72, 288, 812))
	hud.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 9)
	p.add_child(v)

	v.add_child(UI.header("Armament"))
	for key in ["laser", "gun"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		var n := UI.label("", 14, UI.TEXT, true)
		var s := UI.label("", 10, UI.MUTED)
		col.add_child(n)
		col.add_child(s)
		row.add_child(col)
		var c := UI.label("", 16, UI.SEC)
		row.add_child(c)
		v.add_child(row)
		arm_rows[key] = [dot, n, s, c]

	v.add_child(UI.header("Fire control"))
	free_btn = UI.button("Weapons free", func(): battle.set_weapons_free(not bool(battle.get_ship(0)["weapons_free"])), UI.HOT)
	free_btn.custom_minimum_size.y = 40
	v.add_child(free_btn)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 2)
	for m in [["Auto", 0], ["Manual", 1]]:
		var mi: int = m[1]
		var b := UI.button(m[0], func(): battle.set_fire_mode(mi, int(battle.get_ship(0)["target_sys"])), UI.PRI)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modes.add_child(b)
		mode_btns.append(b)
	v.add_child(modes)
	v.add_child(UI.label("Target system (manual)", 10, UI.MUTED, true))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	for i in SYS_NAMES.size():
		var si := i
		var b := UI.button(SYS_NAMES[i], func(): battle.set_fire_mode(1, si), UI.PRI, 128)
		b.custom_minimum_size.y = 30
		grid.add_child(b)
		target_btns.append(b)
	v.add_child(grid)
	var pre := GridContainer.new()
	pre.columns = 2
	pre.add_theme_constant_override("h_separation", 2)
	pre.add_theme_constant_override("v_separation", 2)
	for pr in PRESETS:
		var si: int = pr[1]
		var b := UI.button(pr[0], func(): battle.set_fire_mode(1, si), UI.PRI, 128)
		b.custom_minimum_size.y = 30
		pre.add_child(b)
		preset_btns.append(b)
	v.add_child(pre)

	v.add_child(UI.header("Maneuver"))
	var burns := GridContainer.new()
	burns.columns = 3
	burns.add_theme_constant_override("h_separation", 2)
	burns.add_theme_constant_override("v_separation", 2)
	for bn in [["Toward", 1], ["Away", 2], ["Match", 5], ["Left", 3], ["Right", 4], ["Drive off", 0]]:
		var bi: int = bn[1]
		var b := UI.button(bn[0], func(): battle.set_burn(bi, throttle.value / 100.0), UI.PRI, 84)
		b.custom_minimum_size.y = 30
		burns.add_child(b)
		burn_btns.append(b)
	v.add_child(burns)
	var th := HBoxContainer.new()
	th.add_child(UI.label("THROTTLE", 11, UI.MUTED))
	throttle = HSlider.new()
	throttle.min_value = 10
	throttle.max_value = 100
	throttle.value = 100
	throttle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	throttle.focus_mode = Control.FOCUS_NONE
	throttle.value_changed.connect(_on_throttle)
	th.add_child(throttle)
	v.add_child(th)
	v.add_child(UI.label("Facing", 10, UI.MUTED, true))
	var fac := HBoxContainer.new()
	fac.add_theme_constant_override("separation", 2)
	for f in [["Nose on", 0], ["Broadside roll", 1], ["Stern", 2]]:
		var fi: int = f[1]
		var b := UI.button(f[0], func(): battle.set_facing(fi), UI.PRI)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 30
		fac.add_child(b)
		facing_btns.append(b)
	v.add_child(fac)
	var hint := UI.label("Nose on: thickest armour, spinal gun bears.\nBroadside roll: lasers do 35 %, but no gun\nand your laser is blocked part of each turn.", 10, UI.FAINT)
	v.add_child(hint)

func _build_right() -> void:
	var p := UI.panel(Rect2(1128, 72, 296, 470))
	hud.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UI.header("Heat", UI.SEC))
	var hr := HBoxContainer.new()
	heat_bar = UI.bar(190, 12)
	heat_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hr.add_child(heat_bar)
	heat_lbl = UI.label("", 14, UI.TEXT)
	hr.add_child(heat_lbl)
	v.add_child(hr)
	rad_btn = UI.button("Radiators extended", func(): battle.set_radiators(not bool(battle.get_ship(0)["radiators_extended"])), UI.SEC)
	rad_btn.tooltip_text = "Extended: sheds heat fast but radiators can be shot off.\nRetracted: safe from hits, heat builds."
	v.add_child(rad_btn)
	var ew := HBoxContainer.new()
	ew.add_theme_constant_override("separation", 2)
	for n in ["Go dark", "Jam", "Decoy", "ECM"]:
		var b := UI.locked(n, 64)
		ew.add_child(b)
	v.add_child(ew)

	v.add_child(UI.header("Damage control", UI.SEC))
	var tr := HBoxContainer.new()
	teams_lbl = UI.label("", 12, UI.MUTED)
	teams_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(teams_lbl)
	auto_rep_btn = UI.button("Auto", func(): battle.set_auto_repair(not bool(battle.get_ship(0)["auto_repair"])), UI.SEC, 64)
	auto_rep_btn.custom_minimum_size.y = 26
	tr.add_child(auto_rep_btn)
	v.add_child(tr)
	for i in SYS_NAMES.size():
		var si := i
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var n := UI.label(SYS_NAMES[i], 13, UI.TEXT, true)
		n.custom_minimum_size.x = 82
		row.add_child(n)
		var b := UI.bar(90, 8)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		var st := UI.label("", 11, UI.MUTED)
		st.custom_minimum_size.x = 40
		row.add_child(st)
		var fix := UI.button("Fix", func(): battle.order_repair(si), UI.SEC, 40)
		fix.custom_minimum_size.y = 24
		row.add_child(fix)
		v.add_child(row)
		sys_rows.append([n, b, st, fix])

func _build_bottom() -> void:
	# EO sensor window, bottom right.
	var p := UI.panel(Rect2(1128, 554, 296, 330))
	hud.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	var eo := UI.button("EO", Callable(), UI.SEC, 56)
	UI.set_active(eo, true, UI.SEC)
	tabs.add_child(eo)
	for n in ["Radar", "Lidar", "IR"]:
		tabs.add_child(UI.locked(n, 64))
	v.add_child(tabs)
	eo_rect = TextureRect.new()
	eo_rect.texture = eo_vp.get_texture()
	eo_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	eo_rect.custom_minimum_size = Vector2(268, 210)
	eo_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eo_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(eo_rect)
	eo_info = UI.label("", 11, UI.SEC)
	v.add_child(eo_info)
	# Event log, bottom centre.
	var lp := UI.panel(Rect2(312, 768, 804, 116))
	hud.add_child(lp)
	log_lbl = UI.label("", 12, UI.TEXT)
	log_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lp.add_child(log_lbl)

func _update_hud() -> void:
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	nameplate.text = str(own["name"]).to_upper()
	nameplate_sub.text = "EARTH · CREW %d/%d · HULL %d%%" % [own["crew"], own["crew_max"], int(float(own["hull"]) * 100)]
	var hullf: float = own["hull"]
	for i in hull_segs.size():
		hull_segs[i].color = UI.SEC if float(i) / hull_segs.size() < hullf else UI.LINE
	clock_lbl.text = "T+ %s   RANGE %.1f KM   CLOSING %.0f M/S" % [_clock(battle.get_time()), battle.get_range_km(), battle.get_closing()]
	for i in speed_btns.size():
		UI.set_active(speed_btns[i], i == battle.get_speed(), UI.SEC)
	speed_btns[6].disabled = not battle.get_cruise_allowed()
	drop_lbl.text = battle.get_drop_reason()
	vp_title.text = ("TARGET · %s" % str(foe["name"]).to_upper()) if view_target else "OWN SHIP · %s" % str(own["name"]).to_upper()
	vp_sub.text = ("armour condition" if armor_view else "real colour") + ("  ·  chase cam" if chase and not view_target else "")
	UI.set_active(view_btns[0], not view_target, UI.SEC)
	UI.set_active(view_btns[1], view_target, UI.SEC)
	UI.set_active(view_btns[2], not armor_view, UI.SEC)
	UI.set_active(view_btns[3], armor_view, UI.SEC)
	UI.set_active(view_btns[4], chase, UI.SEC)
	# Armament.
	var health: PackedFloat64Array = own["health"]
	var lr: Array = arm_rows["laser"]
	lr[0].color = UI.health_color(health[1])
	lr[1].text = "Laser turret"
	lr[2].text = "firing" if own["laser_firing"] else ("destroyed" if health[1] <= 0 else ("overheated" if float(own["heat"]) >= 100 else "idle"))
	lr[3].text = "%d%%" % int(health[1])
	var gr: Array = arm_rows["gun"]
	var gun: int = own["gun"]
	gr[1].text = ["No gun fitted", "Railgun", "Spinal coilgun"][gun]
	if gun == 0:
		gr[0].color = UI.LINE; gr[2].text = ""; gr[3].text = ""
	else:
		gr[0].color = UI.health_color(health[2])
		var cd: float = own["gun_cooldown"]
		gr[2].text = ("reloading %.0f s" % cd) if cd > 0 else ("%d%% to hit" % int(battle.get_hit_chance() * 100) if battle.get_hit_chance() > 0 else "out of range or not bearing")
		gr[3].text = "%03d" % int(own["ammo"])
	# Fire control.
	var free: bool = own["weapons_free"]
	free_btn.text = "WEAPONS FREE" if free else "WEAPONS HOLD"
	UI.set_active(free_btn, free, UI.HOT)
	var mode: int = own["fire_mode"]
	UI.set_active(mode_btns[0], mode == 0)
	UI.set_active(mode_btns[1], mode == 1)
	var q: float = battle.get_sensor_quality()
	var fh: PackedFloat64Array = foe["health"]
	for i in target_btns.size():
		var known := q > 0.3
		target_btns[i].text = "%s %s" % [SYS_NAMES[i].to_upper(), ("%d" % int(fh[i])) if known else "?"]
		UI.set_active(target_btns[i], mode == 1 and int(own["target_sys"]) == i)
	for i in preset_btns.size():
		UI.set_active(preset_btns[i], mode == 1 and int(own["target_sys"]) == int(PRESETS[i][1]))
	var burn: int = own["burn"]
	for i in burn_btns.size():
		UI.set_active(burn_btns[i], [1, 2, 5, 3, 4, 0][i] == burn)
	for i in facing_btns.size():
		UI.set_active(facing_btns[i], int(own["facing"]) == i)
	# Heat and damage control.
	var heat: float = own["heat"]
	heat_bar.value = heat
	UI.bar_color(heat_bar, UI.HOT if heat >= 80 else (UI.PRI if heat >= 50 else UI.SEC))
	heat_lbl.text = " %d" % int(heat)
	rad_btn.text = "RADIATORS EXTENDED" if own["radiators_extended"] else "RADIATORS RETRACTED"
	var reps: Array = own["repairs"]
	teams_lbl.text = "REPAIR TEAMS %d/%d" % [int(own["teams"]) - reps.size(), int(own["teams"])]
	UI.set_active(auto_rep_btn, own["auto_repair"], UI.SEC)
	for i in sys_rows.size():
		var row: Array = sys_rows[i]
		var hv: float = health[i]
		var na := i == 2 and gun == 0
		row[1].value = 0 if na else hv
		UI.bar_color(row[1], UI.health_color(hv))
		var job := ""
		for r in reps:
			if int(r["sys"]) == i: job = "%.0f s" % float(r["left"])
		row[2].text = "—" if na else (job if job != "" else "%d%%" % int(hv))
		row[2].add_theme_color_override("font_color", UI.SEC if job != "" else UI.MUTED)
		row[3].disabled = na or hv >= 100 or job != ""
	# EO window.
	eo_info.text = "EO TRACK %d%%  ·  %s" % [int(q * 100), "components resolved" if q > 0.5 else ("outline only" if q > 0.25 else "point source")]
	log_lbl.text = "\n".join(log_lines)

# ------------------------------------------------------------------ menus

func _overlay() -> Control:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var c := ColorRect.new()
	c.color = Color(0.016, 0.024, 0.035, 0.92)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(c)
	return c

func _build_menu() -> void:
	menu = _overlay()
	var v := VBoxContainer.new()
	v.position = Vector2(520, 180)
	v.size = Vector2(400, 560)
	v.add_theme_constant_override("separation", 14)
	menu.add_child(v)
	var t := UI.label("TDC", 64, UI.PRI)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := UI.label("Earth and Mars, 2300. One battle at the Moon.", 14, UI.MUTED)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	v.add_child(UI.header("Choose your ship"))
	v.add_child(UI.button("Dagger · laser cruiser", func(): _start(0), UI.PRI, 400))
	v.add_child(UI.button("Lance · laser + spinal coilgun", func(): _start(1), UI.PRI, 400))
	v.add_child(UI.button("Watch an AI battle", _watch_ai, UI.SEC, 400))
	v.add_child(UI.header("Coming soon", UI.FAINT))
	v.add_child(UI.locked("Ship designer", 400))
	v.add_child(UI.locked("Fleet battles · missiles · drones", 400))
	v.add_child(UI.button("Support development on Patreon", _open_patreon, UI.HOT, 400))
	v.add_child(UI.button("Quit", func(): get_tree().quit(), UI.MUTED, 400))
	var keys := UI.label("Right-drag: orbit camera · Wheel: zoom · Space: pause · , . : speed · Tab: own / target view · Esc: menu", 11, UI.FAINT)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(keys)

func _show_menu() -> void:
	state = "menu"
	menu.visible = true
	end_screen.visible = false
	hud.visible = false
	if battle == null:
		battle = DemoBattle.new()
		battle.start(1, 0)
		battle.set_player_ai(true)
		battle.set_speed(3)
		_spawn_models()

func _build_end() -> void:
	end_screen = _overlay()
	end_screen.visible = false

func _show_end() -> void:
	for c in end_screen.get_children(): c.queue_free()
	end_screen.visible = true
	var v := VBoxContainer.new()
	v.position = Vector2(470, 220)
	v.size = Vector2(500, 460)
	v.add_theme_constant_override("separation", 12)
	end_screen.add_child(v)
	var won := battle.get_winner() == 0
	var t := UI.label("VICTORY" if won else "DEFEAT", 56, UI.PRI if won else UI.HOT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	var loser: Dictionary = foe if won else own
	var lines_out := [
		"Battle time %s" % _clock(battle.get_time()),
		"%s: %s" % [loser["name"], loser["out_reason"]],
		"Your hull %d%%, crew %d of %d" % [int(float(own["hull"]) * 100), own["crew"], own["crew_max"]],
		"Enemy hull %d%%, crew %d of %d" % [int(float(foe["hull"]) * 100), foe["crew"], foe["crew_max"]],
	]
	for s in lines_out:
		var l := UI.label(s, 15, UI.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	v.add_child(UI.button("Fight again", func(): _start(ship_class), UI.PRI, 500))
	v.add_child(UI.button("Main menu", func(): _show_menu(), UI.SEC, 500))
	v.add_child(UI.button("Support development on Patreon", _open_patreon, UI.HOT, 500))

func _on_throttle(val: float) -> void:
	var sh: Dictionary = battle.get_ship(0)
	if int(sh["burn"]) != 0:
		battle.set_burn(int(sh["burn"]), val / 100.0)

func _watch_ai() -> void:
	_start(1)
	battle.set_player_ai(true)

func _open_patreon() -> void:
	if PATREON_URL != "":
		OS.shell_open(PATREON_URL)

# ------------------------------------------------------------------ input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE: dragging = e.pressed
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP: dist = max(60.0, dist * 0.88)
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN: dist = min(5000.0, dist / 0.88)
	elif e is InputEventMouseMotion and dragging:
		yaw -= e.relative.x * 0.006
		pitch = clamp(pitch + e.relative.y * 0.006, -1.4, 1.4)
	elif e is InputEventKey and e.pressed and state == "battle":
		match e.keycode:
			KEY_SPACE: battle.set_speed(0 if battle.get_speed() != 0 else 2)
			KEY_PERIOD: battle.set_speed(battle.get_speed() + 1)
			KEY_COMMA: battle.set_speed(max(1, battle.get_speed() - 1))
			KEY_TAB: view_target = not view_target
			KEY_ESCAPE: _show_menu()
