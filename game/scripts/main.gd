extends Node3D
## TDC demo: one battle above Mars. All rules run in the compiled DemoBattle; this script only draws and sends orders.
## The HUD follows the CIC flight-deck layout. Features that are not in the demo are drawn with a red X and do nothing.

const PATREON_URL := ""   # set before release
const SPEED_NAMES := ["II", "½×", "1×", "2×", "5×", "10×", "CRZ"]
const SYS_NAMES := ["Drive", "Laser", "Gun", "Sensors", "Radiators", "Crew"]
const SYS_ABBR := ["DRV", "LSR", "GUN", "SNS", "RAD", "CRW"]
const PRESET_VERB := ["Disable", "Disarm", "Silence", "Blind", "Cook", "Kill"]
## Target select grid: [system, turret (-1 any), label, preset verb]
## One cell per kind of target, however many of it the enemy carries. Clicking a weapon kind again cycles through
## the individual mounts (any → 1 → 2 → 3 → any), so the grid never grows with the enemy's loadout.
const TARGETS := [[0, -1, "DRV", "Disable"], [1, -1, "LSR", "Disarm"], [2, -1, "GUN", "Silence"],
	[3, -1, "SNS", "Blind"], [4, -1, "RAD", "Cook"], [5, -1, "CRW", "Kill"]]
const MARS_R := 3389.5e3
const ALT := 650e3          # display orbit height, chosen so the planet's limb shows as an arc
const VP := Rect2(312, 72, 804, 684)

var battle: DemoBattle
var ship_class := 0
var state := "menu"
var ev_index := 0
var log_lines: Array = []   # [text, clock]

# 3D
var view_vp: SubViewport
var cam: Camera3D
var own_model: ShipModel
var foe_model: ShipModel
var planet: MeshInstance3D
var lines: ImmediateMesh
var line_mat: StandardMaterial3D
var yaw := 0.9
var pitch := 0.42
var dist := 320.0
var dragging := false
var view_target := false
var chase := false
var armor_view := false
var roll_angle := 0.0
var foe_roll := 0.0

# EO sensor
var eo_vp: SubViewport
var eo_cam: Camera3D

# player-side UI state
var sel_burn := 1           # burn direction picked on the helm (1 close, 2 open, 3 left, 4 right, 5 match)
var preset_mode := false
var throttle := 1.0
var last_heat := 0.0
var last_time := 0.0
var heat_rate := 0.0
var dc_line_sys: Array = []

# HUD
var hud: Control
var menu: Control
var end_screen: Control
var overlay: Control
var nameplate: Control
var cond_badge: Control
var clock_scr: W.Screen
var speed_btns: Array = []
var drop_txt: W.Txt
var arm_rows: Array = []    # [arm btn, flag, name txt, sub txt, counter screen]
var mode_btns: Array = []
var guard: W.Guard
var free_txt: W.Txt
var free_sub: W.Txt
var tgt_hdr: W.Header
var tgt_scr: W.Screen
var tgt_btns: Array = []
var helm_btns: Array = []
var drive_txt: W.Txt
var thr_txt: W.Txt
var thr_segs: W.Segs
var ignite: W.Btn
var dv_scr: Array = []
var fuel_txt: W.Txt
var ball: W.Ball
var att_scr: W.Screen
var rwr_txt: W.Txt
var view_btns: Array = []
var lamps: Array = []
var heat_rate_txt: W.Txt
var ring: W.Ring
var heat_lines: Array = []
var rad_txt: W.Txt
var rad_btns: Array = []
var dc_hdr: W.Header
var auto_btn: W.Btn
var paper: W.Paper
var eo_label_t1 := ""
var eo_label_t2 := ""
var scope_over: Control
var scope_rect := Rect2()
var bracket_pos := Vector2(-999, -999)
var pick_points: Array = []   # enemy components on screen this frame: [position in the view, system, turret, label]
var sfx: Sfx
var was_lasing := false
var scope_foot_l: W.Txt
var scope_foot_r: W.Txt

# capture mode: --shot path --at seconds [--class n] [--target] [--armor] [--menu] [--hold] [--preset]
var shot_path := ""
var shot_at := 0.0
var shot_frames := 0
var shot_clicks: Array = []   # --click x,y (repeatable): synthetic clicks for checking the HUD wiring headless

func _ready() -> void:
	RenderingServer.set_default_clear_color(W.BG)
	sfx = Sfx.new()
	add_child(sfx)
	if OS.get_cmdline_user_args().has("--dump-sfx"):
		var dir: String = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--dump-sfx") + 1]
		sfx.dump(dir)
		get_tree().quit()
		return
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
			"--dist": dist = float(args[i + 1])
			"--yaw": yaw = float(args[i + 1])
			"--pitch": pitch = float(args[i + 1])
			"--click":
				var xy: PackedStringArray = args[i + 1].split(",")
				shot_clicks.append(Vector2(float(xy[0]), float(xy[1])))
	if shot_path != "" and not args.has("--menu"):
		_start(ship_class)
		if args.has("--hold"): battle.set_weapons_free(false)
		if args.has("--preset"): _set_mode(1)
		if args.has("--broadside"): battle.set_facing(1)
		if args.has("--burn"):
			throttle = float(args[args.find("--throttle") + 1]) if args.has("--throttle") else 1.0
			battle.set_burn(int(args[args.find("--burn") + 1]), throttle)
		while battle.get_time() < shot_at and battle.get_winner() < 0:
			battle.advance(1.0)
			_track_heat()
		battle.set_speed(0)
		_drain_events()
	else:
		_show_menu()

# ------------------------------------------------------------------ world

func _build_world() -> void:
	var env := Environment.new()
	# A star sky around the whole scene: the background, and something for glowing exhaust to add onto
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skymat := PanoramaSkyMaterial.new()
	skymat.panorama = _star_panorama()
	sky.sky_material = skymat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.4)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_AGX     # same view transform as the Blender renders
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.8
	sun.light_color = Color(1, 0.95, 0.88)
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.8, -0.25, 0.6), Vector3.UP)
	planet = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = MARS_R
	sm.height = MARS_R * 2
	sm.radial_segments = 192
	sm.rings = 96
	planet.mesh = sm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.46, 0.2, 0.09)
	mm.roughness = 1.0
	planet.material_override = mm
	planet.layers = 4          # the fill light below skips the planet so its night side stays dark
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	fill.light_color = Color(0.75, 0.82, 0.95)
	fill.light_cull_mask = 1 | 2
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.6, -0.5, -0.7), Vector3.UP)
	add_child(planet)
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
	# EO sensor: a camera of its own, rendered small and blown up, so poor quality shows as big pixels.
	eo_vp = SubViewport.new()
	eo_vp.size = Vector2i(64, 64)
	eo_vp.world_3d = get_world_3d()
	eo_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	eo_cam = Camera3D.new()
	eo_cam.fov = 4.0
	eo_cam.near = 10.0
	eo_cam.far = 9.0e6
	eo_cam.cull_mask = 1
	eo_vp.add_child(eo_cam)
	add_child(eo_vp)

## Equirectangular star field: a few thousand faint points, a handful bright, slightly warm or cool. Same every run.
static func _star_panorama() -> ImageTexture:
	var w := 4096
	var h := 2048
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.006, 0.008, 0.013))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2300
	for i in 6000:
		var x := rng.randi_range(0, w - 1)
		# uniform over the sphere: pick the row by the sine of latitude
		var y := int((acos(rng.randf_range(-1.0, 1.0)) / PI) * (h - 1))
		var b := pow(rng.randf(), 6.0) * 0.9 + 0.08
		var tint := Color(1.0, 0.92, 0.82) if rng.randf() < 0.3 else (Color(0.82, 0.9, 1.0) if rng.randf() < 0.5 else Color.WHITE)
		img.set_pixel(x, y, tint * b)
		if b > 0.5:                                  # the brightest few get a small halo
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x >= 0 and q.x < w and q.y >= 0 and q.y < h:
					img.set_pixel(q.x, q.y, tint * b * 0.35)
	return ImageTexture.create_from_image(img)

func _spawn_models() -> void:
	for m in [own_model, foe_model]:
		if m: m.queue_free()
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	own_model = ShipModel.new()
	own_model.build(false, int(own["gun"]))
	add_child(own_model)
	foe_model = ShipModel.new()
	foe_model.build(true, int(foe["gun"]))
	add_child(foe_model)

# ------------------------------------------------------------------ battle flow

func _start(cls: int) -> void:
	ship_class = cls
	battle = DemoBattle.new()
	battle.start(int(Time.get_unix_time_from_system()) if shot_path == "" else 7, cls)
	battle.set_speed(2)
	ev_index = 0
	log_lines.clear()
	preset_mode = false
	sel_burn = 1
	throttle = 1.0
	last_heat = 0.0
	last_time = 0.0
	heat_rate = 0.0
	_spawn_models()
	state = "battle"
	menu.visible = false
	end_screen.visible = false
	hud.visible = true

func _drain_events() -> void:
	for e in battle.get_events(ev_index):
		_event_sound(e)
		if not ["hit", "burn-through", "disabled", "overheat", "out"].has(str(e["kind"])):
			continue
		log_lines.append([str(e["text"]), _clock(float(e["time"]))])
	ev_index = battle.event_count()
	while log_lines.size() > 6:
		log_lines.pop_front()

## What the crew hears: our own gun firing, enemy rounds striking our hull, alarms for our losses and overheating.
func _event_sound(e: Dictionary) -> void:
	if sfx == null or state != "battle" or battle.get_speed() == 0: return
	var mine := int(e["ship"]) == 0
	match str(e["kind"]):
		"fire": if mine: sfx.play("coil", 0.0)
		"hit": if mine: sfx.play("hit", -2.0, 0.15)
		"disabled": if mine: sfx.play("alarm", -4.0, 0.0)
		"overheat": if mine: sfx.play("klaxon", -4.0, 0.0)

func _loop_sounds(delta: float) -> void:
	if sfx == null: return
	if state != "battle" or battle.get_speed() == 0 or battle.get_winner() >= 0:
		sfx.stop_loops()
		was_lasing = false
		return
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	var n := 0
	for f in own["turret_firing"]:
		if f: n += 1
	if n > 0 and not was_lasing: sfx.play("charge", -6.0, 0.03)
	was_lasing = n > 0
	sfx.loop("laser", 0.18 * n, delta)
	sfx.loop("sizzle", 0.5 if foe["laser_firing"] else 0.0, delta)
	sfx.loop("drive", 0.6 if own["burning"] else 0.0, delta)
	sfx.loop("oms", 0.35 if (own["oms"] as Vector2).length() > 0.01 else 0.0, delta)

func _track_heat() -> void:
	var t: float = battle.get_time()
	if t - last_time >= 1.0:
		var h: float = battle.get_ship(0)["heat"]
		heat_rate = lerpf(heat_rate, (h - last_heat) / (t - last_time), 0.5)
		last_heat = h
		last_time = t

func _process(delta: float) -> void:
	if state == "battle" and battle:
		battle.advance(delta)
		_drain_events()
		_track_heat()
		_loop_sounds(delta)
		if battle.get_winner() >= 0 and not end_screen.visible:
			_show_end()
	if battle:
		_update_world(delta)
		if hud.visible:
			_update_hud()
	if shot_path != "":
		shot_frames += 1
		if shot_frames == 10:
			for p in shot_clicks:
				for down in [true, false]:
					var ev := InputEventMouseButton.new()
					ev.button_index = MOUSE_BUTTON_LEFT
					ev.pressed = down
					ev.position = p
					ev.global_position = p
					Input.parse_input_event(ev)
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
	roll_angle = float(own["roll"])
	foe_roll = float(foe["roll"])
	own_model.rotation = Vector3(0, float(own["heading"]) - PI / 2, roll_angle)
	foe_model.rotation = Vector3(0, float(foe["heading"]) - PI / 2, foe_roll)
	own_model.view_mode = 1 if armor_view else 0
	foe_model.view_mode = 1 if armor_view and view_target and battle.get_sensor_quality() > 0.5 else 0
	own_model.show_state(own, delta)
	foe_model.show_state(foe, delta)
	own_model.aim(foe_model.global_position, own["turret_bears"])
	foe_model.aim(own_model.global_position, foe["turret_bears"])
	planet.position = Vector3(0, -(MARS_R + ALT), 0)
	# Camera: orbit (or chase) the ship in view; the view is rolled a little so the planet's limb runs across the lower left.
	var target_node: Node3D = foe_model if view_target else own_model
	var off: Vector3
	if chase and not view_target:
		var back := own_model.global_transform.basis.z.normalized()
		off = back * dist * 0.9 + Vector3.UP * dist * 0.25
	else:
		off = Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * dist
	cam.position = target_node.position + off
	var fwd := (target_node.position - cam.position).normalized()
	cam.look_at(target_node.position, Vector3.UP.rotated(fwd, -0.38))
	# Beams and rounds.
	lines.clear_surfaces()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, line_mat)
	var any := false
	for k in 3:
		if (own["turret_firing"] as Array)[k]:
			_seg(own_model.muzzle_position(k), foe_model.position, Color(0.55, 0.85, 1.0, 0.9)); any = true
		if (foe["turret_firing"] as Array)[k]:
			_seg(foe_model.muzzle_position(k), own_model.position, Color(1.0, 0.45, 0.25, 0.9)); any = true
	for s in battle.get_shots():
		var p := _sim_to_world(s["pos"], focus)
		var dir := (foe_model.position - own_model.position).normalized() if int(s["shooter"]) == 0 else (own_model.position - foe_model.position).normalized()
		_seg(p - dir * 400.0, p, Color(1.6, 1.3, 0.6, 1)); any = true
	lines.surface_end()
	if not any: lines.clear_surfaces()
	# EO camera: a long lens is a camera placed close along the same line of sight, framed by the target's apparent size.
	var q: float = battle.get_sensor_quality()
	var res := int(clamp(12 + 180 * q * q, 12, 192))
	eo_vp.size = Vector2i(res, res)
	var los := (foe_model.position - own_model.position).normalized()
	var axis := -foe_model.global_transform.basis.z.normalized()
	var across: float = foe_model.length * sqrt(max(0.0, 1.0 - pow(los.dot(axis), 2))) + foe_model.length * 0.25
	var half: float = max(12.0, across * 0.65)
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

static func _sd(n: float) -> float:
	var x := sin(n * 12.9898 + 78.233) * 43758.5453
	return x - floor(x)

# ------------------------------------------------------------------ HUD build

func _add(c: Control, pos: Vector2, parent: Control = null) -> Control:
	c.position = pos
	(parent if parent else hud).add_child(c)
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
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	_build_viewport()
	_build_top()
	_build_left()
	_build_right()
	_build_bottom()

func _build_viewport() -> void:
	# The 3D view (its star sky is part of the 3D world), then the drawn overlay.
	var box := SubViewportContainer.new()
	box.position = VP.position
	box.size = VP.size
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(box)
	view_vp = SubViewport.new()
	view_vp.size = Vector2i(VP.size)
	view_vp.transparent_bg = false
	view_vp.world_3d = get_world_3d()
	view_vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(view_vp)
	cam = Camera3D.new()
	cam.fov = 46
	cam.near = 2.0
	cam.far = 6.0e6
	view_vp.add_child(cam)
	overlay = _painter(VP, _draw_overlay)
	# time compression, top right of the view
	var x := VP.end.x - 18 - SPEED_NAMES.size() * 44
	_add(W.Txt.new("TIME", 10, W.FAINT, true, 40), Vector2(x - 42, VP.position.y + 22))
	for i in SPEED_NAMES.size():
		var idx := i
		speed_btns.append(_btn("tab", SPEED_NAMES[i], Vector2(x + i * 44, VP.position.y + 16), Vector2(42, 26), func(): battle.set_speed(idx)))
	drop_txt = W.Txt.new("", 10, W.PRI, true, 330)
	drop_txt.align = HORIZONTAL_ALIGNMENT_RIGHT
	_add(drop_txt, Vector2(VP.end.x - 18 - 330, VP.position.y + 48))

func _build_top() -> void:
	# nameplate
	nameplate = _painter(Rect2(504, 0, 420, 62), func(c: Control):
		c.draw_colored_polygon(PackedVector2Array([Vector2(0.5, 0.5), Vector2(419.5, 0.5), Vector2(391.5, 61.5), Vector2(28.5, 61.5)]), W.PANEL)
		c.draw_polyline(PackedVector2Array([Vector2(0.5, 0.5), Vector2(419.5, 0.5), Vector2(391.5, 61.5), Vector2(28.5, 61.5), Vector2(0.5, 0.5)]), W.LINE, 1.0)
		c.draw_line(Vector2(150, 61), Vector2(270, 61), W.PRI, 3)
		if battle == null: return
		var own: Dictionary = battle.get_ship(0)
		W.text_c(c, W.FH, _own_name().to_upper(), Vector2(210, 15), 24, W.TEXT)
		var hullf: float = own["hull"]
		W.text_c(c, W.FM, "%s · HULL %d%%" % [_own_class(), int(hullf * 100)], Vector2(210, 35), 11, W.MUTED)
		for k in 24:
			c.draw_rect(Rect2(210 - 24 * 11 * 0.5 + k * 11, 46, 9, 5), W.hp(hullf * 100) if float(k) / 24.0 < hullf else W.DIM))
	# condition badge and mission clock
	cond_badge = _painter(Rect2(1128, 12, 160, 30), func(c: Control):
		if battle == null: return
		var hot := not bool(battle.get_cruise_allowed())
		var col := W.HOT if hot else W.PRI
		var t := "CONDITION 1" if hot else "CONDITION 2"
		var tw := W.FH.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 22
		var r := Rect2(160 - tw, 2, tw, 26)
		W.stripes(c, r, col, W.BG, 7)
		c.draw_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), W.BG)
		W.text_c(c, W.FH, t, r.get_center(), 14, col))
	_add(W.Txt.new("MISSION ELAPSED", 9, W.FAINT, true, 120), Vector2(1310, 6))
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
		var n := W.Txt.new("", 15, W.TEXT, false, 130)
		_add(n, Vector2(x + 80, row_y))
		var s := W.Txt.new("", 10, W.MUTED, true, 130)
		_add(s, Vector2(x + 80, row_y + 19))
		var c := W.Screen.new("--", Vector2(46, 24), W.PRI, 16)
		_add(c, Vector2(x + 214, row_y + 6))
		arm_rows.append([arm, flag, n, s, c])
	(arm_rows[0][0] as W.Btn).pressed.connect(func(): battle.set_armed(false, not bool(battle.get_ship(0)["gun_armed"])))
	for k in 3:
		var tk := k
		(arm_rows[1 + k][0] as W.Btn).pressed.connect(func(): battle.set_turret_armed(tk, not bool((battle.get_ship(0)["turret_armed"] as Array)[tk])))
	var vls: Array = arm_rows[4]
	(vls[0] as W.Btn).locked = true
	(vls[0] as W.Btn).text = "SAFE"
	(vls[2] as W.Txt).set_text("VLS ×12", W.FAINT)
	(vls[3] as W.Txt).set_text("not in demo", W.FAINT)
	(vls[4] as W.Screen).set_text("--", W.FAINT)
	y += 5 * 38 + 6
	# fire mode
	_add(W.Header.new("Fire mode", W.PRI, "", 260), Vector2(x, y))
	y += 31
	var mw := (260.0 - 4) / 3
	for m in [["F1", "Manual", 0], ["F2", "Preset", 1], ["F3", "Auto", 2]]:
		var mi: int = m[2]
		var b := _btn("tab", m[1], Vector2(x + mi * (mw + 2), y), Vector2(mw, 32), func(): _set_mode(mi))
		b.key = m[0]; b.font_size = 12
		mode_btns.append(b)
	y += 39
	guard = W.Guard.new()
	guard.pressed.connect(_toggle_free)
	_add(guard, Vector2(x, y))
	free_txt = W.Txt.new("WEAPONS FREE", 18, W.PRI, false, 190)
	_add(free_txt, Vector2(x + 66, y + 10))
	free_sub = W.Txt.new("guard open · Space to safe", 10, W.MUTED, true, 190)
	_add(free_sub, Vector2(x + 66, y + 34))
	y += 64
	# target select
	tgt_hdr = W.Header.new("Target select", W.PRI, "TRK --", 260)
	_add(tgt_hdr, Vector2(x, y))
	y += 31
	tgt_scr = W.Screen.new("", Vector2(260, 26), W.PRI, 13)
	_add(tgt_scr, Vector2(x, y))
	y += 33
	var cw3 := (260.0 - 8) / 3
	for i in TARGETS.size():
		var pos := Vector2(x + (i % 3) * (cw3 + 4), y + (i / 3) * 44)
		var si: int = TARGETS[i][0]
		var b := _btn("cap", TARGETS[i][2], pos, Vector2(cw3, 40), func(): _pick_target(si))
		tgt_btns.append(b)
	y += 92
	var cw := (260.0 - 12) / 4
	# rotation / translation
	_add(W.Header.new("Rotation · translation", W.SEC, "", 260), Vector2(x, y))
	y += 31
	var helm := [["Q", "⟲ Roll", "roll"], ["W", "▲ Close", 1], ["E", "Roll ⟳", "roll"], ["X", "Match", 5],
		["A", "◀ Left", 3], ["S", "▼ Open", 2], ["D", "Right ▶", 4], ["T", "On tgt", "nose"]]
	for i in helm.size():
		var h: Array = helm[i]
		var act = h[2]
		var b := _btn("cap", h[1], Vector2(x + (i % 4) * (cw + 4), y + (i / 4) * 46), Vector2(cw, 42), func(): _helm(act))
		b.top = h[0]; b.font_size = 12
		helm_btns.append(b)
	y += 96
	drive_txt = W.Txt.new("", 10, W.MUTED, true, 180)
	_add(drive_txt, Vector2(x, y))
	thr_txt = W.Txt.new("", 10, W.TEXT, true, 80)
	thr_txt.align = HORIZONTAL_ALIGNMENT_RIGHT
	_add(thr_txt, Vector2(x + 180, y))
	y += 17
	thr_segs = W.Segs.new(20, Vector2(260, 10), W.PRI)
	thr_segs.clicked.connect(func(k: int): _set_throttle(maxf(0.1, (k + 1) / 20.0)))
	_add(thr_segs, Vector2(x, y))
	y += 18
	ignite = _btn("cap", "IGNITE", Vector2(x, y), Vector2(127, 42), _toggle_ignite)
	ignite.hazard = true; ignite.font_size = 16
	var dark := _locked("cap", "GO DARK", Vector2(x + 133, y), Vector2(127, 42))
	dark.sub = "cut drive · sink heat"; dark.font_size = 15

func _build_bottom() -> void:
	var y := 768.0
	_add(W.Txt.new("Δv REMAINING · M/S", 10, W.FAINT, true, 160), Vector2(324, y + 14))
	for i in 4:
		var d := W.Screen.new("0", Vector2(26, 38), W.PRI, 26)
		_add(d, Vector2(324 + i * 28, y + 33))
		dv_scr.append(d)
	fuel_txt = W.Txt.new("", 10, W.MUTED, true, 160)
	_add(fuel_txt, Vector2(324, y + 76))
	ball = W.Ball.new()
	_add(ball, Vector2(476, y + 6))
	_add(W.Txt.new("ATTITUDE · Y / P / R", 10, W.FAINT, true, 170), Vector2(604, y + 22))
	att_scr = W.Screen.new("", Vector2(150, 34), W.TEXT, 19)
	_add(att_scr, Vector2(604, y + 40))
	rwr_txt = W.Txt.new("", 10, W.MUTED, true, 190)
	_add(rwr_txt, Vector2(604, y + 80))
	var vw := (268.0 - 9) / 4
	var views := [["Own", "own"], ["Enemy", "enemy"], ["Chase", "chase"], ["Aim", ""], ["Real", "real"], ["Armor", "armor"], ["Eclipse", ""], ["IR view", ""]]
	for i in views.size():
		var pos := Vector2(836 + (i % 4) * (vw + 3), y + 24 + (i / 4) * 33)
		var v: String = views[i][1]
		var b: W.Btn
		if v == "":
			b = _locked("tab", views[i][0], pos, Vector2(vw, 30))
		else:
			b = _btn("tab", views[i][0], pos, Vector2(vw, 30), func(): _view(v))
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
	_add(W.Txt.new("HEAT", 18, W.HOT, false, 50), Vector2(x, y + 3))
	var ht := _btn("tab", "Thermal", Vector2(x + 50, y), Vector2(78, 26))
	ht.active = true; ht.font_size = 12
	var hs := _locked("tab", "Stealth", Vector2(x + 130, y), Vector2(78, 26))
	hs.font_size = 12
	heat_rate_txt = W.Txt.new("", 10, W.FAINT, true, 58)
	heat_rate_txt.align = HORIZONTAL_ALIGNMENT_RIGHT
	_add(heat_rate_txt, Vector2(x + 210, y + 7))
	y += 33
	ring = W.Ring.new()
	_add(ring, Vector2(x, y))
	var big := W.Txt.new("", 22, W.PRI, false, 180)
	_add(big, Vector2(x + 90, y + 2))
	heat_lines.append(big)
	for k in 3:
		var t := W.Txt.new("", 11, W.TEXT, true, 180)
		_add(t, Vector2(x + 90, y + 30 + k * 15))
		heat_lines.append(t)
	y += 86
	_add(W.Txt.new("RADIATORS", 10, W.MUTED, true, 100), Vector2(x, y))
	rad_txt = W.Txt.new("", 10, W.SEC, true, 168)
	rad_txt.align = HORIZONTAL_ALIGNMENT_RIGHT
	_add(rad_txt, Vector2(x + 100, y))
	y += 17
	for k in 2:
		var ext := k == 0
		var b := _btn("tab", ["Extend", "Stow"][k], Vector2(x + k * 135, y), Vector2(133, 26), func(): battle.set_radiators(ext))
		b.font_size = 12; b.accent = W.SEC
		rad_btns.append(b)
	y += 38
	# damage control checklist
	dc_hdr = W.Header.new("Damage ctrl", W.MUTED, "", 212)
	_add(dc_hdr, Vector2(x, y))
	auto_btn = _btn("tab", "Auto", Vector2(x + 216, y - 2), Vector2(52, 24), func(): battle.set_auto_repair(not bool(battle.get_ship(0)["auto_repair"])))
	auto_btn.font_size = 11; auto_btn.accent = W.SEC
	auto_btn.tooltip_text = "Auto: repair teams take the worst damage first.\nClick a line on the card to send a team yourself."
	y += 30
	paper = W.Paper.new(Vector2(268, 104))
	paper.line_clicked.connect(_on_dc_line)
	_add(paper, Vector2(x, y))
	y += 116
	# scope: EO only in the demo
	_add(W.Txt.new("SCOPE", 18, W.PRI, false, 70), Vector2(x, y + 4))
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
	eo.texture = eo_vp.get_texture()
	eo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	eo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eo.stretch_mode = TextureRect.STRETCH_SCALE
	eo.size = Vector2(240, 240)
	eo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(eo, Vector2(x + 14, y + 14))
	scope_rect = Rect2(x + 14, y + 14, 240, 240)
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
	scope_foot_l = W.Txt.new("EO TELESCOPE · 1.2 m", 10, W.MUTED, true, 160)
	_add(scope_foot_l, Vector2(x, y))
	scope_foot_r = W.Txt.new("", 10, W.SEC, true, 108)
	scope_foot_r.align = HORIZONTAL_ALIGNMENT_RIGHT
	_add(scope_foot_r, Vector2(x + 160, y))

# ------------------------------------------------------------------ orders

func _set_mode(mi: int) -> void:
	var own: Dictionary = battle.get_ship(0)
	preset_mode = mi == 1
	battle.set_fire_mode(0 if mi == 2 else 1, int(own["target_sys"]))
	if mi == 2: battle.set_target_turret(-1)

func _pick_target(si: int) -> void:
	# Picking a target in auto switches to manual, as on the prototype. Picking the lasers again steps through the
	# enemy's turrets that still work: any (fire control picks the exposed one) → 1 → 2 → 3 → any.
	var own: Dictionary = battle.get_ship(0)
	var again := int(own["fire_mode"]) == 1 and int(own["target_sys"]) == si
	if int(own["fire_mode"]) == 0:
		preset_mode = false
	battle.set_fire_mode(1, si)
	var next := -1
	if si == 1 and again:
		var thp: PackedFloat64Array = battle.get_ship(1)["turret_hp"]
		var cur: int = own["target_turret"]
		for step in range(1, 5):
			var cand := (cur + 1 + step) % 4 - 1        # cycles -1, 0, 1, 2
			if cand < 0 or thp[cand] > 0:
				next = cand
				break
	battle.set_target_turret(next)

func _toggle_free() -> void:
	battle.set_weapons_free(not bool(battle.get_ship(0)["weapons_free"]))

func _set_throttle(v: float) -> void:
	throttle = v
	var b := int(battle.get_ship(0)["burn"])
	if b != 0:
		battle.set_burn(b, throttle)

func _toggle_ignite() -> void:
	if int(battle.get_ship(0)["burn"]) != 0:
		battle.set_burn(0, throttle)
	else:
		battle.set_burn(sel_burn, throttle)

func _helm(act) -> void:
	if act is String:
		if act == "roll":
			battle.set_facing(0 if int(battle.get_ship(0)["facing"]) == 1 else 1)
		elif act == "nose":
			battle.set_facing(0)
	else:
		sel_burn = int(act)
		if int(battle.get_ship(0)["burn"]) != 0:
			battle.set_burn(sel_burn, throttle)

func _view(v: String) -> void:
	match v:
		"own": view_target = false
		"enemy": view_target = true
		"chase": chase = not chase
		"real": armor_view = false
		"armor": armor_view = true

func _on_dc_line(i: int) -> void:
	if i < dc_line_sys.size() and int(dc_line_sys[i]) >= 0:
		battle.order_repair(int(dc_line_sys[i]))

# ------------------------------------------------------------------ HUD update

func _own_name() -> String:
	if battle == null: return "Dagger"
	return "ESF " + str(battle.get_ship(0)["name"])

func _own_class() -> String:
	if battle == null: return ""
	return ["LASER CRUISER", "COILGUN CRUISER", "FRIGATE"][ship_class] + " · EARTH"

func _foe_name() -> String:
	return "MRS " + str(battle.get_ship(1)["name"]).to_upper().replace("MARS ", "")

func _update_hud() -> void:
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	var health: PackedFloat64Array = own["health"]
	var fh: PackedFloat64Array = foe["health"]
	var q: float = battle.get_sensor_quality()
	var known := q > 0.3
	var t: float = battle.get_time()
	nameplate.queue_redraw()
	cond_badge.queue_redraw()
	overlay.queue_redraw()
	clock_scr.set_text("%03d:%02d:%02d" % [int(t) / 3600, (int(t) / 60) % 60, int(t) % 60])
	for i in speed_btns.size():
		(speed_btns[i] as W.Btn).set_state(i == battle.get_speed())
	var cruise_b: W.Btn = speed_btns[6]
	if cruise_b.locked == battle.get_cruise_allowed():
		cruise_b.locked = not battle.get_cruise_allowed()
		cruise_b.queue_redraw()
	drop_txt.set_text(str(battle.get_drop_reason()).to_upper())

	# armament: row 0 the gun, row 1 the laser
	var gun: int = own["gun"]
	var r0: Array = arm_rows[0]
	var gb: W.Btn = r0[0]
	if gun == 0:
		gb.locked = true
		gb.text = "SAFE"
		(r0[1] as W.Flag).set_on(false)
		(r0[2] as W.Txt).set_text("No gun fitted", W.FAINT)
		(r0[3] as W.Txt).set_text("Lance only", W.FAINT)
		(r0[4] as W.Screen).set_text("--", W.FAINT)
		gb.queue_redraw()
	else:
		var armed: bool = own["gun_armed"]
		gb.set_state(armed)
		gb.set_text("ARM" if armed else "SAFE")
		(r0[1] as W.Flag).set_on(armed)
		var gh := health[2]
		var name := "Spinal coilgun" if gun == 2 else "Railgun"
		(r0[2] as W.Txt).set_text(name, (W.PRI if armed else W.MUTED) if gh > 0 else W.HOT)
		var cd: float = own["gun_cooldown"]
		var sub := ""
		if gh <= 0: sub = "DESTROYED"
		elif cd > 0: sub = "RLD %02d s" % int(ceil(cd))
		elif battle.get_hit_chance() > 0: sub = "RDY · ▸ %s · %d%%" % [SYS_ABBR[int(own["target_sys"])], int(battle.get_hit_chance() * 100)]
		else: sub = "RDY · no arc/range"
		(r0[3] as W.Txt).set_text(sub, W.HOT if gh <= 0 else W.MUTED)
		(r0[4] as W.Screen).set_text("%02d" % int(own["ammo"]), W.PRI if armed else W.MUTED)
		gb.queue_redraw()
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
		(row[2] as W.Txt).set_text("Laser %d" % (k + 1), col)
		var st := "SAFE"
		if hp_k <= 0: st = "DESTROYED"
		elif bool(own["overheated"]) and armed_k: st = "LOCKOUT · HEAT"
		elif tfire[k]: st = "FIRING ▸ %s" % SYS_ABBR[int(own["target_sys"])]
		elif armed_k and not tbear[k]: st = "NO ARC · hull blocks"
		elif armed_k: st = "RDY · ⅓ power"
		(row[3] as W.Txt).set_text(st, W.HOT if hp_k <= 0 or st.begins_with("LOCKOUT") else W.MUTED)
		(row[4] as W.Screen).set_text("%d" % int(hp_k), W.hp(hp_k) if hp_k > 0 else W.HOT)

	# fire mode
	var mode: int = own["fire_mode"]
	var ui_mode := 2 if mode == 0 else (1 if preset_mode else 0)
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
	var tname: String = SYS_NAMES[ts].to_upper() + ((" %d" % (tt + 1)) if ts == 1 and tt >= 0 else "")
	var tval := fthp[tt] if ts == 1 and tt >= 0 else fh[ts]
	tgt_scr.set_text("%s|▸ %s|%s" % [_foe_name().replace("MRS ", ""), tname, ("%d%%" % int(tval)) if known else "??"])
	for i in TARGETS.size():
		var b: W.Btn = tgt_btns[i]
		var si: int = TARGETS[i][0]
		var hv: float = fh[si]
		var v := ("%d" % int(hv)) if known else "??"
		if si == 1 and ts == 1 and int(own["fire_mode"]) == 1:
			v = ("ANY" if tt < 0 else "#%d" % (tt + 1)) + ((" · %d" % int(fthp[tt] if tt >= 0 else hv)) if known else "")
		if preset_mode:
			b.set_text(TARGETS[i][3], TARGETS[i][2])
		else:
			b.set_text(TARGETS[i][2], v)
		b.set_state(si == ts)
		var dash := not known
		if b.dashed != dash:
			b.dashed = dash
			b.modulate.a = 0.45 if dash else 1.0
			b.queue_redraw()

	# helm and drive
	var facing: int = own["facing"]
	var burn: int = own["burn"]
	var helm_act := [-1, 1, -1, 5, 3, 2, 4, -2]
	for i in helm_btns.size():
		var a: int = helm_act[i]
		var on := false
		if a == -1: on = facing == 1
		elif a == -2: on = facing == 0
		else: on = a == (burn if burn != 0 else sel_burn)
		(helm_btns[i] as W.Btn).set_state(on)
	var oms_on := (own["oms"] as Vector2).length() > 0.01
	if own["burning"]: drive_txt.set_text("MAIN DRIVE · BURNING", W.PRI)
	elif oms_on: drive_txt.set_text("OMS PODS · FIRING", W.SEC)
	else: drive_txt.set_text("MAIN DRIVE · IDLE", W.MUTED)
	thr_txt.set_text("THR %d%%" % int(round(throttle * 100)))
	thr_segs.set_on(int(round(throttle * 20)), W.PRI if burn != 0 else W.KEY_LINE)
	ignite.set_text("CUT DRIVE" if burn != 0 else "IGNITE")
	ignite.accent = W.HOT if burn != 0 else W.PRI

	# Δv and attitude
	var dv: float = own["dv_left"]
	var dv_s := "%04d" % clampi(int(dv), 0, 9999)
	for i in 4:
		(dv_scr[i] as W.Screen).set_text(dv_s[i], W.PRI if dv > 0.2 * float(own["dv_max"]) else W.HOT)
	fuel_txt.set_text("PROPELLANT %d%%" % int(100.0 * dv / maxf(1.0, float(own["dv_max"]))))
	var rel: Vector2 = Vector2(foe["pos"]) - Vector2(own["pos"])
	var brg := rel.angle()
	var off := rad_to_deg(wrapf(brg - float(own["heading"]), -PI, PI))
	ball.set_att(roll_angle, off)
	var hdg := int(round(rad_to_deg(wrapf(float(own["heading"]), 0, TAU)))) % 360
	att_scr.set_text("%03d %+03d %+04d" % [hdg, 0, int(rad_to_deg(roll_angle))])
	if foe["laser_firing"]:
		rwr_txt.set_text("LASER WARNING · UNDER FIRE", W.HOT)
	else:
		rwr_txt.set_text("TGT BRG %03d · OFF NOSE %+d°" % [int(round(rad_to_deg(wrapf(brg, 0, TAU)))) % 360, int(off)], W.MUTED)
	var vstate := [not view_target, view_target, chase, false, not armor_view, armor_view, false, false]
	for i in view_btns.size():
		(view_btns[i] as W.Btn).set_state(vstate[i])

	# caution / warning
	var heat: float = own["heat"]
	var incoming := false
	for s in battle.get_shots():
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
	heat_rate_txt.set_text("%+.1f/s" % heat_rate, W.HOT if heat_rate > 0.3 else W.FAINT)
	var big: W.Txt = heat_lines[0]
	if bool(own["overheated"]):
		big.set_text("LOCKOUT", W.HOT)
	elif heat_rate > 0.05:
		var s := (100.0 - heat) / heat_rate
		big.set_text("%d:%02d to lockout" % [int(s) / 60, int(s) % 60], W.PRI)
	else:
		big.set_text("STABLE", W.SEC)
	(heat_lines[1] as W.Txt).set_text("Heat %d / 100" % int(heat))
	(heat_lines[2] as W.Txt).set_text("Weapons lock at 100" if not bool(own["overheated"]) else "Locked until below 70", W.TEXT if not bool(own["overheated"]) else W.HOT)
	(heat_lines[3] as W.Txt).set_text("Laser & drive add heat", W.MUTED)
	var ext: bool = own["radiators_extended"]
	rad_txt.set_text("EXTENDED · fast cooling" if ext else "STOWED · safe from hits", W.SEC if ext else W.PRI)
	(rad_btns[0] as W.Btn).set_state(ext)
	(rad_btns[1] as W.Btn).set_state(not ext)

	# damage control card
	var teams: int = own["teams"]
	dc_hdr.set_hint("TEAMS %d/%d" % [teams - reps.size(), teams])
	auto_btn.set_state(own["auto_repair"])
	var pl: Array = []
	dc_line_sys.clear()
	var busy := {}
	# The laser is judged by its worst turret: that is the one a team works on.
	var worst_t := 0
	for k in 3:
		if thp[k] < thp[worst_t]: worst_t = k
	var need := health.duplicate()
	need[1] = thp[worst_t]
	var dc_name := SYS_NAMES.duplicate()
	dc_name[1] = "Laser %d" % (worst_t + 1)
	for r in reps:
		busy[int(r["sys"])] = true
		pl.append(["☐", "REPAIR %s" % str(dc_name[int(r["sys"])]).to_upper(), "%d s" % int(ceil(float(r["left"]))), W.INK])
		dc_line_sys.append(-1)
	var dmg: Array = []
	for i in 6:
		if i == 2 and gun == 0: continue
		if need[i] < 100 and not busy.has(i): dmg.append(i)
	dmg.sort_custom(func(a, b): return need[a] < need[b])
	for i in dmg:
		if pl.size() >= 5: break
		var hv: float = need[i]
		pl.append(["⚠" if hv < 45 else "▸", "%s %d%%  ▸ FIX" % [str(dc_name[i]).to_upper(), int(hv)], "", W.INK_HOT if hv < 45 else W.INK])
		dc_line_sys.append(i)
	if pl.is_empty():
		pl.append(["☒", "ALL SYSTEMS NOMINAL", "", W.INK])
		dc_line_sys.append(-1)
	for k in range(log_lines.size() - 1, -1, -1):
		if pl.size() >= 5: break
		var l: Array = log_lines[k]
		var txt: String = str(l[0]).to_upper()
		if txt.length() > 24: txt = txt.substr(0, 23) + "…"
		pl.append(["☒", txt, l[1], W.INK_DIM])
		dc_line_sys.append(-1)
	paper.set_lines(pl)

	# scope
	eo_label_t1 = "EO · VIS · TRK %d%%" % int(q * 100)
	eo_label_t2 = "components resolved" if q > 0.5 else ("outline only" if q > 0.25 else "point source")
	scope_over.queue_redraw()
	scope_foot_r.set_text("TRACK %d%%" % int(q * 100))

func _draw_overlay(c: Control) -> void:
	if battle == null: return
	var own: Dictionary = battle.get_ship(0)
	var foe: Dictionary = battle.get_ship(1)
	var q: float = battle.get_sensor_quality()
	var known := q > 0.3
	# mask the cut corners and draw the frame
	c.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(22, 0), Vector2(0, 22)]), W.BG)
	c.draw_colored_polygon(PackedVector2Array([Vector2(804, 662), Vector2(804, 684), Vector2(782, 684)]), W.BG)
	c.draw_polyline(PackedVector2Array([Vector2(22.5, 0.5), Vector2(803.5, 0.5), Vector2(803.5, 661.5), Vector2(781.5, 683.5), Vector2(0.5, 683.5), Vector2(0.5, 22.5), Vector2(22.5, 0.5)]), W.LINE, 1.5)
	c.draw_line(Vector2(22, 1), Vector2(120, 1), W.PRI, 3)
	c.draw_line(Vector2(1, 22), Vector2(1, 120), W.PRI, 3)
	c.draw_line(Vector2(803, 562), Vector2(803, 683), W.PRI, 3)
	c.draw_line(Vector2(782, 683), Vector2(684, 683), W.PRI, 3)
	# titles
	var title := ("TGT-1 · %s · EO RECON" % _foe_name()) if view_target else ("OWN SHIP · %s" % ("ARMOR CONDITION" if armor_view else "REAL COLOR · SUNLIT"))
	c.draw_string(W.FH, Vector2(40, 38), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, W.TEXT)
	var sub := ("click a part to target it" if battle.get_sensor_quality() > 0.3 else "EO can't resolve parts yet: close the range") if view_target else "right-drag to orbit · wheel to zoom · C chase cam · Tab enemy view"
	c.draw_string(W.FM, Vector2(40, 56), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, W.MUTED)
	var health: PackedFloat64Array = own["health"]
	var fh: PackedFloat64Array = foe["health"]
	if not view_target:
		# target bracket: where the enemy is, clamped to the view edge when off screen
		if cam.position.is_zero_approx(): return
		var fp := foe_model.position
		var p := cam.unproject_position(fp)
		var behind := cam.is_position_behind(fp)
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
		W.text_c(c, W.FH, "TGT-1 · %s%s" % [_foe_name(), "  · OFF VIEW" if clamped else ""], p + Vector2(0, 38), 17, col)
		bracket_pos = p
		W.text_c(c, W.FM, "%.1f km · closing %.2f km/s" % [battle.get_range_km(), battle.get_closing() / 1000.0], p + Vector2(0, 54), 11, W.MUTED)
		# callout: our most damaged system
		var worst := -1
		for i in 6:
			if i == 2 and int(own["gun"]) == 0: continue
			if health[i] < 100 and (worst < 0 or health[i] < health[worst]): worst = i
		if worst >= 0 and not cam.is_position_behind(own_model.sys_position(worst)):
			_callout(c, cam.unproject_position(own_model.sys_position(worst)), "%s · %d%%" % [SYS_NAMES[worst].to_upper(), int(health[worst])], W.hp(health[worst]))
	else:
		var ts: int = own["target_sys"]
		var tt: int = own["target_turret"]
		var fthp: PackedFloat64Array = foe["turret_hp"]
		# clickable component markers, once the EO can resolve the parts
		pick_points.clear()
		if known:
			for pp in _foe_components():
				if cam.is_position_behind(pp[0]): continue
				var sp := cam.unproject_position(pp[0])
				pick_points.append([sp, pp[1], pp[2], pp[3]])
				var sel: bool = int(pp[1]) == ts and (int(pp[2]) < 0 or tt < 0 or int(pp[2]) == tt)
				var mc := W.PRI if sel else W.SEC
				c.draw_arc(sp, 9, 0, TAU, 20, Color(mc, 0.9), 1.5)
				c.draw_string(W.FM, sp + Vector2(12, -6), pp[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(mc, 0.9))
		var tpos: Vector3 = foe_model.turret_position(tt) if ts == 1 and tt >= 0 else foe_model.sys_position(ts)
		var tval: float = fthp[tt] if ts == 1 and tt >= 0 else fh[ts]
		var tlab: String = SYS_NAMES[ts].to_upper() + ((" %d" % (tt + 1)) if ts == 1 and tt >= 0 else "")
		if not cam.is_position_behind(tpos):
			_callout(c, cam.unproject_position(tpos), "%s · %s" % [tlab, ("%d%%" % int(tval)) if known else "??"], W.PRI)
		# resolved components panel
		var pr := Rect2(40, 80, 210, 30 + 6 * 18)
		c.draw_rect(pr, W.PANEL)
		c.draw_rect(Rect2(pr.position + Vector2(0.5, 0.5), pr.size - Vector2(1, 1)), W.LINE, false, 1.0)
		c.draw_string(W.FH, pr.position + Vector2(10, 20), "RESOLVED COMPONENTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, W.MUTED)
		for i in 6:
			var yy := pr.position.y + 40 + i * 18
			var res := q > 0.25 + i * 0.05
			var nm: String = str(SYS_NAMES[i]).to_upper()
			c.draw_string(W.FM, Vector2(pr.position.x + 10, yy), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, W.TEXT if res else W.FAINT)
			var v := ("%d%%" % int(fh[i])) if res else "??"
			var vw := W.FM.get_string_size(v, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			c.draw_string(W.FM, Vector2(pr.end.x - 10 - vw, yy), v, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, W.hp(fh[i]) if res else W.FAINT)

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
	menu = _overlay()
	var v := VBoxContainer.new()
	v.position = Vector2(520, 170)
	v.size = Vector2(400, 580)
	v.add_theme_constant_override("separation", 14)
	menu.add_child(v)
	var t := UI.label("TDC", 64, UI.PRI)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := UI.label("Earth and Mars, 2300. One battle above Mars.", 15, UI.MUTED)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	v.add_child(UI.header("Choose your ship"))
	v.add_child(UI.button("Dagger · laser cruiser", func(): _start(0), UI.PRI, 400))
	v.add_child(UI.button("Lance · laser + spinal coilgun", func(): _start(1), UI.PRI, 400))
	v.add_child(UI.button("Watch an AI battle", _watch_ai, UI.SEC, 400))
	v.add_child(UI.header("Coming soon", UI.FAINT))
	v.add_child(UI.locked("Ship designer", 400))
	v.add_child(UI.locked("Fleet battles · missiles · EW · sensors", 400))
	v.add_child(UI.button("Support development on Patreon", _open_patreon, UI.HOT, 400))
	v.add_child(UI.button("Quit", func(): get_tree().quit(), UI.MUTED, 400))
	var keys := UI.label("Space weapons safe/free · P pause · , . time · Q/E roll · T nose on · WASD/X burn direction · I ignite · F1-F3 fire mode · Tab enemy view · C chase cam · Right-drag orbit · Wheel zoom · M mute · Click an enemy part to target it · Esc menu", 12, UI.FAINT)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys.custom_minimum_size.x = 400
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
		var l := UI.label(s, 16, UI.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	v.add_child(UI.button("Fight again", func(): _start(ship_class), UI.PRI, 500))
	v.add_child(UI.button("Main menu", func(): _show_menu(), UI.SEC, 500))
	v.add_child(UI.button("Support development on Patreon", _open_patreon, UI.HOT, 500))

func _watch_ai() -> void:
	_start(1)
	battle.set_player_ai(true)

func _open_patreon() -> void:
	if PATREON_URL != "":
		OS.shell_open(PATREON_URL)

# ------------------------------------------------------------------ input

## Click an enemy component in the enemy view or on the EO scope to target it; click the target bracket to look at it.
func _click_target(p: Vector2) -> bool:
	if battle == null or state != "battle": return false
	if VP.has_point(p):
		var local := p - VP.position
		if not view_target:
			if bracket_pos.distance_to(local) < 40: view_target = true; return true
			return false
		return _pick_near(local, pick_points)
	if scope_rect.has_point(p) and battle.get_sensor_quality() > 0.3:
		var res := float(eo_vp.size.x)
		var pts: Array = []
		for pp in _foe_components():
			if eo_cam.is_position_behind(pp[0]): continue
			pts.append([eo_cam.unproject_position(pp[0]) * (240.0 / res), pp[1], pp[2], pp[3]])
		return _pick_near(p - scope_rect.position, pts)
	return false

func _pick_near(p: Vector2, pts: Array) -> bool:
	var best: Array = []
	var bd := 45.0
	for pp in pts:
		var d: float = (pp[0] as Vector2).distance_to(p)
		if d < bd: bd = d; best = pp
	if best.is_empty(): return false
	_pick_target(best[1])
	return true

## The enemy's targetable parts in world space: [position, system, turret, label]
func _foe_components() -> Array:
	var out: Array = []
	for i in TARGETS.size():
		var si: int = TARGETS[i][0]
		var tk: int = TARGETS[i][1]
		if si == 2 and int(battle.get_ship(1)["gun"]) == 0: continue
		var pos: Vector3 = foe_model.sys_position(si)
		var lab: String = TARGETS[i][2]
		if si == 1:
			# one marker for the lasers, on the picked turret, or the one fire control would hit (faces us), or any live one
			var foe: Dictionary = battle.get_ship(1)
			var fthp: PackedFloat64Array = foe["turret_hp"]
			var want: int = battle.get_ship(0)["target_turret"]
			if want < 0:
				var bears: Array = foe["turret_bears"]
				for k in 3:
					if fthp[k] > 0 and bears[k]: want = k; break
				if want < 0:
					for k in 3:
						if fthp[k] > 0: want = k; break
			if want >= 0:
				pos = foe_model.turret_position(want)
				lab = "LSR %d" % (want + 1) if int(battle.get_ship(0)["target_turret"]) >= 0 else "LSR"
		out.append([pos, si, tk, lab])
	return out

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _click_target(e.position):
		return
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE: dragging = e.pressed
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP: dist = max(60.0, dist * 0.88)
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN: dist = min(5000.0, dist / 0.88)
	elif e is InputEventMouseMotion and dragging:
		yaw -= e.relative.x * 0.006
		pitch = clamp(pitch + e.relative.y * 0.006, -1.4, 1.4)
	elif e is InputEventKey and e.pressed and not e.echo and state == "battle":
		match e.keycode:
			KEY_SPACE: _toggle_free()
			KEY_P: battle.set_speed(0 if battle.get_speed() != 0 else 2)
			KEY_PERIOD: battle.set_speed(battle.get_speed() + 1)
			KEY_COMMA: battle.set_speed(max(1, battle.get_speed() - 1))
			KEY_TAB: view_target = not view_target
			KEY_C: chase = not chase
			KEY_Q, KEY_E: _helm("roll")
			KEY_T: _helm("nose")
			KEY_W: _helm(1)
			KEY_S: _helm(2)
			KEY_A: _helm(3)
			KEY_D: _helm(4)
			KEY_X: _helm(5)
			KEY_I, KEY_ENTER: _toggle_ignite()
			KEY_F1: _set_mode(0)
			KEY_F2: _set_mode(1)
			KEY_F3: _set_mode(2)
			KEY_ESCAPE: _show_menu()
			KEY_M: sfx.muted = not sfx.muted
